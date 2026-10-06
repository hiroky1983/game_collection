import Foundation
import HomerunCore
import simd

/// 結果に応じて打者の頭に重ねる記号（#1760）。空振りのぐるぐる目・頭上の星（#1681・`HomerunWhiffGag`）と同じ仕組みで、
/// 頭の骨に合わせて記号の絵を置く。判定（`HomerunJudge`）・飛距離は変えない。
///
/// 発生条件・表示の数値はすべて初期値で、会長 QA で調整する前提のため、このファイルの定数に集めてある。
enum HomerunFaceMark: Equatable, Sendable {
    case none
    /// キラキラ目: 打球を見送る間、目を星にして頭の横にもきらめきを出す。
    case sparkle
    /// 怒りマーク（#1769）: 振った空振りの次の球の構えで、頭の横に白い吹き出しに入れた赤い 💢 を出す（弾ませてプンプンさせる）。
    case waitingAngry
    /// 怒りが溜まった構え（#1797）: 💢 に加えて頭から湯気を出す（会長確定版 2026-10-04。顔の赤みは入れない）。怒りゲージが `angerStageThreshold` 以上のとき。
    case waitingAngryHot
    /// 柵越えを打った次の球の構え（#1762）: 球を待つ間、目だけを星にする（頭の横のきらめきは出さない）。
    case waitingSparkle
    /// たんこぶ（#1793）: 打ち上げた球が自分の頭に落ちた次の球の構えで、ヘルメットの上にたんこぶを残す。
    case waitingLump

    // MARK: 発生

    /// 構え（次の球を待つ間）に出す記号か。構えの記号は振っていない段階（構え・踏み込み）で置く。
    var isWaiting: Bool { self == .waitingSparkle || self == .waitingAngry || self == .waitingAngryHot || self == .waitingLump }

    /// 💢 を出す構えか（段階①・②）。
    var showsAngryMark: Bool { self == .waitingAngry || self == .waitingAngryHot }

    /// 1 球の結果から記号を決める（純粋な値）。
    /// - `swung`: 振ったか（見送りは記号を出さない）。
    /// - `isNewBest`: この球で挑戦が終わり、自己ベストを更新したか。
    static func decide(ball: HomerunBattedBall?, swung: Bool, isNewBest: Bool) -> HomerunFaceMark {
        guard swung, let ball, !ball.isTankobu else { return .none }
        switch ball.kind {
        case .miss, .foul:
            return .none
        case .inPlay, .fenceHit, .homer:
            // ジャストの当たり・柵越え・自己ベスト更新。
            return ball.timing == .just || ball.kind == .homer || isNewBest ? .sparkle : .none
        }
    }

    /// 次の球の構えに出す記号。次の球を打つ・見送るまでの 1 球だけ。挑戦が終わる球（10 球目・月が割れた球）の次は無いので出さない。
    /// - 柵越え（場外・ポール直撃・月を含む）を打った次はキラキラ目（#1762）。
    /// - 打ち上げた球が頭に落ちてたんこぶができた（#1793）次は、たんこぶ。
    /// - 振った空振り（見送りは数えない）の次は怒りマーク（#1769）。
    /// - 怒りゲージ（`anger`・この球を数えた後の値）が `angerStageThreshold` 以上なら、怒りマークは湯気つきの段階②（#1797）。
    static func waiting(after ball: HomerunBattedBall?, swung: Bool, challengeFinished: Bool, anger: Int = 0) -> HomerunFaceMark {
        guard let ball, !challengeFinished else { return .none }
        if ball.isTankobu { return .waitingLump }
        if ball.kind == .homer { return .waitingSparkle }
        guard swung && ball.kind == .miss else { return .none }
        return anger >= angerStageThreshold ? .waitingAngryHot : .waitingAngry
    }

    // MARK: 怒りゲージ（#1797・裏パラメータ・画面には出さない）

    /// 振った空振りで `angerWhiffGain` 増え、当たり（ファウル含む）で `angerHitRelief` 減る（0 未満にしない）。見送りは変えない。
    /// `angerStageThreshold` 以上で段階②。挑戦の開始で 0。会長 QA で調整する前提で、数値はここの 3 つに集める。
    static let angerWhiffGain = 1
    static let angerHitRelief = 1
    static let angerStageThreshold = 3

    /// 1 球を締めた後の怒りゲージ。
    static func angerGauge(after ball: HomerunBattedBall?, swung: Bool, from gauge: Int) -> Int {
        guard swung, let ball else { return gauge }
        return ball.kind == .miss ? gauge + angerWhiffGain : max(gauge - angerHitRelief, 0)
    }

    // MARK: 時間

    /// 記号が出始めるコマ（クリップの 1 始まり。振り抜きの打点は約 26 コマ目・フォロースルーは 31 コマ目〜）と、広がりきるまで（秒）。
    static let appearFrame: Double = 31
    static let appearGrow: TimeInterval = 0.15

    // MARK: 大きさ・置き方（m・頭の骨の局所を基準）

