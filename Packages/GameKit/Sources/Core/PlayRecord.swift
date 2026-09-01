import Foundation

/// そのゲームの「らしさ」を1行で表すときに主役にする指標（#115）。
///
/// ゲームごとに意味のある数字が違う（2048 はスコア、マインスイーパーはタイム、将棋は勝敗）ため、
/// 保存する値は共通の `PlayRecord` に持たせ、**どれを見出しにするか**だけをこの enum で選ぶ。
/// こうするとハブとリザルトの表示ロジックを 1 か所に集約でき、ゲームごとの分岐を撒かずに済む。
public enum RecordMetric: String, Codable, Equatable, Sendable {
    /// 高いほど良い数値（2048 のスコア、ポーカー / ブラックジャックのチップ）。
    case points
    /// 短いほど良いクリアタイム（マインスイーパー・麻雀ソリティア）。
    case shortestTime
    /// 少ないほど良い手数。
    case fewestMoves
    /// 勝敗と連勝（CPU と対戦するもの）。
    case winLoss
}

/// ゲーム 1 回ぶんの成績。決着を判定した Model が `GameServices.gameDidFinish` へ渡す。
///
/// すべて任意項目で、渡された項目だけが自己ベストの判定対象になる。
public struct GameScore: Equatable, Sendable {
    /// ハブ・リザルトで見出しにする指標。
    public var metric: RecordMetric
    /// 高いほど良い数値（スコア・チップ）。
    public var points: Int?
    /// 到達した最大値（2048 の最大タイル）。高いほど良い。
    public var highestValue: Int?
    /// クリアまでの秒数。短いほど良い。**勝ち / クリアのときだけ記録する**。
    public var seconds: Int?
    /// クリアまでの手数。少ないほど良い。**勝ち / クリアのときだけ記録する**。
    public var moves: Int?
    /// 記録を分けたい区分のキー（マインスイーパーの難易度）。nil ならゲーム単位で 1 件。
    public var variant: String?
    /// 区分の表示名（「初級」など）。ハブの 1 行に添える。
    public var variantLabel: String?

    public init(
        metric: RecordMetric = .winLoss,
        points: Int? = nil,
        highestValue: Int? = nil,
        seconds: Int? = nil,
        moves: Int? = nil,
        variant: String? = nil,
        variantLabel: String? = nil
    ) {
        self.metric = metric
        self.points = points
        self.highestValue = highestValue
        self.seconds = seconds
        self.moves = moves
        self.variant = variant
        self.variantLabel = variantLabel
    }
}

/// 1 ゲーム（区分がある場合は 1 区分）ぶんの自己ベストと通算成績。
///
/// 盤面・棋譜は持たない。持つのは下の数値だけで、**プレイ回数が増えても項目数は増えない**
/// （区分ぶんだけ横に増えるが、上限は登録ゲーム数 + 難易度数で固定）。
public struct PlayRecord: Codable, Equatable, Sendable {
    /// 見出しにする指標。
    public var metric: RecordMetric
    /// 区分の表示名（マインスイーパーの「初級」など）。
    public var variantLabel: String?
    /// 終局した回数（勝敗を問わない）。
    public var plays: Int
    public var wins: Int
    public var losses: Int
    public var draws: Int
    /// 現在の連勝数。勝ち以外（負け・引き分け）で 0 に戻る。
    public var currentStreak: Int
    /// 過去最高の連勝数。
    public var bestStreak: Int
    /// 自己ベストのスコア・チップ。
    public var bestPoints: Int?
    /// 到達した最大値（2048 の最大タイル）。
    public var highestValue: Int?
    /// 最短クリアタイム（秒）。
    public var bestSeconds: Int?
    /// 最少クリア手数。
    public var fewestMoves: Int?
    /// 最後に決着した日時。レコメンドの「久しぶり枠」（#335）が使う。
    ///
    /// **必ず Optional にする**。旧データ（この項目が入る前に保存された JSON）には鍵が無く、
    /// 非 Optional にすると `PlayLog` のデコードが丸ごと失敗して**全記録が空に倒れる**
    /// （`PlayLog.init` の壊れた JSON へのフォールバック）。日付が無いものは
    /// 「いつ遊んだか分からないくらい前」として扱う。
    public var lastPlayedAt: Date?

    public init(
        metric: RecordMetric = .winLoss,
        variantLabel: String? = nil,
        plays: Int = 0,
        wins: Int = 0,
        losses: Int = 0,
        draws: Int = 0,
        currentStreak: Int = 0,
        bestStreak: Int = 0,
        bestPoints: Int? = nil,
        highestValue: Int? = nil,
        bestSeconds: Int? = nil,
        fewestMoves: Int? = nil,
        lastPlayedAt: Date? = nil
    ) {
        self.metric = metric
        self.variantLabel = variantLabel
        self.plays = plays
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.bestPoints = bestPoints
        self.highestValue = highestValue
        self.bestSeconds = bestSeconds
        self.fewestMoves = fewestMoves
        self.lastPlayedAt = lastPlayedAt
    }

