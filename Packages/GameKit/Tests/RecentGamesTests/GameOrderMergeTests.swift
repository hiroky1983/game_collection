import Testing
import CoreEngine

@Suite("ハブの並び順・非表示のマージ規則（#1390）")
struct GameOrderMergeTests {
    @Test("保存が空（初回起動）なら登録順がそのまま並びになる")
    func emptyStoredUsesRegisteredOrder() {
        #expect(GameOrderMerge.mergedOrder(stored: [], registered: ["a", "b", "c"]) == ["a", "b", "c"])
    }

    @Test("保存済みの並びはそのまま守られる")
    func storedOrderIsPreserved() {
        #expect(GameOrderMerge.mergedOrder(stored: ["c", "a", "b"], registered: ["a", "b", "c"]) == ["c", "a", "b"])
    }

    @Test("新しく登録されたゲームは既存の並びの末尾に付く")
    func newGamesAppendToTail() {
        let merged = GameOrderMerge.mergedOrder(stored: ["b", "a"], registered: ["a", "n1", "b", "n2"])
        #expect(merged == ["b", "a", "n1", "n2"])
    }

    @Test("登録に無くなった ID は捨てられる")
    func unregisteredIDsAreDropped() {
        #expect(GameOrderMerge.mergedOrder(stored: ["gone", "b", "a"], registered: ["a", "b"]) == ["b", "a"])
    }

    @Test("登録されたゲームはすべて含まれ、足し込みで重複しない")
    func noDuplicatesAndComplete() {
        let merged = GameOrderMerge.mergedOrder(stored: ["a", "a", "b"], registered: ["a", "b", "c"])
        #expect(Set(merged) == ["a", "b", "c"])
        #expect(merged.filter { $0 == "c" }.count == 1)
    }

    @Test("非表示は登録済みのものだけ残る")
    func hiddenKeepsOnlyRegistered() {
        #expect(GameOrderMerge.mergedHidden(stored: ["a", "gone"], registered: ["a", "b"]) == ["a"])
        #expect(GameOrderMerge.mergedHidden(stored: [], registered: ["a"]).isEmpty)
    }
}
