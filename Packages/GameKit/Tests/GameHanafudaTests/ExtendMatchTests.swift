import Core
import Foundation
import Testing
@testable import GameHanafuda
import CoreTestSupport

/// 最終局で負けているときに広告で 1 局延長する救済（#1049）。
@MainActor
@Suite("花札: 広告で1局延長")
struct HanafudaExtendMatchTests {

    /// 決着まで機械的に回す。`onRoundResult` は局の結果画面に来るたびに呼ぶ。
    @discardableResult
    private func playOut(
        _ model: HanafudaModel, limit: Int = 400,
        onRoundResult: (HanafudaModel) -> Void = { _ in }
    ) -> Bool {
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
                onRoundResult(model)
                // `onRoundResult` が延長して次の局を配っていたら、結果画面はもう終わっている。
                if model.phase == .roundResult { model.advanceAfterRound() }
            case .matchResult:
                return true
            case .idle:
                return false
            }
        }
        return false
    }

    private func makeLog(_ suite: String) -> PlayLog {
        let name = "asobiba.hanafuda.tests.extend.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PlayLog(defaults: defaults)
    }

    /// 指定の局・累計で「局の結果画面」にいる中断データを作って、そこから復元したモデルを返す。
    /// 札の並びは実際に配った局面を使う（48 枚の検証を通すため）。
    private func modelAtRoundResult(
        round: Int, humanTotal: Int, cpuTotal: Int,
        options: HanafudaOptions = HanafudaOptions(rounds: 6),
        hasExtendedMatch: Bool? = nil,
        store: MemorySnapshotStore = MemorySnapshotStore(),
        services: (@MainActor (MemorySnapshotStore) -> GameServices)? = nil
    ) throws -> HanafudaModel {
        let seedModel = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 7)
        seedModel.startMatch(options: options)
        let dealt = try #require(store.load(HanafudaSnapshot.self, for: HanafudaModel.gameID))
        let snap = HanafudaSnapshot(
            options: options, round: round, dealer: .cpu, turn: .cpu,
            hands: dealt.hands, captured: dealt.captured, field: dealt.field, deck: dealt.deck,
            claimed: [0, 0], koiKoiCounts: [0, 0], totals: [humanTotal, cpuTotal],
            phase: .roundResult, selection: nil, drawnCard: nil,
            roundResult: HanafudaRoundResult(winner: .cpu, hits: [], basePoints: 5, score: 5, reasons: []),
            message: "CPUのあがり！ 5文",
            hasExtendedMatch: hasExtendedMatch
        )
        store.inject(try JSONEncoder().encode(snap), for: HanafudaModel.gameID)
        let model = HanafudaModel(
            services: services?(store) ?? makeServices(store: store), cpuDelay: .zero, seed: 8
        )
        #expect(model.phase == .roundResult, "中断データから復元できていない（前提が壊れている）")
        return model
    }

    // MARK: 導線を出す条件

    @Test("最終局で負けているときだけ延長できる")
    func offeredOnlyWhenLosingTheFinalRound() throws {
        #expect(try modelAtRoundResult(round: 6, humanTotal: 3, cpuTotal: 10).canExtendMatch)
        #expect(try !modelAtRoundResult(round: 6, humanTotal: 10, cpuTotal: 3).canExtendMatch, "勝っている")
        #expect(try !modelAtRoundResult(round: 6, humanTotal: 5, cpuTotal: 5).canExtendMatch, "引き分け")
        #expect(try !modelAtRoundResult(round: 5, humanTotal: 3, cpuTotal: 10).canExtendMatch, "最終局ではない")
    }

    @Test("対局中や試合の決着後には延長できない")
    func notOfferedOutsideTheFinalRoundResult() throws {
        let model = try modelAtRoundResult(round: 6, humanTotal: 3, cpuTotal: 10)
        model.advanceAfterRound()
        #expect(model.phase == .matchResult)
        #expect(!model.canExtendMatch)

        let playing = HanafudaModel(cpuDelay: .zero, seed: 1)
        playing.startMatch(options: HanafudaOptions(rounds: 6))
        #expect(!playing.canExtendMatch)
    }

    // MARK: 延長

    @Test("広告を見ると延長戦が配られ、累計はそのまま続きから遊べる")
    func extendingDealsAnExtraRound() throws {
        let model = try modelAtRoundResult(round: 6, humanTotal: 3, cpuTotal: 10)
        #expect(model.extendMatchAfterAd(forGame: model.gameSerial))
        #expect(model.phase == .playing)
        #expect(model.round == 7)
        #expect(model.totalRounds == 7)
        #expect(model.humanTotal == 3)
        #expect(model.cpuTotal == 10)
        #expect(model.humanHand.count == 8)
        #expect(model.hasExtendedMatch)
        #expect(!model.canExtendMatch)
    }

    @Test("見なかったときは従来どおり最終局で試合が決着する")
    func withoutTheAdTheMatchEndsAsBefore() throws {
        let model = try modelAtRoundResult(round: 6, humanTotal: 3, cpuTotal: 10)
        #expect(model.canExtendMatch)
        model.advanceAfterRound()
        #expect(model.phase == .matchResult)
        #expect(model.round == 6)
    }

    @Test("延長は1試合に1回まで。延長戦で負けても2回目は出ず、延長戦で決着する")
    func extensionIsOncePerMatch() throws {
        let model = try modelAtRoundResult(round: 6, humanTotal: 0, cpuTotal: 100)
        #expect(model.extendMatchAfterAd(forGame: model.gameSerial))
        var results = 0
        var offeredAgain = false
        let finished = playOut(model) { m in
            results += 1
            if m.canExtendMatch || m.extendMatchAfterAd(forGame: m.gameSerial) { offeredAgain = true }
        }
        #expect(finished)
        #expect(results == 1)
        #expect(!offeredAgain, "延長戦の結果画面で2回目の延長が出た")
        #expect(model.phase == .matchResult)
        #expect(model.round == 7)
    }

    @Test("通しで遊んでも、延長で試合が1局だけ伸びる")
    func extendingFromARealMatchAddsExactlyOneRound() {
        // 負けて最終局を迎える種を探す（CPU が強いほど見つかりやすい）。
        var extended = false
        for seed in UInt64(1)..<60 where !extended {
            let model = HanafudaModel(cpuDelay: .zero, seed: seed)
            model.startMatch(options: HanafudaOptions(rounds: 6, difficulty: .hard))
            var extendedAtRound = 0
            let finished = playOut(model, limit: 900) { m in
                if m.canExtendMatch, m.extendMatchAfterAd(forGame: m.gameSerial) {
                    extendedAtRound = m.round - 1
                }
            }
            #expect(finished)
            if extendedAtRound > 0 {
                extended = true
                #expect(extendedAtRound == 6)
                #expect(model.round == 7)
            }
        }
        #expect(extended, "60種で一度も最終局に負けていなかった（テストの前提が壊れている）")
    }

    // MARK: 局ガード

    @Test("広告のあいだに試合が決着・入れ替わっていたら延長しない")
    func staleAdIsRejected() throws {
        let finished = try modelAtRoundResult(round: 6, humanTotal: 3, cpuTotal: 10)
        let serial = finished.gameSerial
        finished.advanceAfterRound()  // 視聴中に「試合の結果へ」
        #expect(!finished.extendMatchAfterAd(forGame: serial))
        #expect(finished.phase == .matchResult)
        #expect(!finished.hasExtendedMatch)

        let resigned = try modelAtRoundResult(round: 6, humanTotal: 3, cpuTotal: 10)
        let resignedSerial = resigned.gameSerial
        resigned.resign()
        #expect(!resigned.extendMatchAfterAd(forGame: resignedSerial))

        let other = try modelAtRoundResult(round: 6, humanTotal: 3, cpuTotal: 10)
        #expect(!other.extendMatchAfterAd(forGame: other.gameSerial + 1), "控えた局の番号が違う")
        #expect(other.phase == .roundResult)
    }

    @Test("もう一度遊ぶと延長の権利が戻る")
    func restartResetsTheExtension() throws {
        let model = try modelAtRoundResult(round: 6, humanTotal: 0, cpuTotal: 100)
        #expect(model.extendMatchAfterAd(forGame: model.gameSerial))
        #expect(playOut(model))
        model.restartMatch()
        #expect(!model.hasExtendedMatch)
        #expect(model.totalRounds == 6)
    }

    // MARK: 中断と復元

    @Test("延長戦の途中で中断しても、再開後に延長の権利は戻らない")
    func extensionSurvivesSuspendAndResume() throws {
        let store = MemorySnapshotStore()
        let model = try modelAtRoundResult(round: 6, humanTotal: 0, cpuTotal: 100, store: store)
        #expect(model.extendMatchAfterAd(forGame: model.gameSerial))

        let resumed = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 9)
        #expect(resumed.phase == .playing, "延長戦（7局目）の中断データが復元されない")
        #expect(resumed.round == 7)
        #expect(resumed.hasExtendedMatch)
        #expect(resumed.totalRounds == 7)

        // 延長戦を打ち切って結果画面へ進んでも、2回目は出ない。
        var offeredAgain = false
        let finished = playOut(resumed) { m in if m.canExtendMatch { offeredAgain = true } }
        #expect(finished)
        #expect(!offeredAgain)
        #expect(resumed.round == 7)
    }

    @Test("延長の印と局番号が食い違う中断データは弾く")
    func extensionFlagAndRoundMismatchIsRejected() throws {
        let store = MemorySnapshotStore()
        _ = try modelAtRoundResult(round: 6, humanTotal: 0, cpuTotal: 100, store: store)
        let snap = try #require(store.load(HanafudaSnapshot.self, for: HanafudaModel.gameID))
        func with(round: Int, extended: Bool?) -> HanafudaSnapshot {
            HanafudaSnapshot(
                options: snap.options, round: round, dealer: snap.dealer, turn: snap.turn,
                hands: snap.hands, captured: snap.captured, field: snap.field, deck: snap.deck,
                claimed: snap.claimed, koiKoiCounts: snap.koiKoiCounts, totals: snap.totals,
                phase: snap.phase, selection: snap.selection, drawnCard: snap.drawnCard,
                roundResult: snap.roundResult, message: snap.message, hasExtendedMatch: extended
            )
        }
        #expect(HanafudaModel.validate(with(round: 7, extended: nil)) == nil)
        #expect(HanafudaModel.validate(with(round: 7, extended: false)) == nil)
        #expect(HanafudaModel.validate(with(round: 7, extended: true)) != nil)
        #expect(HanafudaModel.validate(with(round: 8, extended: true)) == nil)
        // 延長の印があるのに局が本来の局数以内（延長戦を配る前）は、広告なしで延長戦へ進めてしまうので弾く。
        #expect(HanafudaModel.validate(with(round: 6, extended: true)) == nil)
        #expect(HanafudaModel.validate(with(round: 1, extended: true)) == nil)
        #expect(HanafudaModel.validate(with(round: 6, extended: false)) != nil)
    }

    @Test("延長の鍵が無い旧データは、未使用として復元する")
    func legacySnapshotWithoutTheKeyDecodes() throws {
        let store = MemorySnapshotStore()
        _ = try modelAtRoundResult(round: 6, humanTotal: 3, cpuTotal: 10, store: store)
        let data = try JSONEncoder().encode(
            try #require(store.load(HanafudaSnapshot.self, for: HanafudaModel.gameID))
        )
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "hasExtendedMatch")
        store.inject(try JSONSerialization.data(withJSONObject: json), for: HanafudaModel.gameID)

        let restored = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 3)
        #expect(restored.phase == .roundResult)
        #expect(!restored.hasExtendedMatch)
        #expect(restored.canExtendMatch)
    }

    // MARK: 記録

    @Test("延長した試合は自己ベストには残すが、順位表へは送らない")
    func extendedMatchIsNotSubmittedToTheLeaderboard() throws {
        let log = makeLog("leaderboard")
        let spy = SpyGameCenterService()
        let model = try modelAtRoundResult(
            round: 6, humanTotal: 0, cpuTotal: 100,
            services: { makeServices(store: $0, log: log, gameCenter: spy) }
        )
        #expect(model.extendMatchAfterAd(forGame: model.gameSerial))
        #expect(playOut(model))
        #expect(log.record(gameID: HanafudaModel.gameID)?.plays == 1)
        #expect(spy.scores.isEmpty)
    }

    @Test("延長しなかった試合はこれまでどおり順位表へ送る")
    func unextendedMatchIsStillSubmitted() throws {
        let log = makeLog("leaderboard-control")
        let spy = SpyGameCenterService()
        let model = try modelAtRoundResult(
            round: 6, humanTotal: 3, cpuTotal: 10,
            services: { makeServices(store: $0, log: log, gameCenter: spy) }
        )
        model.advanceAfterRound()
        #expect(model.phase == .matchResult)
        #expect(spy.scores.count == 1)
    }
}
