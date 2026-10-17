import Core
import SwiftUI

/// 図入りの遊び方（#2386）のルーレットの図。文言は `HowToPlayGuide.roulette.items`（Core）と同じ順。
/// ホイールとマスの色は本番と同じ部品（`RouletteWheelView.fill(for:)`）で塗る。
@MainActor
enum RouletteHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(BetFigure()) },
        { AnyView(SpinFigure()) },
        { AnyView(PayoutFigure()) },
        { AnyView(ZeroFigure()) },
    ]

    /// 賭けのマス 1 つ（数字・色など）。`staked` があれば右上にチップを置く。
    private static func cell(_ text: String, fill: Color, ink: Color, width: CGFloat,
                             staked: Int? = nil) -> some View {
        Text(text)
            .scaledFont(12, weight: .bold, design: .rounded, maxScale: 1.15)
            .foregroundStyle(ink)
            .lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: width, height: 28)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if let staked {
                    Text(verbatim: "\(staked)")
                        .scaledFont(9, weight: .black, design: .rounded, maxScale: 1.15)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.white))
                        .overlay(Capsule().strokeBorder(Theme.onAccent, lineWidth: 1))
                        .offset(x: 3, y: -5)
                }
            }
    }

    private static func numberCell(_ number: Int, staked: Int? = nil) -> some View {
        cell("\(number)", fill: RouletteWheelView.fill(for: number),
             ink: RouletteWheelView.textColor(for: number), width: 36, staked: staked)
    }

    /// チップの額を選び、マスをタップして置く。
    private struct BetFigure: View {
        var body: some View {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach([10, 50, 100], id: \.self) { amount in
                        let selected = amount == 50
                        Text(verbatim: "\(amount)")
                            .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(selected ? Theme.Fill.yellow : Theme.surface))
                            .overlay(Circle().strokeBorder(selected ? Theme.yellow : Theme.inkSub.opacity(0.5),
                                                           style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
                            .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
                    }
                }
                HStack(spacing: 8) {
                    RouletteHowToFigures.numberCell(7)
                    RouletteHowToFigures.numberCell(17, staked: 50)
                    RouletteHowToFigures.cell(tr("赤"), fill: Theme.Fill.coral, ink: Theme.onAccent, width: 52, staked: 50)
                    RouletteHowToFigures.cell(tr("黒"), fill: Theme.fillStrong, ink: .white, width: 52)
                }
                RuleFigureLabel(tr("額を選んで、マスをタップ"))
            }
        }
    }

    /// ホイールが回り、玉の真下で止まった数字が出目。
    private struct SpinFigure: View {
        var body: some View {
            HStack(spacing: 18) {
                RouletteWheelView(
                    rotation: -RouletteMotion.pocketAngle(index: RouletteWheel.pocketIndex(of: 17)), highlighted: nil)
                    .frame(width: 110, height: 110)
                Image(systemName: "arrow.right")
                    .scaledFont(12, weight: .black, maxScale: 1.2)
                    .foregroundStyle(Theme.inkSub)
                VStack(spacing: 4) {
                    RouletteHowToFigures.numberCell(17)
                    RuleFigureLabel(tr("玉の真下の数字が出目"))
                }
            }
        }
    }

    /// 配当の違い。
    private struct PayoutFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                entry(label: tr("数字1点")) { RouletteHowToFigures.numberCell(17) } payout: { tr("%lld倍", 35) }
                entry(label: tr("12個の区分")) {
                    RouletteHowToFigures.cell("1–12", fill: Theme.fillMuted, ink: Theme.ink, width: 52)
                } payout: { tr("%lld倍", 2) }
                entry(label: tr("赤黒など")) {
                    RouletteHowToFigures.cell(tr("赤"), fill: Theme.Fill.coral, ink: Theme.onAccent, width: 52)
                } payout: { tr("%lld倍", 1) }
            }
        }

        private func entry<Cell: View>(label: String, @ViewBuilder cell: () -> Cell,
                                       payout: () -> String) -> some View {
            VStack(spacing: 4) {
                cell()
                Text(payout())
                    .scaledFont(16, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.coralText)
                RuleFigureLabel(label)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 0（緑）が出ると、赤黒などの賭けはすべて外れ。
    private struct ZeroFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 4) {
                    RouletteHowToFigures.numberCell(0)
                    RuleFigureLabel(tr("0が出ると"))
                }
                Image(systemName: "arrow.right")
                    .scaledFont(12, weight: .black, maxScale: 1.2)
                    .foregroundStyle(Theme.inkSub)
                    .padding(.top, 6)
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        RouletteHowToFigures.cell(tr("赤"), fill: Theme.Fill.coral, ink: Theme.onAccent, width: 44)
                        RouletteHowToFigures.cell(tr("黒"), fill: Theme.fillStrong, ink: .white, width: 44)
                    }
                    HStack(spacing: 8) {
                        RuleVerdictMark(false).frame(width: 44)
                        RuleVerdictMark(false).frame(width: 44)
                    }
                    RuleFigureLabel(tr("すべて外れ"), color: Theme.coralText)
                }
            }
        }
    }
}
