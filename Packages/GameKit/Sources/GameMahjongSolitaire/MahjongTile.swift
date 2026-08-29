import Foundation

/// 盤上の 1 枚分の置き場所。
///
/// 座標は**半マス単位**で持つ。亀（タートル）型レイアウトの左右のヒレが行と行の間に
/// またがって置かれるため、整数マスでは表現できない。1 枚の牌は `hx...hx+1` × `hy...hy+1` の
/// 2×2 半マスを占める。
public struct MahjongPosition: Hashable, Codable, Sendable {
    /// 段。0 が最下段で、数字が大きいほど上に積まれている。
    public let layer: Int
    /// 左上の x 座標（半マス単位）。
    public let hx: Int
    /// 左上の y 座標（半マス単位）。
    public let hy: Int

    public init(layer: Int, hx: Int, hy: Int) {
        self.layer = layer
        self.hx = hx
        self.hy = hy
    }

    /// もう 1 枚と場所が重なるか（同じ段なら隣接、別の段なら覆っているかの判定に使う）。
    public func overlaps(_ other: MahjongPosition) -> Bool {
        abs(hx - other.hx) < 2 && abs(hy - other.hy) < 2
    }
}

/// 牌の絵柄。標準の 144 枚（数牌 3 種 × 9 × 4 + 風牌 4 × 4 + 三元牌 3 × 4 + 花牌 4 + 季節牌 4）。
public enum MahjongFace: Hashable, Codable, Sendable {
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
    /// 花牌 0〜3（梅蘭菊竹）。
    case flower(Int)
    /// 季節牌 0〜3（春夏秋冬）。
    case season(Int)

    /// 「同じ牌」とみなすためのキー。
    /// 花牌同士・季節牌同士は絵柄が違っても合わせられる（麻雀ソリティアの一般的なルール）。
    public var matchKey: String {
        switch self {
        case .characters(let n): return "m\(n)"
        case .circles(let n):    return "p\(n)"
        case .bamboos(let n):    return "s\(n)"
        case .wind(let n):       return "w\(n)"
        case .dragon(let n):     return "d\(n)"
        case .flower:            return "flower"
        case .season:            return "season"
        }
    }

    /// 2 枚を取り除けるか（絵柄が合うか）。
    public func matches(_ other: MahjongFace) -> Bool {
        matchKey == other.matchKey
    }
}
