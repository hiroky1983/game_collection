import Foundation
import Core

/// 配札が理論上クリアできるかを判定するソルバー（#492 の「全配札クリア可能」の裏付け）。
///
/// 構造はソリティアの `SolitaireSolver` と同じ（最良優先探索 + 同一局面の刈り込みで
/// **勝ち筋を1本見つける**ことだけを目的にする）。上限に達して打ち切った場合は `hitLimit` を立て、
/// **クリア不能とは言い切らない**。
///
/// フリーセル固有の工夫は3つ:
///
/// - **列とセルを並べ替えて正準化する**（`FreeCellBoard.stateKey`）。フリーセルは列の順序が
///   ルールに一切効かないため、正準化しないと「入れ替えただけの局面」を別物として掘り続ける。
/// - **安全な組札送りは分岐させずに即実行する**（`autoplaySafe`）。判定はクロンダイクと同じ。
/// - **退避先の空きセルは1つだけ試す**（`FreeCellBoard.legalMoves` と同じ理由。セルは等価）。
public enum FreeCellSolver {

    public struct Result: Sendable {
        /// 勝ち筋（見つからなければ nil）。先頭から順に `FreeCellBoard.apply` すればクリアに到達する。
        public let solution: [FreeCellMove]?
        public let statesExplored: Int
        /// 最後まで探索せずに打ち切ったか。true のときの `solution == nil` は「不能」ではなく「不明」。
        public let hitLimit: Bool

        public var isSolvable: Bool { solution != nil }
    }

    /// 既定の探索上限。
    ///
    /// 実測（種 1〜1230・Apple Silicon の `-O` ビルド・2026-09-08）で、
    /// **1230 種のうち 1200 種（97.6%）がこの上限内に解けた**（平均 4,563 局面・最悪 59,300 局面・
    /// 1200 個の生成に 175 秒）。最悪値が上限に肉薄しているので、これ以上下げると採用率が落ちる。
    ///
    /// 上げなかったのは、**配札生成は踏破できなかった種を捨てるだけ**だから
    /// （クロンダイク側と同じ判断）。捨てた 30 種は「クリア不能と証明された配札」ではなく
    /// 「このソルバーが上限内に見つけられなかった配札」で、**安全側に落ちている**。
    public static let defaultMaxStates = 60_000

    public static func solve(
        _ board: FreeCellBoard,
        maxStates: Int = defaultMaxStates,
        isCancelled: () -> Bool = { false }
    ) -> Result {
        let (root, rootMoves) = autoplaySafe(board)
        if root.isWon {
            return Result(solution: rootMoves, statesExplored: 1, hitLimit: false)
        }
        var nodes: [Node] = [Node(board: root, parent: -1, movesFromParent: rootMoves)]
        var visited: Set<Data> = [root.stateKey]
        var frontier = Heap()
        frontier.push(priority: heuristic(root), order: 0, node: 0)
        var order = 0

        while let index = frontier.pop() {
            if isCancelled() {
                return Result(solution: nil, statesExplored: nodes.count, hitLimit: true)
            }
            let current = nodes[index].board
            for move in successors(of: current) {
                var next = current
                guard next.apply(move) else { return brokenMove() }
                let (child, autoMoves) = autoplaySafe(next)

                let key = child.stateKey
                guard !visited.contains(key) else { continue }
                visited.insert(key)

                let moves = [move] + autoMoves
                if child.isWon {
                    nodes.append(Node(board: child, parent: index, movesFromParent: moves))
                    return Result(solution: path(to: nodes.count - 1, in: nodes),
                                  statesExplored: nodes.count, hitLimit: false)
                }
                // 上限の判定は**足す前**に行う（`maxStates <= 0` なら根だけ見て打ち切る）。
                if nodes.count >= maxStates {
                    return Result(solution: nil, statesExplored: nodes.count, hitLimit: true)
                }
                nodes.append(Node(board: child, parent: index, movesFromParent: moves))
                order += 1
                frontier.push(priority: heuristic(child), order: order, node: nodes.count - 1)
            }
        }
        return Result(solution: nil, statesExplored: nodes.count, hitLimit: false)
    }

