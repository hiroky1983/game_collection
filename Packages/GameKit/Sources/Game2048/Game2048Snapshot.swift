/// 2048 の中断スナップショット。盤面そのものを保存するため乱数シードの再現は不要。
/// ベストスコアは持たない（仕様）。
public struct Game2048Snapshot: Codable, Equatable, Sendable {
    public var board: [[Int]]
    public var score: Int

    public init(board: [[Int]], score: Int) {
        self.board = board
        self.score = score
    }
}
