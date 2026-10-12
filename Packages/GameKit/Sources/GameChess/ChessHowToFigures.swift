import Core
import SwiftUI

/// 図入りの遊び方（#2044）のチェスの図。文言は `HowToPlayGuide.chess.items`（Core）と同じ順。
@MainActor
enum ChessHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(SelectMoveFigure()) },
        { AnyView(MovesFigure()) },
        { AnyView(MateFigure()) },
    ]

    private static func piece(_ type: ChessPieceType, _ color: ChessColor = .white, size: CGFloat = 26) -> some View {
        ChessPieceView(piece: ChessPiece(type: type, color: color), size: size, style: .flat)
            .frame(width: size, height: size)
    }

    /// 駒をタップ → 動けるマスが光る → 移動。
    private struct SelectMoveFigure: View {
        private let moves: Set<[Int]> = [[0, 0], [0, 4], [1, 1], [1, 3], [3, 1], [3, 3], [4, 0], [4, 4]]

        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    RuleMiniBoard(rows: 5, cols: 5, cell: 26, style: .checker) { row, col in
                        ZStack {
                            if index == 0, moves.contains([row, col]) { RuleBoardMark.dot() }
                            if index == 0, row == 2, col == 2 { piece(.bishop) }
                            if index == 1, row == 0, col == 4 { piece(.bishop) }
                        }
                    }
                    RuleFigureLabel(index == 0 ? "駒をタップ → 光るマス" : "タップで移動",
                                    color: index == 0 ? Theme.coral : Theme.inkSub)
                }
            }
        }
    }

    /// ナイト（L 字）・ビショップ（ななめ）・ルーク（たてよこ）の動き。
    private struct MovesFigure: View {
        private let knight: Set<[Int]> = [[0, 1], [0, 3], [1, 0], [1, 4], [3, 0], [3, 4], [4, 1], [4, 3]]

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                column("ナイト", .knight) { row, col in knight.contains([row, col]) }
                column("ビショップ", .bishop) { row, col in row != 2 && col != 2 && abs(row - 2) == abs(col - 2) }
                column("ルーク", .rook) { row, col in (row == 2) != (col == 2) }
            }
        }

        private func column(_ name: String, _ type: ChessPieceType,
                            dot: @escaping (Int, Int) -> Bool) -> some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 5, cols: 5, cell: 18, style: .checker) { row, col in
                    ZStack {
                        if dot(row, col) { RuleBoardMark.dot() }
                        if row == 2, col == 2 { piece(type, size: 18) }
                    }
                }
                RuleFigureLabel(name)
            }
        }
    }

    /// バックランクメイト: キングの逃げ場がない。
    private struct MateFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 2, cols: 4, cell: 30, style: .checker) { row, col in
                    ZStack {
                        if row == 0, col == 0 { piece(.rook, size: 30) }
                        if row == 0, col == 3 { piece(.king, .black, size: 30) }
                        if row == 1, col == 2 || col == 3 { piece(.pawn, .black, size: 30) }
                    }
                }
                RuleFigureLabel("ルークで王手！ 逃げ場がない", color: Theme.coral)
            }
        }
    }
}
