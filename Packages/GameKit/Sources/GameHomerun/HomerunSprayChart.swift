import SwiftUI
import Core
import HomerunCore

/// 上から見た扇（本塁が下・中堅が上）に打球を置く（`34-result-spray` の簡易版）。
/// ★ 柵越え・● 当たり（teal）・● 直撃（coral）・F ファウル・× 空振り。番号は球の順。
/// 縮尺は最大飛距離（180m）まで入る固定（#1676）。柵の外にスタンド（柵〜場外の線）を薄く敷き、場外の線を点線で引く。
///
/// 部品は `Canvas` 1 枚に描く（`Shape` を `ZStack` に積むと iOS で図案が潰れる）。
struct HomerunSprayChart: View {
    let balls: [HomerunBattedBall]
    /// 番号を振るか（1 球の結果の小さな扇では振らない）。
    var numbered = true

    var body: some View {
        Canvas { ctx, size in
            // 扇は ±45°・半径 180m。★（18pt）と番号の札が縁で切れない余白を残す。
            let layout = HomerunSprayGeometry.layout(in: size, inset: numbered ? 16 : 10)
            let home = layout.home
            func map(_ p: CGPoint) -> CGPoint { layout.map(p) }
            let degrees = Array(stride(from: -45.0, through: 45.0, by: 3))
            func arc(_ meters: (Double) -> Double) -> [CGPoint] {
                degrees.map { map(HomerunSprayGeometry.point(direction: $0, distance: meters($0))) }
            }
            let fenceArc = arc(HomerunJudge.fence(atDirection:))
            // 場外の線（スタンドの最後列の後端）。球場の 3D・場外の判定と同じ定数（`HomerunBallChase.outOfParkDistance`）。
            let outArc = arc(HomerunBallChase.outOfParkDistance(atDirection:))

            // スタンド（柵〜場外の線）。
            // `addLines` は部分パスを新しく始めるので、続けてつなぐ所は `addLine` で足す。
            var stand = Path()
            stand.addLines(fenceArc)
            outArc.reversed().forEach { stand.addLine(to: $0) }
            stand.closeSubpath()
            ctx.fill(stand, with: .color(Theme.inkSub.opacity(0.14)))
            var outLine = Path()
            outLine.addLines(outArc)
            ctx.stroke(outLine, with: .color(Theme.inkSub.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))

            // 芝（柵までの扇）。
            var field = Path()
            field.move(to: home)
            fenceArc.forEach { field.addLine(to: $0) }
            field.closeSubpath()
            ctx.fill(field, with: .color(Theme.Fill.teal.opacity(0.18)))

            // 柵。
            var fence = Path()
            fence.addLines(fenceArc)
            ctx.stroke(fence, with: .color(Theme.teal), lineWidth: 2.5)

            // ファウルライン（スタンドの後端まで）。
            for deg in [-45.0, 45.0] {
                var line = Path()
                line.move(to: home)
                line.addLine(to: map(HomerunSprayGeometry.point(direction: deg,
                                                                 distance: HomerunBallChase.outOfParkDistance(atDirection: deg))))
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

            // 柵の距離と「場外」（場外の線の外）。
            if numbered {
                for (deg, label) in [(-45.0, "100"), (0.0, "122"), (45.0, "100")] {
                    let p = map(HomerunSprayGeometry.point(direction: deg, distance: HomerunJudge.fence(atDirection: deg) + 9))
                    ctx.draw(Text(verbatim: label).font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSub), at: p)
                }
                let outLabel = map(HomerunSprayGeometry.point(direction: -22, distance: HomerunBallChase.outOfParkDistance(atDirection: -22) + 8))
                ctx.draw(Text(verbatim: "場外").font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub), at: outLabel)
            }

            // 打球。
            let marks = balls.map { ball -> CGPoint in
                let p = map(HomerunSprayGeometry.mark(for: ball))
                return ball.kind == .miss ? CGPoint(x: p.x, y: p.y - 8) : p
            }
            let labels = HomerunSprayGeometry.labelCenters(for: marks)
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
                        .foregroundStyle(Theme.ink), at: labels[index])
                }
            }
        }
    }
}
