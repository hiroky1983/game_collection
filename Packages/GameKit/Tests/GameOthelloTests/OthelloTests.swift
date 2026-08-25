import Testing
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
