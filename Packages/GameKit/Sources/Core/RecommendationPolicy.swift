import Foundation

/// なぜそのゲームを提示したか。カードの見出しを出し分けるのに使う（#335）。
public enum RecommendationReason: Equatable, Sendable {
    /// まだ一度も終局まで遊んでいないゲームへの提案（従来の条件4）。
    case unplayed
    /// 未プレイが尽きたあとの「久しぶり枠」。`days` は最終プレイからの経過日数で、
    /// 記録に日付が無い（この機能より前に遊んだ）場合は nil。
    case revisit(days: Int?)

    /// カードの見出し。
    public var caption: String {
        switch self {
        case .unplayed:
            return "次はこれで遊ぶ？"
        case .revisit(let days?) where days >= 1:
            return "\(days)日ぶりに遊んでみない？"
        case .revisit(nil):
            // 遊んだのは確かだが日付が無い＝この機能より前。「◯日ぶり」と断言しない。
            return "ひさしぶりに遊んでみない？"
        case .revisit:
            // 今日も遊んでいる。嘘にならない言い方に倒す。
            return "また遊んでみない？"
        }
    }
}

/// 提示するゲームと、その理由。
public struct RecommendationSuggestion: Equatable, Sendable {
    public let gameID: String
    public let reason: RecommendationReason

    public init(gameID: String, reason: RecommendationReason) {
        self.gameID = gameID
        self.reason = reason
    }
}

/// ゲーム間レコメンドの提示条件と候補テーブル。
///
/// **乱数を使わず決定的**にする。同じ状態なら常に同じ結果になるのでユニットテストで固定でき、
/// 提案が外れたときはテーブルを直せば原因と対策が1対1で対応する。
public enum RecommendationPolicy {
    /// 条件1: これだけ遊ぶまでは一度も出さない（初見の学習中には出さない）。
    public static let firstShowThreshold = 20
    /// 条件2: 定常状態での提示間隔（終了回数）。
    public static let baseInterval = 30
    /// 条件5前半: 直近2回とも無視されていたら間隔を倍にする。
    public static let extendedInterval = 60
    /// 条件5前半のしきい値。
    public static let extendedIntervalStreak = 2
    /// 条件5後半: これだけ連続で無視されたら以後表示しない。
    public static let stopStreak = 3
    /// 条件3: 前回提示からこれだけ経つまでは出さない（一気に遊ばれた日に連発しない）。
    public static let minimumElapsed: TimeInterval = 24 * 60 * 60

    /// 直前に遊んだゲーム → 提示候補（近い順）。近さの根拠は Issue #52 の表を参照。
    ///
    /// **ハブの全ゲームがキーにも値にも1回以上現れること**が不変条件（#237）。値に現れない
    /// ゲームは「他を遊んだ人には構造的に提案されない」状態になる（大富豪・麻雀ソリティア・
    /// 四人打ち麻雀・数独で実際に起きていた）。ゲームを増やしたら
    /// `RecommendationTableTests` の網羅テストが落ちるので、そこで気づける。
    public static let candidateTable: [String: [String]] = [
        // 第3候補をチェス（#462）に差し替えた。同じ「駒を動かして相手の王を詰ます」型で、
        // 2048 より近い（2048 はオセロ・マインスイーパー・数独の候補として引き続き出る）。
        "shogi":         ["gomoku", "othello", "chess"],
        // チェス（#462）。将棋が最も近く、次いで同じ盤で陣地を争うオセロ・囲碁の順。
        "chess":         ["shogi", "othello", "go"],
        // 盤と石をそのまま流用した囲碁（#398）が最も近い。
        "gomoku":        ["go", "othello", "shogi"],
        "othello":       ["gomoku", "shogi", "2048"],
        // 囲碁（#398）。同じ盤・同じ石を使う五目並べが最も近く、次いで陣地を取り合うオセロ、
        // 同じ本格ボードゲームの将棋の順で近い。
        "go":            ["gomoku", "othello", "shogi"],
        // 「1人で盤面を詰める」系。同じ手触りの麻雀ソリティアへ抜けられるようにし（#237）、
        // マインスイーパーには最も近い論理パズルの数独を第1候補に置く。
        // 第3候補をブロック崩し（#463）に差し替えた。同じ「1人でスコアを伸ばす」型で、
        // 神経衰弱（CPU 対戦）より近い（神経衰弱は下のトランプ系とブロック崩しから引き続き出る）。
        "2048":          ["minesweeper", "mahjong", "blocks"],
        // ブロック崩し（#463・アクション枠の1本目）。同じ1人用スコアアタックの 2048 が最も近く、
        // 次いで1人で盤面を消していくマインスイーパー、手軽に終わる神経衰弱の順。
        "blocks":        ["2048", "minesweeper", "concentration"],
        "minesweeper":   ["sudoku", "2048", "mahjong"],
        // トランプ系。同じ札を使う大富豪（#89）へ抜けられるようにする（#237）。
        // 第1候補は同じ「トランプを1人で並べる」ソリティア（#397）に置き換えた。
        "concentration": ["solitaire", "daifugo", "blackjack"],
        "poker":         ["blackjack", "daifugo", "concentration"],
        "blackjack":     ["poker", "daifugo", "concentration"],
        "daifugo":       ["poker", "blackjack", "concentration"],
        // 麻雀ソリティア（#90）。牌が同じ四人打ち麻雀が最も近い。
        "mahjong":       ["mahjong4", "concentration", "minesweeper"],
        // 四人打ち麻雀（#106）。牌が同じで手軽な麻雀ソリティア、同じ CPU 対戦の大富豪、
        // 役の考え方が近いポーカーの順で近い。
        "mahjong4":      ["mahjong", "daifugo", "poker"],
        // 数独（#262）。1人でじっくり詰める点でマインスイーパー・2048 が近く、
        // 同じ「盤面を消していく」手触りの麻雀ソリティアを第3候補に置く。
        "sudoku":        ["minesweeper", "2048", "mahjong"],
        // ソリティア（クロンダイク・#397）。同じ「1人で盤面を片付ける」麻雀ソリティアが最も近く、
        // 同じトランプを使う神経衰弱、1人でじっくり詰めるナンプレの順で近い。
        "solitaire":     ["mahjong", "concentration", "sudoku"],
    ]

