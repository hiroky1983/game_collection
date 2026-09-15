import Foundation
import Observation
import Core
import MahjongTiles

extension MahjongModel {
    // MARK: - 鳴き

    /// 提示されている鳴きのうち 1 つを成立させる。
    public func acceptCall(_ call: MahjongCall) {
        guard phase == .callOffer, let offer = callOffer, offer.options.contains(call) else {
            services?.feedback.notify(.warning)
            return
        }
        performCall(call, by: Self.humanIndex)
    }

    /// 提示されている鳴きを見送る。下家のチーなど、優先度の低い主張があればそちらへ回る。
    public func declineCall() {
        guard phase == .callOffer else { return }
        callOffer = nil
        phase = .playing
        services?.feedback.impact(.light)
        resolveNextClaim()
    }

    /// 鳴きを成立させ、手番をその人へ移す。
    func performCall(_ call: MahjongCall, by player: Int) {
        guard let pending = pendingDiscard else { return }
        pendingDiscard = nil
        pendingClaims = []
        callOffer = nil
        phase = .playing

        // 鳴かれた牌は河から取り上げる。フリテンの判定に使う `discardedKinds` には残す
        // （実際に捨てた事実は消えないため）。
        if !discards[pending.by].isEmpty { discards[pending.by].removeLast() }
        for tile in call.tilesFromHand { hands[player].remove(tile) }
        melds[player].append(call)

        cancelIppatsu()
        currentPlayer = player
        drawnTile = nil
        isRinshanDraw = false
        turnCount += 1
        services?.feedback.impact(.medium)

        if call.kind == .openKan {
            revealKanDora()
            drawFromDeadWall(for: player)
        }
        persist()
    }

    /// 自分の手番でカン（暗槓・加槓）を宣言する。
    public func declareKan(_ call: MahjongCall) {
        guard availableSelfKans.contains(call) else {
            services?.feedback.notify(.warning)
            return
        }
        performSelfKan(call, by: Self.humanIndex)
    }

    func performSelfKan(_ call: MahjongCall, by player: Int) {
        // 加槓は槍槓（他家が横取りするロン）の対象になる。暗槓は対象外。
        if call.kind == .addedKan, let claimant = ronClaimant(
            for: call.tile, discardedBy: player, isChankan: true
        ) {
            if claimant == Self.humanIndex, !autoPlayEnabled {
                pendingKan = (call, player)
                ronOffer = RonOffer(tile: call.tile, discarder: player, isChankan: true)
                phase = .ronOffer
                services?.feedback.notify(.success)
                return
            }
            concludeWin(
                winner: claimant, loser: player, winningTile: call.tile,
                isTsumo: false, isChankan: true
            )
            return
        }
        completeSelfKan(call, by: player)
    }

    func completeSelfKan(_ call: MahjongCall, by player: Int) {
        pendingKan = nil
        // ツモ牌もいったん手牌に入れてから、槓に使う牌を抜く。
        if let drawn = drawnTile {
            hands[player].add(drawn)
            drawnTile = nil
        }
        for tile in call.tilesFromHand { hands[player].remove(tile) }
        if call.kind == .addedKan,
           let index = melds[player].firstIndex(where: { $0.kind == .pon && $0.tile == call.tile }) {
            melds[player][index] = call
        } else {
            melds[player].append(call)
        }
        cancelIppatsu()
        services?.feedback.impact(.medium)
        revealKanDora()
        drawFromDeadWall(for: player)
        persist()
    }

    /// 鳴きが入ると一発は消える。立直そのものは続く。
    private func cancelIppatsu() {
        riichiTurn = Array(repeating: nil, count: Self.playerCount)
    }
}
