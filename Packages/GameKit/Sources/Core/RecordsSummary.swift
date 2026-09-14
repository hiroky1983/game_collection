import Foundation

/// アプリ内「きろく」画面（#669）に出す数字を、`PlayLog` が既に持っている値だけから組み立てた結果。
///
/// **保存項目は1つも足さない**（受け入れ条件・会長の「永続化は渋い」方針）。節目の達成も保存せず、
/// 開くたびに記録から計算し直す。そのため「プレイ記録を消去」（`PlayLog.clear()`）のあとに開けば、
/// 何もしなくても全部が「まだ遊んでいない」に戻る。
///
/// 画面（App ターゲットの `RecordsView`）は描くだけで、並び・文言・読み上げはここで決める
/// （App の View は GameKit のテストから import できないため、判断を純粋関数に寄せてテストで固定する）。
public struct RecordsSummary: Equatable, Sendable {
    /// 一覧に載せるゲーム 1 本ぶんの素性。並びは呼び出し側が渡した順のまま使う。
    public struct Game: Equatable, Sendable {
        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    /// ゲームごとの節目。**`PlayRecord` から計算できるものだけ**（新しい保存項目を要らない）。
    public enum GameMilestone: String, CaseIterable, Equatable, Sendable {
        /// 初めて勝った / クリアした。
        case firstWin
        /// 10 回遊んだ（決着した回数）。
        case plays10

        /// 10 回遊んだ、の閾値。
        public static let playsTarget = 10
    }

    /// ゲーム 1 本の行。
    public struct Row: Equatable, Sendable {
        public let gameID: String
        public let title: String
        /// 一度でも決着まで遊んだか。
        public let isPlayed: Bool
        /// ハブのカードと同じ表記の記録（「3勝5敗・2連勝中」「最短 1:23」）。数字が無ければ nil。
        public let recordLine: String?
        /// 決着した回数（全区分の合計）。
        public let plays: Int
        /// 見出しの指標が勝敗か。節目の呼び名（初勝利 / 初クリア）を分けるためだけに使う。
        public let isWinLoss: Bool
        /// 達成済みの節目（`GameMilestone.allCases` の順）。
        public let milestones: [GameMilestone]

        /// 2 段目に出す 1 行。未プレイは「まだ遊んでいない」（受け入れ条件）。
        public var detailText: String {
            guard isPlayed else { return RecordsSummary.unplayedText }
            // 遊んだのに数字が無い（スコアの無い終わり方だけ・コンティニューで負けが取り消された）
            // ときも空欄にはしない。
            return recordLine ?? "記録なし"
        }

        /// 遊んだ回数の表記。0 回（未プレイ）は出さない。
        public var playsText: String? {
            plays > 0 ? "\(RecordFormat.number(plays))回" : nil
        }

        /// 節目の呼び名。勝敗のゲームは「初勝利」、それ以外（タイム・スコア）は「初クリア」。
        public func milestoneTitle(_ milestone: GameMilestone) -> String {
            switch milestone {
            case .firstWin: return isWinLoss ? "初勝利" : "初クリア"
            case .plays10:  return "\(GameMilestone.playsTarget)回あそんだ"
            }
        }

        /// VoiceOver で 1 行ずつ読むためのラベル（受け入れ条件）。必ずゲーム名から読ませる。
        public var accessibilityLabel: String {
            var parts = [title, detailText]
            if plays > 0 { parts.append("\(RecordFormat.number(plays))回あそんだ") }
            // 10回の節目は直前の回数と同じことを言うので、読み上げでは初勝利だけを添える。
            if milestones.contains(.firstWin) { parts.append(milestoneTitle(.firstWin)) }
            return parts.joined(separator: "、")
        }
    }

    /// ゲーム横断の節目。**Game Center の実績 4 個と同じ定義**で、達成率も同じ式で出す
    /// （`GameCenterAchievements.progress` との一致はテストが縛る）。
    public struct Milestone: Equatable, Sendable {
        /// 対応する Game Center の実績 ID。
        public let achievementID: String
        public let title: String
        public let value: Int
        public let target: Int

        public var isAchieved: Bool { target > 0 && value >= target }

