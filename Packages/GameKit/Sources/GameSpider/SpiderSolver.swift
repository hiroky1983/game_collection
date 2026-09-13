import Foundation

/// 配札が理論上クリアできるかを判定するソルバー（#717 の「解ける配札だけ配る」の裏付け）。
///
/// 目的はフリーセル `FreeCellSolver` と同じで、**勝ち筋を 1 本見つける**ことだけ。上限に達して
/// 打ち切った場合は `hitLimit` を立て、**クリア不能とは言い切らない**。
///
/// スパイダー固有の事情と、それに合わせた構造:
///
/// - 104 枚・伏せ札あり・山札 5 回で、局面の数はフリーセルより桁違いに多い。探索は
///   **`SpiderBoard` ではなく詰めた内部表現（`State`）で回す**（1 局面あたりのメモリを抑える）。
/// - 「配る」は 5 回すべて必ず行う手で、順番も固定されている。そこで探索を**配りと配りの間の
///   6 段**に分け、各段では「配らずに動かせる範囲」を最良優先で探して見込みの良い局面を
///   `beamWidth` 件残し、そこから配って次の段へ進む（行き詰まったら前の段の次の候補へ戻る）。
///   1 本の最良優先で全体を掘ると、配ると並びが切れて評価が悪化するため**配る前の並べ替えを
///   掘り尽くして上限に達する**（実測: 1 スートで 141 種中 5 種しか解けなかった）。
/// - 同じスート・ランクの札は区別しない（`SpiderBoard.stateKey` と同じ）。
/// - 伏せ札の中身は種で決まっているので、ソルバーは**全部見えている前提**で探索する
///   （「どう指せば勝てるか」ではなく「勝ち筋が存在するか」を確かめるのが目的）。
public enum SpiderSolver {

    public struct Result: Sendable {
        /// 勝ち筋（見つからなければ nil）。先頭から順に `SpiderBoard.apply` すればクリアに到達する。
        public let solution: [SpiderMove]?
        public let statesExplored: Int
        /// 最後まで探索せずに打ち切ったか。true のときの `solution == nil` は「不能」ではなく「不明」。
        public let hitLimit: Bool

        public var isSolvable: Bool { solution != nil }
    }

    /// 既定の探索上限（スート数ごと・全段の合計）。
    ///
    /// 種の生成（`SpiderDealerTests` の「検証済みの種を作り直す」）と、テストでの抜き取り検証は
    /// **同じ上限**で回す。上限が違うと「生成時は解けたのにテストでは解けない」が起きる。
    /// 値の根拠は `SpiderVerifiedSeeds.swift` の冒頭（実測）。
    public static func defaultMaxStates(for suits: SpiderSuitCount) -> Int {
        switch suits {
        case .one:  return 60_000
        case .two:  return 150_000
        // 4 スートは桁が違う。-O ビルドで 1 種あたり十数秒かかるので、**テストでは
        // この上限でソルバーを回さず、保存した勝ち筋の再生で確かめる**（`SpiderDealerTests`）。
        case .four: return 1_500_000
        }
    }

    /// 配りを挟む中間の段で掘る局面数。全体の上限を 12 で割る（6 段 × 戻り 1 回ぶん）。
    /// 配り切ったあとの最終段は残りの上限を全部使う（詰めが一番深い）。
    static func stageBudget(maxStates: Int) -> Int { max(1, maxStates / 12) }
    /// 各段で次の段へ持ち越す候補の数。
    static let beamWidth = 4

    public static func solve(
        _ board: SpiderBoard,
        maxStates: Int,
        isCancelled: () -> Bool = { false }
    ) -> Result {
        let table = Table(board: board)
        let root = State(board: board)
        if root.isWon { return Result(solution: [], statesExplored: 1, hitLimit: false) }

        return withoutActuallyEscaping(isCancelled) { isCancelled in
            var search = Search(table: table, maxStates: maxStates, isCancelled: isCancelled)
            let solution = search.run(from: root, prefix: [])
            // 「不能」と言い切れるのは、どの段も予算内に掘り尽くし、候補も切り捨てなかったときだけ。
            // 段の予算切れ・全体の上限・候補の絞り込み（`beamWidth`）のどれかで探索を狭めていれば「不明」。
            return Result(solution: solution, statesExplored: search.explored,
                          hitLimit: solution == nil && (search.exhausted || search.truncated))
        }
    }

