import Foundation
import simd
import HomerunCore

/// Meshy の打者（`HomerunBatter.usdz`）のバットの軌跡。USDZ の骨（`RightHand/Bat`）とバットの点群から
/// 実寸で測った値（`HomerunBatPath+Samples.swift`・scratchpad の `measure_bat.py` / `subframe.py` で生成）。
/// 打者の局所座標（メートル・y 上・1 コマ目で胸が +z）。打席の世界座標へは `HomerunAtBatLayout.batterWorld` で置く。
enum HomerunBatPath {
    /// 表の刻み（Hz）とクリップのコマ（fps）。
    static let sampleRate: TimeInterval = 120
    static let frameRate: TimeInterval = 30
    static var sampleCount: Int { samples.count / 6 }
    /// クリップの長さ（44 コマ = 43/30 秒）。
    static var duration: TimeInterval { TimeInterval(sampleCount - 1) / sampleRate }
    /// 骨 Bat の局所でのグリップ端と先端（USDZ の BatWood の点群を主成分で直線に当てた両端。長さ 0.80m）。
    static let gripInBatJoint: SIMD3<Float> = [0, 0, -0.048]
    static let tipInBatJoint: SIMD3<Float> = [0, 0, 0.754]
    /// 太い方の半径（m）。点群の径の最大は 0.0445（グリップエンド）、打つ部分は 0.035。
    static let barrelRadius: Float = 0.035

    /// クリップ時刻 `t`（秒・0 = 1 コマ目・`frame = t * 30 + 1`）のバット（線分）。表の間は線形補間、外は端で止める。
    static func segment(atClipTime t: TimeInterval) -> (grip: SIMD3<Float>, tip: SIMD3<Float>) {
        let position = min(max(t, 0), duration) * sampleRate
        let i0 = min(Int(position.rounded(.down)), sampleCount - 1)
        let i1 = min(i0 + 1, sampleCount - 1)
        let a = Float(position - TimeInterval(i0))
        func row(_ i: Int, _ offset: Int) -> SIMD3<Float> {
            [samples[i * 6 + offset], samples[i * 6 + offset + 1], samples[i * 6 + offset + 2]]
        }
        return (grip: simd_mix(row(i0, 0), row(i1, 0), SIMD3(repeating: a)),
                tip: simd_mix(row(i0, 3), row(i1, 3), SIMD3(repeating: a)))
    }

    /// クリップ時刻をコマ番号（1 始まり・小数）に直す。
    static func frame(atClipTime t: TimeInterval) -> Double { t * frameRate + 1 }
}

/// 打者の動きの段階（試作）。1 本のスイングを 3 つに切って使う。
///
/// USDZ のスイングは、1〜20 コマ目（0.63 秒）が**踏み込み**（バットはほとんど動かない）、21〜30 コマ目で振り抜き、
/// 31〜44 コマ目がフォロースルー。バットが本塁の上（球の通り道）を通るのは約 25.3〜26.3 コマ目
/// （`HomerunSwingContact.contactWindow`）で、振り抜きの起点（20 コマ目）から約 0.18 秒後。
/// 離した瞬間に頭から流すと当たる前に結果が出て見えるので、**輪が的に重なる瞬間にバットが打点に来るよう逆算して振り始める**
/// （`HomerunSwingContact.swingStart(arrival:column:)`）。
enum HomerunBatterMotion: Equatable {
    /// 構え（1 コマ目で止める）。
    case stance
    /// 踏み込み（1〜20 コマ目を流して 20 コマ目で止める）。
    case load
    /// 振り抜き〜フォロースルー（20 コマ目から最後まで）。`start` は 20 コマ目を置く実時刻。過去なら途中から流す
    /// （離した瞬間に打点のコマへ合わせ直すときに使う）。
    case swing(start: Date)

    /// 踏み込みの長さ（秒・20 コマ目 = 19/30 秒）。振り抜きはここから始まる。
    static let loadDuration: TimeInterval = 19.0 / 30
}

