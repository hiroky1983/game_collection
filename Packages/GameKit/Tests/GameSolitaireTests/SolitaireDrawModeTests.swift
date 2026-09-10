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
    /// 旧版の中断データ（`drawMode` の鍵が無い JSON）を直接ねじ込む口。
    func inject(raw: Data, for gameID: String) { store[gameID] = raw }
}

@MainActor
private func makeServices(store: SnapshotStore = MemorySnapshotStore()) -> GameServices {
    GameServices(snapshots: store, ads: NoopAdService(), feedback: NoopFeedbackService(), playLog: nil)
}

private let draw3 = SolitaireRuleSet(drawMode: .three)

/// 場札を空にした、山札と捨て札だけを見るための盤面。
/// 場札が絡むと「どの札が使えるか」の検証に余計な条件が混ざる。
private func stockOnlyBoard(
    stock: [SolitaireCard],
    waste: [SolitaireCard] = [],
    rules: SolitaireRuleSet = .standard
) -> SolitaireBoard {
    SolitaireBoard(
        tableau: Array(repeating: SolitairePile(), count: SolitaireBoard.pileCount),
        stock: stock,
        waste: waste,
        rules: rules
    )
}

/// 並びを作りやすくするための短縮（スートは判定に効かないので全部スペード）。
private func cards(_ ranks: [Int]) -> [SolitaireCard] {
    ranks.map { SolitaireCard(.spade, $0) }
}

// MARK: - めくり枚数

@Suite("ソリティア 山札のめくり枚数（#498）")
struct SolitaireDrawModeTests {

    @Test("既定は1枚めくりで、めくる枚数も従来どおり1枚")
    func defaultIsSingleDraw() {
        #expect(SolitaireRuleSet.standard.drawMode == .one)
        #expect(SolitaireRuleSet().drawCount == 1)
        #expect(SolitaireDealer.deal(seed: 7).rules == .standard)

        var board = stockOnlyBoard(stock: cards([1, 2, 3, 4, 5]))
        board.apply(.draw)
        #expect(board.waste.map(\.rank) == [5])
        #expect(board.stock.count == 4)
    }

    @Test("3枚めくりは1回のめくりで3枚を捨て札へ送り、使えるのは一番上だけ")
    func drawsThreeAtOnce() {
        var board = stockOnlyBoard(stock: cards([1, 2, 3, 4, 5]), rules: draw3)
        board.apply(.draw)
        // 山札は `last` が一番上なので、5 → 4 → 3 の順に出る。
        #expect(board.waste.map(\.rank) == [5, 4, 3])
        #expect(board.waste.last?.rank == 3, "使えるのは最後にめくった1枚")
        #expect(board.stock.map(\.rank) == [1, 2])
    }

    @Test("山札の残りが3枚に満たなければ残り全部だけめくる")
    func drawsRemainderWhenStockIsShort() {
        var board = stockOnlyBoard(stock: cards([1, 2]), rules: draw3)
        board.apply(.draw)
        #expect(board.waste.map(\.rank) == [2, 1])
        #expect(board.stock.isEmpty)
    }

    @Test("山札が空なら捨て札を戻してから3枚めくる（循環は無制限のまま）")
    func recyclesWasteBeforeDrawing() {
        var board = stockOnlyBoard(stock: [], waste: cards([1, 2, 3, 4]), rules: draw3)
        #expect(board.isLegal(.draw))
        board.apply(.draw)
        // 捨て札を裏返して戻すので、いちばん下だった 1 から順に出てくる。
        #expect(board.waste.map(\.rank) == [1, 2, 3])
        #expect(board.stock.map(\.rank) == [4])
    }

    @Test("山札も捨て札も空ならめくれない")
    func cannotDrawFromNothing() {
        let board = stockOnlyBoard(stock: [], waste: [], rules: draw3)
        #expect(!board.isLegal(.draw))
        #expect(board.reachableStockCards().isEmpty)
    }
}

// MARK: - 到達できる札の数え上げ

@Suite("ソリティア 山札を循環させて到達できる札（#498）")
struct SolitaireReachableStockTests {