    /// 何か 1 つでも記録があるか。何も無いゲームはハブに 1 行も出さない。
    public var hasAnyRecord: Bool {
        plays > 0
    }
}

/// 直近の 1 回で「自己ベストが更新されたか」の内訳。リザルトの「自己ベスト更新！」の判定に使う。
///
/// **同点は更新扱いにしない**（すべて狭義の大小比較）。同じスコアで何度も「更新！」が出ると
/// 表示の意味が薄れるため。
public struct RecordUpdate: Equatable, Sendable {
    public var points: Bool
    public var highestValue: Bool
    public var seconds: Bool
    public var moves: Bool
    public var streak: Bool

    public init(
        points: Bool = false,
        highestValue: Bool = false,
        seconds: Bool = false,
        moves: Bool = false,
        streak: Bool = false
    ) {
        self.points = points
        self.highestValue = highestValue
        self.seconds = seconds
        self.moves = moves
        self.streak = streak
    }

    /// 1 つでも更新されたか。
    public var isNewBest: Bool {
        points || highestValue || seconds || moves || streak
    }
}

/// 決着 1 回ぶんの記録結果。更新後の記録と、その回の更新内訳をまとめて Model に返す。
public struct RecordResult: Equatable, Sendable {
    public let record: PlayRecord
    public let update: RecordUpdate

    public init(record: PlayRecord, update: RecordUpdate) {
        self.record = record
        self.update = update
    }
}

public extension PlayRecord {
    /// 自分（古い側）を `newer`（新しい側）に畳み込んだ記録を返す（#383）。
    ///
    /// キーの付け替え（区分の後付け）で新旧2件に割れてしまった記録を1件に戻すためのもの。
    /// 通算は足し合わせ、自己ベストは良いほうを採り、「今」を表す項目
    /// （見出しの指標・区分名・現在の連勝）は**新しい側を優先する**。
    /// 古い記録の連勝は既に途切れているため、足したり大きいほうを採ったりしない。
    func merged(into newer: PlayRecord) -> PlayRecord {
        var result = newer
        result.plays  += plays
        result.wins   += wins
        result.losses += losses
        result.draws  += draws
        result.bestStreak = max(bestStreak, newer.bestStreak)
        result.bestPoints   = Self.better(bestPoints, newer.bestPoints, by: >)
        result.highestValue = Self.better(highestValue, newer.highestValue, by: >)
        result.bestSeconds  = Self.better(bestSeconds, newer.bestSeconds, by: <)
        result.fewestMoves  = Self.better(fewestMoves, newer.fewestMoves, by: <)
        if let mine = lastPlayedAt, mine > (newer.lastPlayedAt ?? .distantPast) {
            result.lastPlayedAt = mine
        }
        return result
    }

    /// 「片方だけある」を落とさずに良いほうを選ぶ。両方あるときだけ `isBetter` で比べる。
    private static func better(_ a: Int?, _ b: Int?, by isBetter: (Int, Int) -> Bool) -> Int? {
        guard let a else { return b }
        guard let b else { return a }
        return isBetter(a, b) ? a : b
    }

    /// 決着 1 回を既存の記録に反映した結果を返す純粋関数。永続化から切り離してテストできるようにする。
    ///
    /// - Parameters:
    ///   - previous: それまでの記録。初回は nil。
    ///   - at: 決着した日時（#335 の「久しぶり枠」に使う）。テストから固定できるよう引数で受ける。
    /// - Note: タイムと手数は**勝ち / クリアのときだけ**取り込む。負けた局の経過時間を
    ///   「最短クリアタイム」に混ぜると、投了した瞬間が常に最短になってしまうため。
    static func applying(
        outcome: GameOutcome,
        score: GameScore,
        to previous: PlayRecord?,
        at date: Date = Date()
    ) -> RecordResult {
        var record = previous ?? PlayRecord()
        var update = RecordUpdate()

        // 見出しの指標と区分名は常に最新の申告で上書きする（表示名の変更に追従するため）。
        record.metric = score.metric
        if let label = score.variantLabel { record.variantLabel = label }

        record.plays += 1
        // 前後する日時で呼ばれても巻き戻らない（端末の時計がずれて補正されたときなど）。
        // 「最後に遊んだのはいつか」を古いほうに倒すと、久しぶり枠が実際より古い候補として拾う。
        if date > (record.lastPlayedAt ?? .distantPast) {
            record.lastPlayedAt = date
        }
        switch outcome {
        case .win:
            record.wins += 1
            record.currentStreak += 1
            if record.currentStreak > record.bestStreak {
                record.bestStreak = record.currentStreak
                // 初勝利（1 連勝）も「更新」ではあるが、演出としては煩いので 2 連勝以上に絞る。
                update.streak = record.currentStreak >= 2
            }
        case .loss:
            record.losses += 1
            record.currentStreak = 0
        case .draw:
            record.draws += 1
            // 引き分けは「連勝」ではないため連勝は途切れる。
            record.currentStreak = 0
        }

        if let points = score.points, points > (record.bestPoints ?? Int.min) {
            record.bestPoints = points
            update.points = true
        }
        if let highest = score.highestValue, highest > (record.highestValue ?? Int.min) {
            record.highestValue = highest
            update.highestValue = true
        }
        if outcome == .win {
            if let seconds = score.seconds, seconds < (record.bestSeconds ?? Int.max) {
                record.bestSeconds = seconds
                update.seconds = true
            }
            if let moves = score.moves, moves < (record.fewestMoves ?? Int.max) {
                record.fewestMoves = moves
                update.moves = true
            }
        }

        return RecordResult(record: record, update: update)
    }
}

