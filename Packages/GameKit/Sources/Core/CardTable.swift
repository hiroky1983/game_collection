import SwiftUI

/// 「札を場に並べて動かす」型のゲームの共通基盤（#524）。
///
/// ソリティア（クロンダイク・#397）とフリーセル（#492）は、ルールこそ別物だが
/// **盤の組み立て方は同じ**である: 空き枠を敷き、札を段差で重ね、ドラッグで持ち上げて
/// 枠に落とす。#492 の実装がクロンダイクの View を写して作られたため、この部分が
/// 2 か所に同じ形で存在していた。ここへ寄せて 1 つにする。
///
/// **ルールに触れるものは置かない**。合法判定・選択・記録はゲーム側のモデルの関心で、
/// ここが受け持つのは「枠・段差・指の位置・配りの動き」という描画と入力の器だけ。
/// `PlayingCard`（札 1 枚の面・#397）と `CardStyle`（紙の質感・#366）の上に載る層になる。

// MARK: - 卓の面（#1501）

/// 札・牌を並べる「卓」の面の寸法と色。ソリティア・スパイダー・フリーセル・麻雀ソリティアの
/// 4 本が**この 1 つ**を共有する（ゲームごとに別の卓は作らない）。
///
/// 4 本はどれも画面の地（`Theme.background`）の上に札・牌が直接乗っていて、遊ぶ場所の区切りが
/// 無かった。見た目は、麻雀（4 人打ち）の雀卓 `MahjongTableSurface` の**フェルトと木枠**を、
/// ポーカー・ブラックジャック・花札の `popCard`（角丸 20 + 落ち影）の**外形**に収めたもの。
/// フェルトの緑・木枠の茶は雀卓と同じ値で、盤・駒・牌と同じく**ライト / ダークで変えない**
/// （`Theme.Fixed` と同じ扱い）。上に乗る空き枠・仕切り・文字の色だけ `CardTableInk` で白系に振る。
///
/// `Color` は生成後に成分を取り出せないため、雀卓との一致とコントラストを検証する
/// `CardTableSurfaceTests` が参照できるよう数値のままここに置く。
public enum CardTableStyle {
    /// フェルトの中央 → 縁。`MahjongTableSurface` のフェルトと同じ値。
    public static let feltCenter: UInt32 = 0x2E7A50
    public static let feltEdge: UInt32 = 0x14432C
    /// 木枠の上 → 中 → 下。`MahjongTableSurface` の木枠と同じ値。
    public static let rimTop: UInt32 = 0xC48A4A
    public static let rimMiddle: UInt32 = 0x8A5A2B
    public static let rimBottom: UInt32 = 0x4A2C12
    /// 木枠の太さ。
    public static let rimWidth: CGFloat = 3
    /// 木枠の内側から札・牌までの余白。狭い画面（iPhone SE・スパイダーの 10 列）で札を削りすぎない値。
    public static let contentInset: CGFloat = 6
    /// 角丸。`popCard` と同じ。
    public static let corner: CGFloat = Theme.corner
    /// フェルトの中央色をそのまま伸ばす半径（全体に対する比）と、縁の暗さに達する半径。
    public static let feltPlateauFraction: CGFloat = 0.35
    public static let feltEdgeFraction: CGFloat = 0.85
    /// フェルトの上に置く白の不透明度。空き枠の破線と印は 3:1（WCAG 1.4.11 の非テキスト）、
    /// 文字は 4.5:1（AA）をフェルトの**いちばん明るい中央**に対して満たす値
    /// （`CardTableSurfaceTests` で固定）。
    public static let feltSlotAlpha: Double = 0.65
    public static let feltDividerAlpha: Double = 0.65
    public static let feltLabelAlpha: Double = 1
    public static let feltLabelSubAlpha: Double = 0.9
}

