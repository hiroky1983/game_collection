import SwiftUI
import Core

/// ホイール（#1318）。**Canvas 1 枚**で描く（Shape を ZStack に積むと iOS で図案が潰れるため）。
///
/// ポケット 0 が回転 0 のとき 12 時にあり、`rotation` だけ時計回りに回した状態を描く。
/// 玉は回らず 12 時に留まり、ホイールが止まったとき玉の真下にあるポケットが出目になる
/// （どのポケットを真下へ持ってくるかは `RouletteMotion.targetRotation` が決める）。
struct RouletteWheelView: View {
    /// ホイールの回転角（度・時計回り）。
    let rotation: Double
    /// 縁取りで強調するポケットの数字（精算後の出目）。nil なら強調しない。
    let highlighted: Int?

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                Self.drawWheel(in: ctx, size: size, highlighted: highlighted)
            }
            .rotationEffect(.degrees(rotation))
            Canvas { ctx, size in
                Self.drawBall(in: ctx, size: size)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    /// ポケット環の外側・内側の半径（直径に対する比）。
    static let pocketOuterRatio: CGFloat = 0.92
    static let pocketInnerRatio: CGFloat = 0.58

    private static func drawWheel(in ctx: GraphicsContext, size: CGSize, highlighted: Int?) {
        let radius = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let step = RouletteMotion.pocketStep
        let pocketOuter = radius * pocketOuterRatio
        let pocketInner = radius * pocketInnerRatio

        // 外枠。ポケットの黒（`fillStrong`）と見分けがつくよう、くすんだ色にする。
        ctx.fill(circle(center: center, radius: radius), with: .color(Theme.fillMuted))

        for (index, number) in RouletteWheel.pocketOrder.enumerated() {
            let path = pocket(index: index, center: center, outer: pocketOuter, inner: pocketInner, step: step)
            ctx.fill(path, with: .color(fill(for: number)))
            ctx.stroke(path, with: .color(Theme.surface.opacity(0.7)), lineWidth: 0.6)

            // 数字は各ポケットの中心へ、ポケットの向きに回して置く。
            var layer = ctx
            layer.translateBy(x: center.x, y: center.y)
            layer.rotate(by: .degrees(Double(index) * step))
            let text = Text(verbatim: "\(number)")
                .font(.system(size: radius * 0.11, weight: .bold, design: .rounded))
                .foregroundStyle(textColor(for: number))
            layer.draw(text, at: CGPoint(x: 0, y: -(pocketInner + pocketOuter) / 2), anchor: .center)
        }

        if let highlighted, let index = RouletteWheel.pocketOrder.firstIndex(of: highlighted) {
            let path = pocket(index: index, center: center, outer: pocketOuter, inner: pocketInner, step: step)
            ctx.stroke(path, with: .color(Theme.yellow), lineWidth: 2.5)
        }

        // 中心のハブ。
        ctx.fill(circle(center: center, radius: pocketInner * 0.92), with: .color(Theme.surface))
        ctx.fill(circle(center: center, radius: pocketInner * 0.38), with: .color(Theme.yellow))
        ctx.fill(circle(center: center, radius: pocketInner * 0.12), with: .color(Theme.fillStrong))
    }

    /// 玉。ポケット環の中ほど・12 時の位置に置く。
    private static func drawBall(in ctx: GraphicsContext, size: CGSize) {
        let radius = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ballRadius = radius * 0.055
        let ballCenter = CGPoint(x: center.x, y: center.y - radius * (pocketOuterRatio + pocketInnerRatio) / 2)
        ctx.fill(circle(center: ballCenter, radius: ballRadius), with: .color(.white))
        ctx.stroke(circle(center: ballCenter, radius: ballRadius), with: .color(Theme.fillStrong), lineWidth: 1)
    }

    private static func circle(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// `index` 番目のポケットの扇形。回転 0 で 0 番が 12 時（-90 度）に来る。
    private static func pocket(index: Int, center: CGPoint, outer: CGFloat, inner: CGFloat, step: Double) -> Path {
        let centerDegrees = -90 + Double(index) * step
        let start = Angle.degrees(centerDegrees - step / 2)
        let end = Angle.degrees(centerDegrees + step / 2)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }

    /// ポケットと盤面のマスで共通の面色。赤黒緑は実物の色そのものではなく、アプリの配色で置き換える
    /// （特定のカジノ・既存アプリの意匠を写さない）。
    static func fill(for number: Int) -> Color {
        switch RouletteWheel.color(of: number) {
        case .red:   return Theme.Fill.coral
        case .black: return Theme.fillStrong
        case .green: return Theme.Fill.teal
        }
    }

    /// 面色の上に載せる文字色。黒（濃い面）には白、差し色の面には `Theme.onAccent`。
    static func textColor(for number: Int) -> Color {
        RouletteWheel.color(of: number) == .black ? .white : Theme.onAccent
    }
}
