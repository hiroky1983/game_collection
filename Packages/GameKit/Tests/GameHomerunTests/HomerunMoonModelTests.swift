import Testing
import Foundation
import simd
import HomerunCore
@testable import GameHomerun

/// 月まで飛ぶ隠し演出（#1680）の進行（台帳の +2・記録・強制の起動引数）と見せ方（カメラ・夜空・月）。
@Suite("柵越えおじさんの月まで飛ぶ隠し演出（画面の進行）")
@MainActor
struct HomerunMoonModelTests {
    private final class Fixture {
        let defaults: UserDefaults
        let name = "asobiba.homerun.moon.tests.\(UUID().uuidString)"
        static let calendar: Calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
            return c
        }()
        static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        init() { defaults = UserDefaults(suiteName: name)! }
        deinit { UserDefaults().removePersistentDomain(forName: name) }

        @MainActor func model() -> HomerunModel {
            HomerunModel(defaults: defaults, calendar: Self.calendar, aimAssist: .off, now: Self.t0)
        }
    }

    /// 押す → ボールの中心から (dx, dy) へずらす → 輪が重なる時刻 + `offset` 秒で離す。結果を閉じる時刻を返す。
    @discardableResult
    private func swing(_ model: HomerunModel, dx: Double = 0, dy: Double, offset: TimeInterval = 0) throws -> (HomerunBattedBall?, Date) {
        let hit = try #require(model.arrival).addingTimeInterval(offset)
        let start = CGPoint(x: 150, y: 600)
        model.press(at: start)
        let ball = model.ballPoint
        let result = model.release(at: CGPoint(x: start.x + ball.x + dx - model.cursor.x, y: start.y + ball.y + dy - model.cursor.y), now: hit)
        return (result, try #require(model.resultUntil))
    }

    private let moonDY = HomerunLaunch.fly.centerDY

    @Test("2 回目の月で挑戦が終わり、残りの球は没収・その時点で記録し、今日のプレイ回数が +2 されて保存される")
    func secondMoonEndsChallengeAndGrantsTwo() throws {
        let f = Fixture()
        let model = f.model()
        #expect(model.start(now: Fixture.t0))
        #expect(model.ledger.remaining == 2)

        let (first, close1) = try swing(model, dy: moonDY)
        #expect(first?.moon == .hit)
        #expect(model.ledger.remaining == 2, "1 回目ではまだ増えない")
        model.advance(now: close1)
        #expect(model.phase == .pitching)

        let (second, close2) = try swing(model, dx: 0.4, dy: moonDY, offset: 0.03)
        #expect(second?.moon == .broken)
        #expect(model.challenge?.isFinished == true)
        #expect(model.challenge?.results.count == 2)
        // +2（当日分）。保存も済み。
        #expect(model.ledger.bonus == HomerunLedger.moonBonus)
        #expect(model.ledger.remaining == 4)
        #expect(HomerunStorage.loadLedger(f.defaults).remaining == 4)
        // 割れた時点で記録（180m × 2）。
        #expect(model.records.challenges == 1)
        #expect(model.records.bestTotalTenths == 3600)
        #expect(model.records.longestTenths == 1800)
        #expect(model.records.moonShots == 2 && model.records.moonBreaks == 1)
        #expect(HomerunStorage.loadRecords(f.defaults).moonShots == 2)
        #expect(model.isNewBest)
        // 月の演出のぶん結果を長く見せ、その後は 10 球の結果（Game over）へ。
        #expect(model.resultUntil == model.ballClock?.releasedAt?.addingTimeInterval(HomerunMoonShot.resultDuration(.broken)))
        model.advance(now: close2)
        #expect(model.phase == .finished)
        #expect(model.ledger.canStart)
    }

    @Test("1 回目の月は挑戦を続け、ヒビの演出のぶん結果を長く見せる。ふだんの柵越えでは月にならない")
    func firstMoonContinues() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        let (normal, close) = try swing(model, dy: moonDY + 2)
        #expect(normal?.moon == nil && normal?.kind == .homer)
        model.advance(now: close)
        let (moon, _) = try swing(model, dy: moonDY, offset: -0.05)
        #expect(moon?.moon == .hit)
        #expect(model.challenge?.isFinished == false)
        #expect(HomerunModel.resultDuration(for: moon) == HomerunMoonShot.resultDuration(.hit))
        #expect(HomerunModel.resultDuration(for: moon) > HomerunModel.resultDuration(for: .homer))
        #expect(HomerunMoonShot.resultDuration(.broken) > HomerunMoonShot.resultDuration(.hit))
    }

    // 鍵（`debugForceMoonKey`・`debugForcePoleKey`）は `HomerunModel+Debug.swift` の #if DEBUG の中だけの
    // 宣言なので、参照するこの 2 つのテストも同じく #if DEBUG で囲む（出荷ビルドのテストが壊れないように・#1705）。
    #if DEBUG
    @Test("確認用の鍵（DEBUG の -homerunForceMoon）が立っていれば、どこで振っても月になる")
    func forcedByDebugKey() throws {
        let f = Fixture()
        f.defaults.set(true, forKey: HomerunModel.debugForceMoonKey)
        let model = f.model()
        model.start(now: Fixture.t0)
        #expect(model.challenge?.forcesMoon == true)
        let (ball, close) = try swing(model, dx: 20, dy: -20, offset: 0.1)
        #expect(ball?.moon == .hit)
        model.advance(now: close)
        let (second, _) = try swing(model, dx: -10, dy: 10, offset: -0.1)
        #expect(second?.moon == .broken)

        let plain = Fixture().model()
        plain.start(now: Fixture.t0)
        #expect(plain.challenge?.forcesMoon == false)
    }

    @Test("確認用の鍵（DEBUG の -homerunForcePole・#1686）が立っていれば、どこで振ってもポール直撃（左右は振った方向の側）")
    func forcedPoleByDebugKey() throws {
        let f = Fixture()
        f.defaults.set(true, forKey: HomerunModel.debugForcePoleKey)
        let model = f.model()
        model.start(now: Fixture.t0)
        #expect(model.challenge?.forcesPole == true)
        let (left, close) = try swing(model, dx: -8, dy: -20, offset: -0.06)
        #expect(left?.isPoleHit == true && left?.direction == -45)
        model.advance(now: close)
        let (right, _) = try swing(model, dx: 8, dy: 0, offset: 0.06)
        #expect(right?.isPoleHit == true && right?.direction == 45)
        #expect(model.resultUntil == model.ballClock?.releasedAt?.addingTimeInterval(HomerunBallChase.poleResultDuration))

        let plain = Fixture().model()
        plain.start(now: Fixture.t0)
        #expect(plain.challenge?.forcesPole == false)
    }
    #endif

    // MARK: 見せ方

    @Test("見せ方: 球は月の手前の面に当たり、カメラは真上寄りへ見上げ、空が夜になってから月が出る・当たってヒビ")
    func moonShotTimeline() throws {
        let start = HomerunMoonShot.frame(.hit, at: HomerunBallChase.cutDelay)
        #expect(start.moon?.night == 0)
        #expect(start.moon?.moonVisible == false)
        #expect(start.moon?.cracked == false)
        #expect(!start.ballHidden)

        let end = HomerunMoonShot.frame(.hit, at: HomerunMoonShot.impact - 0.01)
        let forward = simd_normalize(end.camera.target - end.camera.position)
        // 見上げる角（仰角）は 70° 以上。
        #expect(asin(forward.y) * 180 / .pi > 70)
        #expect(end.moon?.night == 1)
        #expect(end.moon?.moonVisible == true)
        #expect(simd_distance(end.ball, HomerunMoonShot.impactPoint) < 1)
        // 当たる点はカメラから見て月の真ん中（月の面の上）。
        #expect(abs(simd_distance(HomerunMoonShot.impactPoint, HomerunMoonShot.moonCenter) - HomerunMoonShot.moonRadius) < 0.01)
        let p = end.camera.screenPoint(of: HomerunMoonShot.impactPoint, aspect: 0.46)
        #expect(abs(p.x - 0.5) < 0.02 && abs(p.y - 0.5) < 0.05)

        // 月は遠くの小さな点から迫ってくる（加速するイーズイン）。球は逆に遠ざかって小さく見える。
        typealias M = HomerunMoonShot
        let appear = M.frame(.hit, at: M.moonAppear)
        let mid = M.frame(.hit, at: (M.moonAppear + M.impact) / 2)
        func moonScreenRadius(_ f: HomerunBallChase.Frame, _ t: TimeInterval) -> Double {
            // 縦の画角に対する月の見かけの半径の割合（画面の高さの何割か）。
            Double(M.moonApparentRadius(at: t)) / (Double(f.camera.verticalFieldOfView) * .pi / 360) / 2
        }
        let r0 = moonScreenRadius(appear, M.moonAppear)
        let r1 = moonScreenRadius(mid, (M.moonAppear + M.impact) / 2)
        let r2 = moonScreenRadius(end, M.impact)
        #expect(r0 < 0.01, "出たときは小さな点: \(r0)")
        #expect(r2 > 0.15, "当たる直前は画面いっぱい（縦画面の横幅を越える）: \(r2)")
        #expect(r1 < r2 / 4, "後半で一気に迫る（加速）: \(r1) \(r2)")
        #expect(abs(M.moonDistance(at: M.moonAppear) - M.moonFarDistance) < 0.01)
        #expect(abs(M.moonDistance(at: M.impact) - M.moonNearDistance) < 0.01)
        // 見かけの大きさは単調に大きくなり、増え方が加速する（途中でも大きくなっていくのが見える: 半分の時刻で 2 倍以上）。
        var last: Float = 0, lastGain: Float = 0
        for k in 0...20 {
            let a = M.moonApparentRadius(at: M.moonAppear + (M.impact - M.moonAppear) * Double(k) / 20)
            #expect(a >= last)
            if k > 1 { #expect(a - last >= lastGain - 1e-6, "大きくなり方が加速している") }
            if k > 0 { lastGain = a - last }
            last = a
        }
        #expect(M.moonApparentRadius(at: (M.moonAppear + M.impact) / 2) > M.moonApparentRadius(at: M.moonAppear) * 2)
        #expect(M.frame(.hit, at: M.impact).moon?.moonCenter == M.moonCenter)
        // 月の手前の面は常に球より奥（球が月を追い越さない）。
        for k in 0...30 {
            let t = M.impact * Double(k) / 30
            if let b = M.ballPosition(at: t) {
                #expect(simd_distance(M.cameraPosition, b) <= M.moonDistance(at: t) - M.moonRadius + 0.5)
            }
        }
        // 球の見かけの大きさ（ラジアン）は当たる直前の方が小さい。
        let ballApparent = { (f: HomerunBallChase.Frame) in
            f.ballScale * HomerunSwingContact.ballRadius / simd_distance(f.camera.position, f.ball)
        }
        #expect(ballApparent(end) < ballApparent(appear) * 0.6)
        // 大気圏を抜ける（空が夜になり始める）ところで燃え、当たるまで火の玉。火の尾は進む向きの逆。
        #expect(M.burnStart == M.nightStart)
        #expect(M.fireball(at: M.burnStart - 0.01) == nil)
        #expect(start.moon?.fire == nil)
        let burning = try #require(end.moon?.fire)
        #expect(simd_distance(burning.center, end.ball) < 1e-3)
        // 火の尾は画面の下（昇ってきた側）へ引き、進む向きとは逆向き。
        #expect(simd_dot(burning.trail, M.screenDown) > 0.9)
        #expect(simd_dot(burning.trail, M.flightDirection) < 0)
        // 月が出た頃の火の玉は月（画面の真ん中）より下に映り、遠くの月の点を隠さない。
        let early = M.frame(.hit, at: M.moonAppear)
        let ep = early.camera.screenPoint(of: early.ball, aspect: 0.46)
        let mp = early.camera.screenPoint(of: M.moonPosition(at: M.moonAppear), aspect: 0.46)
        #expect(ep.y - mp.y > 0.1)
        // 炎は球よりずっと大きく見える（月の上でも見分けられる）。
        let fireApparent = burning.radius / simd_distance(end.camera.position, burning.center)
        #expect(fireApparent > ballApparent(end) * 3)
        #expect(M.fireball(at: M.impact) == nil, "当たったら炎ごと月に突っ込んで消える")
        #expect(M.frame(.hit, at: M.impact + 0.05).moon?.fire == nil)
        // 全体は以前（当たるまで 2.8 秒）から 1 秒以内しか延ばさない。
        #expect(M.impact <= 3.8)

        let hit = HomerunMoonShot.frame(.hit, at: HomerunMoonShot.impact + 0.05)
        #expect(hit.ballHidden)
        #expect(hit.moon?.cracked == true)
        #expect((hit.moon?.flash ?? 0) > 0.5)
        #expect(hit.moon?.split == 0)
        let later = HomerunMoonShot.look(.hit, at: HomerunMoonShot.cardDelay(.hit))
        #expect(later.split == 0 && later.flash == 0 && later.shake == .zero)

        // 2 回目: ヒビの後に割れて離れ切る。
        #expect(HomerunMoonShot.look(.broken, at: HomerunMoonShot.impact + 0.1).split == 0)
        #expect(HomerunMoonShot.look(.broken, at: HomerunMoonShot.impact + HomerunMoonShot.splitDelay + HomerunMoonShot.splitDuration).split == 1)
        #expect(HomerunMoonShot.cardDelay(.broken) > HomerunMoonShot.impact + HomerunMoonShot.splitDelay + HomerunMoonShot.splitDuration)
    }

    @Test("打球を追うカメラは月の打球で月の演出に替わり、場外より月が優先・結果のカードは月の演出の後")
    func swingPlanUsesMoonShot() throws {
        let release = Date(timeIntervalSince1970: 1000)
        let clock = HomerunModel.BallClock(pitchStart: release.addingTimeInterval(-1.2), zone: 4, pressedAt: nil,
                                           releasedAt: release, timingOffset: 0)
        let ball = HomerunJudge.moonBall(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY))
        #expect(ball.isMoon)
        #expect(!ball.isOutOfPark, "180m の中堅は場外の距離を越えるが、月を優先する")
        #expect(HomerunText.kind(of: ball) == "月まで飛んだ！")
        #expect(HomerunText.distance(of: ball) == "384,400 km")
        #expect(HomerunText.place(ball) == "月")
        var broken = ball
        broken.moon = .broken
        #expect(HomerunText.kind(of: broken) == "月が割れた！")

        let plan = HomerunSwingPlan(phase: .ballResult, clock: clock, lastBall: ball)
        let contact = try #require(plan.contactAt)
        #expect(plan.chaseTrack == nil)
        let frame = try #require(plan.chaseFrame(at: contact.addingTimeInterval(1)))
        #expect(frame == HomerunMoonShot.frame(.hit, at: 1))
        #expect(plan.chaseCardAt == contact.addingTimeInterval(HomerunMoonShot.cardDelay(.hit)))
        // カードは結果を閉じる前に出る。
        let resultEnd = release.addingTimeInterval(HomerunModel.resultDuration(for: ball))
        #expect(try #require(plan.chaseCardAt) < resultEnd)
    }

    @Test("月の絵: 模様にクレーターとヒビ（正面だけ）・半球の殻と断面は外向き・星は固定の並び")
    func moonArt() {
        let front = simd_normalize(SIMD3<Float>(-0.04, 0, 1))   // ヒビの本筋の上（正面）
        #expect(HomerunMoonArt.isCrack(front))
        #expect(!HomerunMoonArt.isCrack([0, 0, -1]))
        #expect(HomerunMoonArt.color(front, cracked: false) != HomerunMoonArt.crack)
        #expect(HomerunMoonArt.color(front, cracked: true) == HomerunMoonArt.crack)
        let crater = HomerunMoonArt.craters[0].direction
        #expect(HomerunMoonArt.color(crater, cracked: false) == HomerunMoonArt.craterFill)
        #expect(HomerunMoonArt.pixels(cracked: true).count == HomerunMoonArt.textureWidth * HomerunMoonArt.textureHeight * 4)

        let sphere = HomerunMoonMesh.shell(radius: 1, rings: 8, segments: 16)
        let right = HomerunMoonMesh.shell(radius: 1, fromLon: -.pi / 2, toLon: .pi / 2, rings: 8, segments: 8)
        #expect(right.positions.allSatisfy { $0.x >= -1e-5 })
        for mesh in [sphere, right, HomerunMoonMesh.cap(radius: 1, facingPositiveX: true, segments: 8),
                     HomerunMoonMesh.cap(radius: 1, facingPositiveX: false, segments: 8)] {
            // 三角形の表（(v1 − v0) × (v2 − v0)）が頂点の法線と同じ向き（退化した極の三角形は除く）。
            for k in stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = mesh.positions[Int(mesh.indices[k])], b = mesh.positions[Int(mesh.indices[k + 1])]
                let c = mesh.positions[Int(mesh.indices[k + 2])]
                let n = simd_cross(b - a, c - a)
                guard simd_length(n) > 1e-6 else { continue }
                let vertexNormal = mesh.normals[Int(mesh.indices[k])] + mesh.normals[Int(mesh.indices[k + 1])] + mesh.normals[Int(mesh.indices[k + 2])]
                #expect(simd_dot(n, vertexNormal) > 0)
            }
        }
        #expect(HomerunMoonArt.stars.count == 90)
        #expect(HomerunMoonArt.stars.map(\.x) == HomerunMoonArt.stars.map(\.x))
        #expect(HomerunMoonArt.stars.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }
}
