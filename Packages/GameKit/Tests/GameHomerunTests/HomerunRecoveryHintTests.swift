import Testing
@testable import GameHomerun

/// 結果の「あと少しで自己ベスト」の案内を出す条件（#2724）。
@Suite("柵越えおじさんの回復の案内")
struct HomerunRecoveryHintTests {
    @Test("自己ベストの 8 割以上で届かなかったら差を m で返す（切り上げ）")
    func closeMiss() {
        #expect(HomerunRecoveryHint.metersToBest(totalTenths: 4700, bestTenths: 5000, isNewBest: false) == 30)
        #expect(HomerunRecoveryHint.metersToBest(totalTenths: 4991, bestTenths: 5000, isNewBest: false) == 1)
        #expect(HomerunRecoveryHint.metersToBest(totalTenths: 4000, bestTenths: 5000, isNewBest: false) == 100)
    }

    @Test("離れすぎ・更新した・同じ・記録なしでは出さない")
    func noHint() {
        #expect(HomerunRecoveryHint.metersToBest(totalTenths: 3999, bestTenths: 5000, isNewBest: false) == nil)
        #expect(HomerunRecoveryHint.metersToBest(totalTenths: 5000, bestTenths: 5000, isNewBest: true) == nil)
        #expect(HomerunRecoveryHint.metersToBest(totalTenths: 5000, bestTenths: 5000, isNewBest: false) == nil)
        #expect(HomerunRecoveryHint.metersToBest(totalTenths: 0, bestTenths: 0, isNewBest: false) == nil)
    }
}
