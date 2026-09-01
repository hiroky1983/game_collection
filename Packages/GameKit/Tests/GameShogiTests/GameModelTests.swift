import Testing
import Foundation
import Core
@testable import GameShogi

@MainActor
@Suite("対局モデル（人間→CPU の流れ）")
struct ShogiGameModelTests {
    @Test func humanMoveThenAIReplies() async {
        let model = ShogiGameModel(services: nil)
        // 既定は人間=先手 / CPU=後手。
        #expect(model.humanSide == .black)
        #expect(model.isAITurn == false)

        // 人間(先手)が 7g7f（選択→着手先タップ）。
        model.tapSquare(Sq.fromUSI("7g")!)
        #expect(model.selectedSquare == Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        #expect(model.moves.count == 1)
        #expect(model.moves.last?.usi == "7g7f")

        // 手番は後手(CPU)。AI が応手する。
        #expect(model.isAITurn)
        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 2)
        #expect(model.gameOver == false)
        // 応手後は再び先手(人間)番。
        #expect(model.isAITurn == false)
    }

    @Test func humanCannotMoveDuringCPUTurn() {
        let model = ShogiGameModel(services: nil)
        // 人間(先手)が一手指すと CPU(後手)の手番。
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        #expect(model.isAITurn)
        let movesBefore = model.moves.count
        // CPU の手番中に後手の駒を触っても何も起きない。
        model.tapSquare(Sq.fromUSI("3c")!) // 後手の歩
        #expect(model.selectedSquare == nil)
        model.tapSquare(Sq.fromUSI("3d")!)
        #expect(model.moves.count == movesBefore) // 手が増えない
    }

    @Test func newGameAsGoteMakesAIMoveFirst() async {
        let model = ShogiGameModel(services: nil)
        model.newGame(humanSide: .white) // 人間後手 → CPU が先手で初手を指す
        #expect(model.isAITurn)
        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 1)
    }

    @Test func undoLastExchangeRemovesHumanAndCPUMoves() async {
        let model = ShogiGameModel(services: nil)
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 2)
        #expect(model.canUndo)

        model.undoLastExchange()
        #expect(model.moves.isEmpty)
        #expect(model.isAITurn == false)
        #expect(model.canUndo == false)
        #expect(model.position.squares[Sq.fromUSI("7f")!] == nil)
    }
}

// MARK: - CPU 起動トリガー（#82: 後手を選ぶと CPU が初手を指さない）

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
@Suite("CPU 起動トリガー")
struct ShogiAITurnKeyTests {
    /// View は `.task(id: model.aiTurnKey)` で CPU を起動する。
    /// 起動直後（0 手）に後手を選んでも手数が 0 のままなので、キーが変わらないと初手が指されない。
    @Test func aiTurnKeyChangesWhenStartingAsGoteWithoutMoves() {
        let model = ShogiGameModel(services: nil)
        #expect(model.moves.isEmpty)
        let before = model.aiTurnKey

        model.newGame(humanSide: .white)
        #expect(model.moves.isEmpty) // 手数は 0 のまま
        #expect(model.aiTurnKey != before) // それでもトリガーは変化する
        #expect(model.isAITurn)
    }

    /// 後手開始 → CPU 初手 → 人間応手 → 再び CPU 番、まで通しで動くこと。
    @Test func goteStartPlaysCPUFirstMoveThenHumanReply() async {
        let model = ShogiGameModel(services: nil)
        model.newGame(humanSide: .white)

        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 1)
        #expect(model.isAITurn == false) // 人間(後手)の番
        let afterCPU = model.aiTurnKey

        // 人間(後手)が 3c3d を指す。
        model.tapSquare(Sq.fromUSI("3c")!)
        model.tapSquare(Sq.fromUSI("3d")!)
        #expect(model.moves.count == 2)
        #expect(model.moves.last?.usi == "3c3d")
        #expect(model.aiTurnKey != afterCPU)
        #expect(model.isAITurn) // CPU(先手)の番に戻る
    }

    /// 先手を選んだ場合は従来どおり CPU は動かず、人間の手番から始まる。
    @Test func senteStartKeepsHumanTurn() async {
        let model = ShogiGameModel(services: nil)
        model.newGame(humanSide: .black)
        #expect(model.isAITurn == false)
        await model.performAIMoveIfNeeded()
        #expect(model.moves.isEmpty)
    }

    /// 「続きから」再開時も手番の判定が保存内容どおりに復元される。
    @Test func resumedGameRestoresSides() {
        let store = MockSnapshotStore()
        let first = ShogiGameModel(services: makeServices(store))
        first.newGame(humanSide: .white)

        let resumed = ShogiGameModel(services: makeServices(store))
        #expect(resumed.humanSide == .white)
        #expect(resumed.moves.isEmpty)
        #expect(resumed.isAITurn) // 再開直後は CPU(先手)の番
    }
}

