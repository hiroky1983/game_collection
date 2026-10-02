import Foundation
import simd
import HomerunCore

/// 打球をカメラが追う（#1613・会長指示 2026-09-30）。当たり以上（当たり・フェンス直撃・柵越え・ファウル）の打球は、
/// バットに当たった瞬間から打席の 3D のカメラを打球の後ろへ回して追い、落ちて弾んで転がって止まるまで（柵越えは柵を越えて
/// スタンドに落ちるまで）を見せてから結果のカードを出す。外野の野手は置かない。
///
/// 打球の道は**判定の方向・飛距離・打ち上げの帯どおり**の、本塁から打球方向へ伸びる鉛直の面の中の線（`Track`）。
/// 乱数なし・同じ `HomerunBattedBall` は同じ道になる。描画は打席の 3D（`HomerunAtBatScene3DView`）の球とカメラを
/// 置き換えるだけで、新しい `ARView`・球場を作らない（3D の重さを増やさない。以前の外野カメラの静止ショットは
/// 2 つ目の `ARView` に球場と外野手をもう 1 組作っていた）。
enum HomerunBallChase {
    // MARK: 時間の定数（会長 QA で詰める）

    /// 当たった瞬間から、打席のカメラのまま球がバットから飛び出すのを見せる時間（秒）。この後、打球を追うカメラへ切り替える。
    static let cutDelay: TimeInterval = 0.15

    /// 当たった瞬間から結果のカードを出すまでの上限（秒）。打球の動き（飛ぶ・弾む・転がる）はこの時間から `restHold` を
    /// 引いた長さに収まるよう、長い打球ほど速回しにする（短い打球は実際の速さのまま早く止まり、カードも早く出る）。
    /// 会長 QA（2026-10-01・#1645）「スタンドまでが近すぎる」で、速回しを弱めて打球の見かけの速さを約 2 割落とした
    /// （柵越え 3.0 → 3.6・当たり / フェンス直撃 2.4 → 2.8・ファウル 2.0 → 2.3 秒）。
    static func limit(for kind: HomerunKind) -> TimeInterval {
        switch kind {
        case .homer: 3.6
        case .fenceHit, .inPlay: 2.8
        case .foul: 2.3
        case .miss: 0
        }
    }

    /// 止まった（柵越えはスタンドに落ちた）打球を、カードを出す前にそのまま見せる時間（秒）。
    static let restHold: TimeInterval = 0.35
    /// 離してから 3D の球がバットに当たるまでの最大（秒・`HomerunSwingContact.contactShownTime`。早振りの端で約 0.2 秒）。
    static let contactLeadMax: TimeInterval = 0.25
    /// 結果のカードを出してから次の球までの時間（秒）。以前の当たりの 1.6 秒（2.4 − 振り抜き 0.8）とほぼ同じ。
    static let cardHold: TimeInterval = 1.4

    /// 1 球の結果の時間（離してから次の球が始まるまで・`HomerunModel.resultDuration`）。
    static func resultDuration(for kind: HomerunKind) -> TimeInterval {
        contactLeadMax + limit(for: kind) + cardHold
    }

    /// ポール直撃（#1686）の、当たった瞬間から結果のカードを出すまでの上限（秒）。ポールまで飛んで当たり、跳ね返って
    /// 下へ落ちて弾むまでを見せるぶん、ふつうの柵越え（`limit(for: .homer)`）より長い。
    static let poleLimit: TimeInterval = 4.6
    /// ポール直撃の 1 球の結果の時間（`HomerunModel.resultDuration`）。
    static var poleResultDuration: TimeInterval { contactLeadMax + poleLimit + cardHold }

    // MARK: 見た目の定数

