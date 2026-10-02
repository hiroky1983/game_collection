import Foundation

/// 戦略ゲーム（将棋・チェス・五目並べ）のヒントの回数制（#1118・#1500）。
///
/// **1 か所に持つ理由**: 3 本が別々に定数と数え方を持つと、片方だけ調整したときに
/// 「同じヒントなのにゲームによって回数が違う」「片方だけ順位表から外れない」状態が静かに生まれる
/// （`RewardedUndoBudget` を Core へ上げたのと同じ理由）。回数・使い切りの判定・順位表の扱いの
/// 3 つをこの型が持ち、各ゲームの Model は値を 1 つ抱えるだけにする。
///
/// **無料 3 回に加え、広告 1 本ごとに 1 回だけ足せる（最大 5 回・合計 8 回）**（会長決裁 2026-09-27・#1500）。
/// 2026-09-19 の決裁「A: 無料3回のみ・広告連携なし」はこの Issue で上書きされた。
/// 無料枠と広告枠は同じ `used` を共有する 1 本のカウンタで、無料が残っているうちは広告を要求しない
/// （`hasFreeRemaining` で判定する）。
public struct BoardHintBudget: Equatable, Sendable {
    /// 無料で使える回数。1 局ごとに戻る（`reset()`）。
    public static let perGame = 3
    /// 無料枠を使い切った後、広告 1 本につき 1 回だけ足せる上限。
    public static let adRefillMax = 5
    /// 1 局で使える合計回数（無料 + 広告）。
    public static let total = perGame + adRefillMax

    /// ヒントを読ませる CPU の強さ（`SimpleMinimaxEngine` 等の `level`）。
    ///
    /// **対局中の CPU の強さには合わせず、常に最強で読む**。ヒントは「最善手を教えてほしい」という
    /// 求めなので、弱い CPU と対局しているときに弱い手を示しても答えにならない。五目並べの level 0 は
    /// 探索せず確率で見逃す「弱」なので、合わせると最善手ですらなくなる（#665）。
    /// **v1.1.6 では「ガチ」を一旦見送った**ため、現行の最強である `.hard`（むずかしい）を指す
    /// （`.serious` 復活時はそちらへ戻す。#1196）。
    public static let engineLevel = CPUStrength.hard.rawValue

    /// ヒントが「むずかしい」より長く考える時間（秒）。ヒントは設定が「むずかしい」と全く同じだと
    /// 対「むずかしい」で互角にしかならないため、考える時間だけ +0.5 秒にする（会長決裁 2026-10-02・#1739。
    /// 毎手従った勝率は将棋 64.2%・チェス 58.2%・五目並べ 50.2%）。深さ・確率・定跡は「むずかしい」のまま。
    public static let extraThinkingTime: TimeInterval = 0.5

    /// この局で使った回数。中断データにはこの値だけを保存する（残りは引き算で導ける）。
    public private(set) var used: Int

    /// - Parameter used: 中断データから復元した使用回数。壊れた値・上限を超えた値は範囲に丸める。
    public init(used: Int = 0) {
        self.used = min(max(used, 0), Self.total)
    }

    /// 残り回数（無料 + 広告の合計）。
    public var remaining: Int { Self.total - used }

    /// 合計で使い切ったか。
    public var isExhausted: Bool { remaining <= 0 }

    /// この局でヒントを 1 回でも使ったか。順位表の資格はこれで決まる。
    public var wasUsed: Bool { used > 0 }

    /// 無料枠がまだ残っているか。true のあいだは次の 1 回が無料で出せる
    /// （= 次の 1 回に広告が要るかは `!hasFreeRemaining && !isExhausted` で判定する）。
    public var hasFreeRemaining: Bool { used < Self.perGame }

    /// 無料の 1 回を消費する。無料枠を使い切っていれば **何も変えずに** false を返す
    /// （広告での補充は `consumeAd()` の担当）。
    public mutating func consume() -> Bool {
        guard hasFreeRemaining else { return false }
        used += 1
        return true
    }

    /// 広告視聴後の 1 回を消費する。無料枠が残っている・8 回を使い切っている場合は
    /// **何も変えずに** false を返す（無料が残っているうちは広告を求めない契約）。
    public mutating func consumeAd() -> Bool {
        guard !hasFreeRemaining, !isExhausted else { return false }
        used += 1
        return true
    }

    /// 新規対局で回数を戻す（無料・広告とも戻る）。
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
