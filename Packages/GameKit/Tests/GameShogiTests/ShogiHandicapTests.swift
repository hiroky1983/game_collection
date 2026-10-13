import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameShogi

/// 将棋の駒落ち（飛車落ち・角落ち。自分が落とす／CPU が落とす・#2179）。
@MainActor
@Suite("将棋 駒落ち（#2179）")
struct ShogiHandicapTests {

    private func makeServices(
        _ store: MemorySnapshotStore = MemorySnapshotStore(), spy: SpyAnalyticsService? = nil, log: PlayLog? = nil
    ) -> GameServices {
        let analytics = spy.map { GameAnalytics(service: $0, allowedGameIDs: ["shogi"]) }
        return GameServices(snapshots: store, ads: NoopAdService(), playLog: log, analytics: analytics)
    }

    private func count(_ pos: Position, _ type: PieceType, _ color: Side) -> Int {
        pos.squares.compactMap { $0 }.filter { $0.type == type && $0.color == color }.count
    }

    // MARK: - 初期局面

    @Test("飛車落ちは上手（後手）の飛車だけが無く、下手は全部そろう")
    func rookHandicapPosition() throws {
        let pos = try #require(Position.fromSFEN(ShogiHandicap.rook.initialSFEN))
        #expect(count(pos, .rook, .white) == 0)
        #expect(count(pos, .bishop, .white) == 1)
        #expect(count(pos, .rook, .black) == 1)
        #expect(count(pos, .bishop, .black) == 1)
        #expect(pos.squares.compactMap { $0 }.count == 40 - 1)
    }

    @Test("角落ちは上手（後手）の角だけが無い")
    func bishopHandicapPosition() throws {
        let pos = try #require(Position.fromSFEN(ShogiHandicap.bishop.initialSFEN))
        #expect(count(pos, .bishop, .white) == 0)
        #expect(count(pos, .rook, .white) == 1)
        #expect(count(pos, .bishop, .black) == 1)
        #expect(pos.squares.compactMap { $0 }.count == 40 - 1)
    }

    @Test("駒を落とした側（上手）が先に指す。平手は先手から")
    func upperPlayerMovesFirst() throws {
        #expect(try #require(Position.fromSFEN(ShogiHandicap.rook.initialSFEN)).sideToMove == .white)
        #expect(try #require(Position.fromSFEN(ShogiHandicap.bishop.initialSFEN)).sideToMove == .white)
        #expect(Position.start().sideToMove == .black)
    }

    @Test("駒落ちの SFEN は往復でき、手合いに戻せる")
    func detectRoundTrips() throws {
        for handicap in ShogiHandicap.allCases {
            let pos = try #require(Position.fromSFEN(handicap.initialSFEN))
            #expect(pos.toSFEN() == handicap.initialSFEN)
            #expect(ShogiHandicap.detect(initialSFEN: handicap.initialSFEN) == handicap)
        }
        #expect(ShogiHandicap.detect(initialSFEN: "9/9/9/9/9/9/9/9/9 b - 1") == .even)
    }

    // MARK: - Model

    @Test("自分が落とすと、自分は後手の位置で先に指す")
    func playerDropsMovesFirst() {
        let model = ShogiGameModel(services: makeServices())
        model.newGame(humanSide: .black, aiLevel: 1, handicap: .rook, dropper: .player)
        #expect(model.humanSide == .white, "humanSide 引数より落とす側が優先される")
        #expect(model.position.sideToMove == .white)
        #expect(!model.isAITurn, "上手の自分が先に指す")
        #expect(model.matchSetting == ShogiMatchSetting(handicap: .rook, dropper: .player))
        #expect(!model.legalMovesCache.isEmpty)
    }

    @Test("CPU が落とすと、CPU が先に指す")
    func cpuDropsMovesFirst() {
        let model = ShogiGameModel(services: makeServices())
        model.newGame(humanSide: .white, aiLevel: 1, handicap: .bishop, dropper: .cpu)
        #expect(model.humanSide == .black)
        #expect(model.position.sideToMove == .white)
        #expect(model.isAITurn, "上手の CPU が先に指す")
        #expect(model.matchSetting == ShogiMatchSetting(handicap: .bishop, dropper: .cpu))
    }

