import Core
import Foundation
import HomerunCore

/// 週間ランキング（#1792）: 決着の送信と、送る前後の順位表の読み込み。
extension HomerunModel {
    public enum WeeklyState: Equatable {
        /// 出さない（送り先が未作成）。
        case off
        /// 送り先はあるが Game Center にサインインしていない（ランキングページは案内だけを出す）。
        case signedOut
        /// 送信と順位表の読み込み中。
        case loading
        /// 読めなかった（オフライン等）。
        case failed
        /// 読めた。`before` は送る前の順位表（アニメの元。読めなければ nil）。
        case ready(before: GameCenterBoard?, after: GameCenterBoard)

        /// 決着のあと、結果ページの前にランキングページを挟むか（サインイン済みのときだけ）。
        public var showsAfterFinale: Bool {
            switch self {
            case .loading, .failed, .ready: true
            case .off, .signedOut: false
            }
        }
    }

    /// 決着で呼ぶ。送る前の順位表 → 送信（完了待ち）→ 送った後の順位表を順に読む。どこで失敗しても進行は止めない。
    func beginWeekly(for challenge: HomerunChallenge) {
        cancelWeekly()
        guard let leaderboardID = weeklyLeaderboardID else { return }
        guard let reporter = services?.gameCenter, reporter.isSignedIn else {
            weekly = .signedOut
            return
        }
        weekly = .loading
        let score = HomerunWeekly.score(for: challenge)
        weeklyTask = Task { [weak self] in
            let before = await reporter.loadWeeklyBoard(gameID: Self.gameID, leaderboardID: leaderboardID)
            if let score {
                _ = await reporter.submitWeeklyAndWait(gameID: Self.gameID, leaderboardID: leaderboardID, value: score)
            }
            let after = await reporter.loadWeeklyBoard(gameID: Self.gameID, leaderboardID: leaderboardID, includesLastWeek: true)
            guard !Task.isCancelled, let self else { return }
            weekly = after.map { .ready(before: before, after: $0) } ?? .failed
        }
    }

    func cancelWeekly() {
        weeklyTask?.cancel()
        weeklyTask = nil
        weekly = .off
    }
}
