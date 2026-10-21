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

    /// 遊んでいる途中（猫 3 匹・× いくつか）。
    private static func playingModel() -> CatPuzzleModel {
        let model = CatPuzzleModel(services: services(), size: .normal, seed: 1)
        let answers = model.puzzle.solutionCells
        for cell in answers.prefix(3) { model.tap(cell: cell); model.tap(cell: cell) }
        for cell in [answers[0] + 1, answers[1] - 1, answers[2] + model.puzzle.side] where model.marks.indices.contains(cell) && model.marks[cell] == .empty {
            model.tap(cell: cell)
        }
        return model
    }

    /// ヒントを使った直後（違う場所に置いた猫を × にして、正しいマスに猫を置いた場面）。
    private static func hintModel() -> CatPuzzleModel {
        let model = playingModel()
        let answers = model.puzzle.solutionCells
        let room = model.puzzle.rooms[answers[4]]
        if let wrong = model.puzzle.cells(inRoom: room).first(where: { $0 != answers[4] && model.marks[$0] == .empty }) {
            model.tap(cell: wrong); model.tap(cell: wrong)
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

    /// 種ごとの遊んでいる途中。答えの猫 3 匹、各部屋の左上から見て最初の「答えでないマス」に ×、ヒント 1 回。
    /// 種 2 だけ、まだ猫のいない部屋の左上寄りの空きマスに間違いの猫を置く。
    private static func playingSeedModel(seed: UInt64) -> CatPuzzleModel {
        let model = CatPuzzleModel(services: services(), size: .normal, seed: seed)
        let puzzle = model.puzzle
        let answers = puzzle.solutionCells
        for cell in answers.prefix(3) { model.tap(cell: cell); model.tap(cell: cell) }
        for room in 0..<puzzle.side {
            if let cell = puzzle.cells(inRoom: room).first(where: { !answers.contains($0) }), model.marks[cell] == .empty {
                model.tap(cell: cell)
            }
        }
        model.useHint()
        if seed == 2,
           let room = answers.map({ puzzle.rooms[$0] }).first(where: { room in !puzzle.cells(inRoom: room).contains { model.marks[$0] == .cat } }),
           let wrong = puzzle.cells(inRoom: room).first(where: { !answers.contains($0) }) {
            for _ in 0..<3 where model.marks[wrong] != .cat { model.tap(cell: wrong) }
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
            hintCells: model.hintCells, lastHint: model.lastHint, cellSide: 40
        ))
        renderer.scale = 1
        let image = renderer.cgImage
        #expect(image != nil)
        #expect(image?.width == 40 * model.puzzle.side)
    }

    @Test("猫の矩形: 途中はマスの内側、クリア後はマスより大きく盤の中に収まる")
    func catRectFits() {
        let n = 7
        let side: CGFloat = 40
        let playing = CatPuzzleBoardCanvas.catRect(cell: 0, pose: .faceNormal, solved: false, side: n, cellSide: side)
        #expect(CGRect(x: 0, y: 0, width: side, height: side).contains(playing))
        for cell in [0, n - 1, n * n - 1, n * 3 + 3] {
            let solved = CatPuzzleBoardCanvas.catRect(cell: cell, pose: .sleep, solved: true, side: n, cellSide: side)
            #expect(solved.width > side || solved.height > side)
            #expect(CGRect(x: 0, y: 0, width: side * CGFloat(n), height: side * CGFloat(n)).insetBy(dx: -0.01, dy: -0.01).contains(solved))
        }
    }

    @Test("部屋の札は答えのマス（最後に猫が座るマス）を避けて、部屋の中の左上寄りに置く")
    func labelAvoidsAnswerCells() {
        var checkedRooms = 0
        // 問題作りはデバッグビルドだと 1 問 1 秒ほどかかるので、大きい盤は種を絞る。
        for (size, seeds) in [(CatPuzzleSize.easy, UInt64(1)...30), (.normal, 1...30), (.hard, 1...6)] {
            for seed in seeds {
                let puzzle = CatPuzzleModel(services: Self.services(), size: size, seed: seed).puzzle
                let n = puzzle.side
                let answers = Set(puzzle.solutionCells)
                for room in 0..<n {
                    let cells = puzzle.cells(inRoom: room)
                    for wide in [false, true] {
                        guard let placement = CatPuzzleBoardCanvas.labelPlacement(room: room, in: puzzle, wide: wide) else {
                            Issue.record("種 \(seed) の部屋 \(room) に札が置けない"); continue
                        }
                        #expect(puzzle.rooms[placement.cell] == room)
                        if cells.count > 1 {
                            #expect(!answers.contains(placement.cell), "種 \(seed) の部屋 \(room) の札が答えのマスに重なる")
                        } else {
                            #expect(placement.cell == cells[0] && !placement.spansRight)
                        }
                        if placement.spansRight {
                            #expect(wide && placement.cell % n < n - 1)
                            #expect(puzzle.rooms[placement.cell + 1] == room && !answers.contains(placement.cell + 1))
                        }
                        if !wide {
                            // 左上から順に見て最初の空き（答えでない）マス。
                            #expect(placement.cell == (cells.first { !answers.contains($0) } ?? cells[0]))
                        }
                    }
                    checkedRooms += 1
                }
            }
        }
        #expect(checkedRooms == 30 * 6 + 30 * 7 + 6 * 8)
    }

    @Test("静止画を書き出す（CAT_PUZZLE_RENDER_DIR があるときだけ）")
    func writeScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["CAT_PUZZLE_RENDER_DIR"], !dir.isEmpty else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let scenes: [(name: String, make: () -> CatPuzzleModel)] = [
            ("1-playing", Self.playingModel),
            ("2-mistake", Self.mistakeModel),
            ("3-hint", Self.hintModel),
            ("4-clear", Self.clearModel),
        ]
        let schemes: [(name: String, scheme: ColorScheme)] = [("light", .light), ("dark", .dark)]
        for device in Self.devices {
            for scene in scenes {
                for scheme in schemes {
                    let model = scene.make()
                    let view = CatPuzzleView(services: Self.services(), model: model)
                        .frame(width: device.size.width, height: device.size.height)
                        .background(Theme.background)
                        .environment(\.colorScheme, scheme.scheme)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 3
                    let image = try #require(renderer.cgImage, "\(device.name) \(scene.name) \(scheme.name) が描けない")
                    let suffix = scheme.scheme == .light ? "" : "-dark"
                    let url = URL(fileURLWithPath: dir).appendingPathComponent("\(scene.name)-\(device.name)\(suffix).png")
                    try Self.write(image, to: url)
                }
            }
        }
        // クリアの盤だけ（カードに隠れない、猫がくつろぐ絵）。
        let solved = Self.clearModel()
        let board = ImageRenderer(content: CatPuzzleBoardCanvas(
            puzzle: solved.puzzle, marks: solved.marks, conflicts: [], isSolved: true, cellSide: 50
        ).padding(8).background(Theme.surface))
        board.scale = 3
        let boardImage = try #require(board.cgImage)
        try Self.write(boardImage, to: URL(fileURLWithPath: dir).appendingPathComponent("5-clear-board.png"))

        // 違う種の解き終えた盤を 3 つ並べる（部屋と答えの行の対応が種ごとに変わることを目で見る・#2250）。
        let seeds = HStack(spacing: 12) {
            ForEach([1, 2, 3], id: \.self) { seed in
                let model = CatPuzzleModel(services: Self.services(), size: .normal, seed: UInt64(seed))
                CatPuzzleBoardCanvas(
                    puzzle: model.puzzle, marks: model.puzzle.solutionCells.reduce(into: model.marks) { $0[$1] = .cat },
                    conflicts: [], isSolved: false, cellSide: 40
                )
            }
        }
        .padding(8)
        .background(Theme.surface)
        let seedsRenderer = ImageRenderer(content: seeds)
        seedsRenderer.scale = 2
        try Self.write(try #require(seedsRenderer.cgImage), to: URL(fileURLWithPath: dir).appendingPathComponent("7-three-seeds.png"))

        // 同じ 3 つの種の遊んでいる途中（猫 3 匹・各部屋の左上寄りの空きマスに ×・ヒント 1 回・種 2 は間違いの猫つき）と
        // クリアの盤。部屋の札が猫の顔・×・ヒントの印に重ならないことを目で見る（#2250）。
        let playingSeeds = HStack(spacing: 12) {
            ForEach([1, 2, 3], id: \.self) { seed in
                let model = Self.playingSeedModel(seed: UInt64(seed))
                CatPuzzleBoardCanvas(
                    puzzle: model.puzzle, marks: model.marks, conflicts: model.violations.cells,
                    hintCells: model.hintCells, lastHint: model.lastHint, cellSide: 40
                )
            }
        }
        .padding(8)
        .background(Theme.surface)
        let playingSeedsRenderer = ImageRenderer(content: playingSeeds)
        playingSeedsRenderer.scale = 2
        try Self.write(try #require(playingSeedsRenderer.cgImage), to: URL(fileURLWithPath: dir).appendingPathComponent("8-three-seeds-playing.png"))

        let clearSeeds = HStack(spacing: 12) {
            ForEach([1, 2, 3], id: \.self) { seed in
                let model = CatPuzzleModel(services: Self.services(), size: .normal, seed: UInt64(seed))
                CatPuzzleBoardCanvas(
                    puzzle: model.puzzle, marks: model.puzzle.solutionCells.reduce(into: model.marks) { $0[$1] = .cat },
                    conflicts: [], isSolved: true, cellSide: 40
                )
            }
        }
        .padding(8)
        .background(Theme.surface)
        let clearSeedsRenderer = ImageRenderer(content: clearSeeds)
        clearSeedsRenderer.scale = 2
        try Self.write(try #require(clearSeedsRenderer.cgImage), to: URL(fileURLWithPath: dir).appendingPathComponent("9-three-seeds-clear.png"))

        // 猫を置いた瞬間のコマ（出入りの transition と同じ `CatPopModifier` を途中の値で描く）。
        let frames: [(CGFloat, Double, Double)] = [(0.25, -18, 0), (0.55, -12, 0.55), (0.9, -4, 1), (1.08, 2, 1), (1, 0, 1)]
        let room = CatPuzzleHouse.room(0)
        let strip = HStack(spacing: 6) {
            ForEach(Array(frames.enumerated()), id: \.offset) { _, f in
                ZStack {
                    Rectangle().fill(room.tint)
                    CatPuzzleArt.image(.faceNormal)
                        .padding(5)
                        .modifier(CatPopModifier(scale: f.0, degrees: f.1, opacity: f.2))
                }
                .frame(width: 60, height: 60)
                .clipped()
            }
        }
        .padding(8)
        .background(Theme.surface)
        let stripRenderer = ImageRenderer(content: strip)
        stripRenderer.scale = 3
        try Self.write(try #require(stripRenderer.cgImage), to: URL(fileURLWithPath: dir).appendingPathComponent("6-appear-frames.png"))
    }

    private static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
