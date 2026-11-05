import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// ねこさがしのライフ表記と、クリアの流れ（ライフ → pt → ランキング → モーダル・#3304）。
@Suite("おじさんちのねこさがしのライフとクリアの流れ")
@MainActor
struct CatPuzzleClearFlowTests {
    private func makeModel() -> CatPuzzleModel {
        let suite = "asobiba.catpuzzle.clearflow.tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return CatPuzzleModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()), stageDefaults: defaults)
    }

    @Test("ライフは 3 つから始まり、ミスのたびに 1 つ減る")
    func livesText() async {
        let model = makeModel()
        model.startStage(1)
        await model.stagePreparation?.value
        #expect(CatPuzzleView.livesText(model) == "♥♥♥")
        let solution = Set(model.puzzle.solutionCells)
        let wrong = (0..<model.puzzle.cellCount).filter { !solution.contains($0) && model.marks[$0] == .empty }
        model.findCat(cell: wrong[0])
        #expect(CatPuzzleView.livesText(model) == "♥♥♡")
        #expect(model.mistakesRemaining == 2)
        model.findCat(cell: wrong[1])
        #expect(CatPuzzleView.livesText(model) == "♥♡♡")
    }

    @Test("pt は残りライフと同じ値（3・2・1）で、鍵の面は 2 倍")
    func pointsEqualLives() {
        for mistakes in 0...2 {
            let lives = CatPuzzleModel.maxMistakes - mistakes
            #expect(CatPuzzleEvent.points(mistakes: mistakes) == lives)
            #expect(CatPuzzleEvent.points(mistakes: mistakes, isKey: true) == lives * 2)
        }
    }

    @Test("段の順序はライフ → ランキング → モーダルで、モーダルの先は無い")
    func stepOrder() {
        var flow = CatPuzzleClearFlow()
        #expect(flow.step == .lives)
        flow.advance()
        #expect(flow.step == .ranking)
        flow.advance()
        #expect(flow.step == .modal && flow.showsModal)
        flow.advance()
        #expect(flow.step == .modal)
    }

    @Test("タップの早送りは今の段を飛ばして次へ進み、モーダルでは何もしない")
    func skip() {
        var flow = CatPuzzleClearFlow()
        flow.skip()
        #expect(flow.step == .ranking)
        flow.skip()
        flow.skip()
        #expect(flow.showsModal)
    }

    @Test("ライフが pt に飛ぶ途中経過: ♥ が減り数字が増え、鍵の面は掛けた後だけ ×2")
    func progress() {
        let start = CatPuzzleClearFlow.progress(lives: 2, flown: 0, isKey: false, multiplied: false)
        #expect(start.hearts == 2 && start.count == 0 && !start.multiplied)
        let mid = CatPuzzleClearFlow.progress(lives: 2, flown: 1, isKey: false, multiplied: false)
        #expect(mid.hearts == 1 && mid.count == 1)
        let over = CatPuzzleClearFlow.progress(lives: 2, flown: 9, isKey: false, multiplied: false)
        #expect(over.hearts == 0 && over.count == 2, "飛ばした数はライフを超えない")
        let key = CatPuzzleClearFlow.progress(lives: 3, flown: 3, isKey: true, multiplied: true)
        #expect(key.count == 3 && key.multiplied)
        let notKey = CatPuzzleClearFlow.progress(lives: 3, flown: 3, isKey: false, multiplied: true)
        #expect(!notKey.multiplied, "鍵の面でなければ ×2 は掛からない")
    }

    @Test("段の長さ: Reduce Motion は余韻だけ、鍵の面は ×2 のぶん長い")
    func durations() {
        let normal = CatPuzzleClearFlow.livesDuration(lives: 3, isKey: false, reduceMotion: false)
        let key = CatPuzzleClearFlow.livesDuration(lives: 3, isKey: true, reduceMotion: false)
        let reduced = CatPuzzleClearFlow.livesDuration(lives: 3, isKey: true, reduceMotion: true)
        #expect(reduced == CatPuzzleClearFlow.hold)
        #expect(key > normal && normal > reduced)
    }

    @Test("順位の読み込みが終わらなくても、上限で諦めて nil を返す（待たせない）")
    func rankTimeout() async {
        let rank = await CatPuzzleClearFlow.loadRank(timeout: .milliseconds(200)) {
            try? await Task.sleep(for: .seconds(30))
            return 1
        }
        #expect(rank == nil)
    }

    @Test("順位が読めたらそのまま返す。読めなかったとき（失敗）は nil")
    func rankLoaded() async {
        #expect(await CatPuzzleClearFlow.loadRank { 2 } == 2)
        #expect(await CatPuzzleClearFlow.loadRank { nil } == nil)
    }

    @Test("上位 3 位だけ特典の予告が付く")
    func top3() {
        #expect(CatPuzzleClearFlow.Standing(total: 6, rank: 3).isTop3)
        #expect(!CatPuzzleClearFlow.Standing(total: 6, rank: 4).isTop3)
        #expect(!CatPuzzleClearFlow.Standing(total: 6, rank: nil).isTop3)
    }

    // MARK: ランキングの段の順位表（#3327）

    private func row(_ id: String, _ score: Int, rank: Int, me: Bool = false) -> GameCenterBoardRow {
        GameCenterBoardRow(id: id, name: id, score: score, rank: rank, isMe: me)
    }

