import Foundation
import Testing
@testable import GameRunner

/// 漕ぐおじさんの脚の形の検証（#569 決裁A）。
///
/// 見た目の追加なので当たり判定は動かないが、**2リンクの逆運動学は位相によって破綻しうる**
/// （膝が伸びきる・関節が裏返る・足が地面にめり込む）。`RunnerScene` を作らずに全周を
/// 走査して、どの位相でも成立していることを機械的に押さえる。
@Suite("チャリンコおじさん: 漕ぐ脚")
struct RunnerRiderTests {

    /// 1 回転を 360 分割して全周を見る。
    private var wholeTurn: [Double] {
        (0..<360).map { Double($0) / 360 * 2 * .pi }
    }

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

    @Test("走り出す前の脚の形が寸法どおりに決まる")
    func poseAtRest() {
        // 長さや向きの検証は「実装の定数」を期待値に使うため、**定数そのものの書き換えは
        // 検知できない**（腿を伸ばす・クランクを動かす等）。ここだけは座標を直に固定して、
        // 寸法を触ったら必ず気付くようにする（絵の作り直しなら、この期待値も一緒に直す）。
        let near = RunnerRider.leg(phase: 0, isFar: false)
        #expect(abs(near.pedal.x - 1.3) < 0.001)
        #expect(abs(near.pedal.y - 3.6) < 0.001)
        #expect(abs(near.knee.x - 0.9354) < 0.001)
        #expect(abs(near.knee.y - 5.8709) < 0.001)
        let far = RunnerRider.leg(phase: 0, isFar: true)
        #expect(abs(far.pedal.x - (-0.9)) < 0.001)
        #expect(abs(far.pedal.y - 3.6) < 0.001)
        #expect(abs(far.knee.x - 0.6854) < 0.001)
        #expect(abs(far.knee.y - 5.2663) < 0.001)
    }

    @Test("クランクは車輪と同じ向き（前進で時計回り）に回る")
    func turnsWithTheWheels() {
        // 走者は +x を向いており、`RunnerScene` は車輪を `-distance` で回す = 時計回り。
        // ペダルも時計回りでなければ後ろ漕ぎに見えるので、外積の符号で向きを固定する。
        for phase in wholeTurn {
            for isFar in [false, true] {
                let before = RunnerRider.pedal(phase: phase, isFar: isFar)
                let after = RunnerRider.pedal(phase: phase + 0.01, isFar: isFar)
                let ax = before.x - RunnerRider.crank.x, ay = before.y - RunnerRider.crank.y
                let bx = after.x - RunnerRider.crank.x, by = after.y - RunnerRider.crank.y
                #expect(ax * by - ay * bx < 0)
            }
        }
    }

    @Test("左右の脚は常に反対側のペダルを踏む")
    func pedalsAreOpposite() {
        for phase in wholeTurn {
            let near = RunnerRider.pedal(phase: phase, isFar: false)
            let far = RunnerRider.pedal(phase: phase, isFar: true)
            // クランクの軸を挟んで点対称。
            #expect(abs((near.x + far.x) / 2 - RunnerRider.crank.x) < 1e-12)
            #expect(abs((near.y + far.y) / 2 - RunnerRider.crank.y) < 1e-12)
        }
    }

    @Test("どの位相でも腿とすねの長さが保たれる（伸びきり・縮みが起きない）")
    func keepsSegmentLengths() {
        for phase in wholeTurn {
            for isFar in [false, true] {
                let leg = RunnerRider.leg(phase: phase, isFar: isFar)
                #expect(abs(distance(leg.hip, leg.knee) - RunnerRider.thigh) < 1e-9)
                #expect(abs(distance(leg.knee, leg.pedal) - RunnerRider.shin) < 1e-9)
            }
        }
    }

    @Test("どの位相でもペダルが脚の届く範囲に余裕を持って収まる")
    func pedalStaysInReach() {
        let maxReach = RunnerRider.thigh + RunnerRider.shin
        let minReach = abs(RunnerRider.thigh - RunnerRider.shin)
        for phase in wholeTurn {
            for isFar in [false, true] {
                let leg = RunnerRider.leg(phase: phase, isFar: isFar)
                let reach = distance(leg.hip, leg.pedal)
                // 端に張り付くと丸めが働いて長さが崩れるので、両端から離れていることまで見る。
                #expect(reach < maxReach - 0.2)
                #expect(reach > minReach + 0.2)
            }
        }
    }

    @Test("膝は常に腰より前に出る（後ろへ折れた姿勢にならない）")
    func kneeBendsForward() {
        for phase in wholeTurn {
            for isFar in [false, true] {
                let leg = RunnerRider.leg(phase: phase, isFar: isFar)
                #expect(leg.knee.x > leg.hip.x)
            }
        }
    }

    @Test("足は地面より上にある（靴が地面にめり込まない）")
    func feetStayAboveGround() {
        for phase in wholeTurn {
            for isFar in [false, true] {
                // 走者ノードのローカル座標では y = 0 が接地点。
                #expect(RunnerRider.pedal(phase: phase, isFar: isFar).y > 1.0)
            }
        }
    }

    private func distance(_ a: RunnerPoint, _ b: RunnerPoint) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}
