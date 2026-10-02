import SwiftUI
import simd
import HomerunCore

/// ジャストミートの確定演出（#1775・会長決裁 2026-10-03 で J4 = 短いヒットストップ + 寄り）。
///
/// 当たったコマ（`HomerunSwingPlan.contactAt`）で画面の時間をほぼ止め（`hitStop` 秒・その間の時間の進みは `slowdown` 倍）、
/// 打席のカメラがバットと球へ寄り（`zoomFieldOfView`）、白い閃光・衝撃の輪・集中線（`HomerunJustMeetEffect`）を重ねる。
/// ほぼ止まった時間の中で球がバットを離れ、引いてから打球を追うカメラ（`HomerunBallChase`）へ移る。
///
/// 時間は**表示の時刻だけ**を遅らせる（`displayTime`）。判定・飛距離は変えない。増えた時間（`extraDuration`）のぶん、
/// 結果のカード（`HomerunSwingPlan.chaseCardAt`）も次の球（`HomerunModel.resultDuration`）も遅らせる。
/// 月まで飛んだ打球（#1680）は月の演出を優先し、この演出は出さない（`applies`）。
/// 時間・倍率・寄りの量はここの定数に集めてある（会長 QA で調整する）。
enum HomerunJustMeet {
    // MARK: 定数（時間はすべて実時間の秒）

    /// ヒットストップの長さ（0.12〜0.25 秒の範囲・モックは 0.2）。
    static let hitStop: TimeInterval = 0.2
    /// 止めている間の時間の進み（倍）。0 にせず、ほぼ止まった中で球がバットを離れて見えるようにする。
    static let slowdown: Double = 0.06
    /// 寄りきるまで（当たった瞬間から）と、引ききるまで（ヒットストップが明けてから）の長さ。
    static let zoomInDuration: TimeInterval = 0.06
    static let pullBackDuration: TimeInterval = 0.12
    /// 寄ったときの縦の画角（度）。打席のカメラは 9.6°（`HomerunAtBatLayout.camera`）。小さいほど寄る。
    static let zoomFieldOfView: Float = 5.0

    /// 閃光（画面全体の白）の濃さの最大とその長さ・衝撃の輪が広がりきる半径（画面の短辺に対する割合）・集中線の本数と長さの範囲（同）。
    static let flashPeak = 0.55
    static let flashDuration: TimeInterval = 0.12
    static let ringRadius = 0.32
    static let speedLineCount = 20
    static let speedLineRange: ClosedRange<Double> = 0.12...0.6

    // MARK: 時間

    /// ヒットストップで増える時間（秒）。結果のカード・次の球をこのぶん遅らせる。
    static var extraDuration: TimeInterval { hitStop * (1 - slowdown) }

    /// 演出の長さ: 表示の時間が打球を追うカメラへ移る（`HomerunBallChase.cutDelay`）まで。引ききる（`pullBackDuration`）のは
    /// これより前に収める（テストで固定）。ゾーン・的の重ね絵はこの間だけ消す。
    static var effectDuration: TimeInterval { hitStop + HomerunBallChase.cutDelay - slowdown * hitStop }

    /// 演出を出す打球か。ジャストミートの当たり。月まで飛んだ打球は月の演出を優先する。
    static func applies(to ball: HomerunBattedBall?) -> Bool {
        guard let ball else { return false }
        return ball.isJustMeet && !ball.isMoon && ball.kind != .miss
    }

    /// 当たってから実時間 `real` 秒のときの、表示の時間（当たってからの秒）。ヒットストップの間はゆっくり、明けた後は増えたぶん遅れて進む。
    static func displayElapsed(realElapsed real: TimeInterval) -> TimeInterval {
        if real <= 0 { return real }
        if real < hitStop { return real * slowdown }
        return real - extraDuration
    }

    // MARK: 寄り

    private static func smoothstep(_ x: Double) -> Double {
        let k = min(max(x, 0), 1)
        return k * k * (3 - 2 * k)
    }

    /// 寄り具合（0 = 打席のカメラ・1 = 寄りきり）。当たった瞬間から寄り、ヒットストップが明けたら引く。
    static func zoom(realElapsed real: TimeInterval) -> Double {
        if real <= 0 { return 0 }
        if real < hitStop { return smoothstep(real / zoomInDuration) }
        return 1 - smoothstep((real - hitStop) / pullBackDuration)
    }

    /// 打席のカメラ `base` から、打点 `contact`（世界座標）へ寄ったカメラ。位置は動かさず、注視点を打点へ寄せて画角を狭める。
    static func camera(base: HomerunAtBatLayout.Camera, contact: SIMD3<Float>, zoom: Double) -> HomerunAtBatLayout.Camera {
        guard zoom > 0 else { return base }
        let near = HomerunAtBatLayout.Camera.aimed(from: base.position, at: contact, yFraction: 0.5,
                                                   verticalFieldOfView: zoomFieldOfView, mirrored: base.mirrored)
        let k = Float(min(zoom, 1))
        return HomerunAtBatLayout.Camera(position: base.position,
                                         target: base.target + (near.target - base.target) * k,
                                         verticalFieldOfView: base.verticalFieldOfView + (near.verticalFieldOfView - base.verticalFieldOfView) * k,
                                         mirrored: base.mirrored)
    }
}