    @Test("平手の先後の選択は従来どおり")
    func evenKeepsSideChoice() {
        let model = ShogiGameModel(services: makeServices())
        model.newGame(humanSide: .white, aiLevel: 1)
        #expect(model.humanSide == .white)
        #expect(model.initialSFEN == Position.startSFEN)
        #expect(model.matchSetting.handicap == .even)
        #expect(model.isAITurn, "後手を選ぶと先手の CPU が先に指す")
    }

    @Test("手合いは中断データに残り、続きから再開しても保たれる")
    func handicapSurvivesResume() async throws {
        let store = MemorySnapshotStore()
        let model = ShogiGameModel(services: makeServices(store))
        model.newGame(humanSide: .black, aiLevel: 1, handicap: .rook, dropper: .cpu)
        await model.performAIMoveIfNeeded()  // CPU（上手）の初手
        #expect(model.moves.count == 1)

        let restored = ShogiGameModel(services: makeServices(store))
        #expect(restored.initialSFEN == ShogiHandicap.rook.initialSFEN)
        #expect(restored.matchSetting == ShogiMatchSetting(handicap: .rook, dropper: .cpu))
        #expect(restored.moves == model.moves)
        #expect(restored.position == model.position)
        #expect(restored.humanSide == .black)
        #expect(!restored.isAITurn, "CPU の初手のあとは自分の番")
    }

    @Test("駒落ちの局を始め直すと、次の平手に手合いが持ち越されない")
    func evenAfterHandicap() {
        let model = ShogiGameModel(services: makeServices())
        model.newGame(humanSide: .black, aiLevel: 1, handicap: .bishop, dropper: .player)
        model.newGame(humanSide: .black, aiLevel: 1)
        #expect(model.initialSFEN == Position.startSFEN)
        #expect(model.position == Position.start())
        #expect(model.matchSetting.handicap == .even)
    }

    @Test("駒落ちで千日手の判定が初形（平手）の局面を使わない")
    func repetitionUsesHandicapStart() async throws {
        let model = ShogiGameModel(services: makeServices())
        model.newGame(humanSide: .black, aiLevel: 1, handicap: .rook, dropper: .player)
        // 開始局面から指し手を再生した局面が、表示の局面と一致する。
        let replayed = model.positionAt(ply: 0)
        #expect(replayed.toSFEN() == ShogiHandicap.rook.initialSFEN)
    }

    @Test("待ったは自分の直前手と CPU の応手を戻す（上手が先に指す駒落ちでも）")
    func undoWorksWithWhiteFirst() async throws {
        for dropper in ShogiHandicapDropper.allCases {
            let model = ShogiGameModel(services: makeServices())
            model.newGame(humanSide: .black, aiLevel: 1, handicap: .rook, dropper: dropper)
            if dropper == .cpu { await model.performAIMoveIfNeeded() }
            // 自分の初手（合法手の先頭）
            let first = try #require(model.legalMovesCache.first)
            model.apply(first)
            await model.performAIMoveIfNeeded()
            let expected = dropper == .cpu ? 3 : 2
            #expect(model.moves.count == expected)
            #expect(model.canUndo)
            model.undoLastExchange()
            #expect(model.moves.count == expected - 2)
            #expect(!model.isAITurn, "戻したあとは自分の番")
        }
    }

    // MARK: - CPU