/// バットと球が当たる瞬間の同期（試作）。判定（`HomerunJudge`・離した時刻 − 輪が的に重なる時刻）は変えず、
/// 3D の打者と球の見え方だけをそれに合わせる。
///
/// - 打点のコマ: バット（線分）が球の通り道の面 `x = 列の x` を横切るクリップ時刻の区間（`contactWindow`）。
///   打者を `HomerunAtBatLayout.batter` に置いた世界座標で測る。区間の真ん中がジャストの打点（芯・先端から約 15cm）。
/// - 逆算: 輪が的に重なる時刻 `arrival` にジャストの打点のコマが来るよう、`arrival − (打点のクリップ時刻 − 19/30)` に
///   20 コマ目を置いて振り始める（約 0.18 秒前）。振り始めは離す前なので、離すのが早い/遅いときは離した瞬間に
///   コマを合わせ直す（`swingStart(release:offsetMilliseconds:column:)`）。早い = 区間の後ろ（バットが前で当たる = 引っ張り）、
///   遅い = 区間の前（バットが本塁の上で当たる = 流し）。当たり窓（±110ms）の端で区間の端になる。
/// - 見送り: 振り始めの時刻に押していなければ振らない（踏み込みのまま）。押したまま離さなかったときは振り抜く
///   （判定と同じ「空振り」扱い）。球は打点より `approachLift` 上を通るので、バットは球の下を通り抜ける。
enum HomerunSwingContact {
    /// ゾーンの 1 マスの世界の大きさ（m）。9 分割の中心の列 (-1, 0, +1)・行がこの間隔で並ぶ（ゾーンの幅 0.36m ≒ 本塁の幅 0.43m）。
    static let zoneCellMeters: Float = 0.12
    /// 球の半径（m・硬式球 7.4cm）。
    static let ballRadius: Float = 0.037
    /// 投球の通り道（当たらなかったときの球）は打点（バットの軸）よりこれだけ上（m）。バットの上面と球の下面に 2.8cm の隙間。
    static let approachLift: Float = 0.10
    /// 当たったとき: 球の中心はバットの軸から半径の和だけ上（表面どうしが触れる）。
    static var contactLift: Float { HomerunBatPath.barrelRadius + ballRadius }
    /// 振り抜きの起点（クリップ秒・20 コマ目）。
    static var swingClipStart: TimeInterval { HomerunBatterMotion.loadDuration }
    /// 打点の探索の刻み（秒・表の刻みと同じ）。
    static let scanStep: TimeInterval = 1 / HomerunBatPath.sampleRate

    /// 9 分割のゾーン（0 = 左上 … 8 = 右下）の列（-1 = 左・0 = 真ん中・+1 = 右）。HUD の右 = 世界の +x（一塁側）。
    static func column(zone: Int) -> Int { min(max(zone, 0), 8) % 3 - 1 }
    /// 列の球の通り道（面 x = 一定）。
    static func ballLineX(column: Int) -> Float { Float(column) * zoneCellMeters }

    /// クリップ時刻 `t` にバットが面 `x` を横切る点（世界座標・前のカメラの置き方）。横切っていなければ nil。
    static func crossing(atClipTime t: TimeInterval, x: Float) -> SIMD3<Float>? {
        let s = HomerunBatPath.segment(atClipTime: t)
        let grip = HomerunAtBatLayout.batterWorld(s.grip), tip = HomerunAtBatLayout.batterWorld(s.tip)
        let dx = tip.x - grip.x
        guard (grip.x - x) * (tip.x - x) <= 0, abs(dx) > 1e-6 else { return nil }
        let a = (x - grip.x) / dx
        return grip + (tip - grip) * a
    }

    /// バットが列の通り道を横切っているクリップ時刻の区間（振り抜きの中・最初の連続した区間）。
    struct ContactWindow: Equatable {
        var enter: TimeInterval
        var exit: TimeInterval
        /// ジャストの打点（区間の真ん中）。
        var just: TimeInterval { (enter + exit) / 2 }
    }

    static func contactWindow(column: Int) -> ContactWindow {
        let x = ballLineX(column: column)
        var t = swingClipStart
        var enter: TimeInterval?
        var last: TimeInterval = swingClipStart
        while t <= HomerunBatPath.duration + 1e-9 {
            if crossing(atClipTime: t, x: x) != nil {
                if enter == nil { enter = t }
                last = t
            } else if enter != nil {
                break
            }
            t += scanStep
        }
        // 届かない列は無い（打者の置き方で保証・テストで固定）。万一無ければ振り抜きの真ん中を返す。
        guard let enter else { return ContactWindow(enter: 25.0 / 30, exit: 26.0 / 30) }
        return ContactWindow(enter: enter, exit: last)
    }

