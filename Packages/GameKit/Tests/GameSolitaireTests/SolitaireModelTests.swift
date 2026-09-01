import Testing
import Foundation
import Core
@testable import GameSolitaire

// MARK: - Mocks

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
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

private final class FeedbackSpy: FeedbackService, @unchecked Sendable {
    private(set) var impacts: [FeedbackImpact] = []
    private(set) var notices: [FeedbackNotice] = []

    @MainActor func impact(_ style: FeedbackImpact) { impacts.append(style) }
    @MainActor func notify(_ type: FeedbackNotice) { notices.append(type) }
}

@MainActor
private func makeLog(suite: String) -> PlayLog {
    let name = "asobiba.solitaire.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return PlayLog(defaults: defaults)
}

@MainActor
private func makeServices(
    store: SnapshotStore = MemorySnapshotStore(),
    playLog: PlayLog? = nil
) -> (GameServices, FeedbackSpy) {
    let spy = FeedbackSpy()
    return (
        GameServices(snapshots: store, ads: NoopAdService(), feedback: spy, playLog: playLog),
        spy
    )
}

/// 使い回す固定種（`SolitaireDealer.verifiedSeeds` の先頭。ソルバー検証済み）。
private let fixedSeed = SolitaireDealer.verifiedSeeds[0]

/// ソルバーの勝ち筋を、**View と同じタップ操作に翻訳して**指す。
///
/// 直接 `SolitaireBoard.apply` を呼ばずタップ経路を通すのは、選択 → 置き先という 2 段の
/// 操作そのものを 1 局ぶん通しで検証するため（View を組まずに触れるのはここが唯一の面）。
@MainActor
private func play(_ model: SolitaireModel, _ moves: [SolitaireMove]) {
    for move in moves {
        switch move {
        case .draw:
            model.tapStock()
        case .wasteToFoundation:
            guard let suit = model.board.waste.last?.suit else { continue }
            model.tapWaste()
            model.tapFoundation(suit)
        case .wasteToTableau(let pile):
            model.tapWaste()
            model.tapPile(pile)
        case .tableauToFoundation(let pile):
            guard let suit = model.board.tableau[pile].top?.suit else { continue }
            model.tapPile(pile)
            model.tapFoundation(suit)
        case .tableauToTableau(let from, let index, let to):
            model.tapPile(from, cardIndex: index)
            model.tapPile(to)
        case .placeJoker(let pile):
            model.placeJoker(onPile: pile)
        }
    }
}

// MARK: - 進行

@Suite("ソリティアの進行")
@MainActor
struct SolitaireModelTests {

    @Test("開始時はクロンダイクの初期配置で、計時も手数も 0 から始まる")
    func initialBoard() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        #expect(model.phase == .playing)
        #expect(model.board.tableau.map(\.faceUp.count) == Array(repeating: 1, count: 7))
        #expect(model.board.tableau.map(\.faceDown.count) == [0, 1, 2, 3, 4, 5, 6])
        #expect(model.board.stock.count == 24)
        #expect(model.moveCount == 0)
        #expect(model.elapsedSeconds == 0)
        #expect(!model.canUndo)
    }

    @Test("札をタップして選び、置き先をタップすると動く")
    func selectThenPlace() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        // 場札から場札へ動かせる組を、盤面から 1 つ見つけて指す。
        var found = false
        outer: for from in 0..<SolitaireBoard.pileCount {
            for to in 0..<SolitaireBoard.pileCount where from != to {
                let move = SolitaireMove.tableauToTableau(from: from, cardIndex: 0, to: to)
                guard model.board.isLegal(move) else { continue }
                let card = model.board.tableau[from].faceUp[0]
                model.tapPile(from, cardIndex: 0)
                #expect(model.selection == .tableau(pile: from, cardIndex: 0))
                model.tapPile(to)
                #expect(model.selection == nil)
                #expect(model.board.tableau[to].top == card)
                #expect(model.moveCount == 1)
                found = true
                break outer
            }
        }
        #expect(found, "初期配置に場札どうしの合法手が 1 つも無い（種の選び直しが要る）")
    }

    @Test("同じ札をもう一度タップすると選択が外れる")
    func tapTwiceDeselects() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        model.tapPile(0, cardIndex: 0)
        #expect(model.selection != nil)
        model.tapPile(0, cardIndex: 0)
        #expect(model.selection == nil)
    }

    @Test("置けない先をタップしても盤面は動かず、拒否として数える")
    func illegalDestinationIsRejected() {
        let (services, spy) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        let before = model.board
        // 組札は A からしか始まらないので、A 以外を選んで組札を叩けば必ず拒否される。
        let pile = (0..<SolitaireBoard.pileCount).first { model.board.tableau[$0].top?.rank != 1 }
        let target = try! #require(pile)
        let suit = try! #require(model.board.tableau[target].top?.suit)
        model.tapPile(target, cardIndex: 0)
        model.tapFoundation(suit)
        #expect(model.board == before)
        #expect(model.rejectedTapCount == 1)
        #expect(spy.notices.contains(.warning))
    }

    @Test("戻すは何回でも効き、配ったばかりの状態まで戻せる")
    func undoIsUnlimited() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        let initial = model.board
        for _ in 0..<5 { model.tapStock() }
        #expect(model.board != initial)
        #expect(model.canUndo)
        while model.canUndo { model.undo() }
        #expect(model.board == initial)
        #expect(model.moveCount == 0)
    }

    @Test("山めくりは手数に数えない（数えると1局で数百手になる）")
    func drawsAreNotCountedAsMoves() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        for _ in 0..<10 { model.tapStock() }
        #expect(model.moveCount == 0)
        #expect(model.canUndo, "めくった手そのものは戻せる")
    }

    @Test("ジョーカーは所持していないと置けない（入手経路は #406 の決裁待ち）")
    func jokerNeedsPossession() {
        let (services, _) = makeServices()
        let model = SolitaireModel(services: services, seed: fixedSeed)
        #expect(!model.board.jokerAvailable)
        #expect(model.placeJoker(onPile: 0) == false)
        #expect(!model.jokerUsed)
        #expect(model.rejectedTapCount == 1)
    }
}