    /// 数え上げの結果を、**実際にその回数だけめくって**裏取りする。
    /// 「n 回めくればその札が一番上に来る」が成り立たないと、ソルバーも詰み検知も嘘をつく。
    private func verifyReachable(_ board: SolitaireBoard) {
        let reachable = board.reachableStockCards()
        #expect(Set(reachable.map(\.card.id)).count == reachable.count, "同じ札が2回出ている")
        for (card, draws) in reachable {
            var replay = board
            for _ in 0..<draws { replay.apply(.draw) }
            #expect(replay.waste.last?.id == card.id,
                    "\(draws)回めくっても \(card.label) が一番上に来ない")
        }
    }

    /// 実装の数え上げを**一切使わずに**、山札と捨て札の状態が一巡するまで実際にめくって
    /// 「一番上に来たことのある札 → 最小のめくり回数」を作る。
    ///
    /// 実装側は「2周ぶん回せば足りる」という理屈で打ち切り回数を決めているので、
    /// 打ち切り回数に依存しないこちらの結果と突き合わせないと**取りこぼし**を検出できない
    /// （`verifyReachable` は「出てきた札が本当に出るか」しか見ないため、
    /// 打ち切りを半分にしても素通りする・PR #498 の敵対的検証で実測）。
    private func bruteForceReachable(_ board: SolitaireBoard) -> [Int: Int] {
        var result: [Int: Int] = [:]
        if let top = board.waste.last { result[top.id] = 0 }
        var replay = board
        var seen: Set<[Int]> = []
        var draws = 0
        // めくりは決定的なので、山札と捨て札の並びが一度でも繰り返したらそれ以上新しい札は出ない。
        while replay.isLegal(.draw) {
            let key = replay.stock.map(\.id) + [-1] + replay.waste.map(\.id)
            guard seen.insert(key).inserted else { break }
            replay.apply(.draw)
            draws += 1
            if let top = replay.waste.last, result[top.id] == nil { result[top.id] = draws }
        }
        return result
    }

    private func verifyReachableIsComplete(_ board: SolitaireBoard) {
        let counted = Dictionary(
            uniqueKeysWithValues: board.reachableStockCards().map { ($0.card.id, $0.draws) }
        )
        #expect(counted == bruteForceReachable(board),
                "到達できる札の数え上げが、実際にめくって出る札と一致しない")
    }

    @Test("3枚めくりの数え上げが、実際にめくって出る札と過不足なく一致する",
          arguments: [0, 1, 2, 5, 137])
    func reachableCountsMatchBruteForce(index: Int) {
        var board = SolitaireDealer.deal(seed: SolitaireDealer.verifiedSeedsDraw3[index], rules: draw3)
        verifyReachable(board)
        verifyReachableIsComplete(board)

        // 山札を回しただけの局面（区切りがずれる形）。
        for _ in 0..<3 { board.apply(.draw) }
        verifyReachable(board)
        verifyReachableIsComplete(board)

        // 捨て札から札を1枚抜いた局面。**枚数が変わると一番上に来る札の顔ぶれが総入れ替えになる**
        // ので、3枚めくりでいちばん壊れやすいのはここ。
        // `isLegal(.draw)` は循環がある限り常に真なので、**回数で必ず打ち切る**
        // （山札 + 捨て札を 1 周する回数で足りる。見つからない配札はそのまま検証する）。
        var played = board
        for _ in 0..<(played.stock.count + played.waste.count) {
            if let target = (0..<SolitaireBoard.pileCount).first(where: {
                played.isLegal(.wasteToTableau(pile: $0))
            }) {
                played.apply(.wasteToTableau(pile: target))
                break
            }
            played.apply(.draw)
        }
        verifyReachable(played)
        verifyReachableIsComplete(played)
    }

    @Test("1枚めくりの数え上げも、実際にめくって出る札と一致する")
    func singleDrawCountsMatchBruteForce() {
        var board = SolitaireDealer.deal(seed: SolitaireDealer.verifiedSeeds[0])
        verifyReachableIsComplete(board)
        for _ in 0..<5 { board.apply(.draw) }
        verifyReachableIsComplete(board)
    }

    @Test("1枚めくりでも同じ性質が成り立つ（既定の挙動が壊れていないことの裏取り）")
    func singleDrawIsAlsoReplayable() {
        var board = SolitaireDealer.deal(seed: SolitaireDealer.verifiedSeeds[0])
        verifyReachable(board)
        for _ in 0..<5 { board.apply(.draw) }
        verifyReachable(board)
    }

    @Test("1枚めくりは山札と捨て札の全札を数え上げる（従来どおり）")
    func singleDrawReachesEveryCard() {
        let board = stockOnlyBoard(stock: cards([1, 2, 3, 4]), waste: cards([5, 6]))
        let reachable = board.reachableStockCards()
        #expect(reachable.count == 6)
        #expect(reachable.map(\.card.rank) == [6, 4, 3, 2, 1, 5])
        #expect(reachable.map(\.draws) == [0, 1, 2, 3, 4, 5])
    }

    @Test("3枚めくりでは一番上に来ない札があり、数え上げからも外れる")
    func tripleDrawSkipsCards() {
        // 6 枚ちょうどなので、循環しても 3 枚目と 6 枚目しか一番上に来ない。
        let board = stockOnlyBoard(stock: cards([1, 2, 3, 4, 5, 6]), rules: draw3)
        let reachable = board.reachableStockCards()
        #expect(reachable.map(\.card.rank) == [4, 1])
        #expect(reachable.map(\.draws) == [1, 2])
        #expect(reachable.count < 6, "3枚めくりで全札に手が届いてしまっている")
    }

    @Test("捨て札を戻すと区切りがずれ、1周めに出なかった札が2周めに出る")
    func recyclingShiftsTheGrouping() {
        // 山札 4 枚・捨て札 1 枚。1 周めは 4 → 1、戻したあとは並びが変わって別の札が出る。
        let board = stockOnlyBoard(stock: cards([1, 2, 3, 4]), waste: cards([9]), rules: draw3)
        let reachable = board.reachableStockCards()
        #expect(reachable.first?.card.rank == 9, "捨て札の一番上は 0 回で使える")
        // 2 周ぶん数えるので、1 周めだけでは届かない札まで拾えている。
        #expect(reachable.count > 2)
        for (card, draws) in reachable {
            var replay = board
            for _ in 0..<draws { replay.apply(.draw) }
            #expect(replay.waste.last?.id == card.id)
        }
    }

    @Test("めくり枚数のちがいで詰み検知の結論が変わる")
    func deadEndDependsOnDrawMode() {
        // 場札は動かせない並び（K の上に何も置けず、空列も無い）。
        // 使えるのは山札から拾える札だけで、♠A が組札へ行けるかどうかで結論が分かれる。
        let piles = (0..<SolitaireBoard.pileCount).map { index in
            SolitairePile(faceUp: [SolitaireCard(index < 4 ? .spade : .heart, 13)])
        }
        // 山札は 3 枚。1 枚めくりなら 3 枚とも一番上に来るが、3 枚めくりでは
        // いちばん下の ♠A（`stock.first`）だけが一番上に来る。
        let stock = [SolitaireCard(.spade, 1), SolitaireCard(.heart, 5), SolitaireCard(.club, 9)]

        let single = SolitaireBoard(tableau: piles, stock: stock)
        #expect(!single.isDeadEnd, "1枚めくりなら ♠A を組札へ送れる")

        var triple = SolitaireBoard(tableau: piles, stock: stock, rules: draw3)
        #expect(triple.reachableStockCards().map(\.card.rank) == [1],
                "3枚めくりで一番上に来るのは山札のいちばん下の1枚だけ")
        #expect(!triple.isDeadEnd, "その1枚が ♠A なのでまだ進める")

        // ♠A を使い切ると、3 枚めくりでは残り 2 枚に手が届かず行き止まりになる。
        triple.apply(.draw)
        triple.apply(.wasteToFoundation)
        #expect(triple.isDeadEnd)
    }
}

