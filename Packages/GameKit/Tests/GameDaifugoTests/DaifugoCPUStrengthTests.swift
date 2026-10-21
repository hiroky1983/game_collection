import Testing
import Foundation
import Core
@testable import GameDaifugo
import CoreTestSupport

/// 常に同じ値を返す乱数。`Double.random(in: 0..<1, using:)` が 0 に近い値（0）か 1 に近い値（max）になる。
private struct FixedRNG: RandomNumberGenerator {
    let value: UInt64
    mutating func next() -> UInt64 { value }
}

@MainActor
private func makeModel(store: SnapshotStore = MemorySnapshotStore()) -> (DaifugoModel, GameServices) {
    let services = GameServices(snapshots: store, ads: NoopAdService())
    return (DaifugoModel(services: services, cpuDelay: .zero, seed: 42), services)
}

@Suite("大富豪の CPU の強さ（#2604）")
struct DaifugoCPUStrengthRulesTests {
    private func play(
        _ hand: [DaifugoCard], field: [DaifugoCard] = [], isRevolution: Bool = false,
        _ strength: CPUStrength, minOpponent: Int = .max, rng: UInt64 = .max
    ) -> [DaifugoCard]? {
        var generator = FixedRNG(value: rng)
        return DaifugoRules.cpuPlay(
            hand: hand, field: field, isRevolution: isRevolution, strength: strength,
            minOpponentHandCount: minOpponent, using: &generator)
    }

    @Test("「ふつう」は貪欲法と同じ手を選ぶ（回帰なし）")
    func normalMatchesGreedy() {
        let hands: [([DaifugoCard], [DaifugoCard])] = [
            ([card(4), card(5), card(6), card(1)], [card(13)]),
            ([card(3), card(3, .hearts), card(9), card(2)], []),
            ([card(7), card(7, .hearts), card(11)], [card(5), card(5, .hearts)]),
        ]
        for (hand, field) in hands {
            #expect(play(hand, field: field, .normal) == DaifugoRules.greedyPlay(hand: hand, field: field, isRevolution: false))
        }
    }

    @Test("「むずかしい」は強い札しか出せない追随でパスして温存し、「ふつう」は出す")
    func hardHoardsStrongCard() {
        let hand = [card(4), card(5), card(6), card(1)]   // 場の K に勝てるのは A だけ
        let field = [card(13)]
        #expect(play(hand, field: field, .normal) == [card(1)])
        #expect(play(hand, field: field, .hard) == nil, "A を温存してパスする")
    }

    @Test("「むずかしい」でも、誰かが上がり間近・自分も上がり間近なら温存しない")
    func hardDoesNotHoardWhenRaceIsTight() {
        let field = [card(13)]
        #expect(play([card(4), card(5), card(6), card(1)], field: field, .hard, minOpponent: 2) == [card(1)])
        #expect(play([card(4), card(1)], field: field, .hard) == [card(1)], "手札が少ないときは上がりを急ぐ")
    }

    @Test("「むずかしい」は弱い札ばかりの手札で、親番に革命から始める")
    func hardLeadsRevolution() {
        let four = [card(5), card(5, .hearts), card(5, .diamonds), card(5, .clubs)]
        let hand = four + [card(3), card(4), card(6)]
        let normal = play(hand, .normal)
        #expect(normal?.count == 1, "ふつうは最弱の 1 枚から出す")
        let hard = play(hand, .hard)
        #expect(hard.map(DaifugoRules.triggersRevolution) == true)
    }

    @Test("「むずかしい」は強い札が多い手札では革命を起こさない")
    func hardKeepsOrderWhenHandIsStrong() {
        let four = [card(5), card(5, .hearts), card(5, .diamonds), card(5, .clubs)]
        let hand = four + [card(3), card(1), card(2), card(13), card(12), card(11)]
        let hard = play(hand, .hard)
        #expect(hard == [card(3)], "革命せず、ふつうと同じ最弱の 1 枚")
    }

    @Test("「かんたん」は乱数しだいで次善手を選び、外れたときは最善手のまま")
    func easySlipsSometimes() {
        let hand = [card(4), card(5), card(6)]
        let field = [card(3)]
        #expect(play(hand, field: field, .easy, rng: .max) == [card(4)], "乱数が大きいと最善手")
        #expect(play(hand, field: field, .easy, rng: 0) == [card(5)], "乱数が小さいと次善手")
    }

