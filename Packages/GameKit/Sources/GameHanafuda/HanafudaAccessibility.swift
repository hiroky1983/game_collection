import Foundation

/// VoiceOver の読み上げ文（#188 の規約に合わせ、View を組まずに検証できる純関数にする）。
/// 文言は表示言語で引く（#2166）。
public enum HanafudaSpeech {

    /// 札 1 枚。**必ず月から読む**（合わせは月でしか起きないため、絵柄より先に来る情報）。
    public static func label(for card: HanafudaCard) -> String {
        // 種別ごとに文を分ける（英語の種別名は役名「Tane (Animals)」と別の語にするため・#2166）。
        switch card.kind {
        case .hikari:  return tr("%lld月 %@ 光", card.month, card.displayName)
        case .tane:    return tr("%lld月 %@ タネ", card.month, card.displayName)
        case .tanzaku: return tr("%lld月 %@ 短冊", card.month, card.displayName)
        case .kasu:    return tr("%lld月 %@ カス", card.month, card.displayName)
        }
    }

    /// 手札の 1 枚。取れる相手があるかまで読む。
    public static func handLabel(for card: HanafudaCard, matches: [HanafudaCard]) -> String {
        let base = label(for: card)
        guard !matches.isEmpty else { return tr("%@。合う場札なし", base) }
        return tr("%1$@。場の%2$lld枚と合う", base, matches.count)
    }

    /// 場の 1 枚（#2481）。手札を選んで取る札を選ぶ待ちのときだけ、取れる札かどうかまで読む。
    public static func fieldLabel(for card: HanafudaCard, isSelecting: Bool, isCandidate: Bool) -> String {
        let base = label(for: card)
        guard isSelecting else { return base }
        return isCandidate ? tr("%@。取れます", base) : tr("%@。合いません", base)
    }

    /// 取り札の要約。役に効く枚数を種別ごとに読む。
    public static func capturedSummary(_ cards: [HanafudaCard]) -> String {
        guard !cards.isEmpty else { return tr("取り札なし") }
        let parts = HanafudaKind.allCases.compactMap { kind -> String? in
            let count = cards.filter { $0.kind == kind }.count
            return count > 0 ? countLabel(kind, count) : nil
        }
        return parts.joined(separator: tr("、"))
    }

    /// 種別ごとの枚数（「光1枚」）。英語は数で単語が変わるので種別ごとに複数形の表を引く。
    static func countLabel(_ kind: HanafudaKind, _ count: Int) -> String {
        switch kind {
        case .hikari:  return tr("光%lld枚", count)
        case .tane:    return tr("タネ%lld枚", count)
        case .tanzaku: return tr("短冊%lld枚", count)
        case .kasu:    return tr("カス%lld枚", count)
        }
    }

    /// 成立している役の読み。
    public static func yakuSummary(_ hits: [HanafudaYakuHit]) -> String {
        guard !hits.isEmpty else { return tr("役なし") }
        let total = hits.reduce(0) { $0 + $1.points }
        let names = hits.map { tr("%@%lld文", $0.name, $0.points) }.joined(separator: tr("、"))
        return tr("%@。合計%lld文", names, total)
    }

    /// 局の決着の読み。
    public static func roundResultSummary(_ result: HanafudaRoundResult) -> String {
        guard let winner = result.winner else { return tr("流局。だれもあがれませんでした") }
        let summary = yakuSummary(result.hits)
        let score = result.score
        guard !result.reasons.isEmpty else {
            return winner == .human
                ? tr("あなたのあがり。%@。獲得%lld文", summary, score)
                : tr("CPUのあがり。%@。獲得%lld文", summary, score)
        }
        let multiplier = result.reasons.map(HanafudaScoring.reasonLabel).joined(separator: tr("、"))
        return winner == .human
            ? tr("あなたのあがり。%1$@。%2$@。獲得%3$lld文", summary, multiplier, score)
            : tr("CPUのあがり。%1$@。%2$@。獲得%3$lld文", summary, multiplier, score)
    }

    /// CPU の手番が終わったときの読み上げ文（#2280）。手札の 1 枚、山札のめくり札、こいこいの順に読む。
    /// 取った枚数だけでなく、取れなかったとき（場に出しただけ）も伝える。
    public static func cpuTurnAnnouncement(_ turn: HanafudaCPUTurnSummary) -> String {
        var parts: [String] = []
        parts.append(turn.playedCaptured > 0
            ? tr("CPUは%1$@で%2$lld枚取りました", turn.played.displayName, turn.playedCaptured)
            : tr("CPUは%@を場に出しました", turn.played.displayName))
        if let drawn = turn.drawn {
            parts.append(turn.drawnCaptured > 0
                ? tr("めくり札「%1$@」で%2$lld枚取りました", drawn.displayName, turn.drawnCaptured)
                : tr("めくり札は「%@」でした", drawn.displayName))
        }
        if turn.koiKoi { parts.append(tr("CPUがこいこいしました")) }
        return parts.joined(separator: tr("。"))
    }
}
