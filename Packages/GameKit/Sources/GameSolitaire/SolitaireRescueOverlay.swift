import SwiftUI
import Core

/// 詰み・敗北確定の救済（#406）。盤に被せる 1 枚の面。
///
/// 2 種類の「もう届かない」を1つの面で受ける（#406 の決裁）。
///
/// - **有効手ゼロ**（`isDeadEnd`）: 盤面が進む手が無い。ただし K → 空列の入れ替えは残るので、
///   「何もできない」わけではない（#475 の実測）。
/// - **敗北確定**（`isLost`）: 指せる手は残っているがソルバーが勝ち筋の不在を確定させた。
///
/// **どちらも閉じられる**（#491 の決裁 C）。まだ触れる盤を告知で取り上げない。
/// 閉じたら配り直すまで出さない。
///
/// ジョーカーは**持っていれば広告なしで使える**（決裁1）。持っていないときだけ広告で補充する
/// （決裁2）。ここで二重に対価を取らないよう、文言もボタンも所持で切り替える。
struct SolitaireRescueOverlay: View {
    let model: SolitaireModel
    /// 広告を出している最中は、この面のボタンをまとめて押させない
    /// （2 本の広告が並走する・配り直しが割り込む）。
    let isWatchingJokerAd: Bool
    let isWatchingUndoAd: Bool
    /// 「戻す」の入口（残り回数の判定と広告の提案は画面本体が持つ・#476）。
    let onUndo: () -> Void
    /// 広告を見てジョーカーを 1 枚受け取る（所持しているときは呼ばれない）。
    let onRequestJoker: () -> Void

    private var isBusy: Bool { isWatchingJokerAd || isWatchingUndoAd }

    var body: some View {
        GameDeadEndPanel(
            emoji: model.isDeadEnd ? "😵" : "🤔",
            title: model.isDeadEnd ? "進める手がありません" : "このままではクリアできません",
            message: rescueMessage
        ) {
            jokerRescueButton

            if model.canUndo {
                // ここでも残り回数を見せる（#476 仕様3）。押した先で初めて
                // 「使い切っていた」と分かるのでは、救済の面で二度手間になる。
                GameDeadEndActionButton(
                    "1手戻す（残り\(model.undosRemaining)）", systemImage: "arrow.uturn.backward",
                    tint: Theme.Fill.coral, isDisabled: isBusy
                ) {
                    onUndo()
                }
                .accessibilityLabel(SolitaireAccessibility.undoButtonLabel(remaining: model.undosRemaining))
                .accessibilityHint(SolitaireAccessibility.undoButtonHint(
                    canUndo: model.canUndo,
                    remaining: model.undosRemaining
                ))
            }

            GameDeadEndDismissButton("新しい配札にする", isDisabled: isBusy) {
                model.newGame()
            }

            // どちらの告知でも盤には触れる手が残っている。宣告で操作を奪わない（#491）。
            GameDeadEndDismissButton("このまま続ける", isDisabled: isBusy) {
                model.dismissRescuePrompt()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SolitaireAccessibility.rescuePromptLabel(
            isDeadEnd: model.isDeadEnd,
            hasJoker: model.hasJoker
        ))
    }

    private var rescueMessage: String {
        // 行き止まりでも K → 空列の入れ替えは残る。「めくるしかない」と書くと、
        // 盤に手が見えている人には事実に反して見える（#475 の会長QA → #491）。
        let head = model.isDeadEnd
            ? "山札をめくるか、盤面が進まない入れ替えしか残っていません。"
            : "指せる手はありますが、ここからは組札を揃えきれません。"
        let tail = model.hasJoker
            ? "ジョーカーを場札に置くと、その上へどんな札でも1枚だけ重ねられます。"
            : "広告を見るとジョーカーを1枚受け取れます。手を戻すか、新しい配札にすることもできます。"
        return head + tail
    }

    /// 所持していれば広告なしで使い、持っていなければリワード広告で補充する。
    private var jokerRescueButton: some View {
        GameDeadEndActionButton(
            model.hasJoker ? "ジョーカーを使う" : "広告を見てジョーカーをもらう",
            systemImage: model.hasJoker ? "questionmark.app.fill" : "play.rectangle.fill",
            tint: Theme.Fill.purple,
            // 「戻す」の補充広告を出している最中もここは押させない（2 本の広告が並走する）。
            isDisabled: isBusy
        ) {
            if model.hasJoker {
                model.beginPlacingJoker()
            } else {
                onRequestJoker()
            }
        }
    }
}
