import Foundation
import Testing
import Core
@testable import GameGomoku

// MARK: - ヘルパー

private func gomokuBoard(black: [(Int, Int)] = [], white: [(Int, Int)] = []) -> GomokuBoard {
    var board = GomokuBoard()
    for (row, col) in black { board[row, col] = .black }
    for (row, col) in white { board[row, col] = .white }
    return board
}

// MARK: - 禁じ手の判定（#441）

@Suite("五目並べ 連珠の禁じ手")
struct GomokuRenjuRuleTests {

    /// 三三: 一手で活三を 2 つ作る。
    /// 横 (7,5)(7,6) と 縦 (5,7)(6,7) の間に打つと、どちらも「あと 1 手で達四」になる。
    @Test func doubleThreeIsForbidden() {
        let board = gomokuBoard(black: [(7, 5), (7, 6), (5, 7), (6, 7)])
        #expect(board.renjuForbidden(row: 7, col: 7) == .doubleThree)
    }

    /// 四四: 一手で四を 2 つ作る（横 3 連と縦 3 連の交点）。
    @Test func doubleFourIsForbidden() {
        let board = gomokuBoard(black: [(7, 4), (7, 5), (7, 6), (4, 7), (5, 7), (6, 7)])
        #expect(board.renjuForbidden(row: 7, col: 7) == .doubleFour)
    }

    /// 長連: 6 つ以上の連。連珠では五にならないので打てない。
    @Test func overlineIsForbidden() {
        let board = gomokuBoard(black: [(7, 3), (7, 4), (7, 5), (7, 7), (7, 8)])
        #expect(board.renjuForbidden(row: 7, col: 6) == .overline)
    }

    /// ちょうど五は禁じ手より優先する（勝ち）。
    ///
    /// 縦が五になると同時に、横と斜めがどちらも活三になっている
    /// （＝五を無視すると三三で拒否される形）。判定の向きの順序（横 → 縦 → 斜め）に
    /// 依らないことを見るため、五は**先頭ではない向き**に置いている。
    @Test func exactFiveWinsOverForbiddenShapes() {
        let board = gomokuBoard(black: [
            (3, 7), (4, 7), (5, 7), (6, 7),   // 縦: (7,7) でちょうど五
            (7, 5), (7, 6),                   // 横: 活三
            (5, 5), (6, 6),                   // 斜め: 活三
        ])
        #expect(board.renjuForbidden(row: 7, col: 7) == nil)
    }

    /// 四三（四が 1 つ + 活三が 1 つ）は禁じ手ではない。連珠で最も普通の攻め筋。
    @Test func fourThreeIsAllowed() {
        let board = gomokuBoard(black: [(7, 4), (7, 5), (7, 6), (5, 7), (6, 7)])
        #expect(board.renjuForbidden(row: 7, col: 7) == nil)
    }

    /// 達四（両端が空いた四）は**四 1 つ**。五にできる点が 2 つあるからと二重に数えると、
    /// 最も普通の勝ち筋がいきなり四四で打てなくなる。
    @Test func straightFourCountsAsSingleFour() {
        let board = gomokuBoard(black: [(7, 4), (7, 5), (7, 6)])
        #expect(board.renjuForbidden(row: 7, col: 7) == nil)
    }

    /// 足すと 6 になる空点は四に数えない（`BBBB.B` の形）。
    ///
    /// (7,7) に足すと 6 連で五にならないため、この方向の四は (7,2) 側の 1 つだけ。
    /// 数え間違えると同じ向きだけで四四になり、打てるはずの手が拒否される。
    @Test func gapThatWouldMakeSixIsNotAFour() {
        let board = gomokuBoard(black: [(7, 3), (7, 4), (7, 5), (7, 8)])
        #expect(board.renjuForbidden(row: 7, col: 6) == nil)
    }

    /// 四になっている向きは三として数えない。
    ///
    /// 横は `.BB□B.`（(7,6) に打つと (7,7) で五 = 四）だが、(7,3) に足すと達四にもなるため
    /// 三としても読める。ここを三に数えると、縦の活三と合わせて三三になり、
    /// **四三のつもりの手が打てなくなる**。
    @Test func aFourIsNotAlsoCountedAsAThree() {
        let board = gomokuBoard(black: [(7, 4), (7, 5), (7, 8), (5, 6), (6, 6)])
        #expect(board.renjuForbidden(row: 7, col: 6) == nil)
    }

