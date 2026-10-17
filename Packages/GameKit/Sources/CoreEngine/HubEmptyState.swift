import Foundation

/// ハブに出すゲームが 0 本のときの空状態（#2002）を決める規則。
///
/// 設定の「ゲーム表示」で全ゲームを非表示にできるため、ハブが空白のまま残らないよう案内を出す。
/// View は App ターゲットにあり GameKit のテストから import できないため、**出す条件と文言だけをここへ
/// 切り出して**テストで固定する（`FirstPick` と同じ作り）。
public enum HubEmptyState {
    public static var message: String { tr("表示するゲームがありません。設定で選べます") }
    public static var buttonTitle: String { tr("設定を開く") }

    /// 見えているゲーム（特別枠を含む）が 1 本も無いとき true。
    public static func isShown(visibleGameIDs: [String]) -> Bool {
        visibleGameIDs.isEmpty
    }
}
