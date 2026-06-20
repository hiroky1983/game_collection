import Testing
import Foundation
@testable import GameConcentration

// MARK: - Mock

private final class MockSnapshotStore: Core.SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]

    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

import Core
private func makeServices(_ store: MockSnapshotStore) -> GameServices {
    GameServices(snapshots: store, ads: NoopAdService())
}

// MARK: - Helpers

/// cards の中から symbol が異なる2枚の index を返す
private func mismatchPair(in cards: [ConcentrationCard]) -> (Int, Int) {
    let first = 0
    let second = cards.indices.first { i in cards[i].symbol != cards[first].symbol }!
    return (first, second)
}

/// cards の中からペアになる2枚の index を返す
private func matchPair(in cards: [ConcentrationCard]) -> (Int, Int) {
    let first = 0
    let second = cards.indices.first { i in i != first && cards[i].symbol == cards[first].symbol }!
    return (first, second)
}

// MARK: - Tests

@Suite("ConcentrationModel")
@MainActor
struct ConcentrationModelTests {

    // MARK: ミスマッチ後の基本動作

    @Test("ミスマッチ後は自動でターン交代しない（人間は次へボタンが必要）")
    func mismatch_doesNotAutoAdvanceTurn() async {
        let model = ConcentrationModel()
        let (a, b) = mismatchPair(in: model.cards)
        model.tap(index: a)
        model.tap(index: b)

        #expect(!model.mismatchedIndices.isEmpty)
        #expect(model.currentPlayer == .human, "ミスマッチ直後はまだ人間のターンのまま")
    }

    @Test("clearMismatch後にCPUターンへ移行する")
    func clearMismatch_switchesToCPU() async {
        let model = ConcentrationModel()
        let (a, b) = mismatchPair(in: model.cards)
        model.tap(index: a)
        model.tap(index: b)
        let prevTurnID = model.turnID
        model.clearMismatch()

        #expect(model.currentPlayer == .cpu)
        #expect(model.turnID == prevTurnID + 1, "turnID がインクリメントされる（task(id:) 再起動のトリガー）")
        #expect(model.mismatchedIndices.isEmpty)
    }

    @Test("clearMismatch後にカードが裏返る")
    func clearMismatch_flipCardsBack() async {
        let model = ConcentrationModel()
        let (a, b) = mismatchPair(in: model.cards)
        model.tap(index: a)
        model.tap(index: b)
        model.clearMismatch()

        #expect(!model.cards[a].isFaceUp)
        #expect(!model.cards[b].isFaceUp)
    }

    // MARK: 待った

    @Test("canMatta: ミスマッチ中のみtrue")
    func canMatta_onlyDuringMismatch() async {
        let model = ConcentrationModel()
        #expect(!model.canMatta, "初期状態はfalse")

        let (a, b) = mismatchPair(in: model.cards)
        model.tap(index: a)
        model.tap(index: b)
        #expect(model.canMatta, "ミスマッチ後はtrue")

        model.clearMismatch()
        #expect(!model.canMatta, "clearMismatch後はfalse")
    }

    @Test("待った: ターン継続・カードが裏返る")
    func useMatta_keepsTurnAndFlipsCards() async {
        let model = ConcentrationModel()
        let (a, b) = mismatchPair(in: model.cards)
        model.tap(index: a)
        model.tap(index: b)
        model.useMatta()

        #expect(model.currentPlayer == .human, "待った後は引き続き人間のターン")
        #expect(model.mismatchedIndices.isEmpty)
        #expect(!model.cards[a].isFaceUp)
        #expect(!model.cards[b].isFaceUp)
        #expect(model.mattaUsed, "待ったフラグが立つ")
    }

    @Test("待った: ミスマッチ中でないと無効")
    func useMatta_noopWhenNoMismatch() async {
        let model = ConcentrationModel()
        let prevPlayer = model.currentPlayer
        model.useMatta()

        #expect(model.currentPlayer == prevPlayer)
        #expect(!model.mattaUsed)
    }

    // MARK: マッチ

