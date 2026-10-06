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
/// （`HomerunSwingContact.contactWindow`）で、振り抜きの起点（20 コマ目）から約 0.2 秒後（`HomerunSwingContact.lead`）。
/// **振りは離した瞬間にだけ始め、始まったら最後まで振り切る**（#1594。押しっぱなしで先読みして振ったり、巻き戻したりしない）。
/// 本番の振りは、離した瞬間に 20 コマ目から速めに流して振り抜きの途中の予定に追いつく（ジャスト・遅いなら打点のコマ、早いなら球が来たときに打点のコマに
/// なる手前・`HomerunSwingContact.swingStart`。判定の 0 = 3D の球が打点に来る瞬間・#1594 会長決裁 A）。素振りは 20 コマ目から流す。当たる瞬間の見た目は球の側を合わせる（`HomerunSwingPlan.ballPosition`）。
enum HomerunBatterMotion: Equatable {
    /// 構え（1 コマ目で止める）。
    case stance
    /// 踏み込み（1〜20 コマ目を流して 20 コマ目で止める）。`start` は 1 コマ目を置く実時刻。過去なら途中から流す
    /// （素振りの振り抜きが踏み込みの始まりより後に終わったとき、当たり窓の始まりに 20 コマ目が間に合うように）。
    case load(start: Date)
    /// 振り抜き〜フォロースルー（20 コマ目から最後まで）。`start` は 20 コマ目を置く実時刻。素振りは離した時刻、
    /// 本番の振りは離した時刻より前（`HomerunSwingContact.swingStart`）。
    /// `catchUpFrom`（本番の振りの離した時刻）があれば、その瞬間に 20 コマ目から `catchUpSpeed` 倍で流し、`start` の予定に
    /// 追いついたら等速に戻す（`swingOffset`）。以前は離した瞬間に振り抜きの前半（約 0.2 秒ぶん）を飛ばして打点のコマを
    /// 出していたため、構えから振り終わりまでが一瞬に見えた（会長 QA 2026-09-30・画面の E2E の録画で確認）。
    case swing(start: Date, catchUpFrom: Date? = nil)
    /// 空振りで回って倒れて目を回す演出（#1681・`HomerunWhiffGag`）。振り抜き（`start`・`catchUpFrom` は `swing` と同じ）から
    /// そのまま回転・尻もち・座って頭をぐるぐるまで流し、最後のコマで止める。
    case whiffGag(start: Date, catchUpFrom: Date? = nil)
    /// 打ち上げた球が自分の頭に落ちてたんこぶ（#1793・`HomerunTankobuGag`）。`start`・`catchUpFrom` は `swing` と同じ。振り終わりで球を待ち、
    /// 頭に当たったら空振りの演出のクリップの途中（50 コマ目）から尻もちを流す。
    case tankobu(start: Date, catchUpFrom: Date? = nil)

    /// 踏み込みの長さ（秒・20 コマ目 = 19/30 秒）。振り抜きはここから始まる。
    static let loadDuration: TimeInterval = 19.0 / 30
    /// 振り抜き〜フォロースルーの長さ（秒・20〜44 コマ目 = 24/30 秒）。素振りはこれを過ぎたら構え・踏み込みへ戻る。
    static var swingDuration: TimeInterval { HomerunBatPath.duration - loadDuration }
    /// 本番の振りで、飛ばしていた振り抜きの前半を追いつくまで流す速さ（倍）。3 倍 = 打点のコマはジャストで離した約 0.065 秒後、
    /// 約 0.1 秒で予定に追いつく（2 倍だと打点が約 0.1 秒遅れ、早すぎる空振り（-111ms）でバットが球に触れて見えた）。判定（離した時刻）は変えず、当たる瞬間の見た目は球の側を合わせる
    /// （`HomerunSwingContact.contactShownTime`）。
    static let catchUpSpeed: Double = 3

    /// 振り抜きの再生位置（20 コマ目からの秒）。`start` の予定どおりなら `now - start`。`catchUpFrom` があればそこから
    /// `catchUpSpeed` 倍で流し、予定に追いついたら予定どおり。
    static func swingOffset(start: Date, catchUpFrom: Date?, at now: Date) -> TimeInterval {
        let scheduled = now.timeIntervalSince(start)
        guard let from = catchUpFrom, from > start else { return max(scheduled, 0) }
        return max(min(catchUpSpeed * now.timeIntervalSince(from), scheduled), 0)
    }
}

