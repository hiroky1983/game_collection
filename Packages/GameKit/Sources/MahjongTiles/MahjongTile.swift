import Foundation

/// 標準の麻雀牌 34 種（数牌 27 + 字牌 7）。
///
/// 四人打ち麻雀（#106）が扱うのはこの型だけで、麻雀ソリティア専用の花牌・季節牌は
/// 混ざりようがない。「標準 34 種」と「ソリティア専用の追加牌」の区別を型で表すのが目的
/// （区別が値の中身の検査に頼っていると、役判定に花牌が紛れ込んでも実行時まで気づけない）。
public enum MahjongTile: Hashable, Codable, Sendable {
    /// 萬子 1〜9。
    case characters(Int)
    /// 筒子 1〜9。
    case circles(Int)
    /// 索子 1〜9。
    case bamboos(Int)
    /// 風牌。0=東 1=南 2=西 3=北。
    case wind(Int)
    /// 三元牌。0=中 1=發 2=白。
    case dragon(Int)

    /// 標準 34 種すべて。
    public static let all: [MahjongTile] =
        (1...9).map(MahjongTile.characters)
        + (1...9).map(MahjongTile.circles)
        + (1...9).map(MahjongTile.bamboos)
        + (0..<4).map(MahjongTile.wind)
        + (0..<3).map(MahjongTile.dragon)

    /// 牌を一意に表す短いキー（萬子 = m / 筒子 = p / 索子 = s / 風牌 = w / 三元牌 = d）。
    public var key: String {
        switch self {
        case .characters(let n): return "m\(n)"
        case .circles(let n):    return "p\(n)"
        case .bamboos(let n):    return "s\(n)"
        case .wind(let n):       return "w\(n)"
        case .dragon(let n):     return "d\(n)"
        }
    }

    /// 数牌（萬子・筒子・索子）なら 1〜9 の数、字牌なら nil。
    public var rank: Int? {
        switch self {
        case .characters(let n), .circles(let n), .bamboos(let n): return n
        case .wind, .dragon: return nil
        }
    }
}

/// 牌の絵柄。標準 34 種に、麻雀ソリティア専用の花牌・季節牌を加えたもの。
///
/// ソリティアは 144 枚（標準 34 種 × 4 = 136 + 花牌 4 + 季節牌 4）を配るのでこの型を使い、
/// 四人打ち麻雀は `MahjongTile` を直接使う。
public enum MahjongFace: Hashable, Sendable {
    /// 標準 34 種。
    case standard(MahjongTile)
    /// 花牌 0〜3（梅蘭菊竹）。ソリティア専用。
    case flower(Int)
    /// 季節牌 0〜3（春夏秋冬）。ソリティア専用。
    case season(Int)

    // 呼び出し側は `.characters(1)` のように種類を直接書けたほうが読みやすいので、
    // `.standard` で包む手間を隠す糖衣を用意する（列挙子と同じ書き味を保つ）。
    public static func characters(_ n: Int) -> MahjongFace { .standard(.characters(n)) }
    public static func circles(_ n: Int) -> MahjongFace { .standard(.circles(n)) }
    public static func bamboos(_ n: Int) -> MahjongFace { .standard(.bamboos(n)) }
    public static func wind(_ n: Int) -> MahjongFace { .standard(.wind(n)) }
    public static func dragon(_ n: Int) -> MahjongFace { .standard(.dragon(n)) }

    /// 標準 34 種ならその牌、ソリティア専用牌なら nil。
    public var standardTile: MahjongTile? {
        if case .standard(let tile) = self { return tile }
        return nil
    }

    /// 「同じ牌」とみなすためのキー。
    /// 花牌同士・季節牌同士は絵柄が違っても合わせられる（麻雀ソリティアの一般的なルール）。
    public var matchKey: String {
        switch self {
        case .standard(let tile): return tile.key
        case .flower:             return "flower"
        case .season:             return "season"
        }
    }

    /// 2 枚を取り除けるか（絵柄が合うか）。
    public func matches(_ other: MahjongFace) -> Bool {
        matchKey == other.matchKey
    }
}

// MARK: - Codable

/// 中断スナップショット（`Snapshots/mahjong.json`）に保存済みの盤面をそのまま読めるよう、
/// `.standard` を挟む前の平坦な列挙子と同じ JSON 表現（例: `{"characters":{"_0":1}}`）を維持する。
/// 自動合成に任せると `{"standard":{"_0":{"characters":{"_0":1}}}}` に変わり、
/// `FileSnapshotStore.load` はデコード失敗を nil で返すため、遊びかけの盤面が黙って消える。
extension MahjongFace: Codable {
    private enum Kind: String, CodingKey {
        case characters, circles, bamboos, wind, dragon, flower, season
    }

    /// 自動合成が associated value に使うキー名。
    private enum Payload: String, CodingKey {
        case _0
    }

    private var encoded: (kind: Kind, value: Int) {
        switch self {
        case .standard(.characters(let n)): return (.characters, n)
        case .standard(.circles(let n)):    return (.circles, n)
        case .standard(.bamboos(let n)):    return (.bamboos, n)
        case .standard(.wind(let n)):       return (.wind, n)
        case .standard(.dragon(let n)):     return (.dragon, n)
        case .flower(let n):                return (.flower, n)
        case .season(let n):                return (.season, n)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Kind.self)
        let (kind, value) = encoded
        var payload = container.nestedContainer(keyedBy: Payload.self, forKey: kind)
        try payload.encode(value, forKey: ._0)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Kind.self)
        guard container.allKeys.count == 1, let kind = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "牌の種類がちょうど 1 つではありません"
                )
            )
        }
        let payload = try container.nestedContainer(keyedBy: Payload.self, forKey: kind)
        let value = try payload.decode(Int.self, forKey: ._0)
        switch kind {
        case .characters: self = .standard(.characters(value))
        case .circles:    self = .standard(.circles(value))
        case .bamboos:    self = .standard(.bamboos(value))
        case .wind:       self = .standard(.wind(value))
        case .dragon:     self = .standard(.dragon(value))
        case .flower:     self = .flower(value)
        case .season:     self = .season(value)
        }
    }
}
