import Foundation
import MahjongTiles

/// VoiceOver の読み上げ文（#188 と同じ方針）。
///
/// 牌は図形で描くので、読み上げ文を作る純関数をここに切り出して View を組まずに検証できるようにする。
public enum MahjongAccessibility {

    /// 手牌の 1 枚。
    public static func handTileLabel(_ tile: MahjongTile, isDrawn: Bool, isDiscardable: Bool) -> String {
        var parts = [tile.displayName]
        if isDrawn { parts.append(tr("ツモ牌")) }
        if !isDiscardable { parts.append(tr("いまは切れません")) }
        return parts.joined(separator: listSeparator)
    }

    /// 河（捨て牌の並び）。牌が多いので枚数と直近の牌に絞る。
    public static func discardPileLabel(player: String, tiles: [MahjongTile]) -> String {
        guard let last = tiles.last else { return tr("%@の捨て牌はまだありません", player) }
        return tr("%1$@の捨て牌 %2$lld枚、最後は%3$@", player, tiles.count, last.displayName)
    }

    /// 局の見出し。
    public static func roundLabel(roundName: String, honba: Int, remainingTiles: Int) -> String {
        // 英語の複数形は最初の整数で選ばれるので、数ごとに別の文言にしてから区切りでつなぐ。
        var parts = [roundName]
        if honba > 0 { parts.append(tr("%lld本場", honba)) }
        parts.append(tr("山の残り%lld枚", remainingTiles))
        return parts.joined(separator: listSeparator)
    }

    /// 各家の状況。
    public static func playerLabel(
        name: String, score: Int, isRiichi: Bool, isCurrent: Bool, melds: [MahjongCall] = []
    ) -> String {
        var parts = [tr("%1$@、持ち点%2$lld点", name, score)]
        if isRiichi { parts.append(tr("立直中")) }
        if isCurrent { parts.append(tr("手番")) }
        if !melds.isEmpty {
            parts.append(melds.map { meldLabel($0) }.joined(separator: listSeparator))
        }
        return parts.joined(separator: listSeparator)
    }

    /// 晒している面子 1 つ。
    public static func meldLabel(_ meld: MahjongCall) -> String {
        let kind: String
        switch meld.kind {
        case .pon:       kind = tr("ポン")
        case .chi:       kind = tr("チー")
        case .openKan:   kind = tr("カン")
        case .addedKan:  kind = tr("加槓")
        case .closedKan: kind = tr("暗槓")
        }
        return kind + " " + meld.tiles.map(\.displayName).joined(separator: listSeparator)
    }

    /// 鳴きの選択肢 1 つ。手牌から使う牌まで読み上げて、取り方の違うチーを選び分けられるようにする。
    public static func callOptionLabel(_ option: MahjongCall) -> String {
        tr("%1$@、手牌から%2$@を使います", option.actionName, option.optionDetail)
    }

    /// 読み上げ文の区切り（日本語は「、」）。
    static var listSeparator: String { tr("、") }
}