/// 卓の上に乗る「札・牌ではないもの」の色（空き枠の破線と印・上段の仕切り・盤の場所に出す文字）。
///
/// 地の上（既定）では `Theme.inkSub` / `Theme.ink` の系統、フェルトの上では白の系統。
/// `View.cardTable()` が環境値 `cardTableInk` にフェルト用を配り、`CardSlot` などがそれを読む。
/// 空き枠を描く側が「卓の上か」を知らなくて済むようにするための間接化で、
/// 4 本の画面のどこにも色の分岐を持たせない。
public struct CardTableInk: Sendable {
    /// 空き枠の破線。
    public var slotStroke: Color
    /// 空き枠の印（スート記号・SF Symbol）。
    public var slotMark: Color
    /// 上段の仕切り（フリーセルの左 4 枠と右 4 枠の境目）。
    public var divider: Color
    /// 盤の場所に出す見出し（麻雀ソリティアの「全部取り切った！」）。
    public var label: Color
    /// 同じ場所の補助文字。
    public var labelSub: Color

    public init(slotStroke: Color, slotMark: Color, divider: Color, label: Color, labelSub: Color) {
        self.slotStroke = slotStroke
        self.slotMark = slotMark
        self.divider = divider
        self.label = label
        self.labelSub = labelSub
    }

    /// 地（`Theme.background`）の上。従来の値そのまま。
    public static let plain = CardTableInk(
        slotStroke: Theme.inkSub.opacity(0.35),
        slotMark: Theme.inkSub.opacity(0.45),
        divider: Theme.inkSub.opacity(0.5),
        label: Theme.ink,
        labelSub: Theme.inkSub
    )

    /// フェルトの上。
    public static let felt = CardTableInk(
        slotStroke: Color.white.opacity(CardTableStyle.feltSlotAlpha),
        slotMark: Color.white.opacity(CardTableStyle.feltSlotAlpha),
        divider: Color.white.opacity(CardTableStyle.feltDividerAlpha),
        label: Color.white.opacity(CardTableStyle.feltLabelAlpha),
        labelSub: Color.white.opacity(CardTableStyle.feltLabelSubAlpha)
    )
}

private struct CardTableInkKey: EnvironmentKey {
    static let defaultValue = CardTableInk.plain
}

public extension EnvironmentValues {
    /// 卓の上に乗る空き枠・仕切り・文字の色。`View.cardTable()` を付けた祖先から配られる。
    var cardTableInk: CardTableInk {
        get { self[CardTableInkKey.self] }
        set { self[CardTableInkKey.self] = newValue }
    }
}

/// 卓の上に置くものの色を、**その場所で**読んで組み立てるための器。
///
/// 環境値は祖先から子孫へしか流れないので、`.cardTable()` を付けた盤の**親**（画面の View 本体）が
/// `@Environment(\.cardTableInk)` を持っても既定の `.plain` しか届かない（verifier の再現で実測）。
/// 仕切り・卓上の文字のように盤の中に置く部品は、必ずこの器（か自前の `@Environment` を持つ子 View）
/// 経由で色を取る。`CardTableSurfaceTests` が「画面の View 本体で読んでいない」ことを走査で固定する。
public struct CardTableInkReader<Content: View>: View {
    @Environment(\.cardTableInk) private var ink
    private let content: (CardTableInk) -> Content

    public init(@ViewBuilder content: @escaping (CardTableInk) -> Content) {
        self.content = content
    }

    public var body: some View {
        content(ink)
    }
}

