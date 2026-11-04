import Testing
import SwiftUI
import AppKit
@testable import GameGomoku

/// 開始シートの「ルールの要点」の図が iPhone SE（幅 375）で枠からはみ出さないこと（#3306）。
/// 幅 1 を提案して返ってくる幅＝その図が縮められる限界（最小幅）を見る。
@MainActor
struct GomokuHowToFigureWidthTests {
    // SE 幅 375 − シートの左右余白 16×2 − カードの左右余白 14×2 = 315。
    private let limit: CGFloat = 315

    private func minWidth<V: View>(_ view: V) -> CGFloat {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: 1, height: 1000)).width
    }

    @Test func figuresFitInSmallPhone() {
        let widths: [CGFloat] = [
            minWidth(GomokuHowToFigures.PlaceFigure()),
            minWidth(GomokuHowToFigures.FiveFigure()),
            minWidth(GomokuHowToFigures.BlockFigure()),
            minWidth(GomokuHowToFigures.DoubleThreeFigure()),
        ]
        for width in widths { #expect(width <= limit) }
    }
}
