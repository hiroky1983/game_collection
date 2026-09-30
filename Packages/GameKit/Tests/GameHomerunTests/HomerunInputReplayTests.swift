import Testing
import Foundation
import HomerunCore
@testable import GameHomerun

/// シミュレータのマウス操作に近い入力（押す・ずらす・離すを時刻つきで）を、アプリと同じ進み方で Model に与える
/// （会長 QA 2026-09-30「振ったのに全部見送り」・#1594）。
///
/// アプリの進み方: View の `.task(id: step)` が `nextWake` まで寝てから `advance` を呼ぶ。`TimelineView` は毎フレーム
/// `HomerunSwingPlan.batterMotion(at:)` で 3D の打者を描く。ここでは 1/60 秒刻みで同じことをし、
/// 「見た目のスイング（打者が .swing を始めた時刻）」と「判定上のスイング（resolve に swing が渡ったか）」を並べて記録する。
@MainActor
private final class Rig {
    let model: HomerunModel
    private(set) var now: Date
    /// 見た目のスイングが始まった時刻（`batterMotion` が `.swing(start:)` を返した start）。
    private(set) var visualSwings: [Date] = []
    private let name = "asobiba.homerun.replay.\(UUID().uuidString)"
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    static let frame: TimeInterval = 1.0 / 60

    init() {
        let defaults = UserDefaults(suiteName: name)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        model = HomerunModel(defaults: defaults, calendar: calendar, aimAssist: .off, now: Self.t0)
        now = Self.t0
        model.start(now: now)
    }

    deinit { UserDefaults().removePersistentDomain(forName: name) }

    /// いまの球の的が出る時刻（結果を見せている間は直前の球のもの）。
    var pitchStart: Date { model.ballClock!.pitchStart }
    /// いまの球の輪が的に重なる時刻。
    var arrival: Date { model.ballClock!.arrival }

    /// `t` まで時間を進める。締め切りは `.task` と同じく `nextWake` ちょうどに `advance` する。
    func wait(until t: Date) {
        while now < t {
            let next = min(now.addingTimeInterval(Self.frame), t)
            if let wake = model.nextWake, wake <= next {
                now = max(now, wake)
                model.advance(now: now)
            }
            now = next
            sample()
        }
    }

    /// 印を付けた時点の球の番号（1 始まり）。`mark()` で更新する。
    private(set) var markedBall = 1
    /// 見たい球の始まりに印を付け、その時刻を返す。
    func mark() -> Date {
        markedBall = (model.challenge?.results.count ?? 0) + 1
        return now
    }

    func wait(_ seconds: TimeInterval) { wait(until: now.addingTimeInterval(seconds)) }

    private func sample() {
        if case .swing(let start) = HomerunSwingPlan(model: model).batterMotion(at: now), visualSwings.last != start {
            visualSwings.append(start)
        }
    }

    // View の DragGesture と同じ呼び方（onChanged: 押していなければ press → drag、onEnded: release）。
    private(set) var finger = CGPoint(x: 150, y: 600)
    func down(at p: CGPoint = CGPoint(x: 150, y: 600)) {
        finger = p
        if !model.isHolding { model.press(at: p, now: now) }
        model.drag(to: p)
    }
    func move(by dx: CGFloat, _ dy: CGFloat) {
        finger = CGPoint(x: finger.x + dx, y: finger.y + dy)
        if !model.isHolding { model.press(at: finger, now: now) }
        model.drag(to: finger)
    }
    @discardableResult
    func up() -> HomerunBattedBall? { model.release(at: finger, now: now) }