    /// 活三は「打った石を含む連」だけを数える。
    ///
    /// 横に離れた (7,10)(7,11)(7,12) は、(7,9) を足すと両端の空いた四になるが、
    /// (7,8) が空いているので **(7,7) に打った石とは無関係**。これを三に数えると、
    /// 縦の活三と合わせて三三になり、盤の反対側の形のせいで打てなくなる。
    @Test func openThreeMustContainThePlacedStone() {
        let board = gomokuBoard(black: [(7, 10), (7, 11), (7, 12), (5, 7), (6, 7)])
        #expect(board.renjuForbidden(row: 7, col: 7) == nil)
    }

    /// 石のある交点・盤外は判定の対象外（`nil`）。
    @Test func occupiedAndOutOfBoardAreNotJudged() {
        let board = gomokuBoard(black: [(7, 5), (7, 6), (5, 7), (6, 7), (7, 7)])
        #expect(board.renjuForbidden(row: 7, col: 7) == nil)      // 既に石がある
        #expect(board.renjuForbidden(row: -1, col: 7) == nil)     // 盤外
        #expect(board.renjuForbidden(row: 7, col: gomokuBoardSize) == nil)
    }
}

// MARK: - Model への接続（#441）

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

/// **黒の**三三の一歩手前の局面を、中断データとして注入する。
///
/// 交互着手で作れる形ではないので、盤面を直接組んで手番だけ指定する
/// （`moveHistory` を渡さない旧形式の経路。`cells` と `currentStone` から復元される）。
///
/// - Parameter toMove: (7,7) に打つ側。`.white` を渡すと「白が黒の三三点を止めに行く」
///   局面になる（実戦で最も普通に起きる形で、ここが拒否されると白が打てなくなる）。
private func doubleThreeSnapshot(
    toMove: GomokuStone,
    forbiddenMoves: Bool?
) -> GomokuSnapshot {
    var board = GomokuBoard()
    for (row, col) in [(7, 5), (7, 6), (5, 7), (6, 7)] { board[row, col] = .black }
    // 手数の辻褄合わせ（盤の端で、判定に絡まない位置）。
    for (row, col) in [(0, 0), (0, 14), (14, 0), (14, 14)] { board[row, col] = .white }
    return GomokuSnapshot(
        cells: board.cells.map { $0?.rawValue },
        currentStone: toMove.rawValue,
        humanSide: toMove.rawValue,
        aiLevel: 1,
        startedAt: Date(),
        moveHistory: nil,
        undoUsed: nil,
        resigned: nil,
        winner: nil,
        forbiddenMoves: forbiddenMoves
    )
}

@MainActor
@Suite("五目並べ 禁じ手ルールの適用")
struct GomokuRenjuModelTests {

    /// オフのときは従来どおり三三に打てる（既定の手触りを変えない）。
    @Test func offAllowsDoubleThree() throws {
        let store = MockSnapshotStore()
        try store.save(doubleThreeSnapshot(toMove: .black, forbiddenMoves: nil), for: "gomoku")
        let model = GomokuModel(services: makeServices(store))
        #expect(model.forbiddenMovesEnabled == false)

        model.tap(row: 7, col: 7)
        #expect(model.board[7, 7] == .black)
        #expect(model.rejectedTapCount == 0)
    }

    /// オンのとき、黒は三三へ打てず理由まで区別できる。盤は動かない。
    @Test func onRejectsBlackDoubleThree() throws {
        let store = MockSnapshotStore()
        try store.save(doubleThreeSnapshot(toMove: .black, forbiddenMoves: true), for: "gomoku")
        let model = GomokuModel(services: makeServices(store))
        #expect(model.forbiddenMovesEnabled)

        let before = model.moveCount
        model.tap(row: 7, col: 7)
        #expect(model.lastRejection == .forbidden(.doubleThree))
        #expect(model.rejectedTapCount == 1)
        #expect(model.board[7, 7] == nil)
        #expect(model.moveCount == before)
    }

    /// 白（後手）には禁じ手が無い。同じ形でも白なら打てる。
    @Test func onDoesNotRestrictWhite() throws {
        let store = MockSnapshotStore()
        try store.save(doubleThreeSnapshot(toMove: .white, forbiddenMoves: true), for: "gomoku")
        let model = GomokuModel(services: makeServices(store))
        #expect(model.forbiddenMovesEnabled)
        #expect(model.currentStone == .white)

        model.tap(row: 7, col: 7)
        #expect(model.board[7, 7] == .white)
        #expect(model.rejectedTapCount == 0)
    }

    /// 禁じ手で断られた表示は、次に打てた時点で消える（View の帯がこの値で出ている）。
    @Test func rejectionClearsOnceALegalMoveIsPlayed() throws {
        let store = MockSnapshotStore()
        try store.save(doubleThreeSnapshot(toMove: .black, forbiddenMoves: true), for: "gomoku")
        let model = GomokuModel(services: makeServices(store))

        model.tap(row: 7, col: 7)
        #expect(model.lastRejection == .forbidden(.doubleThree))

        model.tap(row: 2, col: 2)   // 何もない場所なら打てる
        #expect(model.board[2, 2] == .black)
        #expect(model.lastRejection == nil)
    }

