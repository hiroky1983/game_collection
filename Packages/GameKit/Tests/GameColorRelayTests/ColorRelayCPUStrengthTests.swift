import Testing
import Foundation
import Core
@testable import GameColorRelay
import CoreTestSupport

/// 常に同じ値を返す乱数。`Double.random(in: 0..<1, using:)` が 0（max なら 1 近く）になる。
private struct FixedRNG: RandomNumberGenerator {
    let value: UInt64
    mutating func next() -> UInt64 { value }
}

@MainActor
private func makeModel(store: SnapshotStore = MemorySnapshotStore()) -> (ColorRelayModel, GameServices) {
    let services = GameServices(snapshots: store, ads: NoopAdService())
    return (ColorRelayModel(services: services, cpuDelay: .zero, seed: 42), services)
}

@Suite("いろリレーの CPU の強さ（#2604）")
struct ColorRelayCPUStrengthRulesTests {
    private func play(
        _ hand: [RelayCard], top: RelayCard, color: RelayColor, next: Int,
        _ strength: CPUStrength, rng: UInt64 = .max
    ) -> RelayCard? {
        var generator = FixedRNG(value: rng)
        return ColorRelayRules.cpuPlay(
            hand: hand, top: top, activeColor: color, nextHandCount: next, strength: strength, using: &generator)
    }

    private let top = card(.red, .number(5))

    @Test("「ふつう」は従来の貪欲法と同じ札を選ぶ（回帰なし）")
    func normalMatchesGreedy() {
        let hand = [card(.red, .number(9)), card(.red, .drawTwo), card(.green, .number(5)), card(nil, .wild)]
        for next in [1, 2, 3, 5] {
            #expect(play(hand, top: top, color: .red, next: next, .normal)
                    == ColorRelayRules.cpuPlay(hand: hand, top: top, activeColor: .red, nextHandCount: next))
        }
    }

    @Test("次の人の手札が 3 枚のとき、「むずかしい」は攻撃札を出し、「ふつう」は出さない")
    func hardAttacksEarlier() {
        let hand = [card(.red, .number(9)), card(.red, .drawTwo)]
        #expect(play(hand, top: top, color: .red, next: 3, .normal) == card(.red, .number(9)))
        #expect(play(hand, top: top, color: .red, next: 3, .hard) == card(.red, .drawTwo))
        #expect(play(hand, top: top, color: .red, next: 4, .hard) == card(.red, .number(9)), "4 枚以上なら攻撃しない")
    }

    @Test("「かんたん」は乱数しだいででたらめに選び、攻撃札も優先しない")
    func easyIsLoose() {
        let hand = [card(.red, .number(9)), card(.red, .drawTwo)]
        // 乱数が大きい（ぶれない）ときも、次の人が 1 枚でも攻撃しない。
        #expect(play(hand, top: top, color: .red, next: 1, .easy, rng: .max) == card(.red, .number(9)))
        // 乱数が 0 のときはでたらめ側（出せる札の先頭）。
        let slipped = play(hand, top: top, color: .red, next: 5, .easy, rng: 0)
        #expect(slipped != nil)
        #expect(play(hand, top: top, color: .red, next: 1, .normal) == card(.red, .drawTwo))
    }

    @Test("どの強さでも、返す札は必ず出せる札で、出せる札が無ければ nil")
    func alwaysPlayable() {
        var generator = SplitMix64(seed: 5)
        let deck = RelayCard.makeDeck()
        for strength in CPUStrength.allCases {
            for _ in 0..<200 {
                var shuffled = deck
                shuffled.shuffle(using: &generator)
                let hand = Array(shuffled.prefix(7))
                let top = shuffled[7]
                guard top.color != nil else { continue }
                let color = top.color!
                let picked = ColorRelayRules.cpuPlay(
                    hand: hand, top: top, activeColor: color, nextHandCount: 3, strength: strength, using: &generator)
                let playable = ColorRelayRules.playableCardIDs(hand: hand, top: top, activeColor: color)
                if let picked {
                    #expect(playable.contains(picked.id))
                } else {
                    #expect(playable.isEmpty)
                }
            }
        }
    }
}

