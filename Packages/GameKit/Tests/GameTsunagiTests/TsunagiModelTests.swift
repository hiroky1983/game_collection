import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameTsunagi

@MainActor
private func makeServices(
    store: MemorySnapshotStore = MemorySnapshotStore(),
    log: PlayLog? = nil,
    feedback: FeedbackService = NoopFeedbackService()
) -> GameServices {
    GameServices(snapshots: store, ads: NoopAdService(), feedback: feedback, playLog: log)
}

/// 3×3 の小さな問題。1: 0-1-2-5-8、2: 3-4-7-6（線の引き方だけを見るので、解が 1 つかは問わない）。
private let sample = TsunagiPuzzle(side: 3, endpoints: [[0, 8], [3, 6]], solution: [[0, 1, 2, 5, 8], [3, 4, 7, 6]])

@MainActor
private func draw(_ model: TsunagiModel, _ cells: [Int]) {
    model.beginStroke(at: cells[0])
    for cell in cells.dropFirst() { model.extendStroke(to: cell) }
    model.endStroke()
}

@MainActor
@Suite("線つなぎの Model")
struct TsunagiModelTests {

    @Test("開始直後は線が無く、手数 0・点だけが埋まっている")
    func freshBoard() {
        let model = TsunagiModel(services: makeServices(), size: .small, seed: 1)
        #expect(model.size == .small)
        #expect(model.puzzle.side == 5)
        #expect(model.paths.allSatisfy { $0.isEmpty })
        #expect(model.moves == 0)
        #expect(!model.isSolved)
        #expect(model.filledCount == model.puzzle.pairCount * 2)
        #expect(model.connectedCount == 0)
    }

    @Test("点からなぞって、もう一方の点まで引くとつながる")
    func drawConnects() {
        let model = TsunagiModel(services: makeServices(), puzzle: sample)
        draw(model, [0, 1, 2, 5, 8])
        #expect(model.isComplete(0))
        #expect(model.paths[0] == [0, 1, 2, 5, 8])
        #expect(model.moves == 1)
        #expect(!model.isSolved)
    }

    @Test("つながった線はそれ以上のびない")
    func completedLineStops() {
        let model = TsunagiModel(services: makeServices(), puzzle: sample)
        model.beginStroke(at: 0)
        for cell in [1, 2, 5, 8, 7] { model.extendStroke(to: cell) }
        model.endStroke()
        #expect(model.paths[0] == [0, 1, 2, 5, 8])
    }

    @Test("別の数字の点には入れない")
    func cannotEnterOtherEndpoint() {
        let model = TsunagiModel(services: makeServices(), puzzle: sample)
        draw(model, [0, 3])
        #expect(model.paths[0] == [0])
    }

    @Test("来た道を戻ると線が縮む")
    func backtrackShrinks() {
        let model = TsunagiModel(services: makeServices(), puzzle: sample)
        model.beginStroke(at: 0)
        for cell in [1, 2, 5, 2] { model.extendStroke(to: cell) }
        model.endStroke()
        #expect(model.paths[0] == [0, 1, 2])
    }

    @Test("線の途中から触ると、そこまで戻して続きを引ける")
    func resumeFromMiddle() {
        let model = TsunagiModel(services: makeServices(), puzzle: sample)
        draw(model, [0, 1, 4])
        draw(model, [1, 2, 5])
        #expect(model.paths[0] == [0, 1, 2, 5])
    }

    @Test("別の線に触れると、その線を触れたマスから先で切る")
    func crossingCutsOtherLine() {
        let model = TsunagiModel(services: makeServices(), puzzle: sample)
        draw(model, [3, 4, 7, 6])
        #expect(model.isComplete(1))
        draw(model, [0, 1, 4])
        #expect(model.paths[0] == [0, 1, 4])
        #expect(model.paths[1] == [3], "2 の線は 4 から先が切れる")
        #expect(!model.isComplete(1))
        #expect(model.owners[7] == nil && model.owners[6] == 1)
    }

    @Test("点から引き直すと前の線は消える")
    func restartFromEndpointClears() {
        let model = TsunagiModel(services: makeServices(), puzzle: sample)
        draw(model, [0, 1, 2])
        draw(model, [8, 5])
        #expect(model.paths[0] == [8, 5])
        #expect(model.owners[1] == nil)
    }

