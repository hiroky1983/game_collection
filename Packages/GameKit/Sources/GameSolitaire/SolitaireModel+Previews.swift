import Foundation

#if DEBUG
/// 撮影用の口のうち、公開 API だけで組めるもの（#831 で本体から切り出した）。
/// `applyPreviewProgressForTesting` は非公開の手順（`moves`）を書き換えるので本体に残してある。
extension SolitaireModel {
    /// 撮影用（#406）: 救済の告知が出ている状態を作る。
    ///
    /// 敗北確定はソルバーが「もう勝てない」と確定させたときにしか出ず、実測で 300 局中 140 局
    /// （しかも局の終盤）でしか起きないため、シミュレータで自然に到達させる手段が無い
    /// （自動タップもできない）。`applyPreviewProgressForTesting` と同じ位置づけの撮影専用の口。
    ///
    /// - Parameter spendJoker: true なら所持を使い切ってから告知を出す（＝広告での補充を促す面）。
    public func applyRescuePreviewForTesting(spendJoker: Bool) {
        guard phase == .playing else { return }
        if spendJoker {
            for pile in board.tableau.indices where board.canPlaceJoker(onPile: pile) {
                placeJoker(onPile: pile)
                break
            }
        }
        applyLostVerdict(true, for: board.stateKey)
    }

    /// 撮影用（#406）: ジョーカーの置き先を選んでいる最中の状態を作る。
    public func applyPlacingJokerPreviewForTesting() {
        beginPlacingJoker()
    }

    /// 撮影用（#498）: 3 枚めくりの局を作り、捨て札が 3 枚重なった状態まで進める。
    ///
    /// 3 枚めくりは開始シートで選ぶものなので、シミュレータ（自動タップができない）では
    /// この口を通さないと扇の表示に到達できない。最後にもう一度めくるのは、
    /// 勝ち筋の途中では捨て札が 1〜2 枚しか残っていないことがあるため。
    public func applyDrawThreePreviewForTesting() {
        newGame(rules: SolitaireRuleSet(drawMode: .three))
        applyPreviewProgressForTesting()
        if board.isLegal(.draw) { tapStock() }
    }
}
#endif
