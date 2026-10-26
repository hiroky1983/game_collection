import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameGo

@MainActor
@Suite("13路盤（#2868）・GameGo")
struct GameGo13BoardTests {
    private func makeServices() -> (GameServices, PlayLog, MemorySnapshotStore) {
        let name = "asobiba.go13.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let store = MemorySnapshotStore()
        return (GameServices(snapshots: store, ads: NoopAdService(), playLog: log), log, store)
    }

    @Test("13路で始めると盤は 13×13 になり、置き石は 13路の星に並ぶ")
    func thirteenBoard() {
        let model = GoModel(services: nil)
        model.newGame(humanSide: .black, level: .normal, handicap: 4, boardSize: .thirteen)
        #expect(model.boardSize == .thirteen)
        #expect(model.board.size == 13)
        #expect(Set(model.ruleset.handicapPoints()) == [
            GoPoint(row: 3, col: 9), GoPoint(row: 9, col: 3), GoPoint(row: 9, col: 9), GoPoint(row: 3, col: 3),
        ])
        #expect(model.board.stoneCount == 4)
    }

    @Test("既定は 9路。白を選んでも 13路のまま置き石だけ無くなる")
    func defaultsAndWhite() {
        let model = GoModel(services: nil)
        model.newGame()
        #expect(model.boardSize == .nine)
        model.newGame(humanSide: .white, handicap: 3, boardSize: .thirteen)
        #expect(model.board.size == 13)
        #expect(model.ruleset.handicap == 0)
    }

    @Test("13路の中断データは 13路で復元される。最後に選んだ条件も 13路を覚える")
    func restoreAndLastStart() {
        let (services, _, store) = makeServices()
        let model = GoModel(services: services)
        model.newGame(humanSide: .black, level: .hard, handicap: 0, boardSize: .thirteen)
        model.tap(row: 6, col: 6)
        #expect(store.exists(for: "go"))
        let restored = GoModel(services: services)
        #expect(restored.board.size == 13)
        #expect(restored.moveCount >= 1)
        store.clear(for: "go")
        let next = GoModel(services: services)
        #expect(next.boardSize == .thirteen)
    }

    @Test("記録の区分: 9路は従来どおり、13路は 13 を前に付ける")
    func recordVariants() {
        #expect(GoBoardSize.nine.recordVariant(strengthVariant: nil) == nil)
        #expect(GoBoardSize.nine.recordVariant(strengthVariant: "hard") == "hard")
        #expect(GoBoardSize.thirteen.recordVariant(strengthVariant: nil) == "13")
        #expect(GoBoardSize.thirteen.recordVariant(strengthVariant: "hard") == "13-hard")
        #expect(RecordVariantLabels.label(recordKey: "go#13", language: .japanese) == "13路")
        #expect(RecordVariantLabels.label(recordKey: "go#13-hard", language: .japanese) == "13路・CPUむずかしい")
        #expect(RecordVariantLabels.label(recordKey: "go#13-hard", language: .english) == "13-line · CPU Hard")
        #expect(RecordVariantLabels.label(recordKey: "go#13-bogus") == nil)
    }

    @Test("13路の対局の決着は、9路とは別の記録に入る")
    func finishGoesToSeparateRecord() {
        let (services, log, _) = makeServices()
        let model = GoModel(services: services)
        model.newGame(humanSide: .black, level: .normal, handicap: 0, boardSize: .thirteen)
        model.resign()
        #expect(log.record(gameID: "go#13")?.plays == 1)
        #expect(log.record(gameID: "go") == nil)
    }
}