    /// キラキラ目の星の外側の半径（目の飾りと同じ位置に貼る）。
    static let sparkleEyeRadius: Float = 0.05
    /// きらめき（頭の横の小さな星）の外側の半径（打席のカメラは遠い・`HomerunWhiffGag.starSize` と同じ考え方）と、頭の中心からの横・上の距離。
    static let sparkleSize: Float = 0.075
    static let sparkleSide: Float = 0.24
    static let sparkleLift: Float = 0.12
    /// きらめきの明滅（回/秒）と振れ幅（割合）。
    static let twinkleRate: Double = 2.5
    static let twinkleDepth: Float = 0.25

    /// 怒りマーク（#1797・会長確定版 = モック v7・2026-10-04）: 白い吹き出し（細い輪郭線・頭の方へ向く小さな尾）の中に、
    /// 赤一色・縁取り無しの「く」の字 4 本の 💢 を入れる。吹き出しは頭の左横（カメラから見て左）・ひさしの高さ・カメラ側へ `angryForward`。
    /// 脈打ち・弾みは吹き出しごと。
    /// 大きさの単位: 💢 の絵は「外側の半径 1」の比で描き（腕の先は `angryExtent` まで）、表示ではそれを `angrySize` 倍（m）する。
    /// 吹き出しの丸の半径は `angryBubbleRadius`（m）。数値はモック（0.22 を 1 とした比）から: 💢 0.22×0.58、丸 0.22×0.56。
    static let angrySize: Float = 0.128
    static let angryBubbleRadius: Float = 0.123
    /// 吹き出しの輪郭線の太らせ幅（吹き出しの半径を 1 とした比）。
    static let angryBubbleRim: Float = 0.07
    /// 頭のてっぺんから見た吹き出しの中心: 左への距離・上への距離（ひさしの高さに来る）・カメラ側への距離（m）。
    /// 頭の左上は HUD「今回 0 m」に掛かったので真横の内側寄り（会長指示 2026-10-03）。
    static let angrySide: Float = 0.42
    static let angryLift: Float = 0.10
    static let angryForward: Float = 0.2
    /// 脈打つ速さ（回/秒）と振れ幅（割合）・弾む高さ（m）。
    static let angryPulseRate: Double = 4
    static let angryPulseDepth: Float = 0.2
    static let angryHop: Float = 0.03

    /// 💢 の形（外側の半径 1 を単位・会長確定 2026-10-04）: 太くて端が丸い「く」の字 4 本。**曲がり角が中心を向き、両腕が外へ伸びる**。
    /// 4 本は上下左右（斜め 4 方向から `angryArmBaseOffset` 回した向き = 上下左右から −8°）に並び、各「く」は自分の軸について左右対称。
    /// 曲がり角の先端（腕の交点）は中心から `angryVertexRadius`、腕は交点から `angryArmLength`、開きは `angryArmOpen`、
    /// 角は半径 `angryCornerRadius` の円弧で丸め、腕はまっすぐにわずかな外への反り `angryArmBow`。太さは一定（半分の太さ `angryStrokeHalfWidth`）。
    static let angryVertexRadius: Float = 0.22
    static let angryArmLength: Float = 0.44
    static let angryArmOpen: Float = 60 * .pi / 180
    static let angryCornerRadius: Float = 0.18
    static let angryArmBow: Float = 0.03
    static let angryArmBaseOffset: Float = 37 * .pi / 180
    static let angryStrokeHalfWidth: Float = 0.10
    /// 絵が外側の半径 1 の単位で収まる半径（腕の先の外側の縁）と、真ん中の空白の直径が全体の直径に占める割合。`angryStrokeCenterline` から実測。
    static let angryExtent: Float = 0.75
    static let angryGapRatio: Float = 0.40

    /// 💢 の `index` 本目（0〜3）の中心線（外側の半径 1 の単位）: 腕（端 → 角の接点）→ 角の円弧 → 腕（接点 → 端）。
    /// 腕は 2 次ベジェで、中心から遠ざかる側へ `angryArmBow` 膨らむ。描画はこれに沿った帯と、両端の円（丸い端）。
    static func angryStrokeCenterline(_ index: Int, segments: Int = 14) -> [SIMD2<Float>] {
        let base = Float(index) * .pi / 2 + .pi / 4 + angryArmBaseOffset
        let d = SIMD2<Float>(cos(base), sin(base))
        let halfOpen = angryArmOpen / 2
        // 腕の向き（外向き・軸から ±halfOpen）。角は 2 本の腕に内接する円弧で、先端（腕の交点）を vertexRadius に置く。
        let dirs = [SIMD2<Float>(cos(base + halfOpen), sin(base + halfOpen)), SIMD2<Float>(cos(base - halfOpen), sin(base - halfOpen))]
        let apex = d * angryVertexRadius
        let tangentDistance = angryCornerRadius / tan(halfOpen)
        let tangents = [apex + dirs[0] * tangentDistance, apex + dirs[1] * tangentDistance]
        let arcCenter = apex + d * (angryCornerRadius / sin(halfOpen))
        func arm(_ i: Int) -> [SIMD2<Float>] {
            let p0 = tangents[i], p1 = apex + dirs[i] * angryArmLength
            var n = SIMD2<Float>(-dirs[i].y, dirs[i].x)
            let mid = (p0 + p1) / 2
            if simd_dot(n, mid) < 0 { n = -n }
            let ctrl = mid + n * angryArmBow
            return (0...segments).map { k in
                let u = Float(k) / Float(segments)
                return p0 * (1 - u) * (1 - u) + ctrl * 2 * (1 - u) * u + p1 * u * u
            }
        }
        var line: [SIMD2<Float>] = arm(0).reversed()
        let a0 = atan2(tangents[0].y - arcCenter.y, tangents[0].x - arcCenter.x)
        var a1 = atan2(tangents[1].y - arcCenter.y, tangents[1].x - arcCenter.x)
        while a1 - a0 > .pi { a1 -= 2 * .pi }
        while a1 - a0 < -.pi { a1 += 2 * .pi }
        for k in 1..<segments {
            let a = a0 + (a1 - a0) * Float(k) / Float(segments)
            line.append(arcCenter + SIMD2<Float>(cos(a), sin(a)) * angryCornerRadius)
        }
        line += arm(1)
        return line
    }