// MARK: - モード別の検証済み配札

@Suite("ソリティア 3枚めくりの検証済み配札（#498）")
struct SolitaireDraw3SeedTests {

    @Test("3枚めくり用の種が十分な数あり、重複していない")
    func hasEnoughSeeds() {
        #expect(SolitaireDealer.verifiedSeedsDraw3.count >= 1000)
        #expect(Set(SolitaireDealer.verifiedSeedsDraw3).count
                == SolitaireDealer.verifiedSeedsDraw3.count)
    }

    @Test("モードごとに別の配列を引く")
    func picksSeedsPerMode() {
        #expect(SolitaireDealer.verifiedSeeds(for: .one) == SolitaireDealer.verifiedSeeds)
        #expect(SolitaireDealer.verifiedSeeds(for: .three) == SolitaireDealer.verifiedSeedsDraw3)
        // 流用していないこと。同じ配列を指していたら検証の意味が消える。
        #expect(SolitaireDealer.verifiedSeeds != SolitaireDealer.verifiedSeedsDraw3)
    }

    /// **1枚めくりの種を流用できない**ことの裏取り。ここが空振りだと、モード別に
    /// 検証を分けている理由そのものが無くなる。
    @Test("1枚めくりで解ける種にも、3枚めくりでは解けないものがある")
    func singleDrawSeedsAreNotAlwaysSolvableWithThree() {
        // 1 件でも見つかれば主張は立つので、そこで探索を打ち切る（`filter` だと 60 件すべてで
        // ソルバーを回すことになり、デバッグビルドでは 1 配札あたり 1 秒近くかかる）。
        let hasUnsolvable = SolitaireDealer.verifiedSeeds.prefix(60).contains { seed in
            !SolitaireSolver.solve(SolitaireDealer.deal(seed: seed, rules: draw3)).isSolvable
        }
        #expect(hasUnsolvable,
                "1枚めくり用の種 60 個すべてが3枚めくりでも解けてしまった（検証の分離が無意味）")
    }

    @Test("3枚めくりの検証済みの種は、勝ち筋を指し切ればクリアできる",
          arguments: [0, 137, 999])
    func verifiedSeedsAreActuallyWinnable(index: Int) {
        let seed = SolitaireDealer.verifiedSeedsDraw3[index]
        var board = SolitaireDealer.deal(seed: seed, rules: draw3)
        let result = SolitaireSolver.solve(board)
        guard let solution = result.solution else {
            Issue.record("種 \(seed) の勝ち筋が見つからなかった（探索局面 \(result.statesExplored)）")
            return
        }
        for move in solution {
            // `#expect` の中で直接 mutating を呼べないので、一度受けてから確かめる。
            let applied = board.apply(move)
            #expect(applied, "種 \(seed) の勝ち筋に非合法手が混ざっている: \(move)")
        }
        #expect(board.isWon, "種 \(seed) は勝ち筋を指し切ってもクリアにならなかった")
    }

    @Test("配札そのものは種だけで決まる（めくり方を変えても並びは動かない）")
    func dealIsIndependentOfRules() {
        let single = SolitaireDealer.deal(seed: 12345)
        let triple = SolitaireDealer.deal(seed: 12345, rules: draw3)
        #expect(single.tableau == triple.tableau)
        #expect(single.stock == triple.stock)
        #expect(single.rules.drawMode == .one)
        #expect(triple.rules.drawMode == .three)
    }
}

