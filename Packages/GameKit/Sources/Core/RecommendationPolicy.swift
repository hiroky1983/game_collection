import Foundation

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
        "shogi":         ["gomoku", "othello", "2048"],
        "gomoku":        ["othello", "shogi", "minesweeper"],
        "othello":       ["gomoku", "shogi", "2048"],
        // 「1人で盤面を詰める」系。同じ手触りの麻雀ソリティアへ抜けられるようにし（#237）、
        // マインスイーパーには最も近い論理パズルの数独を第1候補に置く。
        "2048":          ["minesweeper", "mahjong", "concentration"],
        "minesweeper":   ["sudoku", "2048", "mahjong"],
        // トランプ系。同じ札を使う大富豪（#89）へ抜けられるようにする（#237）。
        "concentration": ["2048", "daifugo", "blackjack"],
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

    /// 提示するゲーム。候補は**まだ一度も終局まで遊んでいない**ゲームに限る（条件4）。
    ///
    /// - Parameters:
    ///   - finishedGameID: 直前に遊び終えたゲーム。
    ///   - playedGameIDs: 一度でも終局まで遊んだ gameID。
    ///   - availableIDs: ハブに並んでいるゲーム（非表示を除き、ハブの並び順）。
    /// - Returns: テーブルの上から順に見て最初に条件を満たすもの。テーブルの3候補が全て埋まって
    ///   いればハブの並び順で先頭の未プレイ、未プレイが1つも無ければ nil（＝表示しない）。
    public static func candidate(
        finishedGameID: String,
        playedGameIDs: Set<String>,
        availableIDs: [String]
    ) -> String? {
        let available = Set(availableIDs)
        func isCandidate(_ id: String) -> Bool {
            available.contains(id) && !playedGameIDs.contains(id)
        }
        if let preferred = candidateTable[finishedGameID]?.first(where: isCandidate) {
            return preferred
        }
        return availableIDs.first(where: isCandidate)
    }
}
