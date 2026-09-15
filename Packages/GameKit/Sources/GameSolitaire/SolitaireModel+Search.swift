import Foundation

/// 盤面だけから答えを出す静的な読み（敗北確定の探索・自動で上がる手順）。
/// モデルの状態には触れないので、本体から切り出してある（#831）。
extension SolitaireModel {
    /// 現在の盤面から勝ち筋が残っているかを、**ジョーカーを使わずに**探索する。
    ///
    /// - Returns: `true` = もう勝てない（探索を尽くして勝ち筋が無かった）/ `false` = まだ勝てる /
    ///   `nil` = 判定不能（探索上限に達した）。**nil を「負け」に倒さない**のが要で、
    ///   打ち切っただけの局面で「もう勝てません」と宣告すると誤報になる。
    /// - Note: `nonisolated` にしてあるのは、この探索を **MainActor の外**（`Task.detached`）で
    ///   回すため。型が `@MainActor` なので、付けないと static メソッドまで MainActor に載る。
    nonisolated static func hopelessVerdict(
        for board: SolitaireBoard,
        maxStates: Int = SolitaireSolver.defaultMaxStates,
        isCancelled: () -> Bool = { false }
    ) -> Bool? {
        let result = SolitaireSolver.solve(
            board, allowJoker: false, maxStates: maxStates, isCancelled: isCancelled
        )
        if result.isSolvable { return false }
        // 取り消されたときも `hitLimit` が立つので、ここで自動的に「分からない」に倒れる。
        return result.hitLimit ? nil : true
    }

    /// 組札へ送る手（詰まったら山めくり）だけで勝ち切れる手順。勝ち切れなければ nil。
    ///
    /// 場札を積み替える手は一切使わない。ここで返せるのは「あとは積むだけ」の局面だけで、
    /// 積み替えが要る局面をプレイヤーの代わりに解いてしまわない。
    static func autoFinishPlan(from board: SolitaireBoard) -> [SolitaireMove]? {
        var board = board
        guard !board.isWon else { return nil }
        var plan: [SolitaireMove] = []
        /// 何も送れないまま山をめくった回数。山 + 捨て札を 1 周しても送れなければ諦める。
        var idleDraws = 0

        while !board.isWon {
            var sent = false
            for pile in board.tableau.indices where board.isLegal(.tableauToFoundation(pile: pile)) {
                board.apply(.tableauToFoundation(pile: pile))
                plan.append(.tableauToFoundation(pile: pile))
                sent = true
            }
            if board.isLegal(.wasteToFoundation) {
                board.apply(.wasteToFoundation)
                plan.append(.wasteToFoundation)
                sent = true
            }
            if sent {
                idleDraws = 0
                continue
            }
            let cycle = board.stock.count + board.waste.count
            guard cycle > 0, idleDraws < cycle, board.isLegal(.draw) else { return nil }
            board.apply(.draw)
            plan.append(.draw)
            idleDraws += 1
        }
        return plan
    }
}