// MARK: - 1局=1RuleSet（焼き込みと復元）

@Suite("ソリティア ルールの焼き込み（#498）")
@MainActor
struct SolitaireRuleSetBakingTests {

    @Test("既定は1枚めくりで、局中に変わらない")
    func defaultsToSingleDrawAndStaysPut() {
        let model = SolitaireModel(services: makeServices())
        #expect(model.rules.drawMode == .one)
        for _ in 0..<3 { model.tapStock() }
        #expect(model.rules.drawMode == .one)
        #expect(model.board.rules == model.rules)
    }

    @Test("配り直しでルールを差し替えると、盤面もそのルールで動く")
    func newGameBakesTheChosenRules() {
        let model = SolitaireModel(services: makeServices())
        model.newGame(rules: draw3)
        #expect(model.rules.drawMode == .three)

        let before = model.board.waste.count
        model.tapStock()
        #expect(model.board.waste.count == before + 3)
    }

    @Test("ルールを省いた配り直しは今の局と同じルールを引き継ぐ")
    func newGameKeepsRulesWhenNotGiven() {
        let model = SolitaireModel(services: makeServices())
        model.newGame(rules: draw3)
        model.newGame()
        #expect(model.rules.drawMode == .three, "クリア後の「次のゲーム」でルールが戻ってしまう")
    }

