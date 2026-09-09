import Foundation

/// 局面（盤面 + 手番 + コウ + 連続パス数 + スーパーコウ履歴）。
///
/// **ルールの正誤はすべてこの型に閉じる**。Model も MCTS も同じ `play(_:)` を通すので、
/// 「対局では合法だが CPU の読みでは非合法」といったズレが構造的に起きない（#398 のテスト計画は
/// この 1 か所を機械検証すれば足りる、という設計に乗っている）。
///
/// ルールは**中国ルール（面積計算）**。禁じ手は自殺手とコウの即時取り返し、加えて
/// **位置的スーパーコウ**（同一盤面の再現禁止）で長生・三コウの無限ループを止める。
public struct GoState: Sendable {
    public private(set) var board: GoBoard
    public private(set) var sideToMove: GoStone
    /// 直前の着手で 1 子を取った結果、すぐには取り返せない交点。
    public private(set) var koPoint: GoPoint?
    /// 連続したパスの回数。2 で終局判定に入る。
    public private(set) var consecutivePasses: Int
    /// これまでの手数（パスを含む）。
    public private(set) var moveNumber: Int
    /// 取った石の数（`captures[GoStone.black.rawValue]` = 黒が取った数）。
    /// 面積計算では使わないが、対局中の表示に出す。
    public private(set) var captures: [Int]

    /// 位置的スーパーコウの履歴（これまでに現れた盤面）。
    ///
    /// **MCTS のプレイアウトでは nil にする**。81 点ぶんの配列を毎手ハッシュ化すると
    /// プレイアウトが桁で遅くなり、1 手 1 秒の上限に入らない。プレイアウト中は単純コウだけを
    /// 見れば十分で（読みの精度に対する影響より速度のほうが効く）、対局そのものの合法性は
    /// 常にこちら（履歴あり）の `GoState` が担保する。
    private var positionHistory: Set<GoBoard>?

    public var size: Int { board.size }
    /// 両者がパスして終局条件を満たしたか。
    public var isTwoPassEnd: Bool { consecutivePasses >= 2 }
    /// 位置的スーパーコウを見ているか（対局は true、プレイアウトは false）。
    public var tracksSuperko: Bool { positionHistory != nil }

    /// - Parameter tracksSuperko: 位置的スーパーコウを見るか。対局は true、プレイアウトは false。
    public init(
        board: GoBoard = GoBoard(),
        sideToMove: GoStone = .black,
        tracksSuperko: Bool = true
    ) {
        self.board = board
        self.sideToMove = sideToMove
        self.koPoint = nil
        self.consecutivePasses = 0
        self.moveNumber = 0
        self.captures = [0, 0]
        self.positionHistory = tracksSuperko ? [board] : nil
    }

    /// 置き石を並べた初期局面。置き石があるときの手番は白（黒が先に置いているため）。
    public static func initial(ruleset: GoRuleset, tracksSuperko: Bool = true) -> GoState {
        var board = GoBoard(size: ruleset.size)
        let stones = ruleset.handicapPoints()
        for point in stones { board[point] = .black }
        return GoState(
            board: board,
            sideToMove: stones.isEmpty ? .black : .white,
            tracksSuperko: tracksSuperko
        )
    }

    /// スーパーコウ履歴を持たない軽い複製（プレイアウト用）。
    public func playoutCopy() -> GoState {
        var copy = self
        copy.positionHistory = nil
        return copy
    }

    // MARK: - 連と呼吸点

    /// `point` の石が属する連と、その呼吸点の数。空点を渡すと空の結果を返す。
    ///
    /// 表示・テスト用の素直な実装。着手のたびに呼ぶ経路では、確保の無い
    /// `hasLiberties(at:on:atLeast:)` のほうを使う。
    public func group(at point: GoPoint) -> (stones: [GoPoint], liberties: Int) {
        Self.group(at: point, on: board)
    }

    static func group(at point: GoPoint, on board: GoBoard) -> (stones: [GoPoint], liberties: Int) {
        guard let color = board[point] else { return ([], 0) }
        var visited = [Bool](repeating: false, count: board.pointCount)
        var libertySeen = [Bool](repeating: false, count: board.pointCount)
        var stones: [GoPoint] = []
        var liberties = 0
        var stack = [point]
        visited[point.row * board.size + point.col] = true

        while let current = stack.popLast() {
            stones.append(current)
            board.forEachNeighbor(of: current) { neighbor in
                let index = neighbor.row * board.size + neighbor.col
                switch board[neighbor] {
                case nil:
                    if !libertySeen[index] {
                        libertySeen[index] = true
                        liberties += 1
                    }
                case .some(let other) where other == color:
                    if !visited[index] {
                        visited[index] = true
                        stack.append(neighbor)
                    }
                default:
                    break
                }
            }
        }
        return (stones, liberties)
    }

