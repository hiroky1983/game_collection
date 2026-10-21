import Core
import SwiftUI

/// 図入りの遊び方（#2044）の線つなぎ（#2235）の図。文言は `HowToPlayGuide.tsunagi.items`（Core）と同じ順。
/// 盤は本番と同じ `TsunagiBoardCanvas` で、3×3 の小さな問題を描く。
@MainActor
enum TsunagiHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(ConnectFigure()) },
        { AnyView(CutFigure()) },
        { AnyView(ClearFigure()) },
    ]

    private static let cellSide: CGFloat = 26

    /// 1 は左上 → 中央、2 は中段の左 → 右下。解は 1: 0-1-2-5-4、2: 3-6-7-8 の 1 通りだけ
    /// （`TsunagiModuleTests` が数え上げで確かめる）。
    static let sample = TsunagiPuzzle(
        side: 3,
        endpoints: [[0, 4], [3, 8]],
        solution: [[0, 1, 2, 5, 4], [3, 6, 7, 8]]
    )

    /// 図の 1 コマ。
    private struct Board: View {
        let paths: [[Int]]
        var body: some View {
            TsunagiBoardCanvas(puzzle: TsunagiHowToFigures.sample, paths: paths, cellSide: TsunagiHowToFigures.cellSide)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous).fill(Theme.surface))
        }
    }

    /// 点だけの盤 → 1 をなぞってつないだ盤。
    private struct ConnectFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 10) { index in
                    Board(paths: index == 0 ? [[], []] : [TsunagiHowToFigures.sample.solution[0], []])
                }
                RuleFigureLabel(tr("点からなぞる"), color: Theme.coralText)
            }
        }
    }

    /// 1 の線の上を 2 でなぞる → 1 の線がそこで切れる。
    private struct CutFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 10) { index in
                    Board(paths: index == 0 ? [[0, 1, 2, 5], []] : [[0, 1, 2], [8, 5]])
                }
                RuleFigureLabel(tr("触れた線は切れる"), color: Theme.coralText)
            }
        }
    }

    /// 全部つながって、全マスが埋まった盤。
    private struct ClearFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                Board(paths: TsunagiHowToFigures.sample.solution)
                RuleFigureLabel(tr("全マスを埋めたらクリア"), color: Theme.coralText)
            }
        }
    }
}

extension TsunagiBoardCanvas {
    /// 持ち主を線から求めて描く（遊び方の図用）。
    init(puzzle: TsunagiPuzzle, paths: [[Int]], cellSide: CGFloat) {
        var owners: [Int?] = Array(repeating: nil, count: puzzle.cellCount)
        for (k, ends) in puzzle.endpoints.enumerated() { for cell in ends { owners[cell] = k } }
        for (k, path) in paths.enumerated() { for cell in path { owners[cell] = k } }
        self.init(puzzle: puzzle, paths: paths, owners: owners, cellSide: cellSide)
    }
}
