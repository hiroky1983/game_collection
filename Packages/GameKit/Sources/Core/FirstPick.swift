import Foundation

/// 記録がゼロの初回だけハブ最上部に出す「はじめの1本」（#721）を、出すか・何を出すか決める純粋関数。
///
/// 初回起動から初めての終局までは、「つづき・最近」（#660）もリザルトのレコメンド（#52。通算終局数が
/// 発火条件）も出ず、ハブには説明文のままのカードが横並びになるだけ。そこへ「はじめてなら、これ」を
/// 1枚だけ置く。
///
/// View は App ターゲットにあり GameKit のテストから import できないため、**規則だけをここへ切り出して**
/// テストで固定する（`RecentGames` と同じ作り）。この機能のために新しく保存するものは無い
/// （「一度でも終局したか」は既存の `PlayLog.playedGameIDs`）。
public enum FirstPick {
    /// 勧めるゲーム。乱数は使わず固定にする（受け入れ条件）。
    ///
    /// ブラックジャックにしたのは、GA4 の過去28日（2026-09-14 集計）で1人あたりの `game_start` が
    /// 全ゲーム中で最も多く（31.4回）、ルール説明なしで遊べ、1ハンドで決着する＝初めての終局に
    /// 最短で届くため。
    public static let preferredGameID = "blackjack"

    /// 出すゲームの ID を返す。**nil ならカードを描かない**（余白も作らない）。
    ///
    /// - Parameters:
    ///   - playedGameIDs: `PlayLog.playedGameIDs`。1本でも入っていたら出さない。記録の仕組みが無い
    ///     環境（nil）でも出さない（初回かどうか分からないのに勧めない）。
    ///   - visibleGameIDs: 設定で非表示にしたものを除いた並び（`visibleModules` の順）。
    ///     勧めるゲームを非表示にしていたら、並びの先頭に倒す（これも乱数なしで決まる）。
    ///   - showsRecentRow: 「つづき・最近」の行を出すか。終局前でも中断データがあれば行が出るので、
    ///     そのときは「続きから」の導線に任せて並べない。
    public static func gameID(
        playedGameIDs: Set<String>?,
        visibleGameIDs: [String],
        showsRecentRow: Bool
    ) -> String? {
        guard let playedGameIDs, playedGameIDs.isEmpty, !showsRecentRow else { return nil }
        return visibleGameIDs.contains(preferredGameID) ? preferredGameID : visibleGameIDs.first
    }
}
