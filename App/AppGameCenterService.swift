import GameKit
import Core

/// `GameCenterService`（Core の境界）の実体。Apple の GameKit へリーダーボードと実績を送る。
/// 認証そのものは `GameCenterAuth`（#289 段階①）が担い、ここは送信だけを担当する。
///
/// **投げっぱなしであること**が本実装の最重要要件（#289 の受け入れ条件「オフライン時に落ちない・
/// 待たされない」）:
/// - 呼び出し元はリザルト表示の同期パス。`Task` に逃がして即座に return する。
/// - 送信失敗（オフライン・App Store Connect に未登録の ID）で UI を出したりリトライを回したり
///   しない。Game Center はあくまで任意機能として上に載せる。実績だけは成否を
///   `GameCenterReporter` へ返し、失敗したぶんを**次の決着**で送り直せるようにする。
/// - `GameCenterReporter` 側で `GKLocalPlayer.local.isAuthenticated` を見てから呼ばれるため、
///   未サインイン時はそもそもここに到達しない。**サインイン済みのままオフラインになった場合は
///   ここに来る**が、その場合も上記のとおり待たない。
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

    func report(
        _ achievements: [GameCenterAchievement],
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        // GKAchievement の生成は送信直前にまとめて行う（`showsCompletionBanner` は既定の true。
        // 解除時のバナーは GameKit が出すので、アプリ側の UI は持たない）。
        let reports = achievements.map { achievement -> GKAchievement in
            let gk = GKAchievement(identifier: achievement.achievementID)
            gk.percentComplete = achievement.percentComplete
            return gk
        }
        Task {
            do {
                try await GKAchievement.report(reports)
                completion(true)
            } catch {
                // 失敗そのものは握りつぶす（UI も出さない）。成否だけを返し、
                // 送り直しの判断は `GameCenterReporter` に任せる。
                completion(false)
            }
        }
    }

    /// 解除済み（達成率 100）の実績 ID を読む（#1794）。失敗（オフライン等）は nil で、呼び出し側は何もせず進む。
    func unlockedAchievementIDs() async -> Set<String>? {
        guard let achievements = try? await GKAchievement.loadAchievements() else { return nil }
        return Set(achievements.filter(\.isCompleted).map(\.identifier))
    }

    /// 送信の完了を待つ版（週間ランキング #1792）。成否だけを返し、失敗しても UI は出さない。
    func submitAndWait(_ score: GameCenterScore) async -> Bool {
        do {
            try await GKLeaderboard.submitScore(
                score.value,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [score.leaderboardID]
            )
            return true
        } catch {
            return false
        }
    }

    /// 定期リーダーボードのいまの回の順位表を読む（#1792）。読めなかったら nil。
    func loadBoard(leaderboardID: String, topCount: Int, includesLastWeek: Bool) async -> GameCenterBoard? {
        guard let leaderboard = try? await GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]).first,
              let page = try? await leaderboard.loadEntries(
                for: .global, timeScope: .allTime, range: NSRange(location: 1, length: max(1, topCount))
              )
        else { return nil }
        let me = GKLocalPlayer.local.gamePlayerID
        let rows = page.1.map { entry in
            GameCenterBoardRow(
                id: entry.player.gamePlayerID, name: entry.player.displayName,
                score: entry.score, rank: entry.rank, isMe: entry.player.gamePlayerID == me
            )
        }
        var lastWeekRank: Int?
        if includesLastWeek,
           let previous = try? await leaderboard.loadPreviousOccurrence(),
           let last = try? await previous.loadEntries(for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 1)) {
            lastWeekRank = last.0?.rank
        }
        let end = leaderboard.startDate.map { $0.addingTimeInterval(leaderboard.duration) }
        return GameCenterBoard(
            rows: rows, myRank: page.0?.rank, myScore: page.0?.score, participants: page.2,
            start: leaderboard.startDate, end: end, lastWeekRank: lastWeekRank
        )
    }
}
