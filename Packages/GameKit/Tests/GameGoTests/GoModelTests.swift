import Testing
import Foundation
import Core
@testable import GameGo

/// テスト専用の中断データ置き場（ファイルに書かず、プロセス内だけで完結させる）。
private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func save<T: Codable>(_ value: T, for key: String) throws {
        storage[key] = try JSONEncoder().encode(value)
    }

    func load<T: Codable>(_ type: T.Type, for key: String) -> T? {
        guard let data = storage[key] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func clear(for key: String) { storage[key] = nil }
    func exists(for key: String) -> Bool { storage[key] != nil }
}

@MainActor
private func makeServices(_ store: SnapshotStore = MemorySnapshotStore()) -> GameServices {
    GameServices(snapshots: store, ads: NoopAdService())
}

@Suite("囲碁の対局進行")
@MainActor
struct GoModelFlowTests {

    @Test("互先の新規対局は黒番・空の盤から始まる")
    func newGameStartsEmpty() {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .black, level: .easy, handicap: 0)
        #expect(model.board.stoneCount == 0)
        #expect(model.state.sideToMove == .black)
        #expect(model.phase == .playing)
        #expect(!model.isAITurn)
        #expect(model.ruleset.komi == 6.5)
    }

    @Test("置き石ありなら黒石が並び、CPU（白）の手番から始まる")
    func handicapGameStartsWithWhite() {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .black, level: .easy, handicap: 4)
        #expect(model.board.stoneCount == 4)
        #expect(model.state.sideToMove == .white)
        #expect(model.isAITurn, "白は CPU なので CPU の手番から始まる")
        #expect(model.ruleset.komi == 0.5)
    }

    /// 置き石は「黒（人間）がハンデをもらう」仕組み。白を選んだときに置き石を残すと
    /// CPU にハンデを与えることになるので、Model 側で 0 に倒す。
    @Test("白を選んだら置き石は付かない")
    func handicapIsDroppedWhenHumanTakesWhite() {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .white, level: .easy, handicap: 4)
        #expect(model.ruleset.handicap == 0)
        #expect(model.board.stoneCount == 0)
        #expect(model.isAITurn, "黒（CPU）から始まる")
    }

    @Test("禁じ手のタップは理由つきで拒否され、盤面が変わらない")
    func illegalTapIsRejectedWithReason() {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .black, level: .easy)
        model.tap(row: 4, col: 4)
        model.applyMoveForTesting(.play(row: 2, col: 2))   // CPU の応手（人間の手番に戻す）
        let before = model.board

        model.tap(row: 4, col: 4)      // すでに石がある
        #expect(model.lastRejection == .illegal(.occupied))
        model.tap(row: -1, col: 0)     // 盤外
        #expect(model.lastRejection == .illegal(.outOfBoard))
        #expect(model.rejectedTapCount == 2)
        #expect(model.board == before)
    }

    @Test("CPU の手番中のタップは「あなたの番ではない」として拒否する")
    func tapDuringCPUTurnIsRejected() {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .black, level: .easy)
        model.tap(row: 4, col: 4)
        #expect(model.isAITurn)
        model.tap(row: 2, col: 2)
        #expect(model.lastRejection == .notYourTurn)
        #expect(model.board[2, 2] == nil)
    }

    @Test("両者パスで終局の確認に入り、そこではまだ成績を記録しない")
    func twoPassesEnterScoring() async {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .black, level: .easy)
        model.pass()
        #expect(model.phase == .playing)
        // CPU にパスさせる代わりに、白の手番でパスを差し込む（読みの時間を使わない）。
        model.forcePassForTesting()
        #expect(model.phase == .scoring)
        #expect(model.recordResult == nil, "確認の段階では記録しない")
        #expect(!model.gameOver)

        await model.evaluateEndgameIfNeeded()
        #expect(model.endgame != nil)
        // 空の盤で終局すればコミのぶん白の勝ち。
        #expect(model.endgame?.score.winner == .white)
    }

    @Test("終局の結果を承認したときにはじめて記録し、中断データを消す")
    func acceptingTheResultRecordsIt() async {
        let store = MemorySnapshotStore()
        let model = GoModel(services: makeServices(store))
        model.newGame(humanSide: .black, level: .easy)
        model.pass()
        model.forcePassForTesting()
        await model.evaluateEndgameIfNeeded()
        #expect(store.exists(for: "go"), "確認の段階では中断データが残っている")

        model.acceptEndgame()
        #expect(model.phase == .finished)
        #expect(model.gameOver)
        #expect(model.winner == .white)
        #expect(!store.exists(for: "go"), "決着したら中断データを消す")
    }

    @Test("「対局続行」で終局から打ち続けられる（簡易死活の誤判定からの復帰）")
    func resumingFromScoringReopensTheGame() async {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .black, level: .easy)
        model.pass()
        model.forcePassForTesting()
        await model.evaluateEndgameIfNeeded()
        #expect(model.endgame != nil)

        model.resumePlay()
        #expect(model.phase == .playing)
        #expect(model.endgame == nil, "続行したら前の計算結果は残さない")
        model.tap(row: 4, col: 4)
        #expect(model.board[4, 4] == .black, "続行後は打てる")
    }

    @Test("投了すると CPU の勝ちで決着し、中断データを消す")
    func resignEndsTheGame() {
        let store = MemorySnapshotStore()
        let model = GoModel(services: makeServices(store))
        model.newGame(humanSide: .black, level: .easy)
        #expect(store.exists(for: "go"))

        model.resign()
        #expect(model.phase == .finished)
        #expect(model.winner == .white)
        #expect(!store.exists(for: "go"))
        // 決着後は盤を触っても拒否として鳴らさない（結果表示が出ている状態のため）。
        let rejections = model.rejectedTapCount
        model.tap(row: 0, col: 0)
        #expect(model.rejectedTapCount == rejections)
    }

    /// 自殺手・コウは「空いているのに打てない」点なので、理由を返さないと操作不能に見える。
    @Test("自殺手は理由つきで拒否する")
    func suicideIsRejectedWithReason() {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .white, level: .easy)
        // (0,0) を黒で囲ってから、白の手番で (0,0) に打たせる。
        for move in [GoMove.play(row: 0, col: 1), .play(row: 8, col: 8), .play(row: 1, col: 0)] {
            model.applyMoveForTesting(move)
        }
        #expect(model.state.sideToMove == .white)
        model.tap(row: 0, col: 0)
        #expect(model.lastRejection == .illegal(.suicide))
        #expect(model.board[0, 0] == nil)
    }

    @Test("取った石の数を手番ごとに数える")
    func countsCaptures() {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .black, level: .easy)
        // 白 1 子を黒が取る形を、交互着手で作る。
        for (row, col) in [(0, 1), (0, 0), (1, 0), (8, 8)] {
            model.applyMoveForTesting(.play(row: row, col: col))
        }
        #expect(model.board[0, 0] == nil, "白 1 子が取れている")
        #expect(model.capturedByHuman == 1)
        #expect(model.capturedByCPU == 0)
    }
}