/// 記録を日本語 1 行に整形する。ハブのカードとリザルトで同じ表記を使うためのもの。
public enum RecordFormat {
    /// 秒数を `M:SS` / `H:MM:SS` に整形する。
    public static func time(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }

    /// 3 桁区切りの数値（12,340）。
    public static func number(_ value: Int) -> String {
        let digits = String(abs(value))
        var grouped = ""
        for (offset, ch) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { grouped.append(",") }
            grouped.append(ch)
        }
        return (value < 0 ? "-" : "") + grouped
    }

    /// ハブのゲームカードに出す 1 行。記録がまだ無ければ nil（＝何も出さない）。
    ///
    /// - Parameter records: そのゲームの全区分の記録（マインスイーパーなら難易度 3 件）。
    public static func hubLine(_ records: [PlayRecord]) -> String? {
        let played = records.filter(\.hasAnyRecord)
        guard let metric = played.first?.metric else { return nil }

        switch metric {
        case .shortestTime:
            // 区分が複数あるときは一番速い記録を代表にする（1 行に収めるため）。
            guard let best = played.compactMap({ r in r.bestSeconds.map { ($0, r.variantLabel) } })
                .min(by: { $0.0 < $1.0 }) else { return nil }
            let label = best.1.map { "（\($0)）" } ?? ""
            return "最短 \(time(best.0))\(label)"
        case .points:
            guard let best = played.compactMap(\.bestPoints).max() else { return nil }
            return "ベスト \(number(best))"
        case .fewestMoves:
            guard let best = played.compactMap(\.fewestMoves).min() else { return nil }
            return "最少 \(number(best))手"
        case .winLoss:
            let streak = played.map(\.currentStreak).max() ?? 0
            let base = winLossText(played)
            return streak >= 2 ? "\(base)・\(streak)連勝中" : base
        }
    }

    /// 「3勝5敗」「1勝2敗1分」の表記。引き分けは 0 のときだけ省く。
    ///
    /// 大富豪は4人中1位が勝ち・最下位が負け・**中位は引き分け**扱いのため、勝ちも負けも 0 のまま
    /// 引き分けだけが積み上がる状態が普通に起きる。勝敗だけを見て「記録なし」に倒すと、
    /// 遊んでいるのにハブに何も出ないゲームができてしまう。
    private static func winLossText(_ records: [PlayRecord]) -> String {
        let wins = records.reduce(0) { $0 + $1.wins }
        let losses = records.reduce(0) { $0 + $1.losses }
        let draws = records.reduce(0) { $0 + $1.draws }
        let base = "\(wins)勝\(losses)敗"
        return draws > 0 ? "\(base)\(draws)分" : base
    }

    /// リザルトに出す 1 行（そのゲームの自己ベスト）。記録が無ければ nil。
    public static func resultLine(_ record: PlayRecord) -> String? {
        guard record.hasAnyRecord else { return nil }
        switch record.metric {
        case .shortestTime:
            guard let best = record.bestSeconds else {
                // まだ一度もクリアしていない。挑戦した回数だけを出す（「記録なし」で終わらせない）。
                return "クリア記録なし（\(record.plays)回挑戦）"
            }
            return "最短タイム \(time(best))・\(record.wins)回クリア"
        case .points:
            guard let best = record.bestPoints else { return nil }
            if let highest = record.highestValue {
                return "自己ベスト \(number(best))（最大 \(number(highest))）"
            }
            return "自己ベスト \(number(best))"
        case .fewestMoves:
            guard let best = record.fewestMoves else { return nil }
            return "最少手数 \(number(best))手"
        case .winLoss:
            let base = "通算 \(winLossText([record]))"
            return record.bestStreak >= 2 ? "\(base)・最高\(record.bestStreak)連勝" : base
        }
    }
}
