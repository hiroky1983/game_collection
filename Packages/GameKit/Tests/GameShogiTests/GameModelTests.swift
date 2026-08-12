import Testing
import Foundation
import Core
@testable import GameShogi

@MainActor
@Suite("対局モデル（人間→CPU の流れ）")
struct ShogiGameModelTests {
    @Test func humanMoveThenAIReplies() async {
        let model = ShogiGameModel(services: nil)
        // 既定は人間=先手 / CPU=後手。
        #expect(model.humanSide == .black)
        #expect(model.isAITurn == false)

        // 人間(先手)が 7g7f（選択→着手先タップ）。
        model.tapSquare(Sq.fromUSI("7g")!)
        #expect(model.selectedSquare == Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        #expect(model.moves.count == 1)
        #expect(model.moves.last?.usi == "7g7f")

        // 手番は後手(CPU)。AI が応手する。
        #expect(model.isAITurn)
        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 2)
        #expect(model.gameOver == false)
        // 応手後は再び先手(人間)番。
        #expect(model.isAITurn == false)
    }

    @Test func humanCannotMoveDuringCPUTurn() {
        let model = ShogiGameModel(services: nil)
        // 人間(先手)が一手指すと CPU(後手)の手番。
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        #expect(model.isAITurn)
        let movesBefore = model.moves.count
        // CPU の手番中に後手の駒を触っても何も起きない。
        model.tapSquare(Sq.fromUSI("3c")!) // 後手の歩
        #expect(model.selectedSquare == nil)
        model.tapSquare(Sq.fromUSI("3d")!)
        #expect(model.moves.count == movesBefore) // 手が増えない
    }

    @Test func newGameAsGoteMakesAIMoveFirst() async {
        let model = ShogiGameModel(services: nil)
        model.newGame(humanSide: .white) // 人間後手 → CPU が先手で初手を指す
        #expect(model.isAITurn)
        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 1)
    }

    @Test func undoLastExchangeRemovesHumanAndCPUMoves() async {
        let model = ShogiGameModel(services: nil)
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 2)
        #expect(model.canUndo)

        model.undoLastExchange()
        #expect(model.moves.isEmpty)
        #expect(model.isAITurn == false)
        #expect(model.canUndo == false)
        #expect(model.position.squares[Sq.fromUSI("7f")!] == nil)
    }
}

// MARK: - CPU 起動トリガー（#82: 後手を選ぶと CPU が初手を指さない）

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

private func makeServices(_ store: MockSnapshotStore) -> GameServices {
    GameServices(snapshots: store, ads: NoopAdService())
}

@MainActor
@Suite("CPU 起動トリガー")
struct ShogiAITurnKeyTests {
    /// View は `.task(id: model.aiTurnKey)` で CPU を起動する。
    /// 起動直後（0 手）に後手を選んでも手数が 0 のままなので、キーが変わらないと初手が指されない。
    @Test func aiTurnKeyChangesWhenStartingAsGoteWithoutMoves() {
        let model = ShogiGameModel(services: nil)
        #expect(model.moves.isEmpty)
        let before = model.aiTurnKey

        model.newGame(humanSide: .white)
        #expect(model.moves.isEmpty) // 手数は 0 のまま
        #expect(model.aiTurnKey != before) // それでもトリガーは変化する
        #expect(model.isAITurn)
    }

    /// 後手開始 → CPU 初手 → 人間応手 → 再び CPU 番、まで通しで動くこと。
    @Test func goteStartPlaysCPUFirstMoveThenHumanReply() async {
        let model = ShogiGameModel(services: nil)
        model.newGame(humanSide: .white)

        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 1)
        #expect(model.isAITurn == false) // 人間(後手)の番
        let afterCPU = model.aiTurnKey

        // 人間(後手)が 3c3d を指す。
        model.tapSquare(Sq.fromUSI("3c")!)
        model.tapSquare(Sq.fromUSI("3d")!)
        #expect(model.moves.count == 2)
        #expect(model.moves.last?.usi == "3c3d")
        #expect(model.aiTurnKey != afterCPU)
        #expect(model.isAITurn) // CPU(先手)の番に戻る
    }

    /// 先手を選んだ場合は従来どおり CPU は動かず、人間の手番から始まる。
    @Test func senteStartKeepsHumanTurn() async {
        let model = ShogiGameModel(services: nil)
        model.newGame(humanSide: .black)
        #expect(model.isAITurn == false)
        await model.performAIMoveIfNeeded()
        #expect(model.moves.isEmpty)
    }

    /// 「続きから」再開時も手番の判定が保存内容どおりに復元される。
    @Test func resumedGameRestoresSides() {
        let store = MockSnapshotStore()
        let first = ShogiGameModel(services: makeServices(store))
        first.newGame(humanSide: .white)

        let resumed = ShogiGameModel(services: makeServices(store))
        #expect(resumed.humanSide == .white)
        #expect(resumed.moves.isEmpty)
        #expect(resumed.isAITurn) // 再開直後は CPU(先手)の番
    }
}
