import Foundation
import Core

/// 盤面の VoiceOver 読み上げ文（#188 の横展開・#492）。
///
/// 場札は「重ねた札の一部だけが見えている」表示なので、画面を見れば分かる
/// 「何列目の何枚目か」「上に何枚載っているか」が音声では一切伝わらない。
/// 読み上げ文はここに集約して純関数にし、View を組まずにテストできるようにする。
public enum FreeCellAccessibility {

    /// 1 枚の呼び名（例: "スペードのA"）。
    public static func cardLabel(_ card: FreeCellCard) -> String {
        card.figure.spokenLabel
    }

    /// 場札の 1 枚（例: "3列目、5枚目、ハートの7、上に2枚、選択中"）。
    ///
    /// - Parameters:
    ///   - pile: 0 起点の列。
    ///   - position: 0 起点の「下から数えた位置」。
    ///   - aboveCount: この札の上に載っている枚数。
    ///   - isMovable: そこから上を丸ごと動かせるか（並びが揃っているか）。
    public static func tableauCardLabel(
        pile: Int,
        position: Int,
        aboveCount: Int,
        card: FreeCellCard,
        isSelected: Bool,
        isMovable: Bool
    ) -> String {
        var parts = [tr("%lld列目", pile + 1), tr("%lld枚目", position + 1), cardLabel(card)]
        if aboveCount > 0 { parts.append(tr("上に%lld枚", aboveCount)) }
        if isSelected { parts.append(tr("選択中")) }
        if !isMovable { parts.append(tr("動かせません")) }
        return parts.joined(separator: tr("、"))
    }

    /// 空の列。**クロンダイクと違い任意の札を置ける**ので、そこまで読む
    /// （「空」とだけ読むと、ソリティアを先に遊んだ人には「K だけ」と誤解される）。
    public static func emptyPileLabel(pile: Int) -> String {
        tr("%lld列目、空、どの札でも置けます", pile + 1)
    }

    /// フリーセルの 1 枠（例: "フリーセル2、ダイヤのK、選択中"）。
    public static func cellLabel(index: Int, card: FreeCellCard?, isSelected: Bool) -> String {
        guard let card else { return tr("フリーセル%lld、空", index + 1) }
        let base = tr("フリーセル%1$lld、%2$@", index + 1, cardLabel(card))
        return isSelected ? tr("%@、選択中", base) : base
    }

    /// 組札（例: "ハートの組札、7まで"）。
    public static func foundationLabel(suit: PlayingCardSuit, rank: Int) -> String {
        guard rank > 0 else { return tr("%@の組札、空", suit.spokenName) }
        return tr("%1$@の組札、%2$@まで", suit.spokenName, FreeCellCard(suit, rank).rankLabel)
    }

    /// ステータスバーの 1 行。
    ///
    /// **一度に動かせる枚数まで読む**。フリーセルで手が通らない理由のほとんどは
    /// 「並びは合っているが枚数の上限を超えている」で、画面ではフリーセルと空列を数えれば
    /// 分かるが、音声では読み上げないと永久に分からない。
    public static func statusLabel(
        phase: FreeCellPhase,
        elapsedSeconds: Int,
        moveCount: Int,
        dealNumber: UInt64,
        maxMovableCount: Int,
        isDeadEnd: Bool
    ) -> String {
        let deal = String(dealNumber)
        let time = RecordFormat.time(elapsedSeconds)
        let base = tr("配札%1$@番、経過%2$@、%3$lld手、一度に%4$lld枚まで動かせます",
                      deal, time, moveCount, maxMovableCount)
        switch phase {
        case .won:
            return tr("クリア。配札%1$@番、経過%2$@、%3$lld手", deal, time, moveCount)
        case .playing:
            return isDeadEnd ? tr("指せる手がありません。%@", base) : base
        }
    }

    /// 「戻す」ボタン。**残り回数が音声だけで分かる**必要がある。
    ///
    /// 使い切っても枠は残る（押すと広告の提案が出る）ので、「戻す」とだけ読まれると
    /// 無料でまだ戻せると誤解される。
    public static func undoButtonLabel(remaining: Int) -> String {
        remaining > 0 ? tr("1手戻す、残り%lld回", remaining) : tr("1手戻す、残りなし")
    }

    public static func undoButtonHint(canUndo: Bool, remaining: Int) -> String {
        guard canUndo else { return tr("まだ戻せる手がありません") }
        return remaining > 0
            ? tr("無料で戻せるのは1局につき%lld回までです", FreeCellUndoBudget.free)
            : tr("広告を見ると%lld回ぶん補充できます", FreeCellUndoBudget.refill)
    }

    /// 「ヒント」ボタン（#2025）。残り回数と広告の要否を音声だけで分かるようにする。
    public static func hintButtonLabel(freeRemaining: Int, needsAd: Bool, isThinking: Bool) -> String {
        if isThinking { return tr("ヒント、考え中") }
        return needsAd ? tr("ヒント（広告を見て表示）") : tr("ヒント（残り%lld回）", freeRemaining)
    }

    /// 示した手の読み上げ（例: "ヒント、ハートの7を3列目へ"）。`board` は動かす前の盤。
    public static func hintLabel(move: FreeCellMove, board: FreeCellBoard) -> String {
        let moved = FreeCellHint.movedCards(move, in: board)
        guard let first = moved.first else { return tr("ヒント") }
        let what = moved.count > 1 ? tr("%1$@から上の%2$lld枚", cardLabel(first), moved.count) : cardLabel(first)
        switch move {
        case .tableauToCell(_, let cell):
            return tr("ヒント、%1$@をフリーセル%2$lldへ", what, cell + 1)
        case .tableauToFoundation, .cellToFoundation:
            return tr("ヒント、%1$@を%2$@の組札へ", what, first.suit.spokenName)
        case .tableauToTableau(_, _, let to), .cellToTableau(_, let to):
            return tr("ヒント、%1$@を%2$lld列目へ", what, to + 1)
        }
    }

    /// 行き止まりの告知。
    ///
    /// - Note: フリーセルの行き止まりは**合法手が本当にゼロ**（`FreeCellBoard.isDeadEnd`）。
    ///   クロンダイクの「進む手が無い」（#491）と違って盤に触れる手が残っていないので、
    ///   そのまま「指せる手がありません」と言い切ってよい。
    public static func deadEndPromptLabel(canUndo: Bool, remaining: Int) -> String {
        let head = tr("指せる手がありません。フリーセルが全部埋まり、どの札も置き先がありません")
        guard canUndo else { return tr("%@。新しい配札にできます", head) }
        return remaining > 0
            ? tr("%1$@。手を戻せます。残り%2$lld回", head, remaining)
            : tr("%1$@。広告を見ると「戻す」を%2$lld回ぶん補充できます", head, FreeCellUndoBudget.refill)
    }
}