@Suite("いろリレーの CPU の強さの保存と記録（#2604）")
@MainActor
struct ColorRelayCPUStrengthModelTests {
    @Test("既定は「ふつう」で、渡した強さは次のゲームにも引き継ぐ")
    func levelCarriesToNextGame() {
        let (model, _) = makeModel()
        #expect(model.aiLevel == CPUStrength.normal.rawValue)
        model.startGame(aiLevel: CPUStrength.hard.rawValue)
        model.startGame()
        #expect(model.aiLevel == CPUStrength.hard.rawValue)
    }

    @Test("対局中の強さは中断データに入り、再開で変わらない")
    func levelSurvivesResume() async {
        let store = MemorySnapshotStore()
        let (model, services) = makeModel(store: store)
        model.startGame(aiLevel: CPUStrength.easy.rawValue)
        model.configureForTesting(
            hands: [[card(.red, .number(1)), card(.red, .number(2))],
                    [card(.green, .number(1)), card(.green, .number(2))],
                    [card(.green, .number(3)), card(.green, .number(4))],
                    [card(.green, .number(5)), card(.green, .number(6))]],
            top: card(.red, .number(7)), drawPile: [card(.green, .number(1))])
        model.toggleSelection(card(.red, .number(1)))
        model.playSelected()
        #expect(store.exists(for: "colorrelay"))
        let resumed = ColorRelayModel(services: services, cpuDelay: .zero)
        #expect(resumed.aiLevel == CPUStrength.easy.rawValue)
    }

    @Test("選んだ強さは、中断データが無くても開き直した次のゲームに残る")
    func levelSurvivesWithoutSnapshot() {
        let (model, services) = makeModel()
        model.startGame(aiLevel: CPUStrength.hard.rawValue)
        let reopened = ColorRelayModel(services: services, cpuDelay: .zero)
        #expect(reopened.aiLevel == CPUStrength.hard.rawValue)
    }

    @Test("強さの無い旧バージョンの中断データは「ふつう」で再開する")
    func legacySnapshotResumesAsNormal() throws {
        let store = MemorySnapshotStore()
        let (model, services) = makeModel(store: store)
        model.startGame()
        model.configureForTesting(
            hands: [[card(.red, .number(1)), card(.red, .number(2))],
                    [card(.green, .number(1)), card(.green, .number(2))],
                    [card(.green, .number(3)), card(.green, .number(4))],
                    [card(.green, .number(5)), card(.green, .number(6))]],
            top: card(.red, .number(7)), drawPile: [card(.green, .number(1))])
        model.toggleSelection(card(.red, .number(1)))
        model.playSelected()
        // aiLevel の鍵を取り除いて旧バージョンの保存データを再現する。
        let data = try #require(store.rawData(for: "colorrelay"))
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "aiLevel")
        store.inject(try JSONSerialization.data(withJSONObject: json), for: "colorrelay")
        let resumed = ColorRelayModel(services: services, cpuDelay: .zero)
        #expect(resumed.phase == .playing)
        #expect(resumed.aiLevel == CPUStrength.normal.rawValue)
    }

    @Test("記録は「ふつう」だけ区分なし、ほかの強さは強さ別の区分に分かれる")
    func recordVariantPerStrength() {
        let (model, _) = makeModel()
        model.startGame()
        #expect(model.recordScore.variant == nil)
        for strength in CPUStrength.allCases where strength != .normal {
            model.startGame(aiLevel: strength.rawValue)
            #expect(model.recordScore.variant == strength.recordVariantKey)
            #expect(model.recordScore.variantLabel == RecordVariantLabels.label(
                recordKey: "colorrelay#\(strength.recordVariantKey)", language: .japanese))
        }
    }
}
