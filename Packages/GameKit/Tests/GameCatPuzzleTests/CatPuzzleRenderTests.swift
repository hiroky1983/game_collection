import Testing
import GameKitTestSupport
import Foundation
import SwiftUI
import Core
import CoreTestSupport
@testable import GameCatPuzzle

/// 画面の静止画（#2250 の試作の確認用）。`CAT_PUZZLE_RENDER_DIR` に出力先を渡したときだけ PNG を書き、
/// 普段のテストでは盤の絵が描けることだけを確かめる。シミュレータを使わずに `ImageRenderer` で描く。
///
/// 例: `CAT_PUZZLE_RENDER_DIR=/tmp/cat swift test --package-path Packages/GameKit --filter CatPuzzleRenderTests`
@Suite("おじさんちのねこさがしの静止画")
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
    private static func playingModel(size: CatPuzzleSize = .normal) -> CatPuzzleModel {
        let model = CatPuzzleModel(services: services(), size: size, seed: 1)
        let answers = model.puzzle.solutionCells
        for cell in answers.prefix(3) { model.findCat(cell: cell) }
        for cell in [answers[0] + 1, answers[1] - 1, answers[2] + model.puzzle.side] where model.marks.indices.contains(cell) && model.marks[cell] == .empty {
            model.toggleCross(cell: cell)
        }
        return model
    }

    /// ヒントを使った直後。`wanted` に合う推理が次のヒントになるまで、手前のヒントの中身をプレイヤーの操作（タップ）で
    /// 盤に写してから 1 回だけヒントを使う（ヒントの印と理由の文が狙った種類になる）。種 1 から順に探す。
    private static func hintModel(_ name: String, wanted: (CatPuzzleHint) -> Bool) -> CatPuzzleModel {
        for seed in 1...40 {
            let model = CatPuzzleModel(services: services(), size: .normal, seed: UInt64(seed))
            var steps = 0
            while let hint = model.nextHint, steps < 60 {
                if wanted(hint) {
                    model.useHint()
                    return model
                }
                steps += 1
                for cell in hint.crossed where model.marks[cell] == .empty { model.toggleCross(cell: cell) }
                if let placed = hint.placed { model.findCat(cell: placed) }
            }
        }
        Issue.record("\(name): 狙った種類のヒントになる局面が見つからない")
        return CatPuzzleModel(services: services(), size: .normal, seed: 1)
    }

    /// 行・列への × （部屋が 1 行／1 列に収まる、など）。
    private static func hintLineModel() -> CatPuzzleModel {
        hintModel("hint-line") { hint in
            if case .confined(_, let targets) = hint.reason, hint.crossed.count >= 2,
               targets.allSatisfy({ if case .room = $0 { false } else { true } }) { return true }
            return false
        }
    }

    /// 部屋への ×（行／列の猫が 1 部屋の中だけ、など）。
    private static func hintRoomModel() -> CatPuzzleModel {
        hintModel("hint-room") { hint in
            if case .confined(_, let targets) = hint.reason, targets.contains(where: { if case .room = $0 { true } else { false } }) { return true }
            return false
        }
    }

    /// 猫の確定（入れるマスが 1 つだけ）。
    private static func hintCatModel() -> CatPuzzleModel {
        hintModel("hint-cat") { hint in
            if case .onlyCell = hint.reason { return true }
            return false
        }
    }

    /// 無料のヒントを使い切った途中の盤（次の 1 回は広告）。
    private static func hintAdModel() -> CatPuzzleModel {
        let model = playingModel()
        for _ in 0..<CatPuzzleModel.freeHints { model.useHint() }
        return model
    }

    /// 答えでないマスに猫を置こうとした直後。前に付いた赤い × 1 つと、いま付いた赤い ×（赤枠）1 つ。
    private static func wrongCrossModel() -> CatPuzzleModel {
        let model = CatPuzzleModel(services: services(), size: .normal, seed: 1)
        let puzzle = model.puzzle
        let answers = puzzle.solutionCells
        let n = puzzle.side
        for cell in answers.prefix(2) { model.findCat(cell: cell) }
        // 答えでないマスを 2 つ（前のミスと、いまのミス）。
        let wrongs = (0..<puzzle.cellCount).filter { !answers.contains($0) && model.marks[$0] == .empty && $0 / n >= 3 }
        for cell in [wrongs[2], wrongs[9]] { model.findCat(cell: cell) }
        return model
    }

    /// 種ごとの遊んでいる途中。答えの猫 3 匹、各部屋の左上から見て最初の「答えでないマス」に ×、ヒント 1 回。
    /// 種 2 だけ、まだ猫のいない部屋の左上寄りの空きマスに猫を置こうとする（答えでないので赤い ×）。
    private static func playingSeedModel(seed: UInt64) -> CatPuzzleModel {
        let model = CatPuzzleModel(services: services(), size: .normal, seed: seed)
        let puzzle = model.puzzle
        let answers = puzzle.solutionCells
        for cell in answers.prefix(3) { model.findCat(cell: cell) }
        for room in 0..<puzzle.side {
            if let cell = puzzle.cells(inRoom: room).first(where: { !answers.contains($0) }), model.marks[cell] == .empty {
                model.toggleCross(cell: cell)
            }
        }
        model.useHint()
        if seed == 2,
           let room = answers.map({ puzzle.rooms[$0] }).first(where: { room in !puzzle.cells(inRoom: room).contains { model.marks[$0] == .cat } }),
           let wrong = puzzle.cells(inRoom: room).first(where: { !answers.contains($0) }) {
            model.findCat(cell: wrong)
        }
        return model
    }

    /// 部屋の札のあるマスに × を付けた盤。札のマスのうち 2 つに通常の ×、1 つに赤い ×（答えでないので猫を置こうとした）。
    /// × はほかのマスと同じ中央にあり、札が × の上に重なる（会長 QA 2026-10-21・build 43）。
    private static func labelCrossModel() -> CatPuzzleModel {
        let model = CatPuzzleModel(services: services(), size: .normal, seed: 1)
        let puzzle = model.puzzle
        let labelCells = (0..<puzzle.side).compactMap { room -> Int? in
            guard let narrow = CatPuzzleBoardCanvas.labelPlacement(room: room, in: puzzle, wide: false),
                  let wide = CatPuzzleBoardCanvas.labelPlacement(room: room, in: puzzle, wide: true),
                  narrow.cell == wide.cell else { return nil }
            return narrow.cell
        }
        for cell in labelCells.prefix(2) { model.toggleCross(cell: cell) }
        if let wrong = labelCells.dropFirst(2).first { model.findCat(cell: wrong) }
        return model
    }

    /// ミスが 3 回になって終局（負け）したところ。
    private static func failedModel() -> CatPuzzleModel {
        let model = CatPuzzleModel(services: services(), size: .normal, seed: 1)
        let answers = model.puzzle.solutionCells
        for cell in answers.prefix(2) { model.findCat(cell: cell) }
        let wrongs = (0..<model.puzzle.cellCount).filter { !answers.contains($0) && model.marks[$0] == .empty }
        for cell in [wrongs[3], wrongs[12], wrongs[25]] { model.findCat(cell: cell) }
        return model
    }

    /// 3 回目のミスの直後（結果カード 1 枚の中でコンティニューかあきらめるかを選ばせている）。
    private static func offerModel() -> CatPuzzleModel { failedModel() }

    /// あきらめて負けを確定したところ（見つけていない猫が正解の場所に出る。結果カードはもう重ねない・#2904）。
    private static func revealedModel() -> CatPuzzleModel {
        let model = failedModel()
        model.declineContinue()
        return model
    }

    /// 広告でコンティニューしたあと、もう一度ミスが 3 回になったところ（提案は出さず、負けのカードを 1 回だけ出す）。
    private static func continuedLossModel() -> CatPuzzleModel {
        let model = failedModel()
        model.continueAfterAd()
        let answers = model.puzzle.solutionCells
        let wrong = (0..<model.puzzle.cellCount).first { !answers.contains($0) && model.marks[$0] == .empty }
        if let wrong { model.findCat(cell: wrong) }
        return model
    }

    /// 最後の猫を置いた瞬間（クリアのダイアログはまだ出ていない。ダイアログを「盤を見る」で閉じた後もこの見た目）。
    private static func lastCatModel() -> CatPuzzleModel {
        let model = CatPuzzleModel(services: services(), size: .normal, seed: 1)
        for cell in model.puzzle.solutionCells { model.findCat(cell: cell) }
        return model
    }

    /// クリアから 1 拍おいてダイアログが出たところ。
    private static func clearModel(size: CatPuzzleSize = .normal) -> CatPuzzleModel {
        let clock = ManualClock()
        let model = CatPuzzleModel(services: services(), size: size, seed: 1)
        model.clockNow = clock.now
        for cell in model.puzzle.solutionCells { model.findCat(cell: cell) }
        clock.advance(by: CatPuzzleModel.clearCardDelay)
        model.revealClearCardIfDue()
        return model
    }

    @Test("盤の絵は描ける（Canvas が空にならない）")
    func boardRenders() {
        let model = Self.playingModel()
        let renderer = ImageRenderer(content: CatPuzzleBoardCanvas(
            puzzle: model.puzzle, marks: model.marks, wrongCrosses: model.wrongCrosses,
            hintCells: model.hintCells, hintCrosses: model.hintCrosses, lastHint: model.lastHint, cellSide: 40
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
        let plan = NightlyScale.value(
            ci: [(CatPuzzleSize.easy, UInt64(1)...6), (.normal, 1...6), (.hard, 1...2)],
            nightly: [(CatPuzzleSize.easy, UInt64(1)...30), (.normal, 1...30), (.hard, 1...6)]
        )
        for (size, seeds) in plan {
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
        #expect(checkedRooms == plan.reduce(0) { $0 + $1.1.count * $1.0.side })
    }

    /// iPhone SE の遊び方のカードで図に使える幅（画面幅 375 − シートの余白 16×2 − カードの内側 14×2）。
    static let seHowToFigureWidth: CGFloat = 375 - Theme.pad * 2 - 14 * 2

    @Test("遊び方の図は iPhone SE の遊び方のカードの幅に収まる（横にはみ出さない）")
    func howToFiguresFitSE() throws {
        #expect(CatPuzzleHowToFigures.items.count == HowToPlayGuide.catPuzzle.items.count)
        for (index, figure) in CatPuzzleHowToFigures.items.enumerated() {
            let renderer = ImageRenderer(content: figure().fixedSize())
            renderer.scale = 1
            let image = try #require(renderer.cgImage, "図 \(index + 1) が描けない")
            #expect(CGFloat(image.width) <= Self.seHowToFigureWidth,
                    "図 \(index + 1) の幅 \(image.width)pt が SE のカード（\(Self.seHowToFigureWidth)pt）を超える")
        }
    }

    @Test("札のマスの × は他のマスと同じ中央に描く（札は × の上に重ねる）")
    func crossIsCenteredEvenUnderLabel() {
        let r = CGRect(x: 40, y: 80, width: 40, height: 40)
        let bounds = CatPuzzleBoardCanvas.crossPath(in: r, cellSide: 40).boundingRect
        #expect(abs(bounds.midX - r.midX) < 0.01 && abs(bounds.midY - r.midY) < 0.01)
    }

    @Test("静止画を書き出す（CAT_PUZZLE_RENDER_DIR があるときだけ）")
    func writeScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["CAT_PUZZLE_RENDER_DIR"], !dir.isEmpty else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let scenes: [(name: String, make: () -> CatPuzzleModel)] = [
            ("1-playing", { Self.playingModel() }),
            // 6×6・8×8・9×9 の途中とクリア（どの大きさでも札・壁・マスの区切りが崩れないことを目で見る。とくに SE の 9×9）。
            ("1-playing-easy", { Self.playingModel(size: .easy) }),
            ("1-playing-hard", { Self.playingModel(size: .hard) }),
            ("4c-clear-easy", { Self.clearModel(size: .easy) }),
            ("4c-clear-hard", { Self.clearModel(size: .hard) }),
            ("1-playing-expert", { Self.playingModel(size: .expert) }),
            ("4c-clear-expert", { Self.clearModel(size: .expert) }),
            ("2-wrong-cross", Self.wrongCrossModel),
            ("3a-hint-line", Self.hintLineModel),
            ("3b-hint-room", Self.hintRoomModel),
            ("3c-hint-cat", Self.hintCatModel),
            // 無料のヒントを使い切ったところ（ヒントのボタンが「0回 ▶ 広告を見て +1」）。
            ("3d-hint-ad", Self.hintAdModel),
            ("4a-last-cat", Self.lastCatModel),
            ("4b-clear-dialog", { Self.clearModel() }),
            ("10-label-cross", Self.labelCrossModel),
            ("11-three-mistakes", Self.offerModel),
            ("11b-answers-board", Self.revealedModel),
            ("11c-continued-loss", Self.continuedLossModel),
        ]
        let schemes: [(name: String, scheme: ColorScheme)] = [("light", .light), ("dark", .dark)]
        for device in Self.devices {
            for scene in scenes {
                for scheme in schemes {
                    let model = scene.make()
                    let view = CatPuzzleView(services: Self.services(), model: model,
                                             showsAnswers: scene.name.hasPrefix("11b") || scene.name.hasPrefix("11c"))
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
        // 開始シート（難易度を選ぶ）と遊び方のカード（図入り）を端末の幅で。
        for device in Self.devices {
            for scheme in schemes {
                let suffix = scheme.scheme == .light ? "" : "-dark"
                // `ImageRenderer` は ScrollView の中身を描かないので、節を本来の位置（題名の行の下）に重ねて描く。
                let sheet = ZStack(alignment: .top) {
                    CatPuzzleNewGameSheet(initial: .normal, onStart: { _ in }, onCancel: {})
                    CatPuzzleNewGameSheet.sizeSection(selection: .constant(.expert))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.pad)
                        .padding(.top, 78)
                }
                    .frame(width: device.size.width, height: device.size.height)
                    .environment(\.colorScheme, scheme.scheme)
                let sheetRenderer = ImageRenderer(content: sheet)
                sheetRenderer.scale = 3
                try Self.write(try #require(sheetRenderer.cgImage),
                               to: URL(fileURLWithPath: dir).appendingPathComponent("12-setup-sheet-\(device.name)\(suffix).png"))
                let guide = HowToPlayGuide.catPuzzle.illustrated(CatPuzzleHowToFigures.items)
                let howTo = VStack(spacing: 10) {
                    ForEach(Array(guide.items.enumerated()), id: \.offset) { index, item in
                        HowToPlayItemCard(item, number: index + 1)
                    }
                    if !guide.notes.isEmpty { HowToPlayNotesCard(guide.notes) }
                }
                .padding(Theme.pad)
                .frame(width: device.size.width)
                .fixedSize(horizontal: false, vertical: true)
                .background(Theme.background)
                .environment(\.colorScheme, scheme.scheme)
                let howToRenderer = ImageRenderer(content: howTo)
                howToRenderer.scale = 3
                try Self.write(try #require(howToRenderer.cgImage),
                               to: URL(fileURLWithPath: dir).appendingPathComponent("13-howto-\(device.name)\(suffix).png"))
            }
        }

        // 札のマスの × を大きく（通常・赤）。
        let labelModel = Self.labelCrossModel()
        let labelBoard = ImageRenderer(content: CatPuzzleBoardCanvas(
            puzzle: labelModel.puzzle, marks: labelModel.marks, wrongCrosses: labelModel.wrongCrosses,
            lastWrongCell: labelModel.lastWrongCell, cellSide: 50
        ).padding(8).background(Theme.surface))
        labelBoard.scale = 3
        try Self.write(try #require(labelBoard.cgImage), to: URL(fileURLWithPath: dir).appendingPathComponent("10-label-cross-board.png"))

        // クリアの盤だけ（カードに隠れない、猫がくつろぐ絵）。
        let solved = Self.clearModel()
        let board = ImageRenderer(content: CatPuzzleBoardCanvas(
            puzzle: solved.puzzle, marks: solved.marks, isSolved: true, cellSide: 50
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
                    isSolved: false, cellSide: 40
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
                    puzzle: model.puzzle, marks: model.marks, wrongCrosses: model.wrongCrosses, lastWrongCell: model.lastWrongCell,
                    hintCells: model.hintCells, hintCrosses: model.hintCrosses, lastHint: model.lastHint, cellSide: 40
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
                    isSolved: true, cellSide: 40
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