    // MARK: - 段階探索

    private struct Search {
        let table: Table
        let maxStates: Int
        let isCancelled: () -> Bool
        var explored = 0
        /// 全体の上限（`maxStates`）か取り消しで止めたか。
        var exhausted = false
        /// 段の予算切れ・候補の切り捨てで探索を狭めたか（勝ち筋が無いことの証明にならない）。
        var truncated = false

        init(table: Table, maxStates: Int, isCancelled: @escaping () -> Bool) {
            self.table = table
            self.maxStates = maxStates
            self.isCancelled = isCancelled
        }

        /// `state` から始めて、配りを挟みながら勝ち筋を探す。
        mutating func run(from state: State, prefix: [SpiderMove]) -> [SpiderMove]? {
            let isFinal = Int(state.dealt) >= table.stock.count
            let budget = isFinal ? maxStates - explored : SpiderSolver.stageBudget(maxStates: maxStates)
            let stage = explore(from: state, budget: budget)
            if let win = stage.win { return prefix + win }
            guard !isFinal else { return nil }
            for candidate in stage.candidates {
                if exhausted { return nil }
                var next = candidate.state
                next.apply(.deal, table)
                if let solution = run(from: next, prefix: prefix + candidate.path + [.deal]) {
                    return solution
                }
            }
            return nil
        }

        struct Stage {
            var win: [SpiderMove]?
            /// 次の段へ持ち越す候補（見込みの良い順）。配れる局面（空列が無い）だけ。
            var candidates: [(state: State, path: [SpiderMove])]
        }

        /// 配らずに動かせる範囲を最良優先で掘る。
        mutating func explore(from root: State, budget stageBudget: Int) -> Stage {
            var nodes: [Node] = [Node(state: root, parent: -1, move: .deal)]
            var visited: Set<Data> = [root.key(table)]
            var frontier = Heap()
            frontier.push(priority: heuristic(root, table), order: 0, node: 0)
            var order = 0
            var budget = stageBudget
            let mustDeal = Int(root.dealt) < table.stock.count

            while let index = frontier.pop(), budget > 0 {
                if isCancelled() || explored >= maxStates {
                    exhausted = true
                    break
                }
                // 1 局面の展開で予算を一気に使い切ると次の pop の前にループが抜けるので、ここでも見る。
                defer {
                    if explored >= maxStates { exhausted = true }
                    if budget <= 0 { truncated = true }
                }
                let current = nodes[index].state
                for move in successors(of: current, table) {
                    var child = current
                    child.apply(move, table)
                    let key = child.key(table)
                    guard !visited.contains(key) else { continue }
                    visited.insert(key)
                    explored += 1
                    budget -= 1
                    nodes.append(Node(state: child, parent: index, move: move))
                    if child.isWon {
                        return Stage(win: path(to: nodes.count - 1, in: nodes), candidates: [])
                    }
                    order += 1
                    frontier.push(priority: heuristic(child, table), order: order, node: nodes.count - 1)
                }
            }

            guard mustDeal else { return Stage(win: nil, candidates: []) }
            // 配れる局面のうち見込みの良いものを `beamWidth` 件。同じ見込みなら後から着いたほう
            // （＝深く進めたほう）を先に試す。
            var ranked: [(score: Int, index: Int)] = []
            for (index, node) in nodes.enumerated() where node.state.canDeal(table) {
                ranked.append((heuristic(node.state, table), index))
            }
            ranked.sort { $0.score != $1.score ? $0.score < $1.score : $0.index > $1.index }
            if ranked.count > SpiderSolver.beamWidth { truncated = true }
            let picked = ranked.prefix(SpiderSolver.beamWidth).map { entry in
                (state: nodes[entry.index].state, path: path(to: entry.index, in: nodes))
            }
            return Stage(win: nil, candidates: picked)
        }
    }

    // MARK: - 内部表現

    /// 種で固定される情報（札の種別・山札の中身）。探索中は変わらないので局面の外に置く。
    struct Table {
        /// `id` → スート（0...3）。
        let suitOf: [UInt8]
        /// `id` → ランク（1...13）。
        let rankOf: [UInt8]
        /// 山札の配り（各 10 枚の `id`）。
        let stock: [[UInt8]]

