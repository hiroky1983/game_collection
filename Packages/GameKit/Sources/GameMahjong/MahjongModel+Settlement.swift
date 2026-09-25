import Foundation
import Observation
import Core
import MahjongTiles

extension MahjongModel {
    // MARK: - 和了の判定

    /// この牌でロンできる人。放銃者の下家から順に見て最初の 1 人（頭跳ね）。
    func ronClaimant(
        for tile: MahjongTile, discardedBy discarder: Int, isChankan: Bool = false
    ) -> Int? {
        for step in 1..<Self.playerCount {
            let player = (discarder + step) % Self.playerCount
            if canWin(player, tile: tile, isChankan: isChankan) { return player }
        }
        return nil
    }

    /// その牌でロンできるか（和了形 + 役 + フリテンでない）。
    func canWin(_ player: Int, tile: MahjongTile, isChankan: Bool = false) -> Bool {
        guard !isFuriten(player) else { return false }
        return winScore(
            for: player, winningTile: tile, isTsumo: false, isChankan: isChankan
        ) != nil
    }

    /// フリテンか。自分が捨てた牌に待ち牌が 1 つでもあれば該当する。
    ///
    /// 判定には河ではなく `discardedKinds`（捨てた牌の種類の記録）を使う。鳴かれた牌は河から
    /// 消えるが、**捨てた事実は消えない**のでフリテンは続くため。
    func isFuriten(_ player: Int) -> Bool {
        if riichiFuriten[player] || temporaryFuriten[player] { return true }
        let waits = MahjongShanten.waits(hands[player], meldCount: melds[player].count)
        guard !waits.isEmpty else { return false }
        return waits.contains { discardedKinds[player].contains(MahjongTileOrder.index(of: $0)) }
    }

    /// 和了点。役が無ければ nil（= 和了できない）。
    func winScore(
        for player: Int,
        winningTile: MahjongTile,
        isTsumo: Bool,
        isRinshan: Bool = false,
        isChankan: Bool = false
    ) -> MahjongScore? {
        let calls = melds[player]
        let hand = hands[player].adding(winningTile)
        guard hand.total == 14 - calls.count * 3 else { return nil }
        let context = MahjongWinContext(
            winningTile: winningTile,
            isTsumo: isTsumo,
            isRiichi: riichi[player],
            isIppatsu: isIppatsu(player),
            isLastTile: remainingTiles == 0,
            isRinshan: isRinshan,
            isChankan: isChankan,
            seatWind: seatWind(player),
            roundWind: 0,
            doraIndicators: doraIndicators,
            uraIndicators: uraIndicators
        )
        return MahjongScoring.score(hand: hand, calls: calls, context: context)
    }

    /// 一発か。立直の宣言から 1 巡以内の和了。
    ///
    /// `turnCount` は自摸のたびに 1 増える通し番号で、`declaredAt` は宣言者が立直を宣言した
    /// 手番の値。他家のロンは差が 1〜3、**宣言者自身の次の自摸によるツモは差がちょうど 4**
    /// （= 参加人数）になるため、境界は `< playerCount` ではなく `<= playerCount`。
    /// `<` にすると立直後の第一ツモだけ一発が付かない。
    private func isIppatsu(_ player: Int) -> Bool {
        guard riichi[player], let declaredAt = riichiTurn[player] else { return false }
        return turnCount - declaredAt <= Self.playerCount
    }

    // MARK: - 局の決着

    func concludeWin(
        winner: Int,
        loser: Int?,
        winningTile: MahjongTile,
        isTsumo: Bool,
        isRinshan: Bool = false,
        isChankan: Bool = false
    ) {
        guard let score = winScore(
            for: winner, winningTile: winningTile, isTsumo: isTsumo,
            isRinshan: isRinshan, isChankan: isChankan
        ) else { return }
        pendingDiscard = nil
        pendingClaims = []
        pendingKan = nil
        callOffer = nil
        // 立直の宣言牌をロンされた場合、その立直は不成立で 1000 点も出ない（#375）。
        // 供託に積む前に取り消すので、和了者が受け取る供託にもこの 1000 点は入らない。
        if !isTsumo, let loser, loser == pendingRiichi { cancelPendingRiichi() }
        let scoresBefore = scores

        var gained = score.total
        // 本場は 1 本につき 300 点（ツモなら 100 点ずつ）。
        let honbaBonus = honba * 300
        if let loser {
            scores[loser] -= score.ronPayment + honbaBonus
        } else {
            for player in 0..<Self.playerCount where player != winner {
                let payment = player == dealer ? score.tsumoFromDealer : score.tsumoFromNonDealer
                scores[player] -= payment + honba * 100
            }
        }
        gained += honbaBonus
        // 供託の立直棒はすべて和了者のもの。
        gained += riichiSticks * 1000
        scores[winner] += gained
        riichiSticks = 0

        handResult = MahjongHandResult(
            kind: isTsumo ? .tsumo : .ron,
            winner: winner,
            loser: loser,
            yaku: score.yaku.map { "\($0.name) \($0.isYakuman ? "役満" : "\($0.han)飜")" },
            han: score.han,
            fu: score.fu,
            limitName: score.limitName,
            gainedPoints: gained,
            tenpaiPlayers: [],
            pointChanges: (0..<Self.playerCount).map { scores[$0] - scoresBefore[$0] },
            // 和了手の表示用（#351）。手牌は和了牌を足す前の門前部分を渡す（和了牌は別枠で
            // ハイライトして出す）。裏ドラは点数計算（`winScore`）に既に入っているものを
            // 立直和了のときだけ開示する。
            winningHand: hands[winner].tiles,
            winningMelds: melds[winner],
            winningTile: winningTile,
            uraDoraIndicators: riichi[winner] ? uraIndicators : nil,
            roundNumber: roundNumber,
            honba: honba
        )
        // 和了牌を手牌に入れた状態で見せる（リザルトで役を確かめられるように）。
        hands[winner] = hands[winner].adding(winningTile)
        drawnTile = nil
        finishHand(dealerContinues: winner == dealer)
    }

