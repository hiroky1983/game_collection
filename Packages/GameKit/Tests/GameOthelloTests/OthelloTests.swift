import Testing
import Foundation
import Core
@testable import GameOthello

@Suite("OthelloBoard")
struct OthelloBoardTests {

    @Test("初期配置は石4個") func initialCount() {
        let board = OthelloBoard()
        #expect(board.count(for: .black) == 2)
        #expect(board.count(for: .white) == 2)
    }

    @Test("初手は4マスどれか") func initialMoves() {
        let board = OthelloBoard()
        let moves = board.validMoves(for: .black)
        #expect(moves.count == 4)
    }

    @Test("石を置くとひっくり返る") func flipOnPlace() {
        var board = OthelloBoard()
        // 黒の初手 (2,3) → (3,3) の白がひっくり返る
        board.place(row: 2, col: 3, stone: .black)
        #expect(board[2, 3] == .black)
        #expect(board[3, 3] == .black)
    }

    @Test("盤面満杯判定") func fullBoard() {
        var board = OthelloBoard()
        for r in 0..<othelloBoardSize {
            for c in 0..<othelloBoardSize {
                if board[r, c] == nil { board[r, c] = .black }
            }
        }
        #expect(board.isFull)
    }
}

// MARK: - CPU 起動トリガー（#140: 後手を選ぶと CPU が初手を打たない）

@MainActor
@Suite("オセロ CPU 起動トリガー")
struct OthelloAITurnKeyTests {
    /// View は `.task(id: model.aiTurnKey)` で CPU を起動する。
    /// 起動直後（turnID = 0）に後手を選んでも turnID が 0 のままなので、
    /// キーが変わらないと初手が打たれない。
    @Test func aiTurnKeyChangesWhenStartingAsGoteWithoutMoves() {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        #expect(model.turnID == 0)
        let before = model.aiTurnKey

        model.newGame(humanSide: .white)
        #expect(model.turnID == 0)         // turnID は 0 のまま
        #expect(model.aiTurnKey != before) // それでもトリガーは変化する
        #expect(model.isAITurn)
    }

    /// 後手開始 → CPU 初手 → 人間応手 → 再び CPU 番、まで通しで動くこと。
    @Test func goteStartPlaysCPUFirstMoveThenHumanReply() async {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        model.newGame(humanSide: .white)

        await model.performAIMoveIfNeeded()
        #expect(model.turnID == 1)
        #expect(model.isAITurn == false) // 人間(白)の番
        let afterCPU = model.aiTurnKey

        let move = try! #require(model.board.validMoves(for: .white).first)
        model.tap(row: move.0, col: move.1)

        #expect(model.turnID == 2)
        #expect(model.aiTurnKey != afterCPU)
        #expect(model.isAITurn) // CPU(黒)の番に戻る
    }

    /// 対局途中から新規対局を始めて後手を選んだ場合もトリガーが変化すること。
    @Test func aiTurnKeyChangesWhenRestartingMidGameAsGote() async {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        let first = try! #require(model.board.validMoves(for: .black).first)
        model.tap(row: first.0, col: first.1)
        await model.performAIMoveIfNeeded()
        let before = model.aiTurnKey

        model.newGame(humanSide: .white)
        #expect(model.turnID == 0)
        #expect(model.aiTurnKey != before)
        #expect(model.isAITurn)
    }

    /// 先手を選んだ場合は従来どおり CPU は動かず、人間の手番から始まる。
    @Test func senteStartKeepsHumanTurn() async {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        model.newGame(humanSide: .black)
        #expect(model.isAITurn == false)
        await model.performAIMoveIfNeeded()
        #expect(model.turnID == 0)
    }
}

// MARK: - 思考中の新規対局（#140 のレビュー指摘: 旧盤面で選んだ手が新盤面に着手される）

