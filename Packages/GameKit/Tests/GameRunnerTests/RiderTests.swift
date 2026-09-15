import Core
import Foundation
import Testing
@testable import GameRunner

/// 走者のコマの選び方と絵の置き方の検証（#701）。
///
/// 見た目の置き換えなので当たり判定は動かないが、**コマの切り替えと原点の決め方は純粋な値の
/// 計算**なので、`RunnerScene` を作らずに固定する（漕ぐ脚が 2 リンクだった頃の `RiderTests` の後継）。
@Suite("チャリンコおじさん: 走者のコマ")
struct RunnerRiderTests {

    // MARK: 位相

    @Test("接地して進んだぶんだけクランクが回る")
    func advancesWhileGrounded() {
        let phase = RunnerRider.advance(phase: 0, by: RunnerRider.crankTravel, isPedaling: true)
        #expect(abs(phase - 2 * .pi) < 1e-12)
    }

    @Test("空中では漕げないので位相が止まる")
    func freezesInAir() {
        #expect(RunnerRider.advance(phase: 1.5, by: 40, isPedaling: false) == 1.5)
    }

    @Test("距離が戻っても位相は戻らない（やり直し・チェックポイント再開）")
    func ignoresBackwardDistance() {
        #expect(RunnerRider.advance(phase: 1.5, by: -120, isPedaling: true) == 1.5)
    }

    @Test("走り出しから接地したままの位相は距離だけで決まる")
    func phaseFromGroundedDistance() {
        let phase = RunnerRider.phase(forGroundedDistance: RunnerRider.crankTravel * 1.5)
        #expect(abs(phase - 3 * .pi) < 1e-12)
    }

    // MARK: 漕ぐコマ

    @Test("半回転ごとに右ペダル前と左ペダル前が入れ替わる")
    func alternatesEveryHalfTurn() {
        #expect(RunnerRider.pedalFrame(phase: 0) == .ride0)
        #expect(RunnerRider.pedalFrame(phase: .pi - 0.01) == .ride0)
        #expect(RunnerRider.pedalFrame(phase: .pi) == .ride1)
        #expect(RunnerRider.pedalFrame(phase: 2 * .pi - 0.01) == .ride1)
        #expect(RunnerRider.pedalFrame(phase: 2 * .pi) == .ride0)
        // 何周しても周期は変わらない。
        #expect(RunnerRider.pedalFrame(phase: 7 * .pi + 0.1) == .ride1)
    }

    @Test("クランク 1 回転（crankTravel）で漕ぐコマがちょうど 2 回入れ替わる")
    func twoSwapsPerTurn() {
        var swaps = 0
        var last = RunnerRider.pedalFrame(phase: 0)
        for step in 1...260 {
            let distance = RunnerRider.crankTravel * Double(step) / 260
            let frame = RunnerRider.pedalFrame(phase: RunnerRider.phase(forGroundedDistance: distance))
            if frame != last { swaps += 1; last = frame }
        }
        #expect(swaps == 2)
    }

    // MARK: 局面ごとのコマ

    @Test("走り出す前は ride0、接地して走行中は位相のコマ、空中は jump")
    func framesWhileAlive() {
        #expect(RunnerRider.frame(phase: .ready, isGrounded: true, pedalPhase: 0) == .ride0)
        #expect(RunnerRider.frame(phase: .running, isGrounded: true, pedalPhase: 0.5) == .ride0)
        #expect(RunnerRider.frame(phase: .running, isGrounded: true, pedalPhase: .pi + 0.5) == .ride1)
        #expect(RunnerRider.frame(phase: .paused, isGrounded: true, pedalPhase: .pi + 0.5) == .ride1)
        #expect(RunnerRider.frame(phase: .running, isGrounded: false, pedalPhase: .pi + 0.5) == .jump)
        #expect(RunnerRider.frame(phase: .cleared, isGrounded: true, pedalPhase: 0) == .ride0)
    }

    @Test("落下・激突の演出中は tumble、演出明けの失敗は dizzy（接地・位相によらない）")
    func framesWhenFailing() {
        for grounded in [true, false] {
            for pedalPhase in [0.0, .pi + 0.5] {
                #expect(RunnerRider.frame(phase: .falling, isGrounded: grounded, pedalPhase: pedalPhase) == .tumble)
                #expect(RunnerRider.frame(phase: .failed, isGrounded: grounded, pedalPhase: pedalPhase) == .dizzy)
            }
        }
    }

    // MARK: 置き方

    @Test("1 ドットは図形時代の見た目の高さをコマの不透明部分の高さで割った大きさ")
    func unitMatchesLegacyHeight() {
        let sprite = OjisanPixel.rider(.ride0)
        let placement = RunnerRider.placement(for: sprite)
        let opaqueHeight = Double(sprite.opaqueBounds?.height ?? 0)
        #expect(opaqueHeight > 0)
        #expect(abs(placement.unit * opaqueHeight - RunnerRider.visualHeight) < 1e-9)
        // 1 ドット ≈ 0.33 単位（40×37 のコマで走者が幅 13・高さ 12 ほどに描かれる）。
        #expect(placement.unit > 0.3 && placement.unit < 0.36)
    }

    @Test("原点は車輪の底の行・両輪の接地点の中央（player の原点 = 足元に乗る）")
    func anchorSitsBetweenWheelsOnTheGround() {
        let sprite = OjisanPixel.rider(.ride0)
        let placement = RunnerRider.placement(for: sprite)
        // 車輪の底はコマの最下行なので、y の原点はスプライトの下端。
        #expect(placement.anchorY == 0)
        // 最下行で色の付いた範囲（後輪の接地点〜前輪の接地点）の中央。
        let bottom = sprite.rows[sprite.rows.count - 1]
        let columns = bottom.enumerated().filter { $0.element != "." }.map(\.offset)
        let expected = (Double(columns.min()!) + Double(columns.max()!) + 1) / 2 / Double(sprite.width)
        #expect(abs(placement.anchorX - expected) < 1e-12)
        // 後輪と前輪の間（画の左右の中央付近）にある。
        #expect(placement.anchorX > 0.4 && placement.anchorX < 0.6)
    }

    @Test("全コマの車輪の底は同じ行にある（1 つの原点を全コマに使える）")
    func allFramesShareTheGroundRow() {
        let base = OjisanPixel.rider(.ride0)
        guard let baseBounds = base.opaqueBounds else {
            Issue.record("ride0 が空")
            return
        }
        let groundRow = baseBounds.y + baseBounds.height
        for frame in OjisanPixel.RiderFrame.allCases {
            let sprite = OjisanPixel.rider(frame)
            #expect(sprite.width == base.width && sprite.height == base.height, "\(frame) の格子が違う")
            #expect((sprite.opaqueBounds?.y ?? -1) + (sprite.opaqueBounds?.height ?? 0) == groundRow,
                    "\(frame) の車輪の底が ride0 と違う行にある")
        }
    }
}
