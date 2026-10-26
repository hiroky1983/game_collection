import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2826）のチャリンコおじさん。
///
/// 「？」の遊び方（`RunnerMode.howToPlayGuide`）と同じく、モード（ステージ制／エンドレス）で先頭の目的と最後のミスの
/// カードだけを出し分ける。走り出し・ジャンプ・二段ジャンプは両モード共通。図は遊び方の図（`RunnerHowToFigures`）の
/// 部品をそのまま使い、走者は本番と同じドット絵。ジャンプの高さ・二段まで・ペダル・チェックポイントでの再開・
/// エンドレスの記録は `RunnerField` / `RunnerModel` の実装どおり（`RunnerOnboardingTests` が確かめる）。
@MainActor
enum RunnerOnboarding {
    static func guide(mode: RunnerMode) -> OnboardingGuide {
        let goal: OnboardingPage = switch mode {
        case .stages:
            OnboardingPage(
                heading: tr("このゲームの目的"),
                lines: [
                    tr("ゴールまで走れば、ステージクリアです。"),
                    tr("面を順にクリアして、先の世界へ進みます。"),
                ],
                figure: { AnyView(RunnerHowToFigures.StageGoalFigure()) }
            )
        case .endless:
            OnboardingPage(
                heading: tr("このゲームの目的"),
                lines: [
                    tr("毎回ちがうコースを、ミスするまで走ります。"),
                    tr("走った距離が記録です。"),
                ],
                figure: { AnyView(RunnerHowToFigures.EndlessFigure()) }
            )
        }
        let miss: OnboardingPage = switch mode {
        case .stages:
            OnboardingPage(
                heading: tr("勝ち負けの決まり"),
                lines: [
                    tr("ぶつかるか穴に落ちたらミス。何度でもステージの頭からやり直せます。"),
                    tr("青いチェックポイントより先でミスしたときは、広告を見てそこから再開することもできます。"),
                ],
                figure: { AnyView(RunnerHowToFigures.MissFigure(isEndless: false)) }
            )
        case .endless:
            OnboardingPage(
                heading: tr("勝ち負けの決まり"),
                lines: [
                    tr("ぶつかるか穴に落ちたらおしまいです。"),
                    tr("途中で閉じると、記録は残りません。"),
                ],
                figure: { AnyView(RunnerHowToFigures.MissFigure(isEndless: true)) }
            )
        }
        return OnboardingGuide(
            gameID: "runner",
            title: tr("チャリンコおじさんのはじめての遊び方"),
            pages: [
                goal,
                OnboardingPage(
                    heading: tr("走り出す"),
                    lines: [
                        tr("画面をタップすると、おじさんが走り出します。"),
                        tr("あとは自動で右へ進みます。"),
                    ],
                    figure: { AnyView(RunnerHowToFigures.StartFigure()) }
                ),
                OnboardingPage(
                    heading: tr("ジャンプ"),
                    lines: [
                        tr("タップでジャンプ。長く押すほど高く跳べます。"),
                        tr("穴や障害物を跳び越えます。"),
                    ],
                    figure: { AnyView(RunnerHowToFigures.JumpFigure()) }
                ),
                OnboardingPage(
                    heading: tr("二段ジャンプ"),
                    lines: [
                        tr("空中でもう一度タップすると、二段ジャンプできます。"),
                        tr("ペダルは地面でしか漕げないので、低く跳ぶほどスピードが乗ります。"),
                    ],
                    figure: { AnyView(RunnerHowToFigures.DoubleJumpFigure()) }
                ),
                miss,
            ]
        )
    }
}