/// 卓の面そのもの（木枠 + フェルト + 木枠の内側の落ち影 + 外の落ち影）。
///
/// 雀卓（`MahjongTableSurface`）は `Canvas` に台形を描いていたが、ここは角丸の長方形なので
/// `RoundedRectangle` で組む。フェルトの照りは `EllipticalGradient`（大きさに対する比で指定できる）に
/// して `GeometryReader` を挟まない。読み上げはしない（面は情報を持たない）。
public struct CardTableSurface: View {
    public init() {}

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CardTableStyle.corner, style: .continuous)
    }

    public var body: some View {
        shape
            .fill(EllipticalGradient(
                stops: [
                    .init(color: Color(hex: CardTableStyle.feltCenter), location: 0),
                    .init(color: Color(hex: CardTableStyle.feltCenter), location: CardTableStyle.feltPlateauFraction),
                    .init(color: Color(hex: CardTableStyle.feltEdge), location: CardTableStyle.feltEdgeFraction),
                ],
                center: .center, startRadiusFraction: 0, endRadiusFraction: 0.7
            ))
            // 木枠の内側の落ち影（フェルトに切り抜いたぼかし線。雀卓と同じ作り）。
            .overlay(
                shape.inset(by: CardTableStyle.rimWidth)
                    .strokeBorder(Color.black.opacity(0.45), lineWidth: 5)
                    .blur(radius: 3)
                    .clipShape(shape.inset(by: CardTableStyle.rimWidth))
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color(hex: CardTableStyle.rimTop),
                                 Color(hex: CardTableStyle.rimMiddle),
                                 Color(hex: CardTableStyle.rimBottom)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: CardTableStyle.rimWidth)
            )
            .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 6)
            .accessibilityHidden(true)
    }
}

public extension View {
    /// このビューを卓の上に置く（#1501）。木枠と内側の余白ぶんだけ中身が縮む
    /// （中身が `GeometryReader` で札の大きさを決めていれば、そのまま卓に収まる）。
    func cardTable() -> some View {
        padding(CardTableStyle.rimWidth + CardTableStyle.contentInset)
            .background(CardTableSurface())
            .environment(\.cardTableInk, .felt)
    }
}

// MARK: - 空き枠

/// 札の無い枠（山札・組札・フリーセル・空いた列）。破線の角丸に印を 1 つ置く。
///
/// 印は**スート記号（文字）か SF Symbol のどちらか**で、両方渡されたらスートを優先する
/// （組札の空き枠は ♠♥♦♣ を出し、それ以外は用途の絵を出す、という既存の使い分けに合わせる）。
/// 色は `cardTableInk`（卓の上なら白系、地の上なら `Theme.inkSub` 系）から取る。
public struct CardSlot: View {
    private let metrics: PlayingCardMetrics
    private let systemImage: String?
    private let suitSymbol: String?
    @Environment(\.cardTableInk) private var ink

    public init(metrics: PlayingCardMetrics, systemImage: String? = nil, suitSymbol: String? = nil) {
        self.metrics = metrics
        self.systemImage = systemImage
        self.suitSymbol = suitSymbol
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .strokeBorder(ink.slotStroke,
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            if let suitSymbol {
                Text(suitSymbol)
                    .font(.system(size: metrics.suitFont))
                    .foregroundStyle(ink.slotMark)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: metrics.suitFont * 0.8, weight: .semibold))
                    .foregroundStyle(ink.slotMark)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
    }
}

// MARK: - ドロップ先の当たり判定

/// ドロップ先の枠を子ビューから集める（`Target` はゲームごとの「置き先」の列挙）。
///
/// 同じ枠が二度報告されることは無いが、順序は不定なので**後から来たほうを採る**。
public struct CardDropFramesKey<Target: Hashable>: PreferenceKey {
    public static var defaultValue: [Target: CGRect] { [:] }

    public static func reduce(value: inout [Target: CGRect],
                              nextValue: () -> [Target: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

public extension View {
    /// このビューの枠を「`target` の置き先」として盤の座標空間で報告する。
    ///
    /// 枠はレイアウトに影響させない `background` から測る。ビュー本体に `GeometryReader` を
    /// 被せると、札の大きさが読み取り結果に引きずられる。
    func cardDropTarget<Target: Hashable>(_ target: Target, in space: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(
                key: CardDropFramesKey<Target>.self,
                value: [target: geometry.frame(in: .named(space))])
        })
    }
}

// MARK: - ドラッグ中の指の位置

/// 盤座標系での指の位置だけを持つ入れ物（#521）。
///
/// 参照型にして「盤本体は持たず、追従表示だけが読む」形にするためのもの。値型で
/// `@State` に置くと、指を 1 サンプル動かすたびに盤のビュー全体が無効化される。
/// `@Observable` なので、`point` を body で読んだビューだけが作り直される。
@MainActor @Observable public final class CardDragLocation {
    public var point: CGPoint = .zero

