import Foundation
import CoreEngine
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
        // MMIX の 1 歩は共通部品の定数を使う（定数の書き写しをやめた #1074 / #1150 の扱い）。
        state = state &* MMIXRandom.multiplier &+ MMIXRandom.increment
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
        forbiddenMoves: nil,
        hintsUsed: nil
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
            let move = await SimpleGomokuEngine(level: 0, seed: spreadSeed(i))
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

// MARK: - 入門の下限（#1463）

/// 合法手（空いている交点）から一様に乱択する相手（会長決裁の「入門は一様乱択の相手に 8 割以上勝つ」の相手役）。
private func randomMove(board: GomokuBoard, seed: UInt64) -> (row: Int, col: Int) {
    let empty = board.cells.indices.filter { board.cells[$0] == nil }
    var rng = TestRNG(state: seed)
    let pick = empty[Int.random(in: 0..<empty.count, using: &rng)]
    return (pick / gomokuBoardSize, pick % gomokuBoardSize)
}

@Suite("五目並べ 入門とむずかしい")
struct GomokuNoviceAndHardTests {

    /// 弱くしても壊さない: 入門でも自分の五は必ず取る。
    @Test func noviceAlwaysTakesItsOwnWin() async {
        let board = makeBoard(black: [(7, 3), (7, 4), (7, 5), (7, 6)],
                              white: [(3, 10), (4, 10), (5, 10), (6, 10)])
        for i in 0..<20 {
            let move = await SimpleGomokuEngine(level: CPUStrength.novice.rawValue, seed: spreadSeed(i))
                .bestMove(board: board, stone: .white)
            #expect(move?.row == 7 && move?.col == 10 || move?.row == 2 && move?.col == 10)
        }
    }

    /// むずかしいは即勝ちも即防ぎも見逃さない（深く読ませても足元が崩れていないこと）。
    @Test func hardTakesTheWinAndTheBlock() async {
        let level = CPUStrength.hard.rawValue
        let winnable = makeBoard(black: [(3, 10), (4, 10), (5, 10)],
                                 white: [(7, 3), (7, 4), (7, 5), (7, 6)])
        let win = await SimpleGomokuEngine(level: level).bestMove(board: winnable, stone: .white)
        #expect(win?.row == 7 && (win?.col == 7 || win?.col == 2),
                "むずかしいが五を完成していない: \(String(describing: win))")

        let mustBlock = makeBoard(black: [(7, 3), (7, 4), (7, 5), (7, 6)], white: [(7, 2)])
        let block = await SimpleGomokuEngine(level: level).bestMove(board: mustBlock, stone: .white)
        #expect(block?.row == 7 && block?.col == 7, "むずかしいが四を止めていない: \(String(describing: block))")
    }

    /// 下限: 入門は、合法手から一様に乱択する相手に 8 割以上勝つ（会長決裁 2026-09-27。
    /// 先後入れ替え 100 局の実測は段階表 `docs/analytics/gomoku-1463-ladder.md`。ここは 20 局の軽い確認）。
    @Test func noviceBeatsAUniformRandomMover() async {
        let games = 20
        var won = 0
        for game in 0..<games {
            let noviceStone: GomokuStone = game % 2 == 0 ? .black : .white
            var board = GomokuBoard()
            var stone = GomokuStone.black
            for ply in 0..<(gomokuBoardSize * gomokuBoardSize) {
                let seed = spreadSeed(game * 1000 + ply, salt: 5)
                let m: (row: Int, col: Int)
                if stone == noviceStone {
                    guard let e = await SimpleGomokuEngine(level: CPUStrength.novice.rawValue, seed: seed, timeLimit: .infinity)
                        .bestMove(board: board, stone: stone), board[e.row, e.col] == nil else {
                        Issue.record("打てない手が返った（\(game) 局目 \(ply) 手目）")
                        return
                    }
                    m = e
                } else {
                    m = randomMove(board: board, seed: seed)
                }
                board[m.row, m.col] = stone
                if board.checkWin(row: m.row, col: m.col) {
                    if stone == noviceStone { won += 1 }
                    break
                }
                stone = stone.opponent
            }
        }
        #expect(won >= games * 8 / 10, "入門が一様乱択の相手に \(won)/\(games) しか勝てない")
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
        #expect(source.contains("BoardGameControlBar("), "\(path) が共通の「待った」を通っていない")
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
