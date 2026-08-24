import Foundation
import MahjongTiles

/// VoiceOver の読み上げ文（#188 と同じ方針）。
///
/// 牌は図形で描くので、読み上げ文を作る純関数をここに切り出して View を組まずに検証できるようにする。
public enum MahjongAccessibility {

    /// 手牌の 1 枚。
    public static func handTileLabel(_ tile: MahjongTile, isDrawn: Bool, isDiscardable: Bool) -> String {
        var parts = [tile.displayName]
        if isDrawn { parts.append("ツモ牌") }
        if !isDiscardable { parts.append("いまは切れません") }
        return parts.joined(separator: "、")
    }

    /// 河（捨て牌の並び）。牌が多いので枚数と直近の牌に絞る。
    public static func discardPileLabel(player: String, tiles: [MahjongTile]) -> String {
        guard let last = tiles.last else { return "\(player)の捨て牌はまだありません" }
        return "\(player)の捨て牌 \(tiles.count)枚、最後は\(last.displayName)"
    }

    /// 局の見出し。
    public static func roundLabel(roundNumber: Int, honba: Int, remainingTiles: Int) -> String {
        let honbaText = honba > 0 ? "\(honba)本場、" : ""
        return "東\(roundNumber)局、\(honbaText)山の残り\(remainingTiles)枚"
    }

    /// 各家の状況。
    public static func playerLabel(name: String, score: Int, isRiichi: Bool, isCurrent: Bool) -> String {
        var parts = ["\(name)、持ち点\(score)点"]
        if isRiichi { parts.append("立直中") }
        if isCurrent { parts.append("手番") }
        return parts.joined(separator: "、")
    }
}
