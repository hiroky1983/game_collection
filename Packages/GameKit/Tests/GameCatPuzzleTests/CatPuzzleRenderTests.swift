import Testing
import Foundation
import SwiftUI
import Core
import CoreTestSupport
@testable import GameCatPuzzle

/// 画面の静止画（#2250 の試作の確認用）。`CAT_PUZZLE_RENDER_DIR` に出力先を渡したときだけ PNG を書き、
/// 普段のテストでは盤の絵が描けることだけを確かめる。シミュレータを使わずに `ImageRenderer` で描く。
///
/// 例: `CAT_PUZZLE_RENDER_DIR=/tmp/cat swift test --package-path Packages/GameKit --filter CatPuzzleRenderTests`
@Suite("おじさんの飼い猫パズルの静止画")
@MainActor
struct CatPuzzleRenderTests {
    /// 幅・高さ（pt）: iPhone 17（393×852）と iPhone SE（375×667）。
    private static let devices: [(name: String, size: CGSize)] = [
        ("iphone17", CGSize(width: 393, height: 852)),
        ("se", CGSize(width: 375, height: 667)),
    ]

    private static func services(store: MemorySnapshotStore = MemorySnapshotStore()) -> GameServices {
        GameServices(snapshots: store, ads: NoopAdService())
    }

    /// 遊んでいる途中（猫 3 匹・× いくつか・ヒント 1 つ）。
    private static func playingModel() -> CatPuzzleModel {
        let model = CatPuzzleModel(services: services(), size: .normal, seed: 1)
        let answers = model.puzzle.solutionCells
        for cell in answers.prefix(3) { model.tap(cell: cell); model.tap(cell: cell) }
        for cell in [answers[0] + 1, answers[1] - 1, answers[2] + model.puzzle.side] where model.marks.indices.contains(cell) && model.marks[cell] == .empty {
            model.tap(cell: cell)
        }
        model.useHint()
        return model
    }

    /// 間違い（同じ行と隣に猫）。
    private static func mistakeModel() -> CatPuzzleModel {
        let model = CatPuzzleModel(services: services(), size: .normal, seed: 1)
        let answers = model.puzzle.solutionCells
        let n = model.puzzle.side
        let first = answers[0]
        model.tap(cell: first); model.tap(cell: first)
        let sameRow = first % n < n - 2 ? first + 2 : first - 2
        model.tap(cell: sameRow); model.tap(cell: sameRow)
        let diagonal = answers[3] + n + 1
        if model.marks.indices.contains(diagonal) {
            model.tap(cell: answers[3]); model.tap(cell: answers[3])
            model.tap(cell: diagonal); model.tap(cell: diagonal)
        }
        return model
    }

    /// クリア。
    private static func clearModel() -> CatPuzzleModel {
        let model = CatPuzzleModel(services: services(), size: .normal, seed: 1)
        for cell in model.puzzle.solutionCells { model.tap(cell: cell); model.tap(cell: cell) }
        return model
    }

    @Test("盤の絵は描ける（Canvas が空にならない）")
    func boardRenders() {
        let model = Self.playingModel()
        let renderer = ImageRenderer(content: CatPuzzleBoardCanvas(
            puzzle: model.puzzle, marks: model.marks, conflicts: model.violations.cells,
            hintCell: model.hintCell, cellSide: 40
        ))
        renderer.scale = 1
        let image = renderer.cgImage
        #expect(image != nil)
        #expect(image?.width == 40 * model.puzzle.side)
    }

    @Test("静止画を書き出す（CAT_PUZZLE_RENDER_DIR があるときだけ）")
    func writeScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["CAT_PUZZLE_RENDER_DIR"], !dir.isEmpty else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let scenes: [(name: String, make: () -> CatPuzzleModel)] = [
            ("1-playing", Self.playingModel),
            ("2-mistake", Self.mistakeModel),
            ("3-clear", Self.clearModel),
        ]
        for device in Self.devices {
            for scene in scenes {
                let model = scene.make()
                let view = CatPuzzleView(services: Self.services(), model: model)
                    .frame(width: device.size.width, height: device.size.height)
                    .background(Theme.background)
                    .environment(\.colorScheme, .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                let image = try #require(renderer.cgImage, "\(device.name) \(scene.name) が描けない")
                let url = URL(fileURLWithPath: dir).appendingPathComponent("\(scene.name)-\(device.name).png")
                try Self.write(image, to: url)
            }
        }
        // クリアの盤だけ（カードに隠れない、猫がくつろぐ絵）。
        let solved = Self.clearModel()
        let board = ImageRenderer(content: CatPuzzleBoardCanvas(
            puzzle: solved.puzzle, marks: solved.marks, conflicts: [], isSolved: true, cellSide: 50
        ).padding(8).background(Theme.surface))
        board.scale = 3
        let boardImage = try #require(board.cgImage)
        try Self.write(boardImage, to: URL(fileURLWithPath: dir).appendingPathComponent("4-clear-board.png"))
    }

    private static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