    /// 追うカメラで見せる球の半径（m・打球の道の地面の高さにも使う）。実寸（0.037m）では数十 m 先で見えないので少し大きくする。
    /// 会長 QA（2026-10-01・#1645）「追う球が大きすぎる」で 0.3 → 0.1（切り替え直後の見かけの直径が画面の高さの約 6% → 2%）。
    /// 大きさは変えないので、カメラから遠ざかるほど小さく映る（`minApparentRadius` まで）。
    static let ballRadius: Double = 0.1
    /// 球の見かけの半径の下限（ラジアン・縦の画角 `verticalFieldOfView` の画面で直径が高さの約 0.8%）。これより遠くでは
    /// 球を大きくして、この見かけの大きさのまま見せる（遠くの球が点になって消えない）。
    static let minApparentRadius: Double = 0.0035
    /// 打席の 3D の球（実寸）を、カメラから `distance` m の所でこの倍率に拡大して見せる。
    static func ballScale(distance: Double) -> Float {
        Float(max(ballRadius, distance * minApparentRadius)) / HomerunSwingContact.ballRadius
    }
    /// 打ち出す点（本塁の少し前・打点の高さ）。
    static let start = Point(s: 0.5, y: 1.0)
    /// 柵（高さ 3.2m + 黄色の上線）を越える打球が、柵の真上で通る最低の高さ（球の中心・m）。
    static let fenceClearance: Double = 4.6
    /// フェンス直撃の球の中心が止まる、柵の面からの距離（m）。
    static let fenceContactInset: Double = 0.4
    static let gravity: Double = 9.8
    /// 追うカメラの縦の画角（度）。#1645 で 40 → 46（広めにして奥の柵・スタンドを小さく = 遠くに見せる）。
    static let verticalFieldOfView: Float = 46
    /// カメラは球の後ろ（本塁側）`trailBase + trailGrowth × 球の距離` に置く（遠くへ飛ぶほど少し引いて、球場を広く映す）。
    /// #1645 で trailGrowth を 0.25 → 0.35（遠くへ飛ぶほど球がカメラから離れて小さくなる）。
    static let trailBase: Double = 12
    static let trailGrowth: Double = 0.35
    /// カメラの高さ = `cameraBaseHeight + cameraHeightFollow × 球の高さ`（上がる球を下から見上げすぎない）。
    static let cameraBaseHeight: Double = 3
    static let cameraHeightFollow: Double = 0.4
    /// カメラは柵のこれだけ手前より先へは出ない（柵越えの球を追ってスタンドへ入り込まない）。#1645 で 12 → 24
    /// （外野の芝の中ほどで止まり、柵越えの球が柵・スタンドへ遠ざかっていくのを見送る）。
    static let cameraFenceMargin: Double = 24

    // MARK: 打球の道

    /// 打球方向の鉛直の面の中の点。`s` は本塁からの水平距離（m・打球方向へ正）、`y` は球の中心の高さ（m）。
    struct Point: Equatable {
        var s: Double
        var y: Double
    }

    /// 道の 1 区間。`arc` は放物線（弦からのふくらみ `bulge`・水平は等速）、`roll` は地面を転がる（だんだん遅くなる）。
    struct Segment: Equatable {
        enum Motion: Equatable {
            case arc(bulge: Double)
            case roll
        }
        var from: Point
        var to: Point
        var motion: Motion
        var duration: TimeInterval

        /// 区間の中の割合 `u`（0〜1）の点。
        func point(at u: Double) -> Point {
            let u = min(max(u, 0), 1)
            switch motion {
            case .arc(let bulge):
                return Point(s: from.s + (to.s - from.s) * u, y: from.y + (to.y - from.y) * u + 4 * bulge * u * (1 - u))
            case .roll:
                let k = 1 - (1 - u) * (1 - u)
                return Point(s: from.s + (to.s - from.s) * k, y: from.y + (to.y - from.y) * k)
            }
        }

        /// 実際の重力での長さ（秒）。放物線はふくらみから（y'' = −g）、転がりは距離から。
        var naturalDuration: TimeInterval {
            switch motion {
            case .arc(let bulge): sqrt(8 * max(bulge, 0.02) / HomerunBallChase.gravity)
            case .roll: min(0.3 + abs(to.s - from.s) / 30, 1.0)
            }
        }
    }

    /// 1 球の打球の道（当たった瞬間 = 0 秒から）。
    struct Track: Equatable {
        /// 判定の方向（度・0 = 中堅・負 = レフト）。
        var direction: Double
        var segments: [Segment]

        /// 最初に地面（柵越えはスタンド・フェンス直撃は柵）に着いた点 = 最初の区間の終わり。
        var landing: Point { segments.first?.to ?? HomerunBallChase.start }
        /// 止まった点。
        var rest: Point { segments.last?.to ?? HomerunBallChase.start }
        /// 飛んでいる（最初の区間の）時間。
        var flightDuration: TimeInterval { segments.first?.duration ?? 0 }
        /// 止まるまでの時間。
        var duration: TimeInterval { segments.reduce(0) { $0 + $1.duration } }
        /// 場外（#1654）: 道の終わり（スタンドの後端の `vanishBeyond` m 先）で球が消える。消えた後は球も影も描かない。
        var vanishesAtEnd = false

