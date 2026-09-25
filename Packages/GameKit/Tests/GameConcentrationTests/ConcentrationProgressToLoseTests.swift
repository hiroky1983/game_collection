import Testing
import Core
@testable import GameConcentration

/// 「新規」の確認を出すかの境目（#1011）。
@MainActor
@Suite("神経衰弱 新規で失われる進行（#1011）")
struct ConcentrationProgressToLoseTests {

    @Test("1 枚もめくっていなければ失うものは無い")
    func untouchedBoardHasNothingToLose() {
        let model = ConcentrationModel(services: nil)
        #expect(!model.hasProgressToLose)
    }

    @Test("1 枚めくったら失う進行がある")
    func flippedCardIsProgress() {
        let model = ConcentrationModel(services: nil)
        model.tap(index: 0)
        #expect(model.hasProgressToLose)
    }

    @Test("新規対戦で盤が入れ替われば、また失うものは無い")
    func newGameResetsProgress() {
        let model = ConcentrationModel(services: nil)
        model.tap(index: 0)
        model.newGame(pairCount: .small, cpuLevel: .normal)
        #expect(!model.hasProgressToLose)
    }

    @Test("全部取り終えて決着したら失うものは無い")
    func finishedGameHasNothingToLose() throws {
        let model = ConcentrationModel(services: nil)
        model.newGame(pairCount: .small, cpuLevel: .normal)
        var guardCount = 0
        while !model.isGameOver, guardCount < 200 {
            guardCount += 1
            guard let first = model.cards.indices.first(where: { !model.cards[$0].isMatched }),
                  let second = model.cards.indices.first(where: {
                      $0 != first && !model.cards[$0].isMatched && model.cards[$0].symbol == model.cards[first].symbol
                  }) else { break }
            model.tap(index: first)
            model.tap(index: second)
        }
        try #require(model.isGameOver)
        #expect(!model.hasProgressToLose)
    }
}
