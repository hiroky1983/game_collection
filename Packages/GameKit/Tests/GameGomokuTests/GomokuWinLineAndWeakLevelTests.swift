import Foundation
import Testing
import Core
@testable import GameGomoku
import CoreTestSupport
import GameKitTestSupport

// MARK: - ヘルパー

/// テスト用の決定論的な乱数（SplitMix 系の混ぜ込み付き LCG）。
private struct TestRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// 連番から散らばった種を作る（連番のまま渡すと LCG の初手が似通う）。
private func spreadSeed(_ i: Int, salt: UInt64 = 0) -> UInt64 {
    (UInt64(i) &+ salt &+ 1) &* 0x9E3779B97F4A7C15
}

private func makeBoard(black: [(Int, Int)] = [], white: [(Int, Int)] = []) -> GomokuBoard {
    var board = GomokuBoard()
    for (row, col) in black { board[row, col] = .black }
    for (row, col) in white { board[row, col] = .white }
    return board
}

/// 黒（人間）が横に四つ並べ、(7,7) に打てば五になる局面を中断データとして作る。
/// `winner` だけを渡すと (7,7) まで打ち終えた決着後、`resigned` も渡すと投了後の中断データになる。
private func blackFourSnapshot(winner: GomokuStone? = nil, resigned: Bool? = nil) -> GomokuSnapshot {
    var ordered: [(Int, Int, GomokuStone)] = [
        (7, 3, .black), (0, 0, .white),
        (7, 4, .black), (0, 14, .white),
        (7, 5, .black), (14, 0, .white),
        (7, 6, .black), (14, 14, .white),
    ]
    if winner != nil, resigned == nil { ordered.append((7, 7, .black)) }
    var board = GomokuBoard()
    for (row, col, stone) in ordered { board[row, col] = stone }
    return GomokuSnapshot(
        cells: board.cells.map { $0?.rawValue },
        currentStone: GomokuStone.black.rawValue,
        humanSide: GomokuStone.black.rawValue,
        aiLevel: 0,
        startedAt: Date(),
        moveHistory: ordered.map { GomokuMoveRecord(row: $0.0, col: $0.1, stone: $0.2.rawValue) },
        undoUsed: nil,
        resigned: resigned,
        winner: winner?.rawValue,
        forbiddenMoves: nil
    )
}

// MARK: - 勝ち筋の座標（#665）

@Suite("五目並べ 勝ち筋の座標")
struct GomokuWinningLineTests {

    @Test func horizontalLineIsOrderedEndToEnd() {
        let board = makeBoard(black: (3..<8).map { (7, $0) })
        #expect(board.winningLine(row: 7, col: 5) == (3..<8).map { GomokuPoint(row: 7, col: $0) })
    }

    @Test func antiDiagonalLineIsOrderedEndToEnd() {
        let board = makeBoard(white: (0..<5).map { (4 + $0, 10 - $0) })
        #expect(board.winningLine(row: 6, col: 8) == (0..<5).map { GomokuPoint(row: 4 + $0, col: 10 - $0) })
    }

    /// 自由五目では長連も勝ち。光らせるのは連全体。
    @Test func overlineReturnsTheWholeRun() {
        let board = makeBoard(black: (2..<8).map { ($0, 9) })
        #expect(board.winningLine(row: 2, col: 9)?.count == 6)
    }

    @Test func fourOrEmptyHasNoLine() {
        let board = makeBoard(black: (0..<4).map { (7, $0) })
        #expect(board.winningLine(row: 7, col: 3) == nil)
        #expect(board.winningLine(row: 0, col: 0) == nil)
    }

    /// 判定は `checkWin` と一致し、返す座標は交点を含む同色の一直線の連であること。
    @Test func agreesWithCheckWinOnRandomBoards() {
        var rng = TestRNG(state: 665)
        for _ in 0..<300 {
            var board = GomokuBoard()
            for i in 0..<(gomokuBoardSize * gomokuBoardSize) where Int.random(in: 0..<10, using: &rng) < 6 {
                board[i / gomokuBoardSize, i % gomokuBoardSize] = Bool.random(using: &rng) ? .black : .white
            }
            for row in 0..<gomokuBoardSize {
                for col in 0..<gomokuBoardSize {
                    let line = board.winningLine(row: row, col: col)
                    #expect((line != nil) == board.checkWin(row: row, col: col))
                    guard let line else { continue }
                    #expect(line.count >= 5)
                    #expect(line.contains(GomokuPoint(row: row, col: col)))
                    #expect(line.allSatisfy { board[$0.row, $0.col] == board[row, col] })
                    let dr = line[1].row - line[0].row, dc = line[1].col - line[0].col
                    #expect(zip(line, line.dropFirst()).allSatisfy { $1.row - $0.row == dr && $1.col - $0.col == dc })
                }
            }
        }
    }
}

