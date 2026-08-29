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

/// 中断データを任意の中身で置くためのスタブ（#218）。
///
/// 復元側の `ConcentrationSnapshot` は `private` で外から作れないため、**同じ鍵を持つ**
/// 別の構造体を保存して JSON を作る（デコードは通り、健全性チェックだけが落ちる）。
/// `AnalyticsTests` の `BrokenConcentrationSnapshot` と同じ手口。
private struct StubConcentrationSnapshot: Codable {
    var symbols: [String]
    var isFaceUp: [Bool]
    var isMatched: [Bool]
    var currentPlayer: Int = 0
    var playerScore: Int = 0
    var cpuScore: Int = 0
    var pairCount: Int = ConcentrationPairCount.small.rawValue
    var cpuLevel: Int = ConcentrationCPULevel.normal.rawValue
    var mattaUsed: Bool = false

    /// 8ペア16枚の正しい盤面。`symbols` だけ差し替えれば壊れた並びを作れる。
    static func healthy() -> StubConcentrationSnapshot {
        let pairs = ConcentrationPairCount.small.rawValue
        let symbols = (0..<pairs).flatMap { ["s\($0)", "s\($0)"] }
        return StubConcentrationSnapshot(
            symbols: symbols,
            isFaceUp: Array(repeating: false, count: symbols.count),
            isMatched: Array(repeating: false, count: symbols.count)
        )
    }
}

/// CPU の手を固定するテスト用 AI。`choices` を使い切ったら通常のロジックに戻る。
private final class ScriptedConcentrationAI: ConcentrationAI {
    var choices: [Int] = []

    init() { super.init(accuracy: 0) }

    override func chooseCard(cards: [ConcentrationCard], firstFlipped: Int?) -> Int {
        guard !choices.isEmpty else {
            return super.chooseCard(cards: cards, firstFlipped: firstFlipped)
        }
        return choices.removeFirst()
    }
}

// MARK: - Tests

/// 自動ターン交代の待ち時間。テストの実行時間を縮めるため短くする（#137）
private let testAutoClearDelay: UInt64 = 40_000_000  // 40ms

/// 予約された自動ターン交代の完了を待つ（#151）。
///
/// 以前は `Task.sleep(240ms)` で「起きているはず」の時間を待っていたが、テストの並列実行で
/// MainActor が混むとサスペンションからの復帰が桁違いに遅れ（実測: 1ms の sleep の復帰に 3.5 秒）、
/// 猶予を超えてフレークした。時間ではなく**タスクの完了**で待ち合わせるため、待ち時間を
/// いくら延ばしても取り切れない不定性が無くなる。予約が無ければ即座に戻る。
@MainActor
private func awaitAutoClear(_ model: ConcentrationModel) async {
    await model.pendingAutoClear?.value
}

@Suite("ConcentrationModel")
@MainActor
struct ConcentrationModelTests {

    // MARK: ミスマッチ後の基本動作（#137: 自動でターンが進む）

    @Test("ミスマッチ直後はまだ人間のターン（待ったを出す猶予がある）")
    func mismatch_keepsTurnDuringGrace() async {
        let model = ConcentrationModel(services: nil, autoClearDelay: testAutoClearDelay)
        let (a, b) = mismatchPair(in: model.cards)
        model.tap(index: a)
        model.tap(index: b)

        #expect(!model.mismatchedIndices.isEmpty)
        #expect(model.currentPlayer == .human, "猶予中はまだ人間のターンのまま")
        #expect(model.canMatta, "猶予中は待ったが使える")
    }

    @Test("ミスマッチ後は「次へ」を押さなくても自動で裏返りターンが CPU に移る")
    func mismatch_autoAdvancesTurn() async {
        let model = ConcentrationModel(services: nil, autoClearDelay: testAutoClearDelay)
        let (a, b) = mismatchPair(in: model.cards)
        let prevTurnID = model.turnID
        model.tap(index: a)
        model.tap(index: b)

        await awaitAutoClear(model)

        #expect(model.mismatchedIndices.isEmpty, "自動でミスマッチが解除される")
        #expect(!model.cards[a].isFaceUp, "自動でカードが裏返る")
        #expect(!model.cards[b].isFaceUp)
        #expect(model.currentPlayer == .cpu, "自動で CPU のターンに移る")
        #expect(model.turnID == prevTurnID + 1, "turnID が1回だけ進む（二重 clearMismatch でない）")
    }

    @Test("マッチしたときは自動ターン交代しない（連続ターンを壊さない）")
    func match_doesNotScheduleAutoClear() async {
        let model = ConcentrationModel(services: nil, autoClearDelay: testAutoClearDelay)
        let (a, b) = matchPair(in: model.cards)
        model.tap(index: a)
        model.tap(index: b)

        #expect(model.pendingAutoClear == nil, "マッチでは自動ターン交代を予約しない")
        #expect(model.currentPlayer == .human, "マッチ後は人間のターンが続く")
        #expect(model.playerScore == 1)
    }

