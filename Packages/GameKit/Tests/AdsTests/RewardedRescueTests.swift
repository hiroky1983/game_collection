import Foundation
import SwiftUI
import Testing
@testable import Core

/// 何も残さない中断データ置き場。`GameServices` を組み立てるためだけに使う。
private final class NullSnapshotStore: SnapshotStore {
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {}
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? { nil }
    func clear(for gameID: String) {}
    func exists(for gameID: String) -> Bool { false }
}

/// 視聴完了 / 未完了を指定でき、出した本数を数える広告。
@MainActor
private final class CountingAdService: AdService {
    let earnsReward: Bool
    private(set) var shownCount = 0

    init(earnsReward: Bool) { self.earnsReward = earnsReward }

    func makeBannerView(width: CGFloat) -> AnyView? { nil }
    func showInterstitial() async {}
    func showRewardedAd() async -> Bool {
        shownCount += 1
        return earnsReward
    }
}

@MainActor
private func makeServices(earnsReward: Bool) -> (GameServices, CountingAdService) {
    let ads = CountingAdService(earnsReward: earnsReward)
    return (GameServices(snapshots: NullSnapshotStore(), ads: ads), ads)
}

/// `RewardedRescue` が中で立てた `Task` が終わるまで待つ。
///
/// **実時間は待たない**（実時間の待ち合わせは並列実行で落ちる）。スタブの広告は
/// 中断点を持たないので、MainActor のジョブが一巡すれば必ず走り切っている。
@MainActor
private func settle() async {
    for _ in 0..<10 { await Task.yield() }
}

@Suite("リワード救済の共通段取り（#526）")
@MainActor
struct RewardedRescueTests {

    @Test("視聴完了したときだけ報酬を適用する")
    func grantsOnlyWhenEarned() async {
        let (earnedServices, _) = makeServices(earnsReward: true)
        let earned = RewardedRescue()
        var grantedCount = 0
        earned.request(earnedServices, gameID: "solitaire", purpose: .undo, guardedBy: .checkedByGrant) {
            grantedCount += 1
            return true
        }
        await settle()
        #expect(grantedCount == 1)
        #expect(earned.showsNotEarned == false)
        #expect(earned.showsUnavailable == false)

        let (skippedServices, _) = makeServices(earnsReward: false)
        let skipped = RewardedRescue()
        var skippedGrantCount = 0
        skipped.request(skippedServices, gameID: "solitaire", purpose: .undo, guardedBy: .checkedByGrant) {
            skippedGrantCount += 1
            return true
        }
        await settle()
        #expect(skippedGrantCount == 0, "見なかったのに報酬を適用している")
        #expect(skipped.showsNotEarned, "見なかったことを知らせていない")
    }

    @Test("視聴は完了したのに適用できなかったときは、局面が変わった旨のアラートを立てる")
    func raisesUnavailableWhenGrantFails() async {
        let (services, _) = makeServices(earnsReward: true)
        let rescue = RewardedRescue()
        // 局ガードが弾いた状況（広告のロード中に配り直された等）を grant の戻り値で表す。
        rescue.request(services, gameID: "solitaire", purpose: .joker, guardedBy: .checkedByGrant) { false }
        await settle()
        #expect(rescue.showsUnavailable, "対価だけ払って何も起きない経路が残っている")
        #expect(rescue.showsNotEarned == false, "視聴はできているので「見なかった」ではない")
    }

    @Test("視聴中の連打では2本目の広告を出さない")
    func ignoresReentrantRequestsWhileWatching() async {
        let (services, ads) = makeServices(earnsReward: true)
        let rescue = RewardedRescue()
        var grantedCount = 0
        func show() {
            rescue.request(services, gameID: "solitaire", purpose: .undo, guardedBy: .checkedByGrant) {
                grantedCount += 1
                return true
            }
        }

        // Task が走り出す前に押し直す = 実機の連打と同じ状況。
        show()
        show()
        show()
        await settle()

        #expect(ads.shownCount == 1, "連打のぶんだけ広告を出している")
        #expect(grantedCount == 1, "1 本の視聴で報酬が複数回入っている")
    }

