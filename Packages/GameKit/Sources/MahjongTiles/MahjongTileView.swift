import SwiftUI
import Core

/// 1 枚の牌。**画像アセットを一切持たず、SwiftUI の図形と文字だけで描く**（配布物にライセンス不明の
/// 画像を含めないため）。麻雀ソリティア（#90）と四人打ち麻雀（#106）で共有する。
///
/// 筒子は円を、索子は竹を、実際の麻雀牌と同じ配置で並べる。麻雀ソリティアは牌が積み重なるぶん
/// 1 枚が小さくなるので、点や節など潰れる装飾は**実寸を見て**描くかどうかを切り替える（`MahjongTileArt`）。
public struct MahjongTileView: View {
    public let face: MahjongFace
    public let width: CGFloat
    public let height: CGFloat
    /// いま取れない牌（上に載っている・両隣が塞がっている）。暗く落として見分けられるようにする。
    public let isBlocked: Bool
    public let isSelected: Bool
    public let isHinted: Bool

    public init(
        face: MahjongFace,
        width: CGFloat,
        height: CGFloat,
        isBlocked: Bool = false,
        isSelected: Bool = false,
        isHinted: Bool = false
    ) {
        self.face = face
        self.width = width
        self.height = height
        self.isBlocked = isBlocked
        self.isSelected = isSelected
        self.isHinted = isHinted
    }

    /// 標準 34 種を描くとき用（四人打ち麻雀はこちら）。
    public init(
        tile: MahjongTile,
        width: CGFloat,
        height: CGFloat,
        isBlocked: Bool = false,
        isSelected: Bool = false,
        isHinted: Bool = false
    ) {
        self.init(
            face: .standard(tile),
            width: width,
            height: height,
            isBlocked: isBlocked,
            isSelected: isSelected,
            isHinted: isHinted
        )
    }

    public var body: some View {
        let corner = width * 0.18
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(MahjongTileArt.faceColor)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected || isHinted ? width * 0.1 : max(0.5, width * 0.03))
            MahjongTileArt(face: face, width: width * 0.76, height: height * 0.68)
        }
        .frame(width: width, height: height)
        .overlay {
            if isBlocked {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(hex: 0x4A3B33, alpha: 0.22))
            }
        }
        .shadow(color: .black.opacity(0.18), radius: width * 0.06, x: width * 0.03, y: width * 0.05)
    }

    private var borderColor: Color {
        if isSelected { return Theme.coral }
        if isHinted { return Theme.teal }
        return Color(hex: 0xD9CDB8)
    }
}

// MARK: - 牌の面の絵柄

/// 牌の面だけを与えられた大きさで描く。枠や影は持たないので、牌一覧・凡例などにも使える。
public struct MahjongTileArt: View {
    public let face: MahjongFace
    /// 絵柄を収める領域の幅。
    public let width: CGFloat
    /// 絵柄を収める領域の高さ。
    public let height: CGFloat

    public init(face: MahjongFace, width: CGFloat, height: CGFloat) {
        self.face = face
        self.width = width
        self.height = height
    }

    static let faceColor = Color(hex: 0xFFFCF2)
    static let circleColor = Color(hex: 0x2E6FD8)
    static let bambooColor = Color(hex: 0x2E9E5B)
    /// 五筒の中心・五索/七索・一索のくちばしなど、実物の牌で赤く塗られている部分。
    /// 同じ形が並ぶ数牌どうしの見分けにも効く。
    static let accentColor = Color(hex: 0xC63A2E)

    private static let kanjiNumerals = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
    private static let winds = ["東", "南", "西", "北"]
    private static let flowers = ["梅", "蘭", "菊", "竹"]
    private static let seasons = ["春", "夏", "秋", "冬"]

    public var body: some View {
        content.frame(width: width, height: height)
    }

    @ViewBuilder
    private var content: some View {
        switch face {
        case .standard(.characters(let n)): charactersFace(n)
        case .standard(.circles(let n)):    circlesFace(n)
        case .standard(.bamboos(let n)):    bamboosFace(n)
        case .standard(.wind(let n)):       glyph(Self.winds[clamp(n, 3)], color: Theme.ink)
        case .standard(.dragon(let n)):     dragonFace(n)
        case .flower(let n):                glyph(Self.flowers[clamp(n, 3)], color: Theme.purple)
        case .season(let n):                glyph(Self.seasons[clamp(n, 3)], color: Theme.pink)
        }
    }

    private func clamp(_ n: Int, _ upper: Int) -> Int { max(0, min(upper, n)) }

    // MARK: 萬子

