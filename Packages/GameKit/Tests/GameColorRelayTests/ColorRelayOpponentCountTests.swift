import Testing
import Foundation
import Core
@testable import GameColorRelay
import CoreTestSupport

@MainActor
private func makeModel(store: SnapshotStore = MemorySnapshotStore()) -> (ColorRelayModel, GameServices) {
    let services = GameServices(snapshots: store, ads: NoopAdService())
    return (ColorRelayModel(services: services, cpuDelay: .zero, seed: 42), services)
}

@Suite("いろリレーの相手の人数（#2866）")
@MainActor
struct ColorRelayOpponentCountTests {
    @Test("既定は相手 3 人（4 人対戦）で、1〜3 人を選べる")
    func defaultsToThreeOpponents() {
        let (model, _) = makeModel()
        #expect(model.opponentCount == 3)
        #expect(Array(ColorRelayModel.opponentCountRange) == [1, 2, 3])
        model.startGame()
        #expect(model.hands.count == 4)
    }

    @Test("人数ぶんだけ 7 枚ずつ配り、番は人数で回る", arguments: [1, 2, 3])
    func dealsForEachCount(opponents: Int) {
        let (model, _) = makeModel()
        model.startGame(opponentCount: opponents)
        #expect(model.playerCount == opponents + 1)
        #expect(model.hands.count == opponents + 1)
        #expect(model.lastActions.count == opponents + 1)
        for hand in model.hands { #expect(hand.count == ColorRelayRules.initialHandCount) }
        #expect(model.nextPlayer(after: opponents) == 0)
        model.configureForTesting(hands: model.hands, top: model.topCard!, isClockwise: false)
        #expect(model.nextPlayer(after: 0) == opponents)
    }

    @Test("結果のまま人数を減らして始め直すとき、hands が縮む前に ranking は空になる（#3084）")
    func rankingClearsBeforeHandsShrink() async {
        let (model, _) = makeModel()
        model.startGame(opponentCount: 3)
        var turns = 0
        while model.phase == .playing, turns < 3_000 {
            turns += 1
            await model.runCPUTurnsIfNeeded()
            guard model.phase == .playing, model.isPlayerTurn else { continue }
            if model.isPlayerPenalized {
                model.takePenalty()
            } else if let id = model.playableCardIDs.sorted().first,
                      let card = model.playerHand.first(where: { $0.id == id }) {
                model.toggleSelection(card)
                model.playSelected(color: card.isWild ? ColorRelayRules.dominantColor(in: model.playerHand) : nil)
            } else if model.canDraw {
                model.drawCard()
            } else {
                model.endTurn()
            }
        }
        #expect(model.ranking.count == 4)
        var rankingWhenHandsChanged: [Int]?
        withObservationTracking {
            _ = model.hands
        } onChange: {
            MainActor.assumeIsolated { rankingWhenHandsChanged = model.ranking }
        }
        model.startGame(opponentCount: 1)
        #expect(rankingWhenHandsChanged == [])
        #expect(model.hands.count == 2)
        #expect(model.ranking.isEmpty)
    }

    @Test("どの人数でも最後まで決着し、順位は人数ぶん並ぶ", arguments: [1, 2, 3])
    func playsToFinish(opponents: Int) async {
        let (model, _) = makeModel()
        model.startGame(opponentCount: opponents)
        var turns = 0
        while model.phase == .playing, turns < 3_000 {
            turns += 1
            await model.runCPUTurnsIfNeeded()
            guard model.phase == .playing, model.isPlayerTurn else { continue }
            if model.isPlayerPenalized {
                model.takePenalty()
            } else if let id = model.playableCardIDs.sorted().first,
                      let card = model.playerHand.first(where: { $0.id == id }) {
                model.toggleSelection(card)
                model.playSelected(color: card.isWild ? ColorRelayRules.dominantColor(in: model.playerHand) : nil)
            } else if model.canDraw {
                model.drawCard()
            } else {
                model.endTurn()
            }
        }
        #expect(model.phase == .result)
        #expect(model.ranking.sorted() == Array(0...opponents))
    }

    @Test("選んだ人数は次のゲーム・開き直しにも残り、強さだけ変えても人数は変わらない")
    func countCarriesOver() {
        let (model, services) = makeModel()
        model.startGame(opponentCount: 1)
        model.startGame(aiLevel: CPUStrength.hard.rawValue)
        #expect(model.opponentCount == 1)
        let reopened = ColorRelayModel(services: services, cpuDelay: .zero)
        #expect(reopened.opponentCount == 1)
        #expect(reopened.aiLevel == CPUStrength.hard.rawValue)
    }

    @Test("人数を持たない旧バージョンの設定は相手 3 人で読む")
    func legacyPreferencesMeanThreeOpponents() throws {
        let store = MemorySnapshotStore()
        store.inject(try JSONSerialization.data(withJSONObject: ["aiLevel": CPUStrength.easy.rawValue]), for: "colorrelay-prefs")
        let (model, _) = makeModel(store: store)
        #expect(model.opponentCount == 3)
        #expect(model.aiLevel == CPUStrength.easy.rawValue)
    }

    @Test("対局中の人数は中断データの手札の数で戻り、続きから遊べる")
    func countSurvivesResume() async {
        let store = MemorySnapshotStore()
        let (model, services) = makeModel(store: store)
        model.startGame(opponentCount: 2)
        let deck = RelayCard.makeDeck()
        func card(_ color: RelayColor, _ n: Int) -> RelayCard { deck.first { $0.color == color && $0.kind == .number(n) }! }
        model.configureForTesting(
            hands: [[card(.red, 1), card(.red, 2)], [card(.green, 1), card(.green, 2)], [card(.green, 3), card(.green, 4)]],
            top: card(.red, 7), drawPile: [card(.green, 5)])
        model.toggleSelection(card(.red, 1))
        model.playSelected()
        #expect(store.exists(for: "colorrelay"))
        let resumed = ColorRelayModel(services: services, cpuDelay: .zero)
        #expect(resumed.phase == .playing)
        #expect(resumed.playerCount == 3)
        #expect(resumed.lastActions.count == 3)
        await resumed.runCPUTurnsIfNeeded()
        #expect(resumed.phase == .playing || resumed.phase == .result)
    }

    @Test("記録の区分: 相手 3 人は従来どおり（ふつうは区分なし）、ほかの人数は人数ごとに分かれる")
    func recordVariantPerOpponentCount() {
        let (model, _) = makeModel()
        model.startGame(aiLevel: CPUStrength.normal.rawValue, opponentCount: 3)
        #expect(model.recordScore.variant == nil)
        model.startGame(aiLevel: CPUStrength.hard.rawValue)
        #expect(model.recordScore.variant == "hard")   // 既存の 4 人の区分のまま
        model.startGame(aiLevel: CPUStrength.normal.rawValue, opponentCount: 2)
        #expect(model.recordScore.variant == "cpu2")
        model.startGame(aiLevel: CPUStrength.easy.rawValue, opponentCount: 1)
        #expect(model.recordScore.variant == "cpu1-easy")
        // 表示名は表から引き直せて、保存する日本語名と一致する。
        for (key, ja, en) in [("cpu2", "相手2人", "2 opponents"), ("cpu1", "相手1人", "1 opponent"),
                              ("cpu1-easy", "相手1人・CPUかんたん", "1 opponent · CPU Easy"),
                              ("cpu2-novice", "相手2人・CPU入門", "2 opponents · CPU Beginner")] {
            #expect(RecordVariantLabels.label(recordKey: "colorrelay#\(key)", language: .japanese) == ja)
            #expect(RecordVariantLabels.label(recordKey: "colorrelay#\(key)", language: .english) == en)
        }
        #expect(model.recordScore.variantLabel == "相手1人・CPUかんたん")
        #expect(RecordVariantLabels.label(recordKey: "colorrelay#cpu3", language: .japanese) == nil)
        #expect(RecordVariantLabels.label(recordKey: "colorrelay#cpu0", language: .japanese) == nil)
    }

    @Test("人数の範囲外は丸める")
    func clampsOutOfRange() {
        let (model, _) = makeModel()
        model.startGame(opponentCount: 9)
        #expect(model.opponentCount == 3)
        model.startGame(opponentCount: 0)
        #expect(model.opponentCount == 1)
    }
}
