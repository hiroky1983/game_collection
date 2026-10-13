import Core
import SwiftUI

/// 図入りの遊び方（#2044）のナンプレの図。文言は `HowToPlayGuide.sudoku.items`（Core）と同じ順。
/// 盤は図用の小さな 9×9（数字の配置は図のためのもので、実際の問題ではない）。
@MainActor
enum SudokuHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(InputFigure()) },
        { AnyView(RuleFigure()) },
        { AnyView(ClearFigure()) },
    ]

    /// 完成した盤（図の数字はここから取る）。
    private static let solved: [[Int]] = [
        [5, 3, 4, 6, 7, 8, 9, 1, 2],
        [6, 7, 2, 1, 9, 5, 3, 4, 8],
        [1, 9, 8, 3, 4, 2, 5, 6, 7],
        [8, 5, 9, 7, 6, 1, 4, 2, 3],
        [4, 2, 6, 8, 5, 3, 7, 9, 1],
        [7, 1, 3, 9, 2, 4, 8, 5, 6],
        [9, 6, 1, 5, 3, 7, 2, 8, 4],
        [2, 8, 7, 4, 1, 9, 6, 3, 5],
        [3, 4, 5, 2, 8, 6, 1, 7, 9],
    ]

    /// 9×9 の盤。`shows(r, c)` が false のマスは空き。`tint(r, c)` で背景に色を付ける。
    private struct Board: View {
        var cell: CGFloat = 16
        let shows: (Int, Int) -> Bool
        var tint: (Int, Int) -> Color? = { _, _ in nil }
        var selected: (Int, Int)? = nil

        var body: some View {
            VStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<9, id: \.self) { c in
                            ZStack {
                                Rectangle().fill(tint(r, c) ?? Color.white)
                                if shows(r, c) {
                                    Text(verbatim: "\(SudokuHowToFigures.solved[r][c])")
                                        .font(.system(size: cell * 0.62, weight: .bold, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                                        .foregroundStyle(Color(hex: 0x2A2A2A))
                                }
                                if let selected, selected == (r, c) {
                                    Rectangle().strokeBorder(Theme.coral, lineWidth: 2)
                                }
                            }
                            .frame(width: cell, height: cell)
                            .overlay(Rectangle().stroke(Color.gray.opacity(0.35), lineWidth: 0.5))
                        }
                    }
                }
            }
            .overlay(boxLines)
            .overlay(Rectangle().stroke(Color(hex: 0x2A2A2A), lineWidth: 2))
        }

        /// 3×3 の区切りの太線。
        private var boxLines: some View {
            ZStack {
                ForEach([3, 6], id: \.self) { i in
                    Rectangle().fill(Color(hex: 0x2A2A2A))
                        .frame(width: 1.5, height: cell * 9)
                        .offset(x: cell * CGFloat(i) - cell * 4.5)
                    Rectangle().fill(Color(hex: 0x2A2A2A))
                        .frame(width: cell * 9, height: 1.5)
                        .offset(y: cell * CGFloat(i) - cell * 4.5)
                }
            }
        }
    }

    /// 問題として見せる配置（およそ半分を空ける）。
    private static func given(_ r: Int, _ c: Int) -> Bool { (r * 7 + c * 5) % 9 < 5 }

    /// マスを選んで、数字パッドで入れる。
    private struct InputFigure: View {
        var body: some View {
            VStack(spacing: 8) {
                Board(shows: { r, c in SudokuHowToFigures.given(r, c) }, selected: (4, 4))
                HStack(spacing: 3) {
                    ForEach(1...9, id: \.self) { n in
                        Text(verbatim: "\(n)")
                            .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                            .foregroundStyle(n == 5 ? Theme.onAccent : Theme.ink)
                            .frame(width: 22, height: 26)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 3, style: .continuous)
                                .fill(n == 5 ? Theme.Fill.coral : Theme.inkSub.opacity(0.15)))
                    }
                }
                RuleFigureLabel(tr("マスを選んで数字をタップ"), color: Theme.coral)
            }
        }
    }

    /// たての列・よこの行・3×3 のどれにも、同じ数字は 1 つまで（5 の入る場所で見せる）。
    private struct RuleFigure: View {
        var body: some View {
            HStack(spacing: 10) {
                part(tr("よこの行")) { r, _ in r == 4 }
                part(tr("たての列")) { _, c in c == 4 }
                part(tr("3×3")) { r, c in (3..<6).contains(r) && (3..<6).contains(c) }
            }
        }

        private func part(_ name: String, _ on: @escaping (Int, Int) -> Bool) -> some View {
            VStack(spacing: 4) {
                Board(cell: 9, shows: { r, c in on(r, c) }, tint: { r, c in on(r, c) ? Theme.teal.opacity(0.2) : nil })
                RuleFigureLabel(name)
            }
        }
    }

    /// 全部埋めたらクリア。
    private struct ClearFigure: View {
        var body: some View {
            HStack(spacing: 12) {
                Board(cell: 13, shows: { _, _ in true })
                Image(systemName: "checkmark.seal.fill")
                    .scaledFont(28, weight: .bold, maxScale: 1.15)
                    .foregroundStyle(Color(hex: 0x2E9D6B))
            }
        }
    }
}
