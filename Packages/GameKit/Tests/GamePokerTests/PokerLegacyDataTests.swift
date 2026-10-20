import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GamePoker

/// チップ制（v1.1.12 まで）の保存データを読み飛ばす（#2551）。
@Suite("ポーカー: チップ制の頃の保存データ")
@MainActor
struct PokerLegacyDataTests {

    /// v1.1.12 の `PokerSnapshot` が書いていた JSON（2 巡目のベッティング中・ボーナスルール・復活 1 回）。
    nonisolated static let legacySnapshot = Data("""
    {"playerHand":[{"id":0,"suit":0,"rank":11},{"id":1,"suit":1,"rank":11},{"id":2,"suit":2,"rank":8},\
    {"id":3,"suit":3,"rank":4},{"id":4,"suit":0,"rank":2}],\
    "cpuHand":[{"id":5,"suit":1,"rank":14},{"id":6,"suit":3,"rank":10},{"id":7,"suit":2,"rank":7},\
    {"id":8,"suit":3,"rank":5},{"id":9,"suit":0,"rank":3}],\
    "deck":[],"playerChips":100,"cpuChips":100,"pot":40,"phase":"betting2","currentBet":0,\
    "playerBetInRound":0,"cpuBetInRound":0,"cpuFolded":false,"cpuAction":"チェック","rules":"bonus",\
    "hasRevivedThisSession":true,"handStartChips":110,"reviveCount":1}
    """.utf8)

    /// 復活を待つ「次の局待ち」の中断データ（`.idle`・#1104）。
    nonisolated static let legacyIdleSnapshot = Data("""
    {"playerHand":[],"cpuHand":[],"deck":[],"playerChips":150,"cpuChips":100,"pot":0,"phase":"idle",\
    "currentBet":0,"playerBetInRound":0,"cpuBetInRound":0,"cpuFolded":false,"cpuAction":"","rules":"standard",\
    "hasRevivedThisSession":true,"reviveCount":1}
    """.utf8)

    @Test("旧い中断データは読み飛ばして消し、新しい 10 回勝負の前から始まる（落ちない）",
          arguments: [legacySnapshot, legacyIdleSnapshot])
    func legacySnapshotIsSkipped(data: Data) {
        let store = MemorySnapshotStore()
        store.inject(data, for: "poker")
        #expect(!PokerModule().hasResumableSnapshot(in: store), "ハブの「続きから」に出さない")
        let model = PokerModel(services: GameServices(snapshots: store, ads: PokerStubAdService()))
        #expect(model.phase == .idle)
        #expect(model.round == 0)
        #expect(model.playerPoints == 0)
        #expect(model.playerHand.isEmpty)
        #expect(!store.exists(for: "poker"), "読めない中断データは消す（開始シートが出ずに空の卓になるのを防ぐ）")
        // そのまま新しい勝負を始められる。
        model.startGame()
        #expect(model.phase == .exchange)
        #expect(model.round == 1)
    }

    @Test("壊れた中断データでも落ちない")
    func brokenSnapshotIsSkipped() {
        let store = MemorySnapshotStore()
        store.inject(Data("{\"format\":2,\"phase\":\"drawn\"}".utf8), for: "poker")
        let model = PokerModel(services: GameServices(snapshots: store, ads: PokerStubAdService()))
        #expect(model.phase == .idle)
        #expect(!store.exists(for: "poker"))
    }

    @Test("版が違う中断データは読めても使わない")
    func futureFormatIsSkipped() throws {
        var snap = pokerSnapshot(player: PokerHands.fullHouse, cpu: PokerHands.straight)
        snap.format = 99
        let store = MemorySnapshotStore()
        try store.save(snap, for: "poker")
        let model = PokerModel(services: GameServices(snapshots: store, ads: PokerStubAdService()))
        #expect(model.phase == .idle)
        #expect(!PokerModule().hasResumableSnapshot(in: store))
    }

    @Test("チップ制の頃の記録（poker・poker#bonus）は読み飛ばし、新しい記録だけが残る")
    func legacyRecordsAreDropped() throws {
        let suite = "poker-legacy-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // 旧版が保存した記録（持ち点の枚数が自己ベスト）。
        let first = PlayLog(defaults: defaults)
        _ = first.recordResult(gameID: "poker", outcome: .win, score: GameScore(metric: .points, points: 1_250))
        _ = first.recordResult(gameID: "poker", outcome: .win,
                               score: GameScore(metric: .points, points: 3_000, variant: "bonus", variantLabel: "ボーナスルール"))
        _ = first.recordResult(gameID: "poker", outcome: .win,
                               score: GameScore(metric: .points, points: 34, variant: PokerModel.recordVariant,
                                                variantLabel: "10回勝負"))
        _ = first.recordResult(gameID: "2048", outcome: .loss, score: GameScore(metric: .points, points: 512))

        let reloaded = PlayLog(defaults: defaults)
        #expect(reloaded.record(gameID: "poker") == nil)
        #expect(reloaded.record(gameID: "poker", variant: "bonus") == nil)
        #expect(reloaded.record(gameID: "poker", variant: PokerModel.recordVariant)?.bestPoints == 34)
        #expect(reloaded.records(gameID: "poker").count == 1)
        #expect(reloaded.summaryLine(gameID: "poker") == "ベスト 34", "ハブの 1 行は新しい記録")
        #expect(reloaded.record(gameID: "2048")?.bestPoints == 512, "ほかのゲームの記録には触れない")
    }

    @Test("新しい記録の区分名は日本語・英語とも引ける")
    func recordVariantLabel() {
        let key = "poker#\(PokerModel.recordVariant)"
        #expect(RecordVariantLabels.label(recordKey: key, language: .japanese) == "10回勝負")
        #expect(RecordVariantLabels.label(recordKey: key, language: .english) == "10 Rounds")
    }
}