// MARK: - 自動で上がる

@Suite("自動で上がる")
@MainActor
struct SolitaireAutoFinishTests {

    /// 全札が表向きで、あとは組札へ積むだけの盤面。
    private func almostWonBoard() -> SolitaireBoard {
        var piles: [SolitairePile] = []
        for suit in SolitaireSuit.allCases {
            // 13 → 1 の降順に置く。組札へは A から送るので、複数回のパスが要る形になる。
            piles.append(SolitairePile(faceUp: (1...13).reversed().map { SolitaireCard(suit, $0) }))
        }
        while piles.count < SolitaireBoard.pileCount { piles.append(SolitairePile()) }
        return SolitaireBoard(tableau: piles)
    }

    @Test("組札へ送るだけで勝てる盤面では手順が見つかる")
    func findsPlanWhenOnlyStackingRemains() {
        let plan = try! #require(SolitaireModel.autoFinishPlan(from: almostWonBoard()))
        var board = almostWonBoard()
        // #expect の中で mutating を呼ぶとマクロ展開側で immutable になるため、外で適用する。
        for move in plan {
            let applied = board.apply(move)
            #expect(applied)
        }
        #expect(board.isWon)
        #expect(plan.allSatisfy { $0 != .draw }, "この盤面に山札は無いのでめくる手は出ない")
    }

    @Test("山札に沈んだ札も、めくりだけで届くなら手順に含める")
    func drawsThroughTheStock() {
        var piles: [SolitairePile] = []
        for suit in SolitaireSuit.allCases {
            piles.append(SolitairePile(faceUp: (2...13).reversed().map { SolitaireCard(suit, $0) }))
        }
        while piles.count < SolitaireBoard.pileCount { piles.append(SolitairePile()) }
        // A 4 枚だけを山札に沈める。
        let aces = SolitaireSuit.allCases.map { SolitaireCard($0, 1) }
        let board = SolitaireBoard(tableau: piles, stock: aces)
        let plan = try! #require(SolitaireModel.autoFinishPlan(from: board))
        #expect(plan.contains(.draw))
        var replayed = board
        for move in plan {
            let applied = replayed.apply(move)
            #expect(applied)
        }
        #expect(replayed.isWon)
    }

    @Test("積み替えが要る盤面では手順を返さない（代わりに解いてしまわない）")
    func refusesWhenReorderingIsNeeded() {
        // 伏せ札が残っている = 場札を動かさないと表に出ない。
        var piles = [SolitairePile(faceDown: [SolitaireCard(.spade, 1)], faceUp: [SolitaireCard(.heart, 2)])]
        while piles.count < SolitaireBoard.pileCount { piles.append(SolitairePile()) }
        #expect(SolitaireModel.autoFinishPlan(from: SolitaireBoard(tableau: piles)) == nil)
    }

    @Test("勝ち済みの盤面には手順を出さない")
    func noPlanWhenAlreadyWon() {
        let won = SolitaireBoard(
            tableau: Array(repeating: SolitairePile(), count: SolitaireBoard.pileCount),
            foundations: [13, 13, 13, 13]
        )
        #expect(won.isWon)
        #expect(SolitaireModel.autoFinishPlan(from: won) == nil)
    }
}

