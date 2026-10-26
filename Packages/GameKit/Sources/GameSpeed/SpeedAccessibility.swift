import Core

/// VoiceOver の読み上げ文。札は記号ではなく「ハートの5」のように文字で読ませる。
///
/// スピードは CPU と同時に出し合うゲームだが、あなたの側に制限時間は無いので、
/// 手札・台札・山札を順に読んでから出せばよい。出せる札には「出せます」を添える。
public enum SpeedAccessibility {
    /// 札の呼び名（「ハートの5」「スペードのキング」）。
    public static func cardName(_ card: SpeedCard) -> String {
        card.figure.spokenLabel
    }

    /// 手札 1 枚の読み上げ。
    public static func handCardLabel(_ card: SpeedCard, isSelected: Bool, isPlayable: Bool) -> String {
        var parts = [cardName(card)]
        if isSelected { parts.append(tr("選択中")) }
        parts.append(isPlayable ? tr("出せます") : tr("いまは出せません"))
        return parts.joined(separator: tr("、"))
    }

    /// 台札 1 山の読み上げ。
    public static func pileLabel(index: Int, top: SpeedCard?) -> String {
        let side = index == 0 ? tr("左の台札") : tr("右の台札")
        guard let top else { return tr("%@、まだ札はありません", side) }
        return tr("%1$@、%2$@", side, cardName(top))
    }

    /// 山札の読み上げ。
    public static func stockLabel(of player: SpeedModel.Player, count: Int) -> String {
        let owner = player == .human ? tr("あなたの山札") : tr("CPUの山札")
        return count == 0 ? tr("%@、なし", owner) : tr("%1$@、残り%2$lld枚", owner, count)
    }

    /// CPU の手札の読み上げ（まとめて 1 要素）。
    public static func cpuHandLabel(_ hand: [SpeedCard], stockCount: Int) -> String {
        let cards = hand.isEmpty ? tr("なし") : hand.map(cardName).joined(separator: tr("、"))
        return tr("CPUの手札、%1$@。%2$@", cards, stockLabel(of: .cpu, count: stockCount))
    }

    /// 進行の 1 行。
    public static func statusLabel(
        phase: SpeedModel.Phase, isStuck: Bool, hasSelection: Bool,
        winner: SpeedModel.Player?, isDraw: Bool
    ) -> String {
        switch phase {
        case .idle:
            return tr("速さを選んで始めましょう")
        case .playing:
            if isStuck { return tr("どちらも出せません。めくってください") }
            if hasSelection { return tr("どちらの台札に置くか選んでください") }
            return tr("1つ違いの札を台札のほうへ払ってください")
        case .result:
            if isDraw { return tr("引き分け") }
            return winner == .human ? tr("あなたの勝ち") : tr("CPUの勝ち")
        }
    }
}