    /// トグルの状態が中断復元をまたいで一貫すること。
    @Test func settingSurvivesSuspendAndRestore() {
        let store = MockSnapshotStore()
        let first = GomokuModel(services: makeServices(store))
        first.newGame(humanSide: .black, aiLevel: 2, forbiddenMoves: true)
        first.tap(row: 7, col: 7)

        let restored = GomokuModel(services: makeServices(store))
        #expect(restored.forbiddenMovesEnabled)
        #expect(restored.aiLevel == 2)
        #expect(restored.board[7, 7] == .black)
    }

    /// 撮影用のプレビュー（`-gomokuRenjuBlocked`）が、狙いどおり三三で断られた状態で止まること。
    /// CPU の手番になると撮影中に盤が動いてしまうので、人間（黒）の手番であることも見る。
    @Test func renjuBlockedPreviewStopsAtARejection() {
        let model = GomokuModel(services: nil)
        model.applyRenjuBlockedPreviewForTesting()

        #expect(model.forbiddenMovesEnabled)
        #expect(model.lastRejection == .forbidden(.doubleThree))
        #expect(model.board[7, 7] == nil)
        #expect(model.gameOver == false)
        #expect(model.isAITurn == false)
    }

    /// 新規対局で明示的にオフへ戻せること（前の対局の設定が残らない）。
    @Test func newGameCanTurnItBackOff() {
        let store = MockSnapshotStore()
        let model = GomokuModel(services: makeServices(store))
        model.newGame(humanSide: .black, aiLevel: 1, forbiddenMoves: true)
        #expect(model.forbiddenMovesEnabled)

        model.newGame(humanSide: .black, aiLevel: 1, forbiddenMoves: false)
        #expect(model.forbiddenMovesEnabled == false)

        let restored = GomokuModel(services: makeServices(store))
        #expect(restored.forbiddenMovesEnabled == false)
    }
}

// MARK: - CPU（#441: オン時に CPU も禁じ手を打たない）

@Suite("五目並べ 禁じ手ルールと CPU")
struct GomokuRenjuEngineTests {

    /// 黒番の CPU は、6 連になる「勝てそうに見える手」を選ばない。
    ///
    /// (7,6) は `checkWin` が真を返す（5 つ以上）ため、フィルタが無いと即勝ちとして選ばれる。
    /// 連珠では長連なので、代わりに打てる手を返さなければならない。
    @Test func blackCPUAvoidsOverline() async {
        let board = gomokuBoard(black: [(7, 3), (7, 4), (7, 5), (7, 7), (7, 8)])

        // 対照: 禁じ手オフなら、そこが唯一の 5 つ以上になる点なので必ず選ばれる。
        let free = await SimpleGomokuEngine(level: 0).bestMove(board: board, stone: .black)
        #expect(free?.row == 7 && free?.col == 6)

        let renju = await SimpleGomokuEngine(level: 0, forbiddenMoves: true)
            .bestMove(board: board, stone: .black)
        let move = try! #require(renju)
        #expect(!(move.row == 7 && move.col == 6))
        #expect(board[move.row, move.col] == nil)
        #expect(board.renjuForbidden(row: move.row, col: move.col) == nil)
    }

    /// 白番には禁じ手が無いので、オンでも 6 連の勝ちをそのまま取る。
    @Test func whiteCPUStillTakesOverline() async {
        let board = gomokuBoard(white: [(7, 3), (7, 4), (7, 5), (7, 7), (7, 8)])
        let move = await SimpleGomokuEngine(level: 0, forbiddenMoves: true)
            .bestMove(board: board, stone: .white)
        #expect(move?.row == 7 && move?.col == 6)
    }

    /// 黒番の CPU が三三へ打たないこと（長連以外の禁じ手でも候補から外れている）。
    @Test func blackCPUAvoidsDoubleThree() async {
        let board = gomokuBoard(black: [(7, 5), (7, 6), (5, 7), (6, 7)],
                                white: [(0, 0), (0, 14), (14, 0)])
        // 罠が実在することを先に固定する（形が崩れると下の期待が空振りになる）。
        #expect(board.renjuForbidden(row: 7, col: 7) == .doubleThree)

        let move = try! #require(await SimpleGomokuEngine(level: 0, forbiddenMoves: true)
            .bestMove(board: board, stone: .black))
        #expect(!(move.row == 7 && move.col == 7))
        #expect(board.renjuForbidden(row: move.row, col: move.col) == nil)
    }
}
