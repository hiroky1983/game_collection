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
