import Foundation
import Testing
@testable import GameBlocks

/// 盤面の進行（#463）。
@Suite("ブロック崩しの盤面")
struct FieldTests {

    private func field(_ rows: [String], speed: Double = 70) -> BlocksField {
        BlocksField(stage: BlocksStage(number: 1, rows: rows, ballSpeed: speed), speed: speed)
    }

    /// ブロックの無い盤（球とパドルと壁だけを見たいとき）。
    private func emptyField(speed: Double = 70) -> BlocksField {
        field([".........", "........."], speed: speed)
    }

    // MARK: - パドル

    @Test("パドルは盤の外へ出ない")
    func paddleStaysInside() {
        var f = emptyField()
        let half = BlocksField.Metrics.paddleHalfWidth
        f.movePaddle(to: -50)
        #expect(f.paddleX == half)
        f.movePaddle(to: 999)
        #expect(f.paddleX == BlocksField.Metrics.width - half)
        f.movePaddle(to: 40)
        #expect(f.paddleX == 40)
    }

    @Test("発射前の球はパドルに乗って一緒に動く")
    func ballRidesOnPaddleBeforeLaunch() {
        var f = emptyField()
        f.movePaddle(to: 30)
        #expect(f.ball.x == 30)
        #expect(f.ball.y == BlocksField.Metrics.restingBallY)
        #expect(!f.ball.isMoving)
    }

    @Test("発射後の球はパドルの動きに引きずられない")
    func ballIsFreeAfterLaunch() {
        var f = emptyField()
        f.launch()
        let x = f.ball.x
        f.movePaddle(to: 10)
        #expect(f.ball.x == x)
    }

    @Test("発射すると上向きに、ステージの速さちょうどで飛ぶ")
    func launchUsesStageSpeed() {
        var f = emptyField(speed: 88)
        f.launch()
        #expect(f.ball.vy > 0)
        #expect(abs(f.ball.speed - 88) < 1e-9)
        // 二度発射しても速度は変わらない。
        let before = f.ball
        f.launch()
        #expect(f.ball == before)
    }

    @Test("停止中の球は step で動かない（イベントも出ない）")
    func stoppedBallDoesNotMove() {
        var f = emptyField()
        let before = f.ball
        #expect(f.step(dt: 1).isEmpty)
        #expect(f.ball == before)
    }

    // MARK: - 壁

    @Test("左右の壁と天井で跳ね返る")
    func bouncesOffWalls() {
        var f = emptyField()
        let r = BlocksField.Metrics.ballRadius

        f.placeBall(x: r + 0.1, y: 80, vx: -70, vy: 0.1)
        #expect(f.step(dt: 0.05).contains(.wallBounce))
        #expect(f.ball.vx > 0)
        #expect(f.ball.x >= r)

        f.placeBall(x: BlocksField.Metrics.width - r - 0.1, y: 80, vx: 70, vy: 0.1)
        #expect(f.step(dt: 0.05).contains(.wallBounce))
        #expect(f.ball.vx < 0)

        f.placeBall(x: 50, y: BlocksField.Metrics.height - r - 0.1, vx: 0.1, vy: 70)
        #expect(f.step(dt: 0.05).contains(.wallBounce))
        #expect(f.ball.vy < 0)
        #expect(f.ball.y <= BlocksField.Metrics.height - r)
    }

    // MARK: - パドルの反射と落球

    @Test("パドルに当たると跳ね返り、当てた位置で角度が変わる")
    func paddleReflects() {
        var f = emptyField()
        f.movePaddle(to: 50)
        // パドルの右寄りへ落とす。
        f.placeBall(x: 55, y: BlocksField.Metrics.paddleTop + 2.2, vx: 0, vy: -70)
        let events = f.step(dt: 0.02)
        #expect(events.contains(.paddleBounce))
        #expect(f.ball.vy > 0)
        #expect(f.ball.vx > 0, "中心より右で当てたら右へ返る")

        f.movePaddle(to: 50)
        f.placeBall(x: 45, y: BlocksField.Metrics.paddleTop + 2.2, vx: 0, vy: -70)
        #expect(f.step(dt: 0.02).contains(.paddleBounce))
        #expect(f.ball.vx < 0, "中心より左で当てたら左へ返る")
    }

    @Test("パドルを外すと落球する")
    func missingThePaddleLosesTheBall() {
        var f = emptyField()
        f.movePaddle(to: 10)
        f.placeBall(x: 90, y: 8, vx: 0, vy: -70)
        let events = f.step(dt: 0.3)
        #expect(events.last == .ballLost)
        #expect(!events.contains(.paddleBounce))
    }

