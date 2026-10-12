/// ハブのカテゴリーのチップ（#1831）。「すべて」以外はゲームの分類で、**どのゲームがどれに入るかは
/// `GameRegistry` がデータとして持つ**（画面のコードにゲーム ID を直書きしない）。
public enum HubCategory: String, CaseIterable, Hashable, Sendable {
    case all
    case ojisan
    case board
    case cards
    case mahjongHanafuda
    case puzzleOther

    /// チップに出す名前。
    public var title: String {
        switch self {
        case .all: "すべて"
        case .ojisan: "おじさん"
        case .board: "盤"
        case .cards: "トランプ"
        case .mahjongHanafuda: "麻雀・花札"
        case .puzzleOther: "パズル・その他"
        }
    }

    /// 絞り込みに使えるカテゴリー（`all` を除く）。
    public static var filterable: [HubCategory] { allCases.filter { $0 != .all } }
}
