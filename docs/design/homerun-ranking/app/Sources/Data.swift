import Foundation

/// ランキングの 1 行（仮データ）。距離は m。月まで飛んだ打球は 384,400,000 m として数えてある（#1792）。
struct RankEntry: Identifiable, Equatable {
    let id: Int
    let name: String
    let meters: Int
    var isMe = false

    static let moonMeters = 384_400_000
    var moonCount: Int { meters / Self.moonMeters }
}

enum RankText {
    static let grouping: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    static func group(_ n: Int) -> String { grouping.string(from: NSNumber(value: n)) ?? "\(n)" }

    /// ランキング用の距離の表示。100 万 m（= 1,000 km）以上は km（切り捨て・桁区切り）、それ未満は m（桁区切り）。
    static func distance(_ meters: Int) -> String {
        meters >= 1_000_000 ? "\(group(meters / 1000)) km" : "\(group(meters)) m"
    }

    /// 月まで飛んだ行の補足（0 なら nil）。
    static func moonNote(_ entry: RankEntry) -> String? {
        switch entry.moonCount {
        case 0: nil
        case 1: "月まで飛んだ"
        default: "月を割った（\(entry.moonCount) 回）"
        }
    }

    /// 「あと ◯ で ◯位」。上の人の記録を 1 m 上回る距離。
    static func gap(to above: RankEntry, from me: RankEntry, aboveRank: Int) -> String {
        let need = above.meters - me.meters + 1
        return "あと \(distance(need)) で \(aboveRank)位"
    }
}

enum MockData {
    static let few: [RankEntry] = [
        RankEntry(id: 1, name: "プレイヤー1", meters: 1_208),
        RankEntry(id: 2, name: "プレイヤー2", meters: 1_131, isMe: true),
        RankEntry(id: 3, name: "プレイヤー3", meters: 702),
    ]

    static let many: [RankEntry] = {
        let base = [384_401_440, 1_462, 1_398, 1_355, 1_290, 1_262, 1_206, 1_188, 1_152, 1_097,
                    1_040, 988, 951, 902, 866, 810, 764, 701, 655, 598]
        return base.enumerated().map { i, m in
            RankEntry(id: i + 1, name: "プレイヤー\(i + 1)", meters: m, isMe: i == 6)
        }
    }()

    /// 入れ替えアニメ用。9 人。自分（id 9）は今回の結果の前は 980 m で 9 位、今回 1,206 m を出して 4 位になる。
    static let animBefore: [RankEntry] = [
        RankEntry(id: 1, name: "プレイヤー1", meters: 1_462),
        RankEntry(id: 2, name: "プレイヤー2", meters: 1_398),
        RankEntry(id: 3, name: "プレイヤー3", meters: 1_244),
        RankEntry(id: 4, name: "プレイヤー4", meters: 1_168),
        RankEntry(id: 5, name: "プレイヤー5", meters: 1_120),
        RankEntry(id: 6, name: "プレイヤー6", meters: 1_097),
        RankEntry(id: 7, name: "プレイヤー7", meters: 1_040),
        RankEntry(id: 8, name: "プレイヤー8", meters: 1_002),
        RankEntry(id: 9, name: "プレイヤー9", meters: 980, isMe: true),
    ]
    static let animNewMeters = 1_206
}
