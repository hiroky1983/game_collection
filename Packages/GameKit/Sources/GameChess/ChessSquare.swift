import Foundation

/// 盤座標ユーティリティ。マスは 0..<64 の Int で表す。
///
/// index = rank * 8 + file。
/// - file 0..7 は筋 a..h（左から右）
/// - rank 0..7 は段 8..1（**上から下**）。rank 0 が黒の最奥段（8段目）、rank 7 が白の最奥段（1段目）
///
/// FEN の盤面フィールドは 8段目から 1段目へ、各段は a筋から h筋へ並ぶので、
/// この取り方だと**読んだ順にそのまま index が増える**（変換式が要らない）。
public enum ChessSquare {
    public static let count = 64

    @inline(__always) public static func file(_ i: Int) -> Int { i % 8 }
    @inline(__always) public static func rank(_ i: Int) -> Int { i / 8 }
    @inline(__always) public static func index(file: Int, rank: Int) -> Int { rank * 8 + file }

    @inline(__always) public static func onBoard(file: Int, rank: Int) -> Bool {
        file >= 0 && file < 8 && rank >= 0 && rank < 8
    }

    /// 代数式（例 "e4"）→ マス。
    public static func fromName(_ s: Substring) -> Int? {
        guard s.count == 2 else { return nil }
        let chars = Array(s)
        guard let fileAscii = chars[0].asciiValue,
              let aAscii = Character("a").asciiValue else { return nil }
        let file = Int(fileAscii) - Int(aAscii)
        guard file >= 0, file < 8 else { return nil }
        guard let rankDigit = chars[1].wholeNumberValue, rankDigit >= 1, rankDigit <= 8 else { return nil }
        return index(file: file, rank: 8 - rankDigit)
    }

    /// マス → 代数式（例 "e4"）。
    public static func name(_ i: Int) -> String {
        let fileChar = Character(UnicodeScalar(UInt8(Int(Character("a").asciiValue!) + file(i))))
        return "\(fileChar)\(8 - rank(i))"
    }

    /// 画面の (row,col) → 内部マス。flipped=true（人間が黒）なら盤を 180 度反転して表示する。
    ///
    /// 反転なし: 白視点（上 = 8段目, 左 = a筋, 白が手前）。反転: 黒が手前。
    /// 将棋（`Sq.boardIndex`）と同じ役割・同じ呼び名にしてある。
    public static func boardIndex(row: Int, col: Int, flipped: Bool) -> Int {
        flipped ? index(file: 7 - col, rank: 7 - row)
                : index(file: col, rank: row)
    }

    /// 内部マス → 画面の (row,col)。`boardIndex(row:col:flipped:)` の逆変換。
    /// 盤を覆う 1 枚の層に駒を絶対座標で置くために使う（将棋 #200 と同じ方式）。
    public static func displayPosition(of square: Int, flipped: Bool) -> (row: Int, col: Int) {
        flipped ? (row: 7 - rank(square), col: 7 - file(square))
                : (row: rank(square), col: file(square))
    }

    /// マスの色（明るいマスか）。a1（左下・index 56）が暗いマス、h1 が明るいマス。
    @inline(__always) public static func isLightSquare(_ i: Int) -> Bool {
        (file(i) + rank(i)) % 2 == 0
    }
}