        /// 当たってから `t` 秒の点。止まった後は止まった点のまま。
        func point(at t: TimeInterval) -> Point {
            var t = max(t, 0)
            for segment in segments {
                if t < segment.duration { return segment.point(at: segment.duration > 0 ? t / segment.duration : 1) }
                t -= segment.duration
            }
            return rest
        }

        /// 当たってから `t` 秒の球の世界座標（`HomerunBallChase.world`）。
        func position(at t: TimeInterval) -> SIMD3<Float> {
            HomerunBallChase.world(point(at: t), direction: direction)
        }
    }

    /// 本塁を原点・+z をセンターとする世界座標（打席の 3D・球場と同じ）。判定の方向の負（レフト = 右打者の引っ張り）は **+x**
    /// （RealityKit は右手系なので、本塁からセンターを向くと左手の +x が三塁側。#1616 の規約・`HomerunAtBatLayout.pullSideX`）。
    static func world(_ p: Point, direction degrees: Double) -> SIMD3<Float> {
        let radians = degrees * .pi / 180
        return [Float(-p.s * sin(radians)), Float(p.y), Float(p.s * cos(radians))]
    }

    /// 打ち上げ角（度）。3D の打席で球がバットから飛び出す角度（`HomerunBallFlight.battedVelocity`）と同じ値。
    static func elevation(for launch: HomerunLaunch?) -> Double {
        switch launch {
        case .grounder: 8
        case .liner: 18
        case .fly: 30
        case .pop: 50
        case nil: 30
        }
    }

    /// 止まる点までのうち、飛んで（最初に地面に着いて）いる割合。残りは弾んで転がる。ゴロは早く落ちて長く転がる。
    static func carryFraction(for launch: HomerunLaunch?) -> Double {
        switch launch {
        case .grounder: 0.3
        case .liner: 0.8
        case .fly, nil: 0.88
        case .pop: 0.92
        }
    }

    /// ファウルの止まる距離（m・判定の飛距離は 0 なので見た目だけの値）。ファウルゾーン（±45° の外・スタンドはファウルラインの
    /// 16m 外）の芝の上に止まる距離。
    static func foulRestDistance(for launch: HomerunLaunch?) -> Double {
        switch launch {
        case .grounder: 30
        case .liner: 55
        case .fly, nil: 65
        case .pop: 28
        }
    }

    /// 打球の道。空振り（`.miss`）は nil。
    static func track(for ball: HomerunBattedBall) -> Track? {
        let segments: [Segment]
        switch ball.kind {
        case .miss:
            return nil
        case .inPlay:
            segments = groundBall(rest: max(ball.distance, 3), launch: ball.launch)
        case .foul:
            segments = groundBall(rest: foulRestDistance(for: ball.launch), launch: ball.launch)
        case .fenceHit:
            segments = fenceHit(ball)
        case .homer where ball.isPoleHit:
            return Track(direction: ball.direction, segments: fitted(poleHit(ball), into: poleLimit - restHold))
        case .homer where ball.isOutOfPark:
            return Track(direction: ball.direction, segments: fitted(outOfPark(ball), into: limit(for: ball.kind) - restHold),
                         vanishesAtEnd: true)
        case .homer:
            segments = homer(ball)
        }
        return Track(direction: ball.direction, segments: fitted(segments, into: limit(for: ball.kind) - restHold))
    }

    /// 本塁から打ち上げ角 `elevation` で打ち出し、`to` に落ちる放物線（最初の区間）。打ち上げ角では `to` に届かない
    /// （高い所に落ちる）・`over` の障害（柵）の上を通らないときは、角度を上げる。
    private static func flight(to: Point, elevation: Double, over obstacles: [Point] = []) -> Segment {
        let y0 = start.y, L = to.s - start.s
        var slope = tan(elevation * .pi / 180)
        // 落ちる点より上へ向けて打ち出す（放物線が上に凸になる）。
        slope = max(slope, (to.y - y0) / L + 0.05)
        // y(x) = y0 + slope·x − k·x²（x は本塁から）、k = (y0 + slope·L − yL) / L²。障害の点 (xo, yo) で y(xo) ≥ yo になる slope。
        for o in obstacles {
            let x = o.s - start.s
            guard x > 0, x < L else { continue }
            let need = (o.y - y0 + (y0 - to.y) * x * x / (L * L)) / (x * (1 - x / L))
            slope = max(slope, need)
        }
        let k = (y0 + slope * L - to.y) / (L * L)
        return make(from: start, to: to, .arc(bulge: k * L * L / 4))
    }

