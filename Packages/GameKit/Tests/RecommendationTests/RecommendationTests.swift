import Testing
import Foundation
import SwiftUI
import Core
import Game2048
import GameShogi
import GameGomoku
import GameMinesweeper
import GameOthello
import GamePoker
import GameConcentration
import GameBlackjack
import GameDaifugo
import GameMahjongSolitaire
import GameMahjong
import GameSudoku
import GameGo

// MARK: - 共通のヘルパー

/// ハブの登録順（AppEnvironment.registry と同じ）。
private let hubOrder = [
    "2048", "shogi", "gomoku", "minesweeper", "othello", "poker", "concentration", "blackjack", "daifugo",
    "mahjong", "mahjong4", "sudoku", "go",
]

@MainActor
private func makeRegistry() -> GameRegistry {
    GameRegistry([
        Game2048Module(), ShogiModule(), GomokuModule(), MinesweeperModule(),
        OthelloModule(), PokerModule(), ConcentrationModule(), BlackjackModule(),
        DaifugoModule(), MahjongSolitaireModule(), MahjongModule(), SudokuModule(),
        GoModule(),
    ])
}

/// テスト専用の UserDefaults を作る。テストごとに違う suite 名を渡すこと（並列実行のため）。
@MainActor
private func makeLog(suite: String) -> (PlayLog, UserDefaults) {
    let name = "asobiba.recommendation.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (PlayLog(defaults: defaults), defaults)
}

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

@MainActor
private func makeServices(
    suite: String,
    hiddenIDs: Set<String> = []
) -> (GameServices, RecommendationService) {
    let (log, _) = makeLog(suite: suite)
    let registry = makeRegistry()
    let service = RecommendationService(
        log: log,
        availableModules: { hubOrder.compactMap { registry.module(id: $0) }.filter { !hiddenIDs.contains($0.id) } }
    )
    let services = GameServices(
        snapshots: MemorySnapshotStore(),
        ads: NoopAdService(),
        recommendations: service
    )
    return (services, service)
}

/// 提示条件を満たすところまで空回しする（別ゲームの終了として数える）。
@MainActor
private func advanceFinishes(_ service: RecommendationService, count: Int, gameID: String) {
    for _ in 0..<count { service.gameDidFinish(gameID: gameID) }
}

// MARK: - 固定テーブル（受け入れ条件: 提示されるゲームがテーブルどおり・ランダム要素が無い）

@Suite("レコメンドの候補テーブル")
@MainActor
struct RecommendationTableTests {

    /// Issue #52 の表に #237 の入れ替えを反映したもの。第1〜第3候補まで検証する。
    static let table: [(String, [String])] = [
        ("shogi",         ["gomoku", "othello", "2048"]),
        ("gomoku",        ["go", "othello", "shogi"]),
        ("othello",       ["gomoku", "shogi", "2048"]),
        ("2048",          ["minesweeper", "mahjong", "concentration"]),
        ("minesweeper",   ["sudoku", "2048", "mahjong"]),
        ("concentration", ["2048", "daifugo", "blackjack"]),
        ("poker",         ["blackjack", "daifugo", "concentration"]),
        ("blackjack",     ["poker", "daifugo", "concentration"]),
        ("daifugo",       ["poker", "blackjack", "concentration"]),
        ("mahjong",       ["mahjong4", "concentration", "minesweeper"]),
        ("mahjong4",      ["mahjong", "daifugo", "poker"]),
        ("sudoku",        ["minesweeper", "2048", "mahjong"]),
        ("go",            ["gomoku", "othello", "shogi"]),
    ]

    @Test("全ゲームそれぞれ、未プレイのみのときは第1候補が出る")
    func firstCandidate() {
        for (finished, expected) in Self.table {
            let got = RecommendationPolicy.candidate(
                finishedGameID: finished,
                playedGameIDs: [finished],
                availableIDs: hubOrder
            )
            #expect(got?.gameID == expected[0], "\(finished) の第1候補は \(expected[0])")
            #expect(got?.reason == .unplayed)
        }
    }

