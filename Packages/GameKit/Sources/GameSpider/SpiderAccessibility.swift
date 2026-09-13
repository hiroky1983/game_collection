import Foundation
import Core

/// 盤面の VoiceOver 読み上げ文（#188 の横展開・#717）。
///
/// 読み上げ文はここに集約して純関数にし、View を組まずにテストできるようにする。
public enum SpiderAccessibility {

    /// 1 枚の呼び名（例: "スペードのA"）。
    public static func cardLabel(_ card: SpiderCard) -> String {
        card.figure.spokenLabel
    }

    /// 場札の表向きの 1 枚（例: "3列目、5枚目、ハートの7、上に2枚、選択中"）。
    ///
    /// - Parameters:
    ///   - position: 0 起点の「下から数えた位置」（伏せ札を含む）。
    ///   - isMovable: そこから上を丸ごと動かせるか（同じスートで降順に揃っているか）。
    public static func tableauCardLabel(
        pile: Int,
        position: Int,
        aboveCount: Int,
        card: SpiderCard,
        isSelected: Bool,
        isMovable: Bool
    ) -> String {
        var parts = ["\(pile + 1)列目", "\(position + 1)枚目", cardLabel(card)]
        if aboveCount > 0 { parts.append("上に\(aboveCount)枚") }
        if isSelected { parts.append("選択中") }
        if !isMovable { parts.append("動かせません") }
        return parts.joined(separator: "、")
    }

    /// 列の伏せ札（例: "3列目、伏せ札4枚"）。
    public static func faceDownLabel(pile: Int, count: Int) -> String {
        "\(pile + 1)列目、伏せ札\(count)枚"
    }

    /// 空の列。どの札でも置けることまで読む。
    public static func emptyPileLabel(pile: Int) -> String {
        "\(pile + 1)列目、空、どの札でも置けます"
    }

    /// 山札（例: "山札、残り3回"）。空いた列があって配れないときはその理由まで読む。
    public static func stockLabel(dealsRemaining: Int, isBlockedByEmptyPile: Bool) -> String {
        guard dealsRemaining > 0 else { return "山札、空" }
        let base = "山札、残り\(dealsRemaining)回"
        return isBlockedByEmptyPile ? base + "、空いた列があるので配れません" : base
    }

    /// 完成した組（例: "完成した組、3組" / "完成した組、なし"）。
    public static func completedLabel(count: Int) -> String {
        count > 0 ? "完成した組、\(count)組" : "完成した組、なし"
    }

    /// ステータスバーの 1 行。
    public static func statusLabel(
        phase: SpiderPhase,
        suitCount: SpiderSuitCount,
        elapsedSeconds: Int,
        moveCount: Int,
        dealNumber: UInt64,
        dealsRemaining: Int,
        completedCount: Int,
        isDeadEnd: Bool
    ) -> String {
        let head = "\(suitCount.label)、配札\(dealNumber)番、経過\(RecordFormat.time(elapsedSeconds))、\(moveCount)手"
        switch phase {
        case .won:
            return "クリア。" + head
        case .playing:
            let body = head + "、\(completedCount)組完成、山札残り\(dealsRemaining)回"
            return isDeadEnd ? "指せる手がありません。\(body)" : body
        }
    }

    /// 「戻す」ボタン。**残り回数が音声だけで分かる**必要がある（フリーセルと同じ）。
    public static func undoButtonLabel(remaining: Int) -> String {
        remaining > 0 ? "1手戻す、残り\(remaining)回" : "1手戻す、残りなし"
    }

    public static func undoButtonHint(canUndo: Bool, remaining: Int) -> String {
        guard canUndo else { return "まだ戻せる手がありません" }
        return remaining > 0
            ? "無料で戻せるのは1局につき\(SpiderUndoBudget.free)回までです"
            : "広告を見ると\(SpiderUndoBudget.refill)回ぶん補充できます"
    }

    /// 行き止まりの告知。
    public static func deadEndPromptLabel(canUndo: Bool, remaining: Int) -> String {
        let head = "指せる手がありません。どの札も置き先がなく、山札も配れません"
        guard canUndo else { return "\(head)。新しい配札にできます" }
        return remaining > 0
            ? "\(head)。手を戻せます。残り\(remaining)回"
            : "\(head)。広告を見ると「戻す」を\(SpiderUndoBudget.refill)回ぶん補充できます"
    }
}
