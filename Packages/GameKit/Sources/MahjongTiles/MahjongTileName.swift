import Foundation

/// 牌の呼び名（#188）。
///
/// `MahjongTileView` は絵柄を図形で描くだけなので、VoiceOver には何も伝わらない。
/// また「一萬」のような表記は読み上げると「いちまん（金額）」に化けやすいため、
/// **種類 + 数**の形に開いた語を使う。麻雀ソリティアと四人打ち麻雀（#106）で共有する。
public extension MahjongTile {
    var displayName: String {
        switch self {
        case .characters(let n): return "萬子の\(n)"
        case .circles(let n):    return "筒子の\(n)"
        case .bamboos(let n):    return "索子の\(n)"
        case .wind(let n):       return "字牌の\(Self.windNames[safe: n] ?? "風牌")"
        case .dragon(let n):     return "字牌の\(Self.dragonNames[safe: n] ?? "三元牌")"
        }
    }

    private static let windNames = ["東", "南", "西", "北"]
    private static let dragonNames = ["中", "發", "白"]
}

public extension MahjongFace {
    var displayName: String {
        switch self {
        case .standard(let tile): return tile.displayName
        case .flower(let n):      return "花牌の\(Self.flowerNames[safe: n] ?? "花")"
        case .season(let n):      return "季節牌の\(Self.seasonNames[safe: n] ?? "季節")"
        }
    }

    private static let flowerNames = ["梅", "蘭", "菊", "竹"]
    private static let seasonNames = ["春", "夏", "秋", "冬"]
}

private extension Array {
    /// 値域外の牌（`isValid == false`）でも読み上げ文の生成で落ちないようにする。
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