    @Test("上位候補が既プレイなら次の候補へ順に下りる")
    func fallsBackInOrder() {
        for (finished, expected) in Self.table {
            for skip in 1..<expected.count {
                let played = Set([finished] + expected.prefix(skip))
                let got = RecommendationPolicy.candidate(
                    finishedGameID: finished,
                    playedGameIDs: played,
                    availableIDs: hubOrder
                )
                #expect(got?.gameID == expected[skip], "\(finished): 上位\(skip)件が既プレイなら \(expected[skip])")
            }
        }
    }

    @Test("3候補が全て既プレイなら、ハブの並び順で先頭の未プレイが出る")
    func fallsBackToHubOrder() {
        let finished = "shogi"
        let played = Set([finished] + RecommendationPolicy.candidateTable[finished]!)
        let got = RecommendationPolicy.candidate(
            finishedGameID: finished,
            playedGameIDs: played,
            availableIDs: hubOrder
        )
        let expected = hubOrder.first { !played.contains($0) }
        #expect(got?.gameID == expected)
        #expect(got?.gameID == "minesweeper", "ハブ順で最初の未プレイ")
    }

    /// #237 の再発防止。値に一度も出てこないゲームは「他を遊んだ人には構造的に提案されない」。
    /// 大富豪・麻雀ソリティア・四人打ち麻雀・数独が実際にその状態だった。
    @Test("候補テーブルはハブの全ゲームを網羅する（キーにも値にも1回以上出る）")
    func coversEveryRegisteredGame() {
        let registered = Set(makeRegistry().modules.map(\.id))
        let table = RecommendationPolicy.candidateTable
        let keys = Set(table.keys)
        let values = Set(table.values.flatMap { $0 })

        #expect(keys == registered,
                "キーの過不足: \(keys.symmetricDifference(registered).sorted())")
        #expect(values.subtracting(registered).isEmpty,
                "登録の無い gameID が候補にある: \(values.subtracting(registered).sorted())")
        #expect(registered.subtracting(values).isEmpty,
                "どこからも提案されないゲーム: \(registered.subtracting(values).sorted())")

        for (key, candidates) in table {
            #expect(candidates.count == 3, "\(key) の候補は3件（実際: \(candidates.count)）")
            #expect(!candidates.contains(key), "\(key) が自分自身を候補にしている")
            #expect(Set(candidates).count == candidates.count, "\(key) の候補が重複している")
        }
    }

    /// 上のテストは `makeRegistry()`（テスト用の複製）を基準にしているため、本体の
    /// `AppEnvironment.registry` にゲームが増えたのに複製の更新を忘れると素通りしてしまう。
    /// GameKit のテストから App ターゲットは import できないので、ソースを走査して突き合わせる。
    @Test("テスト用のレジストリが AppEnvironment.registry と同じ構成である")
    func testRegistryMatchesAppRegistry() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RecommendationTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // GameKit/
            .deletingLastPathComponent()   // Packages/
            .deletingLastPathComponent()   // リポジトリのルート
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("App/AppGameServices.swift"), encoding: .utf8
        )
        guard let block = source.range(
            of: #"static let registry = GameRegistry\(\[[^\]]*\]\)"#, options: .regularExpression
        ) else {
            Issue.record("AppEnvironment.registry の定義が見つからない（走査のパターンが壊れている可能性）")
            return
        }

        let listed = Set(source[block].split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"),
                  let name = trimmed.split(separator: "(").first, name.hasSuffix("Module")
            else { return nil }
            return String(name)
        })
        let fixture = Set(makeRegistry().modules.map { String(describing: type(of: $0)) })

        #expect(listed.count == fixture.count && !listed.isEmpty)
        #expect(listed == fixture,
                "テスト用レジストリと本体の差分: \(listed.symmetricDifference(fixture).sorted())")
    }

    /// #335: 以前は「未プレイが無ければ nil」で、12本を1回ずつ遊んだ時点でレコメンドが
    /// 二度と出なくなっていた。未プレイが尽きたら久しぶり枠へ落ちる。
    @Test("全ゲーム既プレイでも、最終プレイが最も古いゲームが提示される")
    func fallsBackToLeastRecentlyPlayed() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // ハブ順に「新しく遊んだ」ほど後ろ。最も古いのは先頭の 2048。
        var lastPlayedAt: [String: Date] = [:]
        for (index, id) in hubOrder.enumerated() {
            lastPlayedAt[id] = now.addingTimeInterval(-Double(hubOrder.count - index) * 86_400)
        }

        for finished in hubOrder {
            let got = RecommendationPolicy.candidate(
                finishedGameID: finished,
                playedGameIDs: Set(hubOrder),
                availableIDs: hubOrder,
                lastPlayedAt: lastPlayedAt,
                now: now
            )
            let expected = finished == "2048" ? "shogi" : "2048"
            #expect(got?.gameID == expected, "\(finished): 最終プレイが最も古いゲーム")
            #expect(got?.gameID != finished, "たった今遊び終えたゲームは勧めない")
            if case .revisit = got?.reason {} else { Issue.record("\(finished): 久しぶり枠のはず") }
        }
    }

    @Test("久しぶり枠の日数は最終プレイからの経過日数（切り捨て・未来なら0日）")
    func revisitDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func reason(daysAgo: Double) -> RecommendationReason? {
            var lastPlayedAt = Dictionary(
                uniqueKeysWithValues: hubOrder.map { ($0, now) }
            )
            lastPlayedAt["2048"] = now.addingTimeInterval(-daysAgo * 86_400)
            return RecommendationPolicy.candidate(
                finishedGameID: "shogi",
                playedGameIDs: Set(hubOrder),
                availableIDs: hubOrder,
                lastPlayedAt: lastPlayedAt,
                now: now
            )?.reason
        }
        #expect(reason(daysAgo: 30) == .revisit(days: 30))
        #expect(reason(daysAgo: 1.9) == .revisit(days: 1), "切り捨て")
        #expect(reason(daysAgo: 0.5) == .revisit(days: 0))

        // 端末の時計が巻き戻ると最終プレイが未来になりうる。「-5日ぶり」を出さない。
        let future = RecommendationPolicy.candidate(
            finishedGameID: "shogi",
            playedGameIDs: Set(hubOrder),
            availableIDs: hubOrder,
            lastPlayedAt: Dictionary(
                uniqueKeysWithValues: hubOrder.map { ($0, now.addingTimeInterval(5 * 86_400)) }
            ),
            now: now
        )
        #expect(future?.reason == .revisit(days: 0), "時計が巻き戻っても負の日数を出さない")

        // 日付の記録が無い（この機能より前に遊んだ）ゲームは「最も古い」扱いで日数は nil。
        let noDate = RecommendationPolicy.candidate(
            finishedGameID: "shogi",
            playedGameIDs: Set(hubOrder),
            availableIDs: hubOrder,
            lastPlayedAt: ["shogi": now],
            now: now
        )
        #expect(noDate?.gameID == "2048", "日付の無いものはハブ順で先頭が出る")
        #expect(noDate?.reason == .revisit(days: nil))
    }

    @Test("見出しは理由で出し分ける（久しぶり枠だけ日数を出す）")
    func captionsPerReason() {
        #expect(RecommendationReason.unplayed.caption == "次はこれで遊ぶ？")
        #expect(RecommendationReason.revisit(days: 30).caption == "30日ぶりに遊んでみない？")
        #expect(RecommendationReason.revisit(days: 1).caption == "1日ぶりに遊んでみない？")
        #expect(RecommendationReason.revisit(days: 0).caption == "また遊んでみない？")
        #expect(RecommendationReason.revisit(days: nil).caption == "ひさしぶりに遊んでみない？")
    }

    @Test("ハブで非表示にしているゲームは候補にならない")
    func neverSuggestsHiddenGames() {
        // 将棋の第1候補は五目並べ。五目並べを非表示にすると第2候補のオセロに下りる。
        let visible = hubOrder.filter { $0 != "gomoku" }
        let got = RecommendationPolicy.candidate(
            finishedGameID: "shogi",
            playedGameIDs: ["shogi"],
            availableIDs: visible
        )
        #expect(got?.gameID == "othello")

        // 候補が1つも表示されていなければ nil。
        let onlyShogi = RecommendationPolicy.candidate(
            finishedGameID: "shogi",
            playedGameIDs: ["shogi"],
            availableIDs: ["shogi"]
        )
        #expect(onlyShogi == nil, "自分以外に提示できるゲームが無ければ nil")
    }

    @Test("同じ入力なら常に同じ結果（ランダム要素が無い）")
    func isDeterministic() {
        for finished in hubOrder {
            let results = (0..<100).map { _ in
                RecommendationPolicy.candidate(
                    finishedGameID: finished,
                    playedGameIDs: [finished, "2048"],
                    availableIDs: hubOrder
                )
            }
            #expect(Set(results.map { $0?.gameID ?? "nil" }).count == 1, "\(finished): 100回とも同じ結果")
        }
    }
}

