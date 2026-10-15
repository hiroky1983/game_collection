import Core
import Observation

/// 線つなぎ（#2235）のゲーム状態。問題・描いた線・手数を保持し、永続化サービスへ中断スナップショットを書く。
/// 生成・判定の純粋ロジックは `TsunagiLogic` に委譲し、ここは線の引き方・永続化・決着管理を担う。
///
/// 線の引き方:
/// - 点から指でなぞると、その数字の線を引き直す（前に引いた線は消える）。
/// - 線の途中から触ると、そこまで戻して続きを引く。来た道を戻ると線が縮む。
/// - 別の数字の線に触れると、その線を触れたマスから先で切る。別の数字の点には入れない。
/// - 全部の数字がつながり、全マスが埋まったらクリア。
@MainActor
@Observable
public final class TsunagiModel {
    /// 解析・記録・中断データの ID。`TsunagiModule.id` と同じ。
    public nonisolated static let gameID = "tsunagi"

    public private(set) var size: TsunagiSize
    public private(set) var puzzle: TsunagiPuzzle
    /// 数字ごとの描いた線。`paths[k]` は数字 `k + 1` の点から始まるマスの並び（描いていなければ空）。
    public private(set) var paths: [[Int]]
    /// 手数。別の数字の線に持ち替えるたびに 1 増える（同じ数字を続けて直すあいだは増えない）。
    public private(set) var moves: Int = 0
    public private(set) var isSolved = false
    /// 直近の決着で確定した自己ベスト。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// いま引いている線の数字（0 始まり）。指を離すと nil（VoiceOver の操作では選んだまま残す）。
    public private(set) var activeColor: Int?
    /// マスごとの持ち主（数字の番号・空きは nil）。点は線を引いていなくても持ち主がある。
    public private(set) var owners: [Int?]

    private let services: GameServices?
    private var generator: SplitMix64?
    /// 直前に線を変えた数字（手数の数え方に使う）。
    private var lastMovedColor: Int?
    /// 1 回のなぞりの始まりの線（変化があったかの判定に使う）。
    private var strokeStartPaths: [[Int]]?

    /// services を渡すと、中断スナップショットがあれば復元、無ければ新規開始する。
    /// `seed` を渡すと問題を種から決める（テスト用。省略時はシステム乱数）。
    public init(services: GameServices? = nil, size: TsunagiSize = .small, seed: UInt64? = nil) {
        self.services = services
        var seeded = seed.map { SplitMix64(seed: $0) }
        if let snap = services?.snapshots.load(TsunagiSnapshot.self, for: Self.gameID),
           let restoredSize = TsunagiSize(rawValue: snap.size),
           Self.isValid(snap, size: restoredSize) {
            self.size = restoredSize
            puzzle = snap.puzzle
            paths = snap.paths
            moves = snap.moves
            // 範囲外の値（壊れた中断データ）は無かったことにする。
            lastMovedColor = snap.lastMovedColor.flatMap { (0..<snap.puzzle.pairCount).contains($0) ? $0 : nil }
            owners = Self.owners(puzzle: snap.puzzle, paths: snap.paths)
        } else {
            self.size = size
            let made = Self.makePuzzle(size: size, generator: &seeded)
            let empty = Array(repeating: [Int](), count: made.pairCount)
            puzzle = made
            paths = empty
            owners = Self.owners(puzzle: made, paths: empty)
            // 中断からの復元は「新しいプレイ」ではないので開始は数えない。
            services?.gameDidStart(gameID: Self.gameID, level: size.analyticsLevel)
        }
        generator = seeded
        persist()
    }

    /// 問題を直接与えて開始する。狙った局面から検証するためのテスト用の経路。
    public init(services: GameServices? = nil, puzzle: TsunagiPuzzle, size: TsunagiSize = .small) {
        self.services = services
        self.size = size
        self.puzzle = puzzle
        let empty = Array(repeating: [Int](), count: puzzle.pairCount)
        paths = empty
        owners = Self.owners(puzzle: puzzle, paths: empty)
        persist()
    }

    // MARK: - 線を引く

    /// なぞり始め。点なら線を引き直し、線の途中ならそこまで戻す。空きマスからは始めない。
    public func beginStroke(at cell: Int) {
        guard !isSolved, puzzle.cellCount > cell, cell >= 0 else { return }
        strokeStartPaths = paths
        if let color = puzzle.endpointColor(at: cell) {
            paths[color] = [cell]
            activeColor = color
        } else if let color = owners[cell], let index = paths[color].firstIndex(of: cell) {
            paths[color] = Array(paths[color].prefix(index + 1))
            activeColor = color
        } else {
            activeColor = nil
            strokeStartPaths = nil
            return
        }
        refreshOwners()
    }

