import CoreGraphics
import Foundation
import Testing
@testable import GameRunner

/// 鳥の絵と当たり判定の関係の検証（#609 / #671 / #943）。
///
/// `SKScene` はここでも生成しない。`RunnerBirdArt` が SpriteKit から独立した値なので、
/// 羽ばたき・浮遊の端まで含めた張り出しをシミュレータ抜きで測れる。
///
/// **ソース走査ではなく寸法の計算で見る。** パーツの座標を後から動かせば、その座標が
/// そのまま `horizontalExtent` / `verticalExtent` に出るので、この Suite が落ちる。
///
/// 見ているのは 2 つの絵:
///
/// - **倍率 1 の絵**（`hitboxArt`）。当たり判定を導く側で、#609 の「張り出し 0」がそのまま成り立つ
///   （横は `0...width` ちょうど、縦は帯の床から `bandHeight` ちょうど）
/// - **実際に描く絵**（`drawnArt`。倍率 `RunnerBirdArt.defaultVisualScale`・#943）。当たり判定より
///   大きく、横は中央合わせで前後に等しく張り出し、縦は床合わせで上だけ張り出す。
///   **当たり判定が絵から出ることは無い**（張り出しは走者に甘い側だけ）
@Suite("鳥の絵と当たり判定の一致（#609）と見た目の倍率（#943）")
struct BirdArtTests {
    /// 実際に使われている箱（`RunnerHazardKind.bird` の**帯** ≒ 13〜17.34 × 1 タイル幅）。
    /// **帯の高さは絵から決まる**ので、ここでも絵の側（`bandHeight`）を基準に置く。
    private static let width = RunnerRules.tileWidth
    private static let groundDrop = RunnerHazardKind.bird.bottom
    /// 倍率 1 の絵（当たり判定を導く側）。
    private static let hitboxArt = RunnerBirdArt(width: width, groundDrop: groundDrop, visualScale: 1)
    /// 実際に描く絵（既定の倍率）。
    private static let drawnArt = RunnerBirdArt(width: width, groundDrop: groundDrop)
    private static let height = hitboxArt.bandHeight
    private static let epsilon = 1e-9
    /// 両方の絵を同じ観点で回すための一覧。
    private static var arts: [(label: String, art: RunnerBirdArt)] {
        [("倍率 1", hitboxArt), ("既定の倍率", drawnArt)]
    }

    /// 影の下端（地面に敷けているかを見る唯一の値）。
    private static func shadowBottom(of art: RunnerBirdArt) -> Double {
        Double(art.shadowCenter.y) - Double(art.shadowSize.height) / 2
    }

    /// 見た目の倍率は会長QA（2026-09-15「鳥が小さすぎて見えない」「おじさんと同じ位の大きさ」・#943）
    /// から 2.5（絵は 10 × 10.8 で走者の絵 11 × 11.9 と同じ位）。1 未満は当たり判定が絵から出る
    /// （#609 の理不尽）ので禁止。
    @Test("見た目の倍率は 2.5（#943）で、当たり判定より小さく描くことは無い")
    func visualScaleIsTheDecidedValue() {
        #expect(RunnerBirdArt.defaultVisualScale == 2.5)
        #expect(RunnerBirdArt.defaultVisualScale >= 1)
        #expect(Self.drawnArt.visualScale == RunnerBirdArt.defaultVisualScale)
        #expect(Self.hitboxArt.visualScale == 1)
        // 倍率 1 の絵の箱は当たり判定そのもの。
        #expect(abs(Self.hitboxArt.drawnRange.lowerBound) < Self.epsilon)
        #expect(abs(Self.hitboxArt.drawnRange.upperBound - Self.width) < Self.epsilon)
    }

