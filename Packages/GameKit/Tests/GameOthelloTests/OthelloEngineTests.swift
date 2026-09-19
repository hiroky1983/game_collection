import Testing
import Foundation
import Core
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

// MARK: - 入門・ガチ（#1174）

@Suite("オセロ 入門とガチ")
struct OthelloNoviceAndSeriousTests {

    private static let novice = CPUStrength.novice.rawValue
    private static let serious = CPUStrength.serious.rawValue

    /// 角が取れるなら取る（「勝てるのに取らない」不自然さは作らない）。
    /// 同じ盤面で「簡単」は返る枚数を採って角を見送る（`weakPrefersFlipCountOverCorner`）ので、
    /// 2 つのテストが対になって「入門と簡単は別の打ち方」であることを固定する。
    @Test("入門は取れる角を取る")
    func noviceTakesTheCorner() async {
        var cells = [OthelloStone?](repeating: nil, count: othelloBoardSize * othelloBoardSize)
        cells[0 * othelloBoardSize + 1] = .white
        cells[0 * othelloBoardSize + 2] = .black
        cells[3 * othelloBoardSize + 3] = .white
        cells[2 * othelloBoardSize + 3] = .white
        cells[1 * othelloBoardSize + 3] = .white
        cells[0 * othelloBoardSize + 3] = .black
        let board = OthelloBoard(cells: cells)

        let move = await OthelloEngine(level: Self.novice).bestMove(board: board, stone: .black)
        #expect(move?.row == 0 && move?.col == 0, "入門が角を見送った: \(String(describing: move))")
    }

    /// 角が無いときは**角のとなり**（X打ち・C打ち）へ飛びつく。初心者の癖をそのまま真似ている。
    @Test("入門は角のとなりを選ぶ")
    func novicePrefersTheSquaresNextToACorner() async {
        var cells = [OthelloStone?](repeating: nil, count: othelloBoardSize * othelloBoardSize)
        // (1,1)（X打ち）に黒を置くと 1 枚返る。
        cells[2 * othelloBoardSize + 2] = .white
        cells[3 * othelloBoardSize + 3] = .black
        // (5,4) に黒を置くと 3 枚返る（枚数だけなら簡単はこちらを選ぶ）。
        cells[4 * othelloBoardSize + 4] = .white
        cells[3 * othelloBoardSize + 4] = .white
        cells[2 * othelloBoardSize + 4] = .white
        cells[1 * othelloBoardSize + 4] = .black
        let board = OthelloBoard(cells: cells)
        #expect(board.flippable(row: 1, col: 1, stone: .black).count == 1)
        #expect(board.flippable(row: 5, col: 4, stone: .black).count == 3)

        let novice = await OthelloEngine(level: Self.novice).bestMove(board: board, stone: .black)
        #expect(novice?.row == 1 && novice?.col == 1, "入門が角のとなりを選ばない: \(String(describing: novice))")
        let easy = await OthelloEngine(level: 0).bestMove(board: board, stone: .black)
        #expect(easy?.row == 5 && easy?.col == 4, "前提が崩れている: 簡単は枚数で選ぶ")
    }

    @Test("入門は同じ盤面に必ず同じ手を返す")
    func noviceIsDeterministic() async {
        let board = OthelloBoard()
        let first = await OthelloEngine(level: Self.novice).bestMove(board: board, stone: .black)
        for _ in 0..<20 {
            let move = await OthelloEngine(level: Self.novice).bestMove(board: board, stone: .black)
            #expect(move?.row == first?.row && move?.col == first?.col)
        }
    }

    /// 入門は簡単に負け越す。どちらも決定的な打ち方なので同じ手順しか作れず、
    /// **最初の 8 手をでたらめに進めてから**戦わせて局面を散らす。
    @Test("入門は簡単に負け越す")
    func noviceLosesToEasy() async {
        let games = 40
        var wins = 0
        for i in 0..<games {
            let noviceIsBlack = i % 2 == 0
            let result = await OthelloSelfPlay.play(
                black: noviceIsBlack ? .level(Self.novice) : .level(0),
                white: noviceIsBlack ? .level(0) : .level(Self.novice),
                seed: UInt64(i) &+ 1, openingPlies: 8)
            let mine = noviceIsBlack ? result.black : result.white
            let theirs = noviceIsBlack ? result.white : result.black
            if mine > theirs { wins += 1 }
        }
        print("othello novice vs easy: \(wins)/\(games)")
        #expect(wins <= games * 4 / 10, "入門が簡単に \(wins)/\(games) 勝っている（段の順が崩れている）")
    }

