import Foundation

/// 盤面のかたち（#239）。
///
/// 亀甲 1 種類しか無いと、何度遊んでも牌の配置運だけが変わって面の形は永遠に同じになる。
/// 位置の集合と、そこから決まる派生値（盤の広さ・最上段・取得可否の関係）を**ひとつの値**に束ね、
/// `MahjongSolitaireRules` は「このレイアウトを受け取る純粋関数の集まり」として扱う。
///
/// 位置は**半マス単位**（`MahjongPosition`）で、1 枚の牌は 2×2 半マスを占める。
/// どのレイアウトも **144 枚ちょうど**（`MahjongSolitaireRules.facePairs()` の 72 組と対応）で、
/// これは `MahjongLayoutTests` が全レイアウトについて検証している。
public struct MahjongSolitaireLayout: Identifiable, Sendable {

    /// 保存・記録の区分キー（`GameScore.variant`）に使う識別子。**値を変えると記録が別物になる**。
    public let id: String
    /// 画面と記録に出す名前。
    public let displayName: String
    /// 牌 1 枚ぶんの置き場所。添字がそのまま盤上の位置 ID になる。
    public let positions: [MahjongPosition]
    /// 盤面の広さ（半マス単位）。描画のスケール計算に使う。**位置から導出する**ので取り違えない。
    public let halfWidth: Int
    public let halfHeight: Int
    /// 最上段の段番号。
    public let topLayer: Int

    /// 位置 → 添字。テストで特定の場所を指すときに使う。
    private let indexByPosition: [MahjongPosition: Int]
    /// 各位置について「上に載りうる牌」「左を塞ぐ牌」「右を塞ぐ牌」。
    /// 位置は不変なので 1 度だけ計算し、毎回 144×144 を舐めずに判定できるようにする。
    let relations: Relations

    struct Relations: Sendable {
        let above: [[Int]]
        let left: [[Int]]
        let right: [[Int]]
    }

    /// 牌の枚数。
    public var count: Int { positions.count }

    init(id: String, displayName: String, positions: [MahjongPosition]) {
        self.id = id
        self.displayName = displayName
        self.positions = positions
        // 盤の広さは位置から導く。定数として別に持つと、レイアウトを足したときに更新し忘れて
        // 牌が枠からはみ出す（= タップ標的の計算がずれる）。
        self.halfWidth = (positions.map(\.hx).max() ?? 0) + 2
        self.halfHeight = (positions.map(\.hy).max() ?? 0) + 2
        self.topLayer = positions.map(\.layer).max() ?? 0

        var map: [MahjongPosition: Int] = [:]
        for (i, position) in positions.enumerated() { map[position] = i }
        self.indexByPosition = map
        self.relations = Self.makeRelations(positions)
    }

    /// 位置から添字を引く。
    public func index(layer: Int, hx: Int, hy: Int) -> Int? {
        indexByPosition[MahjongPosition(layer: layer, hx: hx, hy: hy)]
    }

    private static func makeRelations(_ positions: [MahjongPosition]) -> Relations {
        let count = positions.count
        var above = [[Int]](repeating: [], count: count)
        var left = [[Int]](repeating: [], count: count)
        var right = [[Int]](repeating: [], count: count)
        for i in 0..<count {
            let a = positions[i]
            for j in 0..<count where i != j {
                let b = positions[j]
                if b.layer > a.layer, a.overlaps(b) {
                    above[i].append(j)
                } else if b.layer == a.layer, abs(a.hy - b.hy) < 2 {
                    // 横に触れている（= 2 半マス以内でずれている）牌だけが取り出しを塞ぐ。
                    if b.hx < a.hx, b.hx > a.hx - 4 { left[i].append(j) }
                    if b.hx > a.hx, b.hx < a.hx + 4 { right[i].append(j) }
                }
            }
        }
        return Relations(above: above, left: left, right: right)
    }
}

extension MahjongSolitaireLayout: Equatable {
    /// 同じ id なら同じレイアウト（位置の配列を毎回比べない）。
    public static func == (lhs: MahjongSolitaireLayout, rhs: MahjongSolitaireLayout) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 収録しているレイアウト

public extension MahjongSolitaireLayout {

