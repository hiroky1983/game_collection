/// ハブが列挙する `GameModule` のレジストリ。登録順に表示される。
public struct GameRegistry {
    public let modules: [GameModule]
    /// ゲーム ID ごとのハブのカテゴリー（#1831）。載っていないゲームは `.puzzleOther` に入る。
    public let categories: [String: HubCategory]

    public init(_ modules: [GameModule], categories: [String: HubCategory] = [:]) {
        self.modules = modules
        self.categories = categories
    }

    /// `gameID` が入るカテゴリー。`.all` は返さない（絞り込みの「すべて」はカテゴリーではなく無指定）。
    public func category(of gameID: String) -> HubCategory {
        guard let category = categories[gameID], category != .all else { return .puzzleOther }
        return category
    }

    /// `ids` のうち `category` に入るものを、並びを保って返す。`.all` は全件。
    public func filter(_ ids: [String], by category: HubCategory) -> [String] {
        guard category != .all else { return ids }
        return ids.filter { self.category(of: $0) == category }
    }

    /// 1 本以上入っているカテゴリー（チップに出す対象）。`ids` は今表示しているゲーム。
    public func populatedCategories(among ids: [String]) -> [HubCategory] {
        HubCategory.filterable.filter { category in ids.contains { self.category(of: $0) == category } }
    }

    public func module(id: String) -> GameModule? {
        modules.first { $0.id == id }
    }

    /// `gameID` の中断データが「続きから」で戻れる途中の局か（#809）。登録外の ID は false。
    public func hasResumableSnapshot(gameID: String, in snapshots: SnapshotStore) -> Bool {
        module(id: gameID)?.hasResumableSnapshot(in: snapshots) ?? false
    }

    /// `gameID` の中断データが手つかずの盤か（#2161）。登録外の ID は false。
    public func hasUntouchedSnapshot(gameID: String, in snapshots: SnapshotStore) -> Bool {
        module(id: gameID)?.hasUntouchedSnapshot(in: snapshots) ?? false
    }
}
