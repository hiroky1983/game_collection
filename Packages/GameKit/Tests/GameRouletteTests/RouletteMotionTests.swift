import Testing
import Foundation
import GameKitTestSupport
@testable import GameRoulette

/// ホイールの回転の演出（#1318）。
///
/// 見た目そのものはシミュレータでしか確認できないので、**出目 → 止まる角度の翻訳**と
/// **長さの整合**をここで固定する。定数だけでは View 側の外し忘れを素通しするため、
/// 結線もブラックジャック（`BlackjackMotionTests`）と同じやり方でソースから見る。
@Suite("ルーレットの演出")
struct RouletteMotionTests {

    typealias Motion = RouletteMotion

    @Test("ポケット 1 つぶんの角度は 360 ÷ 37")
    func pocketStep() {
        #expect(abs(Motion.pocketStep - 360.0 / 37.0) < 1e-9)
        #expect(abs(Motion.pocketAngle(index: 0)) < 1e-9)
        #expect(abs(Motion.pocketAngle(index: 37) - 360) < 1e-9)
    }

    @Test("止まる角度は、そのポケットを 12 時へ持ってくる")
    func targetRotationBringsPocketToTop() {
        for index in 0..<RouletteWheel.pocketCount {
            let target = Motion.targetRotation(from: 0, toPocket: index)
            // ホイールを `target` 度回したあとのポケットの位置 = 元の角度 + target ≡ 0（12 時）。
            let landed = (Motion.pocketAngle(index: index) + target).truncatingRemainder(dividingBy: 360)
            let distance = min(landed, 360 - landed)
            #expect(distance < 1e-6, "ポケット \(index) が 12 時に来ていない（\(landed) 度）")
        }
    }

    @Test("必ず時計回りに規定の周回数以上回って、1 周未満で止まる")
    func targetRotationAlwaysSpinsForward() {
        var current = 123.4
        for index in [0, 1, 18, 36, 5, 5] {
            let target = Motion.targetRotation(from: current, toPocket: index)
            #expect(target >= current + Motion.spinTurns * 360 - 1e-9, "逆回転や不足がある")
            #expect(target < current + (Motion.spinTurns + 1) * 360, "1 周ぶん余計に回っている")
            current = target
        }
    }

    @Test("同じポケットへ続けて止めても、また規定の周回数だけ回る")
    func repeatedSamePocketStillSpins() {
        let first = Motion.targetRotation(from: 0, toPocket: 10)
        let second = Motion.targetRotation(from: first, toPocket: 10)
        #expect(abs((second - first) - Motion.spinTurns * 360) < 1e-9)
    }

    @Test("Model の待ち時間と View の回転の長さは同じ値から作る")
    func spinIntervalMatchesDuration() {
        #expect(Motion.spinDuration > 0)
        #expect(Motion.spinInterval == .milliseconds(Int((Motion.spinDuration * 1000).rounded())))
        #expect(Motion.spinTurns >= 2, "少なすぎると回った感じがしない")
        #expect(Motion.resultBadgeDuration < Motion.spinDuration, "出目のバッジは山場より短い")
    }

    @Test("View はスピンを Motion の定数と純関数で組み、素の Animation を書いていない")
    func viewIsWiredToMotion() throws {
        let view = try SourceScan.packageSource("Sources/GameRoulette/RouletteView.swift")
        #expect(SourceScan.matchCount(of: #"withGameAnimation\(RouletteMotion\.spin\)"#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"RouletteMotion\.targetRotation\(from:"#, in: view) == 1)
        #expect(SourceScan.matchCount(of: #"RouletteModel\(services: services, spinInterval: spinInterval\)"#, in: view) == 1,
                "Model へ Motion 由来の待ち時間を渡していない")
        #expect(SourceScan.matchCount(of: #"\.gameAnimation\(RouletteMotion\.resultBadge"#, in: view) == 1)
    }
}