    @Test("離れたマスへ飛んだ指は、縦・横に 1 マスずつ追う")
    func fastDragFillsGaps() {
        let model = TsunagiModel(services: makeServices(), puzzle: sample)
        model.beginStroke(at: 0)
        model.extendStroke(to: 2)
        model.extendStroke(to: 8)
        model.endStroke()
        #expect(model.paths[0] == [0, 1, 2, 5, 8])
    }

    @Test("空きマスから始めたなぞりは何もしない")
    func strokeFromEmptyDoesNothing() {
        let model = TsunagiModel(services: makeServices(), puzzle: sample)
        draw(model, [4, 5])
        #expect(model.paths.allSatisfy { $0.isEmpty })
        #expect(model.moves == 0)
    }

    @Test("手数は別の数字の線に持ち替えたときだけ増える")
    func movesCountColorSwitches() {
        let model = TsunagiModel(services: makeServices(), puzzle: sample)
        draw(model, [0, 1])
        draw(model, [1, 2])
        #expect(model.moves == 1, "同じ数字を続けて直すあいだは増えない")
        draw(model, [3, 4])
        #expect(model.moves == 2)
        draw(model, [2, 5])
        #expect(model.moves == 3)
        // 何も変えないなぞりは数えない。
        model.beginStroke(at: 4)
        model.endStroke()
        #expect(model.moves == 3)
    }

    @Test("全部つながっても空きが残っていればクリアにならない（理由を出せる）")
    func connectedButNotFilled() {
        let puzzle = TsunagiPuzzle(side: 2, endpoints: [[0, 2]], solution: [[0, 1, 3, 2]])
        let model = TsunagiModel(services: makeServices(), puzzle: puzzle)
        draw(model, [0, 2])
        #expect(model.isComplete(0))
        #expect(!model.isSolved)
        #expect(model.isConnectedButNotFilled)
        draw(model, [0, 1, 3, 2])
        #expect(model.isSolved)
        #expect(!model.isConnectedButNotFilled)
    }

    @Test("解き終えると決着し、手数を大きさごとの最少手数として記録・中断データを消す")
    func solvingRecordsMoves() {
        let suite = "asobiba.tsunagi.tests.record"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let log = PlayLog(defaults: defaults)
        let store = MemorySnapshotStore()
        let feedback = SpyFeedbackService()
        let model = TsunagiModel(services: makeServices(store: store, log: log, feedback: feedback), puzzle: sample)
        draw(model, sample.solution[0])
        #expect(store.load(TsunagiSnapshot.self, for: TsunagiModel.gameID) != nil)
        draw(model, sample.solution[1])
        #expect(model.isSolved)
        #expect(model.moves == 2)
        #expect(feedback.notices.last == .success)
        let record = log.record(gameID: "tsunagi", variant: "5x5")
        #expect(record?.metric == .fewestMoves)
        #expect(record?.fewestMoves == 2)
        #expect(record?.wins == 1)
        #expect(model.recordResult != nil)
        #expect(store.load(TsunagiSnapshot.self, for: TsunagiModel.gameID) == nil, "決着で中断データを消す")
        // 決着後は線を触れない。
        draw(model, [0, 1])
        #expect(model.paths[0] == sample.solution[0])
    }

    @Test("中断データから、問題・線・手数・大きさを復元する")
    func restoresSnapshot() {
        let store = MemorySnapshotStore()
        let first = TsunagiModel(services: makeServices(store: store), size: .large, seed: 5)
        let path = first.puzzle.solution[0]
        draw(first, Array(path.prefix(2)))
        let restored = TsunagiModel(services: makeServices(store: store), size: .small, seed: 9)
        #expect(restored.size == .large)
        #expect(restored.puzzle == first.puzzle)
        #expect(restored.paths == first.paths)
        #expect(restored.moves == 1)
    }

    @Test("復元の直後に同じ数字の線を伸ばしても手数は増えない（#2286）")
    func resumeKeepsLastMovedColor() {
        let store = MemorySnapshotStore()
        let first = TsunagiModel(services: makeServices(store: store), size: .large, seed: 5)
        let path = first.puzzle.solution[0]
        draw(first, Array(path.prefix(2)))
        #expect(first.moves == 1)
        let restored = TsunagiModel(services: makeServices(store: store), size: .small, seed: 9)
        draw(restored, Array(path.prefix(3)))
        #expect(restored.moves == 1, "同じ数字の続きは 1 手のまま")
        // 別の数字に移れば従来どおり +1。
        draw(restored, Array(restored.puzzle.solution[1].prefix(2)))
        #expect(restored.moves == 2)
    }

