import Foundation

/// 取り札を種別ごとに束ねたもの（#2336）。画面は 光・タネ・短・カス の 4 列に札を重ねて並べる。
struct HanafudaCapturedGroup: Equatable {
    let kind: HanafudaKind
    let cards: [HanafudaCard]

    /// 基本の役（三光・タネ・タン・カス）が成り立つ枚数。見出しに「いまの枚数/この枚数」と出す。
    var goal: Int {
        switch kind {
        case .hikari:  return 3
        case .tane:    return 5
        case .tanzaku: return 5
        case .kasu:    return 10
        }
    }

    var isComplete: Bool { cards.count >= goal }

    /// 画面に並べる順（光・タネ・短冊・カス）で、枚数が 0 の種別も含めた 4 つ。
    static func groups(of cards: [HanafudaCard]) -> [HanafudaCapturedGroup] {
        [HanafudaKind.hikari, .tane, .tanzaku, .kasu].map { kind in
            HanafudaCapturedGroup(kind: kind, cards: cards.filter { $0.kind == kind })
        }
    }
}
