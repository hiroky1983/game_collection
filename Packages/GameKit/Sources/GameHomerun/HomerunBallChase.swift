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
    static func limit(for kind: HomerunKind) -> TimeInterval {
        switch kind {
        case .homer: 3.0
        case .fenceHit, .inPlay: 2.4
        case .foul: 2.0
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

    // MARK: 見た目の定数

    /// 追うカメラで見せる球の半径（m）。実寸（0.037m）では数十 m 先で見えないので大きくする（以前の外野カメラと同じ扱い）。
    static let ballRadius: Double = 0.3
    /// 打席の 3D の球（実寸）をこの倍率に拡大して見せる。
    static var ballScale: Float { Float(ballRadius) / HomerunSwingContact.ballRadius }
    /// 打ち出す点（本塁の少し前・打点の高さ）。
    static let start = Point(s: 0.5, y: 1.0)
    /// 柵（高さ 3.2m + 黄色の上線）を越える打球が、柵の真上で通る最低の高さ（球の中心・m）。
    static let fenceClearance: Double = 4.6
    /// フェンス直撃の球の中心が止まる、柵の面からの距離（m）。
    static let fenceContactInset: Double = 0.4
    static let gravity: Double = 9.8
    /// 追うカメラの縦の画角（度）。
    static let verticalFieldOfView: Float = 40
    /// カメラは球の後ろ（本塁側）`trailBase + trailGrowth × 球の距離` に置く（遠くへ飛ぶほど少し引いて、球場を広く映す）。
    static let trailBase: Double = 12
    static let trailGrowth: Double = 0.25
    /// カメラの高さ = `cameraBaseHeight + cameraHeightFollow × 球の高さ`（上がる球を下から見上げすぎない）。
    static let cameraBaseHeight: Double = 3
    static let cameraHeightFollow: Double = 0.4
    /// カメラは柵のこれだけ手前より先へは出ない（柵越えの球を追ってスタンドへ入り込まない）。
    static let cameraFenceMargin: Double = 12

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
        let hop = make(from: landing, to: Point(s: landing.s + 1.2, y: landing.y), .arc(bulge: 0.5))
        return [f, hop]
    }

    /// バックスクリーン（`HomerunToonModel.stadium` の中堅の板: 幅 26m・高さ 15m・z = 125.5 の厚さ 1m）の手前の面。
    static let battersEyeZ: Double = 125.0
    static let battersEyeHalfWidth: Double = 13
    static let battersEyeHeight: Double = 15

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
    }

    /// 当たってから `t` 秒のコマ。カメラは球の後ろ（本塁側）・少し上から球を見る。
    static func frame(_ track: Track, at t: TimeInterval) -> Frame {
        let p = track.point(at: t)
        // 着いた後の弾みでカメラが上下に揺れないよう、高さは飛んでいる間だけ球に付いていき、その後は着いた高さのまま。
        let followY = t < track.flightDuration ? p.y : track.landing.y
        let fence = HomerunJudge.fence(atDirection: track.direction)
        let camS = min(p.s - (trailBase + trailGrowth * p.s), fence - cameraFenceMargin)
        let camera = HomerunAtBatLayout.Camera(
            position: world(Point(s: camS, y: cameraBaseHeight + cameraHeightFollow * followY), direction: track.direction),
            target: world(p, direction: track.direction),
            verticalFieldOfView: verticalFieldOfView)
        return Frame(camera: camera, ball: world(p, direction: track.direction), ballScale: ballScale)
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

    /// 打球の道（当たり以上のときだけ）。
    var chaseTrack: HomerunBallChase.Track? {
        guard contactAt != nil, let lastBall else { return nil }
        return HomerunBallChase.track(for: lastBall)
    }

    /// 打球を追うカメラのコマ。当たってから `HomerunBallChase.cutDelay` 秒たつまでは nil（打席のカメラのまま）。
    func chaseFrame(at now: Date) -> HomerunBallChase.Frame? {
        guard let contactAt, let track = chaseTrack else { return nil }
        let t = now.timeIntervalSince(contactAt)
        guard t >= HomerunBallChase.cutDelay else { return nil }
        return HomerunBallChase.frame(track, at: t)
    }

    /// 結果のカードを出す時刻: 打球が止まって（柵越えはスタンドに落ちて）から `restHold` 秒後。当たり以上でなければ nil。
    var chaseCardAt: Date? {
        guard let contactAt, let track = chaseTrack else { return nil }
        return contactAt.addingTimeInterval(track.duration + HomerunBallChase.restHold)
    }
}