// MARK: - 提示条件（受け入れ条件: 条件1〜5・一桁では絶対に出ない）

@Suite("レコメンドの提示条件")
@MainActor
struct RecommendationPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("条件1: 終了回数が一桁のときは絶対に表示されない")
    func neverShowsInSingleDigits() {
        for finishes in 0...9 {
            // 未提示・無視ゼロという最も出やすい状態でも出ない。
            let state = RecommendationState(totalFinishes: finishes)
            #expect(RecommendationPolicy.shouldShow(state: state, now: now) == false,
                    "\(finishes)回では表示しない")
        }
    }

    @Test("条件1: 19回では出ず、20回で初回が出る")
    func firstShowAtTwenty() {
        #expect(RecommendationPolicy.shouldShow(state: .init(totalFinishes: 19), now: now) == false)
        #expect(RecommendationPolicy.shouldShow(state: .init(totalFinishes: 20), now: now) == true)
    }

    @Test("条件2: 前回提示から30回終えるまで出ない")
    func intervalOfThirty() {
        let shownAt = now.addingTimeInterval(-RecommendationPolicy.minimumElapsed * 2)
        func state(_ total: Int) -> RecommendationState {
            .init(totalFinishes: total, lastShownCount: 20, lastShownAt: shownAt, ignoredStreak: 1)
        }
        #expect(RecommendationPolicy.shouldShow(state: state(49), now: now) == false, "29回では出ない")
        #expect(RecommendationPolicy.shouldShow(state: state(50), now: now) == true, "30回で出る")
    }

    @Test("条件3: 前回提示から24時間経つまで出ない")
    func minimumElapsed() {
        func state(_ elapsed: TimeInterval) -> RecommendationState {
            .init(totalFinishes: 100, lastShownCount: 20,
                  lastShownAt: now.addingTimeInterval(-elapsed), ignoredStreak: 1)
        }
        #expect(RecommendationPolicy.shouldShow(state: state(23 * 3600), now: now) == false)
        #expect(RecommendationPolicy.shouldShow(state: state(24 * 3600), now: now) == true)
    }

    @Test("条件5前半: 2回連続で無視されたら間隔が60回に倍増する")
    func extendedIntervalAfterTwoIgnores() {
        let shownAt = now.addingTimeInterval(-RecommendationPolicy.minimumElapsed * 2)
        func state(_ total: Int) -> RecommendationState {
            .init(totalFinishes: total, lastShownCount: 50, lastShownAt: shownAt, ignoredStreak: 2)
        }
        #expect(RecommendationPolicy.shouldShow(state: state(80), now: now) == false, "30回では出ない")
        #expect(RecommendationPolicy.shouldShow(state: state(110), now: now) == true, "60回で出る")
    }

    @Test("条件5後半: 3回連続で無視されたら以後どんな状態でも出ない")
    func stopsAfterThreeIgnores() {
        let longAgo = now.addingTimeInterval(-RecommendationPolicy.minimumElapsed * 365)
        for total in [20, 100, 10_000] {
            let state = RecommendationState(
                totalFinishes: total, lastShownCount: 0, lastShownAt: longAgo, ignoredStreak: 3
            )
            #expect(RecommendationPolicy.shouldShow(state: state, now: now) == false)
        }
    }
}