    @Test("視聴が終われば次の要求を受け付ける")
    func acceptsTheNextRequestAfterFinishing() async {
        let (services, ads) = makeServices(earnsReward: true)
        let rescue = RewardedRescue()
        rescue.request(services, gameID: "solitaire", purpose: .undo, guardedBy: .checkedByGrant) { true }
        await settle()
        #expect(rescue.isWatching == false)

        rescue.request(services, gameID: "solitaire", purpose: .undo, guardedBy: .checkedByGrant) { true }
        await settle()
        #expect(ads.shownCount == 2)
    }

    @Test("見なかったときの後始末（whenNotEarned）はアラートと一緒に走る")
    func runsWhenNotEarnedHook() async {
        let (services, _) = makeServices(earnsReward: false)
        let rescue = RewardedRescue()
        var restored = false
        rescue.request(
            services, gameID: "concentration", purpose: .undo,
            guardedBy: .unchecked(note: "テスト"),
            whenNotEarned: { restored = true }
        ) { true }
        await settle()
        #expect(restored, "止めた進行を戻す後始末が走っていない")
        #expect(rescue.showsNotEarned)
    }

    @Test("見たときは後始末を走らせない")
    func skipsTheHookWhenEarned() async {
        let (services, _) = makeServices(earnsReward: true)
        let rescue = RewardedRescue()
        var restored = false
        rescue.request(
            services, gameID: "concentration", purpose: .undo,
            guardedBy: .unchecked(note: "テスト"),
            whenNotEarned: { restored = true }
        ) { true }
        await settle()
        #expect(restored == false)
    }

    // MARK: - モデルが広告ごと持っている面（チップ切れ復活・トビ復活）

    @Test("モデル側で失敗したときだけアラートを立て、続きは連打ガードを解いてから走る")
    func modelHandledFlowReportsFailureAndRunsFollowUp() async {
        let rescue = RewardedRescue()
        var followUpRan = false
        var watchingDuringFollowUp: Bool?
        rescue.requestHandledByModel {
            true
        } whenGranted: {
            followUpRan = true
            watchingDuringFollowUp = rescue.isWatching
        }
        await settle()
        #expect(followUpRan)
        #expect(watchingDuringFollowUp == false, "続きのあいだボタンを塞いだままになっている")
        #expect(rescue.showsNotEarned == false)

        let failing = RewardedRescue()
        var followUpAfterFailure = false
        failing.requestHandledByModel { false } whenGranted: { followUpAfterFailure = true }
        await settle()
        #expect(failing.showsNotEarned, "モデルが false を返したのに知らせていない")
        #expect(followUpAfterFailure == false, "適用できていないのに続きを走らせている")
    }

    @Test("モデル側の面でも視聴中の連打を塞ぐ")
    func modelHandledFlowGuardsReentrancy() async {
        let rescue = RewardedRescue()
        var performed = 0
        func show() { rescue.requestHandledByModel { performed += 1; return true } }
        show()
        show()
        await settle()
        #expect(performed == 1)
    }
}

/// 局ガードの宣言（`RewardGuard`）をソース走査で固定する（#526）。
///
/// `RewardedRescue.request` は `guardedBy` を省略できないので、新しい救済を足すときに
/// 照合の有無を必ず選ぶことになる。ただし**選び方まではコンパイラが縛れない**ので、
/// 照合しない側（`unchecked`）を選んだ面はここで名指しで固定する。増えたらこのテストが赤くなり、
/// 「なぜ照合しないのか」をレビューで問われる。
@Suite("局ガードの宣言（#526）")
struct RewardGuardCallSiteTests {

    private static let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // AdsTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // GameKit
        .appendingPathComponent("Sources")