    /// 離したときのずれ（ms・負が早い）に対する打点のクリップ時刻。ジャストで区間の真ん中、早いほど後ろ（バットが前で当たる）、
    /// 遅いほど前。当たり窓（±110ms）の端で区間の端、外はそこで止める。
    static func contactClipTime(column: Int, offsetMilliseconds offset: Double) -> TimeInterval {
        let w = contactWindow(column: column)
        let k = min(max(-offset / HomerunTiming.hitWindow, -1), 1)
        return w.just + k * (w.exit - w.enter) / 2
    }

    /// 当たったときの球の中心（世界座標）: そのずれの打点でバットが通り道を横切る点の、半径の和だけ上。
    static func contactPoint(column: Int, offsetMilliseconds offset: Double) -> SIMD3<Float> {
        let t = contactClipTime(column: column, offsetMilliseconds: offset)
        let x = ballLineX(column: column)
        let p = crossing(atClipTime: t, x: x) ?? crossing(atClipTime: contactWindow(column: column).just, x: x) ?? [x, 0.9, 0]
        return p + [0, contactLift, 0]
    }

    /// 投球が輪の重なる瞬間に着く点（世界座標）: ジャストの打点の `approachLift` 上。
    static func approachTarget(column: Int) -> SIMD3<Float> {
        let x = ballLineX(column: column)
        let p = crossing(atClipTime: contactWindow(column: column).just, x: x) ?? [x, 0.9, 0]
        return p + [0, approachLift, 0]
    }

    /// 振り始め（20 コマ目を置く実時刻）: 輪が的に重なる `arrival` にジャストの打点が来るよう逆算する。
    static func swingStart(arrival: Date, column: Int) -> Date {
        arrival.addingTimeInterval(-(contactWindow(column: column).just - swingClipStart))
    }

    /// 離した瞬間 `release`（ずれ `offset` ms）にその打点のコマが来るよう合わせ直した振り始め。
    static func swingStart(release: Date, offsetMilliseconds offset: Double, column: Int) -> Date {
        release.addingTimeInterval(-(contactClipTime(column: column, offsetMilliseconds: offset) - swingClipStart))
    }
}

/// 3D の球の飛び方（試作）。投球は投手の手からジャストの打点の上まで直線・等速、当たれば打点から放物線。
enum HomerunBallFlight {
    /// 投手の手（リリース点・世界座標）。右投げの投手（マウンド 17.4m・本塁を向く）の右手。
    static let releasePoint: SIMD3<Float> = [-0.25, 1.9, 16.8]
    /// ここより後ろ（捕手のミット）に入ったら消す。
    static let mittZ: Float = -1.5
    static let gravity: Float = 9.8

    /// 投球中の球の位置。的が出る `pitchStart` に手を離れ、`arrival` に `approachTarget` へ着き、その後も同じ速さで進む。
    /// 的が出る前・ミットに入った後は nil。
    static func pitchPosition(at now: Date, pitchStart: Date, arrival: Date, column: Int) -> SIMD3<Float>? {
        let travel = arrival.timeIntervalSince(pitchStart)
        guard travel > 0 else { return nil }
        let k = Float(now.timeIntervalSince(pitchStart) / travel)
        guard k >= 0 else { return nil }
        let target = HomerunSwingContact.approachTarget(column: column)
        let p = releasePoint + (target - releasePoint) * k
        return p.z < mittZ ? nil : p
    }

    /// 打球の初速（m/s・世界座標）。方向は判定の `direction`（0 = 中堅・負が左 = -x）、打ち上げ角は帯の中心、
    /// 速さは飛距離が出る初速（空気抵抗なし）。ファウルは 28m/s の固定。
    static func battedVelocity(_ ball: HomerunBattedBall) -> SIMD3<Float> {
        let elevation: Double = switch ball.launch {
        case .grounder: 8
        case .liner: 18
        case .fly: 30
        case .pop: 50
        case nil: 30
        }
        let theta = elevation * .pi / 180
        let speed: Double = ball.kind == .foul ? 28 : min(max(sqrt(ball.distance * Double(gravity) / sin(2 * theta)), 15), 45)
        let d = ball.direction * .pi / 180
        return SIMD3<Float>(Float(sin(d) * cos(theta)), Float(sin(theta)), Float(cos(d) * cos(theta))) * Float(speed)
    }