    /// **当たり判定は倍率で動かない**（#943 の本質）。帯の厚みは倍率 1 の絵の高さそのもので、
    /// 会長決裁（2026-09-12）の値から 1 ミリも動いていない。
    @Test("帯の厚みは見た目の倍率に依存せず、決裁時の値のまま")
    func bandHeightIgnoresVisualScale() {
        let decided = 4.335495639393049
        #expect(abs(Self.hitboxArt.bandHeight - decided) < 1e-6, "帯の厚みが #943 以前の値から動いた")
        for scale in [1.0, 1.25, 1.5, 2.0] {
            let art = RunnerBirdArt(width: Self.width, groundDrop: Self.groundDrop, visualScale: scale)
            #expect(abs(art.bandHeight - Self.height) < Self.epsilon, "倍率 \(scale) で帯の厚みが変わった")
        }
        // 当たり判定そのものと突き合わせる（`bandHeight` を使う側が取り違えていないこと）。
        let band = RunnerHazardKind.bird.height - RunnerHazardKind.bird.bottom
        #expect(abs(Self.drawnArt.bandHeight - band) < Self.epsilon, "帯の上端が倍率 1 の絵の頂点から外れている")
    }

    @Test("絵の水平方向の張り出しが 0（絵の箱の幅ちょうどに収まる）")
    func horizontalExtentMatchesDrawnBox() {
        for (label, art) in Self.arts {
            let extent = art.horizontalExtent
            #expect(abs(extent.lowerBound - art.drawnRange.lowerBound) < Self.epsilon, "\(label): 後端")
            #expect(abs(extent.upperBound - art.drawnRange.upperBound) < Self.epsilon, "\(label): 前端")
            // 箱は当たり判定の倍率ぶんの幅で、当たり判定に中央合わせ（前後の張り出しが等しい）。
            let drawnWidth = art.drawnRange.upperBound - art.drawnRange.lowerBound
            #expect(abs(drawnWidth - Self.width * art.visualScale) < Self.epsilon, "\(label): 箱の幅")
            let rearOverhang = -art.drawnRange.lowerBound
            let frontOverhang = art.drawnRange.upperBound - Self.width
            #expect(abs(rearOverhang - frontOverhang) < Self.epsilon, "\(label): 前後の張り出しが等しくない")
        }
    }

    /// 縦は**倍率 1 の絵と帯がぴったり一致する**こと（#671・会長決裁 2026-09-12）。
    ///
    /// - 床（13）は「接地してくぐれる／跳ぶと当たる」の境目そのもの。ここに絵の無いすき間を
    ///   残すと「鳥の下を通ったのに当たった」になる
    /// - 天井は絵の頂点（浮遊の上端）に一致させる。**上に絵の無い帯を残すと「見えている鳥を
    ///   跳び越したのに当たる」**（#609 で潰した理不尽の再発）。決裁値 22 を下げたのはこれが理由で、
    ///   ここが旧 `verticalExtentReachesCeiling` の役目を引き継ぐ
    @Test("倍率 1 の絵の下端が帯の床、上端が帯の天井にちょうど一致する")
    func verticalExtentFillsTheBand() {
        let extent = Self.hitboxArt.birdVerticalExtent
        #expect(abs(extent.lowerBound - 0) < Self.epsilon, "絵の底が帯の床から浮いている")
        #expect(abs(extent.upperBound - Self.height) < Self.epsilon, "絵の頂点が帯の天井とズレている")
    }

