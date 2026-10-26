import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2826）のおじさんの盆栽。
///
/// 盆栽の絵は本番と同じ `BonsaiIcon`、動かす・落とす・合体・並び・点線の図は遊び方の図（`FruitsHowToFigures`）の
/// 部品を使い回す（SpriteKit の盤は図に使わない）。合体の図は `FruitsHowToFigures.merge`、出てくる盆栽の図は
/// `FruitKind.dropPool` をそのまま描く。`FruitsOnboardingTests` が同じ定数を `FruitField` / `FruitsModel` に通し、
/// 合体・出てくる段・点線の秒数・金の松の得点・コンティニューの回数が文言のとおりであることを確かめる。
@MainActor
enum FruitsOnboarding {
    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "fruits",
            title: tr("おじさんの盆栽のはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("同じ盆栽をくっつけて、立派に育てるゲームです。"),
                        tr("盆栽は 11 種類。いちばん立派なのは金の松です。"),
                    ],
                    figure: { AnyView(FruitsHowToFigures.LineupFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回でやること"),
                    lines: [
                        tr("指を左右に動かすと、縁側のおじさんが盆栽を持って付いてきます。"),
                        tr("指を離すと、その真下の庭へ盆栽が落ちます。"),
                    ],
                    figure: { AnyView(TurnFigure()) }
                ),
                OnboardingPage(
                    heading: tr("くっつけて育てる"),
                    lines: [
                        tr("同じ盆栽どうしが触れるとくっついて、1 つ立派な盆栽になります。"),
                        tr("違う盆栽どうしは、触れてもくっつきません。"),
                        tr("金の松どうしがくっつくと、2 つとも消えて 100 点です。"),
                    ],
                    figure: { AnyView(FruitsHowToFigures.MergeFigure()) }
                ),
                OnboardingPage(
                    heading: tr("出てくるのは小さい 5 種"),
                    lines: [
                        tr("落とす盆栽は、小さいほうの 5 種だけが出てきます。"),
                        tr("大きい盆栽は、くっつけて育てるしかありません。立派なほど高得点です。"),
                    ],
                    figure: { AnyView(PoolFigure()) }
                ),
                OnboardingPage(
                    heading: tr("ゲームオーバーの決まり"),
                    lines: [
                        tr("上の点線より上に盆栽が 3 秒以上とどまると、ゲームオーバーです。"),
                        tr("ゲームオーバーのあと、広告を見ると 1 回だけ続けられます。"),
                    ],
                    figure: { AnyView(FruitsHowToFigures.LimitFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 左右に動かす → 離すと真下に落ちる。
    private struct TurnFigure: View {
        var body: some View {
            VStack(spacing: 14) {
                FruitsHowToFigures.MoveFigure()
                FruitsHowToFigures.DropFigure()
            }
        }
    }

    /// 落とす盆栽として出てくる段（`FruitKind.dropPool`）。
    private struct PoolFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(FruitKind.dropPool, id: \.self) { kind in
                        FruitsHowToFigures.icon(kind, size: 36)
                    }
                }
                RuleFigureLabel(tr("落ちてくるのはこの 5 種"), color: Theme.coralText)
            }
        }
    }
}
