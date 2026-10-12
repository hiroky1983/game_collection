import Foundation
import Core

/// 盤面の VoiceOver 読み上げ文（#188 の横展開）。
///
/// 場札は「重ねた札の一部だけが見えている」表示なので、画面を見れば分かる
/// 「何列目の何枚目か」「上に何枚載っているか」「伏せ札が何枚あるか」が音声では一切伝わらない。
/// 読み上げ文はここに集約して純関数にし、View を組まずにテストできるようにする。
public enum SolitaireAccessibility {

    /// 1 枚の呼び名（例: "スペードのA" / "ジョーカー"）。
    public static func cardLabel(_ card: SolitaireCard) -> String {
        card.figure.spokenLabel
    }

    /// 場札の 1 枚（例: "3列目、5枚目、ハートの7、選択中"）。
    ///
    /// - Parameters:
    ///   - pile: 0 起点の列。
    ///   - position: 0 起点の「表向きの下から数えた位置」。
    ///   - aboveCount: この札の上に載っている表向きの枚数。
    ///   - hiddenCount: この列に残っている伏せ札の枚数。
    public static func tableauCardLabel(
        pile: Int,
        position: Int,
        aboveCount: Int,
        hiddenCount: Int,
        card: SolitaireCard,
        isSelected: Bool,
        isMovable: Bool
    ) -> String {
        var parts = [tr("%lld列目", pile + 1), tr("%lld枚目", position + 1), cardLabel(card)]
        if hiddenCount > 0 { parts.append(tr("伏せ札%lld枚", hiddenCount)) }
        if aboveCount > 0 { parts.append(tr("上に%lld枚", aboveCount)) }
        if isSelected { parts.append(tr("選択中")) }
        if !isMovable { parts.append(tr("動かせません")) }
        return parts.joined(separator: tr("、"))
    }

    /// 空の列。
    public static func emptyPileLabel(pile: Int) -> String {
        tr("%lld列目、空、キングだけ置けます", pile + 1)
    }

    /// 組札（例: "ハートの組札、7まで"）。
    public static func foundationLabel(suit: SolitaireSuit, rank: Int) -> String {
        let name = suit.playingCardSuit.spokenName
        guard rank > 0 else { return tr("%@の組札、空", name) }
        return tr("%1$@の組札、%2$@まで", name, SolitaireCard(suit, rank).figure.rankLabel)
    }

    /// 山札（伏せた束）。
    public static func stockLabel(remaining: Int) -> String {
        remaining > 0 ? tr("山札、残り%lld枚、タップでめくる", remaining) : tr("山札、空、タップで捨て札を戻す")
    }

    /// 捨て札の一番上。
    ///
    /// - Parameter covered: 3枚めくり（#498）で下に重なって見えている札（下から順）。
    ///   使えるのは一番上の1枚だけだが、次に何が控えているかは画面には出ているので
    ///   音声でも取れるようにする。空なら文言は 1枚めくりのときと変わらない。
    public static func wasteLabel(
        card: SolitaireCard?,
        isSelected: Bool,
        covered: [SolitaireCard] = []
    ) -> String {
        guard let card else { return tr("捨て札、空") }
        var parts = [tr("捨て札"), cardLabel(card)]
        if isSelected { parts.append(tr("選択中")) }
        if !covered.isEmpty {
            parts.append(tr("下に%@", covered.map(cardLabel).joined(separator: tr("、"))))
        }
        return parts.joined(separator: tr("、"))
    }

    /// ステータスバーの 1 行。
    /// - Parameter isLost: 敗北確定（#406）。告知を閉じたあとも音声で状態が分かるようにする
    ///   （画面には 🤔 が出続けるので、読み上げだけ何も言わないと状態が伝わらない）。
    /// - Parameter ruleLabel: 標準以外のルール名（「3枚めくり」）。帯に出しているときだけ渡す（#498・#1856）。
    public static func statusLabel(
        phase: SolitairePhase,
        elapsedSeconds: Int,
        moveCount: Int,
        isDeadEnd: Bool,
        isLost: Bool = false,
        ruleLabel: String? = nil
    ) -> String {
        let time = RecordFormat.time(elapsedSeconds)
        let base = ruleLabel.map { tr("経過%1$@、%2$lld手、ルールは%3$@", time, moveCount, $0) }
            ?? tr("経過%1$@、%2$lld手", time, moveCount)
        switch phase {
        case .won:
            return tr("クリア。%@", base)
        case .playing:
            if isDeadEnd { return tr("進める手がありません。%@", base) }
            return isLost ? tr("このままではクリアできません。%@", base) : base
        }
    }