// MARK: - サービス（提示 → 無視 / タップの一巡）

@Suite("レコメンドの提示と反応")
@MainActor
struct RecommendationServiceTests {

    @Test("19回目までは提示せず、20回目で提示する")
    func showsOnTwentiethFinish() {
        let (_, service) = makeServices(suite: "service-twentieth")
        advanceFinishes(service, count: 19, gameID: "shogi")
        #expect(service.suggestedGameID == nil, "19回目までは出さない")
        service.gameDidFinish(gameID: "shogi")
        #expect(service.suggestedGameID == "gomoku", "20回目に将棋の第1候補が出る")
    }

    @Test("タップすると遷移が依頼され、連続無視がリセットされる")
    func acceptRequestsNavigation() {
        let (_, service) = makeServices(suite: "service-accept")
        advanceFinishes(service, count: 20, gameID: "shogi")
        #expect(service.suggestedGameID == "gomoku")
        #expect(service.log.state.ignoredStreak == 1, "提示は既定で無視として数える")

        service.accept()
        #expect(service.requestedGameID == "gomoku", "タップで該当ゲームへの遷移を依頼する")
        #expect(service.suggestedGameID == nil, "カードは閉じる")
        #expect(service.log.state.ignoredStreak == 0, "タップで連続無視がリセットされる")
    }