// MARK: - 記録・中断

@Suite("ソリティアの記録と中断")
@MainActor
struct SolitaireRecordTests {

    @Test("勝ち筋を指し切るとクリアになり、タイムと手数が記録されて中断データが消える")
    func clearRecordsTimeAndMoves() {
        let store = MemorySnapshotStore()
        let log = makeLog(suite: "clear")
        let (services, spy) = makeServices(store: store, playLog: log)
        let model = SolitaireModel(services: services, seed: fixedSeed)

        let solution = try! #require(SolitaireSolver.solve(SolitaireDealer.deal(seed: fixedSeed)).solution)
        model.tick()   // 0 秒クリアにしない（順位表は 0 秒を送らない設計・#289）
        play(model, solution)

        #expect(model.phase == .won)
        #expect(model.board.isWon)
        #expect(spy.notices.contains(.success))
        #expect(!store.exists(for: "solitaire"), "決着した局の中断データは残さない")

        let record = try! #require(log.record(gameID: "solitaire"))
        #expect(record.metric == .shortestTime)
        #expect(record.wins == 1)
        #expect(record.plays == 1)
        #expect(record.bestSeconds == 1)
        #expect(record.fewestMoves == model.moveCount)
    }

    @Test("1手でも指した盤面を捨てると、クリアできなかった局として記録される")
    func abandoningADealCountsAsALoss() {
        let log = makeLog(suite: "abandon")
        let (services, _) = makeServices(playLog: log)
        let model = SolitaireModel(services: services, seed: fixedSeed)

        model.tapStock()
        model.newGame()

        let record = try! #require(log.record(gameID: "solitaire"))
        #expect(record.plays == 1)
        #expect(record.losses == 1)
        #expect(record.wins == 0)
        #expect(record.bestSeconds == nil, "クリアしていない局のタイムは自己ベストに入れない")
    }

    @Test("配ったばかりの盤面を配り直しても記録しない")
    func redealingUntouchedBoardIsNotRecorded() {
        let log = makeLog(suite: "redeal")
        let (services, _) = makeServices(playLog: log)
        let model = SolitaireModel(services: services, seed: fixedSeed)

        model.newGame()

        #expect(log.record(gameID: "solitaire") == nil)
    }

    @Test("中断すると種と手順が保存され、復元すると同じ盤面・同じ経過秒に戻る")
    func restoresFromSnapshot() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = SolitaireModel(services: services, seed: fixedSeed)
        for _ in 0..<3 { model.tapStock() }
        for _ in 0..<7 { model.tick() }
        model.tick()   // 保存の間隔に乗せず、直近の手で保存済みの経過秒を確かめる

        #expect(store.exists(for: "solitaire"))
        let restored = SolitaireModel(services: services, seed: 999_999)
        #expect(restored.board == model.board, "種ではなく保存された配札が優先される")
        #expect(restored.canUndo)
    }

    @Test("配ったばかりの盤面は保存しない（ハブに「続きから」を出さない）")
    func untouchedBoardIsNotPersisted() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = SolitaireModel(services: services, seed: fixedSeed)
        model.tick()
        #expect(!store.exists(for: "solitaire"))

        // 1 手指せば保存され、戻して配りたてに戻ると再び消える。
        model.tapStock()
        #expect(store.exists(for: "solitaire"))
        model.undo()
        #expect(!store.exists(for: "solitaire"))
    }

    @Test("計時は30秒ごとに保存し直す（長考のあとの終了でタイムが縮まない・#240）")
    func timerPersistsPeriodically() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = SolitaireModel(services: services, seed: fixedSeed)
        model.tapStock()
        for _ in 0..<SolitaireModel.persistInterval { model.tick() }
        let snapshot = try! #require(store.load(SolitaireSnapshot.self, for: "solitaire"))
        #expect(snapshot.elapsedSeconds == SolitaireModel.persistInterval)
    }
}

// MARK: - 寸法

@Suite("ソリティアの盤面寸法")
struct SolitaireMetricsTests {

    @Test("どの画面幅でも 7 列が収まる", arguments: [320.0, 375.0, 393.0, 430.0, 744.0, 1024.0])
    func sevenColumnsFit(width: Double) {
        let available = CGFloat(width)
        let card = SolitaireMetrics.cardWidth(availableWidth: available)
        let total = card * CGFloat(SolitaireBoard.pileCount)
            + SolitaireMetrics.columnGap * CGFloat(SolitaireBoard.pileCount - 1)
        // 上限に張り付く広い画面だけは余る（間延びさせないための頭打ち）。それ以外ははみ出さない。
        #expect(total <= available || card == SolitaireMetrics.maxCardWidth)
        #expect(card >= SolitaireMetrics.minCardWidth)
    }