    @Test("落球したらその先のできごとは返さない（1 回の落球を 2 回と数えない）")
    func stopsAtBallLost() {
        var f = emptyField()
        f.movePaddle(to: 10)
        f.placeBall(x: 90, y: 4, vx: 0, vy: -70)
        let events = f.step(dt: 1.0)
        #expect(events.filter { $0 == .ballLost }.count == 1)
        #expect(events.last == .ballLost)
    }

    @Test("パドルの真下を通り抜ける球を拾い上げない")
    func doesNotCatchBallBelowPaddle() {
        var f = emptyField()
        f.movePaddle(to: 50)
        // すでにパドルより十分下にいる球。
        f.placeBall(x: 50, y: 3, vx: 0, vy: -70)
        let events = f.step(dt: 0.2)
        #expect(!events.contains(.paddleBounce))
        #expect(events.contains(.ballLost))
    }

    // MARK: - ブロック

    @Test("通常ブロックに当たると壊れ、跳ね返る")
    func breaksNormalBlock() {
        var f = field(["....n...."])
        let rect = BlocksField.blockRect(row: 0, column: 4)
        f.placeBall(x: rect.midX, y: rect.minY - 2.1, vx: 0, vy: 70)
        let events = f.step(dt: 0.02)
        #expect(events == [.blockHit(row: 0, column: 4, kind: .normal, destroyed: true)])
        #expect(f.block(row: 0, column: 4) == nil)
        #expect(f.ball.vy < 0, "下から当てたら下へ返る")
        #expect(f.isCleared)
    }

    @Test("硬いブロックは 2 回当てないと消えず、1 回目は残る")
    func hardBlockTakesTwoHits() {
        var f = field(["....h...."])
        let rect = BlocksField.blockRect(row: 0, column: 4)

        f.placeBall(x: rect.midX, y: rect.minY - 2.1, vx: 0, vy: 70)
        #expect(f.step(dt: 0.02) == [.blockHit(row: 0, column: 4, kind: .hard, destroyed: false)])
        #expect(f.block(row: 0, column: 4)?.remaining == 1)
        #expect(!f.isCleared)

        f.placeBall(x: rect.midX, y: rect.minY - 2.1, vx: 0, vy: 70)
        #expect(f.step(dt: 0.02) == [.blockHit(row: 0, column: 4, kind: .hard, destroyed: true)])
        #expect(f.block(row: 0, column: 4) == nil)
        #expect(f.isCleared)
    }

    @Test("壊れないブロックは跳ね返すだけで、クリア判定にも数えない")
    func solidBlockOnlyReflects() {
        var f = field(["....s...."])
        #expect(f.isCleared, "壊せるブロックが 0 なので最初からクリア済み扱い")
        let rect = BlocksField.blockRect(row: 0, column: 4)
        f.placeBall(x: rect.midX, y: rect.minY - 2.1, vx: 0, vy: 70)
        #expect(f.step(dt: 0.02) == [.blockHit(row: 0, column: 4, kind: .solid, destroyed: false)])
        #expect(f.block(row: 0, column: 4)?.kind == .solid)
        #expect(f.ball.vy < 0)
    }

    @Test("横から当たったら左右反転する")
    func sideHitFlipsHorizontally() {
        var f = field(["....n...."])
        let rect = BlocksField.blockRect(row: 0, column: 4)
        f.placeBall(x: rect.minX - 2.1, y: rect.midY, vx: 70, vy: 0.5)
        #expect(f.step(dt: 0.02).count == 1)
        #expect(f.ball.vx < 0)
    }

    @Test("1 サブステップで壊すブロックは 1 個だけ（角で二重反転しない）")
    func resolvesOneBlockPerSubstep() {
        var f = field(["...nn...."])
        let left = BlocksField.blockRect(row: 0, column: 3)
        // 2 個の境目の真下へ、ちょうど接する高さで置く。
        f.placeBall(x: left.maxX, y: left.minY - 2.05, vx: 0, vy: 70)
        let events = f.step(dt: 0.01)
        #expect(events.count == 1, "同じサブステップで 2 個ぶんのイベントが出ている: \(events)")
        #expect(f.ball.vy < 0, "二重反転して上向きのままになっていない")
    }

