import Testing
import Foundation
import Core
@testable import GameBlackjack
import CoreTestSupport

/// プレイヤーのターンの中断データを注入して復元する（配りが乱数なので手札を決め打ちするため）。
@MainActor
private func makeModel(player: [Int], dealer: [Int], deck: [Int],
                       hands: ((inout BlackjackTable) -> [BlackjackHand])? = nil) -> BlackjackModel {
    makeBlackjackModel(blackjackSnapshot(player: player, dealer: dealer, deck: deck, hands: hands))
}

@Suite("ブラックジャックの 1 回の決着表示（#1754・#2552 で勝ち点を添える）")
@MainActor
struct BlackjackHandResultTests {

    @Test("決着するまでは出さない")
    func nilBeforeResult() {
        let model = makeModel(player: [10, 8], dealer: [10, 7], deck: [])
        #expect(model.handResult == nil)
    }

    @Test("勝つと点数の対比と +1 点が理由に出る。枚数の行は出さない")
    func win() throws {
        let model = makeModel(player: [10, 9], dealer: [10, 7], deck: [])
        model.stand()
        let result = try #require(model.handResult)

        #expect(result.kind == .win)
        #expect(result.headline == "勝ち！")
        #expect(result.reason == "あなた19 対 ディーラー17（+1点）")
        #expect(result.chipDelta == nil)
        #expect(result.chipText == nil)
    }

    @Test("バストすると負け。理由に点数が出て、勝ち点は添えない")
    func bust() throws {
        let model = makeModel(player: [10, 6], dealer: [10, 7], deck: [10])
        model.hit()
        let result = try #require(model.handResult)

        #expect(result.kind == .lose)
        #expect(result.reason == "バスト（26）")
        #expect(result.chipDelta == nil)
    }

    @Test("ディーラーがバストして勝つ")
    func dealerBust() throws {
        let model = makeModel(player: [10, 8], dealer: [10, 6], deck: [10])
        model.stand()
        let result = try #require(model.handResult)

        #expect(result.kind == .win)
        #expect(result.reason == "ディーラーがバスト（26）（+1点）")
    }

    @Test("同点は引き分け")
    func push() throws {
        let model = makeModel(player: [10, 8], dealer: [10, 8], deck: [])
        model.stand()
        let result = try #require(model.handResult)

        #expect(result.kind == .draw)
        #expect(result.reason == "あなた18 対 ディーラー18")
        #expect(result.chipText == nil)
    }

    @Test("スプリットで手ごとに勝敗が割れても、見出し・理由・実際の点が一致する")
    func splitMixed() throws {
        // ハンド1: 20（勝ち）/ ハンド2: 12（負け）。ディーラーは 17 で止まる。
        let model = makeModel(player: [10, 10], dealer: [10, 7], deck: []) { table in [
            BlackjackHand(id: 0, cards: table.cards([10, 10]), isFromSplit: true),
            BlackjackHand(id: 1, cards: table.cards([10, 2]), isFromSplit: true),
        ] }
        model.stand()
        model.stand()
        let result = try #require(model.handResult)

        #expect(model.points == 1)
        #expect(result.kind == .win, "勝ち点が入った回は勝ちとして見せる")
        #expect(result.reason == "ハンド1 勝ち / ハンド2 負け（+1点）")
    }

    @Test("次の回へ進むと結果は消える")
    func clearedOnNextRound() {
        let model = makeModel(player: [10, 9], dealer: [10, 7], deck: [])
        model.stand()
        #expect(model.handResult != nil)

        model.nextRound()
        if model.phase == .playerTurn {
            #expect(model.handResult == nil)
            #expect(model.roundPoints == nil)
        }
    }

    @Test("読み上げに枚数の増減を含めない")
    func spokenTextHasNoChipCount() throws {
        let model = makeModel(player: [10, 9], dealer: [10, 7], deck: [])
        model.stand()
        let result = try #require(model.handResult)
        #expect(result.spokenText == "勝ちです。あなた19 対 ディーラー17（+1点）")
    }
}
