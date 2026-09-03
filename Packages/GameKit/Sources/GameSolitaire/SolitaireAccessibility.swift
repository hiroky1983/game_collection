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
        var parts = ["\(pile + 1)列目", "\(position + 1)枚目", cardLabel(card)]
        if hiddenCount > 0 { parts.append("伏せ札\(hiddenCount)枚") }
        if aboveCount > 0 { parts.append("上に\(aboveCount)枚") }
        if isSelected { parts.append("選択中") }
        if !isMovable { parts.append("動かせません") }
        return parts.joined(separator: "、")
    }

    /// 空の列。
    public static func emptyPileLabel(pile: Int) -> String {
        "\(pile + 1)列目、空、キングだけ置けます"
    }

    /// 組札（例: "ハートの組札、7まで"）。
    public static func foundationLabel(suit: SolitaireSuit, rank: Int) -> String {
        let name = suit.playingCardSuit.spokenName
        guard rank > 0 else { return "\(name)の組札、空" }
        return "\(name)の組札、\(SolitaireCard(suit, rank).figure.rankLabel)まで"
    }

    /// 山札（伏せた束）。
    public static func stockLabel(remaining: Int) -> String {
        remaining > 0 ? "山札、残り\(remaining)枚、タップでめくる" : "山札、空、タップで捨て札を戻す"
    }

    /// 捨て札の一番上。
    public static func wasteLabel(card: SolitaireCard?, isSelected: Bool) -> String {
        guard let card else { return "捨て札、空" }
        return isSelected ? "捨て札、\(cardLabel(card))、選択中" : "捨て札、\(cardLabel(card))"
    }

    /// ステータスバーの 1 行。
    /// - Parameter isLost: 敗北確定（#406）。告知を閉じたあとも音声で状態が分かるようにする
    ///   （画面には 🤔 が出続けるので、読み上げだけ何も言わないと状態が伝わらない）。
    public static func statusLabel(
        phase: SolitairePhase,
        elapsedSeconds: Int,
        moveCount: Int,
        isDeadEnd: Bool,
        isLost: Bool = false
    ) -> String {
        let base = "経過\(RecordFormat.time(elapsedSeconds))、\(moveCount)手"
        switch phase {
        case .won:
            return "クリア。\(base)"
        case .playing:
            if isDeadEnd { return "進める手がありません。\(base)" }
            return isLost ? "このままではクリアできません。\(base)" : base
        }
    }

    /// ジョーカーの所持ボタン（#406）。**所持しているかどうかが音声だけで分かる**必要がある。
    ///
    /// ボタンは持っていない間も枠を残す（見た目は薄くなるだけ）ので、
    /// 画面を見ずに「ジョーカー」とだけ読まれると、持っていないのに押せると誤解される。
    public static func jokerButtonLabel(hasJoker: Bool, isPlacing: Bool) -> String {
        if isPlacing { return "ジョーカーを置くのをやめる" }
        return hasJoker ? "ジョーカーを使う、1枚所持" : "ジョーカー、所持していません"
    }

    /// - Note: 補充の案内は**救済の告知が出る条件**（行き止まり = 有効手ゼロ、または
    ///   敗北確定）に合わせる。「行き止まりになったとき」とだけ言うと、指せる手が残っている
    ///   敗北確定でも広告が出ることが音声では伝わらない（PR #457 の CodeRabbit 指摘）。
    public static func jokerButtonHint(hasJoker: Bool, isPlacing: Bool) -> String {
        if isPlacing { return "置き先の列をタップすると置けます" }
        return hasJoker
            ? "押したあと、置きたい列をタップします"
            : "手詰まりかクリアできない局面になったとき、広告を見て1枚受け取れます"
    }

    /// 救済の告知（#406）。行き止まりと敗北確定を読み分ける。
    public static func rescuePromptLabel(isDeadEnd: Bool, hasJoker: Bool) -> String {
        let head = isDeadEnd ? "進める手がありません" : "このままではクリアできません"
        let action = hasJoker ? "ジョーカーが1枚使えます" : "広告を見るとジョーカーを1枚受け取れます"
        return "\(head)。\(action)"
    }
}
