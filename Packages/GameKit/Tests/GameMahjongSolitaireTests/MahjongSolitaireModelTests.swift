import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjongSolitaire

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
private func makeServices(
    store: SnapshotStore = MemorySnapshotStore()
) -> (GameServices, FeedbackSpy) {
    let spy = FeedbackSpy()
    return (GameServices(snapshots: store, ads: NoopAdService(), feedback: spy), spy)
}

/// 生成時の解法どおりにタップして最後まで取り切る。
@MainActor
private func clearBoard(_ model: MahjongSolitaireModel) {
    for pair in model.solution {
        model.tap(pair[0])
        model.tap(pair[1])
    }
}

// MARK: - 進行

@Suite("麻雀ソリティアの進行")
@MainActor
struct MahjongSolitaireModelTests {

    @Test("開始時は144枚が並び、取り切ればクリアになる")
    func playThrough() {
        let (services, _) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 2026)
        #expect(model.remainingCount == 144)
        #expect(model.phase == .playing)

        clearBoard(model)

        #expect(model.remainingCount == 0)
        #expect(model.phase == .won)
    }

    @Test("取れない牌のタップは拒否され、盤面が動かない")
    func tappingBlockedTileIsRejected() {
        let (services, spy) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 3)
        guard let covered = MahjongSolitaireRules.index(layer: 3, hx: 12, hy: 6) else {
            Issue.record("レイアウトの位置が見つからない")
            return
        }
        #expect(!model.isFreeByIndex[covered], "最上段に覆われているので取れない")

        model.tap(covered)

        #expect(model.selectedIndex == nil, "取れない牌は選択されない")
        #expect(model.remainingCount == 144)
        #expect(spy.notices.contains(.warning), "拒否として鳴る")
    }

    @Test("合わない牌をタップすると選び直しになる")
    func tappingUnmatchedTileMovesSelection() {
        let (services, _) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 11)
        let first = model.solution[0][0]
        // 1手目の相方とは違う絵柄の、いま取れる牌を探す。
        guard let firstFace = model.faces[first],
              let other = model.isFreeByIndex.indices.first(where: { index in
                  model.isFreeByIndex[index] && index != first
                      && model.faces[index].map { !$0.matches(firstFace) } == true
              }) else {
            Issue.record("合わない牌が見つからない")
            return
        }

        model.tap(first)
        #expect(model.selectedIndex == first)
        model.tap(other)
        #expect(model.selectedIndex == other, "選択が移るだけで取り除かれない")
        #expect(model.remainingCount == 144)
    }

    @Test("同じ牌をもう一度タップすると選択が外れる")
    func tappingSelectedTileDeselects() {
        let (services, _) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 12)
        let first = model.solution[0][0]
        model.tap(first)
        #expect(model.selectedIndex == first)
        model.tap(first)
        #expect(model.selectedIndex == nil)
        #expect(model.remainingCount == 144)
    }

    @Test("新規ゲームでは計時が入り直す（クリア後に時計が止まったままにならない）")
    func newGameRestartsTheClock() {
        let (services, _) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 13)
        model.resumeTimerIfNeeded()
        #expect(model.isCounting)

        clearBoard(model)
        #expect(model.phase == .won)
        #expect(!model.isCounting, "クリアしたら止まる")

        model.newGame()
        #expect(model.isCounting, "次のゲームでは計時が再開する")
        #expect(model.elapsedSeconds == 0)
    }

    @Test("ヒントはいま取れる合う2枚を指す")
    func hintPointsToAnAvailablePair() {
        let (services, _) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 21)
        model.showHint()
        #expect(model.hintPair.count == 2)
        let (a, b) = (model.hintPair[0], model.hintPair[1])
        #expect(model.isFreeByIndex[a] && model.isFreeByIndex[b], "どちらも取れる牌")
        #expect(model.faces[a]?.matches(model.faces[b] ?? .dragon(0)) == true, "絵柄が合う")
        #expect(model.hintCount == 1)
    }

    @Test("牌を取るとヒントの表示は消える")
    func hintClearsOnNextTap() {
        let (services, _) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 22)
        model.showHint()
        #expect(!model.hintPair.isEmpty)
        model.tap(model.solution[0][0])
        #expect(model.hintPair.isEmpty)
    }
}

// MARK: - 手詰まり

@Suite("手詰まりの検知と並べ替え")
@MainActor
struct MahjongDeadlockTests {

    private func index(_ layer: Int, _ hx: Int, _ hy: Int) -> Int? {
        MahjongSolitaireRules.index(layer: layer, hx: hx, hy: hy)
    }

