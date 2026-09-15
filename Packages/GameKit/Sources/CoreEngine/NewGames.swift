import Foundation

/// 更新で増えたゲーム（#723）を決める純粋関数。ハブのカードの NEW 印と、更新後の初回だけ出す1行に使う。
///
/// View は App ターゲットにあり GameKit のテストから import できないため、**規則だけをここへ切り出して**
/// テストで固定する（`FirstPick` と同じ作り）。保存するのは「前回ハブを出した時点の登録ゲーム ID」だけで、
/// 読み書きは `PlayLog` が持つ（`PlayLog.knownGameIDsKey`）。
public enum NewGames {
    /// 前回の登録ゲームの記録が入る前（v1.1.4 まで）に配信していたゲーム。
    ///
    /// 記録が無い端末は「新規インストール」と「記録を持たない版からの更新」の2通りがあり、保存値だけでは
    /// 見分けられない。プレイの記録が残っている＝更新と判断し、そのときの比較元にこの一覧を使う。
    /// 記録が一度書かれた端末では使わないので、ゲームを足しても**ここは更新しない**。
    public static let legacyKnownGameIDs: Set<String> = [
        "2048", "shogi", "mahjong4", "sudoku", "othello", "go", "chess", "mahjong", "solitaire",
        "freecell", "daifugo", "poker", "blackjack", "minesweeper", "gomoku", "concentration",
        "blocks", "runner",
    ]

    /// 増えたゲームの ID を返す。
    ///
    /// - Parameters:
    ///   - registeredIDs: いまハブに登録されているゲーム。
    ///   - knownIDs: 前回ハブを出した時点の登録ゲーム。記録が無ければ nil。
    ///   - hasPlayHistory: プレイの記録が残っているか。`knownIDs` が nil のときだけ見る
    ///     （残っていなければ新規インストールとみなし、何も NEW にしない）。
    public static func ids(
        registeredIDs: [String],
        knownIDs: Set<String>?,
        hasPlayHistory: Bool
    ) -> Set<String> {
        let baseline: Set<String>
        if let knownIDs {
            baseline = knownIDs
        } else if hasPlayHistory {
            baseline = legacyKnownGameIDs
        } else {
            return []
        }
        return Set(registeredIDs).subtracting(baseline)
    }

    /// ハブ上部の1行。増えたゲームが無ければ nil（行ごと出さない）。
    public static func notice(count: Int) -> String? {
        guard count > 0 else { return nil }
        return "新しいあそびが\(count)本増えました"
    }
}