    public init(point: CGPoint = .zero) {
        self.point = point
    }
}

/// 追従表示の位置合わせ。
public enum CardDragLayout {
    /// 指の位置とつかんだ点のずれから、持ち上げた札の左上を出す。
    public static func origin(location: CGPoint, grab: CGSize) -> CGPoint {
        CGPoint(x: location.x - grab.width, y: location.y - grab.height)
    }
}

/// 指に追従する持ち上げた札。**位置を読むのはこの body の中だけ**（#521）。
///
/// 盤本体から独立したビューにすることで、指の動きによる無効化がこのビューで止まる。
/// 当たり判定は持たない（ドロップ先は下の盤が報告する）。
public struct CardDragLayer<Card: Identifiable, Content: View>: View {
    private let cards: [Card]
    private let grab: CGSize
    private let location: CardDragLocation
    /// 持ち上げた並びを重ねる段差。盤の列と同じ値を渡す。
    private let step: CGFloat
    private let content: (Int, Card) -> Content

    public init(
        cards: [Card],
        grab: CGSize,
        location: CardDragLocation,
        step: CGFloat,
        @ViewBuilder content: @escaping (Int, Card) -> Content
    ) {
        self.cards = cards
        self.grab = grab
        self.location = location
        self.step = step
        self.content = content
    }

    public var body: some View {
        let origin = CardDragLayout.origin(location: location.point, grab: grab)
        ZStack(alignment: .top) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                content(index, card)
                    .offset(y: CGFloat(index) * step)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
        .offset(x: origin.x, y: origin.y)
        .allowsHitTesting(false)
    }
}

// MARK: - 配札

/// 配り元から飛んできて場札に収まる 1 枚（#421）。
///
/// 段差は「配られた順」で決まりビューの再生成では変わらないので、状態は**このビュー自身が持つ**
/// （ブラックジャックの `BJDealtCardView` と同じ設計）。`dealing` が false のときは何もしない。
///
/// 飛び始める位置と動きは**ゲームごとの `Motion` が決める**ので、ここでは受け取るだけにする
/// （配り元の場所も配る順も、クロンダイクとフリーセルで違う）。
public struct CardDealtView<Content: View>: View {
    private let startOffset: CGSize
    private let animation: Animation
    private let content: Content

    /// 置き終わったか。`false` の間だけ配り元の位置に隠しておく。
    @State private var dealt: Bool

    public init(
        startOffset: CGSize,
        animation: Animation,
        dealing: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.startOffset = startOffset
        self.animation = animation
        self.content = content()
        _dealt = State(initialValue: !dealing)
    }

    public var body: some View {
        content
            .offset(x: dealt ? 0 : startOffset.width, y: dealt ? 0 : startOffset.height)
            .opacity(dealt ? 1 : 0)
            .onAppear {
                guard !dealt else { return }
                // Reduce Motion が ON なら `withGameAnimation` が補間を落とすので、
                // 遅れも動きも無く即座に置かれる（状態変更そのものは必ず走る）。
                withGameAnimation(animation) { dealt = true }
            }
    }
}

// MARK: - 移動の補間

/// 移動の補間で札どうしを結ぶ鍵（#421）。
///
/// 配り直しの世代（`deal`）を含めるので、**世代が変わると結ばれない**。またいで結ぶと、
/// 新しい配札の札が前の配札での居場所から飛んでくることになり、配る演出と食い違う。
public struct CardMotionID: Hashable {
    public let deal: Int
    public let card: Int