    /// 標準的な亀（タートル）型。144 枚。
    ///
    /// 第1段 87 枚（8 行の甲羅 84 枚 + 左のヒレ 1 枚 + 右のヒレ 2 枚）、
    /// 第2段 36 枚（6×6）、第3段 16 枚（4×4）、第4段 4 枚（2×2）、第5段 1 枚。
    static let turtle = MahjongSolitaireLayout(
        id: "turtle",
        displayName: "亀甲",
        positions: {
            var result: [MahjongPosition] = []

            // 第1段の甲羅。(y の半マス座標, x の左端, x の右端) を上の行から並べる。
            let rows: [(hy: Int, from: Int, to: Int)] = [
                (0, 1, 12), (2, 3, 10), (4, 2, 11), (6, 1, 12),
                (8, 1, 12), (10, 2, 11), (12, 3, 10), (14, 1, 12),
            ]
            for row in rows {
                for x in row.from...row.to {
                    result.append(MahjongPosition(layer: 0, hx: x * 2, hy: row.hy))
                }
            }
            // ヒレは 4 行目と 5 行目の間にまたがるので hy を半マスずらす（左 1 枚・右 2 枚）。
            result.append(MahjongPosition(layer: 0, hx: 0, hy: 7))
            result.append(MahjongPosition(layer: 0, hx: 26, hy: 7))
            result.append(MahjongPosition(layer: 0, hx: 28, hy: 7))

            // 第2〜4段は中央に向かって一回り小さくなる矩形。
            result.append(contentsOf: MahjongSolitaireLayout.rectangles([
                (1, 4...9, 1...6),
                (2, 5...8, 2...5),
                (3, 6...7, 3...4),
            ]))

            // 第5段の 1 枚は第4段 2×2 の中央にまたがって載る。
            result.append(MahjongPosition(layer: 4, hx: 13, hy: 7))
            return result
        }()
    )

    /// ピラミッド。144 枚（78 / 44 / 18 / 4）。
    ///
    /// 段ごとに一回り小さくなる矩形を積む。亀甲より横に狭く縦に浅いので、**盤の端まで見渡しやすく
    /// 手数の見通しが立てやすい**代わりに、覆われている牌の割合が高い（下の段を掘る順序が問われる）。
    static let pyramid = MahjongSolitaireLayout(
        id: "pyramid",
        displayName: "ピラミッド",
        positions: {
            var result = MahjongSolitaireLayout.rectangles([
                (0, 0...12, 0...5),     // 13×6 = 78
                (1, 1...11, 1...4),     // 11×4 = 44
                (2, 2...10, 2...3),     //  9×2 = 18
            ])
            // 頂上の 4 枚。第3段は 2 行しか無いので、整数マスでは中央に置けない。
            // 半マスずらして 2 行にまたがらせる（亀甲のヒレと同じ手）。
            for hx in [9, 11, 13, 15] {
                result.append(MahjongPosition(layer: 3, hx: hx, hy: 5))
            }
            return result
        }()
    )

    /// 十字。144 枚（90 / 44 / 6 / 4）。
    ///
    /// 横棒と縦棒を重ねた形。**4 本の腕の先端が常に取れる**ので手詰まりにくい一方、
    /// 縦に長く（10 枚ぶん）盤面を見て回る距離が長い。亀甲・ピラミッドと遊び味を変えるための 1 つ。
    static let cross = MahjongSolitaireLayout(
        id: "cross",
        displayName: "十字",
        positions: MahjongSolitaireLayout.rectangles([
            (0, 0...14, 3...6),     // 横棒 15×4
            (0, 5...9, 0...9),      // 縦棒  5×10（重なる 5×4 は捨てて 90 枚）
            (1, 1...13, 4...5),     // 横棒 13×2
            (1, 6...8, 1...8),      // 縦棒  3×8（重なる 3×2 は捨てて 44 枚）
            (2, 6...8, 4...5),      // 中央  3×2 = 6
        ]) + [
            // 頂上の 4 枚は第3段の 3×2 に載せる。横は 2 枚 vs 3 枚なので半マスずらすが、
            // 縦は 2 行 vs 2 行で段差が偶数なのでずらさない（ずらすと頂上が下へ半マスはみ出す）。
            MahjongPosition(layer: 3, hx: 13, hy: 8),
            MahjongPosition(layer: 3, hx: 15, hy: 8),
            MahjongPosition(layer: 3, hx: 13, hy: 10),
            MahjongPosition(layer: 3, hx: 15, hy: 10),
        ]
    )

    /// 選べるレイアウト。**この並び順が「＋」メニューと順送りの順序**になる。
    static let all: [MahjongSolitaireLayout] = [turtle, pyramid, cross]

    /// id から引く。**知らない id と nil は亀甲に倒す**（レイアウト識別子を持たない
    /// 古い中断データでも復元が失敗しないようにするため）。
    static func named(_ id: String?) -> MahjongSolitaireLayout {
        guard let id, let found = all.first(where: { $0.id == id }) else { return turtle }
        return found
    }

    /// 次のレイアウト（末尾なら先頭へ戻る）。
    var next: MahjongSolitaireLayout {
        guard let current = Self.all.firstIndex(where: { $0.id == id }) else { return Self.turtle }
        return Self.all[(current + 1) % Self.all.count]
    }

    /// 矩形（マス単位の x/y 範囲）を半マス座標の位置に展開する。**同じ場所は 1 度しか置かない**ので、
    /// 十字のように矩形が重なる形もそのまま並べて書ける。
    internal static func rectangles(
        _ specs: [(layer: Int, x: ClosedRange<Int>, y: ClosedRange<Int>)]
    ) -> [MahjongPosition] {
        var result: [MahjongPosition] = []
        var seen: Set<MahjongPosition> = []
        for spec in specs {
            for y in spec.y {
                for x in spec.x {
                    let position = MahjongPosition(layer: spec.layer, hx: x * 2, hy: y * 2)
                    if seen.insert(position).inserted { result.append(position) }
                }
            }
        }
        return result
    }
}