// MARK: - Model の勝ち筋（#665）

@MainActor
@Suite("五目並べ 勝ち筋の状態")
struct GomokuWinningLineModelTests {

    @Test func winningMoveSetsLineAndNewGameClearsIt() throws {
        let store = MemorySnapshotStore()
        try store.save(blackFourSnapshot(), for: "gomoku")
        let model = GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.winningLine == nil)

        model.tap(row: 7, col: 7)
        #expect(model.winner == .black)
        #expect(model.winningLine == (3...7).map { GomokuPoint(row: 7, col: $0) })

        model.newGame(humanSide: .black, aiLevel: 0)
        #expect(model.winningLine == nil)
    }

    /// 投了は盤上に五が無いので光らせない。
    @Test func resignHasNoLine() throws {
        let store = MemorySnapshotStore()
        try store.save(blackFourSnapshot(), for: "gomoku")
        let model = GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.resign()
        #expect(model.gameOver)
        #expect(model.winningLine == nil)
    }

    /// 決着を書いた中断データからでも、直前手から勝ち筋を引き直す（撮影・復元の経路）。
    @Test func restoredWinnerRedrawsLine() throws {
        let store = MemorySnapshotStore()
        try store.save(blackFourSnapshot(winner: .black), for: "gomoku")
        let model = GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.winner == .black)
        #expect(model.winningLine?.count == 5)

        let resignedStore = MemorySnapshotStore()
        try resignedStore.save(blackFourSnapshot(winner: .white, resigned: true), for: "gomoku")
        let resigned = GomokuModel(services: GameServices(snapshots: resignedStore, ads: NoopAdService()))
        #expect(resigned.winner == .white)
        #expect(resigned.winningLine == nil)
    }

    @Test func winLineAnimationIsThreeTenthsOfASecond() {
        #expect(GomokuMotion.winLineDuration == 0.3)
    }
}

// MARK: - 「弱」の穴（#665）

/// CPU（白）が止めないと黒が五になる局面と、その唯一の防ぎ点。
private let blackFourPositions: [(board: GomokuBoard, block: (Int, Int))] = [
    (makeBoard(black: [(7, 3), (7, 4), (7, 5), (7, 6)], white: [(7, 2)]), (7, 7)),
    (makeBoard(black: [(3, 10), (4, 10), (5, 10), (6, 10)], white: [(2, 10)]), (7, 10)),
    (makeBoard(black: [(2, 2), (3, 3), (4, 4), (5, 5)], white: [(1, 1)]), (6, 6)),
    (makeBoard(black: [(9, 3), (9, 4), (9, 6), (9, 7)], white: [(1, 13)]), (9, 5)),
]

@Suite("五目並べ 弱の穴")
struct GomokuWeakLevelTests {

    /// 相手の四を防ぐのは半分程度。旧「弱」は必ず防いでいた（深さ3の読み + 即防ぎ）。
    @Test func weakMissesAboutHalfOfTheBlocks() async {
        var blocked = 0, total = 0
        for (index, position) in blackFourPositions.enumerated() {
            #expect(position.board.checkWin(row: position.block.0, col: position.block.1) == false)
            for i in 0..<100 {
                let engine = SimpleGomokuEngine(level: 0, seed: spreadSeed(i, salt: UInt64(index) << 32))
                let move = await engine.bestMove(board: position.board, stone: .white)
                total += 1
                if move?.row == position.block.0 && move?.col == position.block.1 { blocked += 1 }
            }
        }
        let rate = Double(blocked) / Double(total)
        #expect((0.4...0.6).contains(rate), "弱の防御率が \(rate)（400 回中 \(blocked) 回）")
    }

    /// 対照: 穴を塞いだ（防御率 1）弱と「普通」は、同じ局面を必ず防ぐ。
    @Test func withoutTheHoleEveryBlockIsFound() async {
        for position in blackFourPositions {
            for i in 0..<20 {
                let engine = SimpleGomokuEngine(level: 0, seed: spreadSeed(i), weakBlockRate: 1)
                let move = await engine.bestMove(board: position.board, stone: .white)
                #expect(move?.row == position.block.0 && move?.col == position.block.1)
            }
            let normal = await SimpleGomokuEngine(level: 1).bestMove(board: position.board, stone: .white)
            #expect(normal?.row == position.block.0 && normal?.col == position.block.1)
        }
    }