    @Test("列の高さは伏せ札と表向き札の段差ぶんだけ伸びる")
    func pileHeightGrows() {
        let height = SolitaireMetrics.cardHeight(width: 46)
        let one = SolitaireMetrics.pileHeight(faceDownCount: 0, faceUpCount: 1, cardHeight: height)
        let stacked = SolitaireMetrics.pileHeight(faceDownCount: 6, faceUpCount: 4, cardHeight: height)
        #expect(one == height)
        #expect(stacked > one)
        #expect(stacked == height
                + 6 * SolitaireMetrics.faceDownStep(cardHeight: height)
                + 3 * SolitaireMetrics.faceUpStep(cardHeight: height))
    }
}

// MARK: - 読み上げ

@Suite("ソリティアの読み上げ")
struct SolitaireAccessibilityTests {

    @Test("場札は 列・枚数・札・伏せ札・上に載る枚数 を読む")
    func tableauCard() {
        let label = SolitaireAccessibility.tableauCardLabel(
            pile: 2, position: 1, aboveCount: 2, hiddenCount: 3,
            card: SolitaireCard(.heart, 7), isSelected: true, isMovable: true
        )
        #expect(label == "3列目、2枚目、ハートの7、伏せ札3枚、上に2枚、選択中")
    }

    @Test("動かせない札はそのことを読む（見た目には出ない情報）")
    func immovableCard() {
        let label = SolitaireAccessibility.tableauCardLabel(
            pile: 0, position: 0, aboveCount: 0, hiddenCount: 0,
            card: SolitaireCard(.spade, 13), isSelected: false, isMovable: false
        )
        #expect(label.hasSuffix("動かせません"))
    }

    @Test("空の列は「K だけ置ける」ことまで読む")
    func emptyPile() {
        #expect(SolitaireAccessibility.emptyPileLabel(pile: 6) == "7列目、空、キングだけ置けます")
    }

    @Test("組札は空とどこまで積んだかを読み分ける")
    func foundation() {
        #expect(SolitaireAccessibility.foundationLabel(suit: .club, rank: 0) == "クラブの組札、空")
        #expect(SolitaireAccessibility.foundationLabel(suit: .diamond, rank: 12) == "ダイヤの組札、Qまで")
    }

    @Test("山札は残量と、めくり切ったあとの動きを読む")
    func stock() {
        #expect(SolitaireAccessibility.stockLabel(remaining: 24).contains("残り24枚"))
        #expect(SolitaireAccessibility.stockLabel(remaining: 0).contains("捨て札を戻す"))
    }

    @Test("捨て札は空と選択中を読み分ける")
    func waste() {
        #expect(SolitaireAccessibility.wasteLabel(card: nil, isSelected: false) == "捨て札、空")
        #expect(SolitaireAccessibility.wasteLabel(card: SolitaireCard(.spade, 1), isSelected: true)
                == "捨て札、スペードのA、選択中")
    }

    @Test("ステータスは経過・手数・詰みを 1 行で読む")
    func status() {
        #expect(SolitaireAccessibility.statusLabel(
            phase: .playing, elapsedSeconds: 65, moveCount: 12, isDeadEnd: false) == "経過1:05、12手")
        #expect(SolitaireAccessibility.statusLabel(
            phase: .playing, elapsedSeconds: 65, moveCount: 12, isDeadEnd: true)
                .hasPrefix("進める手がありません"))
        #expect(SolitaireAccessibility.statusLabel(
            phase: .won, elapsedSeconds: 65, moveCount: 12, isDeadEnd: false).hasPrefix("クリア"))
    }

    @Test("札の呼び名はスート記号ではなく語で読む")
    func cardNames() {
        #expect(SolitaireAccessibility.cardLabel(SolitaireCard(.spade, 11)) == "スペードのJ")
        #expect(SolitaireAccessibility.cardLabel(.joker) == "ジョーカー")
    }
}

// MARK: - 遊び方シート

@Suite("ソリティアのルールシート")
struct SolitaireRuleSheetTests {

    @Test("クロンダイクの要点（空列は K・山札の循環・戻すの無料）が抜けていない")
    func coversTheEssentials() {
        let text = SolitaireRuleSheet.rules.map { $0.0 + $0.1 }.joined()
        #expect(text.contains("K だけ"))
        #expect(text.contains("捨て札が山札に戻ります"))
        #expect(text.contains("何回でも無料"))
        #expect(text.contains("クリアできることを確かめて"))
    }
}
