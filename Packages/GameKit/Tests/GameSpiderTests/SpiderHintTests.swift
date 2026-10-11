import Testing
import Foundation
import Core
@testable import GameSpider
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

private func card(_ suit: SpiderSuit, _ rank: Int, id: Int) -> SpiderCard {
    SpiderCard(id: id, suit: suit, rank: rank)
}

/// 10 列のうち指定した列だけを埋め、残りは 1 枚ずつ重ならない札で埋める盤（空列を作らない）。
private func board(_ columns: [[SpiderCard]], faceDown: [Int] = [], stock: [[SpiderCard]] = []) -> SpiderBoard {
    var piles: [SpiderPile] = []
    for (index, cards) in columns.enumerated() {
        piles.append(SpiderPile(cards: cards, faceDownCount: index < faceDown.count ? faceDown[index] : 0))
    }
    return SpiderBoard(piles: piles, stock: stock)
}

/// 純粋な「次の一手」（#2025）。
@Suite("スパイダー ヒントの探索（#2025）")
struct SpiderHintSearchTests {

    @Test("ヒントの手だけを打ち続けて、検証済みの 1 スートの配りを勝ち切れる")
    func playingOnlyHintsWins() throws {
        for seed in SpiderDealer.verifiedSeeds(for: .one).prefix(2) {
            var board = SpiderDealer.deal(seed: seed, suits: .one)
            var trail: SpiderHintTrail?
            var steps = 0
            while !board.isWon {
                steps += 1
                try #require(steps <= 3000, "種 \(seed): 3000 手でも勝てない（往復している）")
                // Model と同じ手順: 筋の続きに着いていればそれを、無ければ解き直す。
                let answer = try #require(
                    trail?.answer(at: board) ?? SpiderHint.findPlan(in: board, suits: .one),
                    "種 \(seed): 読みが降ろされた")
                trail = SpiderHintTrail.after(answer, from: board)
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

    @Test("探索を尽くしても勝ち筋が無い盤（指せる手が無い）は勝てないと言う")
    func hopelessWhenExhausted() {
        // 10 列とも一番上が K（8 本）か A。K の上に置ける札は無く、山札も無い。
        var columns: [[SpiderCard]] = []
        for i in 0..<8 { columns.append([card(.spade, 13, id: i)]) }
        columns.append([card(.spade, 1, id: 20)])
        columns.append([card(.spade, 1, id: 21)])
        let b = board(columns)
        #expect(b.isDeadEnd, "前提: 指せる手が無い")
        #expect(SpiderHint.find(in: b, suits: .one) == .hopeless)
    }

    @Test("上限で打ち切られたら、勝てないとは言わず見込みの良い手を示す")
    func fallbackWhenSearchHitsTheLimit() throws {
        let b = SpiderDealer.deal(seed: SpiderDealer.verifiedSeeds(for: .one)[0], suits: .one)
        let result = try #require(SpiderHint.find(in: b, suits: .one, maxStates: 1))
        guard case .move(let move) = result else {
            Issue.record("打ち切りで勝てないと言った")
            return
        }
        #expect(b.isLegal(move))
    }

    @Test("見込みの良い手は、組を完成させる手を最優先する")
    func promisingPrefersCompletingARun() {
        // 列0 に K〜2、列1 に A。A を列0 へ置くと組が完成する。
        var column0: [SpiderCard] = []
        for rank in stride(from: 13, through: 2, by: -1) { column0.append(card(.spade, rank, id: rank)) }
        var columns = [column0, [card(.spade, 1, id: 40)]]
        for i in 0..<8 { columns.append([card(.spade, 13, id: 50 + i)]) }
        let b = board(columns)
        #expect(SpiderHint.promisingMove(in: b) == .move(from: 1, cardIndex: 0, to: 0))
    }

    @Test("組が作れないなら、伏せ札をめくれる手を優先する")
    func promisingPrefersFlippingAFaceDownCard() {
        // 列0 は伏せ札 1 枚 + 表の 5。列1 の 6 へ動かすと下の伏せ札がめくれる。列2 の 4 の上へ置く手（めくらない）もある。
        var columns = [
            [card(.spade, 9, id: 1), card(.spade, 5, id: 2)],
            [card(.heart, 6, id: 3)],
            [card(.heart, 6, id: 4)],
        ]
        for i in 0..<7 { columns.append([card(.spade, 13, id: 50 + i)]) }
        let b = board(columns, faceDown: [1])
        let move = SpiderHint.promisingMove(in: b)
        guard case .move(let from, _, _) = move else {
            Issue.record("手が示されない"); return
        }
        #expect(from == 0)
    }

    @Test("動かす手が無く山札が配れるなら配る")
    func promisingDealsWhenNothingElse() {
        var columns: [[SpiderCard]] = []
        for i in 0..<10 { columns.append([card(.spade, 13, id: i)]) }
        let stock = [(0..<10).map { card(.spade, 12, id: 60 + $0) }]
        // K の上には置けるが 12（K の上に 12 は置ける）…動かす手があるので、列を全部 A にして動かせなくする。
        columns = (0..<10).map { [card(.spade, 1, id: $0)] }
        let b = board(columns, stock: stock)
        #expect(SpiderHint.promisingMove(in: b) == .deal)
    }

    @Test("取り消されたら nil（印を出さない）")
    func cancelledReturnsNil() {
        let b = SpiderDealer.deal(seed: SpiderDealer.verifiedSeeds(for: .one)[0], suits: .one)
        #expect(SpiderHint.find(in: b, suits: .one, isCancelled: { true }) == nil)
    }
}

/// Model 側（回数・広告・順位表・中断復元）。
@Suite("スパイダー ヒントのモデル（#2025）")
@MainActor
struct SpiderHintModelTests {

    private struct Fixture {
        let model: SpiderModel
        let store: MemorySnapshotStore
        let services: GameServices
        let center: SpyGameCenterService
    }

    private func makeFixture() -> Fixture {
        let store = MemorySnapshotStore()
        let name = "asobiba.spider.hint.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let center = SpyGameCenterService()
        let services = GameServices(
            snapshots: store, ads: NoopAdService(), playLog: PlayLog(defaults: defaults),
            gameCenter: GameCenterReporter(service: center, allowedGameIDs: ["spider"], isAvailable: { true })
        )
        let model = SpiderModel(services: services, seed: SpiderDealer.verifiedSeeds(for: .one)[0])
        return Fixture(model: model, store: store, services: services, center: center)
    }

    /// 指せる手が無く勝ち筋も無い盤。
    private func hopelessBoard() -> SpiderBoard {
        var columns: [[SpiderCard]] = []
        for i in 0..<8 { columns.append([card(.spade, 13, id: i)]) }
        columns.append([card(.spade, 1, id: 20)])
        columns.append([card(.spade, 1, id: 21)])
        return board(columns)
    }

    /// 動かせる手を 1 手指す（札を動かして盤を変える）。
    private func playAnyMove(_ model: SpiderModel) {
        guard case .move(let from, let index, let to)? = model.board.legalMoves.first(where: {
            if case .move = $0 { return true } else { return false }
        }) else { return }
        model.tapPile(from, cardIndex: index)
        model.tapPile(to)
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
        #expect(f.model.hintSource != nil || f.model.hintsDeal)
        #expect(!f.model.isHintThinking)
    }

    @Test("札を動かすと印は消える")
    func hintClearsWhenTheBoardMoves() async {
        let f = makeFixture()
        await f.model.requestHint()
        #expect(f.model.hintMove != nil)
        playAnyMove(f.model)
        #expect(f.model.hintMove == nil)
        #expect(f.model.hintSource == nil)
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
        #expect(model.moveCount == 1, "前提: 読みの最中に 1 手指した")
        #expect(model.hintMove == nil)
        #expect(model.hints.used == 0)
        #expect(!model.isHintThinking)
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

        let restored = SpiderModel(services: f.services)
        #expect(restored.hints.used == 1)

        let data = try #require(f.store.rawData(for: "spider"))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["hintsUsed"] = nil
        let legacy = MemorySnapshotStore()
        legacy.inject(try JSONSerialization.data(withJSONObject: json), for: "spider")
        let services = GameServices(snapshots: legacy, ads: NoopAdService())
        #expect(SpiderModel(services: services).hints.used == 0)
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
        control.model.tapPile(0, cardIndex: 0)
        control.model.tapPile(1)
        #expect(control.model.phase == .won)
        #expect(control.center.scores.count == 1, "前提: 使わなければ送られる")

        let used = makeFixture()
        await used.model.requestHint()
        used.model.tick()
        used.model.replaceBoardForTesting(Self.almostWon())
        used.model.tapPile(0, cardIndex: 0)
        used.model.tapPile(1)
        #expect(used.model.phase == .won)
        #expect(used.center.scores.isEmpty, "ヒントを使った局のタイムを順位表に混ぜない")
        #expect(used.model.recordResult != nil, "自己ベストの表示は従来どおり出る")
    }

    /// 列0 の A を列1 の 2（K〜2 が並んでいる）へ置けば 8 組目が完成して勝つ盤。
    private static func almostWon() -> SpiderBoard {
        var run: [SpiderCard] = []
        for rank in stride(from: 13, through: 2, by: -1) { run.append(card(.spade, rank, id: rank)) }
        var columns: [[SpiderCard]] = [[card(.spade, 1, id: 40)], run]
        for _ in 0..<8 { columns.append([]) }
        var b = board(columns)
        b.completed = Array(repeating: .spade, count: 7)
        return b
    }
}
