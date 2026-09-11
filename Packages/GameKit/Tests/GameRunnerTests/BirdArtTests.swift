import CoreGraphics
import Foundation
import Testing
@testable import GameRunner

/// 鳥の絵が当たり判定の矩形からはみ出していないことの検証（#609）。
///
/// `SKScene` はここでも生成しない。`RunnerBirdArt` が SpriteKit から独立した値なので、
/// 羽ばたき・浮遊の端まで含めた張り出しをシミュレータ抜きで測れる。
///
/// **ソース走査ではなく寸法の計算で見る。** パーツの座標を後から動かせば、その座標が
/// そのまま `horizontalExtent` / `verticalExtent` に出るので、この Suite が落ちる。
@Suite("鳥の絵と当たり判定の一致（#609）")
struct BirdArtTests {
    /// 実際に使われている箱（`RunnerHazardKind.bird` の高さ 7 × 1 タイル幅）。
    private static let width = RunnerRules.tileWidth
    private static let height = RunnerHazardKind.bird.height
    private static let art = RunnerBirdArt(width: width, height: height)
    private static let epsilon = 1e-9

    @Test("絵の水平方向の張り出しが 0（箱の幅ちょうどに収まる）")
    func horizontalExtentMatchesHitbox() {
        let extent = Self.art.horizontalExtent
        #expect(abs(extent.lowerBound - 0) < Self.epsilon)
        #expect(abs(extent.upperBound - Self.width) < Self.epsilon)
    }

    @Test("絵の上端が箱の天井に一致する（見えない当たり判定を上に残さない）")
    func verticalExtentReachesCeiling() {
        let extent = Self.art.verticalExtent
        #expect(abs(extent.upperBound - Self.height) < Self.epsilon)
        // 影は地面（y = 0）に敷くので、下端が地面より下へ潜らないことだけ見る。
        #expect(extent.lowerBound >= -Self.epsilon)
    }

    @Test("はみ出しをパーツごとに見る（胴・頭・くちばし・尾羽・影）")
    func eachStaticPartStaysInsideTheBox() {
        let art = Self.art
        let box = 0.0...Self.width

        func expectInside(_ value: Double, _ label: Comment) {
            #expect(value >= box.lowerBound - Self.epsilon, label)
            #expect(value <= box.upperBound + Self.epsilon, label)
        }

        expectInside(Double(art.bodyCenter.x) - art.bodyRadius, "胴の後端")
        expectInside(Double(art.bodyCenter.x) + art.bodyRadius, "胴の前端")
        expectInside(Double(art.headCenter.x) - art.headRadius, "頭の後端")
        expectInside(Double(art.headCenter.x) + art.headRadius, "頭の前端")
        for point in art.beak.points {
            expectInside(Double(art.beak.anchor.x) + Double(point.x), "くちばし")
        }
        for (index, tail) in art.tails.enumerated() {
            for point in tail.points {
                expectInside(Double(tail.anchor.x) + Double(point.x), "尾羽 \(index)")
            }
        }
        expectInside(Double(art.shadowCenter.x) - Double(art.shadowSize.width) / 2, "影の後端")
        expectInside(Double(art.shadowCenter.x) + Double(art.shadowSize.width) / 2, "影の前端")
    }

    @Test("羽ばたきの振り切ったところでも翼が箱を出ない")
    func wingsStayInsideThroughTheWholeFlap() {
        for (label, wing) in [("奥", Self.art.farWing), ("手前", Self.art.nearWing)] {
            // 回転の端だけでなく、その間も刻んで見る（端が最外周とは限らない）。
            let steps = 200
            for step in 0...steps {
                let ratio = Double(step) / Double(steps)
                let angle = wing.rotation.lowerBound
                    + (wing.rotation.upperBound - wing.rotation.lowerBound) * ratio
                for point in wing.points {
                    let x = Double(point.x) * cos(angle) - Double(point.y) * sin(angle)
                    let world = Double(wing.pivot.x) + x
                    #expect(world >= -Self.epsilon, "\(label)の翼が後端を越えた")
                    #expect(world <= Self.width + Self.epsilon, "\(label)の翼が前端を越えた")
                }
            }
        }
    }

    @Test("箱の縁まで使い切っている（無駄に小さくしていない）")
    func artFillsTheBox() {
        // くちばしの先端は前端ちょうど、翼か尾羽の先端は後端ちょうど。
        let art = Self.art
        let beakTip = art.beak.points.map { Double(art.beak.anchor.x) + Double($0.x) }.max() ?? 0
        #expect(abs(beakTip - Self.width) < Self.epsilon)

        let tailTip = art.tails
            .flatMap { tail in tail.points.map { Double(tail.anchor.x) + Double($0.x) } }
            .min() ?? .infinity
        let wingTip = Double(art.farWing.pivot.x)
            + RunnerBirdArt.rotatedXRange(art.farWing.points, art.farWing.rotation).lowerBound
        #expect(abs(min(tailTip, wingTip) - 0) < Self.epsilon)
    }

    @Test("箱の寸法を変えても張り出しは 0 のまま（比率で組んである）")
    func extentFollowsAnyHitboxSize() {
        for (width, height) in [(4.0, 7.0), (4.0, 5.0), (6.0, 7.0), (8.0, 12.0)] {
            let art = RunnerBirdArt(width: width, height: height)
            #expect(abs(art.horizontalExtent.lowerBound) < Self.epsilon)
            #expect(abs(art.horizontalExtent.upperBound - width) < Self.epsilon)
            #expect(abs(art.verticalExtent.upperBound - height) < Self.epsilon)
        }
    }

    @Test("回転の端を求める計算が、刻んで探した値と一致する")
    func rotatedRangeMatchesSampling() {
        let points = [
            CGPoint(x: 0, y: 0.35), CGPoint(x: -1.1, y: 0.65),
            CGPoint(x: -2.8, y: 0.3), CGPoint(x: -0.9, y: -0.45),
        ]
        for rotation in [-0.2...0.7, -0.55...0.55, 0.0...(2 * Double.pi), -3.0...3.0] {
            let computed = RunnerBirdArt.rotatedXRange(points, rotation)
            var sampledLow = Double.infinity, sampledHigh = -Double.infinity
            let steps = 20000
            for step in 0...steps {
                let ratio = Double(step) / Double(steps)
                let angle = rotation.lowerBound
                    + (rotation.upperBound - rotation.lowerBound) * ratio
                for point in points {
                    let x = Double(point.x) * cos(angle) - Double(point.y) * sin(angle)
                    sampledLow = min(sampledLow, x)
                    sampledHigh = max(sampledHigh, x)
                }
            }
            #expect(computed.lowerBound <= sampledLow + 1e-6)
            #expect(computed.upperBound >= sampledHigh - 1e-6)
            #expect(abs(computed.lowerBound - sampledLow) < 1e-3)
            #expect(abs(computed.upperBound - sampledHigh) < 1e-3)
        }
    }

    @Test("当たり判定そのものは変えていない（鳥の箱は 1 タイル幅 × 高さ 7）")
    func hitboxIsUnchanged() {
        #expect(RunnerHazardKind.bird.height == 7)
        let birds = RunnerStage.all.flatMap { $0.hazards }.filter { $0.kind == .bird }
        #expect(!birds.isEmpty)
        for bird in birds {
            #expect(bird.length == RunnerRules.tileWidth)
            #expect(bird.height == 7)
        }
    }
}
