import Foundation
import CoreEngine

/// CPU の手選び。`CPUStrength` の 4 段階（入門 / かんたん / ふつう / むずかしい）に対応する。
///
/// | 段階 | 中身 |
/// |---|---|
/// | 入門（-1） | 打てる穴から無作為に 1 つ |
/// | かんたん（0） | 1 手先だけ見る（ストアの差が最も開く手） |
/// | ふつう（1） | 4 手先まで読む（αβ 探索） |
/// | むずかしい（2） | 8 手先まで読む（αβ 探索） |
///
/// 続けて打つ手（最後の種がストアに入る）も 1 手と数える。各手番の候補は 6 つ以下なので、
/// 8 手先でも αβ で十分に速い。開始シートの説明（`MancalaView`）はこの表と一致させること（#416）。
public struct MancalaEngine: Sendable {
    public let level: Int
    /// 入門の無作為選択に使う乱数の種。nil なら毎回変わる。
    public let seed: UInt64?

    public init(level: Int, seed: UInt64? = nil) {
        self.level = level
        self.seed = seed
    }

    /// 段階ごとの読みの深さ（入門は読まない）。
    public static func depth(for strength: CPUStrength) -> Int {
        switch strength {
        case .novice: return 0
        case .easy:   return 1
        case .normal: return 4
        case .hard:   return 8
        }
    }

    /// 打つ穴（0〜5）。打てる穴が無ければ nil。
    public func bestMove(board: MancalaBoard, side: MancalaSide) -> Int? {
        let moves = MancalaRules.legalMoves(board: board, side: side)
        guard !moves.isEmpty else { return nil }
        if moves.count == 1 { return moves[0] }
        let strength = CPUStrength.strength(for: level)
        if strength == .novice {
            var rng = SplitMix64(seed: seed ?? UInt64.random(in: 0...UInt64.max))
            return moves[Int(rng.next() % UInt64(moves.count))]
        }
        let depth = Self.depth(for: strength)
        // 同点なら先に並んだ手（ストアに近い穴から見る並び）。並びは決定的なので、同じ局面なら同じ手になる。
        var best = moves[0], bestScore = -Double.infinity
        var alpha = -Double.infinity
        for pit in Self.ordered(moves) {
            let result = MancalaRules.apply(pit: pit, side: side, to: board)
            let score = Self.search(result, mover: side, me: side, depth: depth - 1,
                                    alpha: alpha, beta: .infinity)
            if score > bestScore { bestScore = score; best = pit }
            alpha = max(alpha, bestScore)
        }
        return best
    }

    /// ストアに近い穴（続けて打てる手・取りが出やすい）から読むと枝刈りが効く。
    private static func ordered(_ moves: [Int]) -> [Int] { moves.reversed() }

    /// `mover` が打った直後の局面 `result` を、`me` から見て評価する（αβ・負けない側を最大化）。
    private static func search(_ result: MancalaMoveResult, mover: MancalaSide, me: MancalaSide,
                               depth: Int, alpha: Double, beta: Double) -> Double {
        let board = result.board
        if result.gameEnded || depth <= 0 { return evaluate(board, for: me, isFinal: result.gameEnded) }
        let next = result.extraTurn ? mover : mover.opponent
        let moves = MancalaRules.legalMoves(board: board, side: next)
        if moves.isEmpty { return evaluate(board, for: me, isFinal: true) }
        var a = alpha, b = beta
        if next == me {
            var value = -Double.infinity
            for pit in ordered(moves) {
                let r = MancalaRules.apply(pit: pit, side: next, to: board)
                value = max(value, search(r, mover: next, me: me, depth: depth - 1, alpha: a, beta: b))
                a = max(a, value)
                if a >= b { break }
            }
            return value
        } else {
            var value = Double.infinity
            for pit in ordered(moves) {
                let r = MancalaRules.apply(pit: pit, side: next, to: board)
                value = min(value, search(r, mover: next, me: me, depth: depth - 1, alpha: a, beta: b))
                b = min(b, value)
                if a >= b { break }
            }
            return value
        }
    }

    /// `side` にとって大きいほど良い評価。
    ///
    /// ストアの差が基本（ストアの種はもう動かない）。穴に残る種は終局で自分のものになりうるが、
    /// 取られもするので小さく足す。終局した盤は勝ち負けを大きく振って、確定した勝ちを最優先にする。
    static func evaluate(_ board: MancalaBoard, for side: MancalaSide, isFinal: Bool) -> Double {
        let diff = Double(board.store(side) - board.store(side.opponent))
        if isFinal {
            if diff > 0 { return 1000 + diff }
            if diff < 0 { return -1000 + diff }
            return 0
        }
        return diff + 0.25 * Double(board.pitTotal(side) - board.pitTotal(side.opponent))
    }
}
