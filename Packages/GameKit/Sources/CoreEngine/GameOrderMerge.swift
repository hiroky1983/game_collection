import Foundation

/// ハブの並び順・非表示の「保存値 × 現在登録されているゲーム」のマージ規則（#1390）。
///
/// 規則は `GameSettings`（App ターゲット）から呼ばれるが、App にはテストが無いので純粋関数として
/// ここへ切り出して固定する（`RecentGames` と同じ作り）。
public enum GameOrderMerge {
    /// 保存済みの並びを現在の登録に合わせる。
    ///
    /// - 保存済みの並びのうち、登録に無い ID（廃止・倉庫入りしたゲーム）は捨てる。
    /// - 保存済みの並びの順序はそのまま守る。
    /// - 保存に無い ID（新しく追加されたゲーム）は、**登録順のまま末尾に足す**
    ///   （既存ユーザーの並びを崩さず、新ゲームだけが末尾に付く）。
    public static func mergedOrder(stored: [String], registered: [String]) -> [String] {
        var order = stored.filter { registered.contains($0) }
        for id in registered where !order.contains(id) { order.append(id) }
        return order
    }

    /// 保存済みの非表示 ID のうち、現在も登録されているものだけを残す。
    public static func mergedHidden(stored: [String], registered: [String]) -> Set<String> {
        Set(stored.filter { registered.contains($0) })
    }
}
