import Foundation

/// 種を与えると同じ並びを再現する乱数（SplitMix64）。
/// ソリティアの `SolitaireSeededGenerator` と同じ実装で、テストからピースの並びを固定するのに使う。
public struct BlockPuzzleRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// ブロックならべ（#493）の純粋ロジック。SwiftUI 非依存・乱数は呼び出し側が持つので、
/// 盤の判定はすべてここで網羅的にテストできる。
///
/// 盤は `[[Int]]` で、0 = 空きマス、1...5 = 置かれたピースの色番号（`BlockPuzzlePiece.colorIndex`）。
public enum BlockPuzzleBoard {
    /// 盤の一辺。
    public static let size = 10
    /// 一度に手元へ配るピースの数。
    public static let handSize = 3

    public static func emptyBoard() -> [[Int]] {
        Array(repeating: Array(repeating: 0, count: size), count: size)
    }

    /// 盤として妥当な形か（10×10・色番号が 0...5）。壊れた中断データを弾くのに使う。
    public static func isValid(_ board: [[Int]]) -> Bool {
        guard board.count == size else { return false }
        return board.allSatisfy { row in
            row.count == size && row.allSatisfy { (0...5).contains($0) }
        }
    }

    /// ピースの左上を (row, col) に合わせて置けるか。盤からはみ出す・既に埋まっているマスがあれば false。
    public static func canPlace(_ board: [[Int]], _ piece: BlockPuzzlePiece, row: Int, col: Int) -> Bool {
        for cell in piece.cells {
            let r = row + cell.row
            let c = col + cell.col
            guard r >= 0, r < size, c >= 0, c < size else { return false }
            guard board[r][c] == 0 else { return false }
        }
        return true
    }

    /// ピースを置いた盤を返す。置けない位置なら nil（呼び出し側が拒否として扱う）。
    public static func place(_ board: [[Int]], _ piece: BlockPuzzlePiece, row: Int, col: Int) -> [[Int]]? {
        guard canPlace(board, piece, row: row, col: col) else { return nil }
        var result = board
        for cell in piece.cells {
            result[row + cell.row][col + cell.col] = piece.colorIndex
        }
        return result
    }

    /// 盤のどこか 1 マスでも置ける場所があるか。
    public static func canPlaceAnywhere(_ board: [[Int]], _ piece: BlockPuzzlePiece) -> Bool {
        for row in 0...(size - piece.height) {
            for col in 0...(size - piece.width) where canPlace(board, piece, row: row, col: col) {
                return true
            }
        }
        return false
    }

    /// 揃った行・列をまとめて消す。
    ///
    /// **行と列は同時に判定してから消す**。先に行を消してしまうと、その行を含んで揃っていた列が
    /// 未完成に変わり、同時消しが 1 本ぶん取りこぼされる。
    /// 戻り値の `lines` は消えた行数 + 列数（行と列が交差していても 2 本として数える）。
    public static func clearLines(_ board: [[Int]]) -> (board: [[Int]], lines: Int) {
        let fullRows = (0..<size).filter { r in board[r].allSatisfy { $0 != 0 } }
        let fullCols = (0..<size).filter { c in board.allSatisfy { $0[c] != 0 } }
        guard !fullRows.isEmpty || !fullCols.isEmpty else { return (board, 0) }

        var result = board
        for r in fullRows {
            for c in 0..<size { result[r][c] = 0 }
        }
        for c in fullCols {
            for r in 0..<size { result[r][c] = 0 }
        }
        return (result, fullRows.count + fullCols.count)
    }

    /// 手元のピースがどれも置けなくなったらゲームオーバー。
    /// 使用済みのスロット（nil）は判定に含めない。
    public static func isGameOver(_ board: [[Int]], hand: [BlockPuzzlePiece?]) -> Bool {
        !hand.compactMap { $0 }.contains { canPlaceAnywhere(board, $0) }
    }

    /// コンティニュー（リワード広告視聴後の復活）で空ける正方領域の一辺。
    ///
    /// カタログのピースの外接矩形は最大でも 5×1 / 1×5 / 3×3 なので、5×5 を丸ごと空ければ
    /// **どの形でも必ず置ける**。手元に残っているピースを配り直さずにそのまま続行できる。
    public static let reviveRegionSize = 5

    /// コンティニュー用の復活処理。盤の中央 5×5 を空ける。
    ///
    /// 乱数を使わないので、同じ盤からは必ず同じ結果になる。空けるのは中央に固定していて、
    /// 「どこが空くか」がプレイヤーから見て予測できる（広告を見る前に価値が分かる）。
    public static func revive(_ board: [[Int]]) -> [[Int]] {
        var result = board
        let origin = (size - reviveRegionSize) / 2
        for r in origin..<(origin + reviveRegionSize) {
            for c in origin..<(origin + reviveRegionSize) {
                result[r][c] = 0
            }
        }
        return result
    }

    /// 手元へ配る `handSize` 個を引く。
    ///
    /// **詰み直行の手札を配らない**: 引いた 3 個がどれも置けず、かつ置ける形がカタログに
    /// 1 つでも存在するなら、先頭を置ける形に差し替える。これで「配られた瞬間に詰んでいる」
    /// 局面は構造的に起きなくなる（盤がほぼ埋まっていて本当にどの形も置けないときだけ詰む）。
    public static func makeHand(board: [[Int]], using rng: inout BlockPuzzleRandom) -> [BlockPuzzlePiece] {
        var hand = (0..<handSize).map { _ in
            BlockPuzzlePiece.catalog.randomElement(using: &rng) ?? BlockPuzzlePiece.catalog[0]
        }
        guard !hand.contains(where: { canPlaceAnywhere(board, $0) }) else { return hand }

        let placeable = BlockPuzzlePiece.catalog.filter { canPlaceAnywhere(board, $0) }
        if let rescue = placeable.randomElement(using: &rng) {
            hand[0] = rescue
        }
        return hand
    }
}

/// 得点計算。配置点と消去点を分けて持ち、どちらも純関数なのでそのままテストできる。
public enum BlockPuzzleScoring {
    /// 置いたときの点 = 埋めたマス数。
    public static func placementPoints(_ piece: BlockPuzzlePiece) -> Int { piece.size }

    /// 消去の点。同時に消した本数ほど 1 本あたりが伸び、連続で消し続けるとコンボ倍率が掛かる。
    ///
    /// - Parameters:
    ///   - lines: 同時に消えた行数 + 列数。
    ///   - combo: 連続して消した回数（この手を含む。1 手目は 1）。
    public static func clearPoints(lines: Int, combo: Int) -> Int {
        guard lines > 0, combo > 0 else { return 0 }
        // 1 本 10 点・2 本 30 点・3 本 60 点（= 10 × 1 + 2 + ... + n）。まとめて消すほど伸びる。
        let base = 10 * lines * (lines + 1) / 2
        return base * combo
    }
}
