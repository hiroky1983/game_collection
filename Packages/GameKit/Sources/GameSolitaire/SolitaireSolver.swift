import Foundation

/// 配札が理論上クリアできるかを判定するソルバー（#397 の「解けることを保証」の裏付け）。
///
/// 最良優先探索 + 同一局面の刈り込みで**勝ち筋を1本見つける**ことだけを目的にする。
/// 見つかれば「クリア可能」が証明済みになるので、配札生成はこの結果だけを信用すればよい。
/// 上限に達して打ち切った場合は `hitLimit` を立て、**クリア不能とは言い切らない**。
///
/// 探索を現実的な規模に保つために3つの工夫を入れている:
///
/// - **山札は「n 回めくってからその札を使う」を1手として扱う**（`reachableStockCards`）。
///   循環が無制限なので、めくるだけの手を1手ずつ辿ると探索木が縦に伸びるだけで枝が減らない。
/// - **安全な組札送りは分岐させずに即実行する**（`autoplaySafe`）。
///   反対色の組札が両方 `rank-1` 以上まで進んでいれば、その札が場札で必要になることはない。
/// - **最良優先で辿る**（`heuristic`）。組札に載った枚数と伏せ札の残りで局面を採点する。
///   深さ優先だと盤面が進まない組み替えの海に沈む（実測: 同じ 60,000 局面の上限で、
///   深さ優先は 30 配札中 19 しか踏破できず、上限を 300,000 に上げても 21 止まりだった）。
public enum SolitaireSolver {

    public struct Result: Sendable {
        /// 勝ち筋（見つからなければ nil）。先頭から順に `SolitaireBoard.apply` すればクリアに到達する。
        public let solution: [SolitaireMove]?
        public let statesExplored: Int
        /// 探索上限に達して打ち切ったか。true のときの `solution == nil` は「不能」ではなく「不明」。
        public let hitLimit: Bool

        public var isSolvable: Bool { solution != nil }
    }

    /// 既定の探索上限。実測（seed 1〜30・Apple Silicon の -O ビルド）で 1 配札あたり平均 0.20 秒・
    /// 最悪 0.92 秒に収まり、30 配札中 23 で勝ち筋が見つかる。上限を 250,000 に上げると 25 まで
    /// 増えるが平均 0.97 秒・最悪 5.85 秒に伸びる。**配札生成は踏破できなかった種を捨てるだけ**なので、
    /// 取りこぼしより速さを採る（捨てた種は「難しい配札」に偏るが、出題としてはむしろ望ましい）。
    public static let defaultMaxStates = 60_000

