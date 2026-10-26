import SwiftUI

/// 対戦相手（CPU）の席の共通部品（#2531）。
///
/// いろリレー（#2369）の相手の見せ方——**色と記号の丸いアイコン・手番の黄色い輪・裏向きの札の束・残り枚数の札・
/// 直前の手の吹き出し**——を、大富豪にも使う（会長「CPU のディテールとか色リレーの感じに寄せれない？」2026-10-19）。
/// 2 本で同じ見た目にするため、席の組み方はここ 1 か所に置き、ゲーム側は札の裏（トランプ / いろリレーの札）と
/// 読み上げ文だけを渡す。
///
/// 卓（フェルト）の上に置く前提で、文字色は `cardTableInk` から取る（地の上なら墨の系統、フェルトの上なら白の系統）。

// MARK: - アイコンの印

/// 相手 3 人のアイコンの印（#2369 会長決裁: おじさんの絵は使わず、シンプルな印で見分ける）。
///
/// **色違いの丸 + 形の違う記号**の 2 つで見分ける（色だけに頼らない）。丸の色は札の色（いろリレーの 4 色・
/// トランプの赤黒）と取り違えないよう、札に無い色（桃・墨・生成り）にしている。
public enum OpponentSeatStyle {
    /// `index`（1〜3）の人の記号（SF Symbols）。
    public static func symbol(for index: Int) -> String {
        switch index {
        case 1:  return "star.fill"
        case 2:  return "moon.fill"
        default: return "cloud.fill"
        }
    }

    /// 丸の色と記号の色（`0xRRGGBB`）。卓の上に置くのでライト / ダークで変えない。
    public static func colors(for index: Int) -> (disc: UInt32, mark: UInt32) {
        switch index {
        case 1:  return (Theme.Hex.Fill.pink, Theme.Hex.onAccent)
        case 2:  return (Theme.Hex.ink.light, 0xFFFFFF)
        default: return (Theme.Hex.background.light, Theme.Hex.onAccent)
        }
    }

    /// 丸の直径。狭い画面（iPhone SE）は 44、それ以外は 56（いろリレーの値）。
    public static func iconDiameter(compact: Bool) -> CGFloat { compact ? 44 : 56 }
    /// 裏向きの札 1 枚の幅。
    public static func cardWidth(compact: Bool) -> CGFloat { compact ? 20 : 24 }
    /// 束で重ねる札の最大枚数（枚数は文字で出す）。
    public static let maxFanCards = 5
    /// 束の札どうしのずれ（札の幅に対する比）。
    public static let fanStepRatio: CGFloat = 0.42
    /// 席の中の部品の縦の間隔。
    public static let spacing: CGFloat = 4

    /// 束の幅（札の幅 + ずれ × (見せる枚数 − 1)）。0 枚でも 1 枚ぶんの幅を残す（席の高さ・幅を揺らさない）。
    public static func fanWidth(count: Int, cardWidth: CGFloat) -> CGFloat {
        let shown = max(1, min(count, maxFanCards))
        return cardWidth + cardWidth * fanStepRatio * CGFloat(shown - 1)
    }
}

// MARK: - アイコン

/// 相手 1 人のアイコン。手番の人は黄色の太い輪で囲む。
public struct OpponentSeatIcon: View {
    private let index: Int
    private let diameter: CGFloat
    private let isCurrent: Bool

    public init(index: Int, diameter: CGFloat, isCurrent: Bool = false) {
        self.index = index
        self.diameter = diameter
        self.isCurrent = isCurrent
    }

