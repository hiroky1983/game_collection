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
        var parts = ["\(pile + 1)列目", "\(position + 1)枚目", cardLabel(card)]
        if aboveCount > 0 { parts.append("上に\(aboveCount)枚") }
        if isSelected { parts.append("選択中") }
        if !isMovable { parts.append("動かせません") }
        return parts.joined(separator: "、")
    }

    /// 空の列。**クロンダイクと違い任意の札を置ける**ので、そこまで読む
    /// （「空」とだけ読むと、ソリティアを先に遊んだ人には「K だけ」と誤解される）。
    public static func emptyPileLabel(pile: Int) -> String {
        "\(pile + 1)列目、空、どの札でも置けます"
    }

    /// フリーセルの 1 枠（例: "フリーセル2、ダイヤのK、選択中"）。
    public static func cellLabel(index: Int, card: FreeCellCard?, isSelected: Bool) -> String {
        guard let card else { return "フリーセル\(index + 1)、空" }
        let base = "フリーセル\(index + 1)、\(cardLabel(card))"
        return isSelected ? base + "、選択中" : base
    }

    /// 組札（例: "ハートの組札、7まで"）。
    public static func foundationLabel(suit: PlayingCardSuit, rank: Int) -> String {
        guard rank > 0 else { return "\(suit.spokenName)の組札、空" }
        return "\(suit.spokenName)の組札、\(FreeCellCard(suit, rank).rankLabel)まで"
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
        let base = "配札\(dealNumber)番、経過\(RecordFormat.time(elapsedSeconds))、"
            + "\(moveCount)手、一度に\(maxMovableCount)枚まで動かせます"
        switch phase {
        case .won:
            return "クリア。配札\(dealNumber)番、経過\(RecordFormat.time(elapsedSeconds))、\(moveCount)手"
        case .playing:
            return isDeadEnd ? "指せる手がありません。\(base)" : base
        }
    }

    /// 「戻す」ボタン。**残り回数が音声だけで分かる**必要がある。
    ///
    /// 使い切っても枠は残る（押すと広告の提案が出る）ので、「戻す」とだけ読まれると
    /// 無料でまだ戻せると誤解される。
    public static func undoButtonLabel(remaining: Int) -> String {
        remaining > 0 ? "1手戻す、残り\(remaining)回" : "1手戻す、残りなし"
    }

    public static func undoButtonHint(canUndo: Bool, remaining: Int) -> String {
        guard canUndo else { return "まだ戻せる手がありません" }
        return remaining > 0
            ? "無料で戻せるのは1局につき\(FreeCellUndoBudget.free)回までです"
            : "広告を見ると\(FreeCellUndoBudget.refill)回ぶん補充できます"
    }

    /// 行き止まりの告知。
    ///
    /// - Note: フリーセルの行き止まりは**合法手が本当にゼロ**（`FreeCellBoard.isDeadEnd`）。
    ///   クロンダイクの「進む手が無い」（#491）と違って盤に触れる手が残っていないので、
    ///   そのまま「指せる手がありません」と言い切ってよい。
    public static func deadEndPromptLabel(canUndo: Bool, remaining: Int) -> String {
        let head = "指せる手がありません。フリーセルが全部埋まり、どの札も置き先がありません"
        guard canUndo else { return "\(head)。新しい配札にできます" }
        return remaining > 0
            ? "\(head)。手を戻せます。残り\(remaining)回"
            : "\(head)。広告を見ると「戻す」を\(FreeCellUndoBudget.refill)回ぶん補充できます"
    }
}