    private func charactersFace(_ n: Int) -> some View {
        VStack(spacing: -height * 0.06) {
            Text(Self.kanjiNumerals[clamp(n - 1, 8)])
                .font(.system(size: width * 0.62, weight: .bold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("萬")
                .font(.system(size: width * 0.46, weight: .bold, design: .serif))
                .foregroundStyle(Self.accentColor)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
    }

    // MARK: 筒子

    /// 筒（円）の配置。実物の牌に合わせ、枚数ごとに決まった並びで置く。
    /// 座標は絵柄領域を 0〜1 に正規化したもの。
    private static func circleLayout(_ n: Int) -> (points: [CGPoint], diameter: CGFloat, accents: Set<Int>) {
        switch n {
        case 1:  return ([CGPoint(x: 0.5, y: 0.5)], 0.66, [])
        case 2:  return ([CGPoint(x: 0.5, y: 0.22), CGPoint(x: 0.5, y: 0.78)], 0.42, [])
        // 三筒は左上から右下への斜め並び。
        case 3:  return ([CGPoint(x: 0.22, y: 0.18), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.78, y: 0.82)], 0.38, [])
        case 4:  return (grid(xs: [0.28, 0.72], ys: [0.22, 0.78]), 0.38, [])
        // 五筒は四隅＋中央。中央は実物どおり赤。
        case 5:  return (grid(xs: [0.24, 0.76], ys: [0.18, 0.82]) + [CGPoint(x: 0.5, y: 0.5)], 0.32, [4])
        case 6:  return (grid(xs: [0.27, 0.73], ys: [0.16, 0.5, 0.84]), 0.32, [])
        // 七筒は上段に 3 つ、下段に 2×2。
        case 7:  return ([CGPoint(x: 0.2, y: 0.14), CGPoint(x: 0.5, y: 0.14), CGPoint(x: 0.8, y: 0.14)]
                         + grid(xs: [0.29, 0.71], ys: [0.55, 0.86]), 0.28, [])
        case 8:  return (grid(xs: [0.29, 0.71], ys: [0.12, 0.37, 0.63, 0.88]), 0.28, [])
        default: return (grid(xs: [0.18, 0.5, 0.82], ys: [0.16, 0.5, 0.84]), 0.28, [])
        }
    }

    /// 行優先で格子状に並べた座標（y を外側に回すので、上の行から順に並ぶ）。
    private static func grid(xs: [CGFloat], ys: [CGFloat]) -> [CGPoint] {
        ys.flatMap { y in xs.map { CGPoint(x: $0, y: y) } }
    }

    private func circlesFace(_ n: Int) -> some View {
        let layout = Self.circleLayout(min(max(n, 1), 9))
        let diameter = layout.diameter * width
        return ZStack {
            ForEach(layout.points.indices, id: \.self) { index in
                circleDot(
                    diameter: diameter,
                    color: layout.accents.contains(index) ? Self.accentColor : Self.circleColor
                )
                .position(x: layout.points[index].x * width, y: layout.points[index].y * height)
            }
        }
    }

    /// 筒 1 つ。実物は同心円だが、内側の輪は潰れると滲むだけなので実寸で描き分ける。
    private func circleDot(diameter: CGFloat, color: Color) -> some View {
        ZStack {
            Circle().fill(color)
            if diameter >= 7 {
                Circle()
                    .strokeBorder(Self.faceColor, lineWidth: max(0.5, diameter * 0.11))
                    .frame(width: diameter * 0.6, height: diameter * 0.6)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: 索子

    /// 竹（索）の配置。行ごとの x 座標（正規化）で表す。行は上から等間隔に置く。
    /// 添字は「行番号 × 行内の位置」で、赤く塗る 1 本を `accent` で指す。
    private static func bambooLayout(_ n: Int) -> (rows: [[CGFloat]], accent: (row: Int, column: Int)?) {
        switch n {
        case 2:  return ([[0.5], [0.5]], nil)
        case 3:  return ([[0.5], [0.28, 0.72]], nil)
        case 4:  return ([[0.28, 0.72], [0.28, 0.72]], nil)
        // 五索は四隅＋中央で、中央が赤。
        case 5:  return ([[0.26, 0.74], [0.5], [0.26, 0.74]], (1, 0))
        case 6:  return ([[0.22, 0.5, 0.78], [0.22, 0.5, 0.78]], nil)
        // 七索は上に 1 本（赤）＋下に 3×2。
        case 7:  return ([[0.5], [0.22, 0.5, 0.78], [0.22, 0.5, 0.78]], (0, 0))
        case 8:  return ([[0.16, 0.39, 0.61, 0.84], [0.16, 0.39, 0.61, 0.84]], nil)
        default: return ([[0.22, 0.5, 0.78], [0.22, 0.5, 0.78], [0.22, 0.5, 0.78]], nil)
        }
    }

    @ViewBuilder
    private func bamboosFace(_ n: Int) -> some View {
        // 一索は実物どおり鳥（雀）の意匠。竹 1 本だと二索の片方と紛らわしいので絵柄を変える。
        if n <= 1 {
            MahjongBirdArt(size: min(width, height))
        } else {
            let layout = Self.bambooLayout(min(n, 9))
            let columns = layout.rows.map(\.count).max() ?? 1
            let rowHeight = height / CGFloat(layout.rows.count)
            let stickHeight = rowHeight * 0.84
            // 竹は縦長でなければ竹に見えない。列数だけで太さを決めると、1 列しかない二索や
            // 五索の中央が「丸い塊」になって筒子と紛らわしくなるため、高さ基準の上限で抑える。
            let stickWidth = max(1.2, min(width / CGFloat(columns) * 0.55, stickHeight * 0.36))
            ZStack {
                ForEach(layout.rows.indices, id: \.self) { row in
                    ForEach(layout.rows[row].indices, id: \.self) { column in
                        BambooStick(
                            width: stickWidth,
                            height: stickHeight,
                            color: layout.accent?.row == row && layout.accent?.column == column
                                ? Self.accentColor : Self.bambooColor
                        )
                        .position(
                            x: layout.rows[row][column] * width,
                            y: (CGFloat(row) + 0.5) * rowHeight
                        )
                    }
                }
            }
        }
    }

    // MARK: 字牌

    /// 三元牌。中・發は文字だが、**白（白板）は文字ではなく枠だけ**というのが実物の牌。
    @ViewBuilder
    private func dragonFace(_ n: Int) -> some View {
        switch n {
        case 0:  glyph("中", color: Self.accentColor)
        case 1:  glyph("發", color: Self.bambooColor)
        default: whiteDragonFace
        }
    }

    private var whiteDragonFace: some View {
        let inset = width * 0.12
        return ZStack {
            RoundedRectangle(cornerRadius: width * 0.1, style: .continuous)
                .strokeBorder(Self.circleColor, lineWidth: max(0.8, width * 0.07))
            RoundedRectangle(cornerRadius: width * 0.06, style: .continuous)
                .strokeBorder(Self.circleColor, lineWidth: max(0.5, width * 0.04))
                .padding(inset)
        }
        .frame(width: width * 0.84, height: height * 0.88)
    }

    private func glyph(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: width * 0.82, weight: .bold, design: .serif))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }
}

// MARK: - 部品

/// 竹（索）1 本。節は小さいと潰れて汚れに見えるので実寸で描き分ける。
private struct BambooStick: View {
    let width: CGFloat
    let height: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            Capsule(style: .continuous).fill(color)
            if height >= 12 {
                VStack(spacing: height * 0.24) {
                    node
                    node
                }
            }
        }
        .frame(width: width, height: height)
    }

    private var node: some View {
        Capsule()
            .fill(MahjongTileArt.faceColor.opacity(0.9))
            .frame(width: width * 0.86, height: max(0.5, height * 0.05))
    }
}

/// 一索の鳥。輪郭を描き込むと小さいときに黒い塊になるので、体・頭・尾・くちばしの
/// 4 つの塊だけで作り、色の差で形を読ませる。
private struct MahjongBirdArt: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // 尾
            Capsule()
                .fill(MahjongTileArt.accentColor)
                .frame(width: size * 0.46, height: size * 0.11)
                .rotationEffect(.degrees(38))
                .offset(x: size * 0.21, y: size * 0.3)
            // 胴
            Ellipse()
                .fill(MahjongTileArt.bambooColor)
                .frame(width: size * 0.46, height: size * 0.6)
                .rotationEffect(.degrees(-20))
                .offset(x: size * 0.02, y: size * 0.06)
            // 頭
            Circle()
                .fill(MahjongTileArt.bambooColor)
                .frame(width: size * 0.3, height: size * 0.3)
                .offset(x: -size * 0.14, y: -size * 0.3)
            // くちばし
            BeakShape()
                .fill(MahjongTileArt.accentColor)
                .frame(width: size * 0.18, height: size * 0.14)
                .offset(x: -size * 0.32, y: -size * 0.26)
            if size >= 14 {
                Circle()
                    .fill(MahjongTileArt.faceColor)
                    .frame(width: size * 0.07, height: size * 0.07)
                    .offset(x: -size * 0.17, y: -size * 0.34)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 左を向いたくちばし。
private struct BeakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
