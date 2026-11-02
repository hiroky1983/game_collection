import Testing
import CoreGraphics
@testable import GameCatPuzzle

@Suite("ねこさがし 盤の拡大・移動（#3238）")
@MainActor
struct CatPuzzleBoardZoomTests {
    let side: CGFloat = 360

    @Test("拡大率は等倍〜2.5 倍に収まる")
    func scaleIsClamped() {
        var zoom = CatPuzzleBoardZoom()
        zoom.zoom(by: 10, anchor: CGPoint(x: 180, y: 180), boardSide: side)
        #expect(zoom.scale == CatPuzzleBoardZoom.maxScale)
        zoom.zoom(by: 0.01, anchor: CGPoint(x: 180, y: 180), boardSide: side)
        #expect(zoom.scale == CatPuzzleBoardZoom.minScale)
        #expect(zoom.offset == .zero)
        #expect(!zoom.isZoomed)
    }

    @Test("指の下の点は拡大しても動かない")
    func anchorStaysPut() {
        var zoom = CatPuzzleBoardZoom()
        let anchor = CGPoint(x: 120, y: 200)
        let before = zoom.unzoomed(anchor)
        zoom.zoom(by: 2, anchor: anchor, boardSide: side)
        let after = zoom.unzoomed(anchor)
        #expect(abs(before.x - after.x) < 0.001)
        #expect(abs(before.y - after.y) < 0.001)
    }

    @Test("移動しても盤は枠の外に出ない")
    func panStaysInsideFrame() {
        var zoom = CatPuzzleBoardZoom()
        zoom.zoom(by: 2, anchor: .zero, boardSide: side)
        zoom.pan(by: CGPoint(x: 5000, y: 5000), boardSide: side)
        #expect(zoom.offset == .zero)
        zoom.pan(by: CGPoint(x: -5000, y: -5000), boardSide: side)
        let slack = side * (zoom.scale - 1)
        #expect(zoom.offset == CGPoint(x: -slack, y: -slack))
    }

    @Test("端で拡大しても盤は枠を覆ったまま")
    func zoomAtEdgeKeepsCover() {
        var zoom = CatPuzzleBoardZoom()
        zoom.zoom(by: 2.5, anchor: CGPoint(x: side, y: side), boardSide: side)
        let slack = side * (zoom.scale - 1)
        #expect(zoom.offset.x >= -slack && zoom.offset.x <= 0)
        #expect(zoom.offset.y >= -slack && zoom.offset.y <= 0)
    }

    @Test("等倍に戻せる")
    func resetReturnsToIdentity() {
        var zoom = CatPuzzleBoardZoom()
        zoom.zoom(by: 2, anchor: CGPoint(x: 90, y: 90), boardSide: side)
        zoom.pan(by: CGPoint(x: -30, y: -10), boardSide: side)
        zoom.reset()
        #expect(zoom == CatPuzzleBoardZoom())
    }

    @Test("拡大中も、タップした場所のマスが選ばれる")
    func tapMapsToCellWhileZoomed() {
        let n = 12
        let inset = CatPuzzleView.boardInset
        let cellSide = CatPuzzleView.cellSide(boardSide: side, side: n)
        var zoom = CatPuzzleBoardZoom()
        zoom.zoom(by: 2.5, anchor: CGPoint(x: 0, y: 0), boardSide: side)
        zoom.pan(by: CGPoint(x: -100, y: -60), boardSide: side)
        // 見えているマス (行 5, 列 7) の中心を、画面上の点に直してから戻す。
        let col = 7, row = 5
        let drawn = cellSide * zoom.scale
        let screen = CGPoint(
            x: zoom.offset.x + inset * zoom.scale + (CGFloat(col) + 0.5) * drawn,
            y: zoom.offset.y + inset * zoom.scale + (CGFloat(row) + 0.5) * drawn)
        let cell = CatPuzzleModel.cell(at: zoom.unzoomed(screen), side: n, cellSide: cellSide, inset: inset)
        #expect(cell == row * n + col)
    }
}
