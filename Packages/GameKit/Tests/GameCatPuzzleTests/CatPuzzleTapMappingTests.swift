import Testing
import Foundation
import SwiftUI
@testable import GameCatPuzzle

/// 盤のタップの座標 → マスの変換（`CatPuzzleModel.cell(at:)`）が、盤の絵（`CatPuzzleBoardCanvas`）の描くマスと一致すること（#3300）。
/// 盤は枠の内側の余白（`CatPuzzleView.boardInset`）だけずらして絵を置き、タップは同じ余白で戻す。外枠の壁・部屋の札は
/// マスの上に重ねて描くだけで、マスの位置は動かさない。
@Suite("ねこさがし タップの位置とマス（#3300）")
@MainActor
struct CatPuzzleTapMappingTests {
    /// 盤の一辺（pt）: iPhone SE（幅 375 − 左右の余白 16×2）と iPhone 17（幅 393 − 32）。
    nonisolated static let boardSides: [CGFloat] = [343, 361]

    /// 9×9（60 面・鍵の面）と 12×12（141 面）。
    nonisolated static let stages = [60, 141]

    @Test("各マスの中心と、四隅から 2pt 内側を押すと、そのマスになる（9×9・12×12 × SE・17）",
          arguments: stages, boardSides)
    func everyCellMapsBack(stage: Int, boardSide: CGFloat) {
        let n = CatPuzzleStage(stage).size.side
        let inset = CatPuzzleView.boardInset
        let cellSide = CatPuzzleView.cellSide(boardSide: boardSide, side: n)
        for cell in 0..<(n * n) {
            // 絵の中のマスの矩形を、盤の枠の座標（絵は余白ぶん右下に置かれる）へ。
            let r = CatPuzzleBoardCanvas.rect(of: cell, side: n, cellSide: cellSide).offsetBy(dx: inset, dy: inset)
            let points = [
                CGPoint(x: r.midX, y: r.midY),
                CGPoint(x: r.minX + 2, y: r.minY + 2), CGPoint(x: r.maxX - 2, y: r.minY + 2),
                CGPoint(x: r.minX + 2, y: r.maxY - 2), CGPoint(x: r.maxX - 2, y: r.maxY - 2),
            ]
            for point in points {
                #expect(CatPuzzleModel.cell(at: point, side: n, cellSide: cellSide, inset: inset) == cell,
                        "\(stage) 面・盤 \(boardSide)pt・マス \(cell)・点 \(point)")
            }
        }
    }

    @Test("実際に描いた赤い × の位置を押すと、そのマスになる（60 面のマス 28・29 と四隅・12×12 の四隅）",
          arguments: boardSides)
    func drawnCrossMapsBack(boardSide: CGFloat) throws {
        for (stage, cells) in [(60, [28, 29, 0, 8, 72, 80]), (141, [0, 11, 132, 143])] {
            let puzzle = CatPuzzleStage(stage).makePuzzle()
            let n = puzzle.side
            let cellSide = CatPuzzleView.cellSide(boardSide: boardSide, side: n)
            let inset = CatPuzzleView.boardInset
            let blank = try render(puzzle, wrong: [], cellSide: cellSide)
            for cell in cells {
                let marked = try render(puzzle, wrong: [cell], cellSide: cellSide)
                let box = try #require(diffBox(blank, marked), "\(stage) 面のマス \(cell) の × が描けていない")
                // 描いた × の中心（絵の座標）を、盤の枠の座標に直してから押す。
                let tap = CGPoint(x: box.midX + inset, y: box.midY + inset)
                #expect(CatPuzzleModel.cell(at: tap, side: n, cellSide: cellSide, inset: inset) == cell,
                        "\(stage) 面・盤 \(boardSide)pt・マス \(cell)・× の中心 \(tap)")
            }
        }
    }

    private struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    private func render(_ puzzle: CatPuzzle, wrong: Set<Int>, cellSide: CGFloat) throws -> Bitmap {
        let renderer = ImageRenderer(content: CatPuzzleBoardCanvas(
            puzzle: puzzle, marks: Array(repeating: .empty, count: puzzle.cellCount),
            wrongCrosses: wrong, lastWrongCell: nil, showsRoomLabels: false, cellSide: cellSide
        ))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        // 画素の並びを揃えるため RGBA に描き直す。
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let context = try #require(CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Bitmap(width: w, height: h, bytes: bytes)
    }

    /// 2 枚で色が違う画素を囲む矩形（左上原点）。
    private func diffBox(_ a: Bitmap, _ b: Bitmap) -> CGRect? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<a.height {
            for x in 0..<a.width {
                let o = (y * a.width + x) * 4
                let d = (0..<3).map { abs(Int(a.bytes[o + $0]) - Int(b.bytes[o + $0])) }.max() ?? 0
                if d > 24 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
