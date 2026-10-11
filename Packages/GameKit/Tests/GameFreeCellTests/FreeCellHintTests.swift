import Testing
import Foundation
import Core
@testable import GameFreeCell
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

/// 純粋な「次の一手」（#2025）。
@Suite("フリーセル ヒントの探索（#2025）")
struct FreeCellHintSearchTests {

    // Debug ビルドでは 1 手ごとの読みが重く、配り 1 つで 2 分近くかかる。CI の時間に収めるため 2 つに絞る
    // （12 配りで往復せず勝ち切れることは作成時に確認済み）。
    @Test("ヒントの手だけを打ち続けて、検証済みの配りを勝ち切れる")
    func playingOnlyHintsWins() throws {
        for seed in FreeCellDealer.verifiedSeeds.prefix(2) {
            var board = FreeCellDealer.deal(seed: seed)
            var steps = 0
            while !board.isWon {
                steps += 1
                try #require(steps <= 400, "種 \(seed): 400 手でも勝てない（往復している）")
                let result = try #require(FreeCellHint.find(in: board), "種 \(seed): 読みが降ろされた")
                guard case .move(let move) = result else {
                    Issue.record("種 \(seed): \(steps) 手目で勝てないと言われた")
                    break
                }
                let applied = board.apply(move)
                #expect(applied, "種 \(seed): 合法でない手を示した \(move)")
            }
            #expect(board.isWon, "種 \(seed)")
        }
    }

    @Test("組札へ送るだけの安全な手は飛ばし、本筋の手を示す")
    func skipsSafeFoundationMoves() throws {
        // 列0 の一番上が A♠（安全に送れる）。列1 の 6♥ を列2 の 7♣ へ移すのが本筋。
        var tableau = [[FreeCellCard]](repeating: [], count: FreeCellBoard.pileCount)
        tableau[0] = [FreeCellCard(.club, 5), FreeCellCard(.spade, 1)]
        tableau[1] = [FreeCellCard(.heart, 6)]
        tableau[2] = [FreeCellCard(.club, 7)]
        let board = FreeCellBoard(tableau: tableau)
        let solution: [FreeCellMove] = [
            .tableauToFoundation(pile: 0),
            .tableauToTableau(from: 1, cardIndex: 0, to: 2),
        ]
        #expect(FreeCellHint.firstMove(of: solution, from: board) == .tableauToTableau(from: 1, cardIndex: 0, to: 2))
    }

    @Test("本筋の手が飛ばした送りの後でないと成立しないときは、その送りを示す")
    func showsTheSkippedSendWhenTheMainMoveNeedsIt() throws {
        // 列2 の一番上の A♠ を送らないと、その下の 7♣ に 6♥ を置けない。
        var tableau = [[FreeCellCard]](repeating: [], count: FreeCellBoard.pileCount)
        tableau[1] = [FreeCellCard(.heart, 6)]
        tableau[2] = [FreeCellCard(.club, 7), FreeCellCard(.spade, 1)]
        let board = FreeCellBoard(tableau: tableau)
        let solution: [FreeCellMove] = [
            .tableauToFoundation(pile: 2),
            .tableauToTableau(from: 1, cardIndex: 0, to: 2),
        ]
        #expect(FreeCellHint.firstMove(of: solution, from: board) == .tableauToFoundation(pile: 2))
    }

    @Test("残りが送るだけなら、その最初の送りを示す")
    func showsASendWhenOnlySendsRemain() {
        var tableau = [[FreeCellCard]](repeating: [], count: FreeCellBoard.pileCount)
        tableau[0] = [FreeCellCard(.spade, 2), FreeCellCard(.spade, 1)]
        let board = FreeCellBoard(tableau: tableau, foundations: [0, 13, 13, 13])
        let solution: [FreeCellMove] = [.tableauToFoundation(pile: 0), .tableauToFoundation(pile: 0)]
        #expect(FreeCellHint.firstMove(of: solution, from: board) == .tableauToFoundation(pile: 0))
    }

    @Test("探索を尽くしても勝ち筋が無い盤は勝てないと言う")
    func hopelessWhenExhausted() {
        var tableau: [[FreeCellCard]] = []
        for suit in PlayingCardSuit.allCases {
            tableau.append((1...6).map { FreeCellCard(suit, $0) })
            tableau.append((7...12).map { FreeCellCard(suit, $0) })
        }
        let cells: [FreeCellCard?] = PlayingCardSuit.allCases.map { FreeCellCard($0, 13) }
        let board = FreeCellBoard(tableau: tableau, cells: cells)
        #expect(board.isDeadEnd, "前提: 指せる手が無い")
        #expect(FreeCellHint.find(in: board) == .hopeless)
    }

    @Test("上限で打ち切られたら、勝てないとは言わず見込みの良い手を示す")
    func fallbackWhenSearchHitsTheLimit() throws {
        let board = FreeCellDealer.deal(seed: FreeCellDealer.verifiedSeeds[0])
        let result = try #require(FreeCellHint.find(in: board, maxStates: 1))
        guard case .move(let move) = result else {
            Issue.record("打ち切りで勝てないと言った")
            return
        }
        #expect(board.isLegal(move))
    }

