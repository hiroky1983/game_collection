import Testing
import Foundation
@testable import GameOthello

/// CPU の難易度カーブの回帰テスト（#1013）。
///
/// **レベルどうしの勝率の実測は `-O` の単体バイナリで行い、結果は #1013 / PR の表に残す。**
/// ここに入れるのは CI（最適化なしのデバッグビルド）で現実的な時間に収まるものだけ:
/// 深さ 3・5 の探索を自己対戦させると 1 局で数十秒かかるため、置けるのは
/// ①「弱」の打ち方（読まずに最も多く返る手を選ぶ）②探索を一切しない「弱」の直接対戦、の 2 つ。
@Suite("オセロ CPU の難易度")
struct OthelloEngineTests {

    // MARK: - 弱（読まない）

    /// 角を取れるが返る石は 1 枚、別の手なら 3 枚返る盤面。
    /// 「弱」は角の価値を知らないので**枚数の多い方**を選ぶ（#1013。
    /// 位置評価を見る実装に戻すと角を取るのでこのテストが落ちる）。
    @Test("弱は角より返る枚数を優先する")
    func weakPrefersFlipCountOverCorner() async {
        var cells = [OthelloStone?](repeating: nil, count: othelloBoardSize * othelloBoardSize)
        // 上端の行: (0,0) が空き・(0,1) が白・(0,2) が黒 → (0,0) に黒を置くと 1 枚返る。
        cells[0 * othelloBoardSize + 1] = .white
        cells[0 * othelloBoardSize + 2] = .black
        // 中央の列: (4,3) が空き・(3,3)(2,3)(1,3) が白・(0,3) が黒 → (4,3) に置くと 3 枚返る。
        cells[3 * othelloBoardSize + 3] = .white
        cells[2 * othelloBoardSize + 3] = .white
        cells[1 * othelloBoardSize + 3] = .white
        cells[0 * othelloBoardSize + 3] = .black
        let board = OthelloBoard(cells: cells)

        #expect(board.flippable(row: 0, col: 0, stone: .black).count == 1)
        #expect(board.flippable(row: 4, col: 3, stone: .black).count == 3)

        let move = await OthelloEngine(level: 0).bestMove(board: board, stone: .black)
        #expect(move?.row == 4 && move?.col == 3, "弱が角 (0,0) を取った: \(String(describing: move))")
    }

    @Test("弱は同じ盤面に必ず同じ手を返す")
    func weakIsDeterministic() async {
        let board = OthelloBoard()
        let first = await OthelloEngine(level: 0).bestMove(board: board, stone: .black)
        for _ in 0..<20 {
            let move = await OthelloEngine(level: 0).bestMove(board: board, stone: .black)
            #expect(move?.row == first?.row && move?.col == first?.col)
        }
    }

    @Test("打てる手が無ければ nil、あれば必ず合法手")
    func returnsLegalMoveOnly() async throws {
        let board = OthelloBoard()
        let move = await OthelloEngine(level: 0).bestMove(board: board, stone: .black)
        let unwrapped = try #require(move)
        #expect(board.isValid(row: unwrapped.row, col: unwrapped.col, stone: .black))

        // 白で埋めた盤は黒に打つ手が無い。
        let full = OthelloBoard(cells: [OthelloStone?](
            repeating: .white, count: othelloBoardSize * othelloBoardSize))
        let none = await OthelloEngine(level: 0).bestMove(board: full, stone: .black)
        #expect(none?.row == nil)
    }

    // MARK: - 「弱」の勝率（#1013）

    /// でたらめに打つ相手との直接対戦。**「弱」は探索しないのでデバッグビルドでも一瞬で終わる。**
    ///
    /// 上限は「初心者が安定して勝てる弱さ」の担保（位置評価を見ていた以前の実装は同じ条件で
    /// 88.3%・平均 +16.9 石だったので、戻すとこのテストが落ちる）。下限は弱くしすぎの検知。
    @Test("弱はでたらめな相手に勝ったり負けたりする")
    func weakWinRateAgainstRandom() async {
        let games = 60
        var wins = 0
        for i in 0..<games {
            let weakIsBlack = i % 2 == 0
            let result = await OthelloSelfPlay.play(
                black: weakIsBlack ? .weak : .random,
                white: weakIsBlack ? .random : .weak,
                seed: UInt64(i) &+ 1)
            let weakStones = weakIsBlack ? result.black : result.white
            let randomStones = weakIsBlack ? result.white : result.black
            if weakStones > randomStones { wins += 1 }
        }
        let rate = Double(wins) / Double(games)
        #expect(rate <= 0.75, "弱がでたらめな相手に \(wins)/\(games) 勝っている（強すぎる）")
        #expect(rate >= 0.35, "弱がでたらめな相手に \(wins)/\(games) しか勝てない（弱すぎる）")
    }
}

// MARK: - 自己対戦（テスト用）

enum OthelloSelfPlay {
    enum Side: Equatable {
        case weak
        case random
    }

    struct Result {
        var black: Int
        var white: Int
    }

    /// 決定的な擬似乱数（でたらめ役の手を再現可能にする）。
    struct Rand: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state ^ (state >> 33)
        }
    }

    static func play(black: Side, white: Side, seed: UInt64) async -> Result {
        var board = OthelloBoard()
        var rng = Rand(seed: seed)
        var stone = OthelloStone.black
        while true {
            let moves = board.validMoves(for: stone)
            if moves.isEmpty {
                if board.validMoves(for: stone.opponent).isEmpty { break }
                stone = stone.opponent
                continue
            }
            var chosen = moves[Int(rng.next() % UInt64(moves.count))]
            if (stone == .black ? black : white) == .weak,
               let move = await OthelloEngine(level: 0).bestMove(board: board, stone: stone) {
                chosen = move
            }
            board.place(row: chosen.0, col: chosen.1, stone: stone)
            stone = stone.opponent
        }
        return Result(black: board.count(for: .black), white: board.count(for: .white))
    }
}