    /// 地面の上の弾み 2 回と転がり（`from` から `rest` まで）。`firstHop` は 1 回目の弾みの高さ（m）。
    private static func bounces(from: Point, rest: Double, firstHop: Double) -> [Segment] {
        let ground = ballRadius
        let d = rest - from.s
        guard abs(d) > 0.3 else { return [] }
        let p1 = Point(s: from.s + d * 0.55, y: ground)
        let p2 = Point(s: from.s + d * 0.8, y: ground)
        let p3 = Point(s: rest, y: ground)
        return [
            make(from: from, to: p1, .arc(bulge: firstHop)),
            make(from: p1, to: p2, .arc(bulge: firstHop * 0.3)),
            make(from: p2, to: p3, .roll),
        ]
    }

    private static func make(from: Point, to: Point, _ motion: Segment.Motion) -> Segment {
        let s = Segment(from: from, to: to, motion: motion, duration: 0)
        return Segment(from: from, to: to, motion: motion, duration: s.naturalDuration)
    }

    /// 1 回目の弾みの高さ: 高く上がった球ほど高く弾む（0.3〜2.5m）。
    private static func firstHop(after flight: Segment) -> Double {
        guard case .arc(let bulge) = flight.motion else { return 0.3 }
        return min(max(bulge * 0.12, 0.3), 2.5)
    }

    /// フェアゾーン・ファウルゾーンに落ちて弾み、`rest` で止まる打球。
    private static func groundBall(rest: Double, launch: HomerunLaunch?) -> [Segment] {
        let landing = Point(s: max(rest * carryFraction(for: launch), start.s + 1), y: ballRadius)
        let f = flight(to: landing, elevation: elevation(for: launch))
        return [f] + bounces(from: landing, rest: rest, firstHop: firstHop(after: f))
    }

    /// フェンス直撃: 柵の面に当たって跳ね返り、判定の飛距離（柵の手前 6m 以内）で止まる。柵に近い当たりほど高い所に当たる。
    private static func fenceHit(_ ball: HomerunBattedBall) -> [Segment] {
        let wall = ball.fence - fenceContactInset
        let rest = min(ball.distance, wall - 0.3)
        let closeness = min(max((ball.distance - (ball.fence - HomerunJudge.fenceHitMargin)) / HomerunJudge.fenceHitMargin, 0), 1)
        let hit = Point(s: wall, y: 1.2 + 1.6 * closeness)
        let f = flight(to: hit, elevation: elevation(for: ball.launch))
        // 跳ね返り: 柵から本塁側へ、止まる点までの 6 割の所に落ち、そこから弾んで転がる。
        let drop = Point(s: wall - (wall - rest) * 0.6, y: ballRadius)
        let back = make(from: hit, to: drop, .arc(bulge: 0.3))
        return [f, back] + bounces(from: drop, rest: rest, firstHop: 0.25)
    }