extension HomerunSwingPlan {
    /// ジャストミートの演出を出す打球が当たる（実）時刻。出さない打球は nil。
    var justMeetContactAt: Date? {
        HomerunJustMeet.applies(to: lastBall) ? contactAt : nil
    }

    /// 当たった後に結果の間の素振りを始めたか。素振りは実時刻で始まるので、このときは表示の時刻を遅らせない
    /// （遅らせると素振りの始まりが遅れ、振り抜きの途中で止まる）。
    private var practicesAfterRelease: Bool {
        guard let practice = clock?.practiceSwingAt, let release = clock?.releasedAt else { return false }
        return practice > release
    }

    /// 画面に出す時刻。演出の間だけ実時刻より遅れる（当たる前は実時刻のまま）。打者・球・打球を追うカメラはこの時刻で描く。
    func displayTime(at now: Date) -> Date {
        guard let contact = justMeetContactAt, now > contact, !practicesAfterRelease else { return now }
        return contact.addingTimeInterval(HomerunJustMeet.displayElapsed(realElapsed: now.timeIntervalSince(contact)))
    }

    /// 演出の中なら、当たってからの実時間（秒）。それ以外は nil。
    func justMeetElapsed(at now: Date) -> TimeInterval? {
        guard let contact = justMeetContactAt else { return nil }
        let real = now.timeIntervalSince(contact)
        return real >= 0 && real < HomerunJustMeet.effectDuration ? real : nil
    }

    /// 打者の振りを表示の時刻から決め直す間か（当たった後・`displayTime` が実時刻とずれている間）。
    func holdsBatterClock(at now: Date) -> Bool {
        guard let contact = justMeetContactAt else { return false }
        return now > contact && !practicesAfterRelease
    }

    /// 演出の打点（世界座標）。
    var justMeetPoint: SIMD3<Float>? {
        guard justMeetContactAt != nil, let clock, let offset = clock.timingOffset else { return nil }
        return HomerunSwingContact.contactPoint(column: HomerunSwingContact.column(zone: clock.zone), offsetMilliseconds: offset)
    }

    /// 演出の寄りのカメラ（寄っている間だけ。引ききったら nil）。
    func justMeetCamera(at now: Date) -> HomerunAtBatLayout.Camera? {
        guard let real = justMeetElapsed(at: now), let point = justMeetPoint else { return nil }
        let zoom = HomerunJustMeet.zoom(realElapsed: real)
        return zoom > 0 ? HomerunJustMeet.camera(base: HomerunAtBatLayout.camera, contact: point, zoom: zoom) : nil
    }
}

/// 閃光・衝撃の輪・集中線（`Canvas` 1 枚）。`elapsed` は当たってからの実時間（秒）、`center` は打点の画面上の位置（画面の幅・高さに対する割合）。
/// 乱数なし: 線の並びは本数から決まる。
struct HomerunJustMeetEffect: View {
    let elapsed: TimeInterval
    let center: CGPoint

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: center.x * size.width, y: center.y * size.height)
            let short = min(size.width, size.height)
            let hold = min(max(elapsed / HomerunJustMeet.hitStop, 0), 1)
            // 閃光: 当たった瞬間が最大で、すぐ消える。
            let flash = HomerunJustMeet.flashPeak * max(1 - elapsed / HomerunJustMeet.flashDuration, 0)
            if flash > 0 {
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(flash)))
            }
            // 衝撃の輪: 打点から広がりながら薄くなる。
            let ringR = short * HomerunJustMeet.ringRadius * (1 - pow(1 - hold, 3))
            if hold < 1 {
                let ring = Path(ellipseIn: CGRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2))
                ctx.stroke(ring, with: .color(.white.opacity(0.9 * (1 - hold))), lineWidth: 6 * (1 - hold) + 1)
            }
            // 集中線: 打点から外へ放射状（長さは線ごとに変える）。ヒットストップの間だけ。
            if hold < 1 {
                let n = HomerunJustMeet.speedLineCount
                let range = HomerunJustMeet.speedLineRange
                for i in 0..<n {
                    let angle = Double(i) / Double(n) * 2 * .pi
                    let length = range.lowerBound + (range.upperBound - range.lowerBound) * Double((i * 7) % n) / Double(n)
                    let inner = short * (range.lowerBound + 0.04 * hold)
                    let outer = short * length * (1 + 0.2 * hold)
                    var line = Path()
                    line.move(to: CGPoint(x: c.x + cos(angle) * inner, y: c.y + sin(angle) * inner))
                    line.addLine(to: CGPoint(x: c.x + cos(angle) * max(outer, inner + 8), y: c.y + sin(angle) * max(outer, inner + 8)))
                    ctx.stroke(line, with: .color(.white.opacity(0.7 * (1 - hold))), lineWidth: 2.5)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
