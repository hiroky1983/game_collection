import SwiftUI
import Core

/// 盤の絵（家の間取り・印・猫）。本番と遊び方の図で同じものを使う（#2250）。
///
/// 1 マスずつ床の色と柄を塗り、マスの区切り（タップの単位）をはっきりした線で引き、部屋の境目に
/// 太い壁を引き、部屋の左上寄りの「答えでないマス」に名前の札を置く（`labelPlacement`）。線の強さは
/// **壁＞マスの区切り＞床の柄** の順（`CatPuzzleHouse`）。
/// 猫は `Canvas` ではなく `CatPuzzleCatLayer` の SwiftUI ビューで重ねる（置いた瞬間に弾む・消すときは
/// 短く縮む・クリアで順に跳ねる演出のため。会長 QA 2026-10-21）。答えでないマスに猫を置こうとして付いた
/// 固定の赤い × も別の層で重ねる（付いた瞬間に揺れて赤く点滅する。build 42）。読み上げと操作は
/// `CatPuzzleView` の透明なマスが担う（この絵は `accessibilityHidden`）。
struct CatPuzzleBoardCanvas: View {
    let puzzle: CatPuzzle
    let marks: [CatPuzzleModel.Mark]
    /// 「！」を付ける猫のマス。遊び方の図（ななめ隣の 2 匹）だけが使う。本番は答えでない猫が盤に残らない
    /// （赤い × に置き換わる・build 42）ので渡さない。
    var conflicts: Set<Int> = []
    /// 答えでないマスに猫を置こうとして付いた固定の赤い ×。
    var wrongCrosses: Set<Int> = []
    /// 直近に赤い × が付いたマス（赤の枠で囲み、付いた瞬間に揺れて点滅する）。次の操作で消える。
    var lastWrongCell: Int? = nil
    /// ヒントで置いた猫のマス（電球の印を付ける）。
    var hintCells: Set<Int> = []
    /// ヒントで置いた × のマス（黄色の縁取りで印を付ける）。
    var hintCrosses: Set<Int> = []
    /// 直近のヒント（関わる行・列・部屋を黄色く光らせ、置いたマスを黄色の枠、× にしたマスを細い枠で囲む）。
    var lastHint: CatPuzzleHint? = nil
    /// 赤い × を揺らすきっかけ（値が変わるたびに `lastWrongCell` の × が短く揺れて点滅する。`CatPuzzleModel.mistakes`）。
    var shakeToken = 0
    var isSolved = false
    let cellSide: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 外周の壁の太さ。
    private var borderWidth: CGFloat { CatPuzzleHouse.wallWidth * 1.5 }

    var body: some View {
        let n = puzzle.side
        let boardSide = cellSide * CGFloat(n)
        let rooms = (0..<n).map { CatPuzzleHouse.room($0) }
        ZStack(alignment: .topLeading) {
            // 下の層: 床・マスの区切り・ヒントの黄色い帯・壁・部屋の札・×（赤い × は別の層）。
            // 札は猫より下に敷く（間違えて札のマスに猫を置いても、猫の顔が札に隠れない）。
            // 札のマスの × は札の下の余白に寄せて描き、札の文字と × が重ならないようにする。
            Canvas { context, _ in
                drawFloors(&context, rooms: rooms)
                drawGrid(&context)
                drawHintGlow(&context)
                drawConflictFills(&context)
                drawWalls(&context)
                let labelBottoms = drawLabels(&context, rooms: rooms)
                drawCrosses(&context, labelBottoms: labelBottoms)
            }
            // 答えでないマスの赤い ×（付いた瞬間に揺れて点滅する）。
            // Reduce Motion のときは揺らさず点滅もしない（直近のマスの赤い枠と面は静止で残る）。
            if !isSolved && !wrongCrosses.isEmpty {
                PhaseAnimator(CatPuzzleMotion.shakePhases, trigger: shakeToken) { phase in
                    Canvas { context, _ in
                        let labelBottoms = drawLabels(&context, rooms: rooms, draw: false)
                        drawWrongCrosses(&context, labelBottoms: labelBottoms, phase: reduceMotion ? 0 : phase)
                    }
                } animation: { _ in
                    reduceMotion ? nil : CatPuzzleMotion.shakeStep
                }
            }
            // 猫（弾む・縮む・跳ねる）。クリアで大きくなった猫は壁に少しかぶる。
            CatPuzzleCatLayer(puzzle: puzzle, marks: marks, isSolved: isSolved, cellSide: cellSide, rooms: rooms)
            // 上の層: 矛盾の「！」・ヒントの印と枠（猫より前に出す）。
            Canvas { context, _ in
                drawConflictBadges(&context)
                drawHintBadges(&context)
                drawLastHint(&context)
            }
        }
        .frame(width: boardSide, height: boardSide)
        .accessibilityHidden(true)
    }