    @Test("lastMovedColor の無い旧形式の中断データも復元できる（#2286）")
    func restoresLegacySnapshotWithoutLastMovedColor() throws {
        var generator = SplitMix64(seed: 11)
        let puzzle = TsunagiLogic.generate(size: .small, using: &generator)
        var paths = Array(repeating: [Int](), count: puzzle.pairCount)
        paths[0] = Array(puzzle.solution[0].prefix(2))
        let data = try JSONEncoder().encode(TsunagiSnapshot(size: "5x5", puzzle: puzzle, paths: paths, moves: 1, lastMovedColor: 0))
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "lastMovedColor")
        let legacy = try JSONDecoder().decode(TsunagiSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.lastMovedColor == nil)
        let store = MemorySnapshotStore()
        try store.save(legacy, for: TsunagiModel.gameID)
        let model = TsunagiModel(services: makeServices(store: store), seed: 2)
        #expect(model.puzzle == puzzle)
        #expect(model.moves == 1)
        // 範囲外の値は無視して復元する。
        try store.save(TsunagiSnapshot(size: "5x5", puzzle: puzzle, paths: paths, moves: 1, lastMovedColor: 99), for: TsunagiModel.gameID)
        #expect(TsunagiModel(services: makeServices(store: store), seed: 2).puzzle == puzzle)
    }

    @Test("壊れた中断データは捨てて新しい問題で始める")
    func rejectsBrokenSnapshot() throws {
        let store = MemorySnapshotStore()
        var generator = SplitMix64(seed: 11)
        let puzzle = TsunagiLogic.generate(size: .small, using: &generator)
        // 2 の線が 1 の点から始まっている（よその点を通る線）。
        var paths = Array(repeating: [Int](), count: puzzle.pairCount)
        paths[1] = [puzzle.endpoints[0][0]]
        try store.save(TsunagiSnapshot(size: "5x5", puzzle: puzzle, paths: paths, moves: 1), for: TsunagiModel.gameID)
        let model = TsunagiModel(services: makeServices(store: store), size: .small, seed: 2)
        #expect(model.puzzle != puzzle)
        #expect(model.moves == 0)
        // 大きさの名札と盤が食い違うデータも使わない。
        try store.save(TsunagiSnapshot(size: "7x7", puzzle: puzzle, paths: Array(repeating: [], count: puzzle.pairCount), moves: 0),
                       for: TsunagiModel.gameID)
        #expect(TsunagiModel(services: makeServices(store: store), seed: 2).puzzle != puzzle)
        // 正しいデータなら使う（対照）。
        try store.save(TsunagiSnapshot(size: "5x5", puzzle: puzzle, paths: Array(repeating: [], count: puzzle.pairCount), moves: 0),
                       for: TsunagiModel.gameID)
        #expect(TsunagiModel(services: makeServices(store: store), seed: 2).puzzle == puzzle)
    }

    @Test("新規ゲームで線・手数・決着が戻り、大きさを変えられる")
    func newGameResets() {
        let model = TsunagiModel(services: makeServices(), puzzle: sample)
        draw(model, sample.solution[0])
        draw(model, sample.solution[1])
        #expect(model.isSolved)
        #expect(!model.hasProgressToLose)
        model.newGame(size: .large)
        #expect(model.size == .large)
        #expect(model.puzzle.side == 7)
        #expect(model.paths.count == model.puzzle.pairCount)
        #expect(model.paths.allSatisfy { $0.isEmpty })
        #expect(model.moves == 0 && !model.isSolved && model.recordResult == nil)
        draw(model, Array(model.puzzle.solution[0].prefix(2)))
        #expect(model.hasProgressToLose)
    }

    @Test("VoiceOver の操作: 点を選んで隣のマスを順に選ぶと線がのび、つながると選択が外れる")
    func accessibilityActivation() {
        let model = TsunagiModel(services: makeServices(), puzzle: sample)
        model.activate(cell: 0)
        #expect(model.activeColor == 0)
        for cell in [1, 2, 5] {
            model.activate(cell: cell)
            #expect(model.activeColor == 0)
        }
        model.activate(cell: 8)
        #expect(model.isComplete(0))
        #expect(model.activeColor == nil)
        #expect(model.moves == 1)
        // 2 も同じ操作でつなぐと、全マスが埋まってクリア。
        model.activate(cell: 3)
        #expect(model.activeColor == 1)
        for cell in [4, 7, 6] { model.activate(cell: cell) }
        #expect(model.isSolved)
        #expect(model.activeColor == nil)
        #expect(model.moves == 2)
    }
}
