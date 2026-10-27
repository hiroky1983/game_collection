import Core
import MahjongTiles
import SwiftUI

/// 図で見る「はじめての遊び方」（#2825）の麻雀（四人打ち）。
///
/// 東風戦と一局戦で先頭の流れと末尾の連荘の説明が変わるので、「？」の遊び方と同じく対局の長さを受けて組む。
/// 和了の形・役の要否・立直・鳴き・流局の点棒・持ち点は `MahjongShanten` / `MahjongScoring` / `MahjongCallFinder` /
/// `MahjongModel` の実装どおりで、`MahjongOnboardingTests` が図の手牌で確かめる。図は遊び方の図
/// （`MahjongHowToFigures`）の部品を使い回し、牌は本番と同じ `MahjongTileView`。
/// 役の点数・七対子や国士無双・カンの細かい扱い・フリテンは「役の早見表」「くわしいルール」に任せ、ここでは触れない。
@MainActor
enum MahjongOnboarding {
    /// 順位の図の持ち点（合計は 4 人ぶんの持ち点 25000 × 4 = 100000）。
    static let exampleScores = [32000, 27000, 22000, 19000]

    static func guide(length: MahjongGameLength) -> OnboardingGuide {
        let isTonpuu = length == .tonpuu
        return OnboardingGuide(
            gameID: "mahjong4",
            title: tr("麻雀のはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        isTonpuu ? tr("CPU 3 人と対局します。東 1 局から東 4 局まで打ちます。")
                                 : tr("CPU 3 人と対局します。東 1 局だけを打ちます。"),
                        tr("最後に、持ち点が多い順に順位が決まります。"),
                    ],
                    figure: { AnyView(MahjongHowToFigures.FlowFigure(rounds: length.roundCount)) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("山から 1 枚引いて、手牌から 1 枚切ります。"),
                        tr("切る牌は、タップで選びます。"),
                    ],
                    figure: { AnyView(MahjongHowToFigures.DrawDiscardFigure()) }
                ),
                OnboardingPage(
                    heading: tr("和了（あがり）の形"),
                    lines: [
                        tr("同じ牌 3 枚か連番 3 枚を 4 組と、同じ牌 2 枚を 1 組そろえると和了です。"),
                        tr("自分で引いた牌での和了が「ツモ」、他の人の捨て牌での和了が「ロン」です。"),
                    ],
                    figure: { AnyView(MahjongHowToFigures.WinningShapeFigure()) }
                ),
                OnboardingPage(
                    heading: tr("役と立直"),
                    lines: [
                        tr("和了の形でも、役が 1 つも無いと和了できません。"),
                        tr("あと 1 枚で和了の「聴牌」になったら、立直を宣言すると役が付きます。"),
                        tr("立直は鳴いていない手だけ。1000 点を供託します。"),
                    ],
                    figure: { AnyView(MahjongHowToFigures.RiichiFigure()) }
                ),
                OnboardingPage(
                    heading: tr("鳴く"),
                    lines: [
                        tr("他の人の捨て牌は、ポン・チー・カンで取れます。"),
                        tr("ポンは誰の捨て牌でも。チーは左の人（上家）の捨て牌だけです。"),
                        tr("鳴くと、その組を手牌の外に出します。ポン・チーのあとは、そのまま 1 枚切ります。"),
                    ],
                    figure: { AnyView(MahjongHowToFigures.CallFigure()) }
                ),
                OnboardingPage(
                    heading: tr("流局と順位"),
                    lines: [
                        tr("山が尽きたら流局。聴牌していた人が、3000 点を分け合います。"),
                        isTonpuu ? tr("親が和了したり、聴牌で流局したりすると、同じ局を続けます（連荘）。")
                                 : tr("一局戦は、親が和了っても連荘せず、その局で終わります。"),
                        tr("最後に、持ち点が多い順に順位が決まります。"),
                    ],
                    figure: { AnyView(RankFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 持ち点の多い順に 1 位〜4 位。
    private struct RankFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                ForEach(Array(MahjongOnboarding.exampleScores.enumerated()), id: \.offset) { index, score in
                    HStack(spacing: 10) {
                        Text(tr("%lld位", index + 1))
                            .scaledFont(14, weight: .black, design: .rounded, maxScale: 1.15)
                            .foregroundStyle(index == 0 ? Theme.coralText : Theme.inkSubText)
                            .frame(width: 44, alignment: .leading)
                        Text(verbatim: "\(score)")
                            .scaledFont(16, weight: .black, design: .rounded, maxScale: 1.15)
                            .foregroundStyle(Theme.ink)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(index == 0 ? Theme.coral.opacity(0.15) : Theme.inkSub.opacity(0.08)))
                }
            }
        }
    }
}