    @Test("待ったを使ったら自動ターン交代は起きない")
    func useMatta_cancelsAutoClear() async {
        let model = ConcentrationModel(services: nil, autoClearDelay: testAutoClearDelay)
        let (a, b) = mismatchPair(in: model.cards)
        model.tap(index: a)
        model.tap(index: b)
        let pending = model.pendingAutoClear
        #expect(pending != nil, "前提: 待ったを使う前は自動ターン交代が予約されている")
        model.useMatta()

        await pending?.value   // 取り消された予約が「何もしないまま終わる」ことまで見届ける

        #expect(model.pendingAutoClear == nil, "待ったで予約が取り消される")
        #expect(model.currentPlayer == .human, "待った後にターンが奪われない")
        #expect(model.mismatchedIndices.isEmpty)
    }

    @Test("pauseAutoTurn 中は自動交代せず、resumeAutoTurn で再開する")
    func pauseAndResumeAutoTurn() async {
        let model = ConcentrationModel(services: nil, autoClearDelay: testAutoClearDelay)
        let (a, b) = mismatchPair(in: model.cards)
        model.tap(index: a)
        model.tap(index: b)
        let paused = model.pendingAutoClear
        #expect(paused != nil, "前提: 一時停止する前は自動ターン交代が予約されている")
        model.pauseAutoTurn()   // 「待った」確認ダイアログを開いた状態

        await paused?.value
        #expect(model.pendingAutoClear == nil, "確認中は自動ターン交代の予約が無い")
        #expect(model.currentPlayer == .human, "確認中は自動でターンが移らない")
        #expect(model.canMatta, "確認中も待ったは有効なまま")

        model.resumeAutoTurn()  // ダイアログをキャンセル
        await awaitAutoClear(model)
        #expect(model.currentPlayer == .cpu, "キャンセル後は自動交代が再開する")
    }

    @Test("resumeAutoTurn: ミスマッチが無ければ何もしない")
    func resumeAutoTurn_noopWithoutMismatch() async {
        let model = ConcentrationModel(services: nil, autoClearDelay: testAutoClearDelay)
        model.resumeAutoTurn()

        #expect(model.pendingAutoClear == nil, "ミスマッチが無ければ予約もしない")
        #expect(model.currentPlayer == .human)
        #expect(model.turnID == 0, "ターンが進まない")
    }

    @Test("新規ゲームは待機中の自動ターン交代を巻き込まない")
    func newGame_cancelsPendingAutoClear() async {
        let model = ConcentrationModel(services: nil, autoClearDelay: testAutoClearDelay)
        let (a, b) = mismatchPair(in: model.cards)
        model.tap(index: a)
        model.tap(index: b)
        let pending = model.pendingAutoClear
        #expect(pending != nil, "前提: 新規ゲームを始める前は自動ターン交代が予約されている")
        model.newGame(pairCount: .small, cpuLevel: .weak)

        await pending?.value   // 旧対局の予約が新しい盤面に手を出さないことまで見届ける

        #expect(model.pendingAutoClear == nil, "新規ゲームで予約が取り消される")
        #expect(model.currentPlayer == .human, "新しい対局は人間の先手のまま")
        #expect(model.turnID == 0)
        #expect(model.cards.allSatisfy { !$0.isFaceUp })
    }

    // MARK: Bug 1 回帰: CPU ターンが詰まらない