/// 思考タスクを探索の開始直前で止めておくためのゲート（#172）。
///
/// 以前は「思考タスクを積んだ直後に空タスクを積む」という MainActor のジョブ順序で待ち合わせて
/// いたが、これは「空タスクが走る時点で探索がまだ終わっていない」ことまでは保証できない。
/// オセロは初期盤面の合法手が4手しかなく探索が軽いため、CI の巡り合わせによっては前提の
/// `#require(model.isThinking)` のほうが落ちて、無関係な PR のマージを止めていた。
///
/// ここではモデル側の待ち合わせ点（`thinkingGate`）で思考を明示的に止め、テストが `release()` を
/// 呼ぶまで探索に入らせない。到達も解放もテストが制御するため、探索の所要時間に依存しない。
@MainActor
final class ThinkingGate {
    private var hasArrived = false
    private var isReleased = false
    private var onArrival: CheckedContinuation<Void, Never>?
    private var onRelease: CheckedContinuation<Void, Never>?

    /// 思考タスク側。ゲートへの到達を知らせ、`release()` まで停止する。
    func wait() async {
        hasArrived = true
        onArrival?.resume()
        onArrival = nil
        guard !isReleased else { return }
        await withCheckedContinuation { onRelease = $0 }
    }

    /// テスト側。思考タスクがゲートに到達するまで待つ。
    func waitUntilArrived() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { onArrival = $0 }
    }

    /// テスト側。止めていた思考タスクを探索へ進ませる。
    func release() {
        isReleased = true
        onRelease?.resume()
        onRelease = nil
    }
}

@MainActor
@Suite("オセロ 思考中の新規対局")
struct OthelloNewGameDuringThinkingTests {
    /// CPU の思考を開始し、探索の直前で止まっている状態にして返す。
    ///
    /// ゲートは一度到達したら外す（`thinkingGate = nil`）。停止中の旧タスクはすでにゲートの中に
    /// いるため影響を受けず、以降に始まる新しい対局の思考は素通りする。
    private func startThinking(_ model: OthelloModel) async throws -> (task: Task<Void, Never>, gate: ThinkingGate) {
        let gate = ThinkingGate()
        model.thinkingGate = { await gate.wait() }
        let task = Task { await model.performAIMoveIfNeeded() }
        await gate.waitUntilArrived()
        model.thinkingGate = nil
        try #require(model.isThinking, "テストの前提: 旧対局の思考が計算中であること")
        return (task, gate)
    }

    /// CPU の思考中に新規対局を始めても、旧盤面で選んだ手が新しい盤面に着手されないこと。
    /// オセロは着手で石が返るため、旧盤面の手をそのまま打つと盤面が壊れる。
    ///
    /// 新旧どちらも「初期盤面・CPU が黒（先手）」に揃えているため、旧盤面で選んだ手は新しい盤面でも
    /// **合法**になる。着手直前の合法手チェックでは弾けない最悪ケースで、世代（`aiTurnKey`）の一致を
    /// 見て初めて弾ける。併せて、旧タスクの完了を待たずに思考フラグが解放されることも確かめる。
    @Test func newGameDuringThinkingDiscardsStaleMove() async throws {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        model.newGame(humanSide: .white, aiLevel: 2) // CPU=黒(先手)
        #expect(model.isAITurn)

        let (thinking, gate) = try await startThinking(model)

        model.newGame(humanSide: .white, aiLevel: 2) // 思考中に同じ初期盤面で新規対局
        #expect(model.isThinking == false)           // 新しい対局の CPU を起動できる

        gate.release()                      // 旧対局の探索はここで初めて走る（旧盤面のまま）
        await thinking.value                // 旧対局の計算が終わるまで待つ
        #expect(model.turnID == 0)          // 旧盤面で選んだ手は入っていない
        #expect(model.blackCount == 2)      // 初期配置のまま（石が返っていない）
        #expect(model.whiteCount == 2)
        #expect(model.isThinking == false)  // 旧タスクの defer にフラグを奪われない
        #expect(model.isAITurn)             // 新しい対局は CPU(黒)の手番のまま
    }
}

// MARK: - 撮影用プレビュー（#366 の PR #367 に付いた未消化のレビュー指摘）

private final class MockSnapshotStore: Core.SnapshotStore, @unchecked Sendable {
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

private func makeServices(_ store: MockSnapshotStore) -> GameServices {
    GameServices(snapshots: store, ads: NoopAdService())
}

@MainActor
@Suite("オセロ 撮影用プレビュー")
struct OthelloPreviewMidgameTests {