    public init(deal: Int, card: Int) {
        self.deal = deal
        self.card = card
    }
}

// MARK: - 列の段差と、帯だけ見えている札の見出し

/// 列に重ねた札の段差・押せる範囲・見出しの寸法（フリーセル・スパイダー共通）。
///
/// 札の幅は「画面幅 ÷ 列の数」でほぼ決まり横には広げられないが、**縦は盤の下に大きく余る**
/// （iPhone 17 で盤が画面の上 4 割しか使っていなかった）。そこで段差を固定比にせず、
/// **いちばん長い列が盤の下端に収まる範囲で広げる**。段差は全列で同じ値にする
/// （列ごとに違うと見た目が揃わない）。
///
/// - 下限は従来の固定比（表向き 0.24・伏せ札 0.13）。**今より詰めることはしない**。
/// - 上限は表向き 0.45。広げすぎると同じ列の札が離れて、1 本の列に見えなくなる。
/// - 伏せ札は表向きと同じ倍率で伸ばす（表向きより狭い関係を保つ）。
///
/// 同じ役割の UI は同じ見た目にする決まりなので、2 つのゲームは**この 1 つの計算**を通す。
public struct CardStackLayout: Equatable, Sendable {
    /// 表向きの札を重ねる段差。
    public let faceUpStep: CGFloat
    /// 伏せ札を重ねる段差。
    public let faceDownStep: CGFloat
    /// 列が押せる範囲（ドロップ枠を含む）の高さ。**盤の下端まで**伸ばす。
    public let reachHeight: CGFloat
    /// 帯だけ見えている札の見出し。
    public let index: CardStackIndexMetrics

    /// 列 1 本の札の内訳。
    public struct Column: Equatable, Sendable {
        public let faceDown: Int
        public let faceUp: Int

        public init(faceDown: Int = 0, faceUp: Int) {
            self.faceDown = max(0, faceDown)
            self.faceUp = max(0, faceUp)
        }
    }

    /// 段差の下限（札の高さに対する比）。従来の固定値。
    public static let minFaceUpRatio: CGFloat = 0.24
    public static let minFaceDownRatio: CGFloat = 0.13
    /// 表向きの段差の上限比。伏せ札の上限はこれと同じ倍率ぶん（0.13 × 0.45 / 0.24）。
    public static let maxFaceUpRatio: CGFloat = 0.45
    /// 盤の左右の余白（画面の端から盤まで）。帯やボタンの `Theme.pad`（16pt）より詰める。
    public static let boardSideInset: CGFloat = 4
    /// いちばん長い列の最後の札と、盤の下端とのあいだに残す余白。
    public static let bottomMargin: CGFloat = 4

    public init(faceUpStep: CGFloat, faceDownStep: CGFloat, reachHeight: CGFloat, index: CardStackIndexMetrics) {
        self.faceUpStep = faceUpStep
        self.faceDownStep = faceDownStep
        self.reachHeight = reachHeight
        self.index = index
    }

    /// 札の幅・高さ、場札に使える高さ（上段の下から盤の下端まで）、全列の内訳から寸法を決める。
    ///
    /// `tableauHeight` が 0 以下（`GeometryReader` が最初に渡す大きさ 0 など）のときは下限の段差になる。
    public static func make(
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        tableauHeight: CGFloat,
        columns: [Column]
    ) -> CardStackLayout {
        let steps = steps(cardHeight: cardHeight, tableauHeight: tableauHeight, columns: columns)
        return CardStackLayout(
            faceUpStep: steps.faceUp,
            faceDownStep: steps.faceDown,
            reachHeight: max(0, tableauHeight),
            index: CardStackIndexMetrics.make(cardWidth: cardWidth, faceUpStep: steps.faceUp)
        )
    }

