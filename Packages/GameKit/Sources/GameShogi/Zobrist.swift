import Foundation

// MARK: - Zobrist Hashing（Position が差分更新で使用する乱数テーブル）

struct LCG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state ^ (state >> 33)
    }
}

enum Zobrist {
    // [pieceType 0-7][color 0-1][promoted 0-1][square 0-80]
    static let piece: [[[[UInt64]]]] = {
        var rng = LCG(state: 0xDEAD_BEEF_CAFE_BABE)
        var t = [[[[UInt64]]]](
            repeating: [[[UInt64]]](
                repeating: [[UInt64]](
                    repeating: [UInt64](repeating: 0, count: 81),
                    count: 2),
                count: 2),
            count: 8)
        for pt in 0..<8 { for c in 0..<2 { for pr in 0..<2 { for sq in 0..<81 {
            t[pt][c][pr][sq] = rng.next()
        }}}}
        return t
    }()

    // [color 0-1][pieceType 0-6 droppable][count 0-18]
    static let hand: [[[UInt64]]] = {
        var rng = LCG(state: 0xCAFE_BABE_DEAD_BEEF)
        var t = [[[UInt64]]](
            repeating: [[UInt64]](
                repeating: [UInt64](repeating: 0, count: 19),
                count: 7),
            count: 2)
        for c in 0..<2 { for pt in 0..<7 { for n in 0..<19 {
            t[c][pt][n] = rng.next()
        }}}
        return t
    }()

    static let sideToMove: UInt64 = {
        var rng = LCG(state: 0x1234_5678_9ABC_DEF0)
        return rng.next()
    }()
}

extension Position {
    /// 盤・持ち駒・手番からフル計算する（初期化時のみ。探索中は make/unmake が差分更新する）。
    static func computeHash(squares: [Piece?], hands: [[Int]], sideToMove: Side) -> UInt64 {
        var h: UInt64 = 0
        for (sq, p) in squares.enumerated() {
            guard let p else { continue }
            h ^= Zobrist.piece[p.type.rawValue][p.color.rawValue][p.promoted ? 1 : 0][sq]
        }
        for c in 0..<2 {
            for t in 0..<7 {
                let n = hands[c][t]
                if n > 0 { h ^= Zobrist.hand[c][t][min(n, 18)] }
            }
        }
        if sideToMove == .black { h ^= Zobrist.sideToMove }
        return h
    }

    /// 互換 API: 保持している差分更新済みハッシュを返す。
    func zobristHash() -> UInt64 { hash }
}