    @Test("×で閉じても連続無視は戻らない")
    func dismissKeepsStreak() {
        let (_, service) = makeServices(suite: "service-dismiss")
        advanceFinishes(service, count: 20, gameID: "shogi")
        service.dismiss()
        #expect(service.suggestedGameID == nil)
        #expect(service.log.state.ignoredStreak == 1)
    }

    @Test("3回連続で無視されたら以後表示されない")
    func stopsAfterThreeIgnores() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (log, _) = makeLog(suite: "service-stop")
        let registry = makeRegistry()
        let service = RecommendationService(
            log: log,
            availableModules: { hubOrder.compactMap { registry.module(id: $0) } },
            now: { clock }
        )

        var shownCount = 0
        // 3回の提示（すべて無視）ののち、十分な回数と時間を与えても二度と出ないことを見る。
        for _ in 0..<400 {
            service.gameDidFinish(gameID: "shogi")
            if service.suggestedGameID != nil {
                shownCount += 1
                service.dismiss()
            }
            clock = clock.addingTimeInterval(3600) // 1回ごとに1時間進める
        }
        #expect(shownCount == 3, "提示は3回で打ち止め（実際: \(shownCount)）")
        #expect(log.state.ignoredStreak == RecommendationPolicy.stopStreak)
    }

    /// #335 の受け入れ条件。全ゲーム踏破後もレコメンドが出続けること（以前は永久に出なくなっていた）。
    @Test("全ゲームを遊び尽くしても、久しぶり枠として提示され続ける")
    func suggestsRevisitWhenEverythingPlayed() {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (log, _) = makeLog(suite: "service-all-played")
        let registry = makeRegistry()
        let service = RecommendationService(
            log: log,
            availableModules: { hubOrder.compactMap { registry.module(id: $0) } },
            now: { clock }
        )
        /// 本番の `GameServices.gameDidFinish` と同じ順（記録 → レコメンド判定）で1回ぶん進める。
        func finish(_ id: String) {
            log.recordResult(gameID: id, outcome: .loss, score: GameScore(), at: clock)
            service.gameDidFinish(gameID: id)
        }

        // 全ゲームをハブ順に1回ずつ、1日ずつずらして遊ぶ（= 最も古いのは先頭の 2048）。
        for id in hubOrder {
            finish(id)
            clock = clock.addingTimeInterval(86_400)
        }
        #expect(log.playedGameIDs.count == hubOrder.count, "全ゲーム既プレイ")

        // 提示は20回目（`firstShowThreshold`）の終了から。その1つ手前まではまだ出ない。
        // ゲームが増えても成り立つよう、回数はしきい値から逆算する。
        for _ in 0..<(RecommendationPolicy.firstShowThreshold - hubOrder.count - 1) {
            finish("shogi")
            clock = clock.addingTimeInterval(3600)
        }
        #expect(service.suggestedGameID == nil, "しきい値の1つ手前までは出さない")

        finish("shogi")
        #expect(service.suggestedGameID == "2048", "最終プレイが最も古いゲームが出る")
        if case .revisit(let days?) = service.suggestedReason {
            #expect(days >= hubOrder.count - 1, "\(hubOrder.count - 1)日以上ぶり（実際: \(days)日）")
        } else {
            Issue.record("久しぶり枠として提示されるはず（実際: \(service.suggestedReason)）")
        }
    }

    /// 記録サービス（`PlayLog.records`）を持たない構成では最終プレイ日時が1件も無い。
    /// その場合も「日付不明＝最も古い」に倒して提示は続ける（黙って消えない）。
    @Test("最終プレイ日時が記録されていなくても、久しぶり枠は出る")
    func suggestsRevisitWithoutDates() {
        let (_, service) = makeServices(suite: "service-all-played-nodates")
        for id in hubOrder { service.gameDidFinish(gameID: id) }   // ハブのゲーム数ぶん
        advanceFinishes(
            service,
            count: RecommendationPolicy.firstShowThreshold - hubOrder.count - 1,
            gameID: "shogi"
        )                                                          // しきい値の1つ手前まで
        #expect(service.suggestedGameID == nil)

        service.gameDidFinish(gameID: "shogi")                     // 20回目で提示
        #expect(service.suggestedGameID == "2048", "日付が無ければハブ順で先頭（将棋以外）")
        #expect(service.suggestedReason == .revisit(days: nil))
    }

    @Test("非表示のゲームは提示されない")
    func skipsHiddenGames() {
        let (_, service) = makeServices(suite: "service-hidden", hiddenIDs: ["gomoku"])
        advanceFinishes(service, count: 20, gameID: "shogi")
        #expect(service.suggestedGameID == "othello", "非表示の五目並べを飛ばして第2候補")
    }

    @Test("評価リクエストと競合したら提示せず、カウントも消費しない")
    func yieldsToOtherPrompt() {
        let (_, service) = makeServices(suite: "service-suppressed")
        advanceFinishes(service, count: 19, gameID: "shogi")
        service.gameDidFinish(gameID: "shogi", isSuppressedByOtherPrompt: true)
        #expect(service.suggestedGameID == nil, "同じリザルトでは出さない")
        #expect(service.log.state.lastShownAt == nil, "提示カウントを消費していない")

        service.gameDidFinish(gameID: "shogi")
        #expect(service.suggestedGameID == "gomoku", "次のリザルトで出る")
    }
}