    public static func minFaceUpStep(cardHeight: CGFloat) -> CGFloat { (cardHeight * minFaceUpRatio).rounded() }
    public static func minFaceDownStep(cardHeight: CGFloat) -> CGFloat { (cardHeight * minFaceDownRatio).rounded() }
    public static func maxFaceUpStep(cardHeight: CGFloat) -> CGFloat {
        max(minFaceUpStep(cardHeight: cardHeight), (cardHeight * maxFaceUpRatio).rounded(.down))
    }
    public static func maxFaceDownStep(cardHeight: CGFloat) -> CGFloat {
        max(minFaceDownStep(cardHeight: cardHeight),
            (cardHeight * minFaceDownRatio * maxFaceUpRatio / minFaceUpRatio).rounded(.down))
    }

    /// 全列で共通の段差。いちばん長い列（下限の段差で測って最も高くなる列）が収まる倍率を取る。
    ///
    /// 倍率は下限（1 倍）と上限（0.45 / 0.24 倍）で挟む。切り捨てで丸めるので、
    /// 下限に掛からない限り**いちばん長い列は `tableauHeight - bottomMargin` を超えない**。
    public static func steps(
        cardHeight: CGFloat,
        tableauHeight: CGFloat,
        columns: [Column]
    ) -> (faceUp: CGFloat, faceDown: CGFloat) {
        let maxScale = maxFaceUpRatio / minFaceUpRatio
        // 各列の「段差の合計」を札の高さを単位にして測る（下限の比のとき）。
        let longestSpan = columns.map { column in
            CGFloat(column.faceDown) * minFaceDownRatio
                + CGFloat(max(0, column.faceUp - 1)) * minFaceUpRatio
        }.max() ?? 0

        let scale: CGFloat
        if longestSpan <= 0 {
            scale = maxScale
        } else {
            let room = tableauHeight - bottomMargin - cardHeight
            scale = min(maxScale, max(1, room / (cardHeight * longestSpan)))
        }
        let up = min(maxFaceUpStep(cardHeight: cardHeight),
                     max(minFaceUpStep(cardHeight: cardHeight),
                         (cardHeight * minFaceUpRatio * scale).rounded(.down)))
        let down = min(maxFaceDownStep(cardHeight: cardHeight),
                       max(minFaceDownStep(cardHeight: cardHeight),
                           (cardHeight * minFaceDownRatio * scale).rounded(.down)))
        return (up, down)
    }

    /// 列 1 本の高さ（いちばん上の札の全体が見える高さまで）。
    public static func columnHeight(_ column: Column, faceUpStep: CGFloat, faceDownStep: CGFloat,
                                    cardHeight: CGFloat) -> CGFloat {
        CGFloat(column.faceDown) * faceDownStep
            + CGFloat(max(0, column.faceUp - 1)) * faceUpStep
            + cardHeight
    }
}

/// 重なって帯だけ見えている札の、左上の「数字 + マーク」の寸法。
///
/// 従来は札の幅に比例した面の文字（`PlayingCardMetrics.rankFont`）の 0.72 倍で、スパイダーでは
/// 9pt 台まで縮んでいた。**帯の高さ**に合わせて大きくし、**「10」+ マークが札の幅に収まる**ところで
/// 頭打ちにする。文字の幅は SF Pro Rounded（Black）の実測から、小さい文字ほど広がる分を見込んだ値。
public struct CardStackIndexMetrics: Equatable, Sendable {
    public let rankFont: CGFloat
    public let suitFont: CGFloat
    /// 数字とマークの間隔。
    public let spacing: CGFloat
    /// 札の左端から文字までの余白。
    public let leading: CGFloat
    /// 文字の枠を札の上端からずらす量。**負の値で上へ寄せる**: 文字の枠は数字の上に
    /// 行の余白（約 0.26em）を持つので、それを帯の中で使うと帯に入る文字が小さくなる。
    public let top: CGFloat
    /// 文字に使える幅（札の幅 − 左右の余白）。
    public let maxWidth: CGFloat

