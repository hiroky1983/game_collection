import Foundation

/// ヒント 1 回ぶんの中身（`CatPuzzleLogic.hint`）。**答えを置くのではなく、推理の 1 歩**を示す
/// （会長 QA 2026-10-21・build 41「ヒント＝正解になっている」）。
///
/// いまの盤（置いた猫・×）から「確実に言えること」を 1 つ選び、`crossed` に × を置く。猫が確定する
/// ときだけ `placed` に猫を置く。決まり違反・答えと合わない猫があれば `removed` で × に変える。
/// `highlights` は理由に関わる行・列・部屋（盤で光らせる）。
public struct CatPuzzleHint: Equatable, Sendable {
    /// 行・列・部屋のいずれか（理由の文と光らせる範囲に使う）。
    public enum Group: Hashable, Sendable {
        case row(Int)
        case column(Int)
        case room(Int)
    }

    /// 推理の種類（理由の文の元）。優先順もこの並び（`CatPuzzleLogic.hint`）。
    public enum Reason: Equatable, Sendable {
        /// (a) 決まり違反・答えと合わない猫を外す。`violation` はその猫が関わる違反の種類（無ければ答えと合わないだけ）。
        case wrongCat(cell: Int, violation: CatPuzzleViolations.Kind?)
        /// (b)(c)(f) `sources` の猫が入れる場所が `targets` の中だけ → `targets` のほかのマスは ×。
        /// 例: 台所（sources）は 2 列目（targets）にしかない。3 行目（sources）の候補は台所（targets）の中だけ。
        case confined(sources: [Group], targets: [Group])
        /// (d) 置いた猫の行・列・部屋と隣のマスに、ほかの猫はいない。
        case aroundCat(cell: Int)
        /// (e) `group` で猫が入れるマスが 1 つだけ → 猫が確定。
        case onlyCell(group: Group, cell: Int)
        /// (g) ここに猫がいると `blocked` に猫が入れなくなる → ×。
        case wouldBlock(cell: Int, blocked: Group)
        /// (h) ここに猫がいると、決まるマスを順に埋めていくと `blocked` に猫が入れなくなる → ×。
        case wouldBlockChain(cell: Int, blocked: Group)
        /// 推理では決まらない盤の最後の手段: 答えの猫を 1 匹置く。
        case forced(cell: Int)
    }

    public let reason: Reason
    /// 猫を置くマス（確定したときだけ）。
    public let placed: Int?
    /// 新しく × にする空きマス（昇順）。
    public let crossed: [Int]
    /// × に変える猫のマス（昇順）。
    public let removed: [Int]
    /// 理由に関わる行・列・部屋。
    public let highlights: [Group]

    public init(reason: Reason, placed: Int? = nil, crossed: [Int] = [], removed: [Int] = [], highlights: [Group] = []) {
        self.reason = reason
        self.placed = placed
        self.crossed = crossed
        self.removed = removed
        self.highlights = highlights
    }

    /// 盤を変えるか（必ず true を返す値だけを `CatPuzzleLogic.hint` が返す）。
    public var changesBoard: Bool { placed != nil || !crossed.isEmpty || !removed.isEmpty }
}

extension CatPuzzleLogic {

    // MARK: - ヒント（推理の 1 歩）

