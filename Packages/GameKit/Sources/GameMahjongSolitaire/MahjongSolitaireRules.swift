import Foundation
import MahjongTiles

/// 麻雀ソリティアのルール判定と盤面生成。**状態も乱数の保持も持たない純粋関数**の集まりで、
/// Model 側は進行・永続化・演出だけを持つ（`DaifugoRules` と同じ分け方）。
///
/// 盤上の位置は `MahjongSolitaireLayout.positions` の添字（0..143）で識別する。位置はゲーム中に
/// 増減しないので、添字がそのまま牌の ID になり、残り牌は `[MahjongFace?]`（取り除いた位置は nil）
/// で表せる。**レイアウトは複数あり（#239）、どの関数も対象のレイアウトを引数で受け取る**
/// （既定値は置かない。渡し忘れが亀甲で静かに動いてしまうのを防ぐため）。
public enum MahjongSolitaireRules {

    // MARK: - 取得可否

    /// その位置の牌を取れるか。上に何も載っておらず、左右のどちらかが空いていれば取れる。
    /// - Parameter remaining: 位置ごとに牌が残っているか（`layout.positions` と同じ長さ）。
    public static func isFree(_ index: Int, remaining: [Bool], layout: MahjongSolitaireLayout) -> Bool {
        guard remaining[index] else { return false }
        let relations = layout.relations
        for above in relations.above[index] where remaining[above] { return false }
        let blockedLeft = relations.left[index].contains { remaining[$0] }
        let blockedRight = relations.right[index].contains { remaining[$0] }
        return !blockedLeft || !blockedRight
    }

    /// いま取れる位置の一覧（レイアウトの並び順）。
    public static func freeIndices(remaining: [Bool], layout: MahjongSolitaireLayout) -> [Int] {
        (0..<layout.count).filter { isFree($0, remaining: remaining, layout: layout) }
    }

    /// 残っている位置（`faces` が非 nil の位置）。
    public static func remainingFlags(faces: [MahjongFace?]) -> [Bool] {
        faces.map { $0 != nil }
    }

    /// いま取れる組の一覧。手詰まり検知とヒントの両方がこれを使う。
    public static func availablePairs(
        faces: [MahjongFace?],
        layout: MahjongSolitaireLayout
    ) -> [(Int, Int)] {
        let remaining = remainingFlags(faces: faces)
        let free = freeIndices(remaining: remaining, layout: layout)
        var pairs: [(Int, Int)] = []
        for (offset, a) in free.enumerated() {
            guard let faceA = faces[a] else { continue }
            for b in free[(offset + 1)...] where faces[b]?.matches(faceA) == true {
                pairs.append((a, b))
            }
        }
        return pairs
    }

    // MARK: - 牌の構成

    /// 144 枚を「同時に取り除ける 2 枚」72 組に分けたもの。
    /// 同じ絵柄は 4 枚あるので 2 組に分かれ、花牌・季節牌は 4 枚を 2 組に分ける。
    public static func facePairs() -> [[MahjongFace]] {
        var pairs: [[MahjongFace]] = []
        func addTwoPairs(_ face: MahjongFace) {
            pairs.append([face, face])
            pairs.append([face, face])
        }
        for n in 1...9 {
            addTwoPairs(.characters(n))
            addTwoPairs(.circles(n))
            addTwoPairs(.bamboos(n))
        }
        for n in 0..<4 { addTwoPairs(.wind(n)) }
        for n in 0..<3 { addTwoPairs(.dragon(n)) }
        pairs.append([.flower(0), .flower(1)])
        pairs.append([.flower(2), .flower(3)])
        pairs.append([.season(0), .season(1)])
        pairs.append([.season(2), .season(3)])
        return pairs
    }

    // MARK: - 盤面生成

    /// 生成した盤面と、その盤面を取り切れる順序。
    public struct Board {
        /// 位置ごとの絵柄。
        public let faces: [MahjongFace?]
        /// 取り切れる順序（1 要素が同時に取る 2 枚）。**この盤面がクリア可能であることの証明**でもある。
        public let solution: [[Int]]
    }

