/// ハノイの塔の中断スナップショット（#2003）。盤・手数・経過秒を保存する。
/// **1 手も動かしていない盤は保存しない**（開いただけの盤を「続き」にしない・#1847）。
public struct HanoiSnapshot: Codable, Equatable, Sendable {
    public var disks: Int
    /// 柱 3 本。各柱は下から上へ円盤の大きさ。
    public var pegs: [[Int]]
    public var moves: Int
    public var elapsedSeconds: Int

    public init(disks: Int, pegs: [[Int]], moves: Int, elapsedSeconds: Int) {
        self.disks = disks
        self.pegs = pegs
        self.moves = moves
        self.elapsedSeconds = elapsedSeconds
    }

    /// 続きから再開できる中断データか（正しい盤・まだ揃っていない・1 手以上動かした）。
    /// `HanoiModel.init` の復元と `HanoiModule.hasResumableSnapshot` の両方がこれを使う。
    public static func isResumable(_ snap: HanoiSnapshot) -> Bool {
        HanoiLogic.isValid(snap.pegs, disks: snap.disks)
            && !HanoiLogic.isSolved(snap.pegs, disks: snap.disks)
            && snap.moves > 0
    }
}