@Suite("囲碁の待った")
@MainActor
struct GoUndoTests {

    @Test("2 手（自分 → CPU）まとめて戻る")
    func undoRewindsTwoMoves() {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .black, level: .easy)
        model.applyMoveForTesting(.play(row: 4, col: 4))   // 黒（人間）
        model.applyMoveForTesting(.play(row: 2, col: 2))   // 白（CPU）
        #expect(model.canUndo)

        model.undoLastExchange()
        #expect(model.moveCount == 0)
        #expect(model.board[4, 4] == nil)
        #expect(model.board[2, 2] == nil)
        #expect(model.undoUsed, "2 回目からは広告視聴が要る")
        #expect(model.state.sideToMove == .black)
    }

    @Test("1 手しか進んでいなければ戻せない")
    func cannotUndoBeforeTwoMoves() {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .black, level: .easy)
        #expect(!model.canUndo)
        model.applyMoveForTesting(.play(row: 4, col: 4))
        #expect(!model.canUndo, "CPU の応手が返る前は戻せない")
    }

    /// 「対局続行」を通ると手順に連続パスが残る。待ったでそこまで巻き戻したとき、再生した局面が
    /// 終局判定のままだと以後どこにも打てなくなる（#426）。
    @Test("「対局続行」後の待ったで局面が終局に戻らない")
    func undoAfterResumeKeepsTheGamePlayable() {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .black, level: .easy)
        model.pass()                                       // 黒（人間）
        model.forcePassForTesting()                        // 白（CPU）
        #expect(model.phase == .scoring)

        model.resumePlay()
        model.applyMoveForTesting(.play(row: 4, col: 4))   // 黒（人間）
        model.applyMoveForTesting(.play(row: 2, col: 2))   // 白（CPU）
        #expect(model.canUndo)

        model.undoLastExchange()
        #expect(model.moveCount == 2, "残るのは続行前の 2 手（両者パス）")
        #expect(model.board[4, 4] == nil)
        #expect(model.phase == .playing)
        #expect(!model.state.isTwoPassEnd, "待ったで終局判定が復活してはいけない")

        model.tap(row: 4, col: 4)
        #expect(model.board[4, 4] == .black, "戻した局面から打ち直せる")
    }

    @Test("戻した局面から打ち直せる（取った石も戻る）")
    func undoRestoresCapturedStones() {
        let model = GoModel(services: makeServices())
        model.newGame(humanSide: .black, level: .easy)
        for (row, col) in [(0, 1), (0, 0), (1, 0), (8, 8)] {
            model.applyMoveForTesting(.play(row: row, col: col))
        }
        #expect(model.capturedByHuman == 1)

        model.undoLastExchange()   // (1,0) と (8,8) を戻す
        #expect(model.board[0, 0] == .white, "取られた白石が戻っている")
        #expect(model.capturedByHuman == 0, "取った石の数も戻る")
    }
}

