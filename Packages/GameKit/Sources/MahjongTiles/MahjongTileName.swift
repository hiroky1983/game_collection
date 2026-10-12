import Foundation

/// 牌の呼び名（#188）。
///
/// `MahjongTileView` は絵柄を図形で描くだけなので、VoiceOver には何も伝わらない。
/// また「一萬」のような表記は読み上げると「いちまん（金額）」に化けやすいため、
/// **種類 + 数**の形に開いた語を使う。麻雀ソリティアと四人打ち麻雀（#106）で共有する。
public extension MahjongTile {
    var displayName: String {
        switch self {
        case .characters(let n): return tr("萬子の%lld", n)
        case .circles(let n):    return tr("筒子の%lld", n)
        case .bamboos(let n):    return tr("索子の%lld", n)
        case .wind(let n):       return Self.windNames[safe: n].map { tr("字牌の%@", $0) } ?? tr("字牌の風牌")
        case .dragon(let n):     return Self.dragonNames[safe: n].map { tr("字牌の%@", $0) } ?? tr("字牌の三元牌")
        }
    }

    // 読み上げ用の名前（表示言語に従う）。牌の面に描く文字（`MahjongTileView`）とは別物。
    private static var windNames: [String] { [tr("東"), tr("南"), tr("西"), tr("北")] }
    private static var dragonNames: [String] { [tr("中"), tr("發"), tr("白")] }
}

public extension MahjongFace {
    var displayName: String {
        switch self {
        case .standard(let tile): return tile.displayName
        case .flower(let n):      return Self.flowerNames[safe: n].map { tr("花牌の%@", $0) } ?? tr("花牌の花")
        case .season(let n):      return Self.seasonNames[safe: n].map { tr("季節牌の%@", $0) } ?? tr("季節牌の季節")
        }
    }

    private static var flowerNames: [String] { [tr("梅"), tr("蘭"), tr("菊"), tr("竹")] }
    private static var seasonNames: [String] { [tr("春"), tr("夏"), tr("秋"), tr("冬")] }
}

private extension Array {
    /// 値域外の牌（`isValid == false`）でも読み上げ文の生成で落ちないようにする。
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