    @Test("見込みの良い手は組札へ送れる札を優先する")
    func promisingMovePrefersFoundation() {
        var tableau = [[FreeCellCard]](repeating: [], count: FreeCellBoard.pileCount)
        tableau[0] = [FreeCellCard(.club, 9), FreeCellCard(.heart, 1)]
        tableau[1] = [FreeCellCard(.spade, 4)]
        let board = FreeCellBoard(tableau: tableau)
        #expect(FreeCellHint.promisingMove(in: board) == .tableauToFoundation(pile: 0))
    }

    @Test("取り消されたら nil（印を出さない）")
    func cancelledReturnsNil() {
        let board = FreeCellDealer.deal(seed: FreeCellDealer.verifiedSeeds[0])
        #expect(FreeCellHint.find(in: board, isCancelled: { true }) == nil)
    }
}

/// Model 側（回数・広告・順位表・中断復元）。
@Suite("フリーセル ヒントのモデル（#2025）")
@MainActor
struct FreeCellHintModelTests {

    private struct Fixture {
        let model: FreeCellModel
        let store: MemorySnapshotStore
        let services: GameServices
        let center: SpyGameCenterService
    }

    private func makeFixture(store: MemorySnapshotStore = MemorySnapshotStore()) -> Fixture {
        let name = "asobiba.freecell.hint.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let center = SpyGameCenterService()
        let services = GameServices(
            snapshots: store, ads: NoopAdService(), playLog: PlayLog(defaults: defaults),
            gameCenter: GameCenterReporter(service: center, allowedGameIDs: ["freecell"], isAvailable: { true })
        )
        let model = FreeCellModel(services: services, seed: FreeCellDealer.verifiedSeeds[0])
        return Fixture(model: model, store: store, services: services, center: center)
    }

    /// 行き止まりの盤（勝ち筋が無い）を差し込む。
    private func makeHopeless(_ model: FreeCellModel) {
        var tableau: [[FreeCellCard]] = []
        for suit in PlayingCardSuit.allCases {
            tableau.append((1...6).map { FreeCellCard(suit, $0) })
            tableau.append((7...12).map { FreeCellCard(suit, $0) })
        }
        let cells: [FreeCellCard?] = PlayingCardSuit.allCases.map { FreeCellCard($0, 13) }
        model.replaceBoardForTesting(FreeCellBoard(tableau: tableau, cells: cells))
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
        #expect(f.model.hintSource != nil)
        #expect(f.model.hintDestination != nil)
        #expect(!f.model.isHintThinking)
    }

    @Test("札を動かすと印は消える")
    func hintClearsWhenTheBoardMoves() async {
        let f = makeFixture()
        await f.model.requestHint()
        #expect(f.model.hintMove != nil)
        f.model.tapPile(0)
        f.model.tapCell(0)
        #expect(f.model.hintMove == nil)
        #expect(f.model.hintSource == nil)
    }

    @Test("勝てない盤では知らせるだけで回数を減らさない")
    func hopelessDoesNotConsume() async {
        let f = makeFixture()
        makeHopeless(f.model)
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
        let task = Task { await f.model.requestHint() }
        await Task.yield()
        f.model.tapPile(0)
        f.model.tapCell(0)
        await task.value
        #expect(f.model.hintMove == nil)
        #expect(f.model.hints.used == 0)
        #expect(!f.model.isHintThinking)
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
        makeHopeless(f.model)
        #expect(await f.model.requestAdHint() == .granted)
        #expect(f.model.showsHintHopeless)
        #expect(f.model.hints.used == 3)
    }

    @Test("戻してもヒントの回数は戻らない")
    func undoDoesNotRestoreHints() async {
        let f = makeFixture()
        f.model.tapPile(0)
        f.model.tapCell(0)
        await f.model.requestHint()
        f.model.undo()
        #expect(f.model.hints.used == 1)
    }

    @Test("使った回数は中断データに残り、再開で戻らない。旧形式は 0 回")
    func usedCountSurvivesRestart() async throws {
        let f = makeFixture()
        f.model.tapPile(0)
        f.model.tapCell(0)
        await f.model.requestHint()
        f.model.pauseTimer()

        let restored = FreeCellModel(services: f.services)
        #expect(restored.hints.used == 1)

        // 鍵の無い旧形式。
        let data = try #require(f.store.rawData(for: "freecell"))
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["hintsUsed"] = nil
        let legacy = MemorySnapshotStore()
        legacy.inject(try JSONSerialization.data(withJSONObject: json), for: "freecell")
        let services = GameServices(snapshots: legacy, ads: NoopAdService())
        #expect(FreeCellModel(services: services).hints.used == 0)
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
    private static func almostWon() -> FreeCellBoard {
        var tableau = [[FreeCellCard]](repeating: [], count: FreeCellBoard.pileCount)
        tableau[0] = [FreeCellCard(.spade, 13)]
        return FreeCellBoard(tableau: tableau, foundations: [12, 13, 13, 13])
    }
}