    /// 中断対局が残っていても撮影用の中盤盤面が作られること。
    /// 以前は `guard turnID == 0` で弾いていたため、保存対局があると撮影が空振りしていた。
    @Test func buildsMidgameEvenWithSavedGame() throws {
        let store = MockSnapshotStore()
        let seed = OthelloModel(services: makeServices(store), flipSettleDelay: .zero)
        seed.tap(row: 2, col: 3)                  // 中断対局を1つ作る（黒が1手）

        let model = OthelloModel(services: makeServices(store), flipSettleDelay: .zero)
        try #require(model.turnID == 1, "テストの前提: 中断対局から復元していること")

        model.applyPreviewMidgameForTesting(placements: 9)

        #expect(model.turnID >= 9)                             // 初期盤面から組み直されている
        #expect(model.blackCount + model.whiteCount >= 4 + 9)  // 初期4個 + 置いた数（石は返るだけ）
        #expect(model.isAITurn == false)                       // 人間の手番で止まる
        #expect(model.gameOver == false)
    }

    /// `turnID` を持たない旧形式のスナップショットが残っていても、撮影用の着手が保存対局を
    /// 上書きしないこと。以前は nil が 0 と読まれて `guard turnID == 0` を素通りし、
    /// 復元した中盤の対局に撮影用の着手が重なって `persist()` が保存を壊していた。
    @Test func doesNotOverwriteLegacySnapshot() throws {
        let store = MockSnapshotStore()
        let seed = OthelloModel(services: makeServices(store), flipSettleDelay: .zero)
        seed.tap(row: 2, col: 3)
        let saved = try #require(store.load(OthelloSnapshot.self, for: "othello"))

        // 旧形式（`turnID` を持たない）へ落として保存し直す。
        let legacy = OthelloSnapshot(
            cells: saved.cells, currentStone: saved.currentStone, humanSide: saved.humanSide,
            aiLevel: saved.aiLevel, startedAt: saved.startedAt, winner: nil, isDraw: false,
            mustPass: nil, turnID: nil, undoUsed: nil)
        try store.save(legacy, for: "othello")

        let model = OthelloModel(services: makeServices(store), flipSettleDelay: .zero)
        try #require(model.turnID == 0, "テストの前提: 旧形式は 0 手として読まれること")

        model.applyPreviewMidgameForTesting()

        let after = try #require(store.load(OthelloSnapshot.self, for: "othello"))
        #expect(after.cells == legacy.cells)   // 保存対局は撮影の着手で書き換わらない
        #expect(after.turnID == nil)
    }

    /// CPU の思考中に撮影用プレビューを適用しても、旧盤面で選んだ手が混ざらず、
    /// 「考え中」の表示も残らないこと。View は CPU 起動（`.task(id:)`）とプレビュー適用
    /// （`.task`）を並行に走らせるため、白番で始めると探索の最中にプレビューが入りうる。
    @Test func discardsStaleMoveWhenAppliedDuringThinking() async throws {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        model.newGame(humanSide: .white, aiLevel: 2)   // CPU=黒(先手) → 起動直後から CPU の手番
        try #require(model.isAITurn)

        let gate = ThinkingGate()
        model.thinkingGate = { await gate.wait() }
        let thinking = Task { await model.performAIMoveIfNeeded() }
        await gate.waitUntilArrived()
        model.thinkingGate = nil
        try #require(model.isThinking, "テストの前提: 探索の直前で止まっていること")

        model.applyPreviewMidgameForTesting()
        #expect(model.isThinking == false)   // 撮影に「考え中」が写らない

        let turnID = model.turnID, black = model.blackCount, white = model.whiteCount

        gate.release()          // 旧対局の探索はここで初めて走る（旧盤面のまま）
        await thinking.value

        #expect(model.turnID == turnID)          // 旧探索の手は入らない
        #expect(model.blackCount == black)
        #expect(model.whiteCount == white)
        #expect(model.isThinking == false)       // 旧タスクの defer にフラグを奪われない
        #expect(model.isAITurn == false)         // 人間(白)の手番で止まっている
    }
}