    /// いまの球の結果が出るまで進めて、その球の記録を返す（`from` 以降に見えたスイングを数える）。
    /// シナリオの始まり（`from`）に投げていた球が結果になるまで待つ（離した瞬間に結果になっていればそのまま）。
    func settle(from: Date) -> Outcome {
        let target = markedBall
        while (model.challenge?.results.count ?? 0) < target { wait(Self.frame) }
        let releasedAt = model.ballClock?.releasedAt
        let judged = model.didSwingLastBall
        let reason = model.lastMissReason
        let kind = model.lastBall?.kind
        let practice = model.ballClock?.practiceSwingAt
        // 結果を見せ終えるまで見た目を追う。
        wait(until: model.resultUntil ?? now)
        let seen = visualSwings.filter { $0 >= from }
        return Outcome(judgedSwing: judged, releasedAt: releasedAt, practiceSwingAt: practice,
                       visualSwings: seen, kind: kind, reason: reason,
                       headline: model.lastBall.map { HomerunBallResultCard.headline($0, tookPitch: !judged) } ?? "-",
                       note: model.lastBall.flatMap {
                           HomerunBallResultCard.reasonLine($0, tookPitch: !judged,
                                                            missNote: HomerunAtBatView.missNote(didSwing: judged, reason: reason))
                       })
    }

    struct Outcome: CustomStringConvertible {
        var judgedSwing: Bool
        var releasedAt: Date?
        var practiceSwingAt: Date?
        var visualSwings: [Date]
        var kind: HomerunKind?
        var reason: HomerunMissReason?
        /// 結果のカードの見出しと、その下の理由（カードと同じ関数で作る）。
        var headline: String
        var note: String?
        var description: String {
            "判定上のスイング=\(judgedSwing) 見た目のスイング=\(visualSwings.count)回 種別=\(kind.map { "\($0)" } ?? "-") カード=\(headline)／\(note ?? "-")"
        }
    }
}

@Suite("柵越えおじさん: 離しの再現（会長 QA・振ったのに見送り）")
@MainActor
struct HomerunInputReplayTests {

    /// 的が出た後に離したら、見た目どおりに判定上も振ったことになる（見送りにならない）。
    private func expectJudged(_ o: Rig.Outcome, releasedAt: Date, _ label: String) {
        print("[再現] \(label): \(o)")
        #expect(o.judgedSwing, "\(label): 振ったのに見送り扱い（\(o)）")
        #expect(o.releasedAt == releasedAt, "\(label): 判定の離し時刻が付いていない")
        #expect(o.visualSwings == [releasedAt], "\(label): 見た目のスイングと判定のスイングがずれている（\(o)）")
        #expect(o.headline != "見送り", "\(label): 見送りと出た")
    }

    @Test("打席に立った直後から押しっぱなし → 的が出た後、輪が重なった瞬間に離す")
    func holdFromStartReleaseOnRing() {
        let rig = Rig()
        let from = rig.mark()
        rig.down()
        rig.wait(until: rig.arrival)
        let release = rig.now
        rig.up()
        expectJudged(rig.settle(from: from), releasedAt: release, "直後から押しっぱなし→輪で離す")
    }

    @Test("押しっぱなし → 3D の球がバットに来たとき（輪が重なった 0.2 秒後）に離す = 遅い空振りとして判定される")
    func releaseWhenBallReachesBat() {
        let rig = Rig()
        let from = rig.mark()
        rig.down()
        let release = rig.arrival.addingTimeInterval(HomerunSwingContact.lead(column: 1))
        rig.wait(until: release)
        rig.up()
        let o = rig.settle(from: from)
        expectJudged(o, releasedAt: release, "球がバットに来たときに離す（輪の \(Int(HomerunSwingContact.lead(column: 1) * 1000))ms 後）")
        #expect(o.reason == .late && o.headline == "空振り" && o.note == "振るのが遅い")
    }

    @Test("遅れて離す（輪の 0.12〜0.45 秒後・見送りの締め切り 0.5 秒の手前）はどれも遅い空振りとして判定される", arguments: [0.12, 0.15, 0.3, 0.45])
    func lateReleases(delay: TimeInterval) {
        let rig = Rig()
        let from = rig.mark()
        rig.down()
        let release = rig.arrival.addingTimeInterval(delay)
        rig.wait(until: release)
        rig.up()
        let o = rig.settle(from: from)
        expectJudged(o, releasedAt: release, "輪の \(Int(delay * 1000))ms 後に離す")
        #expect(o.reason == .late)
    }

