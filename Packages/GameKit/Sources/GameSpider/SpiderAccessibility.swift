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
        var parts = [tr("%lld列目", pile + 1), tr("%lld枚目", position + 1), cardLabel(card)]
        if aboveCount > 0 { parts.append(tr("上に%lld枚", aboveCount)) }
        if isSelected { parts.append(tr("選択中")) }
        if !isMovable { parts.append(tr("動かせません")) }
        return parts.joined(separator: tr("、"))
    }

    /// 列の伏せ札（例: "3列目、伏せ札4枚"）。
    public static func faceDownLabel(pile: Int, count: Int) -> String {
        tr("%1$lld列目、伏せ札%2$lld枚", pile + 1, count)
    }

    /// 空の列。どの札でも置けることまで読む。
    public static func emptyPileLabel(pile: Int) -> String {
        tr("%lld列目、空、どの札でも置けます", pile + 1)
    }

    /// 山札（例: "山札、残り3回"）。空いた列があって配れないときはその理由まで読む。
    public static func stockLabel(dealsRemaining: Int, isBlockedByEmptyPile: Bool) -> String {
        guard dealsRemaining > 0 else { return tr("山札、空") }
        let base = tr("山札、残り%lld回", dealsRemaining)
        return isBlockedByEmptyPile ? tr("%@、空いた列があるので配れません", base) : base
    }

    /// 完成した組（例: "完成した組、3組" / "完成した組、なし"）。
    public static func completedLabel(count: Int) -> String {
        count > 0 ? tr("完成した組、%lld組", count) : tr("完成した組、なし")
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
        let head = tr("%1$@、配札%2$@番、経過%3$@、%4$lld手",
                      suitCount.label, String(dealNumber), RecordFormat.time(elapsedSeconds), moveCount)
        switch phase {
        case .won:
            return tr("クリア。%@", head)
        case .playing:
            let body = tr("%1$@、%2$lld組完成、山札残り%3$lld回", head, completedCount, dealsRemaining)
            return isDeadEnd ? tr("指せる手がありません。%@", body) : body
        }
    }

    /// 「戻す」ボタン。**残り回数が音声だけで分かる**必要がある（フリーセルと同じ）。
    public static func undoButtonLabel(remaining: Int) -> String {
        remaining > 0 ? tr("1手戻す、残り%lld回", remaining) : tr("1手戻す、残りなし")
    }

    public static func undoButtonHint(canUndo: Bool, remaining: Int) -> String {
        guard canUndo else { return tr("まだ戻せる手がありません") }
        return remaining > 0
            ? tr("無料で戻せるのは1局につき%lld回までです", SpiderUndoBudget.free)
            : tr("広告を見ると%lld回ぶん補充できます", SpiderUndoBudget.refill)
    }

    /// 「ヒント」ボタン（#2025）。残り回数と広告の要否を音声だけで分かるようにする。
    public static func hintButtonLabel(freeRemaining: Int, needsAd: Bool, isThinking: Bool) -> String {
        if isThinking { return tr("ヒント、考え中") }
        return needsAd ? tr("ヒント（広告を見て表示）") : tr("ヒント（残り%lld回）", freeRemaining)
    }

    /// 示した手の読み上げ（例: "ヒント、ハートの7を3列目へ"）。`board` は動かす前の盤。
    public static func hintLabel(move: SpiderMove, board: SpiderBoard) -> String {
        switch move {
        case .deal:
            return tr("ヒント、山札を配ります")
        case .move(let from, let index, let to):
            guard board.piles.indices.contains(from), board.piles[from].cards.indices.contains(index) else { return tr("ヒント") }
            let run = board.piles[from].cards[index...]
            let what = run.count > 1 ? tr("%1$@から上の%2$lld枚", cardLabel(run[run.startIndex]), run.count) : cardLabel(run[run.startIndex])
            return tr("ヒント、%1$@を%2$lld列目へ", what, to + 1)
        }
    }

    /// 行き止まりの告知。
    public static func deadEndPromptLabel(canUndo: Bool, remaining: Int) -> String {
        let head = tr("指せる手がありません。どの札も置き先がなく、山札も配れません")
        guard canUndo else { return tr("%@。新しい配札にできます", head) }
        return remaining > 0
            ? tr("%1$@。手を戻せます。残り%2$lld回", head, remaining)
            : tr("%1$@。広告を見ると「戻す」を%2$lld回ぶん補充できます", head, SpiderUndoBudget.refill)
    }
}
