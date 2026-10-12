import Testing
import Foundation
import Core
@testable import GameSolitaire
import CoreTestSupport

/// 送信内容をそのまま溜めるスパイ。Apple の GameKit にもネットワークにも触れない。
@MainActor
private final class SpyGameCenterService: GameCenterService {
    private(set) var scores: [GameCenterScore] = []
    func submit(_ score: GameCenterScore) { scores.append(score) }
    func report(_ achievements: [GameCenterAchievement], completion: @escaping @MainActor (Bool) -> Void) {
        completion(true)
    }
}

/// 勝ち筋が無く指せる手も無い盤（ルートに A が無く、組札に何も載らない）。
private func hopelessBoard() -> SolitaireBoard {
    let piles: [SolitairePile] = [
        SolitairePile(faceUp: [SolitaireCard(.spade, 13)]),
        SolitairePile(faceUp: [SolitaireCard(.heart, 13)]),
        SolitairePile(faceUp: [SolitaireCard(.diamond, 13)]),
        SolitairePile(faceUp: [SolitaireCard(.club, 13)]),
        SolitairePile(faceUp: [SolitaireCard(.spade, 2)]),
        SolitairePile(faceUp: [SolitaireCard(.heart, 2)]),
        SolitairePile(faceUp: [SolitaireCard(.diamond, 2)]),
    ]
    return SolitaireBoard(tableau: piles)
}

/// 純粋な「次の一手」（#2025）。
@Suite("ソリティア ヒントの探索（#2025）")
struct SolitaireHintSearchTests {

    @Test("ヒントの手だけを打ち続けて、検証済みの配りを勝ち切れる")
    func playingOnlyHintsWins() throws {
        for seed in SolitaireDealer.verifiedSeeds.prefix(2) {
            var board = SolitaireDealer.deal(seed: seed)
            var trail: SolitaireHintTrail?
            var steps = 0
            while !board.isWon {
                steps += 1
                try #require(steps <= 3000, "種 \(seed): 3000 手でも勝てない（往復している）")
                // Model と同じ手順: 筋の続きに着いていればそれを、無ければ解き直す。
                let answer = try #require(
                    trail?.answer(at: board) ?? SolitaireHint.findPlan(in: board),
                    "種 \(seed): 読みが降ろされた")
                trail = SolitaireHintTrail.after(answer, from: board)
                guard case .move(let move) = answer.result else {
                    Issue.record("種 \(seed): \(steps) 手目で勝てないと言われた")
                    break
                }
                let applied = board.apply(move)
                #expect(applied, "種 \(seed): 合法でない手を示した \(move)")
            }
            #expect(board.isWon, "種 \(seed)")
        }
    }

    @Test("探索を尽くしても勝ち筋が無い盤は勝てないと言う")
    func hopelessWhenExhausted() {
        let board = hopelessBoard()
        #expect(board.isDeadEnd, "前提: 指せる手が無い")
        #expect(SolitaireHint.find(in: board) == .hopeless)
    }

    @Test("上限で打ち切られたら、勝てないとは言わず見込みの良い手を示す")
    func fallbackWhenSearchHitsTheLimit() throws {
        let board = SolitaireDealer.deal(seed: SolitaireDealer.verifiedSeeds[0])
        let result = try #require(SolitaireHint.find(in: board, maxStates: 1))
        guard case .move(let move) = result else {
            Issue.record("打ち切りで勝てないと言った")
            return
        }
        #expect(board.isLegal(move))
    }

    @Test("見込みの良い手は、組札へ送れる札を最優先する")
    func promisingPrefersFoundation() {
        var piles = [SolitairePile](repeating: SolitairePile(), count: 7)
        piles[0] = SolitairePile(faceDown: [SolitaireCard(.club, 9)], faceUp: [SolitaireCard(.heart, 1)])
        piles[1] = SolitairePile(faceUp: [SolitaireCard(.spade, 13)])
        let board = SolitaireBoard(tableau: piles, stock: [SolitaireCard(.club, 4)])
        #expect(SolitaireHint.promisingMove(in: board) == .tableauToFoundation(pile: 0))
    }

    @Test("組札へ送れないなら、裏札をめくれる移動を山めくりより優先する")
    func promisingPrefersFlipping() {
        // 列0: 裏 1 枚 + 表 6♥。列1 の表 7♠ の上へ動かすと裏札がめくれる。
        var piles = [SolitairePile](repeating: SolitairePile(), count: 7)
        piles[0] = SolitairePile(faceDown: [SolitaireCard(.club, 9)], faceUp: [SolitaireCard(.heart, 6)])
        piles[1] = SolitairePile(faceUp: [SolitaireCard(.spade, 7)])
        let board = SolitaireBoard(tableau: piles, stock: [SolitaireCard(.club, 4)])
        #expect(SolitaireHint.promisingMove(in: board) == .tableauToTableau(from: 0, cardIndex: 0, to: 1))
    }

    @Test("動かす手が無ければ山札をめくる")
    func promisingDrawsWhenNothingElse() {
        var piles = [SolitairePile](repeating: SolitairePile(), count: 7)
        piles[0] = SolitairePile(faceUp: [SolitaireCard(.spade, 5)])
        let board = SolitaireBoard(tableau: piles, stock: [SolitaireCard(.club, 4)])
        #expect(SolitaireHint.promisingMove(in: board) == .draw)
    }

    @Test("取り消されたら nil（印を出さない）")
    func cancelledReturnsNil() {
        let board = SolitaireDealer.deal(seed: SolitaireDealer.verifiedSeeds[0])
        #expect(SolitaireHint.find(in: board, isCancelled: { true }) == nil)
    }
}

