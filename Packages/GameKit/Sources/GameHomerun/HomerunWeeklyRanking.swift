import Foundation
import Core
import HomerunCore

/// 柵越えおじさんの週間ランキング（#1792）の、画面に依らない部分。
///
/// 送る値は **1 挑戦の総飛距離 m**。月まで飛んだ打球は画面表示どおり 384,400 km（= 384,400,000 m）で数える
/// （会長決定 2026-10-08。常設の自己ベスト・通算は 180 m のまま）。送り先は Game Center の定期リーダーボード
/// （毎週月曜 0:00 JST 開始・7 日・ベストスコア型。作成は会長操作）で、ID は `GameCenterLeaderboard.homerunWeekly`。
public enum HomerunWeekly {
    /// 挑戦 1 回ぶんの送る値（m・切り捨て）。月 1 本ごとに `homerunWeeklyMoonMeters` を足し、上限
    /// （`homerunWeeklyMaxMeters`）を超える値は送らない（nil）。
    public static func score(for challenge: HomerunChallenge) -> Int? {
        let moons = challenge.results.filter(\.isMoon)
        let others = challenge.results.filter { !$0.isMoon }.reduce(0) { $0 + $1.distance }
        let total = Int(others) + moons.count * GameCenterLeaderboard.homerunWeeklyMoonMeters
        guard total >= 0, total <= GameCenterLeaderboard.homerunWeeklyMaxMeters else { return nil }
        return total
    }

    /// 順位表が前の週のものか（その回の終わりを過ぎている）。終わりが取れない表は今週のものとして扱う。
    static func isPastWeek(_ board: GameCenterBoard, now: Date) -> Bool {
        guard let end = board.end else { return false }
        return end <= now
    }

    /// 今週の順位表として出せる形にする（#2216）。週が切り替わった直後に前週の表が残っていたら、前週の順位・行は捨てて
    /// 「今週はまだ誰も記録していない」表にする（期間は前週の続きの 1 回ぶん）。
    static func currentWeek(_ board: GameCenterBoard, now: Date) -> GameCenterBoard {
        guard isPastWeek(board, now: now), let end = board.end else { return board }
        var start = end
        var length = board.start.map { end.timeIntervalSince($0) } ?? 7 * 86_400
        if length <= 0 { length = 7 * 86_400 }
        // 何週ぶんも経っていたら、いまを含む回まで進める。
        while start.addingTimeInterval(length) <= now { start = start.addingTimeInterval(length) }
        return GameCenterBoard(rows: [], myRank: nil, myScore: nil, participants: 0,
                               start: start, end: start.addingTimeInterval(length),
                               lastWeekRank: nil)
    }
}

/// 打席前の「今週のランキング」の行（#2216）の、状態ごとの文言。表記は結果画面・ランキングページの既存の文言に合わせる。
enum HomerunLobbyRankText {
    /// 行の 2 段目に出す文言。nil は行を出さない（送り先が未作成）。
    static func detail(for state: HomerunModel.WeeklyState, language: AppLanguage? = nil) -> String? {
        switch state {
        case .off:
            return nil
        case .signedOut:
            return tr("Game Center に登録すると見られます", language: language)
        case .loading:
            return tr("今週の順位を読み込んでいます", language: language)
        case .failed:
            return tr("ランキングを取得できませんでした", language: language)
        case .ready(_, let board):
            guard let rank = board.myRank else { return tr("今週はまだ記録がありません", language: language) }
            // 人数が取れない（0・順位より少ない）ときは順位だけ。
            guard board.participants >= rank else { return tr("%lld位", rank, language: language) }
            return tr("%1$lld位 / %2$lld人", rank, board.participants, language: language)
        }
    }
}

/// ランキングページの 1 行（Core の `RankingEntry`・#3327。スコアは m）。
typealias HomerunRankEntry = RankingEntry