    /// 実際に描く絵（#943）は当たり判定を**包む**: 横は前後に等しく張り出し、縦は床合わせのまま
    /// 上へだけ張り出す。床を合わせたままにするのは、帯の床 13 が「接地でくぐれる」の境目で、
    /// そこに絵を下ろすと接地した頭（11）と見た目で触れそうになるから。
    @Test("描く絵は当たり判定を包み、床合わせで上へだけ張り出す（#943）")
    func drawnArtCoversTheHitbox() {
        let art = Self.drawnArt
        let scale = art.visualScale
        let horizontal = art.horizontalExtent
        #expect(horizontal.lowerBound <= 0 + Self.epsilon, "当たり判定の後端が絵から出ている")
        #expect(horizontal.upperBound >= Self.width - Self.epsilon, "当たり判定の前端が絵から出ている")
        let expectedOverhang = Self.width * (scale - 1) / 2
        #expect(abs(-horizontal.lowerBound - expectedOverhang) < Self.epsilon, "後ろの張り出し")
        #expect(abs(horizontal.upperBound - Self.width - expectedOverhang) < Self.epsilon, "前の張り出し")

        let vertical = art.birdVerticalExtent
        #expect(abs(vertical.lowerBound - 0) < Self.epsilon, "描く絵の底が帯の床から浮いている")
        #expect(vertical.upperBound >= Self.height - Self.epsilon, "帯の天井が絵から出ている")
        // 各パーツは箱の幅に比例するので、頂点は倍率 1 の高さのちょうど倍率倍。
        #expect(abs(vertical.upperBound - Self.height * scale) < Self.epsilon, "描く絵の頂点が倍率ぶんになっていない")
    }