    /// 次のヒント（会長の決まり・2026-10-21、#2250）。解けていれば nil。返す値は必ず盤を 1 歩進める。
    ///
    /// 優先順:
    /// (a) 答えでない位置の猫があれば、それを外す（決まり違反の猫を先に）。
    /// (b) 部屋の猫が入れる場所が 1 行／1 列に収まっている → その行／列のほかのマスは ×。
    /// (c) 行／列の猫が入れる場所が 1 部屋の中だけ → その部屋のほかのマスは ×。
    /// (d) 置いた猫の行・列・部屋と隣のマスは ×。
    /// (e) 行・列・部屋で猫が入れるマスが 1 つだけ → 猫が確定。
    /// (f) 2〜3 の部屋（行・列）の入れる場所が同じ 2〜3 の行・列（部屋）に収まる → ほかのマスは ×。
    /// (g) そのマスに猫がいると、どこかの行・列・部屋に猫が入れなくなる → ×。
    /// (h) そのマスに猫がいると、入れるマスが 1 つだけの行・列・部屋を順に埋めていくと、どこかに猫が入れなくなる → ×。
    /// 最後の手段: どれも無ければ答えの猫を 1 匹置く（`forced`）。
    ///
    /// 「猫が入れる場所」は、置いた猫（全部正しい）が消すマスと、答えのマスでない × から求める。
    /// 答えのマスに置いた × は信じない（そのマスは入れる場所に残す）ので、どの推理も答えと矛盾しない。
    /// × を置くのは空きマスだけ（すでに × のマスしか変えない推理は飛ばす）。
    public static func hint(puzzle: CatPuzzle, marks: [CatPuzzleModel.Mark]) -> CatPuzzleHint? {
        let n = puzzle.side
        let solution = Set(puzzle.solutionCells)
        let cats = marks.indices.filter { marks[$0] == .cat }
        guard !isSolved(puzzle: puzzle, cats: cats) else { return nil }

        // (a) 答えでない位置の猫。決まり違反に関わっている猫を先に、同じなら番号の若い順。
        let wrong = cats.filter { !solution.contains($0) }
        if !wrong.isEmpty {
            let current = violations(puzzle: puzzle, cats: cats)
            let cell = wrong.first { current.cells.contains($0) } ?? wrong[0]
            let kind = violationKind(of: cell, among: cats, puzzle: puzzle)
            var highlights: [CatPuzzleHint.Group] = []
            switch kind {
            case .row: highlights = [.row(cell / n)]
            case .column: highlights = [.column(cell % n)]
            case .room: highlights = [.room(puzzle.rooms[cell])]
            case .adjacent, .none: break
            }
            return CatPuzzleHint(reason: .wrongCat(cell: cell, violation: kind), removed: [cell], highlights: highlights)
        }

        // ここから先、置いてある猫は全部答え。
        let board = DeductionBoard(puzzle: puzzle, marks: marks, cats: cats)

        // (b) 部屋 → 行／列。(c) 行／列 → 部屋。
        for (source, targets) in [(GroupKind.room, [GroupKind.row, .column]), (.row, [.room]), (.column, [.room])] {
            for target in targets {
                if let hint = board.confined(size: 1, source: source, target: target) { return hint }
            }
        }

        // (d) 猫の周り。
        for cat in cats {
            let around = board.cellsRuledOut(by: cat).filter { marks[$0] == .empty }.sorted()
            if !around.isEmpty {
                return CatPuzzleHint(
                    reason: .aroundCat(cell: cat), crossed: around,
                    highlights: [.row(cat / n), .column(cat % n), .room(puzzle.rooms[cat])]
                )
            }
        }

        // (e) 入れるマスが 1 つだけ。
        for kind in [GroupKind.room, .row, .column] {
            for index in 0..<n where !board.isDecided(kind, index) {
                let candidates = board.candidates(kind, index)
                if candidates.count == 1 {
                    let group = kind.group(index)
                    return CatPuzzleHint(reason: .onlyCell(group: group, cell: candidates[0]), placed: candidates[0], highlights: [group])
                }
            }
        }

        // (f) 2〜3 組。
        for size in 2...3 {
            for source in GroupKind.allCases {
                for target in GroupKind.allCases where target != source {
                    if let hint = board.confined(size: size, source: source, target: target) { return hint }
                }
            }
        }

        // (g) 置いてみると、どこかに猫が入れなくなる。
        for cell in 0..<(n * n) where board.possible[cell] && marks[cell] == .empty {
            if let blocked = board.groupBlocked(byCatAt: cell) {
                return CatPuzzleHint(reason: .wouldBlock(cell: cell, blocked: blocked), crossed: [cell], highlights: [blocked])
            }
        }

        // (h) 置いてみて、決まるマスを順に埋めていくと、どこかに猫が入れなくなる。
        for cell in 0..<(n * n) where board.possible[cell] && marks[cell] == .empty {
            if let blocked = board.groupBlockedByChain(fromCatAt: cell) {
                return CatPuzzleHint(reason: .wouldBlockChain(cell: cell, blocked: blocked), crossed: [cell], highlights: [blocked])
            }
        }

        // 最後の手段: 答えの猫を 1 匹。まだ猫のいない部屋のうち、入れる場所が最も少ない部屋。
        var best: (cell: Int, candidates: Int)?
        for cell in puzzle.solutionCells where marks[cell] != .cat {
            let count = board.candidates(.room, puzzle.rooms[cell]).count
            if best == nil || count < best!.candidates { best = (cell, count) }
        }
        guard let best else { return nil }
        return CatPuzzleHint(reason: .forced(cell: best.cell), placed: best.cell, highlights: [.room(puzzle.rooms[best.cell])])
    }

