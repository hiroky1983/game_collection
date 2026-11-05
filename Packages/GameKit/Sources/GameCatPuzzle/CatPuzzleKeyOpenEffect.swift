import Core
import SwiftUI

/// 鍵が開いた瞬間の盤の演出（#3330）。鍵の猫のマスから波紋が広がり、鍵の部屋の外の覆いと金色の枠が
/// 外側へ向かって順に消え、鍵の猫に小さな光（キラッ）が走る。
///
/// 盤の `Canvas` は鍵が開いた時点で覆いも枠も描かなくなるので、この層が「閉じていた間の見た目」を
/// 進み具合に合わせて薄めながら描き足す。操作は止めない（`allowsHitTesting(false)`）。図形だけで、
/// `Canvas` に `Text` は描かない。Reduce Motion のときは波紋・光を使わず、覆いと枠が一様に薄れるだけ。
struct CatPuzzleKeyOpenEffect: View {
    let puzzle: CatPuzzle
    let keyRoom: Int
    let keyCat: Int?
    let cellSide: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// 演出の長さ（波紋・光・札の鍵が終わるまで）。
    static let duration: Duration = .milliseconds(1000)
    static let seconds: Double = 1.0
    /// 波紋が盤の端へ着くまでの割合（残りは覆いの薄れ切るまでの余韻）。
    static let waveSpan: Double = 0.7

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: false)) { timeline in
            let t = min(1, max(0, timeline.date.timeIntervalSince(start) / Self.seconds))
            Canvas { context, _ in
                drawVeil(&context, t: t)
                drawFrame(&context, t: t)
                if !reduceMotion { drawSparkle(&context, t: t) }
            }
        }
        .frame(width: cellSide * CGFloat(puzzle.side), height: cellSide * CGFloat(puzzle.side))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - 進み具合（純粋な計算。テストで固定する）

    /// 覆いの濃さ（1 = 鍵が閉じていた間と同じ、0 = 消えた）。`distance` は鍵の猫からの距離を盤の対角で割った 0...1。
    /// 通常は近いマスから順に消え（波紋）、Reduce Motion では距離に依らず一様に薄れる。
    static func veilAmount(distance: Double, t: Double, reduceMotion: Bool) -> Double {
        if reduceMotion { return 1 - clamp(t / 0.6) }
        let arrival = distance * waveSpan
        return 1 - clamp((t - arrival) / 0.3)
    }

    /// 波の先頭（金色の輪）の半径を盤の対角に対する割合で。まだ出ない・もう消えたときは nil。
    static func ringProgress(t: Double) -> Double? {
        let p = t / waveSpan
        return (0..<1).contains(p) ? p : nil
    }

    /// 光の大きさ（0...1...0）。鍵の猫に t = 0.1〜0.6 の間だけ。
    static func sparkleAmount(t: Double) -> Double {
        let p = clamp((t - 0.1) / 0.5)
        return p <= 0 || p >= 1 ? 0 : sin(p * .pi)
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

    // MARK: - 描画

    private var origin: CGPoint {
        let n = puzzle.side
        let cell = keyCat ?? puzzle.cells(inRoom: keyRoom).first ?? 0
        let r = CatPuzzleBoardCanvas.rect(of: cell, side: n, cellSide: cellSide)
        return CGPoint(x: r.midX, y: r.midY)
    }

    private var diagonal: Double { Double(cellSide) * Double(puzzle.side) * 2.0.squareRoot() }

    private func drawVeil(_ context: inout GraphicsContext, t: Double) {
        let n = puzzle.side
        let o = origin
        for cell in 0..<puzzle.cellCount where puzzle.rooms[cell] != keyRoom {
            let r = CatPuzzleBoardCanvas.rect(of: cell, side: n, cellSide: cellSide)
            let d = hypot(Double(r.midX - o.x), Double(r.midY - o.y)) / diagonal
            let amount = Self.veilAmount(distance: d, t: t, reduceMotion: reduceMotion)
            guard amount > 0 else { continue }
            context.fill(Path(r), with: .color(Theme.surface.opacity(0.6 * amount)))
        }
        // 波の先頭に金色の輪（盤の外へはみ出さない。盤の `clipShape` が切る）。
        if !reduceMotion, let p = Self.ringProgress(t: t) {
            let radius = CGFloat(p * diagonal)
            let ring = Path(ellipseIn: CGRect(x: o.x - radius, y: o.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(ring, with: .color(Theme.yellow.opacity(0.8 * (1 - p))), lineWidth: max(2, cellSide * 0.08))
        }
    }

    private func drawFrame(_ context: inout GraphicsContext, t: Double) {
        let alpha = 1 - min(1, t / 0.5)
        guard alpha > 0 else { return }
        let outline = CatPuzzleBoardCanvas.outline(of: Set(puzzle.cells(inRoom: keyRoom)), side: puzzle.side, cellSide: cellSide)
        context.stroke(outline, with: .color(Theme.yellow.opacity(alpha)), style: StrokeStyle(lineWidth: max(3, cellSide * 0.1), lineCap: .square))
    }

    /// 鍵の猫の上で 4 つ尖りの星が膨らんで消える。
    private func drawSparkle(_ context: inout GraphicsContext, t: Double) {
        let a = Self.sparkleAmount(t: t)
        guard a > 0, keyCat != nil else { return }
        let o = origin
        let c = cellSide
        for (dx, dy, scale) in [(0.22, -0.22, 1.0), (-0.26, -0.05, 0.6), (0.1, 0.25, 0.5)] as [(Double, Double, Double)] {
            let center = CGPoint(x: o.x + c * dx, y: o.y + c * dy)
            let long = c * 0.3 * a * scale, short = long * 0.22
            var star = Path()
            star.move(to: CGPoint(x: center.x, y: center.y - long))
            star.addLine(to: CGPoint(x: center.x + short, y: center.y - short))
            star.addLine(to: CGPoint(x: center.x + long, y: center.y))
            star.addLine(to: CGPoint(x: center.x + short, y: center.y + short))
            star.addLine(to: CGPoint(x: center.x, y: center.y + long))
            star.addLine(to: CGPoint(x: center.x - short, y: center.y + short))
            star.addLine(to: CGPoint(x: center.x - long, y: center.y))
            star.addLine(to: CGPoint(x: center.x - short, y: center.y - short))
            star.closeSubpath()
            context.fill(star, with: .color(Theme.yellow))
            context.stroke(star, with: .color(.white), lineWidth: max(1, c * 0.02))
        }
    }
}

/// 鍵の部屋の札の鍵アイコン。鍵が開いた演出の間は、閉じた錠前が回りながら開いた錠前になる（はね返る）。
/// Reduce Motion のときは回さず、入れ替わりを透明度だけで見せる。
struct CatPuzzleKeyLabelIcon: View {
    let size: CGFloat
    let opening: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened = false

    var body: some View {
        ZStack {
            if opening {
                Image(systemName: "lock.fill")
                    .opacity(opened ? 0 : 1)
                Image(systemName: "lock.open.fill")
                    .opacity(opened ? 1 : 0)
                    .rotationEffect(.degrees(opened || reduceMotion ? 0 : -35))
                    .scaleEffect(opened || reduceMotion ? 1 : 0.7)
            } else {
                Image(systemName: "key.fill")
            }
        }
        .font(.system(size: size, weight: .bold)) // fixed-size: 盤のマスの寸法に比例させる札の鍵（文字と同じ扱い）
        .foregroundColor(Theme.yellowText)
        .frame(width: ceil(size), alignment: .center)
        .onChange(of: opening, initial: true) {
            guard opening else { opened = false; return }
            opened = false
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.3)) { opened = true }
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.35)) { opened = true }
            }
        }
    }
}
