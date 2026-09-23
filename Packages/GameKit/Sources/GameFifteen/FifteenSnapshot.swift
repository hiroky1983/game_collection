/// 15 パズルの中断スナップショット。盤面そのものと手数を保存する（乱数シードの再現は不要）。
public struct FifteenSnapshot: Codable, Equatable, Sendable {
    public var tiles: [Int]
    public var moves: Int

    public init(tiles: [Int], moves: Int) {
        self.tiles = tiles
        self.moves = moves
    }
}