/// バットと球が当たる瞬間の同期（試作）。判定（`HomerunJudge`・離した時刻 − 輪が的に重なる時刻）は変えず、
/// 3D の打者と球の見え方だけをそれに合わせる。**輪が的に重なる瞬間 = 3D の球が打点に来る瞬間 = 判定の 0**
/// （#1594 会長決裁 A・2026-09-30。球を見て、球がバットに来た瞬間に離せばジャスト）。
///
/// - 打点のコマ: バット（線分）が球の通り道の面 `x = 列の x` を横切るクリップ時刻の区間（`contactWindow`）。
///   打者を `HomerunAtBatLayout.batter` に置いた世界座標で測る。区間の真ん中がジャストの打点（芯・先端から約 15cm）。
/// - 3D の球は輪が的に重なる時刻に打点へ着くよう投げる（`HomerunSwingPlan.ballArrival`・投げてから 1.2 秒）。
///   振りは離した瞬間に始まり（#1594）、本番の振りは振り抜きの途中から流して、ジャストならその瞬間に打点のコマを出す
///   （`swingStart`: 20 コマ目を離した `lead` 前に置き、振り抜きの前半約 0.2 秒は飛ばす。早いときは球が来る瞬間に
///   打点のコマになるよう、その分だけ手前から流す）。以前は 20 コマ目から流していたため、打点のコマが
///   離した `lead`（約 0.195 秒）後になり、球もその分遅らせて投げていた（球に合わせて離すと必ず「振るのが遅い」だった）。
///   早い = 区間の後ろ（バットが前で当たる = 引っ張り）、遅い = 区間の前（バットが本塁の上で当たる = 流し）。
///   当たったときは、離した瞬間の球の位置からその打点へ球を寄せて、バットと触れさせる。
/// - 見送り: 押したまま離さなければ振らない（踏み込みのまま）。球は打点より `approachLift` 上を通るので、
///   ジャストで照準を外した空振りでも、バットは球の下を通り抜ける。
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

    /// 9 分割のゾーン（0 = 左上 … 8 = 右下）の列（-1 = 左・0 = 真ん中・+1 = 右）。HUD の右 = 世界の +x（前のカメラの画面の右）。
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

    /// 振り始め（20 コマ目）からジャストの打点のコマまでの時間（秒・約 0.2 秒）。
    static func lead(column: Int) -> TimeInterval { contactWindow(column: column).just - swingClipStart }

    /// 離した瞬間 `release`（ずれ `offset` ms）に振ったとき、バットがその打点のコマに来る時刻。
    /// ジャスト・遅い: 離した瞬間（打点のコマから流す）。早い（当たり窓の中）: 投球の線を来る 3D の球がその打点の奥行きに
    /// 来る瞬間（輪が重なる少し前。早いほど打点は前 = 投手側なので、球はそのぶん早く着く）。振り抜きの途中から流して、
    /// 球が来たときに打点のコマになる。当たり窓の外（空振り）は離した瞬間に打点を通す（早ければ球はまだ来ておらず、
    /// 遅ければもう過ぎている = 空振りに見える）。
    static func contactTime(release: Date, offsetMilliseconds offset: Double, column: Int) -> Date {
        guard offset < 0, -offset <= HomerunTiming.hitWindow else { return release }
        let ahead = contactPoint(column: column, offsetMilliseconds: offset).z - approachTarget(column: column).z
        let ballArrivesIn = -offset / 1000 - Double(ahead / HomerunBallFlight.pitchSpeedZ(column: column))
        return release.addingTimeInterval(max(ballArrivesIn, 0))
    }

    /// バットがその打点のコマを**画面に出す**時刻。振り抜きの前半を飛ばさずに `catchUpSpeed` 倍で流すぶん、
    /// `contactTime` より少し遅れることがある（ジャストで離した約 0.1 秒後）。3D の球はこの時刻に打点へ寄せる。
    static func contactShownTime(release: Date, offsetMilliseconds offset: Double, column: Int) -> Date {
        let start = swingStart(release: release, offsetMilliseconds: offset, column: column)
        let clip = contactClipTime(column: column, offsetMilliseconds: offset) - swingClipStart
        return max(release.addingTimeInterval(clip / HomerunBatterMotion.catchUpSpeed), start.addingTimeInterval(clip))
    }

    /// 本番の振りの 20 コマ目を置く実時刻（離した時刻より前）。`contactTime` にそのずれの打点のコマが来るよう逆算する。
    /// 見せるのは離した瞬間から（その時点のコマから流す）。ジャストなら離した時刻の `lead` 前。
    static func swingStart(release: Date, offsetMilliseconds offset: Double, column: Int) -> Date {
        contactTime(release: release, offsetMilliseconds: offset, column: column)
            .addingTimeInterval(-(contactClipTime(column: column, offsetMilliseconds: offset) - swingClipStart))
    }
}

