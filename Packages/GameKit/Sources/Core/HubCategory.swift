/// ハブのカテゴリーのチップ（#1831）。「すべて」以外はゲームの分類で、**どのゲームがどれに入るかは
/// `GameRegistry` がデータとして持つ**（画面のコードにゲーム ID を直書きしない）。
public enum HubCategory: String, CaseIterable, Hashable, Sendable {
    case all
    /// お気に入り（#3478）。ゲームの分類ではなく、利用者が☆を付けたゲームだけを出すタブ。
    /// `GameRegistry` の分類には入らず（`filterable` にも含めない）、「すべて」の次にチップを出す。
    case favorites
    case cards
    case ojisan
    case board
    case mahjongHanafuda
    case puzzleOther

    /// チップに出す名前。
    public var title: String {
        switch self {
        case .all: tr("すべて")
        case .favorites: tr("お気に入り")
        case .ojisan: tr("おじさんシリーズ")
        case .board: tr("盤ゲーム")
        case .cards: tr("トランプ")
        case .mahjongHanafuda: tr("麻雀・花札")
        case .puzzleOther: tr("パズル・その他")
        }
    }

    /// ゲームの分類として絞り込めるカテゴリー（`all` と `favorites` を除く）。
    public static var filterable: [HubCategory] { allCases.filter { $0 != .all && $0 != .favorites } }
}

/// ハブを開いたときに最初に出すタブ（#3478）。設定の「最初に開くタブ」で選ぶ。既定は「すべて」。
public enum HubStartTab: String, CaseIterable, Sendable {
    case all
    case favorites

    public var category: HubCategory { self == .favorites ? .favorites : .all }

    public var title: String { category.title }
}
