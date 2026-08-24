import Foundation
import MahjongTiles
@testable import GameMahjong

/// テスト用の手牌記法。麻雀で一般的な `123m456p789s11z` の形で書けるようにする。
///
/// 字牌は標準的な `z` 記法（1東 2南 3西 4北 5白 6發 7中）で書く。この記法は
/// 麻雀の文献・牌姿ツールと共通なので、**期待値を実際のルールに照らして確認できる**
/// （受け入れ条件の「期待値は実際の麻雀ルールに照らした具体的な手牌で検証する」）。
/// リポジトリ内部の `MahjongTile.dragon` は 0=中 / 1=發 / 2=白 の順なのでここで変換する。
enum MahjongNotation {

    static func tiles(_ text: String) -> [MahjongTile] {
        var result: [MahjongTile] = []
        var digits: [Int] = []
        for character in text {
            if let value = character.wholeNumberValue, (1...9).contains(value) {
                digits.append(value)
                continue
            }
            for digit in digits {
                guard let tile = make(suit: character, digit: digit) else {
                    fatalError("読めない牌姿です: \(text)")
                }
                result.append(tile)
            }
            digits = []
        }
        precondition(digits.isEmpty, "種類の指定が無い数が残っています: \(text)")
        return result
    }

    static func hand(_ text: String) -> MahjongHand {
        MahjongHand(tiles: tiles(text))
    }

    static func tile(_ text: String) -> MahjongTile {
        let parsed = tiles(text)
        precondition(parsed.count == 1, "1 枚だけ指定してください: \(text)")
        return parsed[0]
    }

    private static func make(suit: Character, digit: Int) -> MahjongTile? {
        switch suit {
        case "m": return .characters(digit)
        case "p": return .circles(digit)
        case "s": return .bamboos(digit)
        case "z":
            switch digit {
            case 1...4: return .wind(digit - 1)      // 東南西北
            case 5:     return .dragon(2)            // 白
            case 6:     return .dragon(1)            // 發
            case 7:     return .dragon(0)            // 中
            default:    return nil
            }
        default: return nil
        }
    }
}