    /// 柵越え: 柵の上を越えてスタンドに落ち、小さく弾んで止まる。中堅のバックスクリーンに向かう打球は、スクリーンの
    /// 上を越えなければスクリーンに当たって足元へ落ちる。
    private static func homer(_ ball: HomerunBattedBall) -> [Segment] {
        let fence = ball.fence
        let front = fence + 2   // スタンドの前縁（`HomerunToonModel.standFront`・外野）
        typealias Stand = HomerunToonModel.Stand
        let lastRow = Stand.rows - 1
        // 落ちる点: 判定の飛距離（スタンドの最前列より手前にはしない・最後列より奥にはしない）。
        let farthest = front + Double(Stand.depth(row: lastRow))
        let distance = min(max(ball.distance, front + Double(Stand.depth(row: 0))), farthest)
        // 中堅（バックスクリーンの裏・|方向| < 6°）には座席が無いので地面に落ちる。
        let seat = abs(ball.direction) < 6 ? 0 : standSurface(depth: distance - front)
        let landing = Point(s: distance, y: seat + ballRadius)
        var f = flight(to: landing, elevation: elevation(for: ball.launch), over: [Point(s: fence, y: fenceClearance)])
        // 中堅（バックスクリーンの幅の中）へ向かう打球は、スクリーンの面を越えられなければそこで当たる。
        let radians = ball.direction * .pi / 180
        let screenS = battersEyeZ / cos(radians) - ballRadius
        if abs(screenS * sin(radians)) < battersEyeHalfWidth, distance > screenS {
            let atScreen = f.point(at: (screenS - start.s) / (distance - start.s))
            if atScreen.y < battersEyeHeight + ballRadius, case .arc(let bulge) = f.motion {
                // 放物線の途中の弦のふくらみは、弦の長さの 2 乗に比例する（同じ放物線の一部を切り出す）。
                let u = (screenS - start.s) / (distance - start.s)
                f = make(from: start, to: atScreen, .arc(bulge: bulge * u * u))
                let foot = Point(s: screenS - 1.5, y: ballRadius)
                return [f, make(from: atScreen, to: foot, .arc(bulge: 0.2))]
            }
        }
        // 小さく弾んで 1.2m 奥に止まる。奥の列の座面は高いので、止まる高さはその所の座面に合わせる（同じ高さのままだと
        // 奥の列の座席の中に埋まって見えなくなる・#1645 の画面の確認で発見）。
        // 最後列の近くに落ちた球は、最後列の後端（`standBackEdgeDepth`・その先はスタンドの外）を越えて弾まない（#1654）。
        let hopS = min(landing.s + 1.2, front + Double(standBackEdgeDepth) - ballRadius)
        let hopY = abs(ball.direction) < 6 ? landing.y : max(standSurface(depth: hopS - front) + ballRadius, landing.y)
        let hop = make(from: landing, to: Point(s: hopS, y: hopY), .arc(bulge: 0.5))
        return [f, hop]
    }

    /// バックスクリーン（`HomerunToonModel.stadium` の中堅の板: 幅 26m・高さ 15m・z = 125.5 の厚さ 1m）の手前の面。
    static let battersEyeZ: Double = 125.0
    static let battersEyeHalfWidth: Double = 13
    static let battersEyeHeight: Double = 15
    /// バックスクリーンの裏のスコアボード（`HomerunToonModel.battersEye`: z = 137・上の縁の幅 29m・上端 26.5m）。
    static let scoreboardZ: Double = 137
    static let scoreboardHalfWidth: Double = 14.5
    static let scoreboardTop: Double = 26.5

    // MARK: ファウルポール直撃（#1686・会長決裁 2026-10-02）

    /// ポールの中心（本塁からの水平距離・m）。球場の 3D のポール（`HomerunToonModel` の柵）と同じく、両翼の柵の上に立つ。
    static var poleS: Double { HomerunJudge.fence(atDirection: HomerunJudge.foulLimit) }
    /// 球の中心がポールに当たる所（本塁からの水平距離・m）: ポールの面の手前、球の半径ぶん。
    static var poleContactS: Double { poleS - HomerunJudge.poleRadius - ballRadius }
    /// 球がポールに当たる高さの上限（m・ポールの先の球より下）。これより高く飛ぶ打球もこの高さで当てる。
    static var poleContactMaxY: Double { HomerunJudge.poleHeight - 1.5 }
    /// 跳ね返った球が落ちる所（ポールの手前・m）と、弾んで止まる所（ポールの手前・m）。どちらも柵の手前のウォーニングトラック。
    static let poleDropBack: Double = 3
    static let poleRestBack: Double = 6
    /// 跳ね返る瞬間に球が上へ跳ねる速さ（m/s・「カーン」と少し浮いてから落ちる）。
    static let poleKickUp: Double = 2.5

    /// ポール直撃: ふつうの柵越えの放物線（柵の上を越えてスタンドへ落ちる）をポールの所で切って当て、本塁側へ跳ね返って
    /// ポールの足元（柵の手前）へ落ち、小さく弾んで止まる。放物線がポールの先より高いときは先の少し下に当てる。
    private static func poleHit(_ ball: HomerunBattedBall) -> [Segment] {
        let contactS = poleContactS
        let landing = Point(s: max(ball.distance, poleS + 8), y: ballRadius)
        let full = flight(to: landing, elevation: elevation(for: ball.launch), over: [Point(s: poleS, y: fenceClearance)])
        let u = (contactS - start.s) / (landing.s - start.s)
        var hit = full.point(at: u)
        let f: Segment
        if hit.y <= poleContactMaxY, case .arc(let bulge) = full.motion {
            // 放物線の途中の弦のふくらみは、弦の長さの 2 乗に比例する（同じ放物線の一部を切り出す）。
            f = make(from: start, to: hit, .arc(bulge: bulge * u * u))
        } else {
            hit = Point(s: contactS, y: poleContactMaxY)
            f = flight(to: hit, elevation: elevation(for: ball.launch))
        }
        // 跳ね返り: 少し上へ跳ねてから重力で落ちる放物線。落ちる時間 T は y(t) = h + v·t − g·t²/2 = 地面 から、
        // ふくらみ（`Segment.arc`）は g·T²/8（`naturalDuration` の逆）。
        let drop = Point(s: poleS - poleDropBack, y: ballRadius)
        let h = hit.y - drop.y
        let fall = (poleKickUp + sqrt(poleKickUp * poleKickUp + 2 * gravity * h)) / gravity
        let back = make(from: hit, to: drop, .arc(bulge: gravity * fall * fall / 8))
        return [f, back] + bounces(from: drop, rest: poleS - poleRestBack, firstHop: 0.6)
    }

