import Core
import SwiftUI

/// 図入りの遊び方（#2044）のおじさんの飼い猫パズル（#2250）の図。文言は `HowToPlayGuide.catPuzzle.items`（Core）と同じ順。
/// 盤は本番と同じ `CatPuzzleBoardCanvas` で、4×4 の小さな問題を描く。
@MainActor
enum CatPuzzleHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(OnePerRoomFigure()) },
        { AnyView(NotAdjacentFigure()) },
        { AnyView(TapCycleFigure()) },
    ]

    private static let cellSide: CGFloat = 28

    /// 4×4・部屋 4 つ。答えは行の順に列 1・3・0・2 の 1 通りだけ（`CatPuzzleModuleTests` が数え上げで確かめる）。
    static let sample = CatPuzzle(
        side: 4,
        rooms: [
            0, 0, 1, 1,
            0, 0, 1, 1,
            2, 2, 3, 1,
            2, 2, 3, 3,
        ],
        solution: [1, 3, 0, 2]
    )

    /// 図の 1 コマ。`cats` と `crosses` のマスに印を置き、矛盾は本番と同じ判定で印を付ける。
    private struct Board: View {
        var cats: [Int] = []
        var crosses: [Int] = []
        var solved = false
        var body: some View {
            let sample = CatPuzzleHowToFigures.sample
            var marks = Array(repeating: CatPuzzleModel.Mark.empty, count: sample.cellCount)
            for cell in crosses { marks[cell] = .cross }
            for cell in cats { marks[cell] = .cat }
            let conflicts = CatPuzzleLogic.violations(puzzle: sample, cats: cats).cells
            return CatPuzzleBoardCanvas(puzzle: sample, marks: marks, conflicts: conflicts, isSolved: solved,
                                        cellSide: CatPuzzleHowToFigures.cellSide)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous).fill(Theme.surface))
        }
    }

    /// 答えの盤（部屋・行・列に 1 匹ずつ）。
    private struct OnePerRoomFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                Board(cats: CatPuzzleHowToFigures.sample.solutionCells)
                RuleFigureLabel(tr("部屋・行・列に 1 匹ずつ"), color: Theme.tealText)
            }
        }
    }

    /// ななめに隣り合った 2 匹に「！」の印。
    private struct NotAdjacentFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                Board(cats: [1, 6])
                RuleFigureLabel(tr("ななめでも隣はダメ"), color: Theme.coralText)
            }
        }
    }

    /// 空き → × → 猫。
    private struct TapCycleFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 3, spacing: 6) { index in
                    Board(cats: index == 2 ? [1] : [], crosses: index == 1 ? [1] : [])
                }
                RuleFigureLabel(tr("タップで × → 猫 → 空"), color: Theme.coralText)
            }
        }
    }
}
