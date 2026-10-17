/// 役の表示名と VoiceOver の読み上げ文。純関数にして、View を組まずにテストできるようにする。
public enum DiceComboText {
    /// 得点表に出す役の名前。
    public static func name(_ category: DiceComboCategory) -> String {
        switch category {
        case .ones:          return tr("1の目")
        case .twos:          return tr("2の目")
        case .threes:        return tr("3の目")
        case .fours:         return tr("4の目")
        case .fives:         return tr("5の目")
        case .sixes:         return tr("6の目")
        case .choice:        return tr("チョイス")
        case .fourDice:      return tr("フォーダイス")
        case .fullHouse:     return tr("フルハウス")
        case .smallStraight: return tr("Sストレート")
        case .bigStraight:   return tr("Bストレート")
        case .fiveDice:      return tr("ファイブダイス")
        }
    }

    /// 役の条件の短い説明（得点表の 2 行目）。
    public static func rule(_ category: DiceComboCategory) -> String {
        switch category {
        case .ones, .twos, .threes, .fours, .fives, .sixes:
            return tr("%lldの目の合計", category.face ?? 0)
        case .choice:        return tr("5個の合計")
        case .fourDice:      return tr("同じ目4個で5個の合計")
        case .fullHouse:     return tr("3個と2個で5個の合計")
        case .smallStraight: return tr("4つ続きで15点")
        case .bigStraight:   return tr("5つ続きで30点")
        case .fiveDice:      return tr("5個とも同じで50点")
        }
    }
}

public enum DiceComboAccessibility {
    /// サイコロ 1 個の読み上げ文（例: "サイコロ1、4、キープ中"）。
    public static func dieLabel(index: Int, value: Int, isHeld: Bool) -> String {
        let base = tr("サイコロ%1$lld、%2$lld", index + 1, value)
        return isHeld ? base + tr("、キープ中") : base
    }

    /// 出目の並びの読み上げ文（例: "出目 4と4と2と4と6、キープ 4と4と4"）。
    public static func diceLabel(dice: [Int], held: [Bool]) -> String {
        guard !dice.isEmpty else { return tr("サイコロはまだ振っていません") }
        let shown = dice.map(String.init).joined(separator: tr("と"))
        let kept = dice.indices.filter { held.indices.contains($0) && held[$0] }.map { String(dice[$0]) }
        if kept.isEmpty { return tr("出目 %@", shown) }
        return tr("出目 %1$@、キープ %2$@", shown, kept.joined(separator: tr("と")))
    }

    /// 得点表の 1 行の読み上げ文。
    ///
    /// - Parameters:
    ///   - scored: 入れた点（未記入なら nil）。
    ///   - preview: いまの出目で入れたときの点（入れられないときは nil）。
    public static func categoryLabel(_ category: DiceComboCategory, scored: Int?, preview: Int?) -> String {
        let name = DiceComboText.name(category)
        if let scored { return tr("%1$@、%2$lld点、記入済み", name, scored) }
        if let preview { return tr("%1$@、いま入れると%2$lld点", name, preview) }
        return tr("%@、未記入", name)
    }

    /// 振るボタンの読み上げ文。
    public static func rollLabel(remaining: Int) -> String {
        remaining > 0 ? tr("サイコロを振る、残り%lld回", remaining) : tr("サイコロを振る、もう振れません")
    }
}