    @Test("3枚めくりの局は、その配札のためだけに検証された種から配られる")
    func newGameUsesTheMatchingSeedTable() {
        let model = SolitaireModel(services: makeServices())
        model.newGame(rules: draw3)
        #expect(SolitaireSolver.solve(model.board).isSolvable,
                "3枚めくりでクリアできない配札が出題された")
    }

    @Test("中断して再開しても、その局のめくり方は変わらない")
    func snapshotRestoresTheDrawMode() {
        let store = MemorySnapshotStore()
        let model = SolitaireModel(services: makeServices(store: store))
        model.newGame(rules: draw3)
        model.tapStock()
        let waste = model.board.waste.map(\.id)

        // 復元側は既定（1枚めくり）を渡す。中断データのほうが優先されないと、
        // 再開した瞬間に別のルールの局に化ける。
        let resumed = SolitaireModel(services: makeServices(store: store), rules: .standard)
        #expect(resumed.rules.drawMode == .three)
        #expect(resumed.board.waste.map(\.id) == waste)
    }

    @Test("めくり方の鍵が無い旧データは、1枚めくりとして読む")
    func legacySnapshotFallsBackToSingleDraw() throws {
        let store = MemorySnapshotStore()
        // #498 以前の中断データ。`drawMode` の鍵そのものが無い。
        let legacy = """
        {"seed":\(SolitaireDealer.verifiedSeeds[0]),"moves":[{"draw":{}}],\
        "elapsedSeconds":12,"jokerGrants":1,"undosRemaining":3}
        """
        store.inject(raw: Data(legacy.utf8), for: "solitaire")

        let model = SolitaireModel(services: makeServices(store: store))
        #expect(model.rules.drawMode == .one, "旧データが3枚めくりに化けた")
        #expect(model.elapsedSeconds == 12, "旧データのデコードそのものが落ちている")
        #expect(model.board.waste.count == 1)
    }

    @Test("3枚めくりで返る札は、そのめくりで出た札だけ（最大3枚）")
    func drawnCardIDsCoverTheWholeDraw() {
        let model = SolitaireModel(services: makeServices())
        model.newGame(rules: draw3)
        model.tapStock()
        #expect(model.drawnCardIDs == Set(model.board.waste.suffix(3).map(\.id)))
        #expect(model.drawnCardIDs.count == 3)

        // めくり以外の手では 1 枚も返さない。
        model.tapWaste()
        model.deselect()
        model.undo()
        #expect(model.drawnCardIDs.isEmpty)
    }

    @Test("捨て札を戻す循環でも、返る札を取りこぼさない")
    func drawnCardIDsSurviveRecycling() {
        var before = stockOnlyBoard(stock: [], waste: cards([1, 2, 3, 4]), rules: draw3)
        let after = { var b = before; b.apply(.draw); return b }()
        #expect(SolitaireBoard.drawnCardIDs(before: before, after: after)
                == Set(after.waste.map(\.id)))
        // 循環をまたがない普通のめくりでも、増えたぶんだけを返す。
        before = stockOnlyBoard(stock: cards([1, 2, 3, 4]), waste: cards([9]), rules: draw3)
        let next = { var b = before; b.apply(.draw); return b }()
        #expect(SolitaireBoard.drawnCardIDs(before: before, after: next)
                == Set(next.waste.suffix(3).map(\.id)))
    }
}

// MARK: - 記録と順位表

@Suite("ソリティア 3枚めくりの記録の扱い（#498）")
@MainActor
struct SolitaireDraw3RecordTests {

    @Test("既定（1枚めくり）は区分を持たず、保存先が従来のまま")
    func standardKeepsTheLegacyRecordKey() {
        #expect(SolitaireDrawMode.one.recordVariant == nil)
        #expect(SolitaireDrawMode.one.recordLabel == nil)
        #expect(PlayLog.recordKey(gameID: "solitaire", variant: SolitaireDrawMode.one.recordVariant)
                == "solitaire")
    }

    @Test("3枚めくりは別の区分に保存され、自己ベストが混ざらない")
    func tripleDrawUsesItsOwnRecordKey() {
        #expect(SolitaireDrawMode.three.recordVariant == "draw3")
        #expect(SolitaireDrawMode.three.recordLabel == "3枚めくり")
        #expect(PlayLog.recordKey(gameID: "solitaire", variant: SolitaireDrawMode.three.recordVariant)
                == "solitaire#draw3")
    }

    @Test("順位表に載るのは標準ルールだけ")
    func onlyStandardGoesToTheLeaderboard() {
        let standard = GameScore(
            metric: .shortestTime, seconds: 120, moves: 40,
            variant: SolitaireDrawMode.one.recordVariant,
            variantLabel: SolitaireDrawMode.one.recordLabel,
            isLeaderboardEligible: true
        )
        #expect(GameCenterLeaderboard.score(gameID: "solitaire", outcome: .win, score: standard) != nil)

        let triple = GameScore(
            metric: .shortestTime, seconds: 120, moves: 40,
            variant: SolitaireDrawMode.three.recordVariant,
            variantLabel: SolitaireDrawMode.three.recordLabel,
            isLeaderboardEligible: false
        )
        #expect(GameCenterLeaderboard.score(gameID: "solitaire", outcome: .win, score: triple) == nil)
    }
}

// MARK: - 捨て札の3枚重ね