@Suite("囲碁の中断・再開")
@MainActor
struct GoSnapshotTests {

    @Test("中断した局面・設定・手数がそのまま戻る")
    func restoresPosition() {
        let store = MemorySnapshotStore()
        let first = GoModel(services: makeServices(store))
        first.newGame(humanSide: .white, level: .hard, handicap: 0)
        first.applyMoveForTesting(.play(row: 3, col: 3))   // 黒（CPU）
        first.applyMoveForTesting(.play(row: 5, col: 5))   // 白（人間）

        let restored = GoModel(services: makeServices(store))
        #expect(restored.board[3, 3] == .black)
        #expect(restored.board[5, 5] == .white)
        #expect(restored.moveCount == 2)
        #expect(restored.humanSide == .white)
        #expect(restored.aiLevel == .hard)
        #expect(restored.phase == .playing)
        #expect(restored.lastMove == GoPoint(row: 5, col: 5))
    }

    @Test("置き石とコミも復元する")
    func restoresRuleset() {
        let store = MemorySnapshotStore()
        let first = GoModel(services: makeServices(store))
        first.newGame(humanSide: .black, level: .normal, handicap: 5)

        let restored = GoModel(services: makeServices(store))
        #expect(restored.ruleset.handicap == 5)
        #expect(restored.ruleset.komi == 0.5)
        #expect(restored.board.stoneCount == 5)
    }

    @Test("終局の確認中に中断しても、再開すれば計算し直せる")
    func restoresScoringPhase() async {
        let store = MemorySnapshotStore()
        let first = GoModel(services: makeServices(store))
        first.newGame(humanSide: .black, level: .easy)
        first.pass()
        first.forcePassForTesting()
        #expect(first.phase == .scoring)

        let restored = GoModel(services: makeServices(store))
        #expect(restored.phase == .scoring)
        #expect(restored.endgame == nil, "計算結果は保存しない（同じ局面から作り直せる）")
        await restored.evaluateEndgameIfNeeded()
        #expect(restored.endgame != nil)
    }

