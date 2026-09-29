import Foundation
import Observation
import Core
import MahjongTiles

extension MahjongModel {
    // MARK: - 自摸と打牌

    func draw(for player: Int) {
        // カンのたびに山の末尾 1 枚が王牌へ回るので、自摸れる範囲も同じだけ短くなる。
        guard wallIndex < wall.count - deadWallDraws else {
            concludeExhaustiveDraw()
            return
        }
        temporaryFuriten[player] = false
        isRinshanDraw = false
        drawnTile = wall[wallIndex]
        wallIndex += 1
        currentPlayer = player
        turnCount += 1
    }

    /// カンの直後に嶺上牌を引く。王牌の末尾から順に使う。
    func drawFromDeadWall(for player: Int) {
        guard deadWallDraws < 4, deadWall.count >= Self.deadWallCount else {
            concludeExhaustiveDraw()
            return
        }
        temporaryFuriten[player] = false
        drawnTile = deadWall[deadWall.count - 1 - deadWallDraws]
        deadWallDraws += 1
        isRinshanDraw = true
        currentPlayer = player
        turnCount += 1
    }

    /// カンで新しいドラをめくる（王牌は表裏 5 組ぶん用意してある）。
    func revealKanDora() {
        revealedDoraCount = min(5, revealedDoraCount + 1)
    }

    /// 人間が牌を切る。`tile` は手牌かツモ牌のどちらでもよい。
    public func discard(_ tile: MahjongTile) {
        guard isPlayerTurn, discardableTiles.contains(tile) else {
            services?.feedback.notify(.warning)
            return
        }
        services?.feedback.impact(.light)
        if isDeclaringRiichi {
            commitRiichi(for: Self.humanIndex)
            services?.feedback.notify(.success)
        }
        performDiscard(tile, by: Self.humanIndex)
    }

    /// 立直を宣言する。実際に成立するのは、続けて切る牌を選んだ時点。
    public func declareRiichi() {
        guard canDeclareRiichi else {
            services?.feedback.notify(.warning)
            return
        }
        isDeclaringRiichi = true
        services?.feedback.impact(.rigid)
    }

    /// 立直の宣言を取り消す。
    public func cancelRiichiDeclaration() {
        guard isDeclaringRiichi else { return }
        isDeclaringRiichi = false
        services?.feedback.impact(.light)
    }

    /// ツモ和了を宣言する。
    public func declareTsumo() {
        guard canDeclareTsumo, let drawn = drawnTile else {
            services?.feedback.notify(.warning)
            return
        }
        concludeWin(
            winner: Self.humanIndex, loser: nil, winningTile: drawn,
            isTsumo: true, isRinshan: isRinshanDraw
        )
    }

    /// 提示されているロンを宣言する。
    public func declareRon() {
        guard phase == .ronOffer, let offer = ronOffer else { return }
        ronOffer = nil
        pendingKan = nil
        concludeWin(
            winner: Self.humanIndex, loser: offer.discarder, winningTile: offer.tile,
            isTsumo: false, isChankan: offer.isChankan
        )
    }

    /// 提示されているロンを見逃す。同巡内はロンできなくなり、立直中なら以後もロンできない。
    public func declineRon() {
        guard phase == .ronOffer, let offer = ronOffer else { return }
        ronOffer = nil
        temporaryFuriten[Self.humanIndex] = true
        if riichi[Self.humanIndex] { riichiFuriten[Self.humanIndex] = true }
        phase = .playing
        // 見逃した = 宣言牌は通ったので、保留していた立直をここで成立させる（#375）。
        settlePendingRiichi()
        services?.feedback.impact(.light)
        // 槍槓を見逃した場合は、止めていた加槓をそのまま成立させて続ける。
        if let pending = pendingKan {
            completeSelfKan(pending.call, by: pending.player)
            return
        }
        // 打牌に対するロンを見逃したときは、続けて鳴きの主張を順に聞く
        // （ロンを見逃した牌をポンすること自体は妨げられない）。
        pendingDiscard = (offer.tile, offer.discarder)
        pendingClaims = claimOrder(for: offer.tile, discardedBy: offer.discarder)
        resolveNextClaim()
    }

    /// 立直を宣言した状態にする。**1000 点の支払いはここでは行わない**（#375）。
    /// 宣言牌をロンされた立直は不成立で点棒も出ないため、支払いは宣言牌が通った時点
    /// （`settlePendingRiichi`）まで保留する。
    /// 合図は鳴らさない。人間の立直と CPU の立直は意味が逆なので、呼び出し元で出し分ける（#714）。
    func commitRiichi(for player: Int) {
        isDeclaringRiichi = false
        riichi[player] = true
        riichiTurn[player] = turnCount
        pendingRiichi = player
    }

    /// 宣言牌が誰にもロンされなかったので立直を成立させ、1000 点を供託に出す。
    private func settlePendingRiichi() {
        guard let player = pendingRiichi else { return }
        pendingRiichi = nil
        scores[player] -= 1000
        riichiSticks += 1
    }