/// 3D の球の飛び方（試作）。投球はマシンの打ち出し口からジャストの打点の上まで直線・等速、当たれば打点から放物線。
enum HomerunBallFlight {
    /// 打ち出し口（リリース点・世界座標）。マウンドのバッティングマシン（#1612）の車輪の間の前 = [0, 1.3, 17.28]。
    /// マシンの込める球は的が出る瞬間にここへ着き（`HomerunMachineMotion.state`）、そこからこの球が引き継ぐ。
    static let releasePoint: SIMD3<Float> = HomerunAtBatLayout.machineWorld(HomerunMachineMotion.mouth)
    /// 見送り・空振りの球が収まる捕手のミットのポケット（捕手の局所座標・`catcherScale` を掛ける前・`HomerunToonModel.catcher()`）。
    static let mittPocketLocal: SIMD3<Float> = [1.5, 1.72, 1.86]
    /// ミットに収まった球を見せておく時間（秒）。過ぎたら消す（影も一緒に消える）。
    static let mittHold: TimeInterval = 0.35
    static let gravity: Float = 9.8

    /// 見送り・空振りの球が止まる奥行きの基準になる点（`camera` の置き方の世界座標・左右反転するカメラでは捕手と同じく x を鏡映した扱い）。
    /// 球は投球の線のまま進み、この点の z（捕手のミットの深さ）に届いたところで止まって消える（#1771。ミットへ曲げると吸い込まれる
    /// 変化球に見えた・会長 QA 2026-10-02）。以前は z −1.5 まで進めて消していて、ミットを外れて後ろへ突き抜けて見えた（#1655）。
    static func mittPoint(for camera: HomerunAtBatLayout.Camera = HomerunAtBatLayout.camera) -> SIMD3<Float> {
        HomerunAtBatLayout.worldPoint(mittPocketLocal * HomerunAtBatLayout.catcherScale, of: HomerunAtBatLayout.catcher, for: camera)
    }

    /// 投球の奥行きの速さ（m/s・本塁へ向かう -z の向きを正に）。手を離れてから 1.2 秒（輪が縮み切る時間）で打点に着く。
    static func pitchSpeedZ(column: Int) -> Float {
        (releasePoint.z - HomerunSwingContact.approachTarget(column: column).z) / (Float(HomerunPitch.travelMilliseconds) / 1000)
    }

    /// 投球中の球の位置。的が出る `pitchStart` に打ち出し口を出て、`arrival` に `target`（省略時は `approachTarget`・
    /// 画面では `HomerunAtBatLayout.pitchTarget` = 2D の的に重なる点）へ着き、その後は向きも速さも変えずにまっすぐ進んで
    /// 捕手のミット（`mitt`・省略時は前のカメラの `mittPoint`）の深さで止まり、`mittHold` だけ見せて消える。的が出る前・消えた後は nil。
    static func pitchPosition(at now: Date, pitchStart: Date, arrival: Date, column: Int,
                              target: SIMD3<Float>? = nil, mitt: SIMD3<Float>? = nil) -> SIMD3<Float>? {
        let travel = arrival.timeIntervalSince(pitchStart)
        guard travel > 0 else { return nil }
        let k = Float(now.timeIntervalSince(pitchStart) / travel)
        guard k >= 0 else { return nil }
        let target = target ?? HomerunSwingContact.approachTarget(column: column)
        guard k > 1 else { return releasePoint + (target - releasePoint) * k }
        let mitt = mitt ?? mittPoint()
        let after = now.timeIntervalSince(arrival)
        let reach = mittReach(target: target, mitt: mitt, travel: travel)
        let velocity = (target - releasePoint) / Float(travel)
        guard after < reach else { return after < reach + mittHold ? target + velocity * Float(reach) : nil }
        return target + velocity * Float(after)
    }

    /// 投球が的の点 `target` からミットの深さ（`mitt` の z）に届くまでの時間（秒）。投球の線のまま同じ速さで進む。
    static func mittReach(target: SIMD3<Float>, mitt: SIMD3<Float>, travel: TimeInterval) -> TimeInterval {
        let vz = Double(target.z - releasePoint.z) / travel
        guard vz != 0 else { return 0.01 }
        return max(Double(mitt.z - target.z) / vz, 0.01)
    }

