import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameGomoku

/// 1局3回のヒント（#1118）。回数の勘定そのものは Core の `BoardHintBudget`（`BoardHintTests`）が
/// 固定するので、ここでは**五目並べの対局にどう結線されているか**を見る（将棋・チェスと同型）。
@MainActor
@Suite("五目並べ ヒント（#1118）")
struct GomokuHintTests {

    private func makeServices(_ store: MemorySnapshotStore) -> GameServices {
        GameServices(snapshots: store, ads: NoopAdService())
    }

    @Test("押すと打つと良い交点が1つ出て、残りが1つ減る")
    func showsBestPointAndSpendsOne() async throws {
        let model = GomokuModel(services: nil)
        #expect(model.hintsRemaining == BoardHintBudget.perGame)
        #expect(model.canUseHint)

        await model.requestHint()

        #expect(model.hintsRemaining == BoardHintBudget.perGame - 1)
        let point = try #require(model.hintPoint, "ヒントの交点が出ていない")
        #expect((0..<gomokuBoardSize).contains(point.row) && (0..<gomokuBoardSize).contains(point.col))
        #expect(model.board[point.row, point.col] == nil, "石のある交点を示している")
        #expect(!model.isHintThinking, "読みが終わったのに思考中のまま")
    }

    @Test("3回使うと押せなくなり、4回目は何も起きない")
    func stopsAfterThreeHints() async {
        let model = GomokuModel(services: nil)
        for _ in 0..<BoardHintBudget.perGame { await model.requestHint() }
        #expect(model.hintsRemaining == 0)
        #expect(!model.canUseHint)

        await model.requestHint()
        #expect(model.hintsRemaining == 0, "使い切ったあとに回数が動いている")
    }

    @Test("CPU の手番ではヒントを押せない")
    func cannotUseHintOnTheCPUTurn() {
        let model = GomokuModel(services: nil)
        model.tap(row: 7, col: 7)
        #expect(model.isAITurn, "前提: CPU の手番になっている")
        #expect(!model.canUseHint)
    }

    @Test("打つとヒントの印は消える（回数は戻らない）")
    func hintMarkDisappearsAfterTheMove() async throws {
        let model = GomokuModel(services: nil)
        await model.requestHint()
        try #require(model.hintPoint != nil)

        model.tap(row: 0, col: 0)

        #expect(model.hintPoint == nil)
        #expect(model.hintsRemaining == BoardHintBudget.perGame - 1, "打ったら回数が戻っている")
    }

    @Test("新規対局で3回に戻る")
    func newGameRefillsHints() async {
        let model = GomokuModel(services: nil)
        await model.requestHint()
        #expect(model.hintsRemaining < BoardHintBudget.perGame)

        model.newGame()

        #expect(model.hintsRemaining == BoardHintBudget.perGame)
        #expect(model.hintPoint == nil, "前の対局のヒントの印が残っている")
    }

    /// 禁じ手ルールがオンのとき、黒に三三・四四・長連を勧めると「打てません」と断られる手を示すことになる。
    ///
    /// (7,7) に打つと三三が成立する盤（`GomokuRenjuTests` の形）を注入する。黒にとっては最も打ちたい
    /// 点なので、読みに禁じ手を渡し忘れていればヒントはここを示す。
    @Test("禁じ手ルールの対局では、黒に打てない交点を示さない")
    func hintRespectsRenjuForbiddenMoves() async throws {
        let store = MemorySnapshotStore()
        try store.save(Self.doubleThreeSnapshot(), for: "gomoku")
        let model = GomokuModel(services: makeServices(store))
        try #require(!model.gameOver && !model.isAITurn, "前提: 黒（人間）の手番で止まっている")
        try #require(model.forbiddenReason(row: 7, col: 7) != nil, "前提: (7,7) は黒の禁じ手")

        await model.requestHint()

        let point = try #require(model.hintPoint)
        #expect(model.forbiddenReason(row: point.row, col: point.col) == nil,
                "禁じ手の交点をヒントとして示している")
    }

    /// (7,7) が黒の三三になる一歩手前の盤（禁じ手ルールあり・黒の手番）。
    private static func doubleThreeSnapshot() -> GomokuSnapshot {
        var board = GomokuBoard()
        for (row, col) in [(7, 5), (7, 6), (5, 7), (6, 7)] { board[row, col] = .black }
        // 手数の辻褄合わせ（盤の端で、判定に絡まない位置）。
        for (row, col) in [(0, 0), (0, 14), (14, 0), (14, 14)] { board[row, col] = .white }
        return GomokuSnapshot(
            cells: board.cells.map { $0?.rawValue },
            currentStone: GomokuStone.black.rawValue,
            humanSide: GomokuStone.black.rawValue,
            aiLevel: 1,
            startedAt: Date(),
            moveHistory: nil,
            undoUsed: nil,
            resigned: nil,
            winner: nil,
            forbiddenMoves: true,
            hintsUsed: nil
        )
    }

    @Test("中断データに使った回数が乗り、再開しても残りが戻らない")
    func hintCountSurvivesRestart() async throws {
        let store = MemorySnapshotStore()
        let model = GomokuModel(services: makeServices(store))
        await model.requestHint()
        try #require(model.hints.used == 1)

        let restored = GomokuModel(services: makeServices(store))
        #expect(restored.hintsRemaining == BoardHintBudget.perGame - 1, "再開でヒントが戻っている")
        #expect(restored.hintPoint == nil, "印は保存しない（開き直したら出し直す）")
    }

    @Test("鍵を持たない旧形式の中断データは未使用として読む")
    func legacySnapshotReadsAsUnused() throws {
        let store = MemorySnapshotStore()
        let model = GomokuModel(services: makeServices(store))
        model.newGame()

        // v1.1.5 までの中断データと同じく `hintsUsed` の鍵が無い形を流し込む。
        let legacy = try #require(store.rawData(for: "gomoku"))
        let text = try #require(String(data: legacy, encoding: .utf8))
        #expect(text.contains("hintsUsed"), "前提: いまの形式は鍵を持つ")
        let stripped = try #require(
            text.replacingOccurrences(of: "\"hintsUsed\":0,", with: "")
                .replacingOccurrences(of: ",\"hintsUsed\":0", with: "")
                .data(using: .utf8)
        )
        store.inject(stripped, for: "gomoku")

        let restored = GomokuModel(services: makeServices(store))
        #expect(restored.hintsRemaining == BoardHintBudget.perGame)
    }

    @Test("ヒントを使った対局は順位表へ送らない（自己ベストはローカルに残る）")
    func usedHintDropsLeaderboardEligibility() async throws {
        let name = "asobiba.gomoku.hint.tests"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
        let model = GomokuModel(services: services)

        #expect(model.hints.winLossScore.isLeaderboardEligible, "前提: 使う前は順位表の対象")
        await model.requestHint()
        try #require(model.hints.used == 1)
        #expect(!model.hints.winLossScore.isLeaderboardEligible)

        model.resign()
        #expect(log.record(gameID: "gomoku")?.plays == 1, "自己ベスト（端末内）は使用有無を問わず残す")
        #expect(model.recordResult != nil, "リザルトの記録行も従来どおり出る")
    }
}
