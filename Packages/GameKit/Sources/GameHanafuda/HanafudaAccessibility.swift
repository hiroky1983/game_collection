import Foundation

/// VoiceOver の読み上げ文（#188 の規約に合わせ、View を組まずに検証できる純関数にする）。
public enum HanafudaSpeech {

    /// 札 1 枚。**必ず月から読む**（合わせは月でしか起きないため、絵柄より先に来る情報）。
    public static func label(for card: HanafudaCard) -> String {
        "\(card.month)月 \(card.name) \(card.kind.label)"
    }

    /// 手札の 1 枚。取れる相手があるかまで読む。
    public static func handLabel(for card: HanafudaCard, matches: [HanafudaCard]) -> String {
        let base = label(for: card)
        guard !matches.isEmpty else { return "\(base)。合う場札なし" }
        return "\(base)。場の\(matches.count)枚と合う"
    }

    /// 取り札の要約。役に効く枚数を種別ごとに読む。
    public static func capturedSummary(_ cards: [HanafudaCard]) -> String {
        guard !cards.isEmpty else { return "取り札なし" }
        let parts = HanafudaKind.allCases.compactMap { kind -> String? in
            let count = cards.filter { $0.kind == kind }.count
            return count > 0 ? "\(kind.label)\(count)枚" : nil
        }
        return parts.joined(separator: "、")
    }

    /// 成立している役の読み。
    public static func yakuSummary(_ hits: [HanafudaYakuHit]) -> String {
        guard !hits.isEmpty else { return "役なし" }
        let total = hits.reduce(0) { $0 + $1.points }
        let names = hits.map { "\($0.name)\($0.points)文" }.joined(separator: "、")
        return "\(names)。合計\(total)文"
    }

    /// 局の決着の読み。
    public static func roundResultSummary(_ result: HanafudaRoundResult) -> String {
        guard let winner = result.winner else { return "流局。だれもあがれませんでした" }
        let multiplier = result.reasons.isEmpty ? "" : "。\(result.reasons.joined(separator: "、"))"
        return "\(winner.label)のあがり。\(yakuSummary(result.hits))\(multiplier)。獲得\(result.score)文"
    }
}
