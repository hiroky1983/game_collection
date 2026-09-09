import Testing
import Foundation
import Core
@testable import GameChess

private func sq(_ name: String) -> Int { ChessSquare.fromName(Substring(name))! }

final class MockChessSnapshotStore: Core.SnapshotStore, @unchecked Sendable {
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

func makeChessServices(_ store: MockChessSnapshotStore) -> GameServices {
    GameServices(snapshots: store, ads: NoopAdService())
}

/// 人間の指し手を「駒を選ぶ → 着手先をタップ」で入れる（View の操作と同じ経路）。
@MainActor
private func tapMove(_ model: ChessGameModel, _ uci: String) {
    let move = ChessMove.fromUCI(uci)!
    model.tapSquare(move.from)
    model.tapSquare(move.to)
}

@MainActor
@Suite("チェス 対局モデル（人間→CPU の流れ）")
struct ChessGameModelTests {

    @Test("人間が指すと CPU が応手する")
    func humanMoveThenAIReplies() async {
        let model = ChessGameModel(services: nil)
        // 既定は人間=白 / CPU=黒。
        #expect(model.humanSide == .white)
        #expect(model.isAITurn == false)

        model.tapSquare(sq("e2"))
        #expect(model.selectedSquare == sq("e2"))
        model.tapSquare(sq("e4"))
        #expect(model.moves.count == 1)
        #expect(model.moves.last?.uci == "e2e4")

        #expect(model.isAITurn)
        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 2)
        #expect(model.gameOver == false)
        #expect(model.isAITurn == false)
    }

    @Test("CPU の手番中は人間の操作を受け付けない")
    func humanCannotMoveDuringCPUTurn() {
        let model = ChessGameModel(services: nil)
        tapMove(model, "e2e4")
        #expect(model.isAITurn)
        let before = model.moves.count
        model.tapSquare(sq("e7")) // 黒のポーン
        #expect(model.selectedSquare == nil)
        model.tapSquare(sq("e5"))
        #expect(model.moves.count == before)
    }

