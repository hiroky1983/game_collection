import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameOjisanPuzzle

/// 遊び方（腰痛モード / パズルモード・#1920）ごとの終わり方・記録・解析。
@Suite("腰痛おじさんパズルの遊び方")
@MainActor
struct OjisanPuzzleModeTests {
    private func services(_ log: PlayLog? = nil) -> GameServices {
        GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
    }

    private func makePlayLog(_ name: String) throws -> (PlayLog, () -> Void) {
        let suite = "asobiba.ojisanpuzzle.tests.\(name)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (PlayLog(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
    }

    /// 1 を 4 つそろえて消える盤（左下に 3 つ、その右に落とす）。
    private func almostClearBoard(extraHigh: Bool) -> [[Int]] {
        var board = OjisanPuzzleBoard.emptyBoard()
        let bottom = OjisanPuzzleBoard.rows - 1
        board[bottom][0] = 1; board[bottom][1] = 1; board[bottom][2] = 1
        if extraHigh {
            // ライン上に届く柱を右端に立てる（隣り合わない種類を交互に積み、勝手に消えない・落ちない）。
            for (index, row) in ((OjisanPuzzleCleanup.clearLineRow - 1)...bottom).enumerated() {
                board[row][5] = index % 2 == 0 ? 3 : 4
            }
        }
        return board
    }

    // MARK: - 盤の作り方

    @Test("腰痛モードは最初から荷物が積まれ、4つつながる塊も、クリア済みもない")
    func backpainStartsWithLuggage() {
        for seed in UInt64(1)...40 {
            let model = OjisanPuzzleModel(services: nil, mode: .backpain, seed: seed)
            #expect(model.board.joined().contains { $0 != 0 })
            #expect(OjisanPuzzleBoard.isValid(model.board))
            #expect(OjisanPuzzleBoard.clearableGroups(model.board).isEmpty, "seed \(seed)")
            #expect(!OjisanPuzzleCleanup.isCleared(model.board), "seed \(seed)")
            #expect(model.clearLineRow == OjisanPuzzleCleanup.clearLineRow)
        }
    }

    @Test("パズルモードは空の盤で始まり、ラインもせり上がりも無い")
    func puzzleStartsEmpty() {
        let model = OjisanPuzzleModel(services: nil, mode: .puzzle, seed: 7)
        #expect(model.board == OjisanPuzzleBoard.emptyBoard())
        #expect(model.clearLineRow == nil)
        #expect(model.millisecondsUntilRise == nil)
    }

    @Test("同じ種なら同じ初期配置になる")
    func initialBoardIsDeterministic() {
        let a = OjisanPuzzleModel(services: nil, mode: .backpain, seed: 99)
        let b = OjisanPuzzleModel(services: nil, mode: .backpain, seed: 99)
        #expect(a.board == b.board)
    }

    // MARK: - ゲージ

    @Test("パズルモードにはゲージが無く、固定しても増えず入院もしない")
    func puzzleHasNoGauge() {
        let model = OjisanPuzzleModel(
            services: nil, board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            pain: 0, mode: .puzzle
        )
        #expect(model.hardDrop())
        #expect(model.pain == 0)
        #expect(model.outcome == nil)
        // 操作の遅れも落下の加速も、ゲージ由来のものは起きない。
        #expect(model.dropInterval == OjisanPuzzleModel.baseDropInterval)
    }

    @Test("パズルモードの落下は固定した組数に応じて速くなり、下限で止まる")
    func puzzleSpeedsUp() {
        #expect(OjisanPuzzleSpeedUp.factor(locks: 0) == 1.0)
        #expect(OjisanPuzzleSpeedUp.factor(locks: OjisanPuzzleSpeedUp.locksPerLevel) < 1.0)
        #expect(OjisanPuzzleSpeedUp.factor(locks: 100_000) == OjisanPuzzleSpeedUp.minimumFactor)
    }

    // MARK: - 腰痛モードの終わり方