    /// なぞっている指が `cell` に入った。隣でないマスへ飛んだときは、縦・横の順に 1 マスずつ追う。
    public func extendStroke(to cell: Int) {
        guard !isSolved, let color = activeColor, let head = paths[color].last,
              cell >= 0, cell < puzzle.cellCount, cell != head else { return }
        if paths[color].contains(cell) {
            stepStroke(color: color, to: cell)
            return
        }
        let side = puzzle.side
        var current = head
        while current != cell {
            let row = current / side, col = current % side
            let targetRow = cell / side, targetCol = cell % side
            let next: Int
            if col != targetCol {
                next = current + (targetCol > col ? 1 : -1)
            } else {
                next = current + (targetRow > row ? side : -side)
            }
            guard stepStroke(color: color, to: next) else { break }
            current = next
        }
    }

    /// なぞり終わり。線が変わっていれば手数を数え、全部つながって埋まっていればクリア。
    public func endStroke() {
        defer {
            strokeStartPaths = nil
            activeColor = nil
        }
        commitStroke()
    }

    /// VoiceOver の操作（#2235 の受け入れ条件）。点か線のマスを選ぶと、その数字を「選んだ」状態にし、
    /// 続けて線の先端の隣のマスを選ぶと 1 マスずつ伸ばす。選んだ数字は次の操作まで残す。
    public func activate(cell: Int) {
        guard !isSolved, cell >= 0, cell < puzzle.cellCount else { return }
        if let color = activeColor, let head = paths[color].last,
           TsunagiLogic.isAdjacent(head, cell, side: puzzle.side) || paths[color].contains(cell),
           puzzle.endpointColor(at: cell) == nil || puzzle.endpointColor(at: cell) == color {
            strokeStartPaths = paths
            extendStroke(to: cell)
            commitStroke()
            activeColor = isSolved || isComplete(color) ? nil : color
            return
        }
        beginStroke(at: cell)
        let selected = activeColor
        commitStroke()
        activeColor = isSolved ? nil : selected
    }

    /// 数字 `color` の線が両方の点をつないでいるか。
    public func isComplete(_ color: Int) -> Bool {
        TsunagiLogic.isComplete(path: paths[color], endpoints: puzzle.endpoints[color], side: puzzle.side)
    }

    /// つながった数字の数。
    public var connectedCount: Int { (0..<puzzle.pairCount).filter(isComplete).count }

    /// 埋まったマスの数（点を含む）。
    public var filledCount: Int { owners.compactMap { $0 }.count }

    /// 全部つながったのに空きマスが残っている（クリアにならない理由を出す）。
    public var isConnectedButNotFilled: Bool {
        !isSolved && connectedCount == puzzle.pairCount && filledCount < puzzle.cellCount
    }

    /// 「新規」で失われる進行があるか（#1011）。1 本も引いていない盤と解き終えた盤は捨てて構わない。
    public var hasProgressToLose: Bool { moves > 0 && !isSolved }

    /// 新規ゲーム。`size` を渡すと盤の大きさを変える。
    public func newGame(size newSize: TsunagiSize? = nil) {
        if let newSize { size = newSize }
        puzzle = Self.makePuzzle(size: size, generator: &generator)
        paths = Array(repeating: [], count: puzzle.pairCount)
        moves = 0
        isSolved = false
        recordResult = nil
        activeColor = nil
        lastMovedColor = nil
        strokeStartPaths = nil
        refreshOwners()
        persist()
        services?.gameDidRestart(gameID: Self.gameID, level: size.analyticsLevel)
    }

    // MARK: - 内部

    /// 先端から隣の `cell` へ 1 マス進む（線の上なら戻る）。進めなければ false。
    @discardableResult
    private func stepStroke(color: Int, to cell: Int) -> Bool {
        if let index = paths[color].firstIndex(of: cell) {
            paths[color] = Array(paths[color].prefix(index + 1))
            refreshOwners()
            return true
        }
        guard let head = paths[color].last,
              TsunagiLogic.isAdjacent(head, cell, side: puzzle.side),
              !isComplete(color) else { return false }
        if let endpoint = puzzle.endpointColor(at: cell) {
            // 別の数字の点には入れない。自分のもう一方の点に着いたら、この線は完成。
            guard endpoint == color else { return false }
            paths[color].append(cell)
            refreshOwners()
            return true
        }
        if let other = owners[cell], other != color, let index = paths[other].firstIndex(of: cell) {
            // 別の数字の線に触れたら、その線を触れたマスから先で切る。
            paths[other] = Array(paths[other].prefix(index))
        }
        paths[color].append(cell)
        refreshOwners()
        return true
    }

