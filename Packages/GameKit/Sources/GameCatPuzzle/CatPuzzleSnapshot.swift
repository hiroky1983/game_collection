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
    /// ヒントで置いた猫のマス（印付き・消せない）。鍵は optional で足してある（鍵の無い旧データも読める）。
    public var hintCells: [Int]?
    /// ヒントで置いた × のマス（印付き・消せない）。同じく optional。
    public var hintCrosses: [Int]?
    /// 答えでないマスに猫を置こうとして付いた固定の赤い ×（消せない）。同じく optional。
    public var wrongCrosses: [Int]?

    public init(size: String, puzzle: CatPuzzle, marks: [Int], elapsedSeconds: Int,
                mistakes: Int, hintsUsed: Int, hintCells: [Int]? = nil, hintCrosses: [Int]? = nil,
                wrongCrosses: [Int]? = nil) {
        self.size = size
        self.puzzle = puzzle
        self.marks = marks
        self.elapsedSeconds = elapsedSeconds
        self.mistakes = mistakes
        self.hintsUsed = hintsUsed
        self.hintCells = hintCells
        self.hintCrosses = hintCrosses
        self.wrongCrosses = wrongCrosses
    }

    /// 続きから再開できる中断データか（正しい問題・印が 1 つ以上・まだ解けていない・ミスが上限に届いていない）。
    /// `CatPuzzleModel.init` の復元と `CatPuzzleModule.hasResumableSnapshot` の両方がこれを使う。
    /// ミス 3 回で負けの決まり（build 43 の QA）より前の中断データでミスが上限以上のものは、終局済みとして捨てる。
    public static func isResumable(_ snap: CatPuzzleSnapshot) -> Bool {
        guard isWellFormed(snap), snap.mistakes < CatPuzzleModel.maxMistakes else { return false }
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
        // ヒントで置いた猫は盤の中にあり、そのマスの印は猫。
        for cell in snap.hintCells ?? [] {
            guard (0..<snap.puzzle.cellCount).contains(cell), snap.marks[cell] == CatPuzzleModel.Mark.cat.rawValue else { return false }
        }
        // ヒントで置いた × と赤い × も盤の中にあり、そのマスの印は ×。
        for cell in (snap.hintCrosses ?? []) + (snap.wrongCrosses ?? []) {
            guard (0..<snap.puzzle.cellCount).contains(cell), snap.marks[cell] == CatPuzzleModel.Mark.cross.rawValue else { return false }
        }
        // 赤い × は答えでないマスにしか付かない（答えのマスに固定の × があると解けなくなる）。
        let solution = Set(snap.puzzle.solutionCells)
        guard (snap.wrongCrosses ?? []).allSatisfy({ !solution.contains($0) }) else { return false }
        return true
    }
}