    /// 取れる 3 枚の絵柄がすべて違い、合う相方はいずれも覆われている盤面。
    private func makeDeadlockedFaces() -> [MahjongFace?]? {
        guard let freeA = index(0, 2, 0), let freeB = index(0, 24, 0),
              let freeC = index(4, 13, 7),
              let coveredA = index(3, 12, 6), let coveredB = index(3, 14, 6),
              let coveredC = index(3, 12, 8) else { return nil }
        var faces = [MahjongFace?](repeating: nil, count: MahjongSolitaireRules.layout.count)
        faces[freeA] = .characters(1)
        faces[coveredA] = .characters(1)
        faces[freeB] = .circles(2)
        faces[coveredB] = .circles(2)
        faces[freeC] = .dragon(0)
        faces[coveredC] = .dragon(0)
        return faces
    }

    @Test("取れる組が無くなったら手詰まりとして検知する")
    func detectsDeadlock() {
        let (services, _) = makeServices()
        guard let faces = makeDeadlockedFaces() else {
            Issue.record("盤面を組み立てられない")
            return
        }
        let model = MahjongSolitaireModel(services: services, seed: 31, faces: faces)
        #expect(model.remainingCount == 6)
        #expect(model.availablePairCount == 0)
        #expect(model.isDeadlocked)
    }

    @Test("並べ替えると手詰まりが解け、牌の内訳は変わらない")
    func shuffleResolvesDeadlock() {
        let (services, _) = makeServices()
        guard let faces = makeDeadlockedFaces() else {
            Issue.record("盤面を組み立てられない")
            return
        }
        let model = MahjongSolitaireModel(services: services, seed: 31, faces: faces)
        #expect(model.shuffleRemaining())
        #expect(!model.isDeadlocked)
        #expect(model.availablePairCount > 0)
        #expect(model.remainingCount == 6)
        #expect(model.shuffleCount == 1)

        var counts: [String: Int] = [:]
        for face in model.faces.compactMap({ $0 }) { counts[face.matchKey, default: 0] += 1 }
        #expect(counts == ["m1": 2, "p2": 2, "d0": 2])
    }

    @Test("並べ替えた後の盤面も解法どおりに取り切れる")
    func shuffledBoardStaysSolvable() {
        let (services, _) = makeServices()
        guard let faces = makeDeadlockedFaces() else {
            Issue.record("盤面を組み立てられない")
            return
        }
        let model = MahjongSolitaireModel(services: services, seed: 31, faces: faces)
        #expect(model.shuffleRemaining())
        clearBoard(model)
        #expect(model.phase == .won)
    }

    @Test("手詰まりで最初からを選ぶと敗北として記録し、新しい盤面を配る")
    func giveUpDealsNewBoard() {
        let (services, spy) = makeServices()
        guard let faces = makeDeadlockedFaces() else {
            Issue.record("盤面を組み立てられない")
            return
        }
        let model = MahjongSolitaireModel(services: services, seed: 31, faces: faces)
        model.giveUpAndRestart()
        #expect(spy.notices.contains(.error))
        #expect(model.remainingCount == 144)
        #expect(model.phase == .playing)
        #expect(!model.isDeadlocked)
    }
}

// MARK: - 中断・再開

@Suite("麻雀ソリティアの中断・再開")
@MainActor
struct MahjongSnapshotTests {

    @Test("取りかけの盤面は保存され、次に開いたとき同じ状態から再開できる")
    func resumesFromSnapshot() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = MahjongSolitaireModel(services: services, seed: 55)
        for pair in model.solution.prefix(5) {
            model.tap(pair[0])
            model.tap(pair[1])
        }
        #expect(model.remainingCount == 134)
        #expect(store.exists(for: "mahjong"), "取りかけの盤面は保存される")

        let resumed = MahjongSolitaireModel(services: services)
        #expect(resumed.remainingCount == 134)
        #expect(resumed.faces == model.faces, "同じ盤面が戻る")
        #expect(resumed.phase == .playing)
    }

    @Test("配ったばかりの盤面は保存しない（ハブに続きからが出続けないように）")
    func untouchedBoardIsNotSaved() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        _ = MahjongSolitaireModel(services: services, seed: 56)
        #expect(!store.exists(for: "mahjong"))
    }

    @Test("取り切ったらスナップショットは消える")
    func snapshotIsClearedOnClear() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = MahjongSolitaireModel(services: services, seed: 57)
        for pair in model.solution {
            model.tap(pair[0])
            model.tap(pair[1])
        }
        #expect(model.phase == .won)
        #expect(!store.exists(for: "mahjong"))
    }

    @Test("新規ゲームを始めるとスナップショットは消える")
    func snapshotIsClearedOnNewGame() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = MahjongSolitaireModel(services: services, seed: 58)
        model.tap(model.solution[0][0])
        model.tap(model.solution[0][1])
        #expect(store.exists(for: "mahjong"))
        model.newGame()
        #expect(!store.exists(for: "mahjong"))
        #expect(model.remainingCount == 144)
    }
}
