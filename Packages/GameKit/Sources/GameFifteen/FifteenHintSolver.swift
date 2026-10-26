/// 15 パズルのヒント用ソルバー（#1975）。「いま盤のどのタイルを 1 枚動かすと揃う道に乗るか」を返す。
///
/// 4×4・5×5 の最短手数探索（IDA*）は平均でも数千万ノードかかる局面があり、そのままでは同期に回せない。
/// そこで（メインスレッドで回すため展開数に上限を置いた）**重み付き A\***（`f = g + w·h`、`h` はマンハッタン距離 + 線形競合）を重みの小さい順に試す。
/// 重み 1 は最短、大きくなるほど速く・手数は長くなる。**どの重みでも返す手は「揃うまでの 1 本の道の最初の 1 手」**
/// なので、示された通りに動かし続ければ必ず揃う。最後の重みは打ち切りが無く、必ず解に届く。
enum FifteenHintSolver {
    /// (重み, 展開ノード数の上限)。最後だけ上限なし（貪欲に近く、数千ノードで解ける）。
    private static let stages: [(weight: Int, limit: Int?)] = [(1, 10_000), (2, 20_000), (4, 40_000), (16, nil)]
    /// 5×5 は重み 1〜2 だと数十万ノードを展開しても解に届かない局面があるので、最初から重みを大きくする
    /// （実測: 重み 6 は 1 万ノード前後、重みを 16 以上にすると逆に増える。#2869）。
    private static let largeBoardStages: [(weight: Int, limit: Int?)] = [(6, 15_000), (8, nil)]

    private static func stages(forCellCount count: Int) -> [(weight: Int, limit: Int?)] {
        count > 16 ? largeBoardStages : stages
    }

    /// 動かすべきタイルが今ある升（空白の隣）。揃っている・解けない盤は nil。
    static func nextIndex(_ tiles: [Int]) -> Int? {
        guard FifteenLogic.isSolvable(tiles), !FifteenLogic.isSolved(tiles) else { return nil }
        for stage in stages(forCellCount: tiles.count) {
            if let index = search(tiles, weight: stage.weight, limit: stage.limit) { return index }
        }
        return nil
    }

    private struct Node {
        var tiles: [Int]
        var blank: Int
        var g: Int
        var parent: Int
        /// 根の直後の 1 手で空白が動いた先（= 根で動かすタイルの升）。根自身は -1。
        var first: Int
    }

    private struct Entry { var f: Int; var h: Int; var node: Int }

