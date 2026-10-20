/// おじさんの飼い猫パズルの中断スナップショット（#2250）。問題（部屋割りと唯一の答え）・置いた印・
/// 経過秒・ミス・ヒントの使用回数を保存する。問題は乱数の種から作り直さず、そのまま持つ
/// （生成の手順を変えても古い中断データが壊れない）。
public struct CatPuzzleSnapshot: Codable, Equatable, Sendable {
    /// 盤の大きさ（`CatPuzzleSize.rawValue`）。
    public var size: String
    public var puzzle: CatPuzzle
    /// マスごとの印（`CatPuzzleModel.Mark.rawValue`。0 空・1 ×・2 猫）。
    public var marks: [Int]
    public var elapsedSeconds: Int
    public var mistakes: Int
    public var hintsUsed: Int
    /// 出しているヒントのマス（無ければ nil）。
    public var hintCell: Int?

    public init(size: String, puzzle: CatPuzzle, marks: [Int], elapsedSeconds: Int,
                mistakes: Int, hintsUsed: Int, hintCell: Int? = nil) {
        self.size = size
        self.puzzle = puzzle
        self.marks = marks
        self.elapsedSeconds = elapsedSeconds
        self.mistakes = mistakes
        self.hintsUsed = hintsUsed
        self.hintCell = hintCell
    }

    /// 続きから再開できる中断データか（正しい問題・印が 1 つ以上・まだ解けていない）。
    /// `CatPuzzleModel.init` の復元と `CatPuzzleModule.hasResumableSnapshot` の両方がこれを使う。
    public static func isResumable(_ snap: CatPuzzleSnapshot) -> Bool {
        guard isWellFormed(snap) else { return false }
        let cats = snap.marks.indices.filter { snap.marks[$0] == CatPuzzleModel.Mark.cat.rawValue }
        guard !CatPuzzleLogic.isSolved(puzzle: snap.puzzle, cats: cats) else { return false }
        return snap.marks.contains { $0 != CatPuzzleModel.Mark.empty.rawValue }
    }

    /// 保存の形が正しいか（印が 1 つも無い「手つかず」の盤も含む）。
    public static func isWellFormed(_ snap: CatPuzzleSnapshot) -> Bool {
        guard let size = CatPuzzleSize(rawValue: snap.size), snap.puzzle.side == size.side,
              CatPuzzleLogic.isWellFormed(snap.puzzle),
              snap.marks.count == snap.puzzle.cellCount,
              snap.marks.allSatisfy({ CatPuzzleModel.Mark(rawValue: $0) != nil }),
              snap.elapsedSeconds >= 0, snap.mistakes >= 0, snap.hintsUsed >= 0 else { return false }
        if let hint = snap.hintCell, !(0..<snap.puzzle.cellCount).contains(hint) { return false }
        return true
    }
}