    @Test("ライン以下まで片付いたらクリア（勝ち）で、クリアタイムを記録する")
    func backpainClearsBelowLine() throws {
        let (log, cleanup) = try makePlayLog("clear")
        defer { cleanup() }
        // 1 を落として 4 つそろえて消すと、盤が空になる（ライン以下）。
        let model = OjisanPuzzleModel(
            services: services(log), board: almostClearBoard(extraHigh: false),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 3, rotation: .up),
            mode: .backpain, clearLineRow: OjisanPuzzleCleanup.clearLineRow
        )
        #expect(model.hardDrop())
        // 時計を進めておく（落下ループの刻みが elapsed に積まれる）。
        for _ in 0..<40 { model.tick() }
        #expect(model.outcome == .cleared)
        let record = try #require(log.record(gameID: "ojisanpuzzle", variant: "backpain"))
        #expect(record.metric == .shortestTime)
        #expect(record.wins == 1)
        #expect(record.bestSeconds == max(1, model.elapsedMilliseconds / 1000))
        #expect((record.bestSeconds ?? 0) >= 1)
    }

    @Test("ラインより上に荷物が残っていれば、片付いたことにはならない")
    func backpainNotClearedWhileLuggageAboveLine() {
        let model = OjisanPuzzleModel(
            services: nil, board: almostClearBoard(extraHigh: true),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 3, rotation: .up),
            mode: .backpain, clearLineRow: OjisanPuzzleCleanup.clearLineRow
        )
        #expect(model.hardDrop())
        for _ in 0..<40 { model.tick() }
        #expect(model.outcome == nil)
        #expect(model.current != nil)
        model.pause()
    }

    @Test("パズルモードには勝ちが無く、盤が空になっても終わらない")
    func puzzleNeverClears() {
        let model = OjisanPuzzleModel(
            services: nil, board: almostClearBoard(extraHigh: false),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 3, rotation: .up),
            mode: .puzzle
        )
        #expect(model.hardDrop())
        for _ in 0..<40 { model.tick() }
        #expect(model.outcome == nil)
        #expect(model.score > 0)
        model.pause()
    }

    @Test("時間が来ると、次の組を出す前に荷物が 1 段せり上がる")
    func risesOverTime() {
        var board = OjisanPuzzleBoard.emptyBoard()
        board[OjisanPuzzleBoard.rows - 1][0] = 2
        let model = OjisanPuzzleModel(
            services: nil, board: board,
            current: OjisanPuzzlePair(axisKind: 1, childKind: 3, row: 1, col: 3, rotation: .up),
            mode: .backpain, riseIntervalMilliseconds: 1_000
        )
        // 落下中の刻みで時間（1 秒）を溜めてから固定すると、次の組を出す直前にせり上がる。
        model.tick(); model.tick()
        #expect(model.millisecondsUntilRise == 0)
        #expect(model.hardDrop())
        for _ in 0..<40 where model.current == nil { model.tick() }
        let bottom = OjisanPuzzleBoard.rows - 1
        #expect(model.board[bottom].allSatisfy { $0 != 0 }, "最下段は荷物で埋まる")
        #expect(model.board[bottom - 1][0] == 2, "元の荷物は 1 段上がる")
        #expect(OjisanPuzzleBoard.clearableGroups(model.board).isEmpty, "せり上がりで勝手に消えない")
        #expect(model.outcome == nil)
        model.pause()
    }

    @Test("せり上がりで一番上の行から荷物が押し出されたら埋まりで終わる")
    func risingPushesOutTopRow() {
        var rng = OjisanPuzzleRandom(seed: 3)
        var board = OjisanPuzzleBoard.emptyBoard()
        board[0][4] = 2
        let risen = OjisanPuzzleCleanup.rising(board, using: &rng)
        #expect(risen.overflowed)
        let safe = OjisanPuzzleCleanup.rising(OjisanPuzzleBoard.emptyBoard(), using: &rng)
        #expect(!safe.overflowed)
        #expect(OjisanPuzzleBoard.isValid(safe.board))
    }

    @Test("せり上がりの新しい最下段は4つつながる塊を作らない")
    func risingRowNeverFormsClearableGroup() {
        for seed in UInt64(1)...60 {
            var rng = OjisanPuzzleRandom(seed: seed)
            var board = OjisanPuzzleCleanup.initialBoard(using: &rng)
            for _ in 0..<4 {
                board = OjisanPuzzleCleanup.rising(board, using: &rng).board
                #expect(OjisanPuzzleBoard.clearableGroups(board).isEmpty, "seed \(seed)")
            }
        }
    }

    // MARK: - 局のあいだは遊び方を変えない

    @Test("もう一度は同じ遊び方で、mode を渡したときだけ替わる（時間・ラインも作り直す）")
    func newGameKeepsOrSwitchesMode() {
        let model = OjisanPuzzleModel(services: nil, mode: .backpain, seed: 5)
        for _ in 0..<5 { model.tick() }
        #expect(model.elapsedMilliseconds > 0)
        model.newGame()
        model.pause()
        #expect(model.mode == .backpain)
        #expect(model.elapsedMilliseconds == 0)
        #expect(model.clearLineRow != nil)
        model.newGame(mode: .puzzle)
        model.pause()
        #expect(model.mode == .puzzle)
        #expect(model.board == OjisanPuzzleBoard.emptyBoard())
        #expect(model.clearLineRow == nil)
        #expect(model.pain == 0)
    }

    // MARK: - 記録（モード別）

    @Test("パズルモードの自己ベストは得点で、腰痛モードの記録とは別の行になる")
    func recordsAreSeparatedPerMode() throws {
        let (log, cleanup) = try makePlayLog("separate")
        defer { cleanup() }
        let model = OjisanPuzzleModel(
            services: services(log), board: almostClearBoard(extraHigh: false),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 3, rotation: .up),
            mode: .puzzle
        )
        #expect(model.hardDrop())
        for _ in 0..<40 { model.tick() }
        model.pause()
        // 得点を作ったあと、埋まらせて終わらせる代わりに直接 newGame で捨てず、決着の入口だけ確かめる。
        let puzzleScore = model.score
        #expect(puzzleScore > 0)

        // 埋まりで終わらせる: 左上の 2 マス以外を、隣り合うマスが別の種類になる並びで全面埋めた盤。
        func kind(_ row: Int, _ col: Int) -> Int { (row + 2 * col) % 5 + 1 }
        var full = OjisanPuzzleBoard.emptyBoard()
        for row in 0..<OjisanPuzzleBoard.rows {
            for col in 0..<OjisanPuzzleBoard.columns { full[row][col] = kind(row, col) }
        }
        full[0][0] = 0
        full[1][0] = 0
        let ending = OjisanPuzzleModel(
            services: services(log), board: full,
            current: OjisanPuzzlePair(axisKind: kind(1, 0), childKind: kind(0, 0), row: 1, col: 0, rotation: .up),
            mode: .puzzle
        )
        #expect(ending.hardDrop())
        ending.tick()
        #expect(ending.outcome == .buried)

        let puzzle = try #require(log.record(gameID: "ojisanpuzzle", variant: "puzzle"))
        #expect(puzzle.metric == .points)
        #expect(puzzle.losses == 1)
        #expect(log.record(gameID: "ojisanpuzzle", variant: "backpain") == nil)
        #expect(log.record(gameID: "ojisanpuzzle") == nil, "区分なしの行は作らない")
    }

    // MARK: - 解析

    @Test("game_start / game_end に mode が載り、捨てた局の quit は前の mode を持つ")
    func analyticsCarriesMode() {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["ojisanpuzzle"])
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        let model = OjisanPuzzleModel(services: services, mode: .backpain, seed: 11)
        #expect(model.hardDrop())            // 1 組置いた局を
        model.newGame(mode: .puzzle)         // 別の遊び方で始め直す
        model.pause()

        let modes = spy.events.compactMap { event -> (String, AnalyticsMode?)? in
            switch event {
            case let .gameStart(_, _, mode, _, _): ("start", mode)
            case let .gameEnd(_, _, _, mode, _, _, _, _): ("end", mode)
            default: nil
            }
        }
        #expect(modes.map(\.0) == ["start", "end", "start"])
        #expect(modes.map(\.1) == [.backpain, .backpain, .puzzle])
    }

    @Test("開始シートの前（announcesStart: false）は game_start を送らず、選んだあとに 1 回だけ送る")
    func startIsDeferredUntilModeIsChosen() {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["ojisanpuzzle"])
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        let model = OjisanPuzzleModel(services: services, announcesStart: false)
        #expect(spy.starts.isEmpty)
        model.newGame(mode: .puzzle)   // 選び直して始める
        model.pause()
        #expect(spy.starts == ["ojisanpuzzle"])
        model.announceStartIfNeeded()  // 冪等
        #expect(spy.starts == ["ojisanpuzzle"])
        // 選ばずに閉じた場合は、既定の遊び方で 1 回だけ送る（別の計測器で確かめる）。
        let spy2 = SpyAnalyticsService()
        let services2 = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy2, allowedGameIDs: ["ojisanpuzzle"]))
        let kept = OjisanPuzzleModel(services: services2, announcesStart: false)
        kept.announceStartIfNeeded()
        kept.announceStartIfNeeded()
        #expect(spy2.starts == ["ojisanpuzzle"])
    }

    @Test("時計は操作で段階が変わっても、渡された経過時間だけ進む")
    func clockAdvancesByElapsedPassedToTick() {
        let model = OjisanPuzzleModel(
            services: nil, board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            mode: .backpain, riseIntervalMilliseconds: 10_000
        )
        #expect(model.hardDrop())      // 落下中の待ちの途中で固定され、段階が後片付けに替わった
        model.tick(elapsed: OjisanPuzzleModel.baseDropInterval)   // 待っていた 620ms ぶん
        #expect(model.elapsedMilliseconds == OjisanPuzzleModel.baseDropInterval)
        #expect(model.millisecondsUntilRise == 10_000 - OjisanPuzzleModel.baseDropInterval)
        model.pause()
    }
}