/// Model 側（回数・広告・順位表・中断復元）。
@Suite("ソリティア ヒントのモデル（#2025）")
@MainActor
struct SolitaireHintModelTests {

    private struct Fixture {
        let model: SolitaireModel
        let store: MemorySnapshotStore
        let services: GameServices
        let center: SpyGameCenterService
    }

    private func makeFixture() -> Fixture {
        let store = MemorySnapshotStore()
        let name = "asobiba.solitaire.hint.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let center = SpyGameCenterService()
        let services = GameServices(
            snapshots: store, ads: NoopAdService(), playLog: PlayLog(defaults: defaults),
            gameCenter: GameCenterReporter(service: center, allowedGameIDs: ["solitaire"], isAvailable: { true })
        )
        let model = SolitaireModel(services: services, seed: SolitaireDealer.verifiedSeeds[0])
        return Fixture(model: model, store: store, services: services, center: center)
    }

    /// 盤を 1 手動かす（山めくり）。
    private func playAnyMove(_ model: SolitaireModel) {
        model.tapStock()
    }

    @Test("最初の 1 手を示す。動かすのはプレイヤーで、盤は変わらない")
    func showsTheFirstMoveWithoutMovingIt() async throws {
        let f = makeFixture()
        let before = f.model.board
        await f.model.requestHint()

        let move = try #require(f.model.hintMove)
        #expect(f.model.board == before, "示すだけで動かさない")
        #expect(f.model.moveCount == 0)
        #expect(before.isLegal(move))
        #expect(f.model.hints.used == 1)
        #expect(!f.model.isHintThinking)
    }

    @Test("札を動かすと印は消える")
    func hintClearsWhenTheBoardMoves() async {
        let f = makeFixture()
        await f.model.requestHint()
        #expect(f.model.hintMove != nil)
        playAnyMove(f.model)
        #expect(f.model.hintMove == nil)
    }

    @Test("勝てない盤では知らせるだけで回数を減らさない")
    func hopelessDoesNotConsume() async {
        let f = makeFixture()
        f.model.replaceBoardForTesting(hopelessBoard())
        await f.model.requestHint()
        #expect(f.model.showsHintHopeless)
        #expect(f.model.hintMove == nil)
        #expect(f.model.hints.used == 0)
        f.model.dismissHintHopeless()
        #expect(!f.model.showsHintHopeless)
    }

    @Test("探索中に札を動かしたら印を出さず、回数も減らさない")
    func movingDuringSearchDiscardsTheResult() async {
        let f = makeFixture()
        let model = f.model
        let play = playAnyMove
        model.hintSearchDidFinishForTesting = { play(model) }
        await model.requestHint()
        #expect(model.moveCount + (model.board.waste.isEmpty ? 0 : 1) >= 1, "前提: 読みの最中に 1 手指した")
        #expect(model.hintMove == nil)
        #expect(model.hints.used == 0)
        #expect(!model.isHintThinking)
    }

    @Test("広告の経路で、読みの最中に盤が動いて結果が捨てられても「広告を見ているあいだに」とは出さない（#2125）")
    func movingDuringAdSearchIsSupersededNotUnavailable() async {
        let f = makeFixture()
        let model = f.model
        for _ in 0..<3 { await model.requestHint() }
        #expect(model.needsAdForHint, "前提: 無料を使い切った")
        let play = playAnyMove
        model.hintSearchDidFinishForTesting = { play(model) }
        #expect(await model.requestAdHint() == .superseded, "広告を出す前に捨てられたので、適用できなかった知らせは出さない")
        #expect(model.hints.used == 3)
        #expect(!model.isHintThinking)
    }