    /// 保存するのは手順なので、「対局続行」で解いた終局判定も再生し直す必要がある。
    /// 解かずに再生すると連続パス以降の手が全部捨てられ、盤面が壊れたうえに打てなくなる（#426）。
    @Test("「対局続行」後に着手してから中断しても、続きの局面がそのまま戻る")
    func restoresPositionAfterResumingFromScoring() {
        let store = MemorySnapshotStore()
        let first = GoModel(services: makeServices(store))
        first.newGame(humanSide: .black, level: .easy)
        first.pass()                                       // 黒（人間）
        first.forcePassForTesting()                        // 白（CPU）
        first.resumePlay()
        first.applyMoveForTesting(.play(row: 4, col: 4))   // 黒（人間）
        first.applyMoveForTesting(.play(row: 2, col: 2))   // 白（CPU）

        let restored = GoModel(services: makeServices(store))
        #expect(restored.phase == .playing)
        #expect(restored.moveCount == 4)
        #expect(restored.board[4, 4] == .black, "続行後の手が再生されている")
        #expect(restored.board[2, 2] == .white)
        #expect(restored.lastMove == GoPoint(row: 2, col: 2))
        #expect(!restored.state.isTwoPassEnd)

        restored.tap(row: 6, col: 6)
        #expect(restored.board[6, 6] == .black, "再開後も打てる")
    }

    /// 続行した直後に中断すると、手順の末尾が連続パスのまま `phase == .playing` で保存される。
    @Test("「対局続行」の直後に中断しても、再開したら打てる")
    func restoresPlayableStateWhenSuspendedRightAfterResuming() {
        let store = MemorySnapshotStore()
        let first = GoModel(services: makeServices(store))
        first.newGame(humanSide: .black, level: .easy)
        first.pass()
        first.forcePassForTesting()
        first.resumePlay()

        let restored = GoModel(services: makeServices(store))
        #expect(restored.phase == .playing)
        #expect(restored.moveCount == 2, "パスも手順として残す")
        #expect(!restored.state.isTwoPassEnd)

        restored.tap(row: 4, col: 4)
        #expect(restored.board[4, 4] == .black)
    }

    /// 保存するのは**手順**で、局面は再生して作る。盤面そのものを保存する形にすると
    /// 位置的スーパーコウの履歴が失われ、再開したあとだけ同一盤面の再現が通ってしまう。
    @Test("再開後もスーパーコウの履歴を持っている（局面ではなく手順を保存しているため）")
    func restoresSuperkoHistory() {
        let store = MemorySnapshotStore()
        let first = GoModel(services: makeServices(store))
        first.newGame(humanSide: .black, level: .easy)
        for move in [GoMove.play(row: 0, col: 0), .play(row: 8, col: 8),
                     .play(row: 0, col: 1), .play(row: 8, col: 7)] {
            first.applyMoveForTesting(move)
        }
        let restored = GoModel(services: makeServices(store))
        #expect(restored.state.tracksSuperko)
        #expect(restored.board == first.board)
        #expect(restored.moveCount == first.moveCount)
    }
}

// MARK: - テスト用の入り口
//
// 対局の進行そのものを確かめたいテストで、毎回 MCTS を回すと時間ばかりかかる。
// CPU の手番でも「この手を指す」と直接指定できる入り口をテスト側にだけ用意する。

extension GoModel {
    /// 手番を問わず 1 手進める（CPU の応手を指定するのに使う）。
    @MainActor
    func applyMoveForTesting(_ move: GoMove) {
        apply(move)
    }

    /// 手番を問わずパスする。
    @MainActor
    func forcePassForTesting() {
        apply(.pass)
    }
}