    /// `start` の連が呼吸点を `threshold` 個以上持つか。
    ///
    /// **ヒープ確保をしない**（`withUnsafeTemporaryAllocation` = 実質スタック）ことと、
    /// 閾値に達した時点で打ち切ることの 2 点で、素直な `group(at:)` より桁で速い。
    /// 合法性の判定は「呼吸点が 2 以上あるか」しか要らないため、この形で足りる
    /// （プレイアウトが 1 手あたり数回これを呼ぶので、ここの速さがそのまま CPU の強さになる）。
    static func hasLiberties(at start: GoPoint, on board: GoBoard, atLeast threshold: Int) -> Bool {
        guard let color = board[start] else { return false }
        guard threshold > 0 else { return true }
        let size = board.size
        let count = board.pointCount

        return board.cells.withUnsafeBufferPointer { cells in
            withUnsafeTemporaryAllocation(of: UInt8.self, capacity: count * 2) { flags in
                flags.initialize(repeating: 0)
                return withUnsafeTemporaryAllocation(of: Int32.self, capacity: count) { stack in
                    var top = 0
                    var found = 0
                    let startIndex = start.row * size + start.col
                    flags[startIndex] = 1
                    stack[top] = Int32(startIndex)
                    top += 1

                    while top > 0 {
                        top -= 1
                        let index = Int(stack[top])
                        let row = index / size
                        let col = index % size

                        // 4 近傍はインラインで展開する（配列を作らない）。
                        for offset in 0..<4 {
                            let neighborIndex: Int
                            switch offset {
                            case 0: neighborIndex = row > 0 ? index - size : -1
                            case 1: neighborIndex = row < size - 1 ? index + size : -1
                            case 2: neighborIndex = col > 0 ? index - 1 : -1
                            default: neighborIndex = col < size - 1 ? index + 1 : -1
                            }
                            guard neighborIndex >= 0 else { continue }
                            if let stone = cells[neighborIndex] {
                                guard stone == color, flags[neighborIndex] == 0 else { continue }
                                flags[neighborIndex] = 1
                                stack[top] = Int32(neighborIndex)
                                top += 1
                            } else if flags[count + neighborIndex] == 0 {
                                flags[count + neighborIndex] = 1
                                found += 1
                                if found >= threshold { return true }
                            }
                        }
                    }
                    return false
                }
            }
        }
    }

    // MARK: - 合法性

    /// 着手の周辺だけを見た判定結果。盤面を複製しないので確保が起きない。
    private struct NeighborAnalysis {
        /// 自殺手でない（打った石の連に呼吸点が残る）。
        var isLegal: Bool
        /// 相手の石を取る手である（スーパーコウの照合が要るのはこのときだけ）。
        var captures: Bool
        /// 打った石が同色とつながらない単独の石になる（単純コウの判定に使う）。
        var isolated: Bool
    }

    private func analyzeNeighbors(of point: GoPoint, for color: GoStone) -> NeighborAnalysis {
        var hasEmptyNeighbor = false
        var connectsToSafeGroup = false
        var captures = false
        var isolated = true

        board.forEachNeighbor(of: point) { neighbor in
            switch board[neighbor] {
            case nil:
                hasEmptyNeighbor = true
            case .some(let stone) where stone == color:
                isolated = false
                // `point` はこの連の呼吸点なので、ほかにも呼吸点があれば打った後も生きる。
                if !connectsToSafeGroup, Self.hasLiberties(at: neighbor, on: board, atLeast: 2) {
                    connectsToSafeGroup = true
                }
            case .some:
                // 隣接する相手の連の呼吸点は必ず 1 以上（`point` がそれ）。
                // 2 個目が無い = 呼吸点は `point` だけ = この手で取れる。
                if !captures, !Self.hasLiberties(at: neighbor, on: board, atLeast: 2) {
                    captures = true
                }
            }
        }
        return NeighborAnalysis(
            isLegal: hasEmptyNeighbor || connectsToSafeGroup || captures,
            captures: captures,
            isolated: isolated
        )
    }