    /// 打球の初速（m/s・世界座標）。方向は判定の `direction`（0 = 中堅・負が左 = レフト）、打ち上げ角は帯の中心、
    /// 速さは飛距離が出る初速（空気抵抗なし）。ファウルは 28m/s の固定。
    /// 引っ張り（負 = レフト = 右打者の立つ三塁側）は x の `pullSideX` の向きへ飛ぶ（`HomerunAtBatLayout.pullSideX`）。
    /// 以前は負を常に -x へ飛ばしていて、前のカメラでは打者（+x）と逆の側 = ライトへ飛んで見えていた（#1594 会長 QA 2026-09-30）。
    /// 上限 55m/s: ライナー（18°）の柵越え（最長 147 × 最高の当たりの上乗せ ≈ 164m・#1647）が見た目でも届くように
    /// （45m/s だと 121m・50m/s だと 150m 止まり）。
    static func battedVelocity(_ ball: HomerunBattedBall, pullSideX: Float = 1) -> SIMD3<Float> {
        let elevation: Double = switch ball.launch {
        case .grounder: 8
        case .liner: 18
        case .fly: 30
        case .pop: 50
        case nil: 30
        }
        let theta = elevation * .pi / 180
        let speed: Double = ball.kind == .foul ? 28 : min(max(sqrt(ball.distance * Double(gravity) / sin(2 * theta)), 15), 55)
        let d = ball.direction * .pi / 180
        return SIMD3<Float>(Float(-sin(d) * cos(theta)) * pullSideX, Float(sin(theta)), Float(cos(d) * cos(theta))) * Float(speed)
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
    var lastBall: HomerunBattedBall?
    /// 直前の空振りで回って倒れる演出を出すか（#1681・`HomerunModel.showsWhiffGag`）。
    var whiffGag = false
    /// 直前の 1 球の結果に重ねる頭の記号（#1760・`HomerunModel.faceMark`）。見せるのは結果の間だけ（`faceMark`）。
    private var resultFaceMark: HomerunFaceMark = .none
    private var waitingFaceMark: HomerunFaceMark = .none

    /// いま打者の頭に重ねる記号。結果の間（`.ballResult`）の結果の記号と、次の球を待つ間（`.pitching`）の構えの記号（#1762）。
    var faceMark: HomerunFaceMark {
        switch phase {
        case .ballResult: resultFaceMark
        case .pitching: waitingFaceMark
        case .idle, .finished, .finale: .none
        }
    }

    @MainActor
    init(model: HomerunModel) {
        phase = model.phase
        clock = model.ballClock
        lastBall = model.lastBall
        whiffGag = model.showsWhiffGag
        resultFaceMark = model.faceMark
        waitingFaceMark = model.waitingFaceMark
    }

    init(phase: HomerunModel.Phase, clock: HomerunModel.BallClock?, lastBall: HomerunBattedBall?, whiffGag: Bool = false,
         faceMark: HomerunFaceMark = .none, waitingFaceMark: HomerunFaceMark = .none) {
        self.phase = phase
        self.resultFaceMark = faceMark
        self.waitingFaceMark = waitingFaceMark
        self.clock = clock
        self.lastBall = lastBall
        self.whiffGag = whiffGag
    }

    var column: Int { HomerunSwingContact.column(zone: clock?.zone ?? 4) }

    /// 3D の球がジャストの打点（の `approachLift` 上）に着く時刻 = 輪が的に重なる時刻 = 判定の 0（#1594 会長決裁 A）。
    /// そこで離すと、バットはその瞬間にジャストの打点のコマにある（`HomerunSwingContact.swingStart`）。
    var ballArrival: Date? { clock?.arrival }

    /// 踏み込みの始まり: 当たり窓の早い端（輪が重なる 110ms 前）に 20 コマ目で待てるよう、その 19/30 秒前から。
    var loadStart: Date? {
        clock.map { $0.arrival.addingTimeInterval(-HomerunTiming.hitWindow / 1000 - HomerunBatterMotion.loadDuration) }
    }

    /// 打者の段階。振り（本番・素振り）は始まったら最後まで振り切り、巻き戻さない。
    func batterMotion(at now: Date) -> HomerunBatterMotion {
        guard let clock, let loadStart else { return .stance }
        switch phase {
        case .pitching:
            // 素振り（的が出る前・前の球の結果の間に離した）: 離した瞬間から頭（20 コマ目）で最後まで振り抜き、振り終わったら
            // 構え・踏み込みへ戻る。
            if let practice = clock.practiceSwingAt, now >= practice,
               now < practice.addingTimeInterval(HomerunBatterMotion.swingDuration) {
                return .swing(start: practice)
            }
            // 押しっぱなしでは振らない（踏み込みで待つ）。
            return now >= loadStart ? .load(start: loadStart) : .stance
        case .ballResult:
            // 本番の振り（離した瞬間に振り抜きの途中から）と、結果の間の素振りのうち、始まっている新しい方。振り終わっても
            // フォロースルーで止める。
            if let practice = clock.practiceSwingAt, practice <= now, clock.releasedAt.map({ practice > $0 }) ?? true {
                return .swing(start: practice)
            }
            if let release = clock.releasedAt, release <= now {
                let start = HomerunSwingContact.swingStart(release: release, offsetMilliseconds: clock.timingOffset ?? 0, column: column)
                // タイミングは合っていて照準で外した空振りは、速めに流さず打点のコマから（遅れて振ると、ジャストの打点の
                // 上を抜けた球にバットが追いついて触れて見える）。
                let aimMiss = lastBall?.kind == .miss && lastBall?.timing != .miss
                let catchUpFrom = start < release && !aimMiss ? release : nil
                // 空振りの演出（#1681）は振り抜きからそのまま回って倒れる（演出の間の素振りは受け付けない・`HomerunModel.release`）。
                if whiffGag, lastBall?.kind == .miss { return .whiffGag(start: start, catchUpFrom: catchUpFrom) }
                // たんこぶ（#1793）も同じ（振り抜きから、頭に当たるまで振り終わりで待つ）。
                if lastBall?.isTankobu == true { return .tankobu(start: start, catchUpFrom: catchUpFrom) }
                return .swing(start: start, catchUpFrom: catchUpFrom)
            }
            // 見送り: 振らない。
            return .stance
        case .idle, .finished, .finale:
            return .stance
        }
    }

    /// 3D の球の位置（世界座標・前のカメラの置き方）。見せない間は nil。`camera` は打球の左右（`HomerunAtBatLayout.pullSideX`）
    /// と、`screen`（3D を描く全画面の大きさ）があるときの投球の着く点（`HomerunAtBatLayout.pitchTarget` = 2D の的に重なる点・#1647）
    /// に使う（左右反転するカメラでは描画側が球を x について鏡映して置く）。`screen` が無ければ打点の上（`approachTarget`）へ着く。
    func ballPosition(at now: Date, camera: HomerunAtBatLayout.Camera = HomerunAtBatLayout.camera,
                      screen: CGSize? = nil) -> SIMD3<Float>? {
        guard let clock, let ballArrival else { return nil }
        let target = screen.map { HomerunAtBatLayout.pitchTarget(zone: clock.zone, camera: camera, screen: $0) }
        let pitched = HomerunBallFlight.pitchPosition(at: now, pitchStart: clock.pitchStart, arrival: ballArrival, column: column,
                                                      target: target, mitt: HomerunBallFlight.mittPoint(for: camera))
        switch phase {
        case .pitching:
            return pitched
        case .ballResult:
            if let release = clock.releasedAt, let offset = clock.timingOffset, let ball = lastBall, ball.kind != .miss {
                let contact = HomerunSwingContact.contactPoint(column: column, offsetMilliseconds: offset)
                let hitAt = HomerunSwingContact.contactShownTime(release: release, offsetMilliseconds: offset, column: column)
                if ball.isTankobu, now >= hitAt {
                    let start = HomerunSwingContact.swingStart(release: release, offsetMilliseconds: offset, column: column)
                    return HomerunTankobuGag.ballPosition(effective: HomerunTankobuGag.effective(now.timeIntervalSince(start)), contact: contact,
                                                          contactOffset: hitAt.timeIntervalSince(start))
                }
                if now < hitAt {
                    // 離した瞬間の球の位置から、バットがその打点に来る時刻に打点へ着くよう寄せる（球の側を合わせる）。早いときは
                    // バットが球の来る時刻に打点へ来るので、球はほぼ投球の線のまま着く。遅いとき（打点のコマ = 離した瞬間）は、
                    // 打点を過ぎた球をその瞬間に打点へ戻す。
                    let from = HomerunBallFlight.pitchPosition(at: release, pitchStart: clock.pitchStart, arrival: ballArrival,
                                                               column: column, target: target,
                                                               mitt: HomerunBallFlight.mittPoint(for: camera)) ?? contact
                    let span = hitAt.timeIntervalSince(release)
                    let k = Float(span > 0 ? min(max(now.timeIntervalSince(release) / span, 0), 1) : 1)
                    return from + (contact - from) * k
                }
                return HomerunBallFlight.battedPosition(at: now, contact: contact, release: hitAt,
                                                        velocity: HomerunBallFlight.battedVelocity(ball, pullSideX: HomerunAtBatLayout.pullSideX(for: camera)))
            }
            // 空振り・見送り: そのままミットへ入って止まり、消える（#1655）。
            return pitched
        case .idle, .finished, .finale:
            return nil
        }
    }
}
