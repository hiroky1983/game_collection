import Foundation

/// 花札 48 枚の札種（#495）。
///
/// 点数そのものは持たせない。こいこいの得点は**役**で決まり、札 1 枚の点（20/10/5/1）は
/// 役の判定には一切使われないため（「タネ 5 枚で 1 文」のように**枚数**で数える）。
/// 点付きの札として持たせると、使われない値がテストの期待値に紛れ込む。
public enum HanafudaKind: Int, Codable, CaseIterable, Sendable, Equatable {
    /// 光札（5 枚）。
    case hikari = 0
    /// タネ札（9 枚）。
    case tane = 1
    /// 短冊札（10 枚）。
    case tanzaku = 2
    /// カス札（24 枚）。
    case kasu = 3

    /// 場・手札の並べ替えに使う優先度（強い札を先に見せる）。
    public var sortOrder: Int { rawValue }

    /// 画面と読み上げに出す短い名前。
    public var label: String {
        switch self {
        case .hikari:  return "光"
        case .tane:    return "タネ"
        case .tanzaku: return "短冊"
        case .kasu:    return "カス"
        }
    }

    /// 札の絵柄の帯に出す表記（#602）。**2 文字までに収める**。
    /// 帯には月の数字も並ぶため、`label` のままだと 12 月の短冊札で 4 文字になって潰れる。
    /// 赤短・青短の別は帯の色が示すので、短冊は「短」だけでよい。
    public var badgeLabel: String {
        self == .tanzaku ? "短" : label
    }
}

/// 短冊札の色分け。役（赤短・青短）の判定に使う。
public enum HanafudaRibbon: Int, Codable, CaseIterable, Sendable, Equatable {
    /// 赤短（文字入りの赤短冊。松・梅・桜の 3 枚）。
    case redPoem = 0
    /// 青短（牡丹・菊・紅葉の 3 枚）。
    case blue = 1
    /// 無地の赤短冊（藤・菖蒲・萩・柳の 4 枚）。役は「タン」にだけ数える。
    case plainRed = 2
}

/// 札 1 枚。
///
/// **保持するのは 0...47 の通し番号だけ**で、月・種別・名前はすべて静的な表から引く。
/// スナップショットに書き出すのも番号 1 個なので、保存データが小さく、
/// 復元時の妥当性検査も「範囲に入っているか」だけで済む（#520 と同じ姿勢）。
public struct HanafudaCard: Identifiable, Codable, Equatable, Hashable, Sendable, Comparable {
    /// 0...47。`(月 - 1) * 4 + 月内の並び` で決まる。
    public let id: Int

    public init(id: Int) {
        self.id = id
    }

    /// 範囲外の番号を弾いて生成する（壊れたスナップショットの復元に使う）。
    public init?(validating id: Int) {
        guard (0..<HanafudaCard.deckSize).contains(id) else { return nil }
        self.id = id
    }

    /// 山札の総枚数。
    public static let deckSize = 48

    /// 1...12。
    public var month: Int { id / 4 + 1 }

    public var kind: HanafudaKind { Self.table[id].kind }

    /// 「松に鶴」などの札名。
    public var name: String { Self.table[id].name }

    /// 短冊札の色。短冊以外は nil。
    public var ribbon: HanafudaRibbon? { Self.table[id].ribbon }

    /// 月の植物名（「松」「桜」など）。同じ月の 4 枚で共通。
    public var monthName: String { Self.monthNames[month - 1] }

    /// 柳の光札（小野道風。雨の札）。四光と雨四光を分けるのに使う。
    public var isRainMan: Bool { id == Self.rainManID }

    /// 菊に盃。月見酒・花見酒の相方で、タネ札でもある。
    public var isSakeCup: Bool { id == Self.sakeCupID }

    /// 芒に月。
    public var isMoon: Bool { id == Self.moonID }

    /// 桜に幕。
    public var isCurtain: Bool { id == Self.curtainID }

    // MARK: - 役の相方になる特定の札

    /// 柳に小野道風。
    public static let rainManID = 40
    /// 菊に盃。
    public static let sakeCupID = 32
    /// 芒に月。
    public static let moonID = 28
    /// 桜に幕。
    public static let curtainID = 8
    /// 萩に猪。
    public static let boarID = 24
    /// 紅葉に鹿。
    public static let deerID = 36
    /// 牡丹に蝶。
    public static let butterflyID = 20