    @Test("広告の経路でも、読みの間は広告を出す前の合図（readDidFinish）が来ていない")
    func readDidFinishComesAfterTheRead() async {
        let f = makeFixture()
        let model = f.model
        for _ in 0..<3 { await model.requestHint() }
        var order: [String] = []
        model.hintSearchDidFinishForTesting = { order.append("read") }
        _ = await model.requestAdHint(readDidFinish: { order.append("finish") })
        #expect(order == ["read", "finish"], "読み終えてから広告へ進む")
    }

    @Test("無料 3 回 → 広告で +1 を最大 5 回 → 使い切り")
    func freeThenAdsThenExhausted() async {
        let f = makeFixture()
        let model = f.model
        #expect(model.hints.freeRemaining == 3)
        #expect(await model.requestAdHint() == .unavailable, "無料が残っているうちは広告の経路で消費しない")

        for _ in 0..<3 { await model.requestHint() }
        #expect(model.hints.used == 3)
        #expect(model.needsAdForHint, "無料を使い切ったら次は広告")
        await model.requestHint()
        #expect(model.hints.used == 3, "広告無しでは出ない")

        for n in 1...5 {
            #expect(await model.requestAdHint() == .granted, "広告 \(n) 本目")
        }
        #expect(model.hints.isExhausted)
        #expect(!model.canUseHint)
        #expect(await model.requestAdHint() == .unavailable, "6 本目は出ない")
        #expect(model.hints.used == 8)
    }

    @Test("勝てない盤では広告を流さず回数も減らさない")
    func hopelessDoesNotShowAnAd() async {
        let f = makeFixture()
        for _ in 0..<3 { await f.model.requestHint() }
        f.model.replaceBoardForTesting(hopelessBoard())
        #expect(await f.model.requestAdHint() == .granted)
        #expect(f.model.showsHintHopeless)
        #expect(f.model.hints.used == 3)
    }

    @Test("戻してもヒントの回数は戻らない")
    func undoDoesNotRestoreHints() async {
        let f = makeFixture()
        playAnyMove(f.model)
        await f.model.requestHint()
        f.model.undo()
        #expect(f.model.hints.used == 1)
    }

    @Test("使った回数は中断データに残り、再開で戻らない。旧形式は 0 回")
    func usedCountSurvivesRestart() async throws {
        let f = makeFixture()
        playAnyMove(f.model)
        await f.model.requestHint()
        f.model.pauseTimer()

        let restored = SolitaireModel(services: f.services)
        #expect(restored.hints.used == 1)

        let data = try #require(f.store.rawData(for: "solitaire"))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["hintsUsed"] = nil
        let legacy = MemorySnapshotStore()
        legacy.inject(try JSONSerialization.data(withJSONObject: json), for: "solitaire")
        let services = GameServices(snapshots: legacy, ads: NoopAdService())
        #expect(SolitaireModel(services: services).hints.used == 0)
    }

    @Test("新規配札で回数と印が戻る")
    func newGameResetsHints() async {
        let f = makeFixture()
        await f.model.requestHint()
        f.model.newGame()
        #expect(f.model.hints.used == 0)
        #expect(f.model.hintMove == nil)
    }

    @Test("ヒントを使った局のクリアは順位表に送らない（使わなければ送る）")
    func usedHintIsNotSubmittedToLeaderboard() async {
        let control = makeFixture()
        control.model.tick()   // 0 秒のクリアは順位表に送らない
        control.model.replaceBoardForTesting(Self.almostWon())
        control.model.tapPile(0)
        control.model.tapFoundation(.spade)
        #expect(control.model.phase == .won)
        #expect(control.center.scores.count == 1, "前提: 使わなければ送られる")

        let used = makeFixture()
        await used.model.requestHint()
        used.model.tick()
        used.model.replaceBoardForTesting(Self.almostWon())
        used.model.tapPile(0)
        used.model.tapFoundation(.spade)
        #expect(used.model.phase == .won)
        #expect(used.center.scores.isEmpty, "ヒントを使った局のタイムを順位表に混ぜない")
        #expect(used.model.recordResult != nil, "自己ベストの表示は従来どおり出る")
    }

    /// あと K♠ を送るだけで勝つ盤。
    private static func almostWon() -> SolitaireBoard {
        var piles = [SolitairePile](repeating: SolitairePile(), count: 7)
        piles[0] = SolitairePile(faceUp: [SolitaireCard(.spade, 13)])
        return SolitaireBoard(tableau: piles, foundations: [12, 13, 13, 13])
    }
}
