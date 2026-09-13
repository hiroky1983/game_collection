import Testing
@testable import GameConcentration

/// 広告の待ったを、広告を出す前に控えた局にだけ適用する（#729）。
@MainActor
@Suite("神経衰弱 広告の待ったの局ガード（#729）")
struct ConcentrationRewardedMattaTests {

    @Test("広告のあいだに新規ゲームを始めたら、前の局の待ったは新しい局に乗らない")
    func mattaForReplacedGameIsRejected() throws {
        let model = ConcentrationModel(services: nil, autoClearDelay: 40_000_000)
        let game = model.gameSerial
        model.newGame(pairCount: .medium, cpuLevel: .normal)
        // 新しい局でも不一致を出し、「戻せる不一致が無い」という状態の確認だけでは弾けない形にする。
        let a = 0
        let b = try #require(model.cards.indices.first { model.cards[$0].symbol != model.cards[a].symbol })
        model.tap(index: a)
        model.tap(index: b)
        // View と同じく、確認のあいだは自動のターン交代を止める。
        model.pauseAutoTurn()
        try #require(model.canMatta)

        #expect(!model.useMatta(forGame: game), "入れ替わった局で待ったを適用している")
        #expect(model.mismatchedIndices.count == 2)
        #expect(model.useMatta(forGame: model.gameSerial), "今の局に対する広告なら戻せる")
        #expect(model.mismatchedIndices.isEmpty)
    }
}