    /// 「戻す」ボタン（#476）。**残り回数が音声だけで分かる**必要がある。
    ///
    /// 使い切っても枠は残る（押すと広告の提案が出る）ので、「戻す」とだけ読まれると
    /// 無料でまだ戻せると誤解される。
    public static func undoButtonLabel(remaining: Int) -> String {
        remaining > 0 ? tr("1手戻す、残り%lld回", remaining) : tr("1手戻す、残りなし")
    }

    public static func undoButtonHint(canUndo: Bool, remaining: Int) -> String {
        guard canUndo else { return tr("まだ戻せる手がありません") }
        return remaining > 0
            ? tr("無料で戻せるのは1局につき%lld回までです", SolitaireUndoBudget.free)
            : tr("広告を見ると%lld回ぶん補充できます", SolitaireUndoBudget.refill)
    }

    /// ジョーカーの所持ボタン（#406）。**所持しているかどうかが音声だけで分かる**必要がある。
    ///
    /// ボタンは持っていない間も枠を残す（見た目は薄くなるだけ）ので、
    /// 画面を見ずに「ジョーカー」とだけ読まれると、持っていないのに押せると誤解される。
    public static func jokerButtonLabel(hasJoker: Bool, isPlacing: Bool) -> String {
        if isPlacing { return tr("ジョーカーを置くのをやめる") }
        return hasJoker ? tr("ジョーカーを使う、1枚所持") : tr("ジョーカー、所持していません")
    }

    /// - Note: 補充の案内は**救済の告知が出る条件**（行き止まり = 有効手ゼロ、または
    ///   敗北確定）に合わせる。「行き止まりになったとき」とだけ言うと、指せる手が残っている
    ///   敗北確定でも広告が出ることが音声では伝わらない（PR #457 の CodeRabbit 指摘）。
    public static func jokerButtonHint(hasJoker: Bool, isPlacing: Bool) -> String {
        if isPlacing { return tr("置き先の列をタップすると置けます") }
        return hasJoker
            ? tr("押したあと、置きたい列をタップします")
            : tr("手詰まりかクリアできない局面になったとき、広告を見て1枚受け取れます")
    }

    /// 「ヒント」ボタン（#2025）。残り回数と広告の要否を音声だけで分かるようにする。
    public static func hintButtonLabel(freeRemaining: Int, needsAd: Bool, isThinking: Bool) -> String {
        if isThinking { return tr("ヒント、考え中") }
        return needsAd ? tr("ヒント（広告を見て表示）") : tr("ヒント（残り%lld回）", freeRemaining)
    }

    /// 示した手の読み上げ（例: "ヒント、ハートの7を3列目へ"）。`board` は動かす前の盤。
    public static func hintLabel(move: SolitaireMove, board: SolitaireBoard) -> String {
        func name(_ card: SolitaireCard?) -> String {
            guard let card else { return tr("札") }
            return cardLabel(card)
        }
        switch move {
        case .draw:
            return tr("ヒント、山札をめくります")
        case .wasteToFoundation:
            return tr("ヒント、捨て札の%@を組札へ", name(board.waste.last))
        case .wasteToTableau(let pile):
            return tr("ヒント、捨て札の%1$@を%2$lld列目へ", name(board.waste.last), pile + 1)
        case .tableauToFoundation(let pile):
            return tr("ヒント、%1$lld列目の%2$@を組札へ", pile + 1, name(board.tableau[pile].top))
        case .tableauToTableau(let from, let index, let to):
            let run = board.tableau[from].faceUp
            guard run.indices.contains(index) else { return tr("ヒント") }
            let count = run.count - index
            let what = count > 1 ? tr("%1$@から上の%2$lld枚", name(run[index]), count) : name(run[index])
            return tr("ヒント、%1$@を%2$lld列目へ", what, to + 1)
        case .placeJoker:
            return tr("ヒント")
        }
    }

    /// 救済の告知（#406）。行き止まりと敗北確定を読み分ける。
    ///
    /// - Note: 行き止まりは**画面の本文と同じ内容まで読む**（#491）。画面には
    ///   「山札をめくるか、盤面が進まない入れ替えしか残っていません」と出ており、
    ///   見出しの「進める手がありません」だけを読むと**合法手までゼロ**と伝わってしまう。
    ///   実際には K → 空列の入れ替えが残っており、告知は閉じて盤に触れる。
    public static func rescuePromptLabel(isDeadEnd: Bool, hasJoker: Bool) -> String {
        let head = isDeadEnd
            ? tr("進める手がありません。山札をめくるか、盤面が進まない入れ替えしか残っていません")
            : tr("このままではクリアできません")
        let action = hasJoker ? tr("ジョーカーが1枚使えます") : tr("広告を見るとジョーカーを1枚受け取れます")
        return tr("%1$@。%2$@", head, action)
    }
}