    public var body: some View {
        let colors = OpponentSeatStyle.colors(for: index)
        ZStack {
            Circle()
                .fill(Color(hex: colors.disc))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            Image(systemName: OpponentSeatStyle.symbol(for: index))
                .font(.system(size: diameter * 0.46, weight: .bold)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                .foregroundStyle(Color(hex: colors.mark))
            Circle()
                .strokeBorder(isCurrent ? Theme.Fill.yellow : Color.white.opacity(0.75),
                              lineWidth: isCurrent ? max(3, diameter * 0.08) : 2)
            if isCurrent {
                // 丸が桃（CPU1）・生成り（CPU3）だと黄色い輪との差が小さいので、輪の内側に細い墨の線を引いて
                // 丸の色によらず輪の縁が立つようにする（PR #2534 の CodeRabbit 指摘）。
                Circle()
                    .strokeBorder(Theme.Fixed.ink.opacity(0.4), lineWidth: 1)
                    .padding(max(3, diameter * 0.08))
                Circle()
                    .strokeBorder(Theme.Fill.yellow.opacity(0.45), lineWidth: max(3, diameter * 0.09))
                    .padding(-max(3, diameter * 0.09))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - 裏向きの札の束

/// 裏向きの札を横に重ねた束（相手の手札）。枚数が多いときは `OpponentSeatStyle.maxFanCards` 枚で止める。
/// 札の裏はゲームごと（トランプ `PlayingCardBack`・いろリレーの裏）なので、描き方だけ受け取る。
public struct OpponentCardFan<Card: View>: View {
    private let count: Int
    private let cardWidth: CGFloat
    private let cardHeight: CGFloat
    private let card: () -> Card

    /// - Parameters:
    ///   - count: 残り枚数。0 なら束を消す（高さは残す）。
    ///   - cardWidth: 札 1 枚の幅。
    ///   - cardHeight: 札 1 枚の高さ。
    ///   - card: 札の裏 1 枚（`cardWidth` × `cardHeight` で描くもの）。
    public init(count: Int, cardWidth: CGFloat, cardHeight: CGFloat, @ViewBuilder card: @escaping () -> Card) {
        self.count = count
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.card = card
    }

    public var body: some View {
        let shown = max(1, min(count, OpponentSeatStyle.maxFanCards))
        let step = cardWidth * OpponentSeatStyle.fanStepRatio
        ZStack(alignment: .leading) {
            ForEach(0..<shown, id: \.self) { i in
                card()
                    .frame(width: cardWidth, height: cardHeight)
                    .offset(x: CGFloat(i) * step)
            }
        }
        .frame(width: OpponentSeatStyle.fanWidth(count: count, cardWidth: cardWidth), height: cardHeight, alignment: .leading)
        .opacity(count == 0 ? 0 : 1)
        .accessibilityHidden(true)
    }
}

// MARK: - 席

/// 相手 1 人の席（アイコン・束・残り枚数・直前の手）。横に 3 つ並べて `frame(maxWidth: .infinity)` で等幅にする。
///
/// 読み上げは 1 まとまりにして `accessibilityLabel` の文で伝える（ゲームごとの文は `DaifugoAccessibility.seatLabel` /
/// `ColorRelayAccessibility.seatLabel`。手番は画面では輪の色でしか示さないので、文に必ず入れる・#2495）。
public struct OpponentSeat<Fan: View>: View {
    private let index: Int
    private let diameter: CGFloat
    private let isCurrent: Bool
    private let cardCount: Int
    private let lastAction: String
    private let lastActionOpacity: Double
    private let accessibilityLabel: String
    private let fan: () -> Fan
    @Environment(\.cardTableInk) private var ink

    /// - Parameters:
    ///   - index: 席の番号（1〜3）。アイコンの色と記号が決まる。
    ///   - diameter: アイコンの直径（`OpponentSeatStyle.iconDiameter(compact:)`）。
    ///   - isCurrent: いまこの人の番か（黄色い輪）。
    ///   - cardCount: 残り枚数。1 枚なら黄色の札で目立たせる。
    ///   - lastAction: 直前の手（空なら吹き出しを透明にして高さだけ残す。CPU が打つたびに場の大きさが揺れないように）。
    ///   - lastActionOpacity: 吹き出しの濃さ（既定 1）。何手も前の手を薄くして、今起きたことと見分けるのに使う。
    ///   - accessibilityLabel: 席 1 まとまりの読み上げ文。
    ///   - fan: 裏向きの札の束（`OpponentCardFan`）。
    public init(index: Int, diameter: CGFloat, isCurrent: Bool, cardCount: Int, lastAction: String,
                lastActionOpacity: Double = 1, accessibilityLabel: String, @ViewBuilder fan: @escaping () -> Fan) {
        self.index = index
        self.diameter = diameter
        self.isCurrent = isCurrent
        self.cardCount = cardCount
        self.lastAction = lastAction
        self.lastActionOpacity = lastActionOpacity
        self.accessibilityLabel = accessibilityLabel
        self.fan = fan
    }

    public var body: some View {
        VStack(spacing: OpponentSeatStyle.spacing) {
            OpponentSeatIcon(index: index, diameter: diameter, isCurrent: isCurrent)
                .gameAnimation(.easeInOut(duration: 0.18), value: isCurrent)
            fan()
            countLabel
            // 吹き出しの高さは空でも取っておく（CPU が打つたびに場の札の大きさが揺れないように）。
            Text(lastAction.isEmpty ? " " : lastAction)
                .scaledFont(10, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.Fixed.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(Color.white))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .opacity(lastAction.isEmpty ? 0 : lastActionOpacity)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// 相手の残り枚数。残り 1 枚は黄色の札にして目立たせる。
    /// 余白は枚数によらず同じにして、残り 1 枚になった瞬間に席の高さ（＝場の高さ）が変わらないようにする（#148 の趣旨）。
    private var countLabel: some View {
        Text(tr("残り%lld枚", cardCount))
            .scaledFont(11, weight: .black, design: .rounded)
            .foregroundStyle(cardCount == 1 ? Theme.onAccent : ink.labelSub)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(cardCount == 1 ? Theme.Fill.yellow : Color.clear))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
