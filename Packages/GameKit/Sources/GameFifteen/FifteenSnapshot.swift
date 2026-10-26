/// 15 パズルの中断スナップショット。盤面そのものと手数を保存する（乱数シードの再現は不要）。
/// 盤の大きさ（#2869）は `tiles` の長さで決まる（16 枚 = 4×4 の従来の中断データはそのまま読める）。
public struct FifteenSnapshot: Codable, Equatable, Sendable {
    public var tiles: [Int]
    public var moves: Int
    /// この局で使ったヒントの回数（#1975）。無料も広告も同じカウンタ。鍵を持たない v1.1.10 までの中断データは未使用として読む。
    /// 盤の上の印は保存しない（開き直したら出し直す）。
    public var hintsUsed: Int?

    public init(tiles: [Int], moves: Int, hintsUsed: Int? = nil) {
        self.tiles = tiles
        self.moves = moves
        self.hintsUsed = hintsUsed
    }
}
