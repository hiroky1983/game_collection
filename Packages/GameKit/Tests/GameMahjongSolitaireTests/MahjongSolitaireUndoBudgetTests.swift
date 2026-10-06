import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjongSolitaire
import CoreTestSupport

/// 「戻す」の回数制（#1855）。ソリティア・フリーセルと同じ `RewardedUndoBudget` を使う。
@Suite("麻雀ソリティア: 戻すの回数制（#1855）")
@MainActor
struct MahjongSolitaireUndoBudgetTests {
    private func makeServices(store: MemorySnapshotStore = MemorySnapshotStore()) -> GameServices {
        GameServices(snapshots: store, ads: NoopAdService(), feedback: SpyFeedbackService())
    }

    /// 解法の先頭から `pairs` 組を取る。
    private func take(_ model: MahjongSolitaireModel, from start: Int, pairs: Int) {
        for pair in model.solution[start..<(start + pairs)] {
            model.tap(pair[0])
            model.tap(pair[1])
        }
    }

    /// 取る → 戻す を `times` 回くり返す。
    private func takeAndUndo(_ model: MahjongSolitaireModel, times: Int) {
        for _ in 0..<times {
            take(model, from: 0, pairs: 1)
            #expect(model.undoLastTake())
        }
    }

    @Test("経済は共有の RewardedUndoBudget と同じ値（別の値を持たない）")
    func sharesTheCoreBudget() {
        #expect(MahjongSolitaireUndoBudget.free == RewardedUndoBudget.free)
        #expect(MahjongSolitaireUndoBudget.refill == RewardedUndoBudget.refill)
        #expect(MahjongSolitaireModel(services: makeServices(), seed: 71).undosRemaining == RewardedUndoBudget.free)
    }

    @Test("無料の回数だけ戻せて、使い切ると戻せず補充の提案になる")
    func freeUndosThenRefillNeeded() {
        let model = MahjongSolitaireModel(services: makeServices(), seed: 72)
        takeAndUndo(model, times: MahjongSolitaireUndoBudget.free)
        #expect(model.undosRemaining == 0)

        take(model, from: 0, pairs: 1)
        #expect(model.canUndo, "戻せる手はある")
        #expect(model.needsUndoRefill)
        let before = model.faces
        #expect(!model.undoLastTake())
        #expect(model.faces == before, "回数が無ければ盤面は動かない")
        #expect(model.undoCount == MahjongSolitaireUndoBudget.free, "空振りは回数に数えない")
    }

    @Test("広告で補充すると戻せるようになり、戻せる手数は 1 手のまま")
    func grantRestoresUndos() {
        let model = MahjongSolitaireModel(services: makeServices(), seed: 73)
        takeAndUndo(model, times: MahjongSolitaireUndoBudget.free)
        take(model, from: 0, pairs: 2)
        #expect(model.grantUndos(forDeal: model.dealSerial))
        #expect(model.undosRemaining == MahjongSolitaireUndoBudget.refill)
        #expect(!model.needsUndoRefill)

        #expect(model.undoLastTake())
        #expect(!model.canUndo, "戻せるのは直前の 1 手だけ")
    }

    @Test("広告を見ているあいだに配り直されたら補充しない")
    func grantIgnoredAfterRedeal() {
        let model = MahjongSolitaireModel(services: makeServices(), seed: 74)
        takeAndUndo(model, times: MahjongSolitaireUndoBudget.free)
        let deal = model.dealSerial
        model.newGame()
        #expect(model.undosRemaining == MahjongSolitaireUndoBudget.free)
        #expect(!model.grantUndos(forDeal: deal))
        #expect(model.undosRemaining == MahjongSolitaireUndoBudget.free)
    }

    @Test("取り切った局には補充しない")
    func grantIgnoredAfterClear() {
        let model = MahjongSolitaireModel(services: makeServices(), seed: 75)
        take(model, from: 0, pairs: model.solution.count)
        #expect(model.phase == .won)
        #expect(!model.grantUndos(forDeal: model.dealSerial))
    }

    @Test("残り回数は中断データに保存され、復元で戻る")
    func remainingSurvivesRestore() {
        let store = MemorySnapshotStore()
        let model = MahjongSolitaireModel(services: makeServices(store: store), seed: 76)
        take(model, from: 0, pairs: 2)
        #expect(model.undoLastTake())
        model.pauseTimer()   // 保存し直す

        let restored = MahjongSolitaireModel(services: makeServices(store: store))
        #expect(restored.undosRemaining == MahjongSolitaireUndoBudget.free - 1)
    }

    @Test("残り回数を持たない旧形式の中断データは無料枠いっぱいで再開する")
    func legacySnapshotStartsFull() throws {
        let store = MemorySnapshotStore()
        let model = MahjongSolitaireModel(services: makeServices(store: store), seed: 77)
        take(model, from: 0, pairs: 1)
        model.pauseTimer()
        let data = try #require(store.rawData(for: "mahjong"))
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["undosRemaining"] != nil, "新形式では残り回数を書いている")
        object.removeValue(forKey: "undosRemaining")
        store.inject(try JSONSerialization.data(withJSONObject: object), for: "mahjong")

        let restored = MahjongSolitaireModel(services: makeServices(store: store))
        #expect(restored.remainingCount == 142)
        #expect(restored.undosRemaining == MahjongSolitaireUndoBudget.free)
    }
}
