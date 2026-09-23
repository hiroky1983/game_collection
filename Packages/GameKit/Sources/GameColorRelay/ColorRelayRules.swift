import Foundation

/// 手札 1 枚のヒント表示の状態（大富豪 #190 と同じ形）。
public enum RelayCardHint: Equatable, Sendable {
    case none
    case playable
    case unplayable
}

/// 手札全体のヒント。出せる札と出せない札を分けて持つ。
public struct RelayHandHint: Equatable, Sendable {
    public let playable: Set<Int>
    public let unplayable: Set<Int>

    public init(playable: Set<Int>, unplayable: Set<Int>) {
        self.playable = playable
        self.unplayable = unplayable
    }

    public func state(for cardID: Int) -> RelayCardHint {
        if playable.contains(cardID) { return .playable }
        if unplayable.contains(cardID) { return .unplayable }
        return .none
    }
}

/// いろリレーのルールを**乱数も状態も持たない純粋関数**として閉じ込めた層。
///
/// Model（`ColorRelayModel`）は進行と永続化だけを持ち、出せるかどうか・CPU の選択はここに集約する。
public enum ColorRelayRules {
    /// 最初に配る枚数。
    public static let initialHandCount = 7

    // MARK: - 出せるか

    /// `card` を、場の札 `top`（いまの色が `activeColor`）の上に出せるか。
    ///
    /// 万能札はいつでも出せる。それ以外は**色が同じ**か**種類（数字・記号）が同じ**なら出せる。
    /// いろがえの上に出すときは選ばれた色（`activeColor`）だけを見る（`top` 自身は色を持たない）。
    public static func canPlay(_ card: RelayCard, onto top: RelayCard, activeColor: RelayColor) -> Bool {
        if card.isWild { return true }
        if card.color == activeColor { return true }
        return card.kind == top.kind
    }

    /// 手札のうち出せる札の ID。
    public static func playableCardIDs(
        hand: [RelayCard], top: RelayCard, activeColor: RelayColor
    ) -> Set<Int> {
        Set(hand.filter { canPlay($0, onto: top, activeColor: activeColor) }.map(\.id))
    }

    // MARK: - CPU

    /// 手札で最も多い色（同数なら `RelayColor` の並び順で先のもの）。万能札を出すときに選ぶ色。
    /// 色札を 1 枚も持っていなければ `.red`。
    public static func dominantColor(in hand: [RelayCard]) -> RelayColor {
        var counts: [RelayColor: Int] = [:]
        for card in hand {
            if let color = card.color { counts[color, default: 0] += 1 }
        }
        return RelayColor.allCases.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) } ?? .red
    }

    /// CPU の 1 手（貪欲法・難易度は持たない）。出せる札が無ければ nil（= 山から引く）。
    ///
    /// 優先順位:
    /// 1. **次の人の手札が 2 枚以下**なら、番を奪う札（いろがえ+4 → +2 → とばし → ぎゃく）を先に出す
    /// 2. 色の合う**数字札**を大きい数字から（手札の多い色を残すため、いまの色と同じ色を優先）
    /// 3. 色の合う特殊札（+2 → とばし → ぎゃく）
    /// 4. 色は違うが種類が同じ札（数字・記号が同じ）。**手札で最も多い色**へ寄せられる札を優先
    /// 5. いろがえ、最後にいろがえ+4（万能札は温存する）
    public static func cpuPlay(
        hand: [RelayCard], top: RelayCard, activeColor: RelayColor, nextHandCount: Int
    ) -> RelayCard? {
        let playable = hand.filter { canPlay($0, onto: top, activeColor: activeColor) }
        guard !playable.isEmpty else { return nil }
        let dominant = dominantColor(in: hand)

        if nextHandCount <= 2 {
            let attackOrder: [RelayKind] = [.wildDrawFour, .drawTwo, .skip, .reverse]
            for kind in attackOrder {
                if let card = playable.first(where: { $0.kind == kind }) { return card }
            }
        }

        func priority(_ card: RelayCard) -> (Int, Int, Int) {
            let matchesColor = card.color == activeColor
            let towardDominant = card.color == dominant
            switch card.kind {
            case .number(let n):
                // 色が合う数字札 → 種類が合う数字札。大きい数字から捨てる。
                return (matchesColor ? 0 : (towardDominant ? 2 : 3), -n, card.id)
            case .drawTwo, .skip, .reverse:
                return (matchesColor ? 1 : (towardDominant ? 2 : 3), card.kind.sortOrder, card.id)
            case .wild:
                return (4, 0, card.id)
            case .wildDrawFour:
                return (5, 0, card.id)
            }
        }
        return playable.min { priority($0) < priority($1) }
    }

    // MARK: - 順位

    /// 上がった人を 1 位に、残りは**手札の少ない順**（同数はプレイヤー番号順）で並べた最終順位。
    public static func ranking(hands: [[RelayCard]], winner: Int) -> [Int] {
        let others = hands.indices
            .filter { $0 != winner }
            .sorted { (hands[$0].count, $0) < (hands[$1].count, $1) }
        return [winner] + others
    }
}