    // MARK: - 行・列・部屋の形

    /// 行・列・部屋のマス。
    private func cells(of group: CatPuzzleHint.Group) -> [Int] {
        let n = puzzle.side
        switch group {
        case .row(let row): return Array((row * n)..<(row * n + n))
        case .column(let col): return (0..<n).map { $0 * n + col }
        case .room(let room): return puzzle.cells(inRoom: room)
        }
    }

    /// マスの集まりの外周（隣が集まりの外にある辺だけ）。帯の縁取りに使う。
    static func outline(of cells: Set<Int>, side n: Int, cellSide: CGFloat) -> Path {
        var path = Path()
        for cell in cells.sorted() {
            let r = rect(of: cell, side: n, cellSide: cellSide)
            let row = cell / n, col = cell % n
            if row == 0 || !cells.contains(cell - n) { path.move(to: CGPoint(x: r.minX, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.minY)) }
            if row == n - 1 || !cells.contains(cell + n) { path.move(to: CGPoint(x: r.minX, y: r.maxY)); path.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
            if col == 0 || !cells.contains(cell - 1) { path.move(to: CGPoint(x: r.minX, y: r.minY)); path.addLine(to: CGPoint(x: r.minX, y: r.maxY)) }
            if col == n - 1 || !cells.contains(cell + 1) { path.move(to: CGPoint(x: r.maxX, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
        }
        return path
    }

    // MARK: - 寸法

    static func rect(of cell: Int, side n: Int, cellSide: CGFloat) -> CGRect {
        CGRect(x: CGFloat(cell % n) * cellSide, y: CGFloat(cell / n) * cellSide, width: cellSide, height: cellSide)
    }

    /// 猫の絵を置く矩形。遊んでいる途中はマスの内側、クリア後はマスより少し大きく（盤の外にははみ出さない）。
    static func catRect(cell: Int, pose: CatPuzzleArt.Pose, solved: Bool, side n: Int, cellSide: CGFloat) -> CGRect {
        let r = rect(of: cell, side: n, cellSide: cellSide)
        guard solved else {
            return CatPuzzleArt.fitted(pose, in: r.insetBy(dx: cellSide * 0.08, dy: cellSide * 0.08))
        }
        let boardRect = CGRect(x: 0, y: 0, width: cellSide * CGFloat(n), height: cellSide * CGFloat(n))
        var target = CatPuzzleArt.fitted(pose, in: r.insetBy(dx: -cellSide * 0.12, dy: -cellSide * 0.12))
        target.origin.x = min(max(target.minX, boardRect.minX), boardRect.maxX - target.width)
        target.origin.y = min(max(target.minY, boardRect.minY), boardRect.maxY - target.height)
        return target
    }

    private func rect(of cell: Int) -> CGRect {
        Self.rect(of: cell, side: puzzle.side, cellSide: cellSide)
    }

    // MARK: - 下の層

    private func drawFloors(_ context: inout GraphicsContext, rooms: [CatPuzzleHouse.Room]) {
        for cell in 0..<puzzle.cellCount {
            let room = rooms[puzzle.rooms[cell] % rooms.count]
            let r = rect(of: cell)
            context.fill(Path(r), with: .color(room.tint))
            CatPuzzleFloorPainter.draw(room.floor, in: r, strength: room.patternStrength, context: &context, ink: Theme.ink)
        }
    }

    /// マスの区切り（タップの単位）。床の柄よりはっきり、壁より細く。
    private func drawGrid(_ context: inout GraphicsContext) {
        let n = puzzle.side
        var path = Path()
        for i in 1..<n {
            let p = CGFloat(i) * cellSide
            path.move(to: CGPoint(x: p, y: 0))
            path.addLine(to: CGPoint(x: p, y: cellSide * CGFloat(n)))
            path.move(to: CGPoint(x: 0, y: p))
            path.addLine(to: CGPoint(x: cellSide * CGFloat(n), y: p))
        }
        context.stroke(path, with: .color(Theme.ink.opacity(CatPuzzleHouse.gridOpacity)), lineWidth: CatPuzzleHouse.gridWidth)
    }

    /// 部屋の境目の壁と外周。
    private func drawWalls(_ context: inout GraphicsContext) {
        let n = puzzle.side
        var walls = Path()
        for cell in 0..<puzzle.cellCount {
            let r = rect(of: cell)
            let row = cell / n, col = cell % n
            if col < n - 1, puzzle.rooms[cell] != puzzle.rooms[cell + 1] {
                walls.move(to: CGPoint(x: r.maxX, y: r.minY))
                walls.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            }
            if row < n - 1, puzzle.rooms[cell] != puzzle.rooms[cell + n] {
                walls.move(to: CGPoint(x: r.minX, y: r.maxY))
                walls.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            }
        }
        // 端は伸ばさない（外周の壁からはみ出さないように）。T 字の継ぎ目は外周の壁が覆う。
        context.stroke(walls, with: .color(Theme.ink), style: StrokeStyle(lineWidth: CatPuzzleHouse.wallWidth, lineCap: .butt))
        let outer = CGRect(x: 0, y: 0, width: cellSide * CGFloat(n), height: cellSide * CGFloat(n))
        context.stroke(Path(outer.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)), with: .color(Theme.ink), lineWidth: borderWidth)
    }

    /// ×（いない印）。こげ茶（ダークは生成り）の太い × に、面の色の縁取りを敷いて床の上で読めるようにする。
    /// ヒントで置いた × は縁取りを黄色にして印を付ける（消せない × だと分かる）。赤い × は `CatPuzzleWrongCrossLayer` が描く。
    /// 札のあるマス（`labelBottoms` = マス → 札の下端の y）では、札より下の余白の真ん中に寄せる。
    private func drawCrosses(_ context: inout GraphicsContext, labelBottoms: [Int: CGFloat] = [:]) {
        guard !isSolved else { return }
        var cross = Path()
        var hinted = Path()
        for cell in 0..<puzzle.cellCount where marks[cell] == .cross && !wrongCrosses.contains(cell) {
            let shape = Self.crossPath(in: rect(of: cell), labelBottom: labelBottoms[cell], cellSide: cellSide)
            if hintCrosses.contains(cell) { hinted.addPath(shape) } else { cross.addPath(shape) }
        }
        let width = Self.crossWidth(cellSide: cellSide)
        let halo = StrokeStyle(lineWidth: Self.crossHaloWidth(cellSide: cellSide), lineCap: .round)
        if !cross.isEmpty {
            context.stroke(cross, with: .color(CatPuzzleHouse.crossHalo.opacity(0.9)), style: halo)
            context.stroke(cross, with: .color(CatPuzzleHouse.crossColor), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        if !hinted.isEmpty {
            context.stroke(hinted, with: .color(Theme.yellow), style: halo)
            context.stroke(hinted, with: .color(CatPuzzleHouse.crossColor), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    /// × の線の太さと縁取りの太さ。
    static func crossWidth(cellSide: CGFloat) -> CGFloat { max(2.5, cellSide * 0.085) }
    static func crossHaloWidth(cellSide: CGFloat) -> CGFloat { crossWidth(cellSide: cellSide) + max(3, cellSide * 0.09) }

    /// マス `r` の × の形。札のあるマス（`labelBottom` = 札の下端の y）では、札より下の余白の真ん中に寄せる。
    static func crossPath(in r: CGRect, labelBottom: CGFloat?, cellSide: CGFloat) -> Path {
        let arm = cellSide * 0.17
        let midY = labelBottom.map { max(r.midY, ($0 + r.maxY) / 2) } ?? r.midY
        var shape = Path()
        shape.move(to: CGPoint(x: r.midX - arm, y: midY - arm))
        shape.addLine(to: CGPoint(x: r.midX + arm, y: midY + arm))
        shape.move(to: CGPoint(x: r.midX + arm, y: midY - arm))
        shape.addLine(to: CGPoint(x: r.midX - arm, y: midY + arm))
        return shape
    }

    /// 答えでないマスの固定の赤い ×（会長 QA 2026-10-21・build 42）。マスを薄い赤で塗り、赤い太い × に白い縁取り。
    /// 直近に付いたマス（`lastWrongCell`）は赤い枠で囲み、`phase`（揺れの位置。0 で止まる）だけ × を左右にずらし、
    /// 揺れているあいだはマスの赤を濃くして点滅させる。
    private func drawWrongCrosses(_ context: inout GraphicsContext, labelBottoms: [Int: CGFloat], phase: CGFloat) {
        let width = Self.crossWidth(cellSide: cellSide) * 1.15
        let inset = CatPuzzleHouse.wallWidth / 2
        for cell in wrongCrosses.sorted() {
            let r = rect(of: cell)
            let isLast = cell == lastWrongCell
            let flash = isLast ? abs(phase) * 0.3 : 0
            context.fill(Path(r), with: .color(Theme.coral.opacity(0.2 + flash)))
            let shift = isLast ? phase * cellSide * 0.09 : 0
            let shape = Self.crossPath(in: r.offsetBy(dx: shift, dy: 0), labelBottom: labelBottoms[cell], cellSide: cellSide)
            context.stroke(shape, with: .color(CatPuzzleHouse.crossHalo.opacity(0.95)),
                           style: StrokeStyle(lineWidth: Self.crossHaloWidth(cellSide: cellSide) * 1.1, lineCap: .round))
            context.stroke(shape, with: .color(Theme.coralText), style: StrokeStyle(lineWidth: width, lineCap: .round))
            if isLast {
                context.stroke(Path(roundedRect: r.insetBy(dx: inset, dy: inset), cornerRadius: cellSide * 0.12),
                               with: .color(Theme.coralText), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }

    /// 遊び方の図の「！」の猫のマスを薄い赤にする。猫の下に敷く。
    private func drawConflictFills(_ context: inout GraphicsContext) {
        guard !isSolved else { return }
        for cell in conflicts where marks.indices.contains(cell) && marks[cell] == .cat {
            context.fill(Path(rect(of: cell)), with: .color(Theme.coral.opacity(0.22)))
        }
    }

    /// 直近のヒントに関わる行・列・部屋を黄色く光らせる（猫の下・壁の下）。次の操作で消える。
    private func drawHintGlow(_ context: inout GraphicsContext) {
        guard let lastHint, !isSolved else { return }
        for group in lastHint.highlights {
            var path = Path()
            for cell in cells(of: group) { path.addRect(rect(of: cell)) }
            context.fill(path, with: .color(Theme.yellow.opacity(0.28)))
        }
    }

    // MARK: - 上の層

    /// 部屋の札を置くマス。部屋のマスを左上から（行優先で）見て、**答えのマスでない最初のマス**。
    /// 答えのマスには最後に必ず猫が座るので、そこを避けて最初から決めておく（猫を置いても札が動かずちらつかない）。
    /// `wide`（札が 1 マスに収まらない）ときは、右隣も同じ部屋の答えでないマスになっているところを優先し、
    /// 札を 2 マスにまたがせる（`spansRight`）。無ければ最初の答えでないマスに置き、文字を縮めて 1 マスに収める。
    /// 1 マスだけの部屋は答えのマスしか無いので、そのマス（札は猫の下に敷かれ、猫の顔は隠れない）。
    static func labelPlacement(room: Int, in puzzle: CatPuzzle, wide: Bool) -> (cell: Int, spansRight: Bool)? {
        let cells = puzzle.cells(inRoom: room)
        guard let first = cells.first else { return nil }
        let n = puzzle.side
        let answers = Set(puzzle.solutionCells)
        let free = cells.filter { !answers.contains($0) }
        if wide, let cell = free.first(where: { $0 % n < n - 1 && puzzle.rooms[$0 + 1] == room && !answers.contains($0 + 1) }) {
            return (cell, true)
        }
        return (free.first ?? first, false)
    }

    /// 部屋の名前の札。`labelPlacement` のマスの左上に置き、隣の部屋のマスにははみ出さない。
    /// 返り値は札がかかるマス → 札の下端の y（× を札の下に寄せるため）。`draw` が偽なら測るだけ（赤い × の層）。
    private func drawLabels(_ context: inout GraphicsContext, rooms: [CatPuzzleHouse.Room], draw: Bool = true) -> [Int: CGFloat] {
        var bottoms: [Int: CGFloat] = [:]
        let n = puzzle.side
        let baseFont = max(8, cellSide * 0.22)
        let margin = max(cellSide * 0.06, CatPuzzleHouse.wallWidth / 2 + 1)
        let padding = CGSize(width: cellSide * 0.1, height: cellSide * 0.04)
        func resolved(_ name: String, size: CGFloat) -> GraphicsContext.ResolvedText {
            context.resolve(
                Text(name)
                    .font(.system(size: size, weight: .bold, design: .rounded)) // fixed-size: 盤のマスの寸法に比例させる札の文字（図形のジオメトリに従う）
                    .foregroundColor(Theme.Fixed.ink)
            )
        }
        for room in 0..<n {
            let name = rooms[room % rooms.count].name
            var text = resolved(name, size: baseFont)
            var measured = text.measure(in: CGSize(width: cellSide * 4, height: cellSide))
            let wide = measured.width + padding.width * 2 > cellSide - margin * 2
            guard let placement = Self.labelPlacement(room: room, in: puzzle, wide: wide) else { continue }
            let available = (placement.spansRight ? cellSide * 2 : cellSide) - margin * 2
            if measured.width + padding.width * 2 > available {
                let size = max(6, baseFont * (available - padding.width * 2) / measured.width)
                text = resolved(name, size: size)
                measured = text.measure(in: CGSize(width: available, height: cellSide))
            }
            let origin = rect(of: placement.cell).origin.applying(.init(translationX: margin, y: margin))
            let chip = CGRect(x: origin.x, y: origin.y,
                              width: measured.width + padding.width * 2, height: measured.height + padding.height * 2)
            if draw {
                context.fill(Path(roundedRect: chip, cornerRadius: chip.height / 2), with: .color(.white.opacity(0.9)))
                context.draw(text, at: CGPoint(x: chip.minX + padding.width, y: chip.minY + padding.height), anchor: .topLeading)
            }
            bottoms[placement.cell] = chip.maxY
            if placement.spansRight, chip.maxX > rect(of: placement.cell).maxX { bottoms[placement.cell + 1] = chip.maxY }
        }
        return bottoms
    }

    /// 矛盾の「！」の丸（赤い面と合わせ、色と印の両方で示す）。
    private func drawConflictBadges(_ context: inout GraphicsContext) {
        guard !isSolved else { return }
        for cell in conflicts where marks.indices.contains(cell) && marks[cell] == .cat {
            let r = rect(of: cell)
            let radius = cellSide * 0.15
            let center = CGPoint(x: r.maxX - radius - 2, y: r.minY + radius + 2)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(Theme.coralText))
            let bang = context.resolve(
                Text(verbatim: "!")
                    .font(.system(size: radius * 1.6, weight: .heavy, design: .rounded)) // fixed-size: 矛盾の印の丸に合わせる記号（図形のジオメトリに従う）
                    .foregroundColor(.white)
            )
            context.draw(bang, at: center, anchor: .center)
        }
    }

    /// ヒントで置いた猫の印（右下の黄色い丸に電球）。消せない猫だと分かるよう、クリアまで出し続ける。
    private func drawHintBadges(_ context: inout GraphicsContext) {
        guard !isSolved else { return }
        for cell in hintCells.sorted() where marks.indices.contains(cell) && marks[cell] == .cat {
            let r = rect(of: cell)
            let radius = cellSide * 0.15
            let center = CGPoint(x: r.maxX - radius - 2, y: r.maxY - radius - 2)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(Theme.yellow))
            let bulb = context.resolve(
                Text(Image(systemName: "lightbulb.fill"))
                    .font(.system(size: radius * 1.3, weight: .bold)) // fixed-size: ヒントの印の丸に合わせる記号（図形のジオメトリに従う）
                    .foregroundColor(Theme.Fixed.ink)
            )
            context.draw(bulb, at: center, anchor: .center)
        }
    }

    /// 直近のヒントの枠。関わる行・列・部屋の縁取り（黄）、置いた猫のマスは黄色の太枠（「ここ！」）、
    /// 新しく × にしたマスは黄色の細い枠、外した猫のマスは赤の枠。次の操作で消える。
    private func drawLastHint(_ context: inout GraphicsContext) {
        guard let lastHint, !isSolved else { return }
        let n = puzzle.side
        for group in lastHint.highlights {
            let path = Self.outline(of: Set(cells(of: group)), side: n, cellSide: cellSide)
            context.stroke(path, with: .color(Theme.yellowText), style: StrokeStyle(lineWidth: max(2, cellSide * 0.05), lineCap: .square))
        }
        let inset = CatPuzzleHouse.wallWidth / 2
        for cell in lastHint.crossed where marks.indices.contains(cell) {
            context.stroke(Path(roundedRect: rect(of: cell).insetBy(dx: inset + 1, dy: inset + 1), cornerRadius: cellSide * 0.12),
                           with: .color(Theme.yellowText), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        for cell in lastHint.removed where marks.indices.contains(cell) {
            context.stroke(Path(roundedRect: rect(of: cell).insetBy(dx: inset, dy: inset), cornerRadius: cellSide * 0.12),
                           with: .color(Theme.coralText), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        if let placed = lastHint.placed, marks.indices.contains(placed) {
            context.stroke(Path(roundedRect: rect(of: placed).insetBy(dx: inset, dy: inset), cornerRadius: cellSide * 0.12),
                           with: .color(Theme.yellow), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }
}

// MARK: - 猫の層

/// 盤の上に置く猫たち。マスごとに 1 つのビューにして、置いた瞬間の「ぽん」・消すときの縮み・
/// クリアで順に跳ねる演出を SwiftUI の transition / phaseAnimator で付ける（会長 QA 2026-10-21）。
/// Reduce Motion のときは弾まず・回らず・跳ねず、出入りは透明度だけ（`Motion` の方針どおり即時反映）。
struct CatPuzzleCatLayer: View {
    let puzzle: CatPuzzle
    let marks: [CatPuzzleModel.Mark]
    let isSolved: Bool
    let cellSide: CGFloat
    let rooms: [CatPuzzleHouse.Room]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let n = puzzle.side
        let boardSide = cellSide * CGFloat(n)
        // 行→列の順（クリアの跳ねる順もこの順）。
        let cats = marks.indices.filter { marks[$0] == .cat }
        ZStack(alignment: .topLeading) {
            ForEach(Array(cats.enumerated()), id: \.element) { order, cell in
                let pose: CatPuzzleArt.Pose = isSolved ? rooms[puzzle.rooms[cell] % rooms.count].clearPose : .faceNormal
                let target = CatPuzzleBoardCanvas.catRect(cell: cell, pose: pose, solved: isSolved, side: n, cellSide: cellSide)
                CatPuzzleCatSprite(pose: pose, order: order, isSolved: isSolved, hop: cellSide * 0.28)
                    .frame(width: target.width, height: target.height)
                    .position(x: target.midX, y: target.midY)
                    .transition(CatPuzzleMotion.catTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(width: boardSide, height: boardSide)
    }
}

/// 猫 1 匹。クリアになった瞬間、`order` の順に少し間を置いて 1 回ずつ跳ねる。
private struct CatPuzzleCatSprite: View {
    let pose: CatPuzzleArt.Pose
    let order: Int
    let isSolved: Bool
    /// 跳ねる高さ（pt）。
    let hop: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CatPuzzleArt.image(pose)
            .phaseAnimator([false, true], trigger: isSolved) { view, up in
                let jumping = up && isSolved && !reduceMotion
                view
                    .scaleEffect(jumping ? 1.08 : 1)
                    .offset(y: jumping ? -hop : 0)
            } animation: { up in
                guard !reduceMotion else { return nil }
                return up
                    ? CatPuzzleMotion.hopUp.delay(Double(order) * CatPuzzleMotion.hopStagger)
                    : CatPuzzleMotion.hopDown
            }
    }
}

/// 猫の演出の数値。
enum CatPuzzleMotion {
    /// 置いた瞬間（小さく回りながら、少し行き過ぎて戻る）。
    static let appear: Animation = .spring(response: 0.32, dampingFraction: 0.55)
    /// 消すとき（短く縮んで消える）。
    static let vanish: Animation = .easeOut(duration: 0.12)
    /// クリアで跳ねる（上がる / 着地）。
    static let hopUp: Animation = .spring(response: 0.22, dampingFraction: 0.7)
    static let hopDown: Animation = .spring(response: 0.32, dampingFraction: 0.5)
    /// クリアで 1 匹ずつずらす間（秒）。
    static let hopStagger: Double = 0.08
    /// 赤い × が付いた瞬間に揺れる位置（マスの幅に対する割合の係数。0 で止まる）。
    static let shakePhases: [CGFloat] = [0, -1, 1, -0.6, 0.6, 0]
    /// 揺れの 1 コマ。
    static let shakeStep: Animation = .linear(duration: 0.05)

    /// 猫の出入り。Reduce Motion のときは透明度だけ（アニメーションは周囲のトランザクションに従う＝即時）。
    static func catTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let rest = CatPopModifier(scale: 1, degrees: 0, opacity: 1)
        return .asymmetric(
            insertion: AnyTransition.modifier(active: CatPopModifier(scale: 0.25, degrees: -18, opacity: 0), identity: rest)
                .gameAnimation(appear, reduceMotion: reduceMotion),
            removal: AnyTransition.modifier(active: CatPopModifier(scale: 0.6, degrees: 0, opacity: 0), identity: rest)
                .gameAnimation(vanish, reduceMotion: reduceMotion)
        )
    }
}

/// 出入りの途中の姿（大きさ・傾き・透明度）。静止画のコマ出し（`CatPuzzleRenderTests`）でも使う。
struct CatPopModifier: ViewModifier {
    var scale: CGFloat
    var degrees: Double
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .rotationEffect(.degrees(degrees))
            .opacity(opacity)
    }
}