    /// 「10」の幅（em）。SF Pro Rounded Black の実測 1.22〜1.31em（小さいほど広い）を丸めて上に取る。
    public static let tenWidthEm: CGFloat = 1.32
    /// いちばん幅のあるマーク（♥）の幅（em）。実測 0.96em。
    public static let suitWidthEm: CGFloat = 0.98
    /// 数字の上端から行の上端までの余白（em）。ascender 0.967 − cap height 0.705。
    public static let ascenderGapEm: CGFloat = 0.26
    /// 数字の高さ（em）。
    public static let capHeightEm: CGFloat = 0.705
    /// マークの大きさ（数字に対する比）。数字を優先して大きくするためにマークは一回り小さく組む。
    public static let suitRatio: CGFloat = 0.68
    /// 帯の上端から数字の上端まで・数字の下端から次の札までに残す余白。
    public static let bandInset: CGFloat = 2
    /// 数字の大きさの下限（帯が詰まったときでも従来より小さくしない目安）と、札の幅に対する上限比。
    public static let minRankFont: CGFloat = 10
    public static let maxRankFontRatio: CGFloat = 0.45

    public init(rankFont: CGFloat, suitFont: CGFloat, spacing: CGFloat, leading: CGFloat,
                top: CGFloat, maxWidth: CGFloat) {
        self.rankFont = rankFont
        self.suitFont = suitFont
        self.spacing = spacing
        self.leading = leading
        self.top = top
        self.maxWidth = maxWidth
    }

    public static func make(cardWidth: CGFloat, faceUpStep: CGFloat) -> CardStackIndexMetrics {
        let leading = max(2, (cardWidth * 0.06).rounded())
        let trailing: CGFloat = 1.5
        let spacing: CGFloat = 1
        let maxWidth = max(0, cardWidth - leading - trailing)

        // 幅: 「10」+ 間隔 + マークが収まる大きさ。
        let widthBound = (maxWidth - spacing) / (tenWidthEm + suitWidthEm * suitRatio)
        // 高さ: 数字の上端を帯の上端（+余白）に寄せたとき、下端が次の札の手前（−余白）に収まる大きさ。
        let heightBound = (faceUpStep - bandInset * 2) / capHeightEm
        let ceiling = cardWidth * maxRankFontRatio

        let rank = max(1, min(ceiling, widthBound, max(minRankFont, heightBound)).rounded(.down))
        let suit = (rank * suitRatio).rounded(.down)
        return CardStackIndexMetrics(
            rankFont: rank,
            suitFont: suit,
            spacing: spacing,
            leading: leading,
            top: bandInset - ascenderGapEm * rank,
            maxWidth: maxWidth
        )
    }

    /// 「10」+ マークの見込み幅。`maxWidth` 以下であることをテストで固定する。
    public var estimatedTenWidth: CGFloat {
        rankFont * Self.tenWidthEm + spacing + suitFont * Self.suitWidthEm
    }
}

/// 重なって帯だけ見えている札の見出し（左上の数字 + マーク）。フリーセル・スパイダー共通。
public struct CardStackIndex: View {
    private let rankLabel: String
    private let suit: PlayingCardSuit
    private let metrics: CardStackIndexMetrics

    public init(rankLabel: String, suit: PlayingCardSuit, metrics: CardStackIndexMetrics) {
        self.rankLabel = rankLabel
        self.suit = suit
        self.metrics = metrics
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics.spacing) {
            Text(rankLabel)
                .font(.system(size: metrics.rankFont, weight: .black, design: .rounded))
            Text(suit.symbol)
                .font(.system(size: metrics.suitFont, weight: .bold))
        }
        .lineLimit(1)
        // 見込み幅（`estimatedTenWidth`）で収めてあるが、端末の字形の差で溢れたときは
        // 切れる（「1…」）より縮むほうが読める。
        .minimumScaleFactor(0.7)
        .foregroundStyle(PlayingCardInk.color(for: suit))
        .frame(width: metrics.maxWidth, alignment: .leading)
        .offset(x: metrics.leading, y: metrics.top)
        .allowsHitTesting(false)
    }
}
