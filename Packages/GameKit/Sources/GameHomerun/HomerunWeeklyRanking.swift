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
}

/// ランキングページの 1 行。
struct HomerunRankEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let meters: Int
    /// Game Center の順位。アニメの間は並びの位置（index + 1）で描くので使わない。
    let rank: Int
    let isMe: Bool

    var moonCount: Int { meters / GameCenterLeaderboard.homerunWeeklyMoonMeters }

    init(_ row: GameCenterBoardRow) {
        id = row.id
        name = row.name.isEmpty ? "プレイヤー" : row.name
        meters = row.score
        rank = row.rank
        isMe = row.isMe
    }

    init(id: String, name: String, meters: Int, rank: Int, isMe: Bool) {
        self.id = id
        self.name = name
        self.meters = meters
        self.rank = rank
        self.isMe = isMe
    }
}

/// 今回の挑戦で自分の行が上がるアニメの計画（B 案「一気に飛び上がる」・会長決定 2026-10-09）。
struct HomerunRankingMotion: Equatable {
    /// 上がる前の並び（自分は前回までの記録の位置）。
    let entries: [HomerunRankEntry]
    /// 今回の記録（m）。
    let newMeters: Int
    /// 自分の行の、前の位置と後の位置（0 始まり）。
    let from: Int
    let to: Int
}

enum HomerunRankingPlan {
    /// 一覧に出す行。自分が上位の外なら、末尾に自分の行を足す（順位は Game Center のもの）。
    static func entries(of board: GameCenterBoard) -> [HomerunRankEntry] {
        var result = board.rows.map(HomerunRankEntry.init)
        if !result.contains(where: \.isMe), let rank = board.myRank, let score = board.myScore {
            result.append(HomerunRankEntry(id: "me", name: "あなた", meters: score, rank: rank, isMe: true))
        }
        return result
    }

    /// 送る前の自分の記録と送った後の順位表から、アニメを作る。順位が上がらない（記録が伸びなかった・
    /// 送る前の記録が読めなかった・自分が上位の外）ときは nil で、静止の表を出す。
    static func motion(before: GameCenterBoard?, after: GameCenterBoard) -> HomerunRankingMotion? {
        guard let before, let newMeters = after.myScore,
              let me = after.rows.first(where: \.isMe) else { return nil }
        let oldMeters = before.myScore ?? 0
        guard newMeters > oldMeters else { return nil }
        let others = after.rows.filter { !$0.isMe }.map(HomerunRankEntry.init)
        let from = others.filter { $0.meters >= oldMeters }.count
        let to = others.filter { $0.meters > newMeters }.count
        guard to < from || before.myScore == nil else { return nil }
        var entries = others
        entries.insert(HomerunRankEntry(id: me.id, name: me.name.isEmpty ? "プレイヤー" : me.name,
                                        meters: oldMeters, rank: from + 1, isMe: true), at: from)
        return HomerunRankingMotion(entries: entries, newMeters: newMeters, from: from, to: to)
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

    /// 距離の表示。100 万 m（= 1,000 km）以上は km（切り捨て・桁区切り）、それ未満は m（桁区切り）。
    static func distance(_ meters: Int) -> String {
        meters >= 1_000_000 ? "\(group(meters / 1000)) km" : "\(group(meters)) m"
    }

    /// 月まで飛んだ行の補足（飛んでいなければ nil）。
    static func moonNote(_ entry: HomerunRankEntry) -> String? {
        switch entry.moonCount {
        case 0: nil
        case 1: "月まで飛んだ"
        default: "月を割った"
        }
    }

    /// 「あと ◯ で ◯位」。上の人の記録を 1 m 上回る距離。
    static func gap(aboveMeters: Int, myMeters: Int, aboveRank: Int) -> String {
        "あと \(distance(aboveMeters - myMeters + 1)) で \(aboveRank)位"
    }

    /// 「10/5（月）〜 10/11（日）　あと 3 日」。終わりは `end` の 1 秒前の日付（次の週の始まりの前日）。
    static func weekRange(start: Date?, end: Date?, now: Date, calendar: Calendar = .current) -> String? {
        guard let start, let end, end > start else { return nil }
        var calendar = calendar
        calendar.locale = Locale(identifier: "ja_JP")
        func day(_ d: Date) -> String {
            let c = calendar.dateComponents([.month, .day, .weekday], from: d)
            let weekday = calendar.shortWeekdaySymbols[(c.weekday ?? 1) - 1]
            return "\(c.month ?? 0)/\(c.day ?? 0)（\(weekday)）"
        }
        var text = "\(day(start)) 〜 \(day(end.addingTimeInterval(-1)))"
        let remaining = end.timeIntervalSince(now)
        if remaining > 0 {
            text += remaining < 86_400 ? "　今日まで" : "　あと \(Int(remaining / 86_400)) 日"
        }
        return text
    }
}
