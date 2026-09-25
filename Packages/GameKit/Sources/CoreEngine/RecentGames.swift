import Foundation

/// ハブ最上部の「つづき・最近」行（#660）に何を何番目に出すかを決める純粋関数。
///
/// 行そのものは App ターゲット（`HubView`）にあり GameKit のテストから import できないため、
/// **並び順と打ち切りの規則だけをここへ切り出して**テストで固定する
/// （`RecommendationPolicy` / `AdaptiveLayout` と同じ作り）。
///
/// 判断に使う材料は「中断データの有無と更新時刻」「最終プレイ日時」の2つだけで、
/// **この機能のために新しく保存するものは無い**（中断データの時刻はファイル属性、最終プレイ日時は
/// 既存の `PlayLog.lastPlayedAtByGame`）。
public enum RecentGames {
    /// 行に並べる最大枚数。横スクロール1行に収める前提の値。
    public static let maxCount = 4

    /// 行に出す 1 枚ぶん。
    public struct Candidate: Equatable, Sendable {
        /// 対象のゲーム（`GameRegistry` の ID）。
        public let gameID: String
        /// 中断データを持っているか。カードの見出しと読み上げがこれで変わる。
        public let hasResume: Bool

        public init(gameID: String, hasResume: Bool) {
            self.gameID = gameID
            self.hasResume = hasResume
        }
    }

    /// 行に出す候補を並び順で返す。**空配列なら行そのものを描かない**（余白も作らない）。
    ///
    /// 並びは「中断あり（新しい順）→ 記録だけあり（新しい順）」。中断がある人は「戻る理由が
    /// 既にある人」なので、記録より必ず前に置く。
    ///
    /// - Parameters:
    ///   - visibleGameIDs: 設定で非表示にしたものを除いたゲームの並び（`visibleModules` の順）。
    ///     **ここに無い ID は候補にならない**（受け入れ条件「非表示にしたゲームは行にも出ない」）。
    ///     同着の決着にもこの並びを使う。
    ///   - resumingGameIDs: 中断データを持つゲーム。
    ///   - resumeUpdatedAt: 中断データを最後に書いた時刻（`SnapshotStore.modifiedAt`）。
    ///     時刻を取れない実装では空でよく、その場合は `visibleGameIDs` の並びが順序になる。
    ///   - lastPlayedAt: `PlayLog.lastPlayedAtByGame`。「プレイ記録を消去」すると空になるため、
    ///     記録由来の候補はそれだけで消える（中断データは記録ではないので残る）。
    public static func candidates(
        visibleGameIDs: [String],
        resumingGameIDs: Set<String>,
        resumeUpdatedAt: [String: Date] = [:],
        lastPlayedAt: [String: Date] = [:],
        limit: Int = maxCount
    ) -> [Candidate] {
        guard limit > 0 else { return [] }
        var rank: [String: Int] = [:]
        for (index, id) in visibleGameIDs.enumerated() { rank[id] = index }

        let resuming = visibleGameIDs
            .filter { resumingGameIDs.contains($0) }
            .sorted { isOrderedBefore($0, $1, by: resumeUpdatedAt, rank: rank) }

        let played = visibleGameIDs
            .filter { !resumingGameIDs.contains($0) && lastPlayedAt[$0] != nil }
            .sorted { isOrderedBefore($0, $1, by: lastPlayedAt, rank: rank) }

        return (resuming + played)
            .prefix(limit)
            .map { Candidate(gameID: $0, hasResume: resumingGameIDs.contains($0)) }
    }

    /// 「新しい順・時刻が無ければ後ろ・同着はハブの並び」を 1 か所に閉じ込める。
    ///
    /// 同着の決着をここで明示的に付けるのが要点。`sorted(by:)` は**安定性が保証されない**ため、
    /// 比較が引き分けのままだと同じ状態から違う並びが出て、ハブを開くたびに行がちらつく。
    private static func isOrderedBefore(
        _ lhs: String, _ rhs: String, by dates: [String: Date], rank: [String: Int]
    ) -> Bool {
        switch (dates[lhs], dates[rhs]) {
        case let (left?, right?) where left != right: return left > right
        case (nil, .some): return false
        case (.some, nil): return true
        default: return (rank[lhs] ?? .max) < (rank[rhs] ?? .max)
        }
    }
}