    // MARK: - 内部

    private struct Node {
        let board: FreeCellBoard
        let parent: Int
        let movesFromParent: [FreeCellMove]
    }

    private static func path(to index: Int, in nodes: [Node]) -> [FreeCellMove] {
        var chain: [[FreeCellMove]] = []
        var cursor = index
        while cursor >= 0 {
            chain.append(nodes[cursor].movesFromParent)
            cursor = nodes[cursor].parent
        }
        return chain.reversed().flatMap { $0 }
    }

    /// 局面の見込み（小さいほど良い）。
    ///
    /// 4 項の重み付き和で、いずれもフリーセルで実際に効く指標:
    ///
    /// 1. **組札に載っていない枚数**（×2）— ゴールまでの距離そのもの。
    /// 2. **埋まっているセルの数** — セルは戻せる資源で、埋めっぱなしは詰みへ近づく。
    /// 3. **次に要る札の上に何枚載っているか** — 「A が最下段に埋まっている」局面の重さを表す。
    ///    この項が無いと、盤面を進めない積み替えの海に沈む（クロンダイク側の実測と同じ傾向）。
    /// 4. **空き列**（×2 で減点）— フリーセルで最も価値の高い資源なので、作る手を明確に優遇する。
    static func heuristic(_ board: FreeCellBoard) -> Int {
        let onFoundations = board.foundations.reduce(0, +)
        var score = (52 - onFoundations) * 2
        score += FreeCellBoard.cellCount - board.freeCellCount
        for suit in PlayingCardSuit.allCases {
            let need = board.foundations[suit.rawValue] + 1
            guard need <= 13 else { continue }
            for pile in board.tableau {
                if let index = pile.firstIndex(where: { $0.suit == suit && $0.rank == need }) {
                    score += pile.count - 1 - index
                    break
                }
            }
        }
        score -= board.emptyPileCount * 2
        return score
    }

    /// 最良優先の待ち行列。同じ評価値なら**先に生まれたほうを先に見る**（`order` で安定させる）。
    private struct Heap {
        private var items: [(priority: Int, order: Int, node: Int)] = []

        mutating func push(priority: Int, order: Int, node: Int) {
            items.append((priority, order, node))
            var child = items.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard isHigher(items[child], than: items[parent]) else { break }
                items.swapAt(child, parent)
                child = parent
            }
        }

        mutating func pop() -> Int? {
            guard let first = items.first else { return nil }
            items.swapAt(0, items.count - 1)
            items.removeLast()
            var parent = 0
            while true {
                let left = parent * 2 + 1
                let right = left + 1
                var best = parent
                if left < items.count, isHigher(items[left], than: items[best]) { best = left }
                if right < items.count, isHigher(items[right], than: items[best]) { best = right }
                if best == parent { break }
                items.swapAt(parent, best)
                parent = best
            }
            return first.node
        }