    @Test("的が出る前に一度クリックして素振り → 的が出た後に押して、輪で離す")
    func practiceThenSwing() {
        let rig = Rig()
        let from = rig.mark()
        rig.wait(until: rig.pitchStart.addingTimeInterval(-0.5))
        rig.down(); rig.wait(0.05); rig.up()
        let practice = rig.model.ballClock?.practiceSwingAt
        rig.wait(until: rig.pitchStart.addingTimeInterval(0.4))
        rig.down()
        rig.wait(until: rig.arrival)
        let release = rig.now
        rig.up()
        let o = rig.settle(from: from)
        print("[再現] 素振り→本番: \(o)")
        #expect(o.judgedSwing && o.releasedAt == release)
        #expect(o.visualSwings == [practice!, release], "素振り 1 回・本番 1 回")
    }

    @Test("前の球の結果表示中から押しっぱなし → 次の球の輪で離す")
    func holdFromPreviousResult() {
        let rig2 = Rig()
        rig2.wait(until: rig2.arrival)
        rig2.down(); rig2.up()                     // 1 球目は普通に振る
        rig2.wait(until: rig2.model.resultUntil!.addingTimeInterval(-0.5))
        #expect(rig2.model.phase == .ballResult)
        let from = rig2.mark()
        rig2.down()                                // 結果表示中に押す
        rig2.wait(until: rig2.model.resultUntil!.addingTimeInterval(0.01))
        #expect(rig2.model.phase == .pitching && rig2.model.isHolding)
        rig2.wait(until: rig2.arrival)
        let release = rig2.now
        rig2.up()
        expectJudged(rig2.settle(from: from), releasedAt: release, "前の結果から押しっぱなし→次の球の輪で離す")
    }

    @Test("ゆっくりドラッグしながら（毎フレーム 1pt）輪で離す")
    func slowDragRelease() {
        let rig = Rig()
        let from = rig.mark()
        rig.down()
        while rig.now < rig.arrival { rig.move(by: 0.3, -0.3); rig.wait(Rig.frame) }
        let release = rig.now
        rig.up()
        expectJudged(rig.settle(from: from), releasedAt: release, "ゆっくりドラッグ→離す")
    }

    @Test("押したまま離さずに球が通り過ぎたら見送り。その後に離しても素振りも判定もしない（見送りのカードと振る絵が重ならない）")
    func neverReleasedIsTakenPitch() {
        let rig = Rig()
        let from = rig.mark()
        rig.down()
        // 締め切りまで離さない。
        rig.wait(until: rig.arrival.addingTimeInterval(HomerunModel.lateLimit + 0.05))
        #expect(rig.model.phase == .ballResult && !rig.model.didSwingLastBall)
        #expect(rig.up() == nil)
        let o = rig.settle(from: from)
        print("[再現] 押したまま見送り→結果中に離す: \(o)")
        #expect(!o.judgedSwing && o.headline == "見送り" && o.note == nil)
        #expect(o.visualSwings.isEmpty, "見送りのあとに打者が振っている")
    }

    @Test("的が出る前に離しただけ（素振り）でその球は押さなければ見送り")
    func releaseBeforePitchOnly() {
        let rig = Rig()
        let from = rig.mark()
        rig.down()
        let pitchStart = rig.pitchStart
        rig.wait(until: pitchStart.addingTimeInterval(-0.05))
        rig.up()
        let o = rig.settle(from: from)
        print("[再現] 的が出る前に離しただけ: \(o)")
        #expect(!o.judgedSwing && o.headline == "見送り" && o.note == nil)
        #expect(o.visualSwings.count == 1 && o.visualSwings.first! < pitchStart, "的が出る前の素振りだけ")
    }
}