@Suite("ソリティア 捨て札の重ね表示（#498）")
struct SolitaireWasteFanTests {

    @Test("扇に広げても、上段が7列の盤幅からはみ出さない")
    func fanFitsInsideTheBoard() {
        for available in stride(from: 320.0, through: 1024.0, by: 8.0) {
            let width = SolitaireMetrics.cardWidth(availableWidth: available)
            let board = SolitaireMetrics.boardWidth(cardWidth: width)
            // 上段は 山札 + 捨て札（扇）+ 組札4 と、その間の 6 つの隙間。
            let row = width
                + SolitaireMetrics.wasteWidth(cardWidth: width, visibleCount: 3)
                + width * 4
                + SolitaireMetrics.columnGap * 6
            #expect(row <= board, "幅 \(available) で捨て札の扇が 7 列目からはみ出す")
        }
    }

    @Test("1枚しか見せないときの枠は札の幅そのもの（既定の見た目を変えない）")
    func singleCardKeepsTheOriginalWidth() {
        let width = SolitaireMetrics.cardWidth(availableWidth: 375)
        #expect(SolitaireMetrics.wasteWidth(cardWidth: width, visibleCount: 1) == width)
        #expect(SolitaireMetrics.wasteWidth(cardWidth: width, visibleCount: 0) == width)
    }

    @Test("ずらし幅は札の幅の半分未満（2枚ぶん重ねても札1枚に収まる）")
    func fanStepStaysWithinOneCard() {
        for width in stride(from: 34.0, through: 120.0, by: 1.0) {
            #expect(SolitaireMetrics.wasteFanStep(cardWidth: width) * 2 <= width)
        }
    }
}

// MARK: - 開始シートと遊び方

@Suite("ソリティア 開始シートの結線（#498）")
struct SolitaireSetupSheetTests {

    @Test("説明文が、モードごとの記録の扱いまで書いている")
    func footerExplainsTheRecordHandling() {
        let single = SolitaireSetupSheet.footer(for: .one)
        #expect(single.contains("1枚ずつ"))
        #expect(single.contains("Game Center"))

        let triple = SolitaireSetupSheet.footer(for: .three)
        #expect(triple.contains("3枚ずつ"))
        #expect(triple.contains("いちばん上の1枚"))
        // 選ぶ前に「記録が別枠になる・順位表に載らない」ことを知らせる（#498 の仕様）。
        #expect(triple.contains("別に記録"))
        #expect(triple.contains("順位表には送りません"))
    }

    @Test("遊び方シートにめくり方の選び方が載っている")
    func ruleSheetExplainsTheOption() {
        let text = SolitaireRuleSheet.rules.map { $0.0 + $0.1 }.joined()
        #expect(text.contains("3枚ずつめくる"))
        #expect(text.contains("順位表に載るのは1枚めくりだけ"))
        // 既存の要点（#476 まで）が落ちていないこと。
        #expect(text.contains("捨て札が山札に戻ります"))
    }

    @Test("View が開始シートと配り直しに結線されている")
    func viewIsWiredToTheSheet() throws {
        let source = try Self.viewSource()
        // シートを開くのは「新規ゲーム」の 1 か所だけ（撮影用の口を除く）。
        #expect(Self.matchCount(of: #"SolitaireSetupSheet\(draft: \$draft"#, in: source) == 1,
                "開始シートが View から外れている")
        // 焼き込むのは「配る」を押した瞬間だけ。ここが `model.newGame()` に戻ると
        // 選んだルールが捨てられ、1局=1RuleSet の入口が消える。
        #expect(Self.matchCount(of: #"model\.newGame\(rules: draft\)"#, in: source) == 1,
                "選んだルールが配り直しに渡っていない")
        // 開くたびに今の局のルールを引き直す（前回の選択が残らない）。
        #expect(Self.matchCount(of: #"draft = model\.rules"#, in: source) == 1,
                "開始シートの初期選択が今の局のルールになっていない")
        // 捨て札の扇は「めくり枚数ぶん」を出す。`suffix(3)` のような直書きに戻ると
        // 1枚めくりの局でも 3 枚重なって見える。
        #expect(Self.matchCount(of: #"waste\.suffix\(model\.rules\.drawCount\)"#, in: source) == 1,
                "捨て札の重ね枚数がルールから外れている")
    }

    private static func viewSource() throws -> String {
        try SolitaireSources.joined()
    }

    private static func matchCount(of pattern: String, in source: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source))
    }
}
