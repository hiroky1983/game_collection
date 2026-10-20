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

    /// `id` を並びの先頭へ移す（ほかの相対順はそのまま・#2572）。並びに無ければ何もしない。
    ///
    /// 柵越えおじさんは #2566 で通常のタイルになるまで、並びとは無関係に常に先頭の特別枠だった。
    /// 保存済みの並び（利用者が並べ替え・非表示をした端末）では末尾近くに置かれていたので、
    /// 通常のタイルになった版で一度だけこれを通し、以前と同じ先頭へ戻す。
    public static func promotingToFront(_ order: [String], id: String) -> [String] {
        guard order.contains(id) else { return order }
        return [id] + order.filter { $0 != id }
    }
}