    @Test("黒を選ぶと CPU が初手を指す（手数 0 でもトリガーが変わる）")
    func newGameAsBlackMakesAIMoveFirst() async {
        let model = ChessGameModel(services: nil)
        let before = model.aiTurnKey
        model.newGame(humanSide: .black)
        #expect(model.moves.isEmpty)
        #expect(model.aiTurnKey != before, "手数 0 のままでもキーは変わる（将棋 #82 と同じ穴）")
        #expect(model.isAITurn)
        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 1)
        #expect(model.isAITurn == false)
    }

    @Test("待ったは人間と CPU の 2 手をまとめて戻す")
    func undoRemovesBothMoves() async {
        let model = ChessGameModel(services: nil)
        tapMove(model, "e2e4")
        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 2)
        #expect(model.canUndo)
        #expect(model.undoUsed == false)

        model.undoLastExchange()
        #expect(model.moves.isEmpty)
        #expect(model.undoUsed, "2回目以降は広告が要る印")
        #expect(model.isAITurn == false)
        #expect(model.canUndo == false)
        #expect(model.position.squares[sq("e4")] == nil)
        #expect(model.position == ChessPosition.start(), "初期局面に完全に戻る")
    }

    @Test("投了すると自分の負けになり、検討へ移る")
    func resignEndsGameAsLoss() {
        let model = ChessGameModel(services: nil)
        tapMove(model, "e2e4")
        model.resign()
        #expect(model.gameOver)
        #expect(model.result == .resignation(loser: .white))
        #expect(model.phase == .review)
        #expect(model.resultText?.contains("あなたの負け") == true)
    }

    // MARK: - プロモーション

    @Test("最奥段へ届くと成り先の選択待ちになり、選ぶと着手される")
    func promotionAsksThenApplies() {
        let store = MockChessSnapshotStore()
        // 白ポーンが e7 に居て、e8 は空・d8 に黒ルーク（前進でも取りでも成れる）。人間=白。
        try? store.save(ChessSnapshot(
            initialFen: "k2r4/4P3/8/8/8/8/8/6K1 w - - 0 1",
            moves: [], phase: .playing, reviewPly: nil,
            white: .human, black: .ai, aiLevel: 0, startedAt: Date(), undoUsed: false
        ), for: "chess")
        let model = ChessGameModel(services: makeChessServices(store))

        model.tapSquare(sq("e7"))
        #expect(model.legalTargets.contains(sq("d8")), "d8 へも成れる")
        model.tapSquare(sq("d8"))
        #expect(model.pendingPromotion != nil, "4 通りあるので選ばせる")
        #expect(model.moves.isEmpty, "選ぶまでは着手しない")

        model.resolvePromotion(.knight)
        #expect(model.pendingPromotion == nil)
        #expect(model.moves.last?.uci == "e7d8n")
        #expect(model.position.squares[sq("d8")] == ChessPiece(type: .knight, color: .white))
    }

    @Test("成り先の選択肢はクイーンが先頭で、4種すべて揃っている")
    func promotionChoicesAreOrderedByUse() {
        // 実戦のほぼ全てがクイーン成りなので、一番使う選択肢を端に置かない。
        #expect(ChessGameModel.promotionChoices.first == .queen)
        #expect(Set(ChessGameModel.promotionChoices)
                == Set(ChessPieceType.allCases.filter(\.isPromotionTarget)))
        #expect(ChessGameModel.promotionChoices.count == 4)
    }

    @Test("成りの選択をやめると着手されず、選択も解ける")
    func promotionCanBeCancelled() {
        let store = MockChessSnapshotStore()
        try? store.save(ChessSnapshot(
            initialFen: "k2r4/4P3/8/8/8/8/8/6K1 w - - 0 1",
            moves: [], phase: .playing, reviewPly: nil,
            white: .human, black: .ai, aiLevel: 0, startedAt: Date(), undoUsed: false
        ), for: "chess")
        let model = ChessGameModel(services: makeChessServices(store))
        model.tapSquare(sq("e7"))
        model.tapSquare(sq("e8"))
        #expect(model.pendingPromotion != nil)

        model.cancelPromotion()
        #expect(model.pendingPromotion == nil)
        #expect(model.selectedSquare == nil)
        #expect(model.moves.isEmpty)
    }
}

// MARK: - 決着の判定

@MainActor
@Suite("チェス 決着の判定")
struct ChessResultTests {

    /// 指定の局面から人間だけで指し進める（CPU は動かさない）モデルを作る。
    private func model(fen: String, moves: [String] = []) -> ChessGameModel {
        let store = MockChessSnapshotStore()
        try? store.save(ChessSnapshot(
            initialFen: fen, moves: moves, phase: .playing, reviewPly: nil,
            white: .human, black: .human, aiLevel: nil, startedAt: Date(), undoUsed: false
        ), for: "chess")
        return ChessGameModel(services: makeChessServices(store))
    }

