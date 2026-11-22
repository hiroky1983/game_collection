import Foundation
import Testing
import Core
import CoreEngine

/// お気に入り（#3478）の置き場と、ハブのタブの語彙。
@MainActor
@Suite("お気に入り")
struct FavoritesTests {
    private func defaults() -> UserDefaults {
        let name = "FavoritesTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("付けた順に並び、外すと詰まる。付け外しは操作の後の状態を返す")
    func toggleKeepsAdditionOrder() {
        let store = FavoritesStore(defaults: defaults())
        #expect(store.toggle("b"))
        #expect(store.toggle("a"))
        #expect(store.toggle("c"))
        #expect(store.ids == ["b", "a", "c"])
        #expect(!store.toggle("a"))
        #expect(store.ids == ["b", "c"])
        #expect(!store.isFavorite("a") && store.isFavorite("c"))
    }

    @Test("保存して読み直せる。登録されていないゲーム・重複は読み込み時に捨てる")
    func persistsAndDropsUnknown() {
        let d = defaults()
        let store = FavoritesStore(defaults: d)
        _ = store.toggle("a"); _ = store.toggle("gone"); _ = store.toggle("b")
        d.set(["a", "gone", "b", "a"], forKey: FavoritesStore.storageKey)
        let reloaded = FavoritesStore(defaults: d, registeredIDs: ["a", "b", "c"])
        #expect(reloaded.ids == ["a", "b"])
        #expect(FavoritesStore(defaults: d).ids == ["a", "gone", "b"], "登録 ID を渡さなければ絞らないが、重複は捨てる")
    }

    @Test("元に戻すは外す前の位置へ入れる。すでにお気に入りなら何もしない")
    func restoreGoesBackToOriginalIndex() {
        let store = FavoritesStore(defaults: defaults())
        for id in ["a", "b", "c"] { _ = store.toggle(id) }
        let index = store.index(of: "b")!
        _ = store.toggle("b")
        store.restore("b", at: index)
        #expect(store.ids == ["a", "b", "c"])
        store.restore("b", at: 0)
        #expect(store.ids == ["a", "b", "c"])
        store.restore("z", at: 99)
        #expect(store.ids == ["a", "b", "c", "z"], "範囲外の位置は末尾に丸める")
    }

    @Test("「お気に入り」は分類ではなく、ゲームの絞り込み対象にも分類の返り値にもならない")
    func favoritesIsNotACategory() {
        #expect(!HubCategory.filterable.contains(.favorites) && !HubCategory.filterable.contains(.all))
        let registry = GameRegistry([], categories: ["a": .favorites])
        #expect(registry.category(of: "a") == .puzzleOther)
        #expect(HubCategory.allCases.prefix(2) == [.all, .favorites], "チップは「すべて」の次が「お気に入り」")
    }

    @Test("最初に開くタブは「すべて」か「お気に入り」の 2 つで、タブに写る")
    func startTabMapsToCategory() {
        #expect(HubStartTab.allCases == [.all, .favorites])
        #expect(HubStartTab.all.category == .all)
        #expect(HubStartTab.favorites.category == .favorites)
    }

    @Test("favorite_toggle は game_id / state / source の 3 鍵だけで、語彙は閉じている")
    func analyticsShape() {
        let event = AnalyticsEvent.favoriteToggle(gameID: "2048", state: .on, source: .hubTile)
        #expect(event.name == "favorite_toggle")
        #expect(event.parameters == [
            "game_id": .string("2048"), "state": .string("on"), "source": .string("hub_tile"),
        ])
        #expect(FavoriteState.allCases.map(\.rawValue) == ["on", "off"])
        #expect(FavoriteSource.allCases.map(\.rawValue) == ["hub_tile", "hub_menu", "header", "header_menu"])
    }
}