// MARK: - 思考中の新規対局（#145: 旧タスクの思考フラグで新しい対局の CPU が止まる）

/// 思考タスクを探索の開始直前で止めておくためのゲート（#172。オセロ側と同じ仕組み）。
///
/// 以前は「思考タスクを積んだ直後に空タスクを積む」という MainActor のジョブ順序で待ち合わせて
/// いたが、これは「空タスクが走る時点で探索がまだ終わっていない」ことまでは保証できない。
/// 将棋は探索が重いぶん実際には落ちていなかったが、穴はオセロ（#172 で顕在化）と同じであるため
/// 同じ方式へ揃える。`Task.sleep` でフラグを見張る形に戻さないこと（#145 / #152）。
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
@Suite("将棋 思考中の新規対局")
struct ShogiNewGameDuringThinkingTests {
    /// CPU の思考を開始し、探索の直前で止まっている状態にして返す。
    ///
    /// ゲートは一度到達したら外す（`thinkingGate = nil`）。停止中の旧タスクはすでにゲートの中に
    /// いるため影響を受けず、以降に始まる新しい対局の思考は素通りする。
    private func startThinking(_ model: ShogiGameModel) async throws -> (task: Task<Void, Never>, gate: ThinkingGate) {
        let gate = ThinkingGate()
        model.thinkingGate = { await gate.wait() }
        let task = Task { await model.performAIMoveIfNeeded() }
        await gate.waitUntilArrived()
        model.thinkingGate = nil
        try #require(model.isThinking, "テストの前提: 旧対局の思考が計算中であること")
        return (task, gate)
    }

    /// CPU の思考中に新規対局を始めたら、旧局面で選んだ手が新しい局面に指されないこと
    /// （PR #144 と同じ回帰テスト）。
    ///
    /// ここでは新旧どちらも「初期局面・CPU が先手」なので、旧局面で選んだ手は新しい局面でも
    /// **合法**になる。将棋の合法性チェックだけでは弾けない最悪ケースで、世代（`aiTurnKey`）の
    /// 一致を見て初めて弾ける（#145）。併せて、旧タスクの完了を待たずに思考フラグが解放される
    /// ことも確かめる。修正前は `isThinking` が true のまま残り、新しい対局の `.task(id:)` が
    /// `guard !isThinking` で即 return して CPU が初手を指さなかった。
    @Test func newGameDuringThinkingDiscardsStaleMove() async throws {
        let model = ShogiGameModel(services: nil)
        model.newGame(humanSide: .white, aiLevel: 2) // CPU=先手
        #expect(model.isAITurn)

        let (thinking, gate) = try await startThinking(model)

        model.newGame(humanSide: .white, aiLevel: 2) // 思考中に新規対局
        #expect(model.isThinking == false)           // 新しい対局の CPU を起動できる

        gate.release()                     // 旧対局の探索はここで初めて走る（旧局面のまま）
        await thinking.value               // 旧対局の計算が終わるまで待つ
        #expect(model.moves.isEmpty)       // 旧局面で選んだ手は入っていない
        #expect(model.isThinking == false) // 旧タスクの defer にフラグを奪われない
        #expect(model.isAITurn)            // 新しい対局は CPU(先手)の手番のまま
    }

    /// 思考中に新規対局を始めても、新しい対局で CPU が手番どおり初手を指すこと（#145 の主症状）。
    /// View の `.task(id: model.aiTurnKey)` は旧タスクの完了を待たずに再起動するため、ここでも待たずに呼ぶ。
    @Test func cpuPlaysFirstMoveAfterNewGameDuringThinking() async throws {
        let model = ShogiGameModel(services: nil)
        model.newGame(humanSide: .white, aiLevel: 2)
        let (thinking, gate) = try await startThinking(model)

        model.newGame(humanSide: .white, aiLevel: 2)
        await model.performAIMoveIfNeeded() // `.task(id:)` の再起動に相当（ゲートは外れている）

        #expect(model.moves.count == 1)  // CPU(先手)の初手が指された
        #expect(model.isAITurn == false) // 人間(後手)の番

        gate.release()
        await thinking.value
        #expect(model.moves.count == 1)  // 旧タスクは新しい局面に指さない
    }
}

