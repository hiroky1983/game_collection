import Foundation
import Observation
import Core
import MahjongTiles

extension MahjongModel {
    // MARK: - CPU

    /// 自動で進む手番が続く限り進める。自分が選ぶ番になるか、局が決着したら止まる。
    /// View から複数の契機で呼ばれても内部で 1 本に制限する。
    ///
    /// `autoPlayEnabled` のときは、局が終わって `.handResult` になっても止まらず、
    /// そのまま「次の局へ」を自動で押した扱いにして次の局のCPU手番も続けて進める
    /// （対局全体が終わる `.gameResult` まで無人で進む）。
    public func runCPUTurnsIfNeeded() async {
        // 多重起動防止。ただし「先行タスクがいたら即リターン」にすると、`.task(id:)` の
        // 差し替え時に「新タスクが先に走る → 先行タスクがまだフラグを持っていて即リターン →
        // 直後に先行タスクがキャンセルで抜ける」の順になったとき走者が誰もいなくなり、
        // `turnKey` はもう変わらないので再起動も掛からず手番が止まる（レース）。
        // 先行タスクの終了を待ってから引き継ぐ。待機中に自分がキャンセルされたら
        // （さらに次のタスクへ差し替えられたら）そちらに譲って抜ける（#531 で共通化）。
        await withAITurnRunner(running: \.isRunningCPUTurns) {
            while true {
                while phase == .playing, isAutomaticTurn, awaitsDiscard(currentPlayer) {
                    // 間合いが 0 だと下の sleep 後の判定を通らないので、ループ先頭でも見る（大富豪 #287・花札 #726 と同じ）。
                    guard !Task.isCancelled else { return }
                    if cpuDelay > .zero {
                        // キャンセル後に抜けないと、`.task(id:)` に差し替えられた古いタスクが
                        // `cpuDelay` を一切待たずに残りの手番を走り抜けてしまう（CodeRabbit 指摘）。
                        guard await pauseCPUTurn(for: cpuDelay) else { return }
                        guard phase == .playing, isAutomaticTurn, awaitsDiscard(currentPlayer) else { return }
                    }
                    advanceAutomaticTurn()
                }
                guard autoPlayEnabled, phase == .handResult else { return }
                guard !Task.isCancelled else { return }
                if cpuDelay > .zero {
                    guard await pauseCPUTurn(for: cpuDelay) else { return }
                    guard autoPlayEnabled, phase == .handResult else { return }
                }
                advanceToNextHand()
            }
        }
    }

    /// 人の選択を要さない手番か。CPU の手番と、**立直後でツモ和了もできない自分の手番**
    /// （宣言後は自摸切りしかできないので選ばせる意味が無い）。`autoPlayEnabled` のときは
    /// 自分の手番も含めすべて自動。
    private var isAutomaticTurn: Bool {
        if currentPlayer != Self.humanIndex { return true }
        if autoPlayEnabled { return true }
        return riichi[Self.humanIndex] && !canDeclareTsumo
    }

    private func advanceAutomaticTurn() {
        if currentPlayer == Self.humanIndex, !autoPlayEnabled {
            guard let drawn = drawnTile else { return }
            performDiscard(drawn, by: Self.humanIndex)   // 立直中の自摸切り
            return
        }
        performCPUTurn(currentPlayer)
    }

    func performCPUTurn(_ player: Int) {
        let meldCount = melds[player].count
        if let drawn = drawnTile {
            // ツモ和了できるなら必ず和了する。
            if winScore(
                for: player, winningTile: drawn, isTsumo: true, isRinshan: isRinshanDraw
            ) != nil {
                concludeWin(
                    winner: player, loser: nil, winningTile: drawn,
                    isTsumo: true, isRinshan: isRinshanDraw
                )
                return
            }
            if riichi[player] {
                performDiscard(drawn, by: player)
                return
            }
            // 形が悪くならないカン（暗槓・加槓）はしてよい。
            if deadWallDraws < 4, remainingTiles > 0 {
                let options = MahjongCallFinder.selfKanOptions(
                    hand: hands[player], drawnTile: drawn, melds: melds[player]
                )
                if let kan = MahjongAI.chooseSelfKan(
                    options: options, hand: hands[player], drawnTile: drawn, melds: melds[player]
                ) {
                    performSelfKan(kan, by: player)
                    return
                }
            }
        }
        // 鳴いた直後はツモ牌が無く、手牌がそのまま 1 枚多い状態になっている。
        var full = hands[player]
        if let drawn = drawnTile { full.add(drawn) }
        let choice = MahjongAI.chooseDiscard(
            from: full, meldCount: meldCount, visible: visibleCounts(for: player)
        )
        // 立直の条件（門前・聴牌・点棒・残り牌）が揃っていれば宣言してから切る。
        if drawnTile != nil, melds[player].allSatisfy({ !$0.breaksConcealment }),
           MahjongAI.shouldDeclareRiichi(hand: full.removing(choice.tile)),
           scores[player] >= 1000, remainingTiles >= Self.playerCount {
            commitRiichi(for: player)
            // 相手が脅威を作った合図。和了と同じ「成功」を鳴らすと意味が逆になる（#714）。
            services?.feedback.impact(.rigid)
        }
        performDiscard(choice.tile, by: player)
    }

    /// その人から見えている牌の枚数（自分の手牌 + 全員の河と副露 + ドラ表示牌）。
    private func visibleCounts(for player: Int) -> [Int] {
        var counts = hands[player].counts
        if let drawn = drawnTile, player == currentPlayer {
            counts[MahjongTileOrder.index(of: drawn)] += 1
        }
        for pile in discards {
            for tile in pile { counts[MahjongTileOrder.index(of: tile)] += 1 }
        }
        for calls in melds {
            for tile in calls.flatMap(\.tiles) { counts[MahjongTileOrder.index(of: tile)] += 1 }
        }
        for indicator in doraIndicators { counts[MahjongTileOrder.index(of: indicator)] += 1 }
        return counts
    }
}
