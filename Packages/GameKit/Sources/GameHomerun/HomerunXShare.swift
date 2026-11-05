import Foundation
import Core
import CoreEngine
import HomerunCore

/// 「X でポストして特典をもらう」（#3359・会長決裁 2026-11-06）の柵越えおじさん側。
///
/// - 出すのは、**1 挑戦（10 球）の合計飛距離が 1,000m 以上**になった挑戦の結果画面で、まだこのゲームの特典を受け取っていないとき
///   （月は記録と同じく 180m で数える＝`challenge.totalDistance`）。提案を閉じたなら、次に同じ条件を満たした結果画面で再び出す。
/// - 特典はその日のプレイ回数 ＋1（当日分・0:00 で消える）。ゲームごとに 1 回だけ。
enum HomerunXShare {
    /// 提案を出す合計飛距離（m）。
    static let thresholdMeters = 1000.0

    /// 共有する本文の案（会長がマージ後に選ぶ。選ぶまでは `selectedMessageIndex` の 1 案目）。
    /// 外部の商標名・元ネタの名前は書かない。App Store のリンクは部品が足す。
    static func messages(total: Double) -> [String] {
        let meters = HomerunText.meters(total)
        return [
            tr("柵越えおじさんで 10 球の合計 %@ 飛ばした！ #あそびば", meters),
            tr("柵越えおじさん、合計 %@ かっ飛ばしました。あなたはどこまで飛ばせる？ #あそびば", meters),
            tr("%@ 越えの大ホームラン連発！ 柵越えおじさん #あそびば", meters),
        ]
    }

    /// 使う案の番号（`messages` の添字）。会長が選んだらここだけ変える。
    static let selectedMessageIndex = 0

    static func message(total: Double) -> String {
        let all = messages(total: total)
        return all[min(selectedMessageIndex, all.count - 1)]
    }
}

extension HomerunModel {
    /// 挑戦が終わった時点で、結果画面に提案を出すか決める。
    func updateXShareEligibility(for challenge: HomerunChallenge) {
        xShareGranted = false
        xShareOfferEligible = challenge.totalDistance >= HomerunXShare.thresholdMeters
            && !XShareReward.isClaimed(defaults, gameID: Self.gameID)
    }

    /// X でポストしたと見なせたときの特典。ゲームごとに 1 回だけで、2 回目は何も渡さない。
    func grantXShareReward(now: Date = Date()) {
        guard xShareOfferEligible, !xShareGranted, !XShareReward.isClaimed(defaults, gameID: Self.gameID) else { return }
        XShareReward.markClaimed(defaults, gameID: Self.gameID)
        applyShareBonus(now: now)
        xShareGranted = true
        services?.gameDidGrantShareReward(gameID: Self.gameID, items: .challenge)
    }

    /// 結果画面に出す提案。出さないとき nil。
    public func xShareOffer() -> XShareOffer? {
        guard xShareOfferEligible, let challenge else { return nil }
        return XShareOffer(
            title: tr("X でポストして、今日のプレイ回数 ＋%lld をもらう", HomerunLedger.shareBonus),
            grantedText: tr("今日のプレイ回数が ＋%lld 回になりました！", HomerunLedger.shareBonus),
            message: HomerunXShare.message(total: challenge.totalDistance),
            onShown: { [weak self] in self?.services?.gameDidOfferXShare(gameID: Self.gameID, step: .shown) },
            onTap: { [weak self] in self?.services?.gameDidOfferXShare(gameID: Self.gameID, step: .tap) },
            onPosted: { [weak self] in self?.grantXShareReward() }
        )
    }
}