    /// 打てない理由。合法なら nil。
    public func illegalReason(for move: GoMove) -> GoIllegalMove? {
        guard !isTwoPassEnd else { return .gameOver }
        guard case .play(let point) = move else { return nil }
        guard board.contains(point) else { return .outOfBoard }
        guard board[point] == nil else { return .occupied }
        if koPoint == point { return .ko }

        let analysis = analyzeNeighbors(of: point, for: sideToMove)
        // 「自殺に見えるが相手の石を取るので合法」は `captures` の側で拾われる。
        guard analysis.isLegal else { return .suicide }

        // 石を取らない手は盤上の石が必ず 1 つ増えるので、過去の盤面と一致しようがない。
        // 履歴の照合（81 点ぶんのハッシュ）は取りが起きるときだけに絞る。
        if analysis.captures, let history = positionHistory {
            var work = board
            _ = Self.applyPlacement(&work, at: point, color: sideToMove)
            if history.contains(work) { return .superko }
        }
        return nil
    }

    public func isLegal(_ move: GoMove) -> Bool { illegalReason(for: move) == nil }

    /// 合法手の一覧（既定でパスを含む）。
    public func legalMoves(includingPass: Bool = true) -> [GoMove] {
        guard !isTwoPassEnd else { return [] }
        var moves: [GoMove] = []
        for point in board.allPoints where board[point] == nil {
            if isLegal(.play(point)) { moves.append(.play(point)) }
        }
        if includingPass { moves.append(.pass) }
        return moves
    }

    // MARK: - 着手

    /// 盤面に石を置き、呼吸点を失った相手の連を取り除く。取った石を返す。
    ///
    /// 合法性の判定は済んでいる前提（`illegalReason(for:)` を先に通すこと）。
    @discardableResult
    static func applyPlacement(_ board: inout GoBoard, at point: GoPoint, color: GoStone) -> [GoPoint] {
        board[point] = color
        var neighbors: [GoPoint] = []
        board.forEachNeighbor(of: point) { neighbors.append($0) }

        var captured: [GoPoint] = []
        for neighbor in neighbors {
            // 先に取った連に含まれていた石はもう空点になっているので自然に飛ばされる。
            guard board[neighbor] == color.opponent else { continue }
            guard !hasLiberties(at: neighbor, on: board, atLeast: 1) else { continue }
            let stones = group(at: neighbor, on: board).stones
            for stone in stones { board[stone] = nil }
            captured.append(contentsOf: stones)
        }
        return captured
    }

    /// 着手する。合法なら nil、非合法なら理由を返して状態は変えない。
    @discardableResult
    public mutating func play(_ move: GoMove) -> GoIllegalMove? {
        if let reason = illegalReason(for: move) { return reason }

        switch move {
        case .pass:
            consecutivePasses += 1
            koPoint = nil
        case .play(let point):
            let color = sideToMove
            let isolated = analyzeNeighbors(of: point, for: color).isolated
            let captured = Self.applyPlacement(&board, at: point, color: color)
            captures[color.rawValue] += captured.count
            // 単純コウ: 1 子だけ取り、打った石が単独で呼吸点 1 になったときだけ、
            // その取った跡が次の 1 手に限り禁止される。
            if captured.count == 1, isolated,
               !Self.hasLiberties(at: point, on: board, atLeast: 2) {
                koPoint = captured[0]
            } else {
                koPoint = nil
            }
            consecutivePasses = 0
            positionHistory?.insert(board)
        }
        sideToMove = sideToMove.opponent
        moveNumber += 1
        return nil
    }

    /// 終局判定から対局へ戻す（簡易死活の誤判定からの復帰導線・#398）。
    /// 連続パス数だけを 0 に戻し、盤面・手番・履歴はそのまま続ける。
    public mutating func resumePlay() {
        consecutivePasses = 0
    }

    // MARK: - 眼（アイ）

    /// `point` が `color` にとっての「単純な眼」か。
    ///
    /// プレイアウトで自分の眼を埋めさせないために使う。埋めることを許すと、ランダム対局が
    /// 自分の生きている石を自分で殺し続けて終局が意味を成さなくなる（＝死活の判定も壊れる）。
    ///
    /// 判定は業界標準の近似: 上下左右がすべて自分の石で、斜めの相手石が
    /// **盤の縁では 0 個・中央では 1 個以下**なら眼とみなす（欠け眼を雑に弾くための条件）。
    public func isSimpleEye(_ point: GoPoint, for color: GoStone) -> Bool {
        guard board[point] == nil else { return false }
        var surrounded = true
        board.forEachNeighbor(of: point) { neighbor in
            if board[neighbor] != color { surrounded = false }
        }
        guard surrounded else { return false }

        var enemyDiagonals = 0
        board.forEachDiagonal(of: point) { diagonal in
            if board[diagonal] == color.opponent { enemyDiagonals += 1 }
        }
        return enemyDiagonals <= (board.isOnEdge(point) ? 0 : 1)
    }
}