// MARK: - 千日手と終局表示の復元（#375）

@MainActor
@Suite("千日手")
struct ShogiRepetitionTests {

    /// 双方が飛車を横に往復させて元の局面に戻る 4 手 1 組の循環。
    /// ▲2h3h △8b7b ▲3h2h △7b8b で初期局面（先手番）へ戻る。
    /// 飛車を使うのは、動きが完全に可逆な駒だから（金は斜め後ろへ戻れない）。
    private static let cycle = ["2h3h", "8b7b", "3h2h", "7b8b"]

    /// 人間 vs 人間にして、CPU の手が割り込まない状態で `cycle` を n 周ぶん指す。
    @MainActor
    private func playCycles(_ count: Int, on model: ShogiGameModel) {
        for _ in 0..<count {
            for usi in Self.cycle {
                let move = Move.fromUSI(usi)!
                #expect(model.legalMovesCache.contains(move), "\(usi) は合法手のはず")
                model.apply(move)
            }
        }
    }

    @MainActor
    private func humanVsHumanModel(_ store: MockSnapshotStore) -> ShogiGameModel {
        let model = ShogiGameModel(services: makeServices(store))
        model.sente = .human
        model.gote = .human
        return model
    }

    @Test("同一局面が 2 回・3 回では終局しない")
    func doesNotEndBeforeFourthOccurrence() {
        let model = humanVsHumanModel(MockSnapshotStore())
        playCycles(2, on: model)   // 初期局面の出現は 0・4・8 手目の 3 回
        #expect(model.moves.count == 8)
        #expect(model.gameOver == false)
        #expect(model.resultText == nil)
    }

    @Test("同一局面が 4 回現れたら千日手で引き分けになる")
    func fourfoldRepetitionEndsAsDraw() {
        let model = humanVsHumanModel(MockSnapshotStore())
        playCycles(3, on: model)   // 0・4・8・12 手目で 4 回目
        #expect(model.moves.count == 12)
        #expect(model.gameOver)
        #expect(model.resultText == "引き分け（千日手）")
        #expect(model.phase == .review)
    }

    @Test("千日手はアプリを再起動しても引き分けのまま復元される")
    func repetitionSurvivesRestart() {
        let store = MockSnapshotStore()
        let model = humanVsHumanModel(store)
        playCycles(3, on: model)
        #expect(model.resultText == "引き分け（千日手）")

        let resumed = ShogiGameModel(services: makeServices(store))
        #expect(resumed.gameOver)
        #expect(resumed.resultText == "引き分け（千日手）")
        #expect(resumed.phase == .review)
    }

    @Test("詰みで終わった対局を再起動しても勝敗表示が残る（#375）")
    func checkmateResultSurvivesRestart() throws {
        let store = MockSnapshotStore()
        // 先手: 6c/5c/4c 金 + 1i 玉、後手: 5a 玉のみ。▲5c5b で 5a 玉は詰み。
        try store.save(
            ShogiSnapshot(
                initialSfen: "4k4/9/3GGG3/9/9/9/9/9/8K b - 1",
                moves: [], phase: .playing, reviewPly: nil,
                sente: .human, gote: .human, aiLevel: nil,
                startedAt: Date(), undoUsed: false
            ),
            for: "shogi"
        )
        let model = ShogiGameModel(services: makeServices(store))
        let mate = Move.fromUSI("5c5b")!
        #expect(model.legalMovesCache.contains(mate), "5c5b は合法手のはず")
        model.apply(mate)
        #expect(model.gameOver)
        #expect(model.resultText == "後手の負け（詰み）")

        let resumed = ShogiGameModel(services: makeServices(store))
        #expect(resumed.gameOver)
        #expect(
            resumed.resultText == "後手の負け（詰み）",
            "再起動で決着の文字が消えてはいけない。実際: \(String(describing: resumed.resultText))"
        )
    }
}