    // MARK: 場外（#1654・会長決裁 2026-10-01）

    /// スタンドの最後列の段の後端（前縁からの奥行き・m）。外野のスタンドはここで終わる（後ろの壁・屋根は内野側だけ）。
    static var standBackEdgeDepth: Float {
        typealias Stand = HomerunToonModel.Stand
        return Stand.treadBack(row: Stand.rows - 1)
    }

    /// 場外になる距離（本塁から・m）: 方向 `degrees` のスタンドの最後列の後端。球場の見た目と同じ `HomerunToonModel.standFront`
    /// から出すので、柵の距離（`HomerunJudge.fence`）+ 柵からスタンドの前縁 2m + 最後列の後端の奥行きになる
    /// （両翼 ±45° ≈ 126.5m・中堅 ≈ 148.5m）。中堅のバックスクリーンの方向（座席が無い）も同じ線で数える。
    static func outOfParkDistance(atDirection degrees: Double) -> Double {
        Double(HomerunToonModel.standFront(degrees, depth: standBackEdgeDepth))
    }

    /// スタンドの最後列の座席の背もたれの上端（m）。場外の打球はここより `outOfParkClearance` 上を抜けていく。
    static var standBackTop: Double {
        typealias Stand = HomerunToonModel.Stand
        return Double(Stand.treadTop(row: Stand.rows - 1) + Stand.seatBackHeight)
    }
    /// 場外の打球が後端・バックスクリーン・スコアボードの上に空ける高さ（m）。
    static let outOfParkClearance: Double = 2
    /// 場外の打球が消える所: スタンドの後端からこれだけ先（m）。後端を越えて抜けていくのが見えてから消える。
    static let vanishBeyond: Double = 3

    /// 場外: 柵とスタンドの上を越えて最後列の後端の上を抜け、その `vanishBeyond` m 先で消える（スタンドに落ちて止まらない）。
    /// 中堅（バックスクリーン・スコアボードの幅の中）はその上も越える。道は 1 本の放物線を後端で 2 区間に分けたもの。
    private static func outOfPark(_ ball: HomerunBattedBall) -> [Segment] {
        let radians = ball.direction * .pi / 180
        let edge = outOfParkDistance(atDirection: ball.direction)
        var obstacles = [Point(s: ball.fence, y: fenceClearance)]
        var exitY = standBackTop + outOfParkClearance
        let screenS = battersEyeZ / cos(radians)
        if abs(screenS * sin(radians)) < battersEyeHalfWidth {
            obstacles.append(Point(s: screenS, y: battersEyeHeight + ballRadius + outOfParkClearance))
        }
        let boardS = scoreboardZ / cos(radians)
        if abs(boardS * sin(radians)) < scoreboardHalfWidth {
            let over = scoreboardTop + ballRadius + outOfParkClearance
            obstacles.append(Point(s: boardS, y: over))
            exitY = max(exitY, over)
        }
        let exit = Point(s: edge, y: exitY)
        let f = flight(to: exit, elevation: elevation(for: ball.launch), over: obstacles)
        guard case .arc(let bulge) = f.motion else { return [f] }
        // 同じ放物線（y = y0 + slope·x − k·x²・x は打ち出す点から）を後端の先 `vanishBeyond` m まで伸ばす。
        let L = edge - start.s, k = 4 * bulge / (L * L)
        let slope = (exit.y - start.y + k * L * L) / L
        let x = L + vanishBeyond
        let end = Point(s: start.s + x, y: start.y + slope * x - k * x * x)
        // 水平は同じ速さのまま（`naturalDuration` はふくらみの下限 0.02m で短い区間を長くするので、長さの比で決める）。
        let beyond = Segment(from: exit, to: end, motion: .arc(bulge: k * vanishBeyond * vanishBeyond / 4),
                             duration: f.duration * vanishBeyond / L)
        return [f, beyond]
    }