    private func board(_ rows: [GameCenterBoardRow], myRank: Int?, myScore: Int?) -> GameCenterBoard {
        GameCenterBoard(rows: rows, myRank: myRank, myScore: myScore, participants: rows.count,
                        start: nil, end: nil, lastWeekRank: nil)
    }

    /// 自分は 6 pt で 4 位。送る前の 3 pt なら 7 位だった。
    private var after: GameCenterBoard {
        board([row("a", 12, rank: 1), row("b", 9, rank: 2), row("c", 7, rank: 3), row("me", 6, rank: 4, me: true),
               row("d", 5, rank: 5), row("e", 4, rank: 6), row("f", 3, rank: 7)], myRank: 4, myScore: 6)
    }

    @Test("送る前の合計から今回の pt を足した順位へ、自分の行が上がる。抜いた人数も数える")
    func rankingMotionMovesUp() throws {
        let result = try #require(CatPuzzleClearFlow.result(board: after, beforeTotal: 3))
        let motion = try #require(result.motion)
        #expect(motion.entries.map(\.id) == ["a", "b", "c", "d", "e", "f", "me"])
        #expect(motion.entries.last?.score == 3)
        #expect(motion.from == 6 && motion.to == 3)
        #expect(motion.newScore == 6)
        #expect(result.passedCount == 3)
        #expect(result.showsTable)
        #expect(result.rank == 4)
        #expect(!result.isTop3)
    }

    @Test("順位が変わらなくても pt が増えたら数え上げだけ流す（抜いた人は 0）")
    func rankingMotionCountUpOnly() throws {
        let gap = board([row("a", 12, rank: 1), row("b", 9, rank: 2), row("c", 7, rank: 3),
                         row("me", 6, rank: 4, me: true), row("d", 4, rank: 5)], myRank: 4, myScore: 6)
        let result = try #require(CatPuzzleClearFlow.result(board: gap, beforeTotal: 5))
        let motion = try #require(result.motion)
        #expect(motion.from == 3 && motion.to == 3)
        #expect(result.passedCount == 0)
    }

    @Test("上位 3 位に入ったら特典の予告の対象")
    func rankingTop3() throws {
        let top = board([row("a", 5, rank: 1), row("me", 4, rank: 2, me: true)], myRank: 2, myScore: 4)
        #expect(try #require(CatPuzzleClearFlow.result(board: top, beforeTotal: 0)).isTop3)
    }

    @Test("上位の外・順位表が読めない・pt が伸びていないときは、表のアニメを出さず今までの 1 行へ戻る")
    func rankingFallsBack() throws {
        let outside = board([row("a", 50, rank: 1)], myRank: 40, myScore: 3)
        let out = try #require(CatPuzzleClearFlow.result(board: outside, beforeTotal: 1))
        #expect(!out.showsTable && out.motion == nil)
        #expect(out.rank == 40)
        #expect(CatPuzzleClearFlow.result(board: nil, beforeTotal: 1) == nil)
        let flat = try #require(CatPuzzleClearFlow.result(board: after, beforeTotal: 6))
        #expect(flat.motion == nil)
        #expect(flat.showsTable)
    }

    @Test("送る前の位置が表の外かもしれないときは、抜いた人数を出さない（数えきれない）")
    func passedCountHiddenWhenStartMayBeOffTable() throws {
        // 自分は 4 位（pt 50）。送る前の合計が 3 pt なら、表の中の誰よりも下から始まる。
        let rows = (0..<10).map { i in i == 3 ? row("me", 50, rank: 4, me: true) : row("p\(i)", 100 - i, rank: i + 1) }
        func board(participants: Int) -> GameCenterBoard {
            GameCenterBoard(rows: rows, myRank: 4, myScore: 50, participants: participants,
                            start: nil, end: nil, lastWeekRank: nil)
        }
        let crowded = try #require(CatPuzzleClearFlow.result(board: board(participants: 40), beforeTotal: 3))
        #expect(crowded.motion != nil)
        #expect(crowded.passedCount == 0)
        // 参加者が全員表に載っているなら、最下段から始まっても数えられる。
        let small = try #require(CatPuzzleClearFlow.result(board: board(participants: 10), beforeTotal: 3))
        #expect(small.passedCount == 6)
    }

    @Test("入れ替えを流すときは、流し終わるまで次へ進まない。動きを省くときは短い")
    func rankingDuration() throws {
        let motion = try #require(CatPuzzleClearFlow.result(board: after, beforeTotal: 3)?.motion)
        let moving = CatPuzzleClearFlow.rankingDuration(motion: motion, reduceMotion: false)
        let still = CatPuzzleClearFlow.rankingDuration(motion: motion, reduceMotion: true)
        #expect(moving > .seconds(RankingMotion.duration))
        #expect(still < moving)
        #expect(CatPuzzleClearFlow.rankingDuration(motion: nil, reduceMotion: false) == still)
    }

    @Test("餌をあげると、おびき出された猫のマスに餌の皿の印が付き、片付けると消える。新しい局には持ち越さない")
    func lure() async {
        let model = makeModel()
        model.startStage(1)
        await model.stagePreparation?.value
        #expect(model.lureCell == nil)
        model.teachCat()
        let placed = model.marks.indices.filter { model.marks[$0] == .cat }
        #expect(placed.count == 1 && model.lureCell == placed.first)
        let token = model.lureToken
        model.clearLure()
        #expect(model.lureCell == nil)
        model.teachCat()
        #expect(model.lureToken == token + 1, "続けてあげても待ちを数え直す")
        model.newGame(size: .easy)
        #expect(model.lureCell == nil)
    }
}
