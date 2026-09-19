import Foundation

/// 戦略ゲーム（将棋・チェス・五目並べ）のヒントの回数制（#1118）。
///
/// **1 か所に持つ理由**: 3 本が別々に定数と数え方を持つと、片方だけ調整したときに
/// 「同じヒントなのにゲームによって回数が違う」「片方だけ順位表から外れない」状態が静かに生まれる
/// （`RewardedUndoBudget` を Core へ上げたのと同じ理由）。回数・使い切りの判定・順位表の扱いの
/// 3 つをこの型が持ち、各ゲームの Model は値を 1 つ抱えるだけにする。
///
/// **広告での補充は持たない**（会長決裁 2026-09-19「A: 無料3回のみ・広告連携なし」）。
/// 補充が要るようになったら `RewardedUndoBudget` と同じく `refill` をここへ足す。
public struct BoardHintBudget: Equatable, Sendable {
    /// 1 局に使える回数。1 局ごとに戻る（`reset()`）。
    public static let perGame = 3

    /// ヒントを読ませる CPU の強さ（`SimpleMinimaxEngine` 等の `level`）。
    ///
    /// **対局中の CPU の強さには合わせず、常に最強で読む**。ヒントは「最善手を教えてほしい」という
    /// 求めなので、弱い CPU と対局しているときに弱い手を示しても答えにならない。五目並べの level 0 は
    /// 探索せず確率で見逃す「弱」なので、合わせると最善手ですらなくなる（#665）。
    public static let engineLevel = 2

    /// この局で使った回数。中断データにはこの値だけを保存する（残りは引き算で導ける）。
    public private(set) var used: Int

    /// - Parameter used: 中断データから復元した使用回数。壊れた値・上限を超えた値は範囲に丸める。
    public init(used: Int = 0) {
        self.used = min(max(used, 0), Self.perGame)
    }

    /// 残り回数。
    public var remaining: Int { Self.perGame - used }

    /// 使い切ったか。
    public var isExhausted: Bool { remaining <= 0 }

    /// この局でヒントを 1 回でも使ったか。順位表の資格はこれで決まる。
    public var wasUsed: Bool { used > 0 }

    /// 1 回使う。残っていなければ **何も変えずに** false を返す。
    public mutating func consume() -> Bool {
        guard !isExhausted else { return false }
        used += 1
        return true
    }

    /// 新規対局で回数を戻す。
    public mutating func reset() {
        used = 0
    }

    /// 決着に渡す成績。対象 3 本はどれも勝敗だけを記録する（`RecordMetric.winLoss`）。
    ///
    /// ヒントを 1 回でも使った局は `isLeaderboardEligible` を落として順位表へ送らない
    /// （`GameCenterLeaderboard.score` の先頭で弾かれる。ソリティアのジョーカー #406 と同じ扱い）。
    /// **ローカルの自己ベスト（`PlayRecord`）は使用の有無を問わず残る** — この旗は順位表だけに効く。
    public var winLossScore: GameScore {
        GameScore(metric: .winLoss, isLeaderboardEligible: !wasUsed)
    }
}