    /// 猪鹿蝶の 3 枚。
    public static let inoshikachoIDs: Set<Int> = [boarID, deerID, butterflyID]

    // MARK: - 並び

    /// 手札・取り札の表示順。種別（光 → タネ → 短冊 → カス）で束ね、同種は月順にする。
    public static func < (lhs: HanafudaCard, rhs: HanafudaCard) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind.sortOrder < rhs.kind.sortOrder }
        return lhs.id < rhs.id
    }

    // MARK: - 山札

    /// 48 枚の並び（番号順）。シャッフルは呼び出し側で行う。
    public static var fullDeck: [HanafudaCard] {
        (0..<deckSize).map { HanafudaCard(id: $0) }
    }

    public static let monthNames = [
        "松", "梅", "桜", "藤", "菖蒲", "牡丹", "萩", "芒", "菊", "紅葉", "柳", "桐",
    ]

    // MARK: - 静的な札の表

    struct Entry {
        let kind: HanafudaKind
        let name: String
        let ribbon: HanafudaRibbon?

        init(_ kind: HanafudaKind, _ name: String, _ ribbon: HanafudaRibbon? = nil) {
            self.kind = kind
            self.name = name
            self.ribbon = ribbon
        }
    }

    /// 48 枚の定義。`id` がそのまま添字になる（`(月-1)*4 + 月内の並び`）。
    ///
    /// 各月の並びは「強い札 → 短冊 → カス」で固定する。この順序を崩すと `id` の意味が変わり、
    /// 保存済みのスナップショットが別の札として復元されるので、**足す・入れ替えることはできない**。
    static let table: [Entry] = [
        // 1月 松
        Entry(.hikari, "松に鶴"), Entry(.tanzaku, "松に赤短", .redPoem),
        Entry(.kasu, "松のカス"), Entry(.kasu, "松のカス"),
        // 2月 梅
        Entry(.tane, "梅に鶯"), Entry(.tanzaku, "梅に赤短", .redPoem),
        Entry(.kasu, "梅のカス"), Entry(.kasu, "梅のカス"),
        // 3月 桜
        Entry(.hikari, "桜に幕"), Entry(.tanzaku, "桜に赤短", .redPoem),
        Entry(.kasu, "桜のカス"), Entry(.kasu, "桜のカス"),
        // 4月 藤
        Entry(.tane, "藤に不如帰"), Entry(.tanzaku, "藤に短冊", .plainRed),
        Entry(.kasu, "藤のカス"), Entry(.kasu, "藤のカス"),
        // 5月 菖蒲
        Entry(.tane, "菖蒲に八橋"), Entry(.tanzaku, "菖蒲に短冊", .plainRed),
        Entry(.kasu, "菖蒲のカス"), Entry(.kasu, "菖蒲のカス"),
        // 6月 牡丹
        Entry(.tane, "牡丹に蝶"), Entry(.tanzaku, "牡丹に青短", .blue),
        Entry(.kasu, "牡丹のカス"), Entry(.kasu, "牡丹のカス"),
        // 7月 萩
        Entry(.tane, "萩に猪"), Entry(.tanzaku, "萩に短冊", .plainRed),
        Entry(.kasu, "萩のカス"), Entry(.kasu, "萩のカス"),
        // 8月 芒
        Entry(.hikari, "芒に月"), Entry(.tane, "芒に雁"),
        Entry(.kasu, "芒のカス"), Entry(.kasu, "芒のカス"),
        // 9月 菊
        Entry(.tane, "菊に盃"), Entry(.tanzaku, "菊に青短", .blue),
        Entry(.kasu, "菊のカス"), Entry(.kasu, "菊のカス"),
        // 10月 紅葉
        Entry(.tane, "紅葉に鹿"), Entry(.tanzaku, "紅葉に青短", .blue),
        Entry(.kasu, "紅葉のカス"), Entry(.kasu, "紅葉のカス"),
        // 11月 柳
        Entry(.hikari, "柳に小野道風"), Entry(.tane, "柳に燕"),
        Entry(.tanzaku, "柳に短冊", .plainRed), Entry(.kasu, "柳に鬼札"),
        // 12月 桐
        Entry(.hikari, "桐に鳳凰"), Entry(.kasu, "桐のカス"),
        Entry(.kasu, "桐のカス"), Entry(.kasu, "桐のカス"),
    ]
}
