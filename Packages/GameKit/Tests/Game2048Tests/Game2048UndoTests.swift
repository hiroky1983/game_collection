import Testing
import Foundation
import Core
import CoreTestSupport
@testable import Game2048

/// #2023: 「戻す」（1 局無料 3 回・広告 1 本で 3 回補充・履歴は中断データに保存）。
@Suite("2048 戻す（#2023）")
@MainActor
struct Game2048UndoTests {
    /// 右へ 1 手動かすと盤が埋まり、どの 2/4 が出ても詰む盤（残る空きは (3,0) だけで、隣は 8 / 16 なので合体しない）。
    static let oneMoveFromLoss = [
        [2, 4, 8, 4],
        [16, 8, 32, 16],
        [8, 64, 128, 32],
        [16, 8, 4, 0],
    ]

    private func makeModel(store: MemorySnapshotStore = MemorySnapshotStore(), board: [[Int]]? = nil) -> Game2048Model {
        let services = GameServices(snapshots: store, ads: NoopAdService())
        if let board { return Game2048Model(services: services, board: board, score: 100) }
        return Game2048Model(services: services)
    }

    /// 動く向きが見つかるまで指して 1 手進める（新タイルは乱数なので向きは盤を見て選ぶ）。
    private func playOneMove(_ model: Game2048Model) {
        let count = model.history.count
        for direction in Direction.allCases where model.history.count == count {
            model.move(direction)
        }
    }

    @Test("戻すと 1 手前（出現タイルも含む）の盤と得点・最大タイルに一致する")
    func undoRestoresPreviousBoardScoreAndMaxTile() {
        let model = makeModel(board: [[2, 2, 4, 0], [0, 0, 0, 0], [0, 0, 0, 8], [0, 0, 0, 0]])
        let before = (board: model.board, score: model.score)
        model.move(.left)
        #expect(model.score > before.score, "前提: 合体で得点が入る")
        #expect(model.undo())
        #expect(model.board == before.board)
        #expect(model.score == before.score)
        #expect(model.board.flatMap { $0 }.max() == 8)
        #expect(model.history.isEmpty)
    }

    @Test("続けて戻すと、さらに前へ戻れる")
    func undoChainsBackwards() {
        let model = makeModel(board: [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2]])
        let first = model.board
        model.move(.left)
        let second = model.board
        model.move(.up)
        #expect(model.history.count == 2)
        model.undo()
        #expect(model.board == second)
        model.undo()
        #expect(model.board == first)
        #expect(!model.canUndo, "履歴が尽きたら押せない")
        #expect(!model.undo())
    }

    @Test("無料 3 回 → 使い切ると提案 → 広告で 3 回補充")
    func freeThenRefill() {
        let model = makeModel()
        for _ in 0..<5 { playOneMove(model) }
        #expect(model.undosRemaining == Game2048UndoBudget.free)
        for _ in 0..<Game2048UndoBudget.free { #expect(model.undo()) }
        #expect(model.undosRemaining == 0)
        #expect(model.canUndo && model.needsUndoRefill, "使い切り: 押せるが広告が要る")
        let frozen = model.board
        #expect(!model.undo(), "回数が無ければ戻らない")
        #expect(model.board == frozen)

        #expect(model.grantUndos(forGame: model.gameSerial))
        #expect(model.undosRemaining == Game2048UndoBudget.refill)
        #expect(!model.needsUndoRefill)
        #expect(model.undo())
        #expect(model.undosRemaining == Game2048UndoBudget.refill - 1)
    }

    @Test("広告のロード中に新規ゲームを始めたら補充しない・新規ゲームで無料枠に戻る")
    func staleRefillIsRejectedAndNewGameResets() {
        let model = makeModel()
        playOneMove(model)
        model.undo()
        let serial = model.gameSerial
        model.newGame()
        #expect(!model.grantUndos(forGame: serial))
        #expect(model.undosRemaining == Game2048UndoBudget.free)
        #expect(model.history.isEmpty)
    }

    @Test("負けの局面からも戻せる。戻すとゲームが続き、コンティニュー権は使わない")
    func undoFromGameOver() {
        let model = makeModel(board: Self.oneMoveFromLoss)
        let before = model.board
        model.move(.right)
        #expect(model.gameOver, "前提: この 1 手で詰む")
        #expect(model.undo())
        #expect(!model.gameOver)
        #expect(model.board == before)
        #expect(model.recordResult == nil)
        #expect(!model.continueUsed, "戻すはコンティニューを消費しない")
        #expect(Direction.allCases.contains { Game2048Logic.slide(model.board, $0).moved })
    }

    @Test("勝利演出の最中は戻せない（先に「続ける / もう一度」を選ぶ）")
    func undoBlockedWhileWinPrompt() {
        let model = makeModel(board: [[1024, 1024, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]])
        model.move(.left)
        #expect(model.showWinPrompt)
        #expect(!model.canUndo)
        #expect(!model.undo())
        model.continueAfterWin()
        #expect(model.canUndo, "続けたあとは戻せる")
    }

    @Test("中断復元で履歴と使った回数が保たれる（回数は無料枠に戻らない）")
    func snapshotRestoresHistoryAndBudget() {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        for _ in 0..<4 { playOneMove(model) }
        model.undo()
        model.undo()
        let remaining = model.undosRemaining
        #expect(remaining == Game2048UndoBudget.free - 2)

        let restored = makeModel(store: store)
        #expect(restored.board == model.board)
        #expect(restored.history == model.history)
        #expect(restored.undosRemaining == remaining)
        let board = restored.board
        let step = restored.history.last
        #expect(restored.undo())
        #expect(restored.board == step?.board)
        #expect(restored.board != board || step?.board == board)
    }

    @Test("履歴の鍵が無い旧い中断データは履歴なし・無料枠から読む")
    func legacySnapshotWithoutHistory() throws {
        let json = #"{"board":[[2,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,2]],"score":4}"#
        let snap = try JSONDecoder().decode(Game2048Snapshot.self, from: Data(json.utf8))
        #expect(snap.history == nil)
        #expect(snap.undosRemaining == nil)
        let store = MemorySnapshotStore()
        try store.save(snap, for: "2048")
        let model = makeModel(store: store)
        #expect(model.history.isEmpty)
        #expect(model.undosRemaining == Game2048UndoBudget.free)
    }

    @Test("履歴に壊れた盤が混じる中断データは履歴ごと捨てる")
    func brokenHistoryIsDropped() throws {
        let store = MemorySnapshotStore()
        try store.save(Game2048Snapshot(
            board: [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2]], score: 4,
            history: [Game2048Step(board: [[2, 0], [0, 2]], score: 0)], undosRemaining: 1
        ), for: "2048")
        let model = makeModel(store: store)
        #expect(model.history.isEmpty)
        #expect(!model.canUndo)
        #expect(model.undosRemaining == 1, "回数は壊れた履歴と無関係に保つ")
    }

    @Test("履歴は上限で打ち止め（復元でも手数を絞る）")
    func historyIsCapped() throws {
        let step = Game2048Step(board: [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2]], score: 0)
        let store = MemorySnapshotStore()
        try store.save(Game2048Snapshot(
            board: step.board, score: 0,
            history: Array(repeating: step, count: Game2048UndoBudget.historyLimit + 50)
        ), for: "2048")
        let model = makeModel(store: store)
        #expect(model.history.count == Game2048UndoBudget.historyLimit)

        // 指し手側も上限を超えて積まない。
        for _ in 0..<5 { playOneMove(model) }
        #expect(model.history.count == Game2048UndoBudget.historyLimit)
    }
}