    /// 宣言牌をロンされたので立直を不成立に戻す。点棒は出ないので供託も動かさない。
    func cancelPendingRiichi() {
        guard let player = pendingRiichi else { return }
        pendingRiichi = nil
        riichi[player] = false
        riichiTurn[player] = nil
    }

    /// 牌を河に置き、他家のロンと鳴きを確かめる。
    func performDiscard(_ tile: MahjongTile, by player: Int) {
        if drawnTile == tile {
            drawnTile = nil
        } else {
            hands[player].remove(tile)
            if let drawn = drawnTile {
                hands[player].add(drawn)
                drawnTile = nil
            }
        }
        isRinshanDraw = false
        // 牌が切られた = 捨てたら途中離脱として数える局面（#500）。
        services?.gameDidProgress(gameID: gameID)
        discards[player].append(tile)
        discardedKinds[player].insert(MahjongTileOrder.index(of: tile))

        // 立直者の待ちがこの牌なら、以後その人はロンできない（見逃しと同じ扱い）。
        for other in 0..<Self.playerCount where other != player && riichi[other] {
            let waits = MahjongShanten.waits(hands[other], meldCount: melds[other].count)
            if waits.contains(tile) && !canWin(other, tile: tile) {
                riichiFuriten[other] = true
            }
        }

        if let claimant = ronClaimant(for: tile, discardedBy: player) {
            if claimant == Self.humanIndex, !autoPlayEnabled {
                ronOffer = RonOffer(tile: tile, discarder: player)
                phase = .ronOffer
                services?.feedback.notify(.success)
                return
            }
            concludeWin(winner: claimant, loser: player, winningTile: tile, isTsumo: false)
            return
        }

        // 宣言牌が誰にもロンされずに通ったので、ここで立直が成立する（#375）。
        // 鳴かれた場合も立直そのものは成立するため、鳴きの解決より前に確定させる。
        settlePendingRiichi()
        pendingDiscard = (tile, player)
        pendingClaims = claimOrder(for: tile, discardedBy: player)
        resolveNextClaim()
    }

    /// 打牌を鳴ける家を優先度順に並べる。
    ///
    /// ポン・カンは誰でも主張できるが**チーは下家だけ**で、ポン・カンのほうが優先される。
    /// 同じ優先度が重なることは無い（同じ牌を 2 人がポンできるのは牌が 4 枚しか無い以上
    /// ありえるが、その場合は放銃者に近い家が取る = 席順で先に来る）。
    private func claimOrder(for tile: MahjongTile, discardedBy discarder: Int) -> [PendingClaim] {
        var tripletClaims: [PendingClaim] = []
        var runClaims: [PendingClaim] = []
        for step in 1..<Self.playerCount {
            let player = (discarder + step) % Self.playerCount
            // 立直している人は手牌を変えられないので鳴けない。
            guard !riichi[player] else { continue }
            var options = MahjongCallFinder.claimOptions(
                hand: hands[player], tile: tile, from: discarder, allowsChi: step == 1
            )
            // 大明槓は嶺上牌を引くので、王牌が尽きた局（残り 0 枚・4 回カン済み）では提示しない。
            let canKan = remainingTiles > 0 && deadWallDraws < 4
            options = options.filter { canKan || $0.kind != .openKan }
            guard !options.isEmpty else { continue }
            let triplets = options.filter { $0.kind != .chi }
            let runs = options.filter { $0.kind == .chi }
            if !triplets.isEmpty {
                tripletClaims.append(PendingClaim(player: player, options: triplets))
            }
            if !runs.isEmpty {
                runClaims.append(PendingClaim(player: player, options: runs))
            }
        }
        return tripletClaims + runClaims
    }

    /// 優先度の高い家から順に「鳴くか」を聞く。誰も鳴かなければ手番を次へ送る。
    func resolveNextClaim() {
        while !pendingClaims.isEmpty, let pending = pendingDiscard {
            let claim = pendingClaims.removeFirst()
            if claim.player == Self.humanIndex, !autoPlayEnabled {
                callOffer = CallOffer(
                    tile: pending.tile, discarder: pending.by, options: claim.options
                )
                phase = .callOffer
                services?.feedback.impact(.rigid)
                return
            }
            let chosen = MahjongAI.chooseCall(
                options: claim.options,
                hand: hands[claim.player],
                melds: melds[claim.player],
                seatWind: seatWind(claim.player),
                roundWind: 0
            )
            if let chosen {
                performCall(chosen, by: claim.player)
                return
            }
        }
        let discarder = pendingDiscard?.by ?? currentPlayer
        pendingDiscard = nil
        pendingClaims = []
        continueAfterDiscard(by: discarder)
    }

    /// ロンも鳴きも起きなかったときに手番を次へ送る。
    private func continueAfterDiscard(by player: Int) {
        persist()
        guard phase == .playing else { return }
        draw(for: (player + 1) % Self.playerCount)
        persist()
    }
}
