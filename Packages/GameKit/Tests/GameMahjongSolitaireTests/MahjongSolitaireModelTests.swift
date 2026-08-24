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

// MARK: - アンドゥ（#198）

@Suite("麻雀ソリティアのアンドゥ")
@MainActor
struct MahjongSolitaireUndoTests {

    /// 解法の先頭から `count` 手ぶん取る。
    @MainActor
    private func take(_ model: MahjongSolitaireModel, pairs count: Int) {
        for pair in model.solution.prefix(count) {
            model.tap(pair[0])
            model.tap(pair[1])
        }
    }

    @Test("取る前は戻せない")
    func cannotUndoBeforeAnyTake() {
        let (services, spy) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 61)
        #expect(!model.canUndo)
        #expect(!model.undoLastTake())
        #expect(model.remainingCount == 144)
        #expect(model.undoCount == 0)
        #expect(spy.notices.contains(.warning), "戻せないことは拒否として鳴る")
    }

    @Test("直前に取った2枚が同じ位置・同じ絵柄で戻る")
    func undoRestoresTheLastPair() {
        let (services, _) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 62)
        let before = model.faces
        let pair = model.solution[0]

        take(model, pairs: 1)
        #expect(model.remainingCount == 142)
        #expect(model.canUndo)

        #expect(model.undoLastTake())
        #expect(model.remainingCount == 144)
        #expect(model.faces == before, "盤面は取る前と同一に戻る")
        #expect(model.faces[pair[0]] != nil && model.faces[pair[1]] != nil)
        #expect(model.undoCount == 1)
        #expect(model.isFreeByIndex[pair[0]] && model.isFreeByIndex[pair[1]], "取れる状態も戻る")
    }

    @Test("戻せるのは1手ぶんだけ（連続では巻き戻せない）")
    func undoIsLimitedToOneTake() {
        let (services, _) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 63)
        take(model, pairs: 3)
        #expect(model.remainingCount == 138)

        #expect(model.undoLastTake())
        #expect(model.remainingCount == 140)
        #expect(!model.canUndo, "2手目より前へは戻れない")
        #expect(!model.undoLastTake())
        #expect(model.remainingCount == 140)
        #expect(model.undoCount == 1, "空振りは回数に数えない")
    }

    @Test("戻した後にもう1手取れば、また1手戻せる")
    func undoBecomesAvailableAgainAfterNextTake() {
        let (services, _) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 64)
        take(model, pairs: 1)
        #expect(model.undoLastTake())
        #expect(!model.canUndo)

        take(model, pairs: 1)
        #expect(model.canUndo)
        #expect(model.undoLastTake())
        #expect(model.undoCount == 2)
        #expect(model.remainingCount == 144)
    }

    @Test("並べ替えると戻せなくなる（位置と絵柄の対応が変わるため）")
    func shuffleDiscardsTheUndoHistory() {
        let (services, _) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 65)
        take(model, pairs: 1)
        #expect(model.canUndo)

        #expect(model.shuffleRemaining())
        #expect(!model.canUndo)
        #expect(model.remainingCount == 142, "並べ替えでは枚数は動かない")
    }

    @Test("取り切った後は戻せない（確定した記録を巻き戻せないように）")
    func cannotUndoAfterClearing() {
        let (services, _) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 66)
        clearBoard(model)
        #expect(model.phase == .won)
        #expect(!model.canUndo)
        #expect(!model.undoLastTake())
        #expect(model.remainingCount == 0)
    }

    @Test("新規ゲームで利用回数と履歴が消える")
    func newGameResetsUndoState() {
        let (services, _) = makeServices()
        let model = MahjongSolitaireModel(services: services, seed: 67)
        take(model, pairs: 1)
        #expect(model.undoLastTake())
        #expect(model.undoCount == 1)

        model.newGame()
        #expect(model.undoCount == 0)
        #expect(!model.canUndo)
    }

    @Test("直前の1手が作った手詰まりはアンドゥで解ける")
    func undoResolvesTheDeadlockItCaused() {
        let (services, _) = makeServices()
        // 手詰まりの盤面（合う相方がいずれも覆われている 6 枚）に、いま取れる 1 組だけを足す。
        // その 1 組を取ると手詰まりの 6 枚だけが残る = 直前の 1 手が手詰まりを作った状態になる。
        guard let freeA = MahjongSolitaireRules.index(layer: 0, hx: 2, hy: 0),
              let freeB = MahjongSolitaireRules.index(layer: 0, hx: 24, hy: 0),
              let freeC = MahjongSolitaireRules.index(layer: 4, hx: 13, hy: 7),
              let coveredA = MahjongSolitaireRules.index(layer: 3, hx: 12, hy: 6),
              let coveredB = MahjongSolitaireRules.index(layer: 3, hx: 14, hy: 6),
              let coveredC = MahjongSolitaireRules.index(layer: 3, hx: 12, hy: 8),
              let finLeft = MahjongSolitaireRules.index(layer: 0, hx: 0, hy: 7),
              let finRight = MahjongSolitaireRules.index(layer: 0, hx: 28, hy: 7) else {
            Issue.record("レイアウトの位置が見つからない")
            return
        }
        var faces = [MahjongFace?](repeating: nil, count: MahjongSolitaireRules.layout.count)
        faces[freeA] = .characters(1)
        faces[coveredA] = .characters(1)
        faces[freeB] = .circles(2)
        faces[coveredB] = .circles(2)
        faces[freeC] = .dragon(0)
        faces[coveredC] = .dragon(0)
        // 盤の両端のヒレ。互いに離れていて、取っても他の牌の取得可否を変えない。
        faces[finLeft] = .bamboos(3)
        faces[finRight] = .bamboos(3)
        let model = MahjongSolitaireModel(services: services, seed: 68, faces: faces)
        #expect(model.remainingCount == 8)
        #expect(!model.isDeadlocked)
        #expect(model.availablePairCount == 1, "取れるのはヒレの1組だけ")

        model.tap(finLeft)
        model.tap(finRight)
        #expect(model.remainingCount == 6)
        #expect(model.isDeadlocked, "取った結果、合う相方が覆われた6枚だけが残って詰む")

        #expect(model.undoLastTake())
        #expect(!model.isDeadlocked)
        #expect(model.availablePairCount == 1)
    }

    @Test("花牌は組では合うが絵柄が違う。戻したときに入れ替わらない")
    func undoRestoresDistinctFlowerFaces() {
        let (services, _) = makeServices()
        guard let finLeft = MahjongSolitaireRules.index(layer: 0, hx: 0, hy: 7),
              let finRight = MahjongSolitaireRules.index(layer: 0, hx: 28, hy: 7),
              let keepA = MahjongSolitaireRules.index(layer: 0, hx: 2, hy: 0),
              let keepB = MahjongSolitaireRules.index(layer: 0, hx: 24, hy: 0) else {
            Issue.record("レイアウトの位置が見つからない")
            return
        }
        var faces = [MahjongFace?](repeating: nil, count: MahjongSolitaireRules.layout.count)
        faces[finLeft] = .flower(0)
        faces[finRight] = .flower(1)
        // 取り切ってしまうと局が終わって戻せなくなるので、触らない組を残しておく。
        faces[keepA] = .characters(1)
        faces[keepB] = .characters(1)
        let model = MahjongSolitaireModel(services: services, seed: 71, faces: faces)
        #expect(model.faces[finLeft]?.matches(.flower(1)) == true, "花牌は組では合う")

        model.tap(finLeft)
        model.tap(finRight)
        #expect(model.remainingCount == 2)

        #expect(model.undoLastTake())
        #expect(model.faces[finLeft] == .flower(0), "絵柄が相方のものに化けない")
        #expect(model.faces[finRight] == .flower(1))
    }

    @Test("1手目を戻して満杯に戻ると、途中の盤面としては保存しない")
    func undoingBackToAFullBoardClearsTheSnapshot() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = MahjongSolitaireModel(services: services, seed: 72)
        take(model, pairs: 1)
        #expect(store.exists(for: "mahjong"))

        #expect(model.undoLastTake())
        #expect(model.remainingCount == 144)
        // 「配ったばかりの盤面は保存しない」ガード（ハブに「続きから」を出さない）に戻る。
        #expect(!store.exists(for: "mahjong"))
        // 記録の内訳はメモリ上には残るので、この局のリザルトには反映される。
        #expect(model.undoCount == 1)
    }

    @Test("利用回数は中断・再開をまたいで残る")
    func undoCountSurvivesSuspension() {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let model = MahjongSolitaireModel(services: services, seed: 69)
        take(model, pairs: 3)
        #expect(model.undoLastTake())
        #expect(model.undoCount == 1)

        let resumed = MahjongSolitaireModel(services: services)
        #expect(resumed.undoCount == 1, "記録の内訳は再開後も失われない")
        #expect(resumed.remainingCount == 140)
        #expect(!resumed.canUndo, "再開直後は戻せない（履歴は保存しない）")
    }

    @Test("アンドゥの項目が無い古いスナップショットも読める")
    func legacySnapshotWithoutUndoCountStillLoads() throws {
        let store = MemorySnapshotStore()
        let (services, _) = makeServices(store: store)
        let seeded = MahjongSolitaireModel(services: services, seed: 70)
        take(seeded, pairs: 2)
        let faces = seeded.faces

        // v1.1.2 までの形（`undoCount` を持たない）をそのまま流し込む。
        struct LegacySnapshot: Codable {
            let faces: [MahjongFace?]
            let elapsedSeconds: Int
            let shuffleCount: Int
            let hintCount: Int
        }
        try store.save(
            LegacySnapshot(faces: faces, elapsedSeconds: 42, shuffleCount: 1, hintCount: 2),
            for: "mahjong"
        )

        let resumed = MahjongSolitaireModel(services: services)
        #expect(resumed.faces == faces, "盤面が捨てられずに戻る")
        #expect(resumed.elapsedSeconds == 42)
        #expect(resumed.undoCount == 0)
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
