import Core
import SwiftUI

/// 図入りの遊び方（#2044）のマインスイーパーの図。文言は `HowToPlayGuide.minesweeper.items`（Core）と同じ順。
/// マスの色・数字の色は本番の盤（`MinesweeperView`）と同じ値で描く。
@MainActor
enum MinesweeperHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(NumberFigure()) },
        { AnyView(FlagFigure()) },
        { AnyView(ChordFigure()) },
        { AnyView(ClearFigure()) },
    ]

    /// 図の 1 マス。
    enum Cell {
        /// 開いていないマス。
        case closed
        /// 開いたマス（0 なら空白）。
        case open(Int)
        /// 旗。
        case flag
        /// 地雷（説明用に見せる）。
        case mine
    }

    private static let size: CGFloat = 26

    private struct CellView: View {
        let cell: Cell
        var highlighted = false

        var body: some View {
            ZStack {
                Rectangle().fill(fill)
                switch cell {
                case .open(let n) where n > 0:
                    Text(verbatim: "\(n)")
                        .font(.system(size: MinesweeperHowToFigures.size * 0.56, weight: .black, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                        .foregroundStyle(numberColor(n))
                case .flag:
                    Image(systemName: "flag.fill")
                        .resizable().scaledToFit()
                        .frame(width: MinesweeperHowToFigures.size * 0.52, height: MinesweeperHowToFigures.size * 0.52)
                        .foregroundStyle(Theme.coral)
                case .mine:
                    Image(systemName: "circle.fill")
                        .resizable().scaledToFit()
                        .frame(width: MinesweeperHowToFigures.size * 0.45, height: MinesweeperHowToFigures.size * 0.45)
                        .foregroundStyle(Color(hex: 0x2A2A2A))
                default:
                    EmptyView()
                }
                if highlighted {
                    Rectangle().strokeBorder(Theme.coral, lineWidth: 2.5)
                }
            }
            .frame(width: MinesweeperHowToFigures.size, height: MinesweeperHowToFigures.size)
        }

        private var fill: Color {
            switch cell {
            case .open, .mine: Color(hex: 0xD8D8D8)
            case .closed, .flag: Color(hex: 0xBDBDBD)
            }
        }

        private func numberColor(_ n: Int) -> Color {
            switch n {
            case 1: Color(hex: 0x1565C0)
            case 2: Color(hex: 0x2E7D32)
            default: Color(hex: 0xC62828)
            }
        }
    }

    /// マスを格子に並べる。`highlight` は (行, 列) の組。
    private struct Grid: View {
        let cells: [[Cell]]
        var highlight: Set<Int> = []

        var body: some View {
            VStack(spacing: 1) {
                ForEach(Array(cells.enumerated()), id: \.offset) { r, row in
                    HStack(spacing: 1) {
                        ForEach(Array(row.enumerated()), id: \.offset) { c, cell in
                            CellView(cell: cell, highlighted: highlight.contains(r * 10 + c))
                        }
                    }
                }
            }
            .padding(1)
            .background(Color(hex: 0x9E9E9E))
        }
    }

    /// 数字はまわり 8 マスにある地雷の数（まん中の 1 と、まわりの 1 つの地雷）。
    private struct NumberFigure: View {
        var body: some View {
            HStack(spacing: 16) {
                RuleFrames(count: 2, spacing: 10) { index in
                    Grid(cells: [
                        [.closed, .closed, .closed],
                        [.closed, index == 0 ? .closed : .open(1), .closed],
                        [.closed, .closed, .closed],
                    ], highlight: index == 0 ? [11] : [])
                }
                VStack(spacing: 4) {
                    Grid(cells: [
                        [.closed, .closed, .mine],
                        [.closed, .open(1), .closed],
                        [.closed, .closed, .closed],
                    ], highlight: [2])
                    RuleFigureLabel(tr("まわりに地雷が 1 つ"))
                }
            }
        }
    }

    /// 長押しで旗。
    private struct FlagFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 10) { index in
                    Grid(cells: [[.open(1), index == 0 ? .closed : .flag]], highlight: index == 0 ? [1] : [])
                }
                RuleFigureLabel(tr("長押しで旗"), color: Theme.coral)
            }
        }
    }

    /// 旗の数が数字と同じなら、数字をタップでまわりをまとめて開ける。
    private struct ChordFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 10) { index in
                    let opened = index == 1
                    Grid(cells: [
                        [.flag, opened ? .open(1) : .closed, opened ? .open(0) : .closed],
                        [opened ? .open(1) : .closed, .open(1), opened ? .open(0) : .closed],
                        [opened ? .open(0) : .closed, opened ? .open(0) : .closed, opened ? .open(0) : .closed],
                    ], highlight: index == 0 ? [11] : [])
                }
                RuleFigureLabel(tr("旗が 1 つ → 1 をタップ"), color: Theme.coral)
            }
        }
    }

    /// 地雷以外を全部開けたらクリア。
    private struct ClearFigure: View {
        var body: some View {
            HStack(spacing: 12) {
                Grid(cells: [
                    [.open(0), .open(1), .flag, .open(1)],
                    [.open(0), .open(1), .open(1), .open(1)],
                    [.open(0), .open(0), .open(0), .open(0)],
                ])
                Image(systemName: "checkmark.seal.fill")
                    .scaledFont(28, weight: .bold, maxScale: 1.15)
                    .foregroundStyle(Color(hex: 0x2E9D6B))
            }
        }
    }
}
