import SwiftUI
import Core
import HomerunCore

/// 上から見た扇（本塁が下・中堅が上）に打球を置く（`34-result-spray` の簡易版）。
/// ★ 柵越え・● 当たり（teal）・● 直撃（coral）・F ファウル・× 空振り。番号は球の順。
///
/// 部品は `Canvas` 1 枚に描く（`Shape` を `ZStack` に積むと iOS で図案が潰れる）。
struct HomerunSprayChart: View {
    let balls: [HomerunBattedBall]
    /// 番号を振るか（1 球の結果の小さな扇では振らない）。
    var numbered = true

    var body: some View {
        Canvas { ctx, size in
            // 扇は ±45° で、横幅は半径 × 2 sin45°・高さは半径（+ 中堅の柵の張り出し）。
            let radius = min(size.width / (2 * sin(.pi / 4) * 1.02), size.height / 1.08)
            let home = CGPoint(x: size.width / 2, y: size.height - 6)
            func map(_ p: CGPoint) -> CGPoint { CGPoint(x: home.x + p.x * radius, y: home.y + p.y * radius) }

            // 芝（柵までの扇）。
            var field = Path()
            field.move(to: home)
            for deg in stride(from: -45.0, through: 45.0, by: 3) {
                field.addLine(to: map(HomerunSprayGeometry.point(direction: deg, distance: HomerunJudge.fence(atDirection: deg))))
            }
            field.closeSubpath()
            ctx.fill(field, with: .color(Theme.Fill.teal.opacity(0.18)))

            // 柵。
            var fence = Path()
            for (i, deg) in stride(from: -45.0, through: 45.0, by: 3).enumerated() {
                let p = map(HomerunSprayGeometry.point(direction: deg, distance: HomerunJudge.fence(atDirection: deg)))
                if i == 0 { fence.move(to: p) } else { fence.addLine(to: p) }
            }
            ctx.stroke(fence, with: .color(Theme.teal), lineWidth: 2.5)

            // ファウルライン。
            for deg in [-45.0, 45.0] {
                var line = Path()
                line.move(to: home)
                line.addLine(to: map(HomerunSprayGeometry.point(direction: deg, distance: 100)))
                ctx.stroke(line, with: .color(Theme.inkSub), lineWidth: 1.5)
            }

            // 内野（ダイヤモンド）。
            var diamond = Path()
            let base = 27.4
            diamond.move(to: home)
            diamond.addLine(to: map(HomerunSprayGeometry.point(direction: 45, distance: base)))
            diamond.addLine(to: map(HomerunSprayGeometry.point(direction: 0, distance: base * sqrt(2))))
            diamond.addLine(to: map(HomerunSprayGeometry.point(direction: -45, distance: base)))
            diamond.closeSubpath()
            ctx.stroke(diamond, with: .color(Theme.inkSub.opacity(0.6)), lineWidth: 1)

            // 柵の距離。
            if numbered {
                for (deg, label) in [(-45.0, "100"), (0.0, "122"), (45.0, "100")] {
                    let p = map(HomerunSprayGeometry.point(direction: deg, distance: HomerunJudge.fence(atDirection: deg) + 9))
                    ctx.draw(Text(verbatim: label).font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSub), at: p)
                }
            }

            // 打球。
            for (index, ball) in balls.enumerated() {
                let p = map(HomerunSprayGeometry.mark(for: ball))
                switch ball.kind {
                case .homer:
                    ctx.draw(Text(verbatim: "★").font(.system(size: 18, weight: .black)).foregroundStyle(Theme.yellow), at: p)
                case .inPlay, .fenceHit:
                    let r = 5.5
                    let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    ctx.fill(dot, with: .color(ball.kind == .fenceHit ? Theme.coral : Theme.teal))
                    ctx.stroke(dot, with: .color(.white), lineWidth: 1.5)
                case .foul:
                    ctx.draw(Text(verbatim: "F").font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.inkSub), at: p)
                case .miss:
                    ctx.draw(Text(verbatim: "×").font(.system(size: 14, weight: .black))
                        .foregroundStyle(Theme.inkSub), at: CGPoint(x: p.x, y: p.y - 8))
                }
                if numbered {
                    ctx.draw(Text(verbatim: "\(index + 1)").font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink), at: CGPoint(x: p.x + 10, y: p.y - 9))
                }
            }
        }
    }
}