    /// 1 フレームの移動量がブロックの厚みを超えると、素朴な実装では当たり判定を飛び越える。
    ///
    /// **現行のステージ速度と `maxStep` の組み合わせでは、まだこの状況に届かない**
    /// （最速 \(BlocksStage.all.map(\.ballSpeed).max()!) × 1/20 秒 = 約 5.7 に対し、
    /// すり抜けには「厚み 5 + 直径 4 = 9」が要る）。それでも押さえておくのは、
    /// **ステージを足して速度曲線を伸ばした瞬間に静かに壊れる**種類の不具合だからで、
    /// ここでは意図的に将来の速度域（最速の 4 倍）で確かめる。
    @Test("1 フレームの移動量がブロックの厚みを超えてもすり抜けない")
    func neverTunnelsThroughBlocks() {
        let speed = BlocksStage.all.map(\.ballSpeed).max()! * 4
        var f = field(["....n...."], speed: speed)
        let rect = BlocksField.blockRect(row: 0, column: 4)
        f.placeBall(x: rect.midX, y: rect.minY - 2.05, vx: 0, vy: speed)
        // 1 サブステップに割らないと 1 回で 22 以上進み、厚み 5 のブロックを飛び越える。
        let events = f.step(dt: BlocksRules.maxStep)
        #expect(events.contains { if case .blockHit = $0 { return true } else { return false } },
                "ブロックをすり抜けた（events: \(events)）")
        #expect(f.block(row: 0, column: 4) == nil)
    }

    @Test("1 フレームの移動量がパドルの当たり判定の帯を超えてもすり抜けない")
    func neverTunnelsThroughPaddle() {
        let speed = BlocksStage.all.map(\.ballSpeed).max()! * 4
        var f = emptyField(speed: speed)
        f.movePaddle(to: 50)
        // パドルを拾う帯（およそ 5.9 の幅）のすぐ上から、真下へ落とす。
        f.placeBall(x: 50, y: BlocksField.Metrics.paddleTop + BlocksField.Metrics.ballRadius + 1,
                    vx: 0, vy: -speed)
        let events = f.step(dt: BlocksRules.maxStep)
        #expect(events.contains(.paddleBounce), "パドルを飛び越えた（events: \(events)）")
        #expect(!events.contains(.ballLost))
    }

    @Test("ブロックが 1 個でも残っていればクリアではない")
    func clearedOnlyWhenBreakablesAreGone() {
        var f = field(["nn......."])
        #expect(f.remainingBreakableCount == 2)
        let rect = BlocksField.blockRect(row: 0, column: 0)
        f.placeBall(x: rect.midX, y: rect.minY - 2.1, vx: 0, vy: 70)
        _ = f.step(dt: 0.02)
        #expect(f.remainingBreakableCount == 1)
        #expect(!f.isCleared)
    }

    // MARK: - ゆっくりモード

    @Test("速さを変えても向きは変わらない")
    func setSpeedKeepsDirection() {
        var f = emptyField(speed: 100)
        f.launch()
        let before = f.ball
        f.setSpeed(50)
        #expect(abs(f.ball.speed - 50) < 1e-9)
        // 向き（vx : vy の比）が保たれている。
        #expect(abs(f.ball.vx / f.ball.vy - before.vx / before.vy) < 1e-9)
        #expect(f.ball.vy > 0)
    }

    @Test("停止中に速さを変えても勝手に動き出さない")
    func setSpeedDoesNotLaunch() {
        var f = emptyField(speed: 100)
        f.setSpeed(40)
        #expect(!f.ball.isMoving)
        f.launch()
        #expect(abs(f.ball.speed - 40) < 1e-9, "次の発射から新しい速さが効く")
    }

    // MARK: - 詰みの防止

    /// 真横に近い角度で固定されると、球は左右の壁を往復し続けてパドルにもブロックにも
    /// 二度と届かなくなる（ブロック崩しの古典的な詰みバグ）。角度を作るのはパドルとブロックの
    /// 反射だけなので、**実際に長く遊ばせて `|vy| / 速さ` の下限が守られ続けるか**を見る。
    @Test("何度反射しても球が真横に張り付かない")
    func neverSettlesIntoHorizontalLoop() {
        var f = field([
            "nnnnnnnnn",
            "n.n.n.n.n",
            "nnnnnnnnn",
        ], speed: 110)
        f.launch()
        var minimumRatio = Double.infinity
        var paddleBounces = 0
        for _ in 0..<20_000 {
            // パドルは常に球の真下へ置く（落とさずに打ち続ける）。
            f.movePaddle(to: f.ball.x)
            for event in f.step(dt: 1.0 / 60) where event == .paddleBounce {
                paddleBounces += 1
            }
            if f.ball.y < 0 { break }
            minimumRatio = min(minimumRatio, abs(f.ball.vy) / f.ball.speed)
        }
        #expect(paddleBounces > 10, "パドルに当たらないまま終わっている（\(paddleBounces) 回）")
        #expect(
            minimumRatio >= BlocksField.Metrics.minimumVerticalRatio - 1e-9,
            "水平に近い角度になった（比: \(minimumRatio)）"
        )
    }
}
