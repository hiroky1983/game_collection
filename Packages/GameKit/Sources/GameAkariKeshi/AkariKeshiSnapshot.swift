/// 明かり消しパズルの中断スナップショット。盤・手数・難易度・最短の手数・経過秒を持つ。
/// **1 回も押していない盤は保存しない**（開いただけの盤を「続き」にしない・#1847）。
public struct AkariKeshiSnapshot: Codable, Equatable, Sendable {
    public var board: [Bool]
    public var moves: Int
    public var difficulty: AkariKeshiDifficulty
    /// この盤の最短の手数（生成で押した数）。
    public var par: Int
    public var elapsedSeconds: Int

    public init(board: [Bool], moves: Int, difficulty: AkariKeshiDifficulty, par: Int, elapsedSeconds: Int) {
        self.board = board
        self.moves = moves
        self.difficulty = difficulty
        self.par = par
        self.elapsedSeconds = elapsedSeconds
    }
}