        private func isHigher(_ lhs: (priority: Int, order: Int, node: Int),
                              than rhs: (priority: Int, order: Int, node: Int)) -> Bool {
            lhs.priority != rhs.priority ? lhs.priority < rhs.priority : lhs.order < rhs.order
        }
    }

    /// 生成した手が非合法だったときの保険。ここに来るのは実装の破綻なので探索を止める。
    private static func brokenMove() -> Result {
        assertionFailure("ソルバーが非合法手を生成した")
        return Result(solution: nil, statesExplored: 0, hitLimit: false)
    }

    /// 場札・セルで二度と必要にならないと確定した札を、分岐させずに組札へ送る。
    ///
    /// 判定はクロンダイクと同じ「反対色の組札が2つとも `rank - 1` 以上」。この条件が立つとき、
    /// その札に重ねうる反対色 `rank - 1` の札は2枚とも既に組札にあるので、場札に残す理由が無い。
    /// A と 2 は常に安全。
    static func autoplaySafe(_ board: FreeCellBoard) -> (FreeCellBoard, [FreeCellMove]) {
        var board = board
        var moves: [FreeCellMove] = []
        var didMove = true
        while didMove {
            didMove = false
            for cell in board.cells.indices {
                guard let card = board.cells[cell],
                      board.canSendToFoundation(card), isSafe(card, board) else { continue }
                board.apply(.cellToFoundation(cell: cell))
                moves.append(.cellToFoundation(cell: cell))
                didMove = true
                break
            }
            if didMove { continue }
            for pile in board.tableau.indices {
                guard let card = board.tableau[pile].last,
                      board.canSendToFoundation(card), isSafe(card, board) else { continue }
                board.apply(.tableauToFoundation(pile: pile))
                moves.append(.tableauToFoundation(pile: pile))
                didMove = true
                break
            }
        }
        return (board, moves)
    }

    private static func isSafe(_ card: FreeCellCard, _ board: FreeCellBoard) -> Bool {
        if card.rank <= 2 { return true }
        return opposites(of: card.suit).allSatisfy { board.foundations[$0.rawValue] >= card.rank - 1 }
    }

    /// 反対色の2スート。
    static func opposites(of suit: PlayingCardSuit) -> [PlayingCardSuit] {
        suit.isRed ? [.spade, .club] : [.heart, .diamond]
    }

    /// 次に試す手の並び。組札へ送る → 場札の移し替え → セルから戻す → 退避、の順。
    ///
    /// 最良優先探索では評価値が同じ局面の間でしか順序が効かないので、この並びは
    /// **同点のときの安定した辿り方**のために置いている。
    /// 区別の付かない空列への重複した置き手と、等価な空きセルへの重複した退避はここで落とす。
    static func successors(of board: FreeCellBoard) -> [FreeCellMove] {
        var toFoundation: [FreeCellMove] = []
        var shuffles: [FreeCellMove] = []
        var fromCells: [FreeCellMove] = []
        var toCells: [FreeCellMove] = []

        for pile in board.tableau.indices where board.isLegal(.tableauToFoundation(pile: pile)) {
            toFoundation.append(.tableauToFoundation(pile: pile))
        }
        for cell in board.cells.indices where board.isLegal(.cellToFoundation(cell: cell)) {
            toFoundation.append(.cellToFoundation(cell: cell))
        }

        // 空列は互いに区別が付かないので、置き先の候補は最初の1本だけにする。
        let firstEmptyPile = board.tableau.firstIndex(where: \.isEmpty)

        for from in board.tableau.indices {
            let pile = board.tableau[from]
            for index in pile.indices where board.isOrderedRun(pile: from, from: index) {
                let run = Array(pile[index...])
                // 列を丸ごと空列へ移すのは盤面が進まない（無限の往復の元）。
                let emptiesPile = index == 0
                for to in board.tableau.indices where to != from {
                    guard board.canPlace(run, onPile: to) else { continue }
                    if board.tableau[to].isEmpty {
                        if emptiesPile { continue }
                        guard to == firstEmptyPile else { continue }
                    }
                    shuffles.append(.tableauToTableau(from: from, cardIndex: index, to: to))
                }
            }
        }

        for cell in board.cells.indices where board.cells[cell] != nil {
            for to in board.tableau.indices where board.isLegal(.cellToTableau(cell: cell, to: to)) {
                if board.tableau[to].isEmpty, to != firstEmptyPile { continue }
                fromCells.append(.cellToTableau(cell: cell, to: to))
            }
        }

        if let cell = board.cells.firstIndex(where: { $0 == nil }) {
            for from in board.tableau.indices where !board.tableau[from].isEmpty {
                // 空列から1枚だけ取ってセルへ入れても、列が空になるだけで盤面は進まない。
                if board.tableau[from].count == 1, board.emptyPileCount > 0 { continue }
                toCells.append(.tableauToCell(from: from, cell: cell))
            }
        }

        return toFoundation + shuffles + fromCells + toCells
    }
}