// MARK: - 保存（受け入れ条件: 再起動をまたいで保持・キーとデータ量が増えない・消去できる）

@Suite("プレイ記録の保存")
@MainActor
struct PlayLogStorageTests {

    /// 保存内容のバイト数（バイナリ plist 換算）。
    private func storedSize(_ domain: [String: Any]) -> Int {
        (try? PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0))?.count ?? -1
    }

    /// 値だけのバイト数。Issue #52 のデータ設計表（合計300バイト未満）と対応する。
    /// キー名（5つで125文字）と plist のヘッダ・オフセット表はこの見積りに含まれない。
    private func storedValueSize(_ domain: [String: Any]) -> Int {
        storedSize(["v": PlayLog.allKeys.compactMap { domain[$0] }])
    }

    @Test("アプリ再起動をまたいで値が保持される")
    func survivesRelaunch() {
        let name = "asobiba.recommendation.tests.persist"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let first = PlayLog(defaults: defaults)
        for _ in 0..<7 { first.recordFinish(gameID: "2048") }
        first.recordFinish(gameID: "othello")
        let shownAt = Date(timeIntervalSince1970: 1_800_000_000)
        first.markShown(at: shownAt)

        // 再起動相当: 同じ保存先から作り直す。
        let second = PlayLog(defaults: defaults)
        #expect(second.totalFinishes == 8)
        #expect(second.playedGameIDs == ["2048", "othello"])
        #expect(second.state.lastShownCount == 8)
        #expect(second.state.lastShownAt == shownAt)
        #expect(second.state.ignoredStreak == 1)

        defaults.removePersistentDomain(forName: name)
    }

    @Test("保存キーは5つだけ。プレイ回数が増えてもキー数もデータ量も増えない")
    func keysAndSizeAreBounded() {
        let name = "asobiba.recommendation.tests.size"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let log = PlayLog(defaults: defaults)
        for i in 0..<20 { log.recordFinish(gameID: hubOrder[i % hubOrder.count]) }
        log.markShown(at: Date(timeIntervalSince1970: 1_800_000_000))
        let after20 = defaults.persistentDomain(forName: name) ?? [:]

        for i in 0..<1000 { log.recordFinish(gameID: hubOrder[i % hubOrder.count]) }
        log.markShown(at: Date(timeIntervalSince1970: 1_900_000_000))
        let after1020 = defaults.persistentDomain(forName: name) ?? [:]

        // 評価リクエスト（#53）の4キーはこのテストでは書き込まれない（勝利を記録していないため）。
        #expect(Set(after20.keys) == Set(PlayLog.recommendationKeys), "書き込むキーは5つだけ")
        #expect(Set(after1020.keys) == Set(after20.keys), "1000回遊んでもキーは増えない")
        // 増えうるのは整数の桁だけ（バイナリ plist の整数幅）。追記型ログなら数十 KB になる。
        #expect(storedSize(after1020) - storedSize(after20) <= 16, "データ量はほぼ一定")
        #expect(storedValueSize(after1020) < 300, "値の合計は300バイト未満（Issue #52 のデータ設計）")
        #expect(storedSize(after1020) <= 512, "キー名と plist の枠を含めても 512 バイト以内")

        defaults.removePersistentDomain(forName: name)
    }

    @Test("消去すると保存した5キーが全て消える")
    func clearRemovesEverything() {
        let name = "asobiba.recommendation.tests.clear"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let log = PlayLog(defaults: defaults)
        for id in hubOrder { log.recordFinish(gameID: id) }
        log.markShown(at: Date(timeIntervalSince1970: 1_800_000_000))
        #expect((defaults.persistentDomain(forName: name) ?? [:]).isEmpty == false)

        log.clear()
        for key in PlayLog.allKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key) が残っている")
        }
        #expect(log.totalFinishes == 0)
        #expect(log.playedGameIDs.isEmpty)
        #expect(log.state == RecommendationState(), "判定用の状態も初期化される")

        defaults.removePersistentDomain(forName: name)
    }
}

