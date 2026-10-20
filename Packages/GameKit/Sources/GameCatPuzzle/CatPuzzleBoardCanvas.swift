import SwiftUI
import Core

/// 盤の絵（家の間取り・印・猫）。本番と遊び方の図で同じものを使う（#2250）。
///
/// 1 マスずつ床の色と柄を塗り、部屋の境目に太い壁を引き、部屋の左上に名前の札を置く。
/// 猫・×・ヒント・矛盾の印はこの上に描く。読み上げと操作は `CatPuzzleView` の透明なマスが担う
/// （この絵は `accessibilityHidden`）。
struct CatPuzzleBoardCanvas: View {
    let puzzle: CatPuzzle
    let marks: [CatPuzzleModel.Mark]
    let conflicts: Set<Int>
    var hintCell: Int? = nil
    var isSolved = false
    let cellSide: CGFloat

    /// 外周の壁の太さ。
    private var borderWidth: CGFloat { CatPuzzleHouse.wallWidth * 1.5 }

    var body: some View {
        let n = puzzle.side
        let boardSide = cellSide * CGFloat(n)
        let rooms = (0..<n).map { CatPuzzleHouse.room($0) }
        Canvas { context, _ in
            drawFloors(&context, rooms: rooms)
            drawGrid(&context)
            drawMarks(&context, rooms: rooms)
            drawWalls(&context)
            drawLabels(&context, rooms: rooms)
            drawHint(&context)
        }
        .frame(width: boardSide, height: boardSide)
        .accessibilityHidden(true)
    }

    // MARK: - 部品

    private func rect(of cell: Int) -> CGRect {
        let n = puzzle.side
        return CGRect(x: CGFloat(cell % n) * cellSide, y: CGFloat(cell / n) * cellSide, width: cellSide, height: cellSide)
    }

    private func drawFloors(_ context: inout GraphicsContext, rooms: [CatPuzzleHouse.Room]) {
        for cell in 0..<puzzle.cellCount {
            let room = rooms[puzzle.rooms[cell] % rooms.count]
            let r = rect(of: cell)
            context.fill(Path(r), with: .color(room.tint))
            CatPuzzleFloorPainter.draw(room.floor, in: r, strength: room.patternStrength, context: &context, ink: Theme.ink)
        }
    }

    /// 部屋の中のマス目（薄い線）。
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
        context.stroke(path, with: .color(Theme.ink.opacity(0.14)), lineWidth: CatPuzzleHouse.gridWidth)
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

    /// 部屋の名前の札。部屋のいちばん上・左のマスの左上に置く。
    private func drawLabels(_ context: inout GraphicsContext, rooms: [CatPuzzleHouse.Room]) {
        let n = puzzle.side
        let fontSize = max(8, cellSide * 0.22)
        for room in 0..<n {
            guard let first = puzzle.rooms.firstIndex(of: room) else { continue }
            let name = rooms[room % rooms.count].name
            let text = context.resolve(
                Text(name)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded)) // fixed-size: 盤のマスの寸法に比例させる札の文字（図形のジオメトリに従う）
                    .foregroundColor(Theme.Fixed.ink)
            )
            let measured = text.measure(in: CGSize(width: cellSide * 2.4, height: cellSide))
            let padding = CGSize(width: cellSide * 0.1, height: cellSide * 0.04)
            let origin = rect(of: first).origin.applying(.init(translationX: cellSide * 0.06, y: cellSide * 0.06))
            let chip = CGRect(x: origin.x, y: origin.y,
                              width: measured.width + padding.width * 2, height: measured.height + padding.height * 2)
            context.fill(Path(roundedRect: chip, cornerRadius: chip.height / 2), with: .color(.white.opacity(0.9)))
            context.draw(text, at: CGPoint(x: chip.minX + padding.width, y: chip.minY + padding.height), anchor: .topLeading)
        }
    }

    /// ×・猫・矛盾・ヒント。クリア後は部屋ごとのくつろぐ姿に替える。
    private func drawMarks(_ context: inout GraphicsContext, rooms: [CatPuzzleHouse.Room]) {
        let boardRect = CGRect(x: 0, y: 0, width: cellSide * CGFloat(puzzle.side), height: cellSide * CGFloat(puzzle.side))
        for cell in 0..<puzzle.cellCount {
            let r = rect(of: cell)
            switch marks[cell] {
            case .empty:
                break
            case .cross:
                guard !isSolved else { break }
                var cross = Path()
                let arm = cellSide * 0.16
                cross.move(to: CGPoint(x: r.midX - arm, y: r.midY - arm))
                cross.addLine(to: CGPoint(x: r.midX + arm, y: r.midY + arm))
                cross.move(to: CGPoint(x: r.midX + arm, y: r.midY - arm))
                cross.addLine(to: CGPoint(x: r.midX - arm, y: r.midY + arm))
                context.stroke(cross, with: .color(Theme.inkSub.opacity(0.75)),
                               style: StrokeStyle(lineWidth: max(2, cellSide * 0.07), lineCap: .round))
            case .cat:
                if isSolved {
                    let pose = rooms[puzzle.rooms[cell] % rooms.count].clearPose
                    var target = CatPuzzleArt.fitted(pose, in: r.insetBy(dx: -cellSide * 0.12, dy: -cellSide * 0.12))
                    // 盤の外にはみ出さない。
                    target.origin.x = min(max(target.minX, boardRect.minX), boardRect.maxX - target.width)
                    target.origin.y = min(max(target.minY, boardRect.minY), boardRect.maxY - target.height)
                    drawCat(pose, in: target, context: &context)
                } else {
                    drawCat(.faceNormal, in: CatPuzzleArt.fitted(.faceNormal, in: r.insetBy(dx: cellSide * 0.08, dy: cellSide * 0.08)), context: &context)
                    if conflicts.contains(cell) {
                        // 色（赤い面）と印（「！」の丸）の両方で示す。
                        context.fill(Path(r), with: .color(Theme.coral.opacity(0.28)))
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
            }
        }
    }

    /// ヒントのマス（黄色の点線の枠）。札や壁の上に描く。
    private func drawHint(_ context: inout GraphicsContext) {
        guard let hintCell, !isSolved, marks.indices.contains(hintCell) else { return }
        let inset = CatPuzzleHouse.wallWidth
        context.stroke(Path(roundedRect: rect(of: hintCell).insetBy(dx: inset, dy: inset), cornerRadius: cellSide * 0.12),
                       with: .color(Theme.yellow),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 4]))
    }

    private func drawCat(_ pose: CatPuzzleArt.Pose, in rect: CGRect, context: inout GraphicsContext) {
        if let cg = CatPuzzleArt.cgImage(pose) {
            context.draw(Image(decorative: cg, scale: 1), in: rect)
        } else {
            let symbol = context.resolve(Image(systemName: "cat.fill"))
            context.draw(symbol, in: rect.insetBy(dx: rect.width * 0.15, dy: rect.height * 0.15))
        }
    }
}