    /// **必ずクリアできる**盤面を作る。
    ///
    /// 空の盤面に絵柄をばら撒くと到達不可能な配置が混ざるため、逆に
    /// 「全部の位置が埋まった盤面から、そのとき取れる 2 枚を選んで取り除く」を 72 回繰り返し、
    /// **取り除けた順序に沿って同じ絵柄を割り当てる**。割り当てた順序がそのまま解法になるので、
    /// 到達不可能な盤面は原理的に生成されない。
    public static func generate<G: RandomNumberGenerator>(
        using rng: inout G,
        layout: MahjongSolitaireLayout
    ) -> Board {
        let all = Array(layout.positions.indices)
        var pairs = facePairs()
        pairs.shuffle(using: &rng)
        // 無作為に剥がす順序が見つからなかったときだけ、上の段を優先する剥がし方に切り替える
        // （下の段に牌が取り残されにくい代わりに、解法の形が段の順に偏る）。
        if let order = removalOrder(positions: all, using: &rng, layout: layout)
            ?? removalOrder(positions: all, using: &rng, layout: layout, topFirst: true) {
            return assign(pairs: pairs, to: order, count: layout.count)
        }
        // ここには実測で到達しない（テストで全レイアウト × 多数の種を通して確認している）。到達した
        // 場合も遊べる盤面は返す（取り切れない配置になりうるが、手詰まりならシャッフルで作り直せる）。
        var faces = [MahjongFace?](repeating: nil, count: layout.count)
        for (i, face) in pairs.flatMap({ $0 }).enumerated() where i < faces.count {
            faces[i] = face
        }
        return Board(faces: faces, solution: [])
    }

    /// 残っている牌だけを並べ替えて、**そこから必ず取り切れる**配置に作り直す（手詰まり時のシャッフル）。
    /// 位置の組み合わせ自体が取り切れない（例: 残り 2 枚が上下に重なっている）場合は nil を返す。
    public static func rearrange<G: RandomNumberGenerator>(
        faces: [MahjongFace?],
        using rng: inout G,
        layout: MahjongSolitaireLayout
    ) -> Board? {
        let positions = faces.indices.filter { faces[$0] != nil }
        guard !positions.isEmpty else { return nil }
        // 取り除きは常に「合う 2 枚」なので、残った牌も必ず組に分け直せる。
        // 分けられないなら盤面が壊れているので並べ替えない。
        var grouped: [String: [MahjongFace]] = [:]
        for index in positions {
            guard let face = faces[index] else { continue }
            grouped[face.matchKey, default: []].append(face)
        }
        var pairs: [[MahjongFace]] = []
        for key in grouped.keys.sorted() {
            let group = grouped[key] ?? []
            guard group.count.isMultiple(of: 2) else { return nil }
            for i in stride(from: 0, to: group.count, by: 2) {
                pairs.append([group[i], group[i + 1]])
            }
        }
        pairs.shuffle(using: &rng)
        guard let order = removalOrder(positions: positions, using: &rng, layout: layout)
            ?? removalOrder(positions: positions, using: &rng, layout: layout, topFirst: true)
        else { return nil }
        return assign(pairs: pairs, to: order, count: layout.count)
    }

    /// 与えられた位置集合を全部取り切れる順序を探す。見つからなければ nil。
    ///
    /// - Parameter topFirst: true なら上の段から優先して剥がす（下の段に取り残しが出にくい）。
    ///   既定は無作為で、盤面ごとに解法の形が偏らないようにする。
    static func removalOrder<G: RandomNumberGenerator>(
        positions: [Int],
        using rng: inout G,
        layout: MahjongSolitaireLayout,
        topFirst: Bool = false,
        attempts: Int = 32
    ) -> [[Int]]? {
        for _ in 0..<attempts {
            if let order = attemptRemovalOrder(
                positions: positions, using: &rng, layout: layout, topFirst: topFirst
            ) {
                return order
            }
        }
        return nil
    }

    private static func attemptRemovalOrder<G: RandomNumberGenerator>(
        positions: [Int],
        using rng: inout G,
        layout: MahjongSolitaireLayout,
        topFirst: Bool
    ) -> [[Int]]? {
        var remaining = [Bool](repeating: false, count: layout.count)
        for index in positions { remaining[index] = true }
        var left = positions.count
        var order: [[Int]] = []
        while left > 0 {
            var free = freeIndices(remaining: remaining, layout: layout)
            guard free.count >= 2 else { return nil }
            free.shuffle(using: &rng)
            if topFirst {
                free.sort { layout.positions[$0].layer > layout.positions[$1].layer }
            }
            let a = free[0], b = free[1]
            remaining[a] = false
            remaining[b] = false
            left -= 2
            order.append([a, b])
        }
        return order
    }

    /// 取り除く順序に沿って組を配る。順序に載っていない位置は絵柄なしになる。
    private static func assign(pairs: [[MahjongFace]], to order: [[Int]], count: Int) -> Board {
        var faces = [MahjongFace?](repeating: nil, count: count)
        for (step, pair) in order.enumerated() where step < pairs.count {
            faces[pair[0]] = pairs[step][0]
            faces[pair[1]] = pairs[step][1]
        }
        return Board(faces: faces, solution: order)
    }
}

/// テスト用の決定的な乱数生成器（SplitMix64）。本番は `seed` を渡さないので system の乱数を使う。
struct MahjongSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