// MARK: - 各ゲームの決着で1回ずつ数えられること

@Suite("全9ゲームの決着を数える")
@MainActor
struct GameFinishCountingTests {

    @Test("2048: 終局で1回数える")
    func game2048() {
        let (services, service) = makeServices(suite: "count-2048")
        let model = Game2048Model(services: services)
        outer: for _ in 0..<3000 {
            for direction in Direction.allCases {
                model.move(direction)
                if model.gameOver { break outer }
            }
        }
        #expect(model.gameOver)
        #expect(service.log.totalFinishes == 1)
        #expect(service.log.playedGameIDs == ["2048"])
    }

    @Test("将棋: 投了で1回数える")
    func shogi() {
        let (services, service) = makeServices(suite: "count-shogi")
        let model = ShogiGameModel(services: services)
        model.resign()
        #expect(service.log.totalFinishes == 1)
        #expect(service.log.playedGameIDs == ["shogi"])
    }

    @Test("五目並べ: 投了で1回数える")
    func gomoku() {
        let (services, service) = makeServices(suite: "count-gomoku")
        let model = GomokuModel(services: services)
        model.newGame(humanSide: .black, aiLevel: 1)
        model.resign()
        #expect(service.log.totalFinishes == 1)
        #expect(service.log.playedGameIDs == ["gomoku"])
    }

