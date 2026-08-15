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