        init(board: SpiderBoard) {
            var suits = [UInt8](repeating: 0, count: SpiderBoard.deckSize)
            var ranks = [UInt8](repeating: 0, count: SpiderBoard.deckSize)
            for card in board.piles.flatMap(\.cards) + board.stock.flatMap({ $0 }) {
                suits[card.id] = UInt8(card.suit.rawValue)
                ranks[card.id] = UInt8(card.rank)
            }
            self.suitOf = suits
            self.rankOf = ranks
            self.stock = board.stock.map { $0.map { UInt8($0.id) } }
        }

        /// 局面のキーに使う札の種別（スート×13 + ランク。1...52）。
        @inline(__always) func kind(_ id: UInt8) -> UInt8 { suitOf[Int(id)] * 13 + rankOf[Int(id)] }
    }

    /// 詰めた局面。札は `id`（UInt8）で持つ。
    struct State {
        var piles: [[UInt8]]
        var faceDown: [UInt8]
        /// 配った回数。
        var dealt: UInt8
        var completed: UInt8

        init(board: SpiderBoard) {
            piles = board.piles.map { $0.cards.map { UInt8($0.id) } }
            faceDown = board.piles.map { UInt8($0.faceDownCount) }
            dealt = 0
            completed = UInt8(board.completed.count)
        }

        var isWon: Bool { completed >= UInt8(SpiderBoard.sequenceGoal) }

        func canDeal(_ table: Table) -> Bool {
            Int(dealt) < table.stock.count && !piles.contains(where: \.isEmpty)
        }

        /// 手を適用し、揃った並びの取り除きとめくりまで済ませる（`SpiderBoard.apply` と同じ規則）。
        mutating func apply(_ move: SpiderMove, _ table: Table) {
            switch move {
            case .move(let from, let cardIndex, let to):
                piles[to].append(contentsOf: piles[from][cardIndex...])
                piles[from].removeSubrange(cardIndex...)
                settle(pile: to, table)
                settle(pile: from, table)
            case .deal:
                let cards = table.stock[Int(dealt)]
                dealt += 1
                for (index, card) in cards.enumerated() where index < piles.count {
                    piles[index].append(card)
                }
                for pile in piles.indices { settle(pile: pile, table) }
            }
        }

        private mutating func settle(pile: Int, _ table: Table) {
            let count = piles[pile].count
            let down = Int(faceDown[pile])
            if count - down >= SpiderBoard.sequenceLength {
                let start = count - SpiderBoard.sequenceLength
                if table.rankOf[Int(piles[pile][start])] == 13, runStart(pile: pile, table) <= start {
                    piles[pile].removeLast(SpiderBoard.sequenceLength)
                    completed += 1
                }
            }
            if faceDown[pile] > 0, Int(faceDown[pile]) == piles[pile].count {
                faceDown[pile] -= 1
            }
        }

        /// 列の上から続く「同じスートで降順」の並びの下端の添字。伏せ札より下へは行かない。
        func runStart(pile: Int, _ table: Table) -> Int {
            let column = piles[pile]
            guard !column.isEmpty else { return 0 }
            var index = column.count - 1
            let down = Int(faceDown[pile])
            while index > down {
                let upper = column[index - 1], lower = column[index]
                guard table.suitOf[Int(upper)] == table.suitOf[Int(lower)],
                      table.rankOf[Int(upper)] == table.rankOf[Int(lower)] + 1 else { break }
                index -= 1
            }
            return index
        }

