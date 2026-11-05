import Foundation
import Core
import CoreEngine

/// 「X でポストして特典をもらう」（#3359・会長決裁 2026-11-06）のねこさがし側。
///
/// - 出すのは、**鍵の面（10 面ごと）を初めてクリアした結果画面**で、まだこのゲームの特典を受け取っていないとき。
///   提案を閉じた（ポストしなかった）なら、次に別の鍵の面を初めてクリアした結果画面で再び出す。
/// - 特典はヒント ＋2・餌をあげる ＋2（ステージ共通の残りに足す。`stageSupplyCount` を超えてよい）。ゲームごとに 1 回だけ。
enum CatPuzzleXShare {
    static let hints = 2
    static let teaches = 2

    /// 共有する本文の案（会長がマージ後に選ぶ。選ぶまでは `selectedMessageIndex` の 1 案目）。
    /// 外部の商標名・元ネタの名前は書かない。App Store のリンクは部品が足す。
    static var messages: [String] {
        [
            tr("おじさんちのねこさがしで、鍵の面をクリアしました！ #あそびば"),
            tr("おじさんちのねこさがし、鍵の面まで来ました。猫はどこにいる？ #あそびば"),
            tr("鍵を持った猫を見つけて、鍵の面をクリア！ おじさんちのねこさがし #あそびば"),
        ]
    }

    /// 使う案の番号（`messages` の添字）。会長が選んだらここだけ変える。
    static let selectedMessageIndex = 0

    static var message: String { messages[min(selectedMessageIndex, messages.count - 1)] }
}

extension CatPuzzleModel {
    /// クリアの時点で、結果画面に提案を出すか決める。`stage + 1 > savedStage` は「この面を初めてクリアした」（`finish` が進捗を進める前に呼ぶ）。
    func updateXShareEligibility() {
        xShareGranted = false
        guard let stage else { xShareOfferEligible = false; return }
        xShareOfferEligible = CatPuzzleStage(stage).isKey && stage + 1 > savedStage
            && !XShareReward.isClaimed(stageDefaults, gameID: Self.gameID)
    }

    /// X でポストしたと見なせたときの特典。ゲームごとに 1 回だけで、2 回目は何も渡さない。
    func grantXShareReward() {
        guard xShareOfferEligible, !xShareGranted, !XShareReward.isClaimed(stageDefaults, gameID: Self.gameID) else { return }
        XShareReward.markClaimed(stageDefaults, gameID: Self.gameID)
        addStageSupply(hints: CatPuzzleXShare.hints, teaches: CatPuzzleXShare.teaches)
        xShareGranted = true
        services?.gameDidGrantShareReward(gameID: Self.gameID, items: .hintTeach)
    }

    /// 結果画面に出す提案。出さないとき nil。
    func xShareOffer() -> XShareOffer? {
        guard xShareOfferEligible else { return nil }
        return XShareOffer(
            title: tr("X でポストして、ヒント ＋%1$lld・餌をあげる ＋%2$lld をもらう", CatPuzzleXShare.hints, CatPuzzleXShare.teaches),
            grantedText: tr("ヒント ＋%1$lld・餌をあげる ＋%2$lld をもらいました！", CatPuzzleXShare.hints, CatPuzzleXShare.teaches),
            message: CatPuzzleXShare.message,
            onShown: { [weak self] in self?.services?.gameDidOfferXShare(gameID: Self.gameID, step: .shown) },
            onTap: { [weak self] in self?.services?.gameDidOfferXShare(gameID: Self.gameID, step: .tap) },
            onPosted: { [weak self] in self?.grantXShareReward() }
        )
    }
}