    /// 下限: 弱くしても、でたらめに打つ相手には勝ったり負けたりする（一方的に負けはしない）。
    @Test("入門はでたらめな相手に一方的に負けはしない")
    func noviceIsNotBrokenAgainstRandom() async {
        let games = 40
        var wins = 0
        for i in 0..<games {
            let noviceIsBlack = i % 2 == 0
            let result = await OthelloSelfPlay.play(
                black: noviceIsBlack ? .level(Self.novice) : .random,
                white: noviceIsBlack ? .random : .level(Self.novice),
                seed: UInt64(i) &+ 1)
            let mine = noviceIsBlack ? result.black : result.white
            let theirs = noviceIsBlack ? result.white : result.black
            if mine > theirs { wins += 1 }
        }
        print("othello novice vs random: \(wins)/\(games)")
        #expect(wins >= games * 3 / 10, "入門がでたらめな相手に \(wins)/\(games) しか勝てない（壊れている）")
    }

    /// ガチは「むずかしい」と同じ深さ 5 を読んでから深さ 7 を読み直す（#1174）。
    /// 深さ 7 が時間内に終わらなければ深さ 5 の結論を使うので、遅い端末でも下回らない。
    @Test("ガチの深さと持ち時間")
    func seriousConfiguration() {
        #expect(OthelloEngine.seriousDeepDepth == 7)
        #expect(OthelloEngine.seriousTimeLimit == 2.5)
    }

    /// 深く読んでも足元は崩さない: 取れる角は取る。
    @Test("ガチは取れる角を取る")
    func seriousTakesTheCorner() async {
        var cells = [OthelloStone?](repeating: nil, count: othelloBoardSize * othelloBoardSize)
        cells[0 * othelloBoardSize + 1] = .white
        cells[0 * othelloBoardSize + 2] = .black
        cells[3 * othelloBoardSize + 3] = .white
        cells[2 * othelloBoardSize + 3] = .white
        cells[1 * othelloBoardSize + 3] = .white
        cells[0 * othelloBoardSize + 3] = .black
        let board = OthelloBoard(cells: cells)

        let move = await OthelloEngine(level: Self.serious).bestMove(board: board, stone: .black)
        #expect(move?.row == 0 && move?.col == 0, "ガチが角を取らなかった: \(String(describing: move))")
    }
}

// MARK: - 自己対戦（テスト用）

enum OthelloSelfPlay {
    enum Side: Equatable {
        case weak
        /// 出荷している段階そのもの（#1174。段の番号から `OthelloEngine` を作る）。
        case level(Int)
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

    /// - Parameter openingPlies: 最初の何手をでたらめに打つか。決定的な段どうしを
    ///   何局も戦わせるために使う（同じ手順を繰り返すと 1 局しか作れないため・#1174）。
    static func play(black: Side, white: Side, seed: UInt64, openingPlies: Int = 0) async -> Result {
        var board = OthelloBoard()
        var rng = Rand(seed: seed)
        var stone = OthelloStone.black
        var ply = 0
        while true {
            let moves = board.validMoves(for: stone)
            if moves.isEmpty {
                if board.validMoves(for: stone.opponent).isEmpty { break }
                stone = stone.opponent
                continue
            }
            var chosen = moves[Int(rng.next() % UInt64(moves.count))]
            defer { ply += 1 }
            if ply < openingPlies {
                board.place(row: chosen.0, col: chosen.1, stone: stone)
                stone = stone.opponent
                continue
            }
            switch stone == .black ? black : white {
            case .weak:
                if let move = await OthelloEngine(level: 0).bestMove(board: board, stone: stone) {
                    chosen = move
                }
            case .level(let level):
                if let move = await OthelloEngine(level: level).bestMove(board: board, stone: stone) {
                    chosen = move
                }
            case .random:
                break
            }
            board.place(row: chosen.0, col: chosen.1, stone: stone)
            stone = stone.opponent
        }
        return Result(black: board.count(for: .black), white: board.count(for: .white))
    }
}
