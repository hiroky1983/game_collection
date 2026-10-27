import Core
import CoreMiniBoard
import SwiftUI

/// 図入りの遊び方（#2386）のバックギャモンの図。文言は `HowToPlayGuide.backgammon.items`（Core）と同じ順。
/// 盤全体ではなく、説明に要るポイントだけを抜き出した小さな帯で描く。色は本番の盤（`BackgammonBoardStyle`）に揃える。
@MainActor
enum BackgammonHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(DiceFigure()) },
        { AnyView(TapFigure()) },
        { AnyView(BlockedFigure()) },
        { AnyView(HitFigure()) },
        { AnyView(BearOffFigure()) },
    ]

    // MARK: - 部品

    private static let pointWidth: CGFloat = 26
    private static let pointHeight: CGFloat = 60
    private static let checkerSize: CGFloat = 20

    /// 帯の中の 1 ポイント。
    private struct Slot {
        var side: BackgammonSide? = nil
        var count: Int = 0
        /// 動かす駒（黄の輪）。
        var isSelected = false
        /// 行き先（青緑の輪）。
        var isTarget = false
        /// 止まれない印（✕）。
        var isBlocked = false
    }

    private struct PointShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.closeSubpath()
            return path
        }
    }

    private struct Checker: View {
        let side: BackgammonSide
        var isSelected = false

        var body: some View {
            Circle()
                .fill(Color(hex: side == .white ? BackgammonBoardStyle.whiteFace : BackgammonBoardStyle.blackFace))
                .overlay(Circle().stroke(Color.black.opacity(side == .white ? 0.25 : 0.6), lineWidth: 1))
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color(hex: BackgammonBoardStyle.selected), lineWidth: 2.5).padding(-2)
                    }
                }
                .frame(width: BackgammonHowToFigures.checkerSize, height: BackgammonHowToFigures.checkerSize)
        }
    }

    /// ポイントを横に並べた帯。
    private struct Strip: View {
        let slots: [Slot]

        var body: some View {
            HStack(spacing: 0) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                    ZStack(alignment: .bottom) {
                        PointShape()
                            .fill(Color(hex: index.isMultiple(of: 2)
                                        ? BackgammonBoardStyle.pointDark : BackgammonBoardStyle.pointLight))
                        VStack(spacing: -2) {
                            if slot.isBlocked { RuleBoardMark.cross() }
                            if slot.isTarget {
                                Circle()
                                    .strokeBorder(Color(hex: BackgammonBoardStyle.hint),
                                                  style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                                    .frame(width: BackgammonHowToFigures.checkerSize,
                                           height: BackgammonHowToFigures.checkerSize)
                            }
                            if let side = slot.side {
                                ForEach(0..<slot.count, id: \.self) { n in
                                    Checker(side: side, isSelected: slot.isSelected && n == 0)
                                }
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    .frame(width: BackgammonHowToFigures.pointWidth, height: BackgammonHowToFigures.pointHeight,
                           alignment: .bottom)
                }
            }
            .padding(3)
            .background(Color(hex: BackgammonBoardStyle.field),
                        in: RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous))
        }
    }

    private static func strip(_ slots: [Slot]) -> some View { Strip(slots: slots) }

    // MARK: - 図

    /// 出た目のぶん進む。目が 3 なら 3 つ先のポイントへ。
    private struct DiceFigure: View {
        var body: some View {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    BackgammonDieFace(value: 3, isUsed: false).frame(width: 30, height: 30)
                    BackgammonDieFace(value: 5, isUsed: false).frame(width: 30, height: 30)
                }
                VStack(spacing: 4) {
                    BackgammonHowToFigures.strip([
                        Slot(side: .white, count: 2, isSelected: true), Slot(), Slot(), Slot(isTarget: true),
                    ])
                    RuleFigureLabel(tr("3の目なら3つ先へ"))
                }
            }
        }
    }

    /// 動かす駒 → 行き先の順にタップ。
    private struct TapFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        BackgammonHowToFigures.strip([
                            Slot(side: .white, count: 2, isSelected: true), Slot(), Slot(isTarget: true),
                        ])
                        RuleFigureLabel(tr("駒 → 行き先"))
                    } else {
                        BackgammonHowToFigures.strip([
                            Slot(side: .white, count: 1), Slot(), Slot(side: .white, count: 1),
                        ])
                        RuleFigureLabel(tr("移動"), color: Theme.coralText)
                    }
                }
            }
        }
    }

    /// 相手の駒が 2 個以上あるポイントには止まれない。
    private struct BlockedFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                BackgammonHowToFigures.strip([
                    Slot(side: .white, count: 1, isSelected: true), Slot(side: .black, count: 2, isBlocked: true),
                    Slot(),
                ])
                RuleFigureLabel(tr("相手が2個以上 → 止まれない"), color: Theme.coralText)
            }
        }
    }

    /// 相手の駒が 1 個だけなら、叩いてバーへ送れる。
    private struct HitFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        if index == 0 {
                            BackgammonHowToFigures.strip([
                                Slot(side: .white, count: 1, isSelected: true), Slot(side: .black, count: 1),
                            ])
                            bar(black: 0)
                        } else {
                            BackgammonHowToFigures.strip([
                                Slot(), Slot(side: .white, count: 1),
                            ])
                            bar(black: 1)
                        }
                    }
                    RuleFigureLabel(index == 0 ? tr("1個だけの駒") : tr("バーへ送る"),
                                    color: index == 0 ? Theme.inkSubText : Theme.coralText)
                }
            }
        }

        private func bar(black: Int) -> some View {
            VStack(spacing: 2) {
                Text(tr("バー"))
                    .scaledFont(10, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Color.white)
                ForEach(0..<black, id: \.self) { _ in Checker(side: .black) }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .frame(width: 30, height: BackgammonHowToFigures.pointHeight + 6)
            .background(Color(hex: BackgammonBoardStyle.frame),
                        in: RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous))
        }
    }

    /// 自陣の 6 ポイントに 15 個そろったら、置き場へあがる。
    private struct BearOffFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    BackgammonHowToFigures.strip([
                        Slot(side: .white, count: 3), Slot(side: .white, count: 3), Slot(side: .white, count: 2),
                        Slot(side: .white, count: 3), Slot(side: .white, count: 2), Slot(side: .white, count: 2),
                    ])
                    Image(systemName: "arrow.right")
                        .scaledFont(12, weight: .black, maxScale: 1.2)
                        .foregroundStyle(Theme.inkSubText)
                    VStack(spacing: 2) {
                        Text(tr("あがり"))
                            .scaledFont(10, weight: .black, design: .rounded, maxScale: 1.15)
                            .foregroundStyle(Color.white)
                        Spacer(minLength: 0)
                        Checker(side: .white)
                    }
                    .padding(.vertical, 3)
                    .frame(width: 36, height: BackgammonHowToFigures.pointHeight + 6)
                    .background(Color(hex: BackgammonBoardStyle.frame),
                                in: RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous))
                }
                RuleFigureLabel(tr("15個そろったら置き場へ"))
            }
        }
    }
}
