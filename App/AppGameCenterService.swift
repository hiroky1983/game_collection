import GameKit
import Core

/// `GameCenterService`（Core の境界）の実体。Apple の GameKit へリーダーボードと実績を送る。
/// 認証そのものは `GameCenterAuth`（#289 段階①）が担い、ここは送信だけを担当する。
///
/// **投げっぱなしであること**が本実装の最重要要件（#289 の受け入れ条件「オフライン時に落ちない・
/// 待たされない」）:
/// - 呼び出し元はリザルト表示の同期パス。`Task` に逃がして即座に return する。
/// - 送信失敗（オフライン・未サインイン・App Store Connect に未登録の ID）は握りつぶす。
///   リトライも UI も持たない。Game Center はあくまで任意機能として上に載せる。
/// - `GameCenterReporter` 側で `GKLocalPlayer.local.isAuthenticated` を見てから呼ばれるため、
///   未サインイン時はそもそもここに到達しない（通信を試みる経路が無い）。
@MainActor
struct AppGameCenterService: GameCenterService {
    func submit(_ score: GameCenterScore) {
        Task {
            try? await GKLeaderboard.submitScore(
                score.value,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [score.leaderboardID]
            )
        }
    }

    func report(_ achievements: [GameCenterAchievement]) {
        // GKAchievement の生成は送信直前にまとめて行う（`showsCompletionBanner` は既定の true。
        // 解除時のバナーは GameKit が出すので、アプリ側の UI は持たない）。
        let reports = achievements.map { achievement -> GKAchievement in
            let gk = GKAchievement(identifier: achievement.achievementID)
            gk.percentComplete = achievement.percentComplete
            return gk
        }
        Task {
            try? await GKAchievement.report(reports)
        }
    }
}
