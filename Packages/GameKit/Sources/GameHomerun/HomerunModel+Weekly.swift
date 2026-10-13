import Core
import Foundation
import HomerunCore

/// 週間ランキング（#1792）: 決着の送信と、送る前後の順位表の読み込み。打席前の今週の順位（#2216）も同じ読み込みを使う。
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

    /// 週間ランキングを読めるか。送り先が未作成なら `.off`、未サインインなら `.signedOut`、読めるなら読み先。
    enum WeeklyAccess {
        case off
        case signedOut
        case available(GameCenterReporter, leaderboardID: String)
    }

    var weeklyAccess: WeeklyAccess {
        guard let leaderboardID = weeklyLeaderboardID else { return .off }
        guard let reporter = services?.gameCenter, reporter.isSignedIn else { return .signedOut }
        return .available(reporter, leaderboardID: leaderboardID)
    }

    /// 決着で呼ぶ。送る前の順位表 → 送信（完了待ち）→ 送った後の順位表を順に読む。どこで失敗しても進行は止めない。
    func beginWeekly(for challenge: HomerunChallenge) {
        cancelWeekly()
        let reporter: GameCenterReporter
        let leaderboardID: String
        switch weeklyAccess {
        case .off:
            return
        case .signedOut:
            weekly = .signedOut
            return
        case .available(let r, let id):
            (reporter, leaderboardID) = (r, id)
        }
        weekly = .loading
        let score = HomerunWeekly.score(for: challenge)
        weeklyTask = Task { [weak self] in
            let before = await Self.loadWeeklyBoard(reporter, leaderboardID: leaderboardID)
            if let score {
                _ = await reporter.submitWeeklyAndWait(gameID: Self.gameID, leaderboardID: leaderboardID, value: score)
            }
            let after = await Self.loadWeeklyBoard(reporter, leaderboardID: leaderboardID, includesLastWeek: true)
            guard !Task.isCancelled, let self else { return }
            weekly = after.map { .ready(before: before, after: $0) } ?? .failed
        }
    }

    func cancelWeekly() {
        weeklyTask?.cancel()
        weeklyTask = nil
        weekly = .off
    }

    /// 打席前の今週の順位（#2216）を読み直す。打席前に出たとき・アプリに戻ったとき・失敗の行を押したときに呼ぶ。
    /// 前に読めた順位がまだ今週のものなら、読み直しのあいだもそれを出し続ける（行がちらつかない）。
    func refreshLobbyWeekly(now: Date = Date()) {
        lobbyWeeklyTask?.cancel()
        lobbyWeeklyTask = nil
        let reporter: GameCenterReporter
        let leaderboardID: String
        switch weeklyAccess {
        case .off:
            lobbyWeekly = .off
            return
        case .signedOut:
            lobbyWeekly = .signedOut
            return
        case .available(let r, let id):
            (reporter, leaderboardID) = (r, id)
        }
        if case .ready(_, let board) = lobbyWeekly, !HomerunWeekly.isPastWeek(board, now: now) {
            // 読み直しのあいだも今の表示を残す。
        } else {
            lobbyWeekly = .loading
        }
        lobbyWeeklyTask = Task { [weak self] in
            let board = await Self.loadWeeklyBoard(reporter, leaderboardID: leaderboardID, includesLastWeek: true)
            guard !Task.isCancelled, let self else { return }
            lobbyWeekly = board.map { .ready(before: nil, after: $0) } ?? .failed
        }
    }

    /// 打席前に出す今週の順位の状態。読んだ順位表が前週のもの（読んだあとで週が切り替わった・Game Center が前の回を
    /// 返した）なら、前週の順位は出さず「今週はまだ記録がない」表にする。
    func lobbyWeeklyState(now: Date) -> WeeklyState {
        guard case .ready(_, let board) = lobbyWeekly else { return lobbyWeekly }
        return .ready(before: nil, after: HomerunWeekly.currentWeek(board, now: now))
    }

    /// 週間ランキングの順位表を読む唯一の入口（決着の前後と打席前で共通）。
    private static func loadWeeklyBoard(_ reporter: GameCenterReporter, leaderboardID: String,
                                        includesLastWeek: Bool = false) async -> GameCenterBoard? {
        await reporter.loadWeeklyBoard(gameID: gameID, leaderboardID: leaderboardID, includesLastWeek: includesLastWeek)
    }
}