    @Test("チェックメイトで決着する")
    func checkmateEndsGame() {
        let m = model(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
        m.apply(ChessMove.fromUCI("a1a8")!)
        #expect(m.gameOver)
        #expect(m.result == .checkmate(loser: .black))
        #expect(m.phase == .review)
    }

    @Test("ステイルメイトは引き分けで決着する（負けにしない）")
    func stalemateIsDraw() {
        // 白番。Qf7 で黒が動けなくなるが王手ではない。
        let m = model(fen: "7k/8/6K1/5Q2/8/8/8/8 w - - 0 1")
        m.apply(ChessMove.fromUCI("f5f7")!)
        #expect(m.result == .stalemate)
        #expect(m.result?.isDraw == true)
        #expect(m.resultText?.contains("引き分け") == true)
    }

    @Test("50手ルールで引き分けになる")
    func fiftyMoveRuleIsDraw() {
        // 99 半手まで進んだ状態から 1 手指すと 100 に達する。
        let m = model(fen: "4k3/8/8/8/8/8/R7/4K3 w - - 99 60")
        #expect(m.gameOver == false)
        m.apply(ChessMove.fromUCI("a2a3")!)
        #expect(m.position.halfmoveClock == 100)
        #expect(m.result == .fiftyMoveRule)
    }

    @Test("同じ局面が3回現れたら引き分けになる")
    func threefoldRepetitionIsDraw() {
        // 双方のキングが同じ往復を 2 周すると、初期局面が 3 回目に現れる。
        let m = model(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
        for uci in ["e1f1", "e8f8", "f1e1", "f8e8", "e1f1", "e8f8", "f1e1"] {
            #expect(m.gameOver == false, "\(uci) の前はまだ決着していない")
            m.apply(ChessMove.fromUCI(uci)!)
        }
        m.apply(ChessMove.fromUCI("f8e8")!)
        #expect(m.result == .threefoldRepetition)
    }

    /// アンパッサン標的の正規化（CodeRabbit 指摘・Major）。
    /// 標的は 2 マス進みの直後なら**取りに行けなくても必ず立つ**ので、生の値で局面を比べると
    /// 「指せる手は全く同じなのに別の局面」と読んで反復を取り逃がす。
    @Test("取れないアンパッサン標的は同一局面の判定に影響しない")
    func threefoldIgnoresUncapturableEnPassantTarget() {
        let m = model(fen: ChessPosition.startFEN)
        // 1.Nf3 a5 で a6 に標的が立つが、白のポーンは b5 に居ないので取れない。
        // 以後ナイトとナイトを往復させると、この局面が3回現れる。
        for uci in ["g1f3", "a7a5", "f3g1", "b8c6", "g1f3", "c6b8", "f3g1", "b8c6", "g1f3"] {
            #expect(m.gameOver == false, "\(uci) の前はまだ決着していない")
            m.apply(ChessMove.fromUCI(uci)!)
        }
        m.apply(ChessMove.fromUCI("c6b8")!)
        #expect(m.result == .threefoldRepetition,
                "取れない標的の有無で別局面と読んではいけない")
    }

    @Test("取れるアンパッサン標的は別の局面として扱う")
    func effectiveEnPassantKeepsCapturableTarget() {
        // 白ポーンが b5 に居るので、a7a5 の直後は本当に取りに行ける。
        let pos = ChessPosition.fromFEN("4k3/p7/8/1P6/8/8/8/4K3 w - - 0 1")!
        var after = pos
        after.make(ChessMove.fromUCI("e1e2")!)
        after.make(ChessMove.fromUCI("a7a5")!)
        #expect(after.enPassant != nil)
        #expect(after.effectiveEnPassant() == after.enPassant, "bxa6 が指せるので標的は生きている")

        // 白ポーンが居なければ同じ標的でも実効は nil。
        let noPawn = ChessPosition.fromFEN("4k3/8/8/8/p7/8/8/4K3 w - a6 0 1")!
        #expect(noPawn.enPassant != nil)
        #expect(noPawn.effectiveEnPassant() == nil)
    }

    @Test("駒が足りなくなったら引き分けになる")
    func insufficientMaterialIsDraw() {
        // 白ルークを黒キングが取ると K vs K になる。
        let m = model(fen: "8/8/8/8/8/4k3/4R3/4K3 b - - 0 1")
        m.apply(ChessMove.fromUCI("e3e2")!)
        #expect(m.result == .insufficientMaterial)
    }

    @Test("王手が掛かるたびに合図の契機が増える（検討ナビでは増えない）")
    func checkEventFires() {
        let m = model(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
        #expect(m.checkEventID == 0)
        m.apply(ChessMove.fromUCI("a1a8")!) // 王手（詰みではない）
        #expect(m.checkedKingSquare == sq("e8"))
        #expect(m.checkEventID == 1)
        #expect(m.lastCheckedSide == .black)

        // 検討で戻ると印は消えるが、契機の番号は動かない。
        m.reviewGoTo(ply: 0)
        #expect(m.checkedKingSquare == nil)
        #expect(m.checkEventID == 1)
    }
}

// MARK: - 中断復元

@MainActor
@Suite("チェス 中断復元")
struct ChessSnapshotTests {

    @Test("指しかけの対局が手順ごと復元される")
    func resumesInProgressGame() async {
        let store = MockChessSnapshotStore()
        let first = ChessGameModel(services: makeChessServices(store))
        tapMove(first, "e2e4")
        await first.performAIMoveIfNeeded()
        let expectedMoves = first.moves.map(\.uci)
        let expectedPosition = first.position

        let resumed = ChessGameModel(services: makeChessServices(store))
        #expect(resumed.moves.map(\.uci) == expectedMoves)
        #expect(resumed.position == expectedPosition)
        #expect(resumed.humanSide == .white)
        #expect(resumed.gameOver == false)
    }

    @Test("先後の選択も復元される（黒を選んだら再開直後は CPU の番）")
    func resumesSides() {
        let store = MockChessSnapshotStore()
        let first = ChessGameModel(services: makeChessServices(store))
        first.newGame(humanSide: .black)

        let resumed = ChessGameModel(services: makeChessServices(store))
        #expect(resumed.humanSide == .black)
        #expect(resumed.isAITurn)
    }

    /// 囲碁 #426 の教訓。**復元 → 待った → 続行**の組み合わせで局面が壊れないこと。
    /// スナップショットが「盤そのもの」を持っていると、待ったで巻き戻した先の
    /// キャスリング権・アンパッサン標的・50手計数が復元できずに食い違う。
    @Test("復元 → 待った → 続行 で局面が壊れない")
    func restoreThenUndoThenContinue() async {
        let store = MockChessSnapshotStore()
        let first = ChessGameModel(services: makeChessServices(store))
        // キャスリング権が消える手（ルークを動かす）を含む手順を作る。
        for uci in ["g1f3", "b8c6", "h1g1", "g8f6"] {
            first.apply(ChessMove.fromUCI(uci)!)
        }
        #expect(first.position.castling.contains(.whiteKingside) == false)

        // 再起動して復元 → 待った。
        let resumed = ChessGameModel(services: makeChessServices(store))
        #expect(resumed.moves.count == 4)
        #expect(resumed.canUndo)
        resumed.undoLastExchange()
        #expect(resumed.moves.count == 2)
        // 巻き戻した先ではキャスリング権が復活していなければならない。
        #expect(resumed.position.castling.contains(.whiteKingside),
                "h1 のルークを動かす前に戻ったので権利は残っている")
        #expect(resumed.position == resumed.positionAt(ply: 2))

        // そのまま続けてキャスリングできる。
        resumed.apply(ChessMove.fromUCI("e2e4")!)
        resumed.apply(ChessMove.fromUCI("e7e5")!)
        resumed.apply(ChessMove.fromUCI("f1c4")!)
        resumed.apply(ChessMove.fromUCI("f8c5")!)
        #expect(resumed.legalMovesCache.contains(ChessMove.fromUCI("e1g1")!))

        // さらに再起動しても同じ局面に戻る。
        let again = ChessGameModel(services: makeChessServices(store))
        #expect(again.position == resumed.position)
        #expect(again.moves.map(\.uci) == resumed.moves.map(\.uci))
    }

    @Test("終局した対局を開き直すと決着の表示が戻る")
    func resumesFinishedGame() {
        let store = MockChessSnapshotStore()
        try? store.save(ChessSnapshot(
            initialFen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1",
            moves: ["a1a8"], phase: .review, reviewPly: 1,
            white: .human, black: .ai, aiLevel: 0, startedAt: Date(), undoUsed: false
        ), for: "chess")
        let resumed = ChessGameModel(services: makeChessServices(store))
        #expect(resumed.gameOver)
        #expect(resumed.result == .checkmate(loser: .black))
        #expect(resumed.resultText?.contains("あなたの勝ち") == true)
        #expect(resumed.phase == .review)
    }

    @Test("投了で終わった対局も投了として戻る")
    func resumesResignedGame() {
        let store = MockChessSnapshotStore()
        let first = ChessGameModel(services: makeChessServices(store))
        first.apply(ChessMove.fromUCI("e2e4")!)
        first.resign()

        let resumed = ChessGameModel(services: makeChessServices(store))
        #expect(resumed.gameOver)
        #expect(resumed.result == .resignation(loser: .white))
    }
}
