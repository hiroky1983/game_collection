import Foundation

/// 盤座標ユーティリティ。マスは 0..<81 の Int で表す。
/// index = rank * 9 + file。file 0..8 は USI ファイル 1..9（fileIndex = USIファイル - 1）、
/// rank 0..8 は USI ランク 'a'..'i'（rank 0 = 'a' = 最上段）。
public enum Sq {
    public static let count = 81

    @inline(__always) public static func file(_ i: Int) -> Int { i % 9 }
    @inline(__always) public static func rank(_ i: Int) -> Int { i / 9 }
    @inline(__always) public static func index(file: Int, rank: Int) -> Int { rank * 9 + file }

    @inline(__always) public static func onBoard(file: Int, rank: Int) -> Bool {
        file >= 0 && file < 9 && rank >= 0 && rank < 9
    }

    /// 指定色の成り地帯か（先手: rank 0..2、後手: rank 6..8）。
    @inline(__always) public static func isPromotionZone(rank: Int, color: Side) -> Bool {
        color == .black ? rank <= 2 : rank >= 6
    }

    /// USI 文字列（例 "7g"）→ マス。
    public static func fromUSI(_ s: Substring) -> Int? {
        guard s.count == 2 else { return nil }
        let chars = Array(s)
        guard let fileDigit = chars[0].wholeNumberValue, fileDigit >= 1, fileDigit <= 9 else { return nil }
        let rankScalar = chars[1].asciiValue.map { Int($0) - Int(Character("a").asciiValue!) }
        guard let rank = rankScalar, rank >= 0, rank < 9 else { return nil }
        return index(file: fileDigit - 1, rank: rank)
    }

    /// 画面の (row,col) → 内部マス。flipped=true（人間が後手）なら盤を 180 度反転して表示する。
    /// 反転なし: 先手視点（上=a段, 左=9筋, 先手が手前）。反転: 後手が手前。
    public static func boardIndex(row: Int, col: Int, flipped: Bool) -> Int {
        flipped ? index(file: col, rank: 8 - row)
                : index(file: 8 - col, rank: row)
    }

    /// マス → USI 文字列（例 "7g"）。
    public static func toUSI(_ i: Int) -> String {
        let fileDigit = file(i) + 1
        let rankLetter = Character(UnicodeScalar(UInt8(Int(Character("a").asciiValue!) + rank(i))))
        return "\(fileDigit)\(rankLetter)"
    }
}