    private func commitStroke() {
        guard let start = strokeStartPaths, let color = activeColor else { return }
        strokeStartPaths = nil
        guard paths != start else { return }
        if lastMovedColor != color {
            moves += 1
            lastMovedColor = color
        }
        // 線が変わった = 捨てたら途中離脱として数える盤面。
        services?.gameDidProgress(gameID: Self.gameID)
        if TsunagiLogic.isSolved(puzzle: puzzle, paths: paths) {
            isSolved = true
            activeColor = nil
            services?.feedback.notify(.success)
            // 決着 1 回につき `gameDidFinish` は 1 回だけ呼ぶ。
            recordResult = services?.gameDidFinish(
                gameID: Self.gameID,
                outcome: .win,
                score: GameScore(
                    metric: .fewestMoves, moves: moves,
                    variant: size.recordVariant, variantLabel: size.recordVariantLabel
                )
            )
            services?.snapshots.clear(for: Self.gameID)
        } else {
            services?.feedback.impact(isComplete(color) ? .medium : .light)
            persist()
        }
    }

    private func refreshOwners() {
        owners = Self.owners(puzzle: puzzle, paths: paths)
    }

    private static func owners(puzzle: TsunagiPuzzle, paths: [[Int]]) -> [Int?] {
        var result: [Int?] = Array(repeating: nil, count: puzzle.cellCount)
        for (k, ends) in puzzle.endpoints.enumerated() {
            for cell in ends { result[cell] = k }
        }
        for (k, path) in paths.enumerated() {
            for cell in path { result[cell] = k }
        }
        return result
    }

    private static func makePuzzle(size: TsunagiSize, generator: inout SplitMix64?) -> TsunagiPuzzle {
        if var seeded = generator {
            defer { generator = seeded }
            return TsunagiLogic.generate(size: size, using: &seeded)
        }
        var system = SystemRandomNumberGenerator()
        return TsunagiLogic.generate(size: size, using: &system)
    }

    /// 中断データの健全性。問題の形が正しく、描いた線が点から始まり、隣どうしでつながり、重ならないこと。
    private static func isValid(_ snap: TsunagiSnapshot, size: TsunagiSize) -> Bool {
        let puzzle = snap.puzzle
        guard puzzle.side == size.side, TsunagiLogic.isWellFormed(puzzle),
              snap.paths.count == puzzle.pairCount, snap.moves >= 0,
              !TsunagiLogic.isSolved(puzzle: puzzle, paths: snap.paths) else { return false }
        var used = Set<Int>()
        for (k, path) in snap.paths.enumerated() where !path.isEmpty {
            guard puzzle.endpoints[k].contains(path[0]) else { return false }
            for (i, cell) in path.enumerated() {
                guard cell >= 0, cell < puzzle.cellCount, used.insert(cell).inserted else { return false }
                if i > 0, !TsunagiLogic.isAdjacent(path[i - 1], cell, side: puzzle.side) { return false }
                if let endpoint = puzzle.endpointColor(at: cell), endpoint != k { return false }
            }
        }
        return true
    }

    private func persist() {
        guard !isSolved else { return }
        try? services?.snapshots.save(
            TsunagiSnapshot(size: size.rawValue, puzzle: puzzle, paths: paths, moves: moves, lastMovedColor: lastMovedColor),
            for: Self.gameID
        )
    }
}

extension TsunagiSize {
    /// `game_start` の `level`（#500）。5×5 をやさしい、7×7 をふつうとして送る。
    var analyticsLevel: AnalyticsLevel {
        switch self {
        case .small: .beginner
        case .large: .normal
        }
    }

    /// 記録の区分キー。大きさごとに自己ベストを分ける。
    var recordVariant: String { rawValue }

    /// 記録に保存する区分名（日本語の控え・`RecordVariantLabels` が表示言語で引き直す）。
    var recordVariantLabel: String { RecordVariantLabels.stored(gameID: TsunagiModel.gameID, variant: rawValue) }

    /// 画面に出す名前（「5×5」）。数字と記号だけなので言語で変わらない。
    public var label: String { "\(side)×\(side)" }
}