    @Test("CPU は上手でも下手でも合法手を返す（落とした駒が無い前提で探索が壊れない）")
    func engineReturnsLegalMoves() async throws {
        for handicap in [ShogiHandicap.rook, .bishop] {
            let pos = try #require(Position.fromSFEN(handicap.initialSFEN))
            let legal = Set(pos.legalMoves().map(\.usi))
            // 上手（後手番）で指す
            let upper = await SimpleMinimaxEngine(level: 1).bestMove(sfen: handicap.initialSFEN)
            #expect(upper != nil && legal.contains(upper!))
            // 下手（先手番）で指す: 上手が 1 手指した後の局面
            var after = pos
            after.make(try #require(pos.legalMoves().first))
            let lower = await SimpleMinimaxEngine(level: 1).bestMove(sfen: after.toSFEN())
            #expect(lower != nil && Set(after.legalMoves().map(\.usi)).contains(lower!))
        }
    }

    @Test("定跡は平手の初形からの手順なので、駒落ちの局面には当たらない")
    func bookDoesNotApplyToHandicap() {
        #expect(OpeningBook.move(for: ShogiHandicap.rook.initialSFEN) == nil)
        #expect(OpeningBook.move(for: ShogiHandicap.bishop.initialSFEN) == nil)
        #expect(OpeningBook.move(for: Position.startSFEN) != nil, "前提: 平手の初形には定跡がある")
    }

    @Test("駒落ちの対局を CPU 同士で指し進めても、合法手が尽きるまで壊れない")
    func selfPlayStaysLegal() async throws {
        for handicap in [ShogiHandicap.rook, .bishop] {
            var pos = try #require(Position.fromSFEN(handicap.initialSFEN))
            for _ in 0..<12 {
                guard !pos.legalMoves().isEmpty else { break }
                let usi = try #require(await SimpleMinimaxEngine(level: 1).bestMove(sfen: pos.toSFEN()))
                let move = try #require(Move.fromUSI(usi))
                #expect(pos.legalMoves().contains(move))
                pos.make(move)
            }
        }
    }

    // MARK: - 記録・解析

    @Test("記録は手合い×落とす側で分かれ、平手は従来の保存先のまま")
    func recordsSplitByHandicap() throws {
        let name = "asobiba.shogi.handicap.tests"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let model = ShogiGameModel(services: makeServices(log: log))

        model.newGame(humanSide: .black, aiLevel: 1, handicap: .rook, dropper: .player)
        model.resign()
        model.newGame(humanSide: .black, aiLevel: 1, handicap: .rook, dropper: .cpu)
        model.resign()
        model.newGame(humanSide: .black, aiLevel: 1)
        model.resign()

        #expect(log.record(gameID: "shogi", variant: "rook-player")?.plays == 1)
        #expect(log.record(gameID: "shogi", variant: "rook-cpu")?.plays == 1)
        #expect(log.record(gameID: "shogi")?.plays == 1, "平手は区分なしの従来の記録")
        #expect(log.record(gameID: "shogi", variant: "rook-player")?.variantLabel == "飛車落ち・自分が落とす")
        #expect(log.record(gameID: "shogi")?.variantLabel == nil)
    }

    @Test("解析の mode に手合いと落とす側が入り、game_start と game_end で同じ値になる")
    func analyticsModeCarriesHandicap() {
        let spy = SpyAnalyticsService()
        let model = ShogiGameModel(services: makeServices(spy: spy))
        model.newGame(humanSide: .black, aiLevel: 1, handicap: .bishop, dropper: .cpu)
        model.resign()

        let starts = spy.events.compactMap { if case .gameStart = $0 { return $0.parameters } else { return nil } }
        let ends = spy.events.compactMap { if case .gameEnd = $0 { return $0.parameters } else { return nil } }
        #expect(starts.first?["mode"] == .string("bishop_cpu"))
        #expect(ends.first?["mode"] == .string("bishop_cpu"))
    }

    @Test("手合いごとの mode は英字の 5 値")
    func modeValues() {
        let all = ShogiHandicap.allCases.flatMap { handicap in
            ShogiHandicapDropper.allCases.map { ShogiMatchSetting(handicap: handicap, dropper: $0).analyticsMode }
        }
        #expect(Set(all.map(\.rawValue)) == ["even", "rook_player", "rook_cpu", "bishop_player", "bishop_cpu"])
    }

    // MARK: - KIF

    @Test("KIF の手合割は手合いの名前で書く")
    func kifHeader() {
        #expect(KIF.handicapHeader(.even) == "手合割：平手")
        #expect(KIF.handicapHeader(.rook) == "手合割：飛車落ち")
        #expect(KIF.handicapHeader(.bishop) == "手合割：角落ち")
    }

    @Test("駒落ちの先頭の手は △（上手）で表記される")
    func firstMoveMarkIsWhite() throws {
        let model = ShogiGameModel(services: makeServices())
        model.newGame(humanSide: .black, aiLevel: 1, handicap: .rook, dropper: .player)
        let move = try #require(Move.fromUSI("5c5d"))
        #expect(model.legalMovesCache.contains(move))
        model.apply(move)
        #expect(model.highlightedMoveText?.hasPrefix("△") == true)
    }
}