    /// 吹き出しの尾（吹き出しの半径を 1 とした比）: 丸の縁から `angryTailLength` 先まで伸びる三角（根元の半幅 `angryTailHalfWidth`）。
    /// 向きは吹き出しの中心から頭の中心（頭のてっぺんの 0.27 下）へ（吹き出しの面の中・x = カメラから見て右・y = 上）。
    static let angryTailLength: Float = 0.54
    static let angryTailHalfWidth: Float = 0.25
    static var angryTailDirection: SIMD2<Float> {
        simd_normalize(SIMD2<Float>(angrySide, -(angryLift + 0.27)))
    }

    // MARK: 段階②（湯気・モック v2 の「プンッ」）

    /// 湯気: 薄い水色のもくもく 1 つにギザギザの尾が付いた絵の板（一辺 `steamWidth` m）を、頭のてっぺんの左右から交互に噴き出す。
    /// 1 周期 `steamPeriod` 秒（左右は半周期ずらす）。最初の `steamBurst` で勢いよく外へ出て膨らみ（ease-out）、その後ゆっくり漂い、
    /// `steamFadeFrom` から薄れて少し広がって消える。板はカメラ側へ `steamForward` 出す。
    static let steamPeriod: TimeInterval = 1.3
    static let steamWidth: Float = 0.36
    static let steamBurst: Float = 0.18
    static let steamFadeFrom: Float = 0.62
    static let steamForward: Float = 0.3
    /// 頭のてっぺんから見た噴き出しの位置（横・上・m）: 出始め、噴き出しで動く量、その後に漂う量。
    static let steamStart = SIMD2<Float>(0.08, 0.10)
    static let steamBurstMove = SIMD2<Float>(0.14, 0.17)
    static let steamDrift = SIMD2<Float>(0.03, 0.04)

    /// 周期の中の位置 `u`（0〜1）での、噴き出しの進み（0〜1・ease-out）・不透明度（1 → 0）・板の大きさの係数。
    static func steamPhase(_ u: Float) -> (burst: Float, fade: Float, size: Float) {
        let b = min(max(u / steamBurst, 0), 1)
        let burst = 1 - (1 - b) * (1 - b) * (1 - b)
        let fade: Float = u < steamFadeFrom ? 1 : max(1 - (u - steamFadeFrom) / (1 - steamFadeFrom), 0)
        return (burst, fade, (0.25 + 0.75 * burst) * (1 + 0.18 * (1 - fade)))
    }

    /// ヘルメット（頭のてっぺんから見て中心 (0, -0.175)・半径 0.29 の球。`HomerunOjisan3D` の頭の球 0.27 m を基準）と吹き出しの丸の間の
    /// 最小の隙間（m）。脈打ち・弾みが最大でも重ならないことをテストで確かめる（尾は頭の方へ向けて伸ばすので含めない）。
    static var angryMinClearance: Float {
        let dx = angrySide, dy = angryLift + 0.175
        return (dx * dx + dy * dy).squareRoot() - 0.29 - angryHop - angryBubbleRadius * (1 + angryPulseDepth)
    }

    /// 弾み（0 以上 `angryHop` 以下）。脈打ちと同じ速さで、跳ねて着く。
    static func angryBounce(since t: TimeInterval) -> Float {
        angryHop * abs(sin(Float(t * angryPulseRate * .pi)))
    }

    /// 構えのキラキラ目の明滅（回/秒）と振れ幅（割合）。
    static let waitingTwinkleRate: Double = 2
    static let waitingTwinkleDepth: Float = 0.12

    /// 出始めから `t` 秒後の明滅の係数（1 を中心に ±`depth`）。
    static func pulse(since t: TimeInterval, rate: Double, depth: Float) -> Float {
        1 + depth * Float(sin(t * rate * 2 * .pi))
    }
}