    /// スタンドの前縁から奥へ `depth` m の座面の上面の高さ（m）。前縁の手前（柵との間）は地面（0）。
    static func standSurface(depth: Double) -> Double {
        typealias Stand = HomerunToonModel.Stand
        guard depth >= Double(Stand.depth(row: 0)) - Double(Stand.seatSize) / 2 else { return 0 }
        let row = (0..<Stand.rows).min { abs(Double(Stand.depth(row: $0)) - depth) < abs(Double(Stand.depth(row: $1)) - depth) } ?? 0
        return Double(Stand.height(row: row) + Stand.seatHeight / 2)
    }

    /// 区間の長さを、全体が `available` 秒に収まるよう同じ割合で縮める（収まっていればそのまま）。
    private static func fitted(_ segments: [Segment], into available: TimeInterval) -> [Segment] {
        let total = segments.reduce(0) { $0 + $1.duration }
        guard total > available, total > 0 else { return segments }
        let k = available / total
        return segments.map { Segment(from: $0.from, to: $0.to, motion: $0.motion, duration: $0.duration * k) }
    }

    // MARK: カメラ

    /// 打球を追う 1 コマ（カメラと球）。
    struct Frame: Equatable {
        var camera: HomerunAtBatLayout.Camera
        var ball: SIMD3<Float>
        var ballScale: Float
        /// 場外の球が消えた後（#1654）。カメラはそのまま、球と影だけ描かない。
        var ballHidden = false
        /// 月まで飛んだ打球（#1680）の月・夜空の見え方。ふだんの打球は nil。
        var moon: HomerunMoonShot.Look? = nil
        /// 描く球の位置（消えた後は nil = 球も影も出さない）。
        var visibleBall: SIMD3<Float>? { ballHidden ? nil : ball }
    }

    /// 球が本塁から `ball` m のときのカメラの本塁からの水平距離（m）。
    static func cameraDistance(ball: Double, fence: Double) -> Double {
        min(ball - (trailBase + trailGrowth * ball), fence - cameraFenceMargin)
    }

    /// 柵（高さ 3.2m + 黄色の上線）の上端（m）と、柵越しに球を見る視線が上端の上に空ける余裕（m）。
    static let fenceTop: Double = 3.45
    static let sightClearance: Double = 0.5
    /// 柵越しに見るために上げるカメラの高さの上限（m）。
    static let maxCameraHeight: Double = 30
    /// 飛んでいる時間のこの割合からカメラを上げ始める。
    static let liftStart: Double = 0.4

    /// 柵の向こうで止まる球（柵越え）を、止まった所のカメラから柵越しに見るのに要る高さ（m・`maxCameraHeight` まで）。
    /// スタンドの前の方の座席は柵の上端より低く、低いカメラからは柵に隠れる（#1645 でカメラを柵から離したので必要になった）。
    /// 柵の手前で止まる球は 0。
    static func overFenceHeight(_ track: Track) -> Double {
        let fence = HomerunJudge.fence(atDirection: track.direction)
        let rest = track.rest
        let camS = cameraDistance(ball: rest.s, fence: fence)
        guard rest.s > fence, camS < fence else { return 0 }
        // カメラ（camS, h）から球（rest）への視線が柵の位置で上端 + 余裕を通る h。
        let f = (fence - camS) / (rest.s - camS)
        return min(max((fenceTop + sightClearance - rest.y * f) / (1 - f), 0), maxCameraHeight)
    }

    private static func smoothstep(_ x: Double) -> Double {
        let k = min(max(x, 0), 1)
        return k * k * (3 - 2 * k)
    }