    /// 自分の五は見逃さない（相手の四が同時にあっても勝ちを取る）。
    @Test func weakAlwaysTakesItsOwnWin() async {
        let board = makeBoard(black: [(7, 3), (7, 4), (7, 5), (7, 6)],
                              white: [(3, 10), (4, 10), (5, 10), (6, 10)])
        for i in 0..<50 {
            let move = await SimpleGomokuEngine(level: 0, seed: spreadSeed(i)).bestMove(board: board, stone: .white)
            #expect(move?.row == 7 && move?.col == 10 || move?.row == 2 && move?.col == 10)
        }
    }
}

// MARK: - 候補手の並び（#812）

@Suite("五目並べ 候補手の並びが全順序")
struct GomokuCandidateOrderTests {

    /// 中心からの距離 → 行 → 列の順に厳密に増える（同点を Set の走査順に任せない）。
    /// 修正前は距離だけで並べていたので、同じ距離の升の順序がプロセスごとに入れ替わっていた。
    @Test func candidatesAreSortedByDistanceThenCoordinate() {
        let center = gomokuBoardSize / 2
        let boards = [
            makeBoard(black: [(7, 7)]),
            makeBoard(black: [(7, 3), (7, 4), (7, 5), (7, 6)], white: [(3, 10), (4, 10), (5, 10), (6, 10)]),
            makeBoard(black: [(0, 0), (14, 14)], white: [(0, 14), (14, 0)]),
        ]
        for board in boards {
            let moves = SimpleGomokuEngine(level: 0).candidateMoves(board: board)
            #expect(moves.count > 1)
            for (a, b) in zip(moves, moves.dropFirst()) {
                let da = abs(a.0 - center) + abs(a.1 - center)
                let db = abs(b.0 - center) + abs(b.1 - center)
                #expect((da, a.0, a.1) < (db, b.0, b.1), "\(a) と \(b) の並びが全順序になっていない")
            }
        }
    }

    /// 中心から等距離の防ぎ点が2つあるとき、防ぐなら行の小さい方を選ぶ（起動ごとに変わらない）。
    @Test func tiedBlocksAreChosenByCoordinate() async {
        let board = makeBoard(black: [(2, 3), (2, 4), (2, 5), (2, 6), (12, 3), (12, 4), (12, 5), (12, 6)],
                              white: [(2, 2), (12, 2)])
        for i in 0..<20 {
            let move = await SimpleGomokuEngine(level: 0, seed: spreadSeed(i), weakBlockRate: 1)
                .bestMove(board: board, stone: .white)
            #expect(move?.row == 2 && move?.col == 7)
        }
    }

    /// 中心から等距離の即勝ちが2つあるとき、行の小さい方を取る。
    @Test func tiedWinsAreChosenByCoordinate() async {
        let board = makeBoard(black: [(2, 2), (12, 2)],
                              white: [(2, 3), (2, 4), (2, 5), (2, 6), (12, 3), (12, 4), (12, 5), (12, 6)])
        for i in 0..<20 {
            let move = await SimpleGomokuEngine(level: 0, seed: spreadSeed(i)).bestMove(board: board, stone: .white)
            #expect(move?.row == 2 && move?.col == 7)
        }
    }
}

// MARK: - 「弱」の勝率（#665）

private enum TestPlayer {
    /// 弱（`blockRate` を変えると穴の大きさだけが変わる）。
    case weak(blockRate: Double)
    /// 既存の石から2マス以内へ一様に乱択する。
    case random
}

private func move(by player: TestPlayer, board: GomokuBoard, stone: GomokuStone,
                  seed: UInt64) async -> (row: Int, col: Int)? {
    switch player {
    case .weak(let blockRate):
        return await SimpleGomokuEngine(level: 0, seed: seed, weakBlockRate: blockRate)
            .bestMove(board: board, stone: stone)
    case .random:
        var near: [(Int, Int)] = []
        for row in 0..<gomokuBoardSize {
            for col in 0..<gomokuBoardSize where board[row, col] == nil {
                let hasNeighbor = (max(0, row - 2)...min(gomokuBoardSize - 1, row + 2)).contains { r in
                    (max(0, col - 2)...min(gomokuBoardSize - 1, col + 2)).contains { c in board[r, c] != nil }
                }
                if hasNeighbor { near.append((row, col)) }
            }
        }
        guard !near.isEmpty else { return (gomokuBoardSize / 2, gomokuBoardSize / 2) }
        var rng = TestRNG(state: seed)
        let pick = near[Int.random(in: 0..<near.count, using: &rng)]
        return (pick.0, pick.1)
    }
}

