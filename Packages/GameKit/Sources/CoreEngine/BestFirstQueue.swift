/// 最良優先探索の待ち行列（二分ヒープ）。評価値 `priority` が小さいものから取り出す（#916）。
///
/// クロンダイク・フリーセル・スパイダーのソルバーが同じヒープを別々に持っていたものを 1 本に寄せた。
/// 3 本の違いは**同じ評価値のときにどちらを先に見るか**だけで、それを `TieBreak` で渡す。
/// この向きを変えると探索順が変わり、検証済みの種が上限内に解けるか・ヒントの答えが変わりうるので、
/// 各ソルバーの選択は変えないこと（探索した局面数を各ゲームのテストで固定している）。
///
/// Foundation にも依存しない（`SplitMix64` と同じく、スパイダーの `swiftc -O` 単体ビルドに並べられる）。
/// ソルバーの内側で局面ごとに呼ばれるので、モジュールをまたいでも最適化が効くよう `@inlinable` にしてある。
public struct BestFirstQueue: Sendable {
    public enum TieBreak: Sendable {
        /// 先に生まれたほうを先に見る（クロンダイク・フリーセル）。
        case earlierFirst
        /// 後から生まれたほうを先に見る（スパイダー。深さ優先寄りにして、同じ見込みの局面を横に掘り尽くさない）。
        case laterFirst
    }

    @usableFromInline let tieBreak: TieBreak
    @usableFromInline var items: [(priority: Int, order: Int, node: Int)] = []

    public init(tieBreak: TieBreak) { self.tieBreak = tieBreak }

    @inlinable
    public mutating func push(priority: Int, order: Int, node: Int) {
        items.append((priority, order, node))
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard isHigher(items[child], than: items[parent]) else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    @inlinable
    public mutating func pop() -> Int? {
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

    @inlinable
    func isHigher(_ lhs: (priority: Int, order: Int, node: Int),
                  than rhs: (priority: Int, order: Int, node: Int)) -> Bool {
        guard lhs.priority == rhs.priority else { return lhs.priority < rhs.priority }
        switch tieBreak {
        case .earlierFirst: return lhs.order < rhs.order
        case .laterFirst:   return lhs.order > rhs.order
        }
    }
}
