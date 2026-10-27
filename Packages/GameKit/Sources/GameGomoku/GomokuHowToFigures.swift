import Core
import CoreMiniBoard
import SwiftUI

/// 図入りの遊び方（#2044）の五目並べの図。文言は `HowToPlayGuide.gomoku.items` /
/// `.gomokuRenju.items`（Core）と同じ順で、先頭 2 項目は共通。
@MainActor
enum GomokuHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = common + [
        { AnyView(BlockFigure()) },
    ]

    /// 禁じ手あり（連珠ルール）の版。
    static let renjuItems: [@MainActor @Sendable () -> AnyView] = common + [
        { AnyView(DoubleThreeFigure()) },
    ]

    /// 禁じ手の有無に合わせた遊び方（開始シートと「？」で共有する）。
    static func guide(forbiddenMoves: Bool) -> HowToPlayGuide {
        forbiddenMoves
            ? HowToPlayGuide.gomokuRenju.illustrated(renjuItems)
            : HowToPlayGuide.gomoku.illustrated(items)
    }

    private static let common: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(PlaceFigure()) },
        { AnyView(FiveFigure()) },
    ]

    /// 交互に石を置く。
    struct PlaceFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    RuleMiniBoard(rows: 5, cols: 5, cell: 22, style: .lines) { row, col in
                        ZStack {
                            if row == 2, col == 2 { RuleStone(.black, size: 22) }
                            if row == 2, col == 3 { RuleStone(.white, size: 22) }
                            if index == 0, row == 3, col == 2 { RuleBoardMark.ring(size: 18) }
                            if index == 1, row == 3, col == 2 { RuleStone(.black, size: 22) }
                        }
                    }
                    RuleFigureLabel(index == 0 ? tr("空いた所をタップ") : tr("石が置かれる"),
                                    color: index == 0 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// たて・よこ・ななめに 5 つ。
    struct FiveFigure: View {
        var body: some View {
            HStack(spacing: 10) {
                line(tr("よこ")) { row, col in row == 2 }
                line(tr("たて")) { row, col in col == 2 }
                line(tr("ななめ")) { row, col in col == row }
            }
        }

        private func line(_ name: String, _ on: @escaping (Int, Int) -> Bool) -> some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 5, cols: 5, cell: 17, style: .lines) { row, col in
                    if on(row, col) { RuleStone(.black, size: 17) }
                }
                RuleFigureLabel(name)
            }
        }
    }

    /// 4 つ並んだら、あいている端を止める。
    struct BlockFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    RuleMiniBoard(rows: 1, cols: 7, cell: 20, style: .lines) { _, col in
                        ZStack {
                            if col == 0 { RuleStone(.white, size: 20) }
                            if (1...4).contains(col) { RuleStone(.black, size: 20) }
                            if col == 5 {
                                if index == 0 { RuleBoardMark.ring(size: 16) } else { RuleStone(.white, size: 20) }
                            }
                        }
                    }
                    RuleFigureLabel(index == 0 ? tr("4 つ並んだ！ ここをあけると 5 つ") : tr("白で止めた"),
                                    color: index == 0 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// 三三: 1 手で「あと 1 つで 3 つ並ぶ列」が 2 本できる場所は、黒は打てない。
    struct DoubleThreeFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 7, cols: 7, cell: 18, style: .lines) { row, col in
                    ZStack {
                        if (row == 3 && (col == 1 || col == 2)) || (col == 3 && (row == 1 || row == 2)) {
                            RuleStone(.black, size: 18)
                        }
                        if row == 3, col == 3 { RuleBoardMark.cross() }
                    }
                }
                RuleFigureLabel(tr("黒は ✕ に打てない（三三）"), color: Theme.coralText)
            }
        }
    }
}