    private static func gameSources() throws -> [(path: String, text: String)] {
        try FileManager.default
            .subpathsOfDirectory(atPath: sourcesRoot.path)
            .filter { $0.hasSuffix(".swift") }
            // Core は共通 API の実装そのものなので対象外。
            .filter { !$0.hasPrefix("Core/") }
            .map { ($0, try String(contentsOf: sourcesRoot.appendingPathComponent($0), encoding: .utf8)) }
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    @Test("救済の入口はすべて局ガードを宣言している")
    func everyRescueDeclaresItsGuard() throws {
        let sources = try Self.gameSources()
        #expect(sources.count > 20, "走査対象が見つからない（パスの導出が壊れている可能性）")

        let requests = sources.reduce(0) { $0 + Self.occurrences(of: "Rescue.request(", in: $1.text) }
        let guards = sources.reduce(0) { $0 + Self.occurrences(of: "guardedBy: .", in: $1.text) }
        #expect(requests == 18, "救済の入口は18面（`requestHandledByModel` の3面を除く）")
        #expect(requests == guards,
                "`RewardedRescue.request` の呼び出しと `guardedBy` の数が合わない（\(requests) 対 \(guards)）")
    }

    @Test("照合していない面は名指しで固定する")
    func uncheckedSitesArePinned() throws {
        let sources = try Self.gameSources()
        let unchecked = sources
            .map { (path: $0.path, count: Self.occurrences(of: "guardedBy: .unchecked(", in: $0.text)) }
            .filter { $0.count > 0 }
            .sorted { $0.path < $1.path }

        // 局の通し番号を持たない10面。#526 の共通化では挙動を変えていない
        // （照合を足すのは各ゲームのモデルに通し番号を入れる別の作業）。
        #expect(unchecked.map(\.path) == [
            "Game2048/Game2048View.swift",
            "GameBlockPuzzle/BlockPuzzleView.swift",
            "GameChess/ChessView.swift",
            "GameConcentration/ConcentrationView.swift",
            "GameGo/GoView.swift",
            "GameGomoku/GomokuView.swift",
            "GameMinesweeper/MinesweeperView.swift",
            "GameOthello/OthelloView.swift",
            "GameShogi/ShogiView.swift",
            "GameSudoku/SudokuView.swift",
        ])
        #expect(unchecked.reduce(0) { $0 + $1.count } == 10)
    }

    @Test("照合すると宣言した面には、適用できなかったときのアラートが必ずある")
    func checkedSitesAlwaysProvideTheUnavailableAlert() throws {
        // `checkedByGrant` は「grant が false を返しうる」という宣言なので、
        // `rewardedRescueAlerts(unavailable:)` を渡し忘れると失敗が**完全に無言**になる
        // （`showsUnavailable` は立つが、渡していない側は `.constant(false)` で出ない）。
        // 対価だけ払って何も起きない状態は広告の契約違反なので、ファイル単位で数を突き合わせる。
        let mismatched = try Self.gameSources()
            .map { (
                path: $0.path,
                checked: Self.occurrences(of: "guardedBy: .checkedByGrant", in: $0.text),
                alerts: Self.occurrences(of: "unavailable: RewardUnavailableAlert(", in: $0.text)
            ) }
            .filter { $0.checked != $0.alerts }
            .map { "\($0.path): checkedByGrant \($0.checked) 件に対しアラート \($0.alerts) 件" }
        #expect(mismatched.isEmpty, "\(mismatched)")
    }

    @Test("救済は共通 API を迂回して広告を出さない")
    func nobodyBypassesTheSharedEntryPoint() throws {
        // `RewardedRescue` を通さずに `services.showRewardedAd(...)` を直に呼ぶと、
        // 連打ガードも局ガードも失敗アラートも付かない面が 1 つだけ生まれる。
        // モデルが広告ごと持っている3面（`requestHandledByModel` 側）だけが直に呼んでよい。
        let callers = try Self.gameSources()
            .filter { $0.text.contains("showRewardedAd(") }
            .map(\.path)
            .sorted()
        #expect(callers == [
            "GameBlackjack/BlackjackModel.swift",
            "GameMahjong/MahjongModel.swift",
            "GamePoker/PokerModel.swift",
        ], "共通 API を迂回した広告の呼び出しがある: \(callers)")
    }

    @Test("視聴できなかったときの文言はゲーム側に散らばっていない")
    func theSharedWordingLivesInExactlyOnePlace() throws {
        let sources = try Self.gameSources()
        let offenders = sources
            .filter { $0.text.contains("広告を最後まで視聴しなかったか") }
            .map(\.path)
        #expect(offenders.isEmpty,
                "`RewardedRescue.notEarnedMessage` を使わず文言を書いている: \(offenders)")
    }
}
