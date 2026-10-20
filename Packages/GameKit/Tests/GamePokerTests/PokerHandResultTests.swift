import Testing
import Foundation
import Core
@testable import GamePoker

@Suite("ポーカーの 1 回の決着表示（#1754・#2551）")
@MainActor
struct PokerHandResultTests {

    @Test("決着するまでは出さない")
    func nilBeforeResult() {
        let (model, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.flush))
        #expect(model.handResult == nil)
    }

    @Test("勝つと、見出し・役の対比・もらった点が出る（チップの増減は出さない）")
    func win() throws {
        let (model, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.flush))
        model.confirmExchange()
        model.finishExchange()
        let result = try #require(model.handResult)

        #expect(result.kind == .win)
        #expect(result.headline == "勝ち！")
        #expect(result.reason == "\(model.playerHandRank.description) 対 \(model.cpuHandRank.description)（+12点）")
        #expect(result.chipDelta == nil)
        #expect(result.chipText == nil)
    }

    @Test("負けは点を添えない")
    func loss() throws {
        let (model, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.junk))
        model.confirmExchange()
        model.finishExchange()
        let result = try #require(model.handResult)

        #expect(result.kind == .lose)
        #expect(result.headline == "負け")
        #expect(!result.reason.contains("点"))
    }

    @Test("引き分けは「どちらも」で伝える")
    func tie() throws {
        let (model, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.tieStraight))
        model.confirmExchange()
        model.finishExchange()
        let result = try #require(model.handResult)

        #expect(result.kind == .draw)
        #expect(result.reason == "どちらも\(model.playerHandRank.description)")
    }

    @Test("次の回を配ると結果は消える")
    func clearedOnNextRound() {
        let (model, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.flush))
        model.confirmExchange()
        model.finishExchange()
        #expect(model.handResult != nil)

        model.nextRound()
        #expect(model.handResult == nil)
        #expect(model.lastRoundPoints == 0)
    }
}