/// `subject` を黒・白交互に持たせて `games` 局打ち、`subject` の勝ち数を返す。
private func wins(of subject: TestPlayer, against opponent: TestPlayer, games: Int, salt: UInt64) async -> Int {
    var won = 0
    for game in 0..<games {
        let subjectStone: GomokuStone = game % 2 == 0 ? .black : .white
        var board = GomokuBoard()
        var stone = GomokuStone.black
        for ply in 0..<(gomokuBoardSize * gomokuBoardSize) {
            let player = stone == subjectStone ? subject : opponent
            let seed = spreadSeed(game * 1000 + ply, salt: salt)
            guard let m = await move(by: player, board: board, stone: stone, seed: seed),
                  board[m.row, m.col] == nil else {
                Issue.record("打てない手が返った（\(game) 局目 \(ply) 手目）")
                return won
            }
            board[m.row, m.col] = stone
            if board.checkWin(row: m.row, col: m.col) {
                if stone == subjectStone { won += 1 }
                break
            }
            stone = stone.opponent
        }
    }
    return won
}

@Suite("五目並べ 弱の勝率")
struct GomokuWeakWinRateTests {

    /// 下限: 弱くしても、でたらめに打つ相手には勝てる（勝負として成立する）。
    @Test func weakStillBeatsARandomMover() async {
        let games = 40
        let won = await wins(of: .weak(blockRate: SimpleGomokuEngine.defaultWeakBlockRate),
                             against: .random, games: games, salt: 1)
        print("weak vs random: \(won)/\(games)")
        #expect(won >= games * 9 / 10, "弱がでたらめな相手に \(won)/\(games) しか勝てない")
    }

    /// 上限: 穴（四の見逃し）を持たない同じ CPU には負け越す。旧「弱」は読みを持つぶんこの相手に勝ち越す。
    @Test func weakLosesToTheSamePlayerWithoutTheHole() async {
        let games = 40
        let won = await wins(of: .weak(blockRate: SimpleGomokuEngine.defaultWeakBlockRate),
                             against: .weak(blockRate: 1), games: games, salt: 2)
        print("weak vs no-hole: \(won)/\(games)")
        #expect(won <= games * 4 / 10, "穴のない相手に \(won)/\(games) 勝っている（弱の穴が効いていない）")
    }
}

// MARK: - 待ったの文言（#665）

@Suite("待ったの確認文言が2手戻しと一致する")
struct UndoWordingMatchesTwoPlyUndoTests {

    /// 5 ゲームとも `undoLastExchange` で「自分の1手 + CPU の応手」を戻す。
    /// 文言は Core の `BoardUndoButton` 1 か所に寄せた（#828）ので、各ゲームは部品を通っていることと、
    /// 1手だけ戻るような文言を持ち直していないことを見る。
    @Test(arguments: [
        "GameGomoku/GomokuView.swift",
        "GameShogi/ShogiView.swift",
        "GameGo/GoView.swift",
        "GameOthello/OthelloView.swift",
        "GameChess/ChessView.swift",
    ])
    func undoMessageMentionsTheCPUReply(path: String) throws {
        let source = try Self.source(path)
        #expect(!source.contains("\"直前の1手を取り消します。"), "\(path) に1手だけ戻るような文言が残っている")
        #expect(!source.contains("広告を視聴すると1手戻せます。"), "\(path) に1手だけ戻るような文言が残っている")
        #expect(source.contains("BoardUndoButton("), "\(path) が共通の「待った」を通っていない")
    }

    @Test func sharedUndoButtonMentionsTheCPUReply() throws {
        let source = try Self.source("Core/BoardGameChrome.swift")
        #expect(!source.contains("\"直前の1手を取り消します。"), "共通の「待った」に1手だけ戻るような文言がある")
        #expect(!source.contains("広告を視聴すると1手戻せます。"), "共通の「待った」に1手だけ戻るような文言がある")
        #expect(source.contains("あなたの直前の1手を、CPU の応手ごと取り消します。"))
    }

    private static func source(_ path: String) throws -> String {
        try SourceScan.packageSource("Sources/\(path)")
    }
}
