import Core
import CoreMiniBoard
import SwiftUI

/// 図入りの遊び方（#2044）の四目並べの図。文言は `HowToPlayGuide.yonmoku.items`（Core）と同じ順。
///
/// 盤は本番と同じ色の小さな立てた盤（穴の並んだ板）で、石は図の共通部品 `RuleStone`（五目並べ・オセロと同じ）。
@MainActor
enum YonmokuHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(DropFigure()) },
        { AnyView(FourFigure()) },
        { AnyView(BlockFigure()) },
    ]

    /// 図の小さな盤。`disc(col, row)` の row は**下から**数える（本番の盤と同じ）。
    private struct MiniBoard: View {
        let cols: Int
        let rows: Int
        var cell: CGFloat = 20
        let disc: (Int, Int) -> RuleStone.Tone?
        var mark: (Int, Int) -> Bool = { _, _ in false }

        var body: some View {
            VStack(spacing: 0) {
                ForEach((0..<rows).reversed(), id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { col in
                            ZStack {
                                Circle().fill(Color(hex: YonmokuBoardStyle.hole)).frame(width: cell * 0.8, height: cell * 0.8)
                                if let tone = disc(col, row) { RuleStone(tone, size: cell) }
                                if mark(col, row) { RuleBoardMark.ring(size: cell * 0.9) }
                            }
                            .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .padding(cell * 0.2)
            .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                .fill(Color(hex: YonmokuBoardStyle.frame)))
        }
    }

    /// 列をタップすると、石が上から落ちて一番下の空きに入る。
    private struct DropFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    VStack(spacing: 2) {
                        Image(systemName: "arrowtriangle.down.fill")
                            .scaledFont(12, maxScale: 1.15)
                            .foregroundStyle(index == 0 ? Theme.coralText : Color.clear)
                            // 2 列目（左から）の真上に置く: 盤の中心から 1 マスぶん左。
                            .offset(x: -20)
                            .accessibilityHidden(true)
                        MiniBoard(cols: 4, rows: 4, disc: { col, row in
                            if col == 1, row == 0 { return .white }
                            if col == 2, row == 0 { return .black }
                            if index == 1, col == 1, row == 1 { return .black }
                            return nil
                        }, mark: { col, row in index == 0 && col == 1 && row == 1 })
                    }
                    RuleFigureLabel(index == 0 ? tr("列をタップ") : tr("一番下の空きに入る"),
                                    color: index == 0 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// たて・よこ・ななめに 4 つ。
    private struct FourFigure: View {
        var body: some View {
            HStack(spacing: 10) {
                line(tr("よこ")) { col, row in row == 0 }
                line(tr("たて")) { col, row in col == 1 }
                line(tr("ななめ")) { col, row in col == row }
            }
        }

        private func line(_ name: String, _ on: @escaping (Int, Int) -> Bool) -> some View {
            VStack(spacing: 4) {
                MiniBoard(cols: 4, rows: 4, cell: 15, disc: { col, row in
                    if on(col, row) { return .black }
                    // ななめは下の段を白で支える（宙に浮いた石は作れない）。
                    if name == tr("ななめ"), col > row { return .white }
                    return nil
                })
                RuleFigureLabel(name)
            }
        }
    }

    /// 相手が 3 つ並べたら、4 つ目の場所を先にふさぐ。
    private struct BlockFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    MiniBoard(cols: 5, rows: 2, disc: { col, row in
                        guard row == 0 else { return nil }
                        if (1...3).contains(col) { return .white }
                        if col == 4, index == 1 { return .black }
                        if col == 0 { return .black }
                        return nil
                    }, mark: { col, row in index == 0 && col == 4 && row == 0 })
                    RuleFigureLabel(index == 0 ? tr("白が 3 つ！ ここで 4 つ") : tr("黒で先にふさいだ"),
                                    color: index == 0 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }
}