    func concludeExhaustiveDraw() {
        drawnTile = nil
        pendingDiscard = nil
        pendingClaims = []
        pendingKan = nil
        callOffer = nil
        let tenpai = (0..<Self.playerCount).filter {
            MahjongShanten.isTenpai(hands[$0], meldCount: melds[$0].count)
        }
        let scoresBefore = scores
        applyExhaustiveDrawPayments(tenpaiPlayers: tenpai)
        handResult = MahjongHandResult(
            kind: .exhaustiveDraw,
            winner: nil,
            loser: nil,
            yaku: [],
            han: 0,
            fu: 0,
            limitName: nil,
            gainedPoints: 0,
            tenpaiPlayers: tenpai,
            pointChanges: (0..<Self.playerCount).map { scores[$0] - scoresBefore[$0] },
            roundNumber: roundNumber,
            honba: honba
        )
        finishHand(dealerContinues: tenpai.contains(dealer))
    }

    /// 荒牌平局の点棒授受。聴牌者で 3000 点を分け合う（全員聴牌・全員ノーテンなら動かない）。
    func applyExhaustiveDrawPayments(tenpaiPlayers: [Int]) {
        let tenpaiCount = tenpaiPlayers.count
        guard tenpaiCount > 0, tenpaiCount < Self.playerCount else { return }
        let notenCount = Self.playerCount - tenpaiCount
        let gain = 3000 / tenpaiCount
        let loss = 3000 / notenCount
        for player in 0..<Self.playerCount {
            scores[player] += tenpaiPlayers.contains(player) ? gain : -loss
        }
    }

    private func finishHand(dealerContinues: Bool) {
        phase = .handResult
        // 一局戦（#639）は連荘しない。認めると「1局で終わる」という約束のほうが破れる
        // （親が和了り続けるかぎり東1局1本場・2本場…と伸びる）。東風戦では `dealerContinues`
        // がそのまま通るので、v1.1.4 までの進行と 1 ビットも変わらない。
        let continues = dealerContinues && gameLength.allowsDealerRepeat
        // アガリやめ: 最終局で親が連荘する条件を満たしていても、その親がトップなら終局する。
        // これを入れないと、勝っている親が連荘し続けるかぎり対局が終わらない。
        // 連荘の変形なので、連荘の無い一局戦では `continues` が常に false になり成立しない。
        let isFinalRound = roundNumber >= roundLimit
        if continues && isFinalRound && isTopPlayer(dealer) {
            endsAfterThisHand = true
        }
        if continues {
            honba += 1
        } else {
            honba = 0
            dealer = (dealer + 1) % Self.playerCount
            roundNumber += 1
        }
        switch handResult?.winner {
        case Self.humanIndex: services?.feedback.notify(.success)
        case .some:           services?.feedback.notify(.error)
        case nil:             services?.feedback.notify(.warning)
        }
        // リザルト表示中に離脱しても局間の経過が消えないよう、決着内容ごと保存する（#350）。
        // 親・本場・局数の繰り上げが終わった後に保存するので、再開後の「次の局へ」は
        // 中断が無かったときと同じ条件で次局を始められる。
        // 終局が確定するなら、`game_end` は保存より**先**に送る（保存の直後に終了すると、復元は
        // `gameDidRestoreFinished` しか呼ばず `game_end` が永久に出ない。#1375）。
        if concludesAfterCurrentResult {
            services?.gameDidDecide(gameID: gameID, outcome: finalOutcome())
        }
        persist()
        // その先が終局（一局戦・最終局・アガリやめ・トビ）のリザルトは、中断データが残っていても
        // 続けて打つ局が無い。「結果を見る」を押さずに戻っても中断のお知らせ（#663）を予約させない（#811）。
        // 記録（戦績・評価リクエスト等）は「結果を見る」の `concludeGame` で付けるので、ここでは `gameDidFinish` を呼ばない。
        // ただし `game_end` は上の `persist()` の前に送っている。リザルトで離れると休憩と判定され、`concludeGame` に戻らなければ
        // 遊び切った対局が「始めたのに終わっていない」ぶんに数えられる（#1375）。送信済みのプレイは
        // `concludeGame` の `gameDidFinish` が再び送らない（`finishPlay` は進行中のときだけ送る）。
        if concludesAfterCurrentResult {
            services?.gameDidRestoreFinished(gameID: gameID)
        }
    }