    @Test("CPU がミスマッチしても二重クリアで詰まらず人間のターンに戻る")
    func cpuMismatch_returnsTurnToHuman() async {
        // CPU の手を固定する。実 AI は選択がランダムで、マッチが続いて決着してしまうと
        // 「CPU のミスマッチ」を一度も通らないままテストが緑になる（PR #146 指摘）。
        let scripted = ScriptedConcentrationAI()
        let model = ConcentrationModel(services: nil,
                                       autoClearDelay: testAutoClearDelay,
                                       aiFactory: { _ in scripted })

        let (a, b) = mismatchPair(in: model.cards)
        model.tap(index: a)
        model.tap(index: b)
        await awaitAutoClear(model)
        #expect(model.currentPlayer == .cpu, "人間のミスマッチで CPU に手番が渡る")

        // CPU にはシンボルの異なる2枚を必ず引かせる
        let (c, d) = mismatchPair(in: model.cards)
        scripted.choices = [c, d]
        let turnIDAtCPUStart = model.turnID
        let cpuScoreBefore = model.cpuScore

        await model.performCPUMoveIfNeeded()

        #expect(model.cards[c].symbol != model.cards[d].symbol, "CPU が引いた2枚はミスマッチ")
        #expect(model.cpuScore == cpuScoreBefore, "ミスマッチなので CPU は得点しない")
        #expect(!model.isGameOver, "ミスマッチなので決着しない")
        #expect(!model.isThinking, "CPU ターン終了時に isThinking が残らない")
        #expect(model.currentPlayer == .human, "人間のターンに戻る（詰まらない）")
        #expect(model.turnID == turnIDAtCPUStart + 1, "CPU のミスマッチで turnID がちょうど1回だけ進む")

        // CPU が自前でクリアした後に人間側の自動クリアが走ると turnID が余計に進む（Bug 1）。
        // 予約そのものが残っていないことを見れば、あとから走る余地が無いと言い切れる
        // （以前はここで実時間を待って「起きなかったこと」を確かめていた）。
        #expect(model.pendingAutoClear == nil, "CPU の経路からは自動ターン交代を予約しない")
        #expect(model.currentPlayer == .human, "CPU の後始末が人間のターンを奪わない")
        #expect(model.turnID == turnIDAtCPUStart + 1, "余計な clearMismatch が走っていない")
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

    // MARK: 中断データの健全性検証（#218）

    /// スタブの中断データを置いて復元させ、できあがったモデルを返す。
    private func restored(from stub: StubConcentrationSnapshot) -> ConcentrationModel {
        let store = MockSnapshotStore()
        try? store.save(stub, for: "concentration")
        return ConcentrationModel(services: makeServices(store))
    }

    /// 盤面のどのカードにも相方がいることを確かめる（= 最後まで揃えられる盤面）。
    private func everyCardHasItsPair(_ model: ConcentrationModel) -> Bool {
        let occurrences = model.cards.reduce(into: [String: Int]()) { $0[$1.symbol, default: 0] += 1 }
        return occurrences.values.allSatisfy { $0 == 2 }
    }

    @Test("復元時: 配列長は揃っていてもシンボルが対を成さない中断データはフォールバックする")
    func restore_rejectsSnapshotWhoseSymbolsDoNotPairUp() {
        var stub = StubConcentrationSnapshot.healthy()
        // 長さ・枚数は正しいまま、全カードのシンボルを別物にする（対が1組も無い）
        stub.symbols = stub.symbols.indices.map { "u\($0)" }

        let model = restored(from: stub)

        #expect(model.cards.count == ConcentrationPairCount.medium.rawValue * 2,
                "既定（12ペア）の新しい盤へフォールバックする")
        #expect(everyCardHasItsPair(model), "復元された盤は最後まで揃えられる")
    }

    @Test("復元時: 一部のシンボルだけ対を欠く中断データもフォールバックする")
    func restore_rejectsSnapshotWithPartiallyBrokenPairs() {
        var stub = StubConcentrationSnapshot.healthy()
        // 1枚だけ別のシンボルに差し替える → その2枚が孤立して揃わなくなる
        stub.symbols[0] = "lonely"

        let model = restored(from: stub)

        #expect(model.cards.count == ConcentrationPairCount.medium.rawValue * 2)
        #expect(everyCardHasItsPair(model))
    }

    @Test("復元時: pairCount が列挙値に無い中断データはフォールバックする")
    func restore_rejectsSnapshotWithUnknownPairCount() {
        var stub = StubConcentrationSnapshot.healthy()
        stub.pairCount = 7   // 8 / 12 / 18 のいずれでもない

        let model = restored(from: stub)

        #expect(model.cards.count == ConcentrationPairCount.medium.rawValue * 2)
    }

    @Test("復元時: cpuLevel が列挙値に無い中断データはフォールバックする")
    func restore_rejectsSnapshotWithUnknownCPULevel() {
        var stub = StubConcentrationSnapshot.healthy()
        stub.cpuLevel = 99

        let model = restored(from: stub)

        #expect(model.cards.count == ConcentrationPairCount.medium.rawValue * 2)
    }

    @Test("復元時: カード枚数が pairCount の2倍でない中断データはフォールバックする")
    func restore_rejectsSnapshotWhoseCardCountMismatchesPairCount() {
        var stub = StubConcentrationSnapshot.healthy()
        stub.pairCount = ConcentrationPairCount.large.rawValue  // 18ペア = 36枚のはずが16枚

        let model = restored(from: stub)

        #expect(model.cards.count == ConcentrationPairCount.medium.rawValue * 2)
    }

    @Test("復元時: 対の揃った中断データはそのまま復元される（検証強化の巻き添えが無い）")
    func restore_acceptsHealthySnapshot() {
        var stub = StubConcentrationSnapshot.healthy()
        stub.playerScore = 3
        stub.cpuScore = 1

        let model = restored(from: stub)

        #expect(model.cards.count == ConcentrationPairCount.small.rawValue * 2, "8ペア16枚がそのまま戻る")
        #expect(model.pairCount == .small)
        #expect(model.playerScore == 3)
        #expect(model.cpuScore == 1)
    }
}