    /// 現在の提示間隔。無視が続いているほど広がる。
    public static func interval(ignoredStreak: Int) -> Int {
        ignoredStreak >= extendedIntervalStreak ? extendedInterval : baseInterval
    }

    /// 条件1〜3・5 を満たすか。条件4（未プレイのゲームが残っているか）は `candidate` 側で判定する。
    public static func shouldShow(state: RecommendationState, now: Date) -> Bool {
        // 条件5後半: 興味が無い人には自然に消える。
        guard state.ignoredStreak < stopStreak else { return false }
        // 条件1: 一桁での発火を構造的に禁止する。
        guard state.totalFinishes >= firstShowThreshold else { return false }
        // 一度も提示していなければ、条件1を満たした時点が初回。
        guard let lastShownAt = state.lastShownAt else { return true }
        // 条件2: 前回提示からの間隔。
        guard state.totalFinishes - state.lastShownCount >= interval(ignoredStreak: state.ignoredStreak) else {
            return false
        }
        // 条件3: 時間の歯止め。
        return now.timeIntervalSince(lastShownAt) >= minimumElapsed
    }

    /// 提示するゲーム。**未プレイを優先し、尽きたら最終プレイが最も古いゲームへ回す**（条件4・#335）。
    ///
    /// 条件4は元々「未プレイに限る」だったが、それだと全ゲームを1回ずつ遊んだ時点でレコメンドが
    /// 二度と出なくなる（よく遊ぶ人ほど回遊導線が消える逆設計）。未プレイが尽きたあとは
    /// 「久しぶり枠」へ落ちるようにして、提示そのものは続くようにする。
    ///
    /// - Parameters:
    ///   - finishedGameID: 直前に遊び終えたゲーム。久しぶり枠では**自分自身を除く**
    ///     （たった今遊び終えたものを勧めない）。
    ///   - playedGameIDs: 一度でも終局まで遊んだ gameID。
    ///   - availableIDs: ハブに並んでいるゲーム（非表示を除き、ハブの並び順）。
    ///   - lastPlayedAt: ゲームごとの最終プレイ日時（`PlayLog.lastPlayedAtByGame`）。
    ///     載っていないゲームは「いつ遊んだか分からないくらい前」として最も古く扱う。
    ///   - now: 経過日数の基準時刻。
    /// - Returns: テーブルの上から順に見て最初に条件を満たすもの。テーブルの3候補が全て埋まって
    ///   いればハブの並び順で先頭の未プレイ、未プレイが1つも無ければ最終プレイが最も古いもの
    ///   （同着はハブの並び順）。提示できるゲームが1つも無ければ nil。
    public static func candidate(
        finishedGameID: String,
        playedGameIDs: Set<String>,
        availableIDs: [String],
        lastPlayedAt: [String: Date] = [:],
        now: Date = Date()
    ) -> RecommendationSuggestion? {
        let available = Set(availableIDs)
        func isUnplayed(_ id: String) -> Bool {
            available.contains(id) && !playedGameIDs.contains(id)
        }
        if let preferred = candidateTable[finishedGameID]?.first(where: isUnplayed) {
            return RecommendationSuggestion(gameID: preferred, reason: .unplayed)
        }
        if let unplayed = availableIDs.first(where: isUnplayed) {
            return RecommendationSuggestion(gameID: unplayed, reason: .unplayed)
        }
        // 久しぶり枠。`min(by:)` は同着で先に見つけたほうを残すため、結果はハブの並び順で決まる
        // （乱数を使わない = 同じ状態なら常に同じ結果、という設計をここでも保つ）。
        guard let stalest = availableIDs
            .filter({ $0 != finishedGameID })
            .min(by: { (lastPlayedAt[$0] ?? .distantPast) < (lastPlayedAt[$1] ?? .distantPast) })
        else { return nil }
        return RecommendationSuggestion(
            gameID: stalest,
            reason: .revisit(days: daysSinceLastPlay(of: stalest, lastPlayedAt: lastPlayedAt, now: now))
        )
    }

    /// 最終プレイからの経過日数（切り捨て）。日付の記録が無ければ nil。
    ///
    /// 端末の時計が巻き戻った等で未来の日付が入っていた場合は 0 に丸める（負の「-3日ぶり」を出さない）。
    static func daysSinceLastPlay(of gameID: String, lastPlayedAt: [String: Date], now: Date) -> Int? {
        guard let last = lastPlayedAt[gameID] else { return nil }
        return Int(max(0, now.timeIntervalSince(last)) / (24 * 60 * 60))
    }
}