    @Test("マインスイーパー: 地雷を踏むと1回数える")
    func minesweeper() {
        let (services, service) = makeServices(suite: "count-minesweeper")
        let model = MinesweeperModel(services: services)
        model.newGame(rows: 9, cols: 9, mines: 10)
        model.tap(row: 0, col: 0)
        guard let mine = model.cells.indices.flatMap({ r in
            model.cells[r].indices.map { (r, $0) }
        }).first(where: { model.cells[$0.0][$0.1].isMine && !model.cells[$0.0][$0.1].isFlagged }) else {
            Issue.record("地雷が見つからない")
            return
        }
        model.tap(row: mine.0, col: mine.1)
        #expect(model.gameOver)
        #expect(service.log.totalFinishes == 1)
        #expect(service.log.playedGameIDs == ["minesweeper"])
    }

    @Test("オセロ: 投了で1回数える")
    func othello() {
        let (services, service) = makeServices(suite: "count-othello")
        let model = OthelloModel(services: services)
        model.newGame(humanSide: .black, aiLevel: 1)
        model.resign()
        #expect(service.log.totalFinishes == 1)
        #expect(service.log.playedGameIDs == ["othello"])
    }

    @Test("ポーカー: ラウンドの決着で1回数える")
    func poker() {
        let (services, service) = makeServices(suite: "count-poker")
        let model = PokerModel(services: services)
        model.restartSession()
        model.startGame()
        model.bet1Action(.check)
        if model.phase == .exchange { model.confirmExchange() }
        if model.phase == .betting2 { model.bet2Action(.check) }
        if model.phase == .betting2, model.currentBet > 0 { model.callCPUBet() }
        #expect(model.phase == .result)
        #expect(service.log.totalFinishes == 1)
        #expect(service.log.playedGameIDs == ["poker"])
    }

    @Test("神経衰弱: 全ペア成立で1回数える")
    func concentration() {
        let (services, service) = makeServices(suite: "count-concentration")
        let model = ConcentrationModel(services: services)
        model.newGame(pairCount: .medium, cpuLevel: .normal)
        for _ in 0..<model.cards.count where !model.isGameOver {
            let unmatched = model.cards.indices.filter { !model.cards[$0].isMatched }
            guard let first = unmatched.first,
                  let second = unmatched.first(where: {
                      $0 != first && model.cards[$0].symbol == model.cards[first].symbol
                  }) else { break }
            if model.firstFlippedIndex == nil { model.tap(index: first) }
            model.tap(index: second)
        }
        #expect(model.isGameOver)
        #expect(service.log.totalFinishes == 1)
        #expect(service.log.playedGameIDs == ["concentration"])
    }

    @Test("数独: 解き切ると1回数える")
    func sudoku() async {
        let (services, service) = makeServices(suite: "count-sudoku")
        let model = SudokuModel(services: services, seed: 31337)
        await model.newGame(difficulty: .easy)
        for index in 0..<81 where model.board[index] == 0 {
            if model.selected != index { model.select(index: index) }
            model.enter(digit: model.solution[index])
        }
        #expect(model.state == .cleared)
        #expect(service.log.totalFinishes == 1)
        #expect(service.log.playedGameIDs == ["sudoku"])
    }

    @Test("ブラックジャック: ラウンドの決着で1回数える")
    func blackjack() {
        let (services, service) = makeServices(suite: "count-blackjack")
        let model = BlackjackModel(services: services)
        model.restartSession()
        model.placeBet(100)
        if model.phase == .playerTurn { model.stand() }
        #expect(model.phase == .result)
        #expect(service.log.totalFinishes == 1)
        #expect(service.log.playedGameIDs == ["blackjack"])
    }

    @Test("麻雀ソリティア: 取り切ると1回数える")
    func mahjong() {
        let (services, service) = makeServices(suite: "count-mahjong")
        let model = MahjongSolitaireModel(services: services, seed: 808)
        for pair in model.solution {
            model.tap(pair[0])
            model.tap(pair[1])
        }
        #expect(model.phase == .won)
        #expect(service.log.totalFinishes == 1)
        #expect(service.log.playedGameIDs == ["mahjong"])
    }
}