    public static func solve(
        _ board: SolitaireBoard,
        allowJoker: Bool = false,
        maxStates: Int = defaultMaxStates
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
            let current = nodes[index].board
            for moves in successors(of: current, allowJoker: allowJoker) {
                var next = current
                for move in moves {
                    guard next.apply(move) else { return brokenMove() }
                }
                let (child, autoMoves) = autoplaySafe(next)

                let key = child.stateKey
                guard !visited.contains(key) else { continue }
                visited.insert(key)

                if child.isWon {
                    nodes.append(Node(board: child, parent: index, movesFromParent: moves + autoMoves))
                    return Result(solution: path(to: nodes.count - 1, in: nodes),
                                  statesExplored: nodes.count, hitLimit: false)
                }
                // 上限の判定は**足す前**に行う。足してから見ると、`maxStates` が探索済みの
                // 局面数より小さいときに上限を1つ超える（`maxStates <= 0` なら根だけ見て打ち切る）。
                if nodes.count >= maxStates {
                    return Result(solution: nil, statesExplored: nodes.count, hitLimit: true)
                }
                nodes.append(Node(board: child, parent: index, movesFromParent: moves + autoMoves))
                order += 1
                frontier.push(priority: heuristic(child), order: order, node: nodes.count - 1)
            }
        }
        return Result(solution: nil, statesExplored: nodes.count, hitLimit: false)
    }

    // MARK: - 内部

    private struct Node {
        let board: SolitaireBoard
        let parent: Int
        let movesFromParent: [SolitaireMove]
    }

    private static func path(to index: Int, in nodes: [Node]) -> [SolitaireMove] {
        var chain: [[SolitaireMove]] = []
        var cursor = index
        while cursor >= 0 {
            chain.append(nodes[cursor].movesFromParent)
            cursor = nodes[cursor].parent
        }
        return chain.reversed().flatMap { $0 }
    }

    /// 局面の見込み（小さいほど良い）。組札に載っていない枚数と、まだ伏せている札の枚数で採点する。
    ///
    /// **伏せ札のほうを重く見る**（係数 2）。組札は終盤に一気に伸びるので、序盤にそこを追うと
    /// 伏せ札を抱えたまま手詰まりになる局面ばかり掘ることになる。係数は 30 配札で実測して選んだ
    /// （伏せ札を軽く見る `(52-f)*2 + h` は 22/30、この式は 23/30・探索局面も 1 割少ない）。
    static func heuristic(_ board: SolitaireBoard) -> Int {
        let onFoundations = board.foundations.reduce(0, +)
        let hidden = board.tableau.reduce(0) { $0 + $1.faceDown.count }
        return (52 - onFoundations) + hidden * 2
    }

    /// 最良優先の待ち行列。同じ評価値なら**先に生まれたほうを先に見る**（`order` で安定させる）。
    private struct Heap {
        private var items: [(priority: Int, order: Int, node: Int)] = []

        var isEmpty: Bool { items.isEmpty }

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

    /// 場札で二度と必要にならないと確定した札を、分岐させずに組札へ送る。
    ///
    /// 判定は「反対色の組札が2つとも `rank - 1` 以上」。この条件が立つとき、その札に重ねうる
    /// 反対色 `rank - 1` の札は2枚とも既に組札にあるので、場札に残しておく理由が無い。
    /// A と 2 は常に安全（A は出た瞬間に組札が最善で、場札で A を受ける必要が生じない）。
    static func autoplaySafe(_ board: SolitaireBoard) -> (SolitaireBoard, [SolitaireMove]) {
        var board = board
        var moves: [SolitaireMove] = []
        var didMove = true
        while didMove {
            didMove = false
            if let card = board.waste.last, board.canSendToFoundation(card), isSafe(card, board) {
                board.apply(.wasteToFoundation)
                moves.append(.wasteToFoundation)
                didMove = true
                continue
            }
            for pile in board.tableau.indices {
                guard let card = board.tableau[pile].top,
                      board.canSendToFoundation(card), isSafe(card, board) else { continue }
                board.apply(.tableauToFoundation(pile: pile))
                moves.append(.tableauToFoundation(pile: pile))
                didMove = true
                break
            }
        }
        return (board, moves)
    }

    private static func isSafe(_ card: SolitaireCard, _ board: SolitaireBoard) -> Bool {
        guard let suit = card.suit else { return false }
        if card.rank <= 2 { return true }
        return suit.opposites.allSatisfy { board.foundations[$0.rawValue] >= card.rank - 1 }
    }

    /// 次に試す手の並び。伏せ札をめくる手 → 組札へ送る手 → 山札の札を使う手 →
    /// その他の場札の移し替え → 列を空にするだけの手 → ジョーカー、の順。
    ///
    /// 最良優先探索では評価値が同じ局面の間でしか順序が効かないので、この並びは
    /// 探索の速さより**同点のときの安定した辿り方**のために置いている
    /// （並べ替えだけを試したときは踏破数が変わらなかった。効いたのは最良優先への切り替えのほう）。
    /// 空列どうしの入れ替えと、区別の付かない空列への重複した置き手はここで落とす。
    static func successors(of board: SolitaireBoard, allowJoker: Bool) -> [[SolitaireMove]] {
        var flips: [[SolitaireMove]] = []
        var toFoundation: [[SolitaireMove]] = []
        var fromStock: [[SolitaireMove]] = []
        var shuffles: [[SolitaireMove]] = []
        var empties: [[SolitaireMove]] = []
        var jokers: [[SolitaireMove]] = []

        for pile in board.tableau.indices {
            if let card = board.tableau[pile].top, board.canSendToFoundation(card) {
                toFoundation.append([.tableauToFoundation(pile: pile)])
            }
        }
        if let card = board.waste.last, board.canSendToFoundation(card) {
            toFoundation.append([.wasteToFoundation])
        }

        // 空列は互いに区別が付かないので、置き先の候補は最初の1本だけにする。
        let firstEmptyPile = board.tableau.firstIndex(where: \.isEmpty)

        for from in board.tableau.indices {
            let faceUp = board.tableau[from].faceUp
            for index in faceUp.indices where board.isMovableRun(pile: from, from: index) {
                let run = Array(faceUp[index...])
                let emptiesPile = index == 0 && board.tableau[from].faceDown.isEmpty
                let revealsFaceDown = index == 0 && !board.tableau[from].faceDown.isEmpty
                for to in board.tableau.indices where to != from {
                    guard board.canPlace(run, onPile: to) else { continue }
                    if board.tableau[to].isEmpty {
                        // 空列から空列への移し替えは盤面が進まない（無限の往復の元）。
                        if emptiesPile { continue }
                        guard to == firstEmptyPile else { continue }
                    }
                    let move: [SolitaireMove] = [.tableauToTableau(from: from, cardIndex: index, to: to)]
                    if revealsFaceDown { flips.append(move) }
                    else if emptiesPile { empties.append(move) }
                    else { shuffles.append(move) }
                }
            }
        }

        for (card, draws) in board.reachableStockCards() {
            let prefix = [SolitaireMove](repeating: .draw, count: draws)
            if board.canSendToFoundation(card) {
                fromStock.append(prefix + [.wasteToFoundation])
            }
            for pile in board.tableau.indices where board.canPlace([card], onPile: pile) {
                if board.tableau[pile].isEmpty, pile != firstEmptyPile { continue }
                fromStock.append(prefix + [.wasteToTableau(pile: pile)])
            }
        }

        if allowJoker, board.jokerAvailable {
            for pile in board.tableau.indices where board.canPlaceJoker(onPile: pile) {
                jokers.append([.placeJoker(pile: pile)])
            }
        }

        return flips + toFoundation + fromStock + shuffles + empties + jokers
    }
}