    /// `cell` の猫が関わる違反の種類（部屋・行・列・隣の順で最初のもの）。無ければ nil。
    static func violationKind(of cell: Int, among cats: [Int], puzzle: CatPuzzle) -> CatPuzzleViolations.Kind? {
        let n = puzzle.side
        let others = cats.filter { $0 != cell }
        if others.contains(where: { puzzle.rooms[$0] == puzzle.rooms[cell] }) { return .room }
        if others.contains(where: { $0 / n == cell / n }) { return .row }
        if others.contains(where: { $0 % n == cell % n }) { return .column }
        if others.contains(where: { isAdjacent($0, cell, side: n) }) { return .adjacent }
        return nil
    }

    /// 行・列・部屋の種類。
    enum GroupKind: CaseIterable {
        case room, row, column

        func group(_ index: Int) -> CatPuzzleHint.Group {
            switch self {
            case .room: .room(index)
            case .row: .row(index)
            case .column: .column(index)
            }
        }
    }

    /// 推理用の盤。`possible[cell]` が「猫が入れる場所」。
    struct DeductionBoard {
        let puzzle: CatPuzzle
        let marks: [CatPuzzleModel.Mark]
        let cats: [Int]
        var possible: [Bool]

        init(puzzle: CatPuzzle, marks: [CatPuzzleModel.Mark], cats: [Int]) {
            self.puzzle = puzzle
            self.marks = marks
            self.cats = cats
            let solution = Set(puzzle.solutionCells)
            var possible = Array(repeating: true, count: puzzle.cellCount)
            // 答えのマスでない × は信じる。答えのマスの × は信じない。
            for cell in marks.indices where marks[cell] == .cross && !solution.contains(cell) { possible[cell] = false }
            for cat in cats {
                possible[cat] = false
                for cell in Self.ruledOut(by: cat, puzzle: puzzle) { possible[cell] = false }
            }
            self.possible = possible
        }

        var n: Int { puzzle.side }

        /// 猫 `cat` が消すマス（同じ行・列・部屋と隣。自分は含まない）。
        static func ruledOut(by cat: Int, puzzle: CatPuzzle) -> [Int] {
            let n = puzzle.side
            return (0..<puzzle.cellCount).filter { cell in
                cell != cat && (cell / n == cat / n || cell % n == cat % n || puzzle.rooms[cell] == puzzle.rooms[cat]
                                || CatPuzzleLogic.isAdjacent(cat, cell, side: n))
            }
        }

        func cellsRuledOut(by cat: Int) -> [Int] { Self.ruledOut(by: cat, puzzle: puzzle) }

        func cells(_ kind: GroupKind, _ index: Int) -> [Int] {
            switch kind {
            case .room: puzzle.cells(inRoom: index)
            case .row: Array((index * n)..<(index * n + n))
            case .column: (0..<n).map { $0 * n + index }
            }
        }

        func groupIndex(_ kind: GroupKind, of cell: Int) -> Int {
            switch kind {
            case .room: puzzle.rooms[cell]
            case .row: cell / n
            case .column: cell % n
            }
        }