    @Test("強さごとに同じ局面で選ぶ手が変わる")
    func strengthsDiffer() {
        let hand = [card(4), card(5), card(6), card(1)]
        let field = [card(13)]
        let picks = [
            CPUStrength.hard: play(hand, field: field, .hard),
            .normal: play(hand, field: field, .normal),
        ]
        #expect(picks[.hard]! != picks[.normal]!)
        #expect(play(hand, field: [card(3)], .easy, rng: 0) != play(hand, field: [card(3)], .normal))
    }

    @Test("どの強さでも、返す手は必ず合法手（パスを除く）")
    func alwaysLegal() {
        var generator = SeededGenerator(seed: 99)
        for strength in CPUStrength.allCases {
            for _ in 0..<200 {
                var deck = DaifugoCard.makeDeck()
                deck.shuffle(using: &generator)
                let hand = Array(deck.prefix(10))
                let field = Bool.random(using: &generator) ? [] : [deck[10]].filter { !$0.isJoker }
                guard let picked = DaifugoRules.cpuPlay(
                    hand: hand, field: field, isRevolution: false, strength: strength, using: &generator
                ) else { continue }
                #expect(DaifugoRules.isValidPlay(picked, field: field, isRevolution: false))
                #expect(picked.allSatisfy { p in hand.contains(p) })
            }
        }
    }
}

@Suite("大富豪の CPU の強さの保存と記録（#2604）")
@MainActor
struct DaifugoCPUStrengthModelTests {
    @Test("既定は「ふつう」で、渡した強さは次のゲームにも引き継ぐ")
    func levelCarriesToNextGame() {
        let (model, _) = makeModel()
        #expect(model.aiLevel == CPUStrength.normal.rawValue)
        model.startGame(aiLevel: CPUStrength.hard.rawValue)
        #expect(model.aiLevel == CPUStrength.hard.rawValue)
        model.startGame()
        #expect(model.aiLevel == CPUStrength.hard.rawValue, "強さを渡さない次のゲームは前の強さのまま")
    }

    @Test("対局中の強さは中断データに入り、再開で変わらない")
    func levelSurvivesResume() {
        let store = MemorySnapshotStore()
        let (model, services) = makeModel(store: store)
        model.startGame(aiLevel: CPUStrength.easy.rawValue)
        model.configureForTesting(hands: [[card(3), card(9)], [card(13), card(4)], [card(12), card(5)], [card(11), card(6)]],
                                  field: [card(7)], fieldOwner: 3, currentPlayer: 0)
        model.toggleSelection(card(9))
        model.playSelected()
        #expect(store.exists(for: "daifugo"))
        let resumed = DaifugoModel(services: services, cpuDelay: .zero)
        #expect(resumed.aiLevel == CPUStrength.easy.rawValue)
    }

    @Test("決着後に開き直しても、選んだ強さが次ゲームに残る")
    func levelSurvivesAfterResultViaCarryOver() async {
        let store = MemorySnapshotStore()
        let (model, services) = makeModel(store: store)
        model.startGame(aiLevel: CPUStrength.hard.rawValue)
        model.configureForTesting(hands: [[card(3)], [card(13), card(4)], [card(12), card(5)], [card(11), card(6)]],
                                  field: [], currentPlayer: 0)
        model.toggleSelection(card(3))
        model.playSelected()
        await model.runCPUTurnsIfNeeded()
        model.resign()
        #expect(model.phase == .result)
        let reopened = DaifugoModel(services: services, cpuDelay: .zero)
        #expect(reopened.aiLevel == CPUStrength.hard.rawValue)
    }

    @Test("強さの無い旧バージョンの中断データは「ふつう」で再開する")
    func legacySnapshotResumesAsNormal() throws {
        let store = MemorySnapshotStore()
        store.inject(Data(DaifugoSnapshotCompatibilityTests.v116JSON.utf8), for: "daifugo")
        let model = DaifugoModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero, seed: 42)
        #expect(model.phase == .playing)
        #expect(model.aiLevel == CPUStrength.normal.rawValue)
    }

    @Test("記録は「ふつう」だけ区分なし、ほかの強さは強さ別の区分に分かれる")
    func recordVariantPerStrength() {
        let (model, _) = makeModel()
        model.startGame()
        #expect(model.recordScore.variant == nil, "ふつうは従来の記録のまま")
        for strength in CPUStrength.allCases where strength != .normal {
            model.startGame(aiLevel: strength.rawValue)
            #expect(model.recordScore.variant == strength.recordVariantKey)
            #expect(model.recordScore.variantLabel == RecordVariantLabels.label(
                recordKey: "daifugo#\(strength.recordVariantKey)", language: .japanese))
        }
    }
}
