import Core
import SwiftUI

/// 図入りの遊び方（#2044）のおじさんちのねこさがし（#2250）の図。文言は `HowToPlayGuide.catPuzzle.items`（Core）と同じ順。
/// 盤は本番と同じ `CatPuzzleBoardCanvas` で、4×4 の小さな問題を描く。
@MainActor
enum CatPuzzleHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(OnePerRoomFigure()) },
        { AnyView(NotAdjacentFigure()) },
        { AnyView(TapControlsFigure()) },
    ]

    /// 1 枚だけの図のマスの大きさ。
    static let cellSide: CGFloat = 28
    /// 3 コマを横に並べる図（タップで ×・ダブルタップで猫）のマスの大きさ。iPhone SE の遊び方のカード
    /// （画面幅 375 − 余白 16×2 − カードの内側 14×2 = 315pt）に 3 枚と矢印が収まる大きさ（会長 QA 2026-10-21・build 43）。
    static let frameCellSide: CGFloat = 18

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

    /// ななめに隣り合った 2 匹の図の猫のマス（`sample` の上で）。
    static let adjacentCats = [1, 6]
    /// タップ操作の図で印を付けるマス（`sample` の答えのマス）。
    static let tapCell = 1

    /// 図の 1 コマ。`cats` と `crosses` のマスに印を置き、矛盾は本番と同じ判定で印を付ける。
    struct Board: View {
        var cats: [Int] = []
        var crosses: [Int] = []
        /// 赤い ×（答えでないマスをダブルタップしたミス）。`crosses` にも入れておく（本番と同じ持ち方）。
        var wrongCrosses: Set<Int> = []
        var solved = false
        var cellSide: CGFloat = CatPuzzleHowToFigures.cellSide
        var showsRoomLabels = true
        var body: some View {
            let sample = CatPuzzleHowToFigures.sample
            var marks = Array(repeating: CatPuzzleModel.Mark.empty, count: sample.cellCount)
            for cell in crosses { marks[cell] = .cross }
            for cell in cats { marks[cell] = .cat }
            let violations = CatPuzzleLogic.violations(puzzle: sample, cats: cats)
            return CatPuzzleBoardCanvas(puzzle: sample, marks: marks, conflicts: violations.cells,
                                        wrongCrosses: wrongCrosses, isSolved: solved, showsRoomLabels: showsRoomLabels, cellSide: cellSide)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous).fill(Theme.surface))
        }
    }

    /// 答えの盤（部屋・行・列に 1 匹ずつ）。
    struct OnePerRoomFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                Board(cats: CatPuzzleHowToFigures.sample.solutionCells)
                RuleFigureLabel(tr("部屋・行・列に 1 匹ずつ"), color: Theme.tealText)
            }
        }
    }

    /// ななめに隣り合った 2 匹に「！」の印。
    struct NotAdjacentFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                Board(cats: CatPuzzleHowToFigures.adjacentCats)
                RuleFigureLabel(tr("ななめでも隣はダメ"), color: Theme.coralText)
            }
        }
    }

    /// 空き ⇄ ×（タップ）と、空き → 猫（ダブルタップ）。3 コマ「× ⇄ 空き → 猫」に並べ、両端のコマの下に操作を書く。
    /// 横幅は従来の 3 コマ（`frameCellSide`）と同じなので iPhone SE のカードに収まる（#2669）。
    struct TapControlsFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    frame(crosses: [CatPuzzleHowToFigures.tapCell], caption: tr("タップ"))
                    arrow("arrow.left.arrow.right")
                    frame(caption: nil)
                    arrow("arrow.right")
                    frame(cats: [CatPuzzleHowToFigures.tapCell], caption: tr("ダブルタップ"))
                }
                RuleFigureLabel(tr("タップで × を付け外し、ダブルタップで猫"), color: Theme.coralText)
            }
        }

        private func frame(cats: [Int] = [], crosses: [Int] = [], caption: String?) -> some View {
            VStack(spacing: 2) {
                Board(cats: cats, crosses: crosses, cellSide: CatPuzzleHowToFigures.frameCellSide, showsRoomLabels: false)
                // 説明の無いコマも同じ高さにして、3 コマの盤の高さを揃える。
                Text(caption ?? " ")
                    .scaledFont(10, weight: .bold, design: .rounded, maxScale: 1.2)
                    .foregroundStyle(Theme.inkSubText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }

        private func arrow(_ systemImage: String) -> some View {
            Image(systemName: systemImage)
                .scaledFont(12, weight: .black, maxScale: 1.2)
                .foregroundStyle(Theme.inkSubText)
                // 盤（4 マス＋余白）の縦の真ん中に合わせる。
                .frame(height: CatPuzzleHowToFigures.frameCellSide * 4 + 6)
        }
    }
}
