import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2826）のブロック崩し。
///
/// 図は遊び方の図（`BlocksHowToFigures`）の 2D の部品を使い回す（SpriteKit の盤は図に使わない）。
/// ブロックの種類の図は `kinds` の並びを、本番と同じ配色（`BlocksPalette`）と耐久（`BlockKind.hitPoints`）で描く。
/// `BlocksOnboardingTests` が同じ定数を `BlocksField` / `BlocksModel` に通し、何回で壊れるか・アイテムの効果・
/// ミスの数え方・ステージ数が文言のとおりであることを確かめる。金庫の壁（#1250）・フレンジー（#1202）は
/// 遊び方（`HowToPlayGuide.blocks`）にも書いていないので、ここでも書かない。
@MainActor
enum BlocksOnboarding {
    /// ブロックの種類の図に並べる種類（左から）。
    static let kinds: [BlockKind] = [.normal, .hard, .solid]

    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "blocks",
            title: tr("ブロック崩しのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("パドルで球をはね返して、ブロックに当てて壊すゲームです。"),
                        tr("壊せるブロックを全部消すと、次のステージへ進みます。"),
                    ],
                    figure: { AnyView(BlocksHowToFigures.BounceFigure()) }
                ),
                OnboardingPage(
                    heading: tr("パドルの動かし方"),
                    lines: [
                        tr("指を横に動かした分だけパドルが動きます。タップで球が飛び出します。"),
                        tr("指は盤の上でも盤の下の空いた場所でもよく、パドルに重ねなくて大丈夫です。"),
                    ],
                    figure: { AnyView(BlocksHowToFigures.PaddleFigure()) }
                ),
                OnboardingPage(
                    heading: tr("ブロックの種類"),
                    lines: [
                        tr("ふつうのブロックは 1 回、硬いブロックは 2 回当てると壊れます。"),
                        tr("灰色のブロックは壊れません。残っていてもステージクリアできます。"),
                    ],
                    figure: { AnyView(KindsFigure()) }
                ),
                OnboardingPage(
                    heading: tr("アイテム"),
                    lines: [
                        tr("落ちてくるアイテムをパドルで受けると、パドルが伸びたり球が増えたりします。"),
                        tr("パドルが伸びるのは 12 秒だけ。球は 3 個まで増えます。"),
                    ],
                    figure: { AnyView(BlocksHowToFigures.ItemFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("盤の球をすべて落とすと 1 ミス。3 回ミスで終わりです。"),
                        tr("球が増えているときは、全部落ちるまでミスになりません。"),
                        tr("全 12 ステージをクリアしたら、あなたの勝ちです。"),
                    ],
                    figure: { AnyView(BlocksHowToFigures.MissFigure()) }
                ),
            ]
        )
    }

    /// 種類ごとの札の文言（耐久から作る）。
    static func label(for kind: BlockKind) -> String {
        kind.hitPoints.map { tr("%lld 回で壊れる", $0) } ?? tr("壊れない")
    }

    /// 本番の配色で描くブロックの色（硬いブロックは無傷の色）。
    static func colorHex(for kind: BlockKind) -> UInt32 {
        switch kind {
        case .normal: return BlocksPalette.normalRows[0]
        case .hard: return BlocksPalette.hardFull
        case .solid: return BlocksPalette.solid
        case .vaultWall: return BlocksPalette.vaultWall
        }
    }

    // MARK: - 図

    /// ふつう（1 回）・硬い（2 回）・壊れない、を本番の盤の色で並べる。
    private struct KindsFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                ForEach(BlocksOnboarding.kinds, id: \.self) { kind in
                    VStack(spacing: 6) {
                        BlocksHowToFigures.Brick(color: Color(hex: BlocksOnboarding.colorHex(for: kind)))
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                                .fill(Color(hex: BlocksPalette.field)))
                        RuleFigureLabel(BlocksOnboarding.label(for: kind),
                                        color: kind.hitPoints == nil ? Theme.coralText : Theme.inkSubText)
                    }
                }
            }
        }
    }
}
