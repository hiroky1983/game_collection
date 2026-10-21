import Core
import SwiftUI

/// 図入りの遊び方（#2386）のおじさんの盆栽の図。文言は `HowToPlayGuide.fruits.items`（Core）と同じ順。
/// 盆栽の絵は本番と同じ `BonsaiIcon` で描く。
@MainActor
enum FruitsHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(MoveFigure()) },
        { AnyView(DropFigure()) },
        { AnyView(MergeFigure()) },
        { AnyView(LineupFigure()) },
        { AnyView(LimitFigure()) },
    ]

    private static func icon(_ kind: FruitKind, size: CGFloat = 44) -> some View {
        BonsaiIcon(kind).frame(width: size, height: size)
    }

    private static func arrow(_ name: String) -> some View {
        Image(systemName: name)
            .scaledFont(14, weight: .black, maxScale: 1.2)
            .foregroundStyle(Theme.coralText)
    }

    /// 指を左右に動かすと、盆栽を持ったおじさんが付いてくる。
    private struct MoveFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    FruitsHowToFigures.arrow("arrow.left")
                    FruitsHowToFigures.icon(.ume, size: 52)
                    FruitsHowToFigures.arrow("arrow.right")
                }
                RuleFigureLabel(tr("左右に動かす"))
            }
        }
    }

    /// 離すと、真下へ落ちる。
    private struct DropFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 20) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        FruitsHowToFigures.icon(.ume, size: 44)
                        RuleFigureLabel(tr("指を離す"))
                    } else {
                        VStack(spacing: 0) {
                            FruitsHowToFigures.arrow("arrow.down")
                            FruitsHowToFigures.icon(.ume, size: 44)
                        }
                        RuleFigureLabel(tr("真下に落ちる"), color: Theme.coralText)
                    }
                }
            }
        }
    }

    /// 同じ盆栽が 2 つ触れると、1 つ上の段の盆栽になる。
    private struct MergeFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 18) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        HStack(spacing: -4) {
                            FruitsHowToFigures.icon(.mikan)
                            FruitsHowToFigures.icon(.mikan)
                        }
                        RuleFigureLabel(tr("同じ盆栽が触れる"))
                    } else {
                        FruitsHowToFigures.icon(.icho, size: 52)
                        RuleFigureLabel(tr("1つ立派に"), color: Theme.coralText)
                    }
                }
            }
        }
    }

    /// 11 種類を小さい順に並べる。いちばん立派なのは金の松。
    private struct LineupFigure: View {
        var body: some View {
            RuleLineup(count: FruitKind.allCases.count, low: tr("小さい"), high: tr("金の松")) { index in
                BonsaiIcon(FruitKind.allCases[index])
                    .frame(height: 26)
            }
        }
    }

    /// 点線より上に盆栽がとどまると、ゲームオーバー。
    private struct LimitFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                        .strokeBorder(Theme.inkSub.opacity(0.6), lineWidth: 1.5)
                        .frame(width: 150, height: 86)
                    VStack(spacing: 0) {
                        FruitsHowToFigures.icon(.shinpaku, size: 30)
                            .padding(.top, 4)
                        Line()
                            .stroke(Theme.coralText, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(width: 150, height: 2)
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            FruitsHowToFigures.icon(.fuji, size: 32)
                            FruitsHowToFigures.icon(.nanten, size: 32)
                            FruitsHowToFigures.icon(.tsubaki, size: 32)
                        }
                    }
                    .frame(width: 150, height: 86)
                }
                RuleFigureLabel(tr("点線より上は危ない"), color: Theme.coralText)
            }
        }

        private struct Line: Shape {
            func path(in rect: CGRect) -> Path {
                var path = Path()
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                return path
            }
        }
    }
}