    /// 打球の位置: 打点 `contact` から `release` に初速 `velocity` で放物線。地面（球の半径）より下へは行かない。
    static func battedPosition(at now: Date, contact: SIMD3<Float>, release: Date, velocity: SIMD3<Float>) -> SIMD3<Float> {
        let t = Float(max(now.timeIntervalSince(release), 0))
        var p = contact + velocity * t
        p.y -= 0.5 * gravity * t * t
        p.y = max(p.y, HomerunSwingContact.ballRadius)
        return p
    }
}

/// 1 球の 3D の見せ方（打者の段階と球の位置）を、モデルの記録（`HomerunModel.BallClock`）と時刻から決める純粋な関数。
struct HomerunSwingPlan {
    var phase: HomerunModel.Phase
    var clock: HomerunModel.BallClock?
    var isHolding: Bool
    var lastBall: HomerunBattedBall?

    @MainActor
    init(model: HomerunModel) {
        phase = model.phase
        clock = model.ballClock
        isHolding = model.isHolding
        lastBall = model.lastBall
    }

    init(phase: HomerunModel.Phase, clock: HomerunModel.BallClock?, isHolding: Bool, lastBall: HomerunBattedBall?) {
        self.phase = phase
        self.clock = clock
        self.isHolding = isHolding
        self.lastBall = lastBall
    }

    private var column: Int { HomerunSwingContact.column(zone: clock?.zone ?? 4) }
    /// 逆算した振り始め（20 コマ目の実時刻）。
    var anticipatedSwingStart: Date? { clock.map { HomerunSwingContact.swingStart(arrival: $0.arrival, column: column) } }

    /// 振り始めの時刻に押していた（= 逆算した振りが始まった）か。
    var isArmed: Bool {
        guard let clock, let start = anticipatedSwingStart, let pressedAt = clock.pressedAt, pressedAt <= start else { return false }
        if let releasedAt = clock.releasedAt { return releasedAt >= start }
        return phase == .pitching ? isHolding : true
    }

    /// 打者の段階。
    func batterMotion(at now: Date) -> HomerunBatterMotion {
        guard let clock, let start = anticipatedSwingStart else { return .stance }
        switch phase {
        case .pitching:
            if now >= start, isArmed { return .swing(start: start) }
            // 踏み込みは振り始めに 20 コマ目が来るよう、その 19/30 秒前から。
            return now >= start.addingTimeInterval(-HomerunBatterMotion.loadDuration) ? .load : .stance
        case .ballResult:
            guard let release = clock.releasedAt, let offset = clock.timingOffset else {
                // 見送り: 押したまま離さなかったなら振り抜く、押していなければ振らない。
                return isArmed ? .swing(start: start) : .stance
            }
            if abs(offset) <= HomerunTiming.hitWindow || (offset < 0 && isArmed) {
                // 当たり窓の中（と、振り始めた後の早い空振り）は離した瞬間にその打点のコマへ合わせ直す。
                return .swing(start: HomerunSwingContact.swingStart(release: release, offsetMilliseconds: offset, column: column))
            }
            // 振り始める前の早い空振りは離した瞬間から頭（20 コマ目）で振る。遅い空振りは振り始めた通りに振り抜く。
            return isArmed ? .swing(start: start) : .swing(start: release)
        case .idle, .finished:
            return .stance
        }
    }

    /// 3D の球の位置（世界座標・前のカメラの置き方）。見せない間は nil。
    func ballPosition(at now: Date) -> SIMD3<Float>? {
        guard let clock else { return nil }
        switch phase {
        case .pitching:
            return HomerunBallFlight.pitchPosition(at: now, pitchStart: clock.pitchStart, arrival: clock.arrival, column: column)
        case .ballResult:
            if let release = clock.releasedAt, let offset = clock.timingOffset, let ball = lastBall, ball.kind != .miss {
                let contact = HomerunSwingContact.contactPoint(column: column, offsetMilliseconds: offset)
                return HomerunBallFlight.battedPosition(at: now, contact: contact, release: release,
                                                        velocity: HomerunBallFlight.battedVelocity(ball))
            }
            // 空振り・見送り: そのままミットへ。
            return HomerunBallFlight.pitchPosition(at: now, pitchStart: clock.pitchStart, arrival: clock.arrival, column: column)
        case .idle, .finished:
            return nil
        }
    }
}