    private static func search(_ root: [Int], weight: Int, limit: Int?) -> Int? {
        let n = FifteenLogic.size(ofCellCount: root.count)!
        let rootBlank = root.firstIndex(of: 0)!
        var nodes = [Node(tiles: root, blank: rootBlank, g: 0, parent: -1, first: -1)]
        var bestG: [BoardKey: Int] = [key(root): 0]
        var heap = MinHeap()
        let h0 = heuristic(root)
        heap.push(Entry(f: weight * h0, h: h0, node: 0))
        var expanded = 0

        while let entry = heap.pop() {
            let node = nodes[entry.node]
            if let known = bestG[key(node.tiles)], known < node.g { continue }
            if entry.h == 0 { return node.first >= 0 ? node.first : nil }
            expanded += 1
            if let limit, expanded > limit { return nil }
            let row = node.blank / n, col = node.blank % n
            for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let r = row + dr, c = col + dc
                guard r >= 0, r < n, c >= 0, c < n else { continue }
                let target = r * n + c
                // 来た道を戻る手は展開しない。
                if node.parent >= 0, nodes[node.parent].blank == target { continue }
                var next = node.tiles
                next.swapAt(node.blank, target)
                let g = node.g + 1
                let k = key(next)
                if let known = bestG[k], known <= g { continue }
                bestG[k] = g
                let h = heuristic(next)
                nodes.append(Node(tiles: next, blank: target, g: g, parent: entry.node,
                                  first: node.first >= 0 ? node.first : target))
                heap.push(Entry(f: g + weight * h, h: h, node: nodes.count - 1))
            }
        }
        return nil
    }

    /// 盤の並びを 1 マス 5 ビットで詰めた鍵。5×5（25 マス）は 64 ビットに収まらないので 2 本に分ける。
    /// `high` は 13 マスぶん（65 ビット）で最初の 1 ビットが溢れるが、盤は 0〜24 が 1 つずつの並びなので、
    /// 溢れた 1 マスは残りの 24 マスから決まる（鍵が衝突することはない）。
    private struct BoardKey: Hashable { var low: UInt64; var high: UInt64 }

    private static func key(_ tiles: [Int]) -> BoardKey {
        var key = BoardKey(low: 0, high: 0)
        for (index, tile) in tiles.enumerated() {
            if index < 12 { key.low = key.low << 5 | UInt64(tile) } else { key.high = key.high << 5 | UInt64(tile) }
        }
        return key
    }

    /// マンハッタン距離 + 線形競合（同じ行・列で互いに追い越さないと帰れない対 1 組につき +2）。ほぼ許容的なので、重み 1 ならほぼ最短になる。
    static func heuristic(_ tiles: [Int]) -> Int {
        let n = FifteenLogic.size(ofCellCount: tiles.count)!
        var total = 0
        for index in tiles.indices where tiles[index] != 0 {
            let goal = tiles[index] - 1
            total += abs(index / n - goal / n) + abs(index % n - goal % n)
        }
        for line in 0..<n {
            total += 2 * conflicts(tiles, line: line, isRow: true)
            total += 2 * conflicts(tiles, line: line, isRow: false)
        }
        return total
    }

    /// 1 行（列）の線形競合を解くのに外す必要のあるタイル数の下限（貪欲に最多競合から外す）。
    private static func conflicts(_ tiles: [Int], line: Int, isRow: Bool) -> Int {
        let n = FifteenLogic.size(ofCellCount: tiles.count)!
        // この行（列）に帰る先を持ち、いまその行（列）にいるタイルの (現在位置, 帰る位置)。
        var members: [(pos: Int, goal: Int)] = []
        for pos in 0..<n {
            let index = isRow ? line * n + pos : pos * n + line
            let value = tiles[index]
            guard value != 0 else { continue }
            let goal = value - 1
            guard (isRow ? goal / n : goal % n) == line else { continue }
            members.append((pos, isRow ? goal % n : goal / n))
        }
        var removed = 0
        while true {
            var counts = [Int](repeating: 0, count: members.count)
            for i in members.indices {
                for j in members.indices where i < j
                    && (members[i].pos < members[j].pos) != (members[i].goal < members[j].goal) {
                    counts[i] += 1
                    counts[j] += 1
                }
            }
            guard let worst = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[worst] > 0 else { return removed }
            members.remove(at: worst)
            removed += 1
        }
    }

    /// f の小さい順（同点は h の小さい順）に取り出す二分ヒープ。
    private struct MinHeap {
        private var items: [Entry] = []

        private static func less(_ a: Entry, _ b: Entry) -> Bool {
            a.f != b.f ? a.f < b.f : a.h < b.h
        }

        mutating func push(_ entry: Entry) {
            items.append(entry)
            var i = items.count - 1
            while i > 0 {
                let p = (i - 1) / 2
                guard Self.less(items[i], items[p]) else { break }
                items.swapAt(i, p)
                i = p
            }
        }

        mutating func pop() -> Entry? {
            guard !items.isEmpty else { return nil }
            items.swapAt(0, items.count - 1)
            let top = items.removeLast()
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count, Self.less(items[l], items[m]) { m = l }
                if r < items.count, Self.less(items[r], items[m]) { m = r }
                if m == i { break }
                items.swapAt(i, m)
                i = m
            }
            return top
        }
    }
}