        /// `SpiderBoard.stateKey` と同じ正準表現。
        func key(_ table: Table) -> Data {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(SpiderBoard.deckSize + 24)
            bytes.append(completed)
            bytes.append(dealt)
            let stockExhausted = Int(dealt) >= table.stock.count
            func encode(_ pile: Int) -> [UInt8] {
                var out: [UInt8] = [faceDown[pile]]
                for card in piles[pile][Int(faceDown[pile])...] { out.append(table.kind(card)) }
                return out
            }
            if stockExhausted {
                var free: [[UInt8]] = []
                for pile in piles.indices {
                    if faceDown[pile] > 0 {
                        bytes.append(0xF0 | UInt8(pile))
                        bytes.append(contentsOf: encode(pile))
                        bytes.append(0xFF)
                    } else {
                        free.append(encode(pile))
                    }
                }
                for column in free.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                    bytes.append(contentsOf: column)
                    bytes.append(0xFF)
                }
            } else {
                for pile in piles.indices {
                    bytes.append(contentsOf: encode(pile))
                    bytes.append(0xFF)
                }
            }
            return Data(bytes)
        }
    }

    private struct Node {
        let state: State
        let parent: Int
        let move: SpiderMove
    }

    private static func path(to index: Int, in nodes: [Node]) -> [SpiderMove] {
        var chain: [SpiderMove] = []
        var cursor = index
        while nodes[cursor].parent >= 0 {
            chain.append(nodes[cursor].move)
            cursor = nodes[cursor].parent
        }
        return chain.reversed()
    }

    // MARK: - 評価

    /// 局面の見込み（小さいほど良い）。
    ///
    /// 1. **未完成の組数**（×40）— ゴールまでの距離そのもの。
    /// 2. **伏せ札の枚数**（×6）— めくらないと何も始まらない。
    /// 3. **並びの切れ目** — 表向きの札で「下の札と同じスートで 1 つ小さい」になっていない箇所。
    ///    降順だがスートが違う（まとめて動かせない）は 2、降順ですらない（そこから上しか動かない）は 4。
    /// 4. **空いた列**（×8 で減点）— 最も価値の高い資源。
    ///
    /// 「配る」は段の切れ目でしか起きない（`Search`）ので、残りの配りは評価に入れない。
    static func heuristic(_ state: State, _ table: Table) -> Int {
        var score = (SpiderBoard.sequenceGoal - Int(state.completed)) * 40
        for pile in state.piles.indices {
            let column = state.piles[pile]
            let down = Int(state.faceDown[pile])
            score += down * 6
            if column.isEmpty { score -= 8; continue }
            var index = down + 1
            while index < column.count {
                let upper = column[index - 1], lower = column[index]
                if table.rankOf[Int(upper)] != table.rankOf[Int(lower)] + 1 {
                    score += 4
                } else if table.suitOf[Int(upper)] != table.suitOf[Int(lower)] {
                    score += 2
                }
                index += 1
            }
        }
        return score
    }

    /// 最良優先の待ち行列。同じ評価値なら**後から生まれたほうを先に見る**
    /// （深さ優先寄りにして、同じ見込みの局面を横に並べて掘り尽くさないため）。
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
            lhs.priority != rhs.priority ? lhs.priority < rhs.priority : lhs.order > rhs.order
        }
    }

    // MARK: - 手の生成

    /// 次に試す手（場札の移し替えだけ。「配る」は段の切れ目で `Search` が行う）。
    ///
    /// 落とす手（どれも盤面が進まないか、別の手と同じ局面へ至る）:
    /// - 空いた列への置き先は最初の 1 本だけ（`SpiderBoard.legalMoves` と同じ）。
    /// - 伏せ札の無い列を丸ごと別の空列へ移す（列を入れ替えるだけ）。
    /// - 「下の札と同じスートで続いている並び」を、置き先も同じスートで続く列へ移す
    ///   （完成した形を横にずらすだけ。列を空ける・めくる効果があるときだけ許す）。
    static func successors(of state: State, _ table: Table) -> [SpiderMove] {
        var moves: [SpiderMove] = []
        let firstEmpty = state.piles.firstIndex(where: \.isEmpty)

        for from in state.piles.indices {
            let column = state.piles[from]
            guard !column.isEmpty else { continue }
            let start = state.runStart(pile: from, table)
            let down = Int(state.faceDown[from])
            for index in stride(from: column.count - 1, through: start, by: -1) {
                let card = column[index]
                let rank = table.rankOf[Int(card)]
                let suit = table.suitOf[Int(card)]
                // この並びが、さらに下の表向きの札と同じスートで続いているか。
                let continuesBelow = index > down
                    && table.suitOf[Int(column[index - 1])] == suit
                    && table.rankOf[Int(column[index - 1])] == rank + 1
                let exposes = index == down  // 動かすと列が空くか伏せ札がめくれる
                for to in state.piles.indices where to != from {
                    let target = state.piles[to]
                    if target.isEmpty {
                        guard to == firstEmpty else { continue }
                        if index == 0 && down == 0 { continue }
                        moves.append(.move(from: from, cardIndex: index, to: to))
                        continue
                    }
                    let top = target[target.count - 1]
                    guard table.rankOf[Int(top)] == rank + 1 else { continue }
                    if continuesBelow, !exposes, table.suitOf[Int(top)] == suit { continue }
                    moves.append(.move(from: from, cardIndex: index, to: to))
                }
            }
        }
        return moves
    }
}