    /// 当たってから `t` 秒のコマ。カメラは球の後ろ（本塁側）・少し上から球を見る。
    static func frame(_ track: Track, at t: TimeInterval) -> Frame {
        let p = track.point(at: t)
        // 着いた後の弾みでカメラが上下に揺れないよう、高さは飛んでいる間だけ球に付いていき、その後は着いた高さのまま。
        let followY = t < track.flightDuration ? p.y : track.landing.y
        let fence = HomerunJudge.fence(atDirection: track.direction)
        let camS = cameraDistance(ball: p.s, fence: fence)
        // 柵の向こうに落ちる球は、落ちていく間にカメラを柵越しに見える高さ（`overFenceHeight`）へなめらかに上げる。
        let lift = smoothstep((t - track.flightDuration * liftStart) / (track.flightDuration * (1 - liftStart)))
        let height = max(cameraBaseHeight + cameraHeightFollow * followY, overFenceHeight(track) * lift)
        let cameraPosition = world(Point(s: camS, y: height), direction: track.direction)
        // 遠くでは見かけの大きさを保つために球を大きくするので、地面・座面に置いた中心の高さ（`ballRadius`）のままだと
        // 球の下側が埋まる。大きくした分だけ中心を持ち上げる（判定と打球の道は変えない）。持ち上げで距離が変わるので
        // 2 回取り直す（差は 1e-5 倍以下）。
        let base = world(p, direction: track.direction)
        var ball = base
        var scale = ballScale(distance: Double(simd_distance(cameraPosition, ball)))
        for _ in 0..<2 {
            ball = base + SIMD3(0, scale * HomerunSwingContact.ballRadius - Float(ballRadius), 0)
            scale = ballScale(distance: Double(simd_distance(cameraPosition, ball)))
        }
        let camera = HomerunAtBatLayout.Camera(position: cameraPosition, target: ball, verticalFieldOfView: verticalFieldOfView)
        return Frame(camera: camera, ball: ball, ballScale: scale, ballHidden: track.vanishesAtEnd && t >= track.duration)
    }
}

extension HomerunBattedBall {
    /// 場外（#1654）: 柵越えのうち、飛距離がその方向のスタンドの最後列の後端（`HomerunBallChase.outOfParkDistance`）以上。
    /// 表示だけ（得点の上乗せなし）。保存（`HomerunShot`）の方向・距離・種別から毎回出すので、保存の形は変えない。
    /// 月まで飛んだ打球（#1680）・ポール直撃（#1686）は場外より優先（場外にしない）。
    var isOutOfPark: Bool {
        !isMoon && !isPoleHit && kind == .homer && distance >= HomerunBallChase.outOfParkDistance(atDirection: direction)
    }
}

extension HomerunSwingPlan {
    /// 3D の球がバットに当たる（打点に着く）時刻。当たり以上（ファウルを含む）で振ったときだけ。
    var contactAt: Date? {
        guard phase == .ballResult, let clock, let release = clock.releasedAt, let offset = clock.timingOffset,
              let ball = lastBall, ball.kind != .miss else { return nil }
        return HomerunSwingContact.contactShownTime(release: release, offsetMilliseconds: offset,
                                                    column: HomerunSwingContact.column(zone: clock.zone))
    }

    /// 打球の道（当たり以上のときだけ）。月まで飛んだ打球（#1680）は道を持たず、`HomerunMoonShot` が時刻から描く。
    var chaseTrack: HomerunBallChase.Track? {
        guard contactAt != nil, let lastBall, !lastBall.isMoon else { return nil }
        return HomerunBallChase.track(for: lastBall)
    }

    /// 打球を追うカメラのコマ。当たってから `HomerunBallChase.cutDelay` 秒たつまでは nil（打席のカメラのまま）。
    func chaseFrame(at now: Date) -> HomerunBallChase.Frame? {
        guard let contactAt else { return nil }
        let t = now.timeIntervalSince(contactAt)
        guard t >= HomerunBallChase.cutDelay else { return nil }
        if let moon = lastBall?.moon { return HomerunMoonShot.frame(moon, at: t) }
        guard let track = chaseTrack else { return nil }
        return HomerunBallChase.frame(track, at: t)
    }

    /// 結果のカードを出す時刻: 打球が止まって（柵越えはスタンドに落ちて）から `restHold` 秒後。当たり以上でなければ nil。
    var chaseCardAt: Date? {
        guard let contactAt else { return nil }
        if let moon = lastBall?.moon { return contactAt.addingTimeInterval(HomerunMoonShot.cardDelay(moon)) }
        guard let track = chaseTrack else { return nil }
        // ジャストミートの演出（#1775）の間は表示の時間が止まっていたぶん、カードも遅らせる。
        let held = HomerunJustMeet.applies(to: lastBall) ? HomerunJustMeet.extraDuration : 0
        return contactAt.addingTimeInterval(track.duration + HomerunBallChase.restHold + held)
    }
}