extension RankingEntry {
    init(id: String, name: String, meters: Int, rank: Int, isMe: Bool) {
        self.init(id: id, name: name, score: meters, rank: rank, isMe: isMe)
    }

    var meters: Int { score }
    var moonCount: Int { score / GameCenterLeaderboard.homerunWeeklyMoonMeters }
}

/// 今回の挑戦で自分の行が上がるアニメの計画（B 案「一気に飛び上がる」・会長決定 2026-10-09）。Core の `RankingMotion`。
typealias HomerunRankingMotion = RankingMotion

extension RankingMotion {
    var newMeters: Int { newScore }
}

enum HomerunRankingPlan {
    static func entries(of board: GameCenterBoard) -> [HomerunRankEntry] { RankingPlan.entries(of: board) }

    /// 送る前の自分の記録と送った後の順位表から、アニメを作る。送る前の表が読めなかったときは nil（静止の表）。
    static func motion(before: GameCenterBoard?, after: GameCenterBoard) -> HomerunRankingMotion? {
        guard let before else { return nil }
        return RankingPlan.motion(beforeScore: before.myScore ?? 0, after: after)
    }
}

/// ランキングの文言。
enum HomerunRankingText {
    private static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    static func group(_ n: Int) -> String { grouping.string(from: NSNumber(value: n)) ?? "\(n)" }

    /// 距離の表示。100 万 m（= 1,000 km）以上は「km + 端数の m」（月を含む値で、月以外の打球の分まで見せる）、
    /// それ未満は m（桁区切り）。
    static func distance(_ meters: Int) -> String {
        meters >= 1_000_000 ? "\(group(meters / 1000)) km + \(group(meters % 1000)) m" : "\(group(meters)) m"
    }

    /// 月まで飛んだ行の補足（飛んでいなければ nil）。
    static func moonNote(_ entry: HomerunRankEntry) -> String? {
        switch entry.moonCount {
        case 0: nil
        case 1: tr("月まで飛んだ")
        default: tr("月を割った")
        }
    }

    /// 「あと ◯ で ◯位」。上の人の記録を 1 m 上回る距離。
    static func gap(aboveMeters: Int, myMeters: Int, aboveRank: Int) -> String {
        tr("あと %1$@ で %2$lld位", distance(aboveMeters - myMeters + 1), aboveRank)
    }

    /// 順位の数字のうしろに付ける語。日本語は「位」、英語は序数の語尾（1st・2nd・3rd・11th…）。
    static func rankSuffix(_ rank: Int, language: AppLanguage? = nil) -> String {
        let language = language ?? AppLanguageStore.shared.language
        guard language == .english else { return tr("位", language: language) }
        if (11...13).contains(rank % 100) { return "th" }
        switch rank % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    /// 「10/5（月）〜 10/11（日）　あと 3 日」。終わりは `end` の 1 秒前の日付（次の週の始まりの前日）。
    /// 曜日の呼び名は表示言語のもの（日本語「月」・英語「Mon」）。
    static func weekRange(start: Date?, end: Date?, now: Date, calendar: Calendar = .current,
                          language: AppLanguage? = nil) -> String? {
        guard let start, let end, end > start else { return nil }
        let language = language ?? AppLanguageStore.shared.language
        var calendar = calendar
        calendar.locale = language.locale
        func day(_ d: Date) -> String {
            let c = calendar.dateComponents([.month, .day, .weekday], from: d)
            let weekday = calendar.shortWeekdaySymbols[(c.weekday ?? 1) - 1]
            return tr("%1$lld/%2$lld（%3$@）", c.month ?? 0, c.day ?? 0, weekday, language: language)
        }
        var text = tr("%1$@ 〜 %2$@", day(start), day(end.addingTimeInterval(-1)), language: language)
        let remaining = end.timeIntervalSince(now)
        if remaining > 0 {
            text += remaining < 86_400 ? tr("　今日まで", language: language)
                : tr("　あと %lld 日", Int(remaining / 86_400), language: language)
        }
        return text
    }
}