    @Test("マッチ後はターン変わらず連続で選べる")
    func match_doesNotSwitchTurn() async {
        let model = ConcentrationModel()
        let (a, b) = matchPair(in: model.cards)
        model.tap(index: a)
        model.tap(index: b)

        #expect(model.currentPlayer == .human, "マッチ後も人間のターン継続")
        #expect(model.playerScore == 1)
        #expect(model.cards[a].isMatched)
        #expect(model.cards[b].isMatched)
    }

    // MARK: Bug 2: 復元時の宙吊りカード問題

    @Test("復元時: 途中でめくれていたカードは裏返される")
    func restore_flipsDanglingFaceUpCard() async {
        let store = MockSnapshotStore()
        let model1 = ConcentrationModel(services: makeServices(store))

        // 1枚だけめくってページ離脱（firstFlippedIndexが設定された状態を保存）
        model1.tap(index: 0)
        #expect(model1.cards[0].isFaceUp)

        // 新しいモデルで復元（ページ戻りをシミュレート）
        let model2 = ConcentrationModel(services: makeServices(store))

        #expect(!model2.cards[0].isFaceUp, "宙吊りカードは裏返される")
        #expect(model2.firstFlippedIndex == nil)
    }

    @Test("復元時: ミスマッチカードは裏返される")
    func restore_flipsBackMismatchedCards() async {
        let store = MockSnapshotStore()
        let model1 = ConcentrationModel(services: makeServices(store))

        let (a, b) = mismatchPair(in: model1.cards)
        model1.tap(index: a)
        model1.tap(index: b)
        // この時点で mismatchedIndices=[a,b], isFaceUp=true で保存されている

        let model2 = ConcentrationModel(services: makeServices(store))

        #expect(!model2.cards[a].isFaceUp, "ミスマッチカードaは裏返される")
        #expect(!model2.cards[b].isFaceUp, "ミスマッチカードbは裏返される")
        #expect(model2.mismatchedIndices.isEmpty)
        #expect(model2.currentPlayer == .human)
    }

    @Test("復元後: マッチ済みカードは保持される")
    func restore_preservesMatchedCards() async {
        let store = MockSnapshotStore()
        let model1 = ConcentrationModel(services: makeServices(store))

        let (a, b) = matchPair(in: model1.cards)
        model1.tap(index: a)
        model1.tap(index: b)
        #expect(model1.playerScore == 1)

        let model2 = ConcentrationModel(services: makeServices(store))

        #expect(model2.cards[a].isMatched, "マッチ済みカードは復元後も維持")
        #expect(model2.cards[b].isMatched)
        #expect(model2.playerScore == 1)
    }

    @Test("復元時: CPUターンのturnIDは非ゼロ（task(id:) が再起動される）")
    func restore_cpuTurnHasNonZeroTurnID() async {
        let store = MockSnapshotStore()
        let model1 = ConcentrationModel(services: makeServices(store))

        // 人間がミスマッチ → 次へ → CPUターンで保存
        let (a, b) = mismatchPair(in: model1.cards)
        model1.tap(index: a)
        model1.tap(index: b)
        model1.clearMismatch()  // currentPlayer = .cpu, persist()

        let model2 = ConcentrationModel(services: makeServices(store))

        #expect(model2.currentPlayer == .cpu)
        #expect(model2.turnID != 0, "task(id:) を起動するために turnID は 0 以外")
    }

    @Test("復元後: 人間ターンでカードをめくれる")
    func restore_humanCanTapAfterRestore() async {
        let store = MockSnapshotStore()
        let model1 = ConcentrationModel(services: makeServices(store))
        // ペアをマッチして保存（スコアがある状態）
        let (a, b) = matchPair(in: model1.cards)
        model1.tap(index: a)
        model1.tap(index: b)

        let model2 = ConcentrationModel(services: makeServices(store))
        // 残りのカードをめくれるか
        let next = model2.cards.indices.first { !model2.cards[$0].isMatched }!
        model2.tap(index: next)

        #expect(model2.cards[next].isFaceUp, "復元後もカードをめくれる")
    }
}
