import Core
import CoreMiniBoard
import SwiftUI

/// 図入りの遊び方（#2044）の将棋の図。文言は `HowToPlayGuide.shogi.items`（Core）と同じ順。
@MainActor
enum ShogiHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(SelectMoveFigure()) },
        { AnyView(CaptureFigure()) },
        { AnyView(PromoteFigure()) },
        { AnyView(MateFigure()) },
    ]

    static let cell: CGFloat = 30

    static func koma(_ type: PieceType, mine: Bool = true, promoted: Bool = false) -> some View {
        KomaView(piece: Piece(type: type, color: mine ? .black : .white, promoted: promoted),
                 size: cell, pointsUp: mine)
    }

    /// 駒をタップ → 動けるマスが光る → 移動。
    struct SelectMoveFigure: View {
        private let moves: Set<[Int]> = [[0, 1], [0, 2], [0, 3], [1, 1], [1, 3], [2, 2]]

        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    RuleMiniBoard(rows: 3, cols: 5, cell: cell, style: .shogi) { row, col in
                        ZStack {
                            if index == 0, row == 1, col == 2 { RuleBoardMark.tint(opacity: 0.25) }
                            if index == 0, moves.contains([row, col]) { RuleBoardMark.dot() }
                            if index == 0, row == 1, col == 2 { koma(.gold) }
                            if index == 1, row == 0, col == 2 { koma(.gold) }
                        }
                    }
                    RuleFigureLabel(index == 0 ? tr("駒をタップ → 光るマス") : tr("タップで移動"), color: index == 0 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// 相手の駒があるマスへ動くと取れて、持ち駒になる。
    struct CaptureFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        RuleMiniBoard(rows: 3, cols: 3, cell: cell, style: .shogi) { row, col in
                            ZStack {
                                if row == 0, col == 1 { RuleBoardMark.tint(opacity: 0.3) }
                                if row == 0, col == 1 { koma(.pawn, mine: false) }
                                if row == 1, col == 1 { koma(.silver) }
                            }
                        }
                        RuleFigureLabel(tr("相手の駒のマスへ"))
                    } else {
                        HStack(alignment: .bottom, spacing: 10) {
                            RuleMiniBoard(rows: 3, cols: 3, cell: cell, style: .shogi) { row, col in
                                ZStack {
                                    if row == 0, col == 1 { koma(.silver) }
                                }
                            }
                            VStack(spacing: 2) {
                                koma(.pawn)
                                RuleFigureLabel(tr("持ち駒"), color: Theme.coralText)
                            }
                        }
                        RuleFigureLabel(tr("取れて、持ち駒に"))
                    }
                }
            }
        }
    }

    /// 相手陣（奥から 3 段）に入ると成れる。
    struct PromoteFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    RuleMiniBoard(rows: 5, cols: 3, cell: 26, style: .shogi) { row, col in
                        ZStack {
                            if row < 3 { RuleBoardMark.tint(opacity: 0.22) }
                            if col == 1 {
                                if index == 0, row == 3 { KomaView(piece: Piece(type: .pawn, color: .black), size: 26, pointsUp: true) }
                                if index == 1, row == 2 { KomaView(piece: Piece(type: .pawn, color: .black, promoted: true), size: 26, pointsUp: true) }
                            }
                        }
                    }
                    RuleFigureLabel(index == 0 ? tr("赤い 3 段が相手陣") : tr("入ると成れる（歩 → と）"),
                                    color: index == 0 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// 頭金の詰み: 王将の逃げ場がなく、金も取れない。
    struct MateFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 3, cols: 3, cell: cell, style: .shogi) { row, col in
                    ZStack {
                        if row == 0, col == 1 { koma(.king, mine: false) }
                        if row == 1, col == 1 { koma(.gold) }
                        if row == 2, col == 1 { koma(.pawn) }
                    }
                }
                RuleFigureLabel(tr("王手！ 逃げ場も、金を取る手もない"), color: Theme.coralText)
            }
        }
    }
}