        /// その行・列・部屋にすでに猫がいるか。
        func isDecided(_ kind: GroupKind, _ index: Int) -> Bool {
            cats.contains { groupIndex(kind, of: $0) == index }
        }

        /// 猫が入れるマス（昇順）。
        func candidates(_ kind: GroupKind, _ index: Int) -> [Int] {
            cells(kind, index).filter { possible[$0] }
        }

        /// `source` の `size` 個の組で、入れる場所が `target` のちょうど `size` 個に収まっているものを探し、
        /// その `target` のほかの空きマスを × にするヒントを返す。組は番号の若い順に調べ、最初に盤が進むものを返す。
        func confined(size: Int, source: GroupKind, target: GroupKind) -> CatPuzzleHint? {
            let undecided = (0..<n).filter { !isDecided(source, $0) }
            guard undecided.count >= size else { return nil }
            let targetSets: [Int: Set<Int>] = Dictionary(uniqueKeysWithValues: undecided.map { index in
                (index, Set(candidates(source, index).map { groupIndex(target, of: $0) }))
            })
            for combo in Self.combinations(of: undecided, size: size) {
                let union = combo.reduce(into: Set<Int>()) { $0.formUnion(targetSets[$1]!) }
                guard union.count == size else { continue }
                let sourceSet = Set(combo)
                let crossed = union.sorted().flatMap { cells(target, $0) }
                    .filter { possible[$0] && marks[$0] == .empty && !sourceSet.contains(groupIndex(source, of: $0)) }
                    .sorted()
                guard !crossed.isEmpty else { continue }
                let sources = combo.map(source.group)
                let targets = union.sorted().map(target.group)
                return CatPuzzleHint(reason: .confined(sources: sources, targets: targets), crossed: crossed, highlights: sources + targets)
            }
            return nil
        }

        /// `cell` に猫を置いたと仮定すると、入れるマスが無くなる行・列・部屋（部屋・行・列の順で最初のもの）。
        func groupBlocked(byCatAt cell: Int) -> CatPuzzleHint.Group? {
            let ruledOut = Set(cellsRuledOut(by: cell))
            for kind in GroupKind.allCases {
                for index in 0..<n where !isDecided(kind, index) && groupIndex(kind, of: cell) != index {
                    if candidates(kind, index).allSatisfy({ ruledOut.contains($0) }) { return kind.group(index) }
                }
            }
            return nil
        }

        /// `cell` に猫を置いたと仮定し、入れるマスが 1 つだけになった行・列・部屋へ順に猫を置いていく。
        /// 途中でどこかの行・列・部屋に入れるマスが無くなれば、その行・列・部屋（最初に見つかったもの）。無ければ nil。
        func groupBlockedByChain(fromCatAt cell: Int) -> CatPuzzleHint.Group? {
            var trial = possible
            var placed = cats + [cell]
            trial[cell] = false
            for ruled in cellsRuledOut(by: cell) { trial[ruled] = false }
            func decided(_ kind: GroupKind, _ index: Int) -> Bool { placed.contains { groupIndex(kind, of: $0) == index } }
            var changed = true
            while changed {
                changed = false
                for kind in GroupKind.allCases {
                    for index in 0..<n where !decided(kind, index) {
                        let candidates = cells(kind, index).filter { trial[$0] }
                        if candidates.isEmpty { return kind.group(index) }
                        if candidates.count == 1 {
                            let next = candidates[0]
                            placed.append(next)
                            trial[next] = false
                            for ruled in cellsRuledOut(by: next) { trial[ruled] = false }
                            changed = true
                        }
                    }
                }
            }
            return nil
        }

        /// `items` から `size` 個を選ぶ組み合わせ（辞書順）。
        static func combinations(of items: [Int], size: Int) -> [[Int]] {
            guard size > 0 else { return [[]] }
            guard items.count >= size else { return [] }
            var result: [[Int]] = []
            for (offset, item) in items.enumerated() {
                for rest in combinations(of: Array(items[(offset + 1)...]), size: size - 1) {
                    result.append([item] + rest)
                }
            }
            return result
        }
    }
}
