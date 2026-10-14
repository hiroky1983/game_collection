/// 線つなぎの中断スナップショット（#2235）。問題（点と唯一の解）・描いた線・手数を保存する。
/// 問題は乱数の種から作り直さず、そのまま持つ（生成の手順を変えても古い中断データが壊れない）。
public struct TsunagiSnapshot: Codable, Equatable, Sendable {
    /// 盤の大きさ（`TsunagiSize.rawValue`）。
    public var size: String
    public var puzzle: TsunagiPuzzle
    /// 数字ごとの描いた線（点から始まるマスの並び。描いていない数字は空）。
    public var paths: [[Int]]
    public var moves: Int

    public init(size: String, puzzle: TsunagiPuzzle, paths: [[Int]], moves: Int) {
        self.size = size
        self.puzzle = puzzle
        self.paths = paths
        self.moves = moves
    }
}