        /// 「3/10」。達成後は目標で頭打ちにする（「57/50」と出さない）。
        public var progressText: String {
            "\(RecordFormat.number(min(value, target)))/\(RecordFormat.number(target))"
        }

        public var accessibilityLabel: String {
            isAchieved ? "\(title)、達成" : "\(title)、\(min(value, target))/\(target)"
        }
    }

    public let rows: [Row]
    /// 一度でも遊んだゲームの数（渡されたゲームの中だけで数える）。
    public let playedCount: Int
    /// 一覧に載せたゲームの数（進捗バーの分母）。
    public let gameCount: Int
    /// 通算の勝利・クリア回数（`PlayLog.totalWins`）。
    public let totalWins: Int
    /// 勝敗のゲームの最高連勝（全ゲームで最大のもの）。
    public let bestStreak: Int
    public let milestones: [Milestone]

    /// 未プレイの行の文言。
    public static let unplayedText = "まだ遊んでいない"

    /// 進捗バーの見出し（「全部あそぶ 12/18」）。
    public var progressText: String {
        "全部あそぶ \(playedCount)/\(gameCount)"
    }

    /// 記録から組み立てる**純粋関数**（保存も送信もしない）。
    ///
    /// - Parameters:
    ///   - games: 一覧に載せるゲーム（登録済みの全ゲーム。非表示にしたものも記録は残っているので含める）。
    ///   - playedGameIDs: `PlayLog.playedGameIDs`。
    ///   - records: ゲーム ID ごとの全区分の記録（`PlayLog.records(gameID:)`）。
    ///   - totalWins: `PlayLog.totalWins`。
    public static func make(
        games: [Game],
        playedGameIDs: Set<String>,
        records: [String: [PlayRecord]],
        totalWins: Int
    ) -> RecordsSummary {
        let rows = games.map { game -> Row in
            let played = (records[game.id] ?? []).filter(\.hasAnyRecord)
            let plays = played.reduce(0) { $0 + $1.plays }
            let wins = played.reduce(0) { $0 + $1.wins }
            var milestones: [GameMilestone] = []
            if wins > 0 { milestones.append(.firstWin) }
            if plays >= GameMilestone.playsTarget { milestones.append(.plays10) }
            return Row(
                gameID: game.id,
                title: game.title,
                // `playedGameIDs` だけを見ると、コンティニューで負けを取り消した回などと食い違うことが
                // あるため、記録が残っていれば遊んだとみなす（どちらか一方で十分）。
                isPlayed: playedGameIDs.contains(game.id) || !played.isEmpty,
                recordLine: RecordFormat.hubLine(played),
                plays: plays,
                isWinLoss: played.first?.metric == .winLoss,
                milestones: milestones
            )
        }
        let playedCount = rows.filter(\.isPlayed).count
        let bestStreak = records.values.joined()
            .filter { $0.metric == .winLoss }
            .map(\.bestStreak)
            .max() ?? 0
        let milestones = [
            Milestone(achievementID: GameCenterAchievements.firstWin, title: "はじめての勝利",
                      value: totalWins, target: 1),
            Milestone(achievementID: GameCenterAchievements.wins10, title: "通算10勝",
                      value: totalWins, target: 10),
            Milestone(achievementID: GameCenterAchievements.wins50, title: "通算50勝",
                      value: totalWins, target: 50),
            Milestone(achievementID: GameCenterAchievements.playAll, title: "全部のあそびを遊ぶ",
                      value: playedCount, target: games.count),
        ]
        return RecordsSummary(
            rows: rows,
            playedCount: playedCount,
            gameCount: games.count,
            totalWins: totalWins,
            bestStreak: bestStreak,
            milestones: milestones
        )
    }
}

public extension PlayLog {
    /// いまの記録から「きろく」画面の中身を組み立てる。
    func recordsSummary(games: [RecordsSummary.Game]) -> RecordsSummary {
        RecordsSummary.make(
            games: games,
            playedGameIDs: playedGameIDs,
            records: games.reduce(into: [:]) { result, game in
                result[game.id] = records(gameID: game.id)
            },
            totalWins: totalWins
        )
    }
}
