import Core
import CoreMiniBoard
import SwiftUI

/// 図入りの遊び方（#2044）の囲碁の図。文言は `HowToPlayGuide.go.items`（Core）と同じ順。
@MainActor
enum GoHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(PlaceFigure()) },
        { AnyView(CaptureFigure()) },
        { AnyView(TerritoryFigure()) },
    ]

    /// 交点に交互に石を置く。
    struct PlaceFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    RuleMiniBoard(rows: 5, cols: 5, cell: 22, style: .lines) { row, col in
                        ZStack {
                            if row == 2, col == 2 { RuleStone(.black, size: 22) }
                            if row == 1, col == 3 { RuleStone(.white, size: 22) }
                            if index == 0, row == 3, col == 1 { RuleBoardMark.ring(size: 18) }
                            if index == 1, row == 3, col == 1 { RuleStone(.black, size: 22) }
                        }
                    }
                    RuleFigureLabel(index == 0 ? tr("交点をタップ") : tr("石が置かれる"),
                                    color: index == 0 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// 白の石の最後の呼吸点を黒が埋めると、白が取り上げられる。
    struct CaptureFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    RuleMiniBoard(rows: 5, cols: 5, cell: 22, style: .lines) { row, col in
                        ZStack {
                            if (row == 1 && col == 2) || (row == 2 && (col == 1 || col == 3)) {
                                RuleStone(.black, size: 22)
                            }
                            if row == 2, col == 2, index == 0 { RuleStone(.white, size: 22) }
                            if row == 3, col == 2 {
                                if index == 0 { RuleBoardMark.ring(size: 18) } else { RuleStone(.black, size: 22) }
                            }
                        }
                    }
                    RuleFigureLabel(index == 0 ? tr("最後のすき間を埋める") : tr("白が取り上げられる"),
                                    color: index == 0 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// 囲んだ空点（地）の数と石の数で勝負する。
    struct TerritoryFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 5, cols: 7, cell: 20, style: .lines) { row, col in
                    ZStack {
                        if col == 2 { RuleStone(.black, size: 20) }
                        if col == 4 { RuleStone(.white, size: 20) }
                        if col < 2 { Rectangle().fill(Color.black).frame(width: 6, height: 6) }
                        if col > 4 { Rectangle().fill(Color.white).frame(width: 6, height: 6)
                            .overlay(Rectangle().stroke(Color.black.opacity(0.5), lineWidth: 0.5)) }
                    }
                }
                RuleFigureLabel(tr("石 ＋ 囲んだ地（■）の合計が多い方の勝ち"))
            }
        }
    }
}
