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

// MARK: - 空き枠

/// 札の無い枠（山札・組札・フリーセル・空いた列）。破線の角丸に印を 1 つ置く。
///
/// 印は**スート記号（文字）か SF Symbol のどちらか**で、両方渡されたらスートを優先する
/// （組札の空き枠は ♠♥♦♣ を出し、それ以外は用途の絵を出す、という既存の使い分けに合わせる）。
public struct CardSlot: View {
    private let metrics: PlayingCardMetrics
    private let systemImage: String?
    private let suitSymbol: String?

    public init(metrics: PlayingCardMetrics, systemImage: String? = nil, suitSymbol: String? = nil) {
        self.metrics = metrics
        self.systemImage = systemImage
        self.suitSymbol = suitSymbol
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .strokeBorder(Theme.inkSub.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            if let suitSymbol {
                Text(suitSymbol)
                    .font(.system(size: metrics.suitFont))
                    .foregroundStyle(Theme.inkSub.opacity(0.45))
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: metrics.suitFont * 0.8, weight: .semibold))
                    .foregroundStyle(Theme.inkSub.opacity(0.45))
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
