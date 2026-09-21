import Foundation
import SwiftUI
import Testing
import GameKitTestSupport
@testable import Core

/// 何も残さない中断データ置き場。`GameServices` を組み立てるためだけに使う。
private final class NullSnapshotStore: SnapshotStore {
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {}
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? { nil }
    func clear(for gameID: String) {}
    func exists(for gameID: String) -> Bool { false }
}

/// 視聴完了 / 未完了を指定でき、出した本数を数える広告。
///
/// `duringAd` を渡すと、視聴のあいだに起きたこと（ハブへ戻る等）を差し込める。
@MainActor
private final class CountingAdService: AdService {
    let earnsReward: Bool
    private(set) var shownCount = 0
    var duringAd: (@MainActor () -> Void)?

    init(earnsReward: Bool) { self.earnsReward = earnsReward }

    func makeBannerView(width: CGFloat) -> AnyView? { nil }
    func showInterstitial() async {}
    func showRewardedAd() async -> Bool {
        shownCount += 1
        duringAd?()
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

    // MARK: - 画面の世代（#653）

    @Test("広告を見ているあいだにハブへ戻ったら報酬を適用しない")
    func skipsTheGrantAfterLeavingTheScreen() async {
        let (services, ads) = makeServices(earnsReward: true)
        let rescue = RewardedRescue()
        // 広告のロード〜視聴のあいだも画面は操作できる。ここでハブへ戻られると Model は
        // 捨てられ、次に開いたときには別の Model が動いている。
        ads.duringAd = { services.gameDidLeave(gameID: "solitaire") }
        var grantedCount = 0
        rescue.request(services, gameID: "solitaire", purpose: .undo, guardedBy: .checkedByGrant) {
            grantedCount += 1
            return true
        }
        await settle()

        #expect(ads.shownCount == 1, "広告そのものは出ている（計測は従来どおり付く）")
        #expect(grantedCount == 0, "捨てられた Model に報酬を適用している")
        #expect(rescue.showsUnavailable == false, "もう無い画面に向けてアラートを立てている")
        #expect(rescue.showsNotEarned == false, "視聴はできているので「見なかった」ではない")
        #expect(rescue.isWatching == false, "連打ガードが解かれていない")
    }

    @Test("画面に留まっていれば従来どおり適用する（世代の照合が常時塞いでいない）")
    func grantsWhileStayingOnTheScreen() async {
        let (services, _) = makeServices(earnsReward: true)
        let rescue = RewardedRescue()
        // 別のゲームを離れても、この救済の世代は進む（世代は画面ごとではなく 1 本）。
        // 先に進めてから要求する = 救済が始まったあとに動いていないので適用される。
        services.gameDidLeave(gameID: "2048")
        var grantedCount = 0
        rescue.request(services, gameID: "solitaire", purpose: .undo, guardedBy: .checkedByGrant) {
            grantedCount += 1
            return true
        }
        await settle()

        #expect(grantedCount == 1)
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

    @Test("モデルが「見終えたが適用できなかった」と返したら、視聴しなかったアラートではなく適用できないアラートを出す")
    func modelHandledOutcomeSeparatesUnavailableFromNotEarned() async {
        let unavailable = RewardedRescue()
        var followUpAfterUnavailable = false
        unavailable.requestHandledByModel(withOutcome: { .unavailable },
                                          whenGranted: { followUpAfterUnavailable = true })
        await settle()
        #expect(unavailable.showsUnavailable, "適用できなかったのに知らせていない")
        #expect(!unavailable.showsNotEarned, "見終えたのに「最後まで視聴しなかった」と知らせている")
        #expect(!followUpAfterUnavailable, "適用できていないのに続きを走らせている")
        #expect(!unavailable.isWatching)

        let notEarned = RewardedRescue()
        notEarned.requestHandledByModel(withOutcome: { .notEarned })
        await settle()
        #expect(notEarned.showsNotEarned)
        #expect(!notEarned.showsUnavailable)

        let granted = RewardedRescue()
        var followUpAfterGrant = false
        granted.requestHandledByModel(withOutcome: { .granted }, whenGranted: { followUpAfterGrant = true })
        await settle()
        #expect(followUpAfterGrant)
        #expect(!granted.showsNotEarned)
        #expect(!granted.showsUnavailable)
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

    private static let sourcesRoot = SourceScan.packageRoot.appendingPathComponent("Sources")

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
        // 盤ゲーム 5 本の「待った」は Core の `BoardUndoButton` 1 か所に寄せた（#828）ので、ここには数えない。
        // 2048・ブロックならべ・ナンプレの広告コンティニューの幕も Core の `RewardedContinueOverlay` に寄せた（#829）。
        #expect(requests == 13, "救済の入口は13面（`requestHandledByModel` の3面と、Core に寄せた待った・コンティニューの幕を除く）")
        #expect(requests == guards,
                "`RewardedRescue.request` の呼び出しと `guardedBy` の数が合わない（\(requests) 対 \(guards)）")
    }

    @Test("Core に寄せた盤ゲームの待ったも、局ガードを宣言して控えた局面を渡している（#828）")
    func sharedBoardUndoDeclaresItsGuard() throws {
        // 上の走査は Core を対象外にしているので、盤ゲーム 5 本の待ったを寄せた部品はここで名指しで見る。
        // 行コメントの言及で数がずれないよう、`//` で始まる行を落としてから数える。
        let text = try String(
            contentsOf: Self.sourcesRoot.appendingPathComponent("Core/BoardGameChrome.swift"), encoding: .utf8
        )
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
        #expect(Self.occurrences(of: "Rescue.request(", in: text) == 1)
        #expect(Self.occurrences(of: "guardedBy: .checkedByGrant", in: text) == 1)
        #expect(Self.occurrences(of: "unavailable: RewardUnavailableAlert(", in: text) == 1)
        #expect(text.matches(of: try Regex(#"model\.\w+\(forTurn:"#)).count == 1)
    }

    @Test("Core に寄せた広告コンティニューの幕も、局ガードを宣言して控えた通し番号を渡している（#829）")
    func sharedContinueOverlayDeclaresItsGuard() throws {
        // 走査は Core を対象外にしているので、2048・ブロックならべ・ナンプレの幕を寄せた部品はここで名指しで見る。
        // 各ゲーム側は `RewardedContinueOverlay(` の呼び出しを照合する宣言として数える（下の 2 つの突き合わせ）。
        let text = try String(
            contentsOf: Self.sourcesRoot.appendingPathComponent("Core/RewardedRescue.swift"), encoding: .utf8
        )
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
        #expect(Self.occurrences(of: "Rescue.request(", in: text) == 1)
        #expect(Self.occurrences(of: "guardedBy: .checkedByGrant", in: text) == 1)
        #expect(Self.occurrences(of: "let game = serial()", in: text) == 1, "広告の前に通し番号を控えていない")
        #expect(Self.occurrences(of: "grant(game)", in: text) == 1, "控えた通し番号を grant に渡していない")
        // 控えるのは広告の**前**。`request` の完了クロージャの中で読むと、広告のあいだに始めた局の番号になる（#729）。
        let captured = try #require(text.range(of: "let game = serial()"))
        let requested = try #require(text.range(of: "Rescue.request("))
        #expect(captured.lowerBound < requested.lowerBound, "通し番号を広告の後に読んでいる")

        let callers = try Self.gameSources()
            .filter { $0.text.contains("RewardedContinueOverlay(") }
            .map(\.path)
            .sorted()
        #expect(callers == [
            "Game2048/Game2048View.swift",
            "GameBlockPuzzle/BlockPuzzleView.swift",
            "GameSudoku/SudokuView.swift",
        ])
    }

    @Test("照合していない面は名指しで固定する")
    func uncheckedSitesArePinned() throws {
        let sources = try Self.gameSources()
        let unchecked = sources
            .map { (path: $0.path, count: Self.occurrences(of: "guardedBy: .unchecked(", in: $0.text)) }
            .filter { $0.count > 0 }
            .sorted { $0.path < $1.path }

        // #526 の共通化の時点では、局の通し番号を持たない10面が照合していなかった。
        // #729 で全面が通し番号を控えて照合するようになり、残りは0面。
        // 新しい救済を照合なしで足すと、ここで名指しされて赤くなる。
        #expect(unchecked.map(\.path) == [])
        #expect(unchecked.reduce(0) { $0 + $1.count } == 0)
    }

    @Test("照合すると宣言した面には、適用できなかったときのアラートが必ずある")
    func checkedSitesAlwaysProvideTheUnavailableAlert() throws {
        // `checkedByGrant` は「grant が false を返しうる」という宣言なので、
        // `rewardedRescueAlerts(unavailable:)` を渡し忘れると失敗が**完全に無言**になる
        // （`showsUnavailable` は立つが、渡していない側は `.constant(false)` で出ない）。
        // 対価だけ払って何も起きない状態は広告の契約違反なので、ファイル単位で数を突き合わせる。
        // モデルが結果を返す形（`requestHandledByModel(withOutcome:)`・#727）も `.unavailable` で
        // `showsUnavailable` を立てるので、同じく照合する側として数える。
        let mismatched = try Self.gameSources()
            .map { (
                path: $0.path,
                checked: Self.occurrences(of: "guardedBy: .checkedByGrant", in: $0.text)
                    + Self.occurrences(of: "requestHandledByModel(withOutcome:", in: $0.text)
                    // Core の幕（#829）は中で `checkedByGrant` を宣言しているので、呼び出しを 1 件と数える。
                    + Self.occurrences(of: "RewardedContinueOverlay(", in: $0.text),
                alerts: Self.occurrences(of: "unavailable: RewardUnavailableAlert(", in: $0.text)
            ) }
            .filter { $0.checked != $0.alerts }
            .map { "\($0.path): 照合する宣言 \($0.checked) 件に対しアラート \($0.alerts) 件" }
        #expect(mismatched.isEmpty, "\(mismatched)")
    }

    @Test("照合すると宣言した面は、広告の前に控えた値を渡して適用している（#815）")
    func checkedSitesPassTheCapturedSerial() throws {
        // `checkedByGrant` は宣言でしかなく、`grant` が局を識別する値を渡さなければ照合は起きない。
        // ナンプレのヒントと麻雀ソリティアのヒント／並べ替えは宣言だけで照合が無く、広告中に始めた
        // 新しい局へ報酬が乗っていた（#815）。上の「残りは0面」はこの3面を数えていなかった。
        // 局の通し番号を受ける `model.xxx(forGame:` / `forDeal:` / `forTurn:` / `forRun:` の呼び出しを
        // ファイル単位で数え、宣言の数と突き合わせる。
        let serialCall = try Regex(#"model\.\w+\(for(Game|Deal|Turn|Run):"#)
        let mismatched = try Self.gameSources()
            .map { (
                path: $0.path,
                checked: Self.occurrences(of: "guardedBy: .checkedByGrant", in: $0.text)
                    + Self.occurrences(of: "RewardedContinueOverlay(", in: $0.text),
                serialCalls: $0.text.matches(of: serialCall).count
            ) }
            .filter { $0.checked != $0.serialCalls }
            .map { "\($0.path): 照合する宣言 \($0.checked) 件に対し通し番号を渡す呼び出し \($0.serialCalls) 件" }
        #expect(mismatched.isEmpty, "\(mismatched)")
    }

    @Test("モデルが広告ごと持つ救済は、見終えたのに適用できなかったことを分けて返す")
    func modelHeldRescuesAlwaysReportTheOutcome() throws {
        // `Bool` 版の `requestHandledByModel` は、広告のあいだに局が入れ替わって適用しなかったときも
        // 「広告を最後まで視聴しなかったか…」を出してしまう（#727）。麻雀のトビ復活だけが `Bool` 版の
        // まま残り、上の突き合わせは `withOutcome:` しか数えないので 0 対 0 で緑のまま通っていた（#814）。
        // `Bool` 版はトレイリングクロージャ（`requestHandledByModel {`）で書けて括弧が付かないので、
        // 名前だけで数えて `withOutcome:` の数と突き合わせる。
        let sources = try Self.gameSources()
        let all = sources.reduce(0) { $0 + Self.occurrences(of: "requestHandledByModel", in: $1.text) }
        let withOutcome = sources.reduce(0) {
            $0 + Self.occurrences(of: "requestHandledByModel(withOutcome:", in: $1.text)
        }
        #expect(withOutcome == 4, "広告をモデルで抱えている3面（ブラックジャック・ポーカー・麻雀）。麻雀は復活と最終局延長（#1201）の2か所")
        #expect(all == withOutcome,
                "`Bool` 版の `requestHandledByModel` が残っている（全 \(all) 件のうち withOutcome は \(withOutcome) 件）")
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

    @Test("広告を自分で抱えているモデルは、画面の世代を自分で照合している")
    func modelHeldRescuesCheckTheScreenGeneration() throws {
        // `RewardedRescue.request` を通る 18 面は共通側が世代を照合する（#653）が、
        // 広告をモデルの中で抱えている3面はそこを通らないので、各モデルが自分で照合する。
        // 照合の無いモデルが増えると、捨てられたモデルが `PlayLog` や中断データを
        // 新しい対局の裏で書き換える経路がそのぶん生まれる。
        let missing = try Self.gameSources()
            .filter { $0.text.contains("showRewardedAd(") }
            .filter { !$0.text.contains("screenGeneration.current == generationBeforeAd") }
            .map(\.path)
            .sorted()
        #expect(missing.isEmpty, "画面の世代を照合していないモデルがある: \(missing)")
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
