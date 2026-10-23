import Foundation
import Core

/// カードの VoiceOver 読み上げ文（#188）。
///
/// `DaifugoCardView` はランク文字とスート記号（♠♥♦♣）だけで 1 枚を表しており、
/// 記号は読み上げても意味が伝わらない。読み上げ文はここに集約して純関数にし、
/// View を組まずにテストできるようにする。
public enum DaifugoAccessibility {
    /// スートの読み（ジョーカーは nil）。トランプ共通基盤（CoreEngine）の読みをそのまま使う（#2166）。
    public static func suitName(_ suit: DaifugoSuit?) -> String? {
        suit.map { $0.playing.spokenName }
    }

    /// ランクの読み（A / J / Q / K は記号のままだと読みが安定しない）。
    public static func rankName(_ card: DaifugoCard) -> String {
        switch card.rank {
        case DaifugoRules.jokerRank: return tr("ジョーカー")
        case 1:  return tr("エース")
        case 11: return tr("ジャック")
        case 12: return tr("クイーン")
        case 13: return tr("キング")
        default: return "\(card.rank)"
        }
    }

    /// カード 1 枚の呼び名（例: "ハートの7"）。
    public static func cardName(_ card: DaifugoCard) -> String {
        guard let suit = suitName(card.suit) else { return rankName(card) }
        return tr("%1$@の%2$@", suit, rankName(card))
    }

    /// 手札 1 枚の読み上げ文。選択中かどうかは見た目では浮き上がりと枠色でしか分からない。
    /// ヒント表示（#190）も枠色と明度でしか表していないので、状態を文字にして補う。
    public static func handCardLabel(
        _ card: DaifugoCard,
        isSelected: Bool,
        hint: DaifugoCardHint = .none
    ) -> String {
        var label = cardName(card)
        if isSelected { label = tr("%@、選択中", label) }
        switch hint {
        case .none:       break
        case .playable:   label = tr("%@、出せます", label)
        case .unplayable: label = tr("%@、いまは出せません", label)
        }
        return label
    }

    /// 場に出ている組の読み上げ文。空なら「場は流れています」。
    ///
    /// 出し手（`ownerName`）は画面ではバッジで示しているだけなので、読み上げにも足す（#193）。
    public static func fieldLabel(_ cards: [DaifugoCard], ownerName: String? = nil) -> String {
        guard !cards.isEmpty else { return tr("場は流れています") }
        let cardsText = tr("場のカード、%@", cards.map(cardName).joined(separator: tr("、")))
        guard let ownerName else { return cardsText }
        return tr("%1$@。%2$@が出しました", cardsText, ownerName)
    }

    /// 交換の帯の文（#2607）。受け取った札・渡した札の順で 1 行ずつ。画面は記号（♠A）、読み上げはスートの読み（スペードのエース）。
    public static func exchangeLines(_ notice: DaifugoExchangeNotice, partnerName: String, spoken: Bool) -> [String] {
        func cards(_ list: [DaifugoCard]) -> String {
            spoken
                ? list.map(cardName).joined(separator: tr("、"))
                : list.map { ($0.suit?.symbol ?? "") + $0.rankLabel }.joined(separator: " ")
        }
        var lines: [String] = []
        if !notice.received.isEmpty { lines.append(tr("%1$@から %2$@ を受け取りました", partnerName, cards(notice.received))) }
        if !notice.gave.isEmpty { lines.append(tr("%1$@へ %2$@ を渡しました", partnerName, cards(notice.gave))) }
        return lines
    }

    /// しばり中の札の読み上げ文（#2605）。記号のままだと読みが安定しないのでスートの読みで伝える。
    public static func bindLabel(_ suits: Set<DaifugoSuit>) -> String {
        let names = suits.sorted { $0.rawValue < $1.rawValue }.compactMap { suitName($0) }
        return tr("しばり中、%@のカードだけ出せます", names.joined(separator: tr("、")))
    }

    /// CPU の席 1 つの読み上げ文。手番かどうかは画面ではアイコンの色でしか示さないので、文字にして足す（#2495）。
    /// 名前・残り枚数・直前の動き（空なら省く）を 1 まとまりに読ませる。
    public static func seatLabel(name: String, remaining: Int, action: String, isTurn: Bool) -> String {
        var parts = [name, tr("残り%lld枚", remaining)]
        if !action.isEmpty { parts.append(action) }
        if isTurn { parts.append(tr("%@の番", name)) }
        return parts.joined(separator: tr("、"))
    }

    /// ルール上の出来事の一言説明（#2721）。画面に出す文と読み上げ文は同じ。
    public static func ruleEventText(_ event: DaifugoRuleEvent) -> String {
        switch event {
        case .eightCut:
            return tr("8切り：場が流れて、8を出した人から")
        case .revolution:
            return tr("革命：カードの強さが逆になります")
        case .counterRevolution:
            return tr("革命返し：カードの強さが元に戻ります")
        case .bind(let suits):
            return tr("しばり：場が流れるまで%@のカードだけ出せます", DaifugoRules.bindLabel(suits))
        case .foulFinish(let includesEight):
            return includesEight
                ? tr("反則上がり：最後が 2・8・ジョーカーなので最下位です")
                : tr("反則上がり：最後が 2・ジョーカーなので最下位です")
        }
    }
}