    /// 対局が終わったか。最終局を終えた（= その次の局に入る）か、アガリやめか、誰かが飛んだとき。
    /// 最終局は対局の長さで決まる（東風戦は東 4 局、一局戦は東 1 局。#639）。
    func isGameOver() -> Bool {
        endsAfterThisHand || roundNumber > roundLimit || scores.contains { $0 < 0 }
    }

    /// いま見ている局のリザルトから進むと、次の局ではなく終局（順位）に行くか（#639）。
    ///
    /// 一局戦は必ずこれに当たる（打つ局が 1 つしかない）。東風戦でも最終局・アガリやめ・トビの
    /// ときは同じで、リザルトのボタンが「次の局へ」のままだと押した先と表示が食い違う。
    public var concludesAfterCurrentResult: Bool {
        phase == .handResult && isGameOver()
    }

    /// その人が単独・同点を問わず最高点か。
    func isTopPlayer(_ player: Int) -> Bool {
        scores[player] == scores.max()
    }

    /// 順位（1 位から）。同点は席順（親から近い順）で上位にする。
    private func rankedPlayers() -> [Int] {
        (0..<Self.playerCount).sorted {
            (scores[$0], -seatWind($0)) > (scores[$1], -seatWind($1))
        }
    }

    /// いまの持ち点で終局した場合の勝敗（`reviewOutcome` と同じ基準。`ranking` はまだ確定させない）。
    private func finalOutcome() -> GameOutcome {
        let order = rankedPlayers()
        guard let place = order.firstIndex(of: Self.humanIndex) else { return .draw }
        if place == 0 { return .win }
        if place == order.count - 1 { return .loss }
        return .draw
    }

    func concludeGame() {
        // 終了理由をリザルトの見出し用に確定する（#352）。トビは他の条件と同時に成立しうるが、
        // 突然終わる驚きが最も大きいので最優先で表示する。次いで「東4局を終えた」が自然な終局、
        // アガリやめはその変形（roundNumber は 4 のまま）なので最後に判定する。
        gameEndReason = scores.contains(where: { $0 < 0 }) ? .busted
            : roundNumber > roundLimit ? .completedAllRounds
            : endsAfterThisHand ? .agariYame
            : .completedAllRounds
        ranking = rankedPlayers()
        // 最後の局が流局で終わると供託（立直棒）が残る。誰にも渡さないと点棒が消えるので、
        // 一般的なルールどおりトップが回収する（回収してもトップは入れ替わらない）。
        // 最後の局が流局で終わると供託（立直棒）が残る。誰にも渡さないと点棒が消えるので、
        // 一般的なルールどおりトップが回収する（回収してもトップは入れ替わらない）。
        if riichiSticks > 0, let top = ranking.first {
            scores[top] += riichiSticks * 1000
            riichiSticks = 0
        }
        phase = .gameResult
        services?.snapshots.clear(for: gameID)
        switch reviewOutcome {
        case .win:  services?.feedback.notify(.success)
        case .loss: services?.feedback.notify(.error)
        case .draw: services?.feedback.notify(.warning)
        }
        // 一局戦（#639）の成績は東風戦と別枠で数える。1 局の出来だけで順位が決まるぶん
        // 結果のばらつきが大きく、同じ通算成績に混ぜると東風戦の勝率が読めなくなる。
        // 東風戦は `recordVariant` が nil のままなので、これまでの記録をそのまま引き継ぐ。
        recordResult = services?.gameDidFinish(
            gameID: gameID,
            outcome: reviewOutcome,
            score: GameScore(
                metric: .winLoss,
                variant: gameLength.recordVariant,
                variantLabel: gameLength.recordVariantLabel,
                isLeaderboardEligible: gameLength.isLeaderboardEligible
            )
        )
        // 自分がトビて終わった対局は、リワード広告で 1 半荘 1 回だけ続けられる（#338）。
        // 決着の通知（`gameDidFinish`）はここまでで従来どおり済ませ、復活したときに
        // 記録側だけを巻き戻す（2048・マインスイーパーのコンティニューと同じ扱い。`reviveAfterAd`）。
        canReviveAfterBust = didBustOut && !hasRevivedThisGame
    }
}