    /// 影は帯の外——地面（y = -groundDrop）に敷く。**影の下端そのもの**を見る:
    /// `verticalExtent` は鳥と影の合併なので、下端が負というだけなら影を地面から
    /// 大きく浮かせても通ってしまう（体とのすき間は「飛んでいる」の手がかりになる）。
    /// 幅は絵に合わせ、中心は当たり判定の中央（= 絵の中央）で倍率に動かない。
    @Test("影は地面に敷き、絵の幅に合わせ、当たり判定の中央に置く")
    func shadowLiesOnTheGround() {
        for (label, art) in Self.arts {
            let shadowBottom = Self.shadowBottom(of: art)
            #expect(shadowBottom >= -Self.groundDrop - Self.epsilon, "\(label): 影が地面より下")
            #expect(
                shadowBottom <= -Self.groundDrop + 0.1,
                "\(label): 影が地面まで降りていない（体とのすき間が『飛んでいる』の手がかり）"
            )
            #expect(abs(Double(art.shadowCenter.x) - Self.width / 2) < Self.epsilon, "\(label): 影の中心")
            let drawnWidth = art.drawnRange.upperBound - art.drawnRange.lowerBound
            #expect(Double(art.shadowSize.width) <= drawnWidth + Self.epsilon, "\(label): 影が絵の箱より広い")
            #expect(Double(art.shadowSize.width) > drawnWidth * 0.8, "\(label): 影が絵に対して小さすぎる")
        }
    }

    @Test("はみ出しをパーツごとに見る（丸・多角形・影のすべて）")
    func eachStaticPartStaysInsideTheBox() {
        for (label, art) in Self.arts {
            let box = art.drawnRange

            func expectInside(_ value: Double, _ part: String) {
                #expect(value >= box.lowerBound - Self.epsilon, "\(label): \(part)")
                #expect(value <= box.upperBound + Self.epsilon, "\(label): \(part)")
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
    }

    /// `addBird` が描くパーツの全量。**ここに載っていないパーツは張り出しを測られない**
    /// （腹・目・足が測定の網から漏れていたのを PR #633 の敵対的検証が見つけた）。
    /// `addBird` はこの一覧の値だけを使って描くので、数が合わなくなったら
    /// どちらかに片付け忘れがある。
    @Test("測定対象のパーツが、描いているパーツを漏れなく覆っている")
    func partInventoryCoversEverythingDrawn() {
        let art = Self.drawnArt
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
        for (label, art) in Self.arts {
            let box = art.drawnRange
            for (index, wing) in art.rotatingParts.enumerated() {
                // 回転の端だけでなく、その間も刻んで見る（端が最外周とは限らない）。
                let steps = 200
                for step in 0...steps {
                    let ratio = Double(step) / Double(steps)
                    let angle = wing.rotation.lowerBound
                        + (wing.rotation.upperBound - wing.rotation.lowerBound) * ratio
                    for point in wing.points {
                        let x = Double(point.x) * cos(angle) - Double(point.y) * sin(angle)
                        let world = Double(wing.pivot.x) + x
                        #expect(world >= box.lowerBound - Self.epsilon, "\(label): 回るパーツ \(index) が後端を越えた")
                        #expect(world <= box.upperBound + Self.epsilon, "\(label): 回るパーツ \(index) が前端を越えた")
                    }
                }
            }
        }
    }

    @Test("箱の縁まで使い切っている（無駄に小さくしていない）")
    func artFillsTheBox() {
        for (label, art) in Self.arts {
            // くちばしの先端は前端ちょうど、翼か尾羽の先端は後端ちょうど。
            let beakTip = art.beak.points.map { Double(art.beak.anchor.x) + Double($0.x) }.max() ?? 0
            #expect(abs(beakTip - art.drawnRange.upperBound) < Self.epsilon, "\(label): くちばし")

            let tailTip = art.tails
                .flatMap { tail in tail.points.map { Double(tail.anchor.x) + Double($0.x) } }
                .min() ?? .infinity
            let wingTip = Double(art.farWing.pivot.x)
                + RunnerBirdArt.rotatedXRange(art.farWing.points, art.farWing.rotation).lowerBound
            #expect(abs(min(tailTip, wingTip) - art.drawnRange.lowerBound) < Self.epsilon, "\(label): 後端")
        }
    }

    /// 倍率が比率ではなく実際の寸法（胴・翼）に効いていること、絵の高さが走者の絵（11.9）と同じ位
    /// （#943 会長「おじさんと同じ位の大きさ」）であること。
    @Test("描く絵の胴・翼は倍率 1 の絵の倍率倍で、走者と同じ位の高さ（#943）")
    func drawnPartsAreScaledUp() {
        let unit = Self.hitboxArt, drawn = Self.drawnArt
        let scale = RunnerBirdArt.defaultVisualScale
        #expect(abs(drawn.bodyRadius - unit.bodyRadius * scale) < Self.epsilon, "胴")
        #expect(abs(drawn.headRadius - unit.headRadius * scale) < Self.epsilon, "頭")
        let unitWing = RunnerBirdArt.rotatedXRange(unit.farWing.points, unit.farWing.rotation)
        let drawnWing = RunnerBirdArt.rotatedXRange(drawn.farWing.points, drawn.farWing.rotation)
        let unitSpan = unitWing.upperBound - unitWing.lowerBound
        let drawnSpan = drawnWing.upperBound - drawnWing.lowerBound
        #expect(abs(drawnSpan - unitSpan * scale) < Self.epsilon, "翼")
        // 走者の絵の全高 11.9（`RunnerScene.buildFace` の帽子の天辺）と同じ位——上下 2 の幅で見る。
        let riderArtHeight = 11.9
        let birdArtHeight = drawn.birdVerticalExtent.upperBound
        #expect(abs(birdArtHeight - riderArtHeight) < 2, "鳥の絵の高さ \(birdArtHeight) が走者 \(riderArtHeight) と同じ位でない")
    }

    /// 箱の幅を変えても、倍率 1 の絵は幅ちょうどいっぱい・帯の床合わせのまま（比率で組んである）。
    /// 縦は入力ではなく結果（`bandHeight`）なので、**幅に比例して帯も伸びる**ことを見る。
    /// 描く絵はどの幅・倍率でも当たり判定を包み、帯の厚みは倍率で動かない。
    @Test("箱の幅・倍率を変えても関係が保たれる（比率で組んである）")
    func extentFollowsAnyHitboxSize() {
        var previousBand = 0.0
        for width in [4.0, 6.0, 8.0] {
            for groundDrop in [0.0, 13.0] {
                let unit = RunnerBirdArt(width: width, groundDrop: groundDrop, visualScale: 1)
                #expect(abs(unit.horizontalExtent.lowerBound) < Self.epsilon)
                #expect(abs(unit.horizontalExtent.upperBound - width) < Self.epsilon)
                #expect(abs(unit.birdVerticalExtent.lowerBound) < Self.epsilon)
                #expect(abs(unit.birdVerticalExtent.upperBound - unit.bandHeight) < Self.epsilon)
                #expect(unit.bandHeight > 0)
                for scale in [1.0, 1.5, 2.0] {
                    let art = RunnerBirdArt(width: width, groundDrop: groundDrop, visualScale: scale)
                    #expect(abs(art.bandHeight - unit.bandHeight) < Self.epsilon, "幅 \(width) 倍率 \(scale): 帯")
                    #expect(art.horizontalExtent.lowerBound <= Self.epsilon, "幅 \(width) 倍率 \(scale): 後端")
                    #expect(art.horizontalExtent.upperBound >= width - Self.epsilon, "幅 \(width) 倍率 \(scale): 前端")
                    #expect(abs(art.birdVerticalExtent.lowerBound) < Self.epsilon, "幅 \(width) 倍率 \(scale): 床")
                    #expect(art.birdVerticalExtent.upperBound >= art.bandHeight - Self.epsilon, "幅 \(width) 倍率 \(scale): 天井")
                    let shadowBottom = Self.shadowBottom(of: art)
                    #expect(shadowBottom >= -groundDrop - Self.epsilon)
                    #expect(shadowBottom <= -groundDrop + 0.1)
                }
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

    /// 絵を合わせる相手（帯）が、全ステージの鳥で同じ 1 タイル幅 × 絵の高さであること。
    /// ここがステージごとに違うと `art` 1 つで張り出しを測っている意味が無くなる
    /// ——帯の厚みは**幅 1 タイルの絵**から導いているので、幅の違う鳥が混ざると
    /// その鳥だけ絵と帯がズレる。
    ///
    /// #796 で鳥は飛び立つ障害になり、帯は走者の進みで上下する（`RunnerHazard.frame`）。
    /// 変わらないのは**帯の厚み = 絵の高さ**で、低く飛ぶあいだの上端は低い岩と同じ 5、
    /// 上がりきった下端は #622 D案の 13。
    @Test("鳥の箱は 1 タイル幅 × 絵の高さの帯（低いときの上端 5・上がったときの下端 13）")
    func hitboxIsTheBand() {
        #expect(RunnerHazardKind.bird.height == RunnerHazardKind.lowBlock.height, "低く飛ぶあいだは低い岩と同じ上端")
        #expect(
            abs(RunnerHazardKind.bird.height - RunnerHazardKind.bird.bottom - Self.height) < Self.epsilon,
            "帯の厚みが絵の高さから外れている"
        )
        #expect(RunnerHazardKind.birdHighBottom == 13, "上がりきった下端は #622 D案の決裁値のまま")
        #expect(RunnerHazardKind.birdHighBottom > RunnerField.Metrics.playerHeight, "上がりきれば接地した頭はつかえない")
        let birds = RunnerStage.all.flatMap { $0.hazards }.filter { $0.kind == .bird }
        #expect(!birds.isEmpty)
        for bird in birds {
            #expect(bird.length == RunnerRules.tileWidth)
            #expect(bird.height == RunnerHazardKind.bird.height)
            // 上がりきった帯（`frame`）も同じ厚み。
            let far = bird.birdTakeoffDistance
                + (RunnerRules.birdLowDistance + RunnerRules.birdClimbDistance) / RunnerRules.birdAdvance
            if let frame = bird.frame(atRunnerDistance: far) {
                #expect(abs(frame.bottom - RunnerHazardKind.birdHighBottom) < Self.epsilon)
                #expect(abs(frame.top - frame.bottom - Self.height) < Self.epsilon)
            }
        }
    }
}
