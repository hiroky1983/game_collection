import Core
import Foundation
import Testing
@testable import GameHanafuda
import CoreTestSupport

/// ルール分岐の記録区分（#827・1局=1RuleSet 規約 2〜4）。
///
/// 既定ルールの記録の保存先（`hanafuda`）と順位表は動かさず、局数・酒の役・CPU の強さの
/// どれかが既定と違う試合だけを別枠に記録し、Game Center へは送らない。
@MainActor
@Suite("花札: ルール分岐の記録区分")
struct HanafudaRecordVariantTests {

    /// 決着まで機械的に回す（`HanafudaModelTests.playOut` のこいこいしない版）。
    private func playOut(_ model: HanafudaModel, limit: Int = 400) -> Bool {
        for _ in 0..<limit {
            switch model.phase {
            case .playing:
                if let selection = model.selection {
                    model.chooseFieldCard(selection.candidates[0])
                } else if model.turn == .human {
                    guard let card = model.humanHand.first(where: { model.canPlay($0) }) else {
                        return false
                    }
                    model.play(card)
                } else {
                    model.stepCPU()
                }
            case .koiKoiPrompt:
                if model.canStop { model.declareStop() } else { model.declareKoiKoi() }
            case .roundResult:
                model.advanceAfterRound()
            case .matchResult:
                return true
            case .idle:
                return false
            }
        }
        return false
    }

    private func makeLog(_ suite: String) -> PlayLog {
        let name = "asobiba.hanafuda.tests.variant.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PlayLog(defaults: defaults)
    }

    // MARK: 区分の値

    @Test("既定ルールは区分なし・区分名なし・順位表の対象")
    func defaultOptionsKeepTheLegacyRecord() {
        let options = HanafudaOptions()
        #expect(options.recordVariant == nil)
        #expect(options.recordVariantLabel == nil)
        #expect(options.isLeaderboardEligible)
    }

    @Test("局数・酒の役・強さのどれか1つでも既定と違えば別枠で、順位表の対象外", arguments: [
        HanafudaOptions(rounds: 12),
        HanafudaOptions(sakeYakuEnabled: false),
        HanafudaOptions(difficulty: .easy),
        HanafudaOptions(difficulty: .hard),
    ])
    func nonDefaultOptionsAreSeparated(options: HanafudaOptions) {
        #expect(options.recordVariant != nil)
        #expect(options.recordVariantLabel != nil)
        #expect(!options.isLeaderboardEligible)
    }

    @Test("区分キーと区分名は組み合わせごとに別の値になる")
    func variantKeysAreDistinctPerCombination() {
        var keys: [String?] = []
        var labels: [String?] = []
        for rounds in HanafudaOptions.allowedRounds {
            for sake in [true, false] {
                for difficulty in HanafudaDifficulty.allCases {
                    let options = HanafudaOptions(sakeYakuEnabled: sake, rounds: rounds, difficulty: difficulty)
                    keys.append(options.recordVariant)
                    labels.append(options.recordVariantLabel)
                }
            }
        }
        #expect(keys.count == 12)
        #expect(Set(keys).count == keys.count)
        #expect(Set(labels).count == labels.count)
        let all = HanafudaOptions(sakeYakuEnabled: false, rounds: 12, difficulty: .easy)
        #expect(all.recordVariant == "r12-nosake-easy")
        #expect(all.recordVariantLabel == "12局・酒の役なし・CPU弱")
    }

    // MARK: 記録と送信

    @Test("既定外のルールで最後まで打った試合は別枠に記録され、リーダーボードへ送られない")
    func nonDefaultMatchIsRecordedSeparately() {
        let log = makeLog("finish")
        let spy = SpyGameCenterService()
        let model = HanafudaModel(
            services: makeServices(log: log, gameCenter: spy), cpuDelay: .zero, seed: 61
        )
        let options = HanafudaOptions(sakeYakuEnabled: false)
        model.startMatch(options: options)
        #expect(playOut(model))
        #expect(model.recordResult != nil)
        let record = log.record(gameID: HanafudaModel.gameID, variant: options.recordVariant)
        #expect(record?.plays == 1)
        #expect(record?.variantLabel == options.recordVariantLabel)
        #expect(log.record(gameID: HanafudaModel.gameID) == nil, "既定ルールの行に混ざらない")
        #expect(spy.scores.isEmpty)
    }

    @Test("既定外のルールの投了も別枠に記録され、既定ルールの投了は従来どおり送られる")
    func resignFollowsTheSameSplit() {
        let log = makeLog("resign")
        let spy = SpyGameCenterService()
        let services = makeServices(log: log, gameCenter: spy)

        let easy = HanafudaOptions(difficulty: .easy)
        let variantModel = HanafudaModel(services: services, cpuDelay: .zero, seed: 71)
        variantModel.startMatch(options: easy)
        variantModel.resign()
        #expect(log.record(gameID: HanafudaModel.gameID, variant: easy.recordVariant)?.losses == 1)
        #expect(log.record(gameID: HanafudaModel.gameID) == nil)
        #expect(spy.scores.isEmpty)

        // 対照: 既定ルールは保存先 `hanafuda` のまま、投了でも文数が送られる。
        let standardModel = HanafudaModel(services: services, cpuDelay: .zero, seed: 72)
        standardModel.startMatch(options: HanafudaOptions())
        standardModel.resign()
        #expect(log.record(gameID: HanafudaModel.gameID)?.losses == 1)
        #expect(spy.scores.count == 1)
        #expect(spy.scores.first?.leaderboardID == GameCenterLeaderboard.hanafudaPoints)
    }

    // MARK: 中断データ

    @Test("options の鍵が無い中断データは捨てずに既定ルールで復元する")
    func snapshotWithoutOptionsFallsBackToDefaults() throws {
        let store = MemorySnapshotStore()
        let model = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 81)
        model.startMatch(options: HanafudaOptions())
        let saved = try #require(store.load(HanafudaSnapshot.self, for: HanafudaModel.gameID))
        let encoded = try JSONEncoder().encode(saved)
        var json = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["options"] != nil, "前提: 今の保存データには options の鍵がある")
        json.removeValue(forKey: "options")
        store.inject(try JSONSerialization.data(withJSONObject: json), for: HanafudaModel.gameID)

        let restored = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 999)
        #expect(restored.phase == model.phase, "中断が黙って消えていない")
        #expect(restored.humanHand == model.humanHand)
        #expect(restored.round == model.round)
        #expect(restored.options == HanafudaOptions())
    }
}
