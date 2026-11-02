import Foundation
import Core
import CoreEngine

/// デイリーランキング（#3204・#3221）の前日の 1〜3 位に渡す特典（#3256・会長決裁 2026-11-03）。
///
/// - 1 位 = ヒント 1 回 ＋ 猫を教える 1 回 / 2 位 = 猫を教える 1 回 / 3 位 = ヒント 1 回。
///   ステージ共通の残り（#3203）に足す（`CatPuzzleModel.stageSupplyCount` の 5 を超えてよい）。
/// - お金に換えられるもの・現実の景品は渡さない（App Store の懸賞の決まり）。
/// - 見るのは Game Center の**前回の回**の自分の順位だけ。同じ日（JST）の特典は 1 回だけで、受け取った日付を端末に保存する。
///   読めなかったとき（未サインイン・通信なし）は保存せず、次に開いたときにやり直す。
/// - 前日が開催期間の外なら渡さない（期間の最終日 12/9 の分は 12/10 に受け取れる）。
enum CatPuzzleDailyReward {
    /// 渡す中身。
    struct Grant: Equatable {
        let rank: Int
        let hints: Int
        let teaches: Int

        /// 解析 `reward_grant` の `items`。
        var items: RewardGrantItems {
            switch (hints > 0, teaches > 0) {
            case (true, true): .hintTeach
            case (false, true): .teach
            default: .hint
            }
        }

        /// カードに出す「猫を教える ＋1」などの 1 行。
        var itemsText: String {
            [hints > 0 ? tr("ヒント ＋%lld", hints) : nil, teaches > 0 ? tr("猫を教える ＋%lld", teaches) : nil]
                .compactMap { $0 }.joined(separator: "　")
        }
    }

    /// 前回の回の順位の読み取り結果。
    enum Lookup: Equatable {
        /// 読めなかった（未サインイン・通信なし・Game Center の不調）。次に開いたときにやり直す。
        case unavailable
        /// 読めた。前日の回に参加していなければ nil（読み損ねと区別できない）。
        case rank(Int?)
        /// 読めたが、前回の回が前日の回ではなかった（前日に遊んでいない。Game Center は自分がスコアを送った直近の回を返しうる）。
        case notYesterday
    }

    /// その順位の特典。4 位以下・順位なしは nil。
    static func grant(forRank rank: Int?) -> Grant? {
        switch rank {
        case 1: Grant(rank: 1, hints: 1, teaches: 1)
        case 2: Grant(rank: 2, hints: 0, teaches: 1)
        case 3: Grant(rank: 3, hints: 1, teaches: 0)
        default: nil
        }
    }

    /// 受け取った日（JST の `yyyy-MM-dd`）の保存先。
    static let claimedDayKey = "catPuzzleRewardClaimedDay"

    /// 前日が開催期間の中か（= 今日が開催初日の翌日から、最終日の翌日まで）。
    static func isPayable(now: Date) -> Bool {
        let oneDay: TimeInterval = 24 * 60 * 60
        return now >= CatPuzzleEvent.start.addingTimeInterval(oneDay) && now < CatPuzzleEvent.end.addingTimeInterval(oneDay)
    }

    /// 今日（`now` の日付）の分を、もう受け取ったか（順位の対象外と分かった日も含む）。
    static func isClaimed(_ defaults: UserDefaults, now: Date) -> Bool {
        defaults.string(forKey: claimedDayKey) == CatPuzzleEvent.day(of: now)
    }

    /// 本番の読み取り口。サインイン済みの Game Center から前回の回の自分の順位を読む。
    /// 日付が変わった直後に前の回が「いまの回」として返ったときは、その回の順位を前日として使う（`CatPuzzleRankingModel.today`）。
    @MainActor
    static func lookup(reporter: GameCenterReporter?, now: Date) async -> Lookup {
        guard let reporter, reporter.isSignedIn,
              let board = await reporter.loadWeeklyBoard(gameID: CatPuzzleModel.gameID,
                                                         leaderboardID: GameCenterLeaderboard.catPuzzleEvent,
                                                         topCount: 1, includesLastWeek: true)
        else { return .unavailable }
        let yesterday = CatPuzzleRankingModel.today(board, now: now)
        guard let rank = yesterday.lastWeekRank else { return .rank(nil) }
        return isYesterdaysOccurrence(start: yesterday.lastWeekStart, now: now) ? .rank(rank) : .notYesterday
    }

    /// その回が**前日の回**か。回の始まりが「今日の 0 時（JST）の 36 時間前から今日の 0 時まで」に入っていれば前日の回
    /// （一つ前の日の回は始まりが 48 時間前になる）。始まりが分からない回は確かめられないので前日と認めない。
    static func isYesterdaysOccurrence(start: Date?, now: Date) -> Bool {
        guard let start else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let today = calendar.startOfDay(for: now)
        return start >= today.addingTimeInterval(-36 * 60 * 60) && start < today
    }
}

extension CatPuzzleModel {
    /// 前日のランキングの特典を受け取る。開いたとき 1 回呼ぶ。渡したら `dailyRewardCard` にカードの中身を入れる。
    /// 期間外・今日の分を受け取り済み・読めなかったときは何も足さない（読めなかったときは保存しないので、次に開いたときにやり直す）。
    func claimDailyReward(lookup: @MainActor () async -> CatPuzzleDailyReward.Lookup) async {
        let started = eventNow()
        guard CatPuzzleDailyReward.isPayable(now: started),
              !CatPuzzleDailyReward.isClaimed(stageDefaults, now: started),
              !isClaimingDailyReward else { return }
        isClaimingDailyReward = true
        defer { isClaimingDailyReward = false }
        let result = await lookup()
        let now = eventNow()
        // 読んでいる間に日付が変わった・別の経路で受け取った場合は、順位が今日のものか分からないので捨てる。
        guard !Task.isCancelled, CatPuzzleEvent.day(of: now) == CatPuzzleEvent.day(of: started),
              !CatPuzzleDailyReward.isClaimed(stageDefaults, now: now),
              result != .unavailable else { return }
        // 前日に遊んでいない（前回の回が前日より前）と分かった日は 4 位以下と同じく読み直さない。
        if result == .notYesterday {
            stageDefaults.set(CatPuzzleEvent.day(of: now), forKey: CatPuzzleDailyReward.claimedDayKey)
            return
        }
        guard case .rank(let rank) = result else { return }
        guard let grant = CatPuzzleDailyReward.grant(forRank: rank) else {
            // 4 位以下と分かった日は読み直さない。順位なし（nil）は前回の回の読み損ねかもしれないので保存せず、次に開いたときに読む。
            if rank != nil { stageDefaults.set(CatPuzzleEvent.day(of: now), forKey: CatPuzzleDailyReward.claimedDayKey) }
            return
        }
        stageDefaults.set(CatPuzzleEvent.day(of: now), forKey: CatPuzzleDailyReward.claimedDayKey)
        addStageSupply(hints: grant.hints, teaches: grant.teaches)
        dailyRewardCard = grant
        services?.gameDidGrantReward(gameID: Self.gameID, rank: grant.rank, items: grant.items)
    }

    /// 特典のカードを閉じる。
    func dismissDailyRewardCard() { dailyRewardCard = nil }
}
