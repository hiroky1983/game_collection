import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2827）の花札こいこい。
///
/// 文言は実装のルールと食い違わないよう、役の名前と文数は `HanafudaYaku`、倍率の境目は
/// `HanafudaScoring`、札の種類は `HanafudaKind` から引く（`HanafudaOnboardingTests` が突き合わせる）。
/// 図は本番と同じ札（`HanafudaCardFace`）で、遊び方の図（`HanafudaHowToFigures`）の部品を使い回す。
@MainActor
public enum HanafudaOnboarding {
    /// 図の「主な役」に並べる役と、その札。札の番号は `HanafudaCard` の表のとおり。
    static let sampleYaku: [(yaku: HanafudaYaku, cardIDs: [Int])] = [
        (.inoshikacho, [HanafudaCard.boarID, HanafudaCard.deerID, HanafudaCard.butterflyID]),
        (.akatan, [1, 5, 9]),
        (.sanko, [0, HanafudaCard.curtainID, HanafudaCard.moonID]),
    ]

    /// 図の「札の種類」に並べる札（光・タネ・短冊・カスの順）。
    static let sampleKinds: [(kind: HanafudaKind, cardID: Int)] = [
        (.hikari, 0), (.tane, 4), (.tanzaku, 1), (.kasu, 2),
    ]

    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: HanafudaModel.gameID,
            title: tr("花札こいこいのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("同じ月の札を取って、役を作るゲームです。"),
                        tr("役ができたら、あがって得点を決めます。"),
                    ],
                    figure: { AnyView(GoalFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("手札を 1 枚出して、場の同じ月の札を取ります。"),
                        tr("次に山札を 1 枚めくって、同じように取ります。"),
                        tr("合う札が無いときは、場に置きます。"),
                    ],
                    figure: { AnyView(TurnFigure()) }
                ),
                OnboardingPage(
                    heading: tr("札の種類"),
                    lines: [
                        tr("札は 12 か月が 4 枚ずつ、全部で 48 枚。"),
                        tr("光・タネ・短冊・カスの 4 種類があります。"),
                        tr("札の上の帯に、月と種類が出ています。"),
                    ],
                    figure: { AnyView(KindsFigure()) }
                ),
                OnboardingPage(
                    heading: tr("主な役"),
                    lines: [
                        tr("決まった札をそろえると役ができます。"),
                        tr("猪鹿蝶・赤短・三光は、どれも %lld 文です。", HanafudaYaku.inoshikacho.basePoints),
                        tr("役の一覧は、画面上の「役の早見表」で見られます。"),
                    ],
                    figure: { AnyView(YakuListFigure()) }
                ),
                OnboardingPage(
                    heading: tr("あがるか、こいこいか"),
                    lines: [
                        tr("役ができたら「あがり」で得点が決まります。"),
                        tr("「こいこい」を選ぶと、続けて役を伸ばせます。"),
                        tr("こいこいのあとに相手があがると、相手の得点が 2 倍です。"),
                    ],
                    figure: { AnyView(HanafudaHowToFigures.YakuFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("全部の局が終わって、文の合計が多いほうの勝ちです。"),
                        tr("1 回の得点が 7 文以上だと、その局は 2 倍です。"),
                        tr("だれもあがれずに手札が尽きたら、その局は 0 文です。"),
                    ],
                    figure: { AnyView(ScoreFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 同じ月の札を取る → 役ができる。
    private struct GoalFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 16) { index in
                VStack(spacing: 4) {
                    HStack(spacing: index == 0 ? -12 : 4) {
                        ForEach(index == 0 ? [0, 2] : [24, 36, 20], id: \.self) { id in
                            HanafudaHowToFigures.card(id)
                        }
                    }
                    RuleFigureLabel(index == 0 ? tr("同じ月を取る") : tr("役ができる"), color: Theme.coralText)
                }
            }
        }
    }

    /// 手札から出す → 山札をめくる、を縦に並べる。
    private struct TurnFigure: View {
        var body: some View {
            VStack(spacing: 14) {
                HanafudaHowToFigures.MatchFigure()
                HanafudaHowToFigures.DrawFigure()
            }
        }
    }

    /// 光・タネ・短冊・カスの札を 1 枚ずつ。
    private struct KindsFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                ForEach(HanafudaOnboarding.sampleKinds, id: \.kind) { entry in
                    VStack(spacing: 4) {
                        HanafudaHowToFigures.card(entry.cardID, width: 44)
                        RuleFigureLabel(entry.kind.label)
                    }
                }
            }
        }
    }

    /// 主な役の札と文数。
    private struct YakuListFigure: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(HanafudaOnboarding.sampleYaku, id: \.yaku) { entry in
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            ForEach(entry.cardIDs, id: \.self) { id in
                                HanafudaHowToFigures.card(id)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.yaku.shortName)
                                .scaledFont(14, weight: .black, design: .rounded, maxScale: 1.15)
                                .foregroundStyle(Theme.ink)
                            RuleFigureLabel(tr("%lld文", entry.yaku.basePoints), color: Theme.coralText)
                        }
                    }
                }
            }
        }
    }

    /// 合計の文数を比べる。
    private struct ScoreFigure: View {
        var body: some View {
            HStack(spacing: 16) {
                score(tr("あなた"), points: 14, wins: true)
                score(tr("CPU"), points: 9, wins: false)
            }
        }

        private func score(_ name: String, points: Int, wins: Bool) -> some View {
            VStack(spacing: 6) {
                Image(systemName: wins ? "crown.fill" : "minus")
                    .scaledFont(16, weight: .bold, maxScale: 1.15)
                    .foregroundStyle(wins ? Theme.coralText : Theme.inkSubText)
                Text(tr("%lld文", points))
                    .scaledFont(22, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(wins ? Theme.onAccent : Theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(wins ? Theme.Fill.coral : Theme.surface))
                RuleFigureLabel(wins ? tr("%@（勝ち）", name) : name, color: wins ? Theme.coralText : Theme.inkSubText)
            }
        }
    }
}
