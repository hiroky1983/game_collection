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
    /// 実際に使われている箱（`RunnerHazardKind.bird` の**帯** ≒ 13〜17.34 × 1 タイル幅）。
    /// **帯の高さは絵から決まる**ので、ここでも絵の側（`bandHeight`）を基準に置く。
    private static let width = RunnerRules.tileWidth
    private static let groundDrop = RunnerHazardKind.bird.bottom
    private static let art = RunnerBirdArt(width: width, groundDrop: groundDrop)
    private static let height = art.bandHeight
    private static let epsilon = 1e-9

    /// 影の下端（地面に敷けているかを見る唯一の値）。
    private static func shadowBottom(of art: RunnerBirdArt) -> Double {
        Double(art.shadowCenter.y) - Double(art.shadowSize.height) / 2
    }

    @Test("絵の水平方向の張り出しが 0（箱の幅ちょうどに収まる）")
    func horizontalExtentMatchesHitbox() {
        let extent = Self.art.horizontalExtent
        #expect(abs(extent.lowerBound - 0) < Self.epsilon)
        #expect(abs(extent.upperBound - Self.width) < Self.epsilon)
    }

    /// 縦は**絵と帯がぴったり一致する**こと（#671・会長決裁 2026-09-12）。
    ///
    /// - 床（13）は「接地してくぐれる／跳ぶと当たる」の境目そのもの。ここに絵の無いすき間を
    ///   残すと「鳥の下を通ったのに当たった」になる
    /// - 天井は絵の頂点（浮遊の上端）に一致させる。**上に絵の無い帯を残すと「見えている鳥を
    ///   跳び越したのに当たる」**（#609 で潰した理不尽の再発）。決裁値 22 を下げたのはこれが理由で、
    ///   ここが旧 `verticalExtentReachesCeiling` の役目を引き継ぐ
    @Test("絵の下端が帯の床、上端が帯の天井にちょうど一致する")
    func verticalExtentFillsTheBand() {
        let extent = Self.art.birdVerticalExtent
        #expect(abs(extent.lowerBound - 0) < Self.epsilon, "絵の底が帯の床から浮いている")
        #expect(abs(extent.upperBound - Self.height) < Self.epsilon, "絵の頂点が帯の天井とズレている")
        // 当たり判定そのものと突き合わせる（`bandHeight` を使う側が取り違えていないこと）。
        let band = RunnerHazardKind.bird.height - RunnerHazardKind.bird.bottom
        #expect(abs(extent.upperBound - band) < Self.epsilon, "帯の上端が絵の頂点から外れている")
        // 影は帯の外——地面（y = -groundDrop）に敷く。**影の下端そのもの**を見る:
        // `verticalExtent` は鳥と影の合併なので、下端が負というだけなら影を地面から
        // 大きく浮かせても通ってしまう（体とのすき間は「飛んでいる」の手がかりになる）。
        let shadowBottom = Self.shadowBottom(of: Self.art)
        #expect(shadowBottom >= -Self.groundDrop - Self.epsilon)
        #expect(
            shadowBottom <= -Self.groundDrop + 0.1,
            "影が地面まで降りていない（体とのすき間が『飛んでいる』の手がかり）"
        )
    }

    @Test("はみ出しをパーツごとに見る（丸・多角形・影のすべて）")
    func eachStaticPartStaysInsideTheBox() {
        let art = Self.art
        let box = 0.0...Self.width

        func expectInside(_ value: Double, _ label: Comment) {
            #expect(value >= box.lowerBound - Self.epsilon, label)
            #expect(value <= box.upperBound + Self.epsilon, label)
        }

        for (index, disc) in art.discs.enumerated() {
            expectInside(Double(disc.center.x) - disc.radius, "丸 \(index) の後端")
            expectInside(Double(disc.center.x) + disc.radius, "丸 \(index) の前端")
        }
        for (index, part) in art.fixedParts.enumerated() {
            for point in part.points {
                expectInside(Double(part.anchor.x) + Double(point.x), "多角形 \(index)")
            }
        }
        expectInside(Double(art.shadowCenter.x) - Double(art.shadowSize.width) / 2, "影の後端")
        expectInside(Double(art.shadowCenter.x) + Double(art.shadowSize.width) / 2, "影の前端")
    }

    /// `addBird` が描くパーツの全量。**ここに載っていないパーツは張り出しを測られない**
    /// （腹・目・足が測定の網から漏れていたのを PR #633 の敵対的検証が見つけた）。
    /// `addBird` はこの一覧の値だけを使って描くので、数が合わなくなったら
    /// どちらかに片付け忘れがある。
    @Test("測定対象のパーツが、描いているパーツを漏れなく覆っている")
    func partInventoryCoversEverythingDrawn() {
        let art = Self.art
        // 丸: 胴・頭・腹・白目・黒目
        #expect(art.discs.count == 5)
        // 多角形（回らない）: くちばし・尾羽2枚
        #expect(art.fixedParts.count == 3)
        // 回る: 奥の翼・手前の翼・足
        #expect(art.rotatingParts.count == 3)
        // 残るのは影 1 枚だけで、これは `horizontalExtent` / `verticalExtent` が直接足す。
        #expect(art.shadowSize.width > 0)
    }

    @Test("羽ばたきの振り切ったところでも翼・足が箱を出ない")
    func wingsStayInsideThroughTheWholeFlap() {
        for (label, wing) in Self.art.rotatingParts.enumerated().map({ ("回るパーツ \($0)", $1) }) {
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

    /// 箱の幅を変えても、絵は幅ちょうどいっぱい・帯の床合わせのまま（比率で組んである）。
    /// 縦は入力ではなく結果（`bandHeight`）なので、**幅に比例して帯も伸びる**ことを見る。
    @Test("箱の幅を変えても張り出しは 0 のまま（比率で組んである）")
    func extentFollowsAnyHitboxSize() {
        var previousBand = 0.0
        for width in [4.0, 6.0, 8.0] {
            for groundDrop in [0.0, 13.0] {
                let art = RunnerBirdArt(width: width, groundDrop: groundDrop)
                #expect(abs(art.horizontalExtent.lowerBound) < Self.epsilon)
                #expect(abs(art.horizontalExtent.upperBound - width) < Self.epsilon)
                #expect(abs(art.birdVerticalExtent.lowerBound) < Self.epsilon)
                #expect(abs(art.birdVerticalExtent.upperBound - art.bandHeight) < Self.epsilon)
                #expect(art.bandHeight > 0)
                let shadowBottom = Self.shadowBottom(of: art)
                #expect(shadowBottom >= -groundDrop - Self.epsilon)
                #expect(shadowBottom <= -groundDrop + 0.1)
            }
            let band = RunnerBirdArt(width: width).bandHeight
            #expect(band > previousBand, "幅を広げたのに帯が高くならない（幅 \(width)）")
            previousBand = band
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

    /// 絵を合わせる相手（帯）が、全ステージの鳥で同じ 1 タイル幅 × 13〜絵の頂点であること。
    /// ここがステージごとに違うと `art` 1 つで張り出しを測っている意味が無くなる
    /// ——帯の上端は**幅 1 タイルの絵**から導いているので、幅の違う鳥が混ざると
    /// その鳥だけ絵と帯がズレる。
    @Test("鳥の箱は 1 タイル幅 × 帯 13〜絵の頂点")
    func hitboxIsTheBand() {
        #expect(RunnerHazardKind.bird.bottom == 13, "くぐれる側の縁（本質）は #622 D案の決裁値のまま")
        #expect(
            RunnerHazardKind.bird.height == 13 + Self.art.bandHeight,
            "帯の上端が絵の頂点から外れている"
        )
        // 単発ジャンプでは足が上端を越えられない＝跳べば必ず当たる（帯を下げても崩れない条件）。
        #expect(RunnerRules.jumpApex < RunnerHazardKind.bird.height)
        let birds = RunnerStage.all.flatMap { $0.hazards }.filter { $0.kind == .bird }
        #expect(!birds.isEmpty)
        for bird in birds {
            #expect(bird.length == RunnerRules.tileWidth)
            #expect(bird.bottom == 13)
            #expect(bird.height == RunnerHazardKind.bird.height)
        }
    }
}
