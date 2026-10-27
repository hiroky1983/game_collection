import SwiftUI
import Core
import CoreMiniCard

/// ソリティア・フリーセル・スパイダーが共通で使う図入りの遊び方の図（#2044）。
/// 札は `RuleMiniCard`。文言は各ゲームの `HowToPlayGuide` が持ち、ここは図だけ。

/// 札 1 枚の指定（数字とスート）。
public struct RuleCardSpec: Sendable {
    public let rank: String
    public let suit: RuleMiniCard.Suit?

    public init(_ rank: String, _ suit: RuleMiniCard.Suit? = nil) {
        self.rank = rank
        self.suit = suit
    }

    @MainActor
    func view(highlighted: Bool = false) -> RuleMiniCard {
        RuleMiniCard(rank, suit: suit, isHighlighted: highlighted)
    }
}

/// 「重ねられる／重ねられない」の組を並べた図。各組は「下に置いてある札」と「その上へ重ねたい札」。
public struct RuleStackPairsFigure: View {
    public struct Pair: Sendable {
        let base: RuleCardSpec
        let placed: RuleCardSpec
        let isOK: Bool

        public init(base: RuleCardSpec, placed: RuleCardSpec, isOK: Bool) {
            self.base = base
            self.placed = placed
            self.isOK = isOK
        }
    }

    private let pairs: [Pair]

    public init(_ pairs: [Pair]) {
        self.pairs = pairs
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 28) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                VStack(spacing: 6) {
                    RuleMiniCardColumn(step: 20) {
                        pair.base.view()
                        pair.placed.view()
                    }
                    .frame(height: RuleMiniCard.height + 20)
                    RuleVerdictMark(pair.isOK)
                }
            }
        }
    }
}

/// 「選ぶ → 置く」の 2 コマ図。左は札を選んだところ（持ち上がって枠が付く）、右は置き先の列に重なったところ。
public struct RuleSelectPlaceFigure: View {
    private let moving: RuleCardSpec
    private let target: RuleCardSpec

    public init(moving: RuleCardSpec, target: RuleCardSpec) {
        self.moving = moving
        self.target = target
    }

    public var body: some View {
        RuleFrames(count: 2, spacing: 14) { index in
            VStack(spacing: 4) {
                if index == 0 {
                    HStack(spacing: 18) {
                        VStack(spacing: 4) {
                            moving.view(highlighted: true)
                            RuleFigureLabel(tr("① 選ぶ"), color: Theme.coralText)
                        }
                        VStack(spacing: 4) {
                            target.view()
                            RuleFigureLabel(tr("② 置き先"))
                        }
                    }
                } else {
                    VStack(spacing: 4) {
                        RuleMiniCardColumn(step: 20) {
                            target.view()
                            moving.view()
                        }
                        .frame(height: RuleMiniCard.height + 20)
                        RuleFigureLabel(tr("置けた"))
                    }
                }
            }
        }
    }
}

/// 空いた列に置ける札を見せる図。
public struct RuleEmptyColumnFigure: View {
    private let card: RuleCardSpec
    private let caption: String

    public init(card: RuleCardSpec, caption: String) {
        self.card = card
        self.caption = caption
    }

    public var body: some View {
        RuleFrames(count: 2, spacing: 14) { index in
            VStack(spacing: 4) {
                if index == 0 {
                    HStack(spacing: 18) {
                        card.view(highlighted: true)
                        RuleMiniSlot(tr("空"))
                    }
                } else {
                    card.view()
                }
                RuleFigureLabel(index == 0 ? tr("空いた列") : caption)
            }
        }
    }
}

/// 組札の図。A から K へ同じスートで積み上げる。
public struct RuleFoundationFigure: View {
    private let suits: [RuleMiniCard.Suit]

    public init(suits: [RuleMiniCard.Suit] = [.spade, .heart, .diamond, .club]) {
        self.suits = suits
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(["A", "2", "3"], id: \.self) { rank in
                    RuleMiniCard(rank, suit: .spade)
                }
                Text("…")
                    .scaledFont(16, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.inkSubText)
                RuleMiniCard("K", suit: .spade)
            }
            HStack(spacing: 6) {
                ForEach(suits, id: \.rawValue) { suit in
                    Text(suit.rawValue)
                        .scaledFont(20, weight: .black, maxScale: 1.15)
                        .foregroundStyle(suit == .heart || suit == .diamond ? Color(hex: 0xC0392B) : Color(hex: 0x1A1A1A))
                }
                RuleFigureLabel(tr("4 つのスートぶん"))
            }
        }
    }
}
