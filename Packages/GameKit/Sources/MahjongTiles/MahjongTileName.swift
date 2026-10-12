import Foundation
import Core

/// 牌の呼び名（#188）。
///
/// `MahjongTileView` は絵柄を図形で描くだけなので、VoiceOver には何も伝わらない。
/// また「一萬」のような表記は読み上げると「いちまん（金額）」に化けやすいため、
/// **種類 + 数**の形に開いた語を使う。麻雀ソリティアと四人打ち麻雀（#106）で共有する。
public extension MahjongTile {
    /// いまの表示言語での呼び名（#2166）。
    var displayName: String { displayName(language: nil) }

    /// `language` での呼び名。nil はいまの表示言語。
    ///
    /// 中断データに入る文字列（四人打ち麻雀の役牌の名前）は表示言語に左右されないよう、
    /// `.development`（日本語）を明示して引く。
    func displayName(language: AppLanguage?) -> String {
        switch self {
        case .characters(let n): return tr("萬子の%lld", n, language: language)
        case .circles(let n):    return tr("筒子の%lld", n, language: language)
        case .bamboos(let n):    return tr("索子の%lld", n, language: language)
        case .wind(let n):
            switch n {
            case 0:  return tr("字牌の東", language: language)
            case 1:  return tr("字牌の南", language: language)
            case 2:  return tr("字牌の西", language: language)
            case 3:  return tr("字牌の北", language: language)
            // 値域外の牌（`isValid == false`）でも読み上げ文の生成で落ちないようにする。
            default: return tr("字牌の風牌", language: language)
            }
        case .dragon(let n):
            switch n {
            case 0:  return tr("字牌の中", language: language)
            case 1:  return tr("字牌の發", language: language)
            case 2:  return tr("字牌の白", language: language)
            default: return tr("字牌の三元牌", language: language)
            }
        }
    }
}

public extension MahjongFace {
    var displayName: String {
        switch self {
        case .standard(let tile): return tile.displayName
        case .flower(let n):
            switch n {
            case 0:  return tr("花牌の梅")
            case 1:  return tr("花牌の蘭")
            case 2:  return tr("花牌の菊")
            case 3:  return tr("花牌の竹")
            default: return tr("花牌の花")
            }
        case .season(let n):
            switch n {
            case 0:  return tr("季節牌の春")
            case 1:  return tr("季節牌の夏")
            case 2:  return tr("季節牌の秋")
            case 3:  return tr("季節牌の冬")
            default: return tr("季節牌の季節")
            }
        }
    }
}
