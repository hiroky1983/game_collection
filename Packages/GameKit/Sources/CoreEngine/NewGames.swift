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

    /// この版で新しく追加されたゲームの ID（#2104）。次の版で新しいゲームが入ったら、その版のゲームに入れ替える。
    ///
    /// 利用者の端末の状態（初回起動・更新・プレイ履歴）とは無関係に、ハブのカードの NEW 印と先頭への
    /// 固定に使う。`ids` が決める「更新後の最初の1回だけ」の判定とは別物（1行のお知らせ用）。
    ///
    /// v1.1.15 は新着なし（会長指示 2026-10-31）。次に新ゲームを出す版でここへ足す。
    public static let currentVersionIDs: Set<String> = []

    /// ハブに並べるゲームの順。この版の新着を先に、そのあとに残りを並べる。どちらも元の順
    /// （利用者の並び替え設定を反映済みの順）を保つ。
    ///
    /// - Parameter visibleIDs: 非表示を除いた、利用者の並びのゲーム ID。非表示のゲームは入っていないので
    ///   新着でも出てこない。
    public static func pinned(visibleIDs: [String], newIDs: Set<String> = currentVersionIDs) -> [String] {
        visibleIDs.filter { newIDs.contains($0) } + visibleIDs.filter { !newIDs.contains($0) }
    }

    /// 長押しメニューの「いちばん上に置く」（#662）が、すでに**表示上**その位置にあるか（#2124）。
    ///
    /// 位置は非表示も含む `orderedIDs` で数える（設定シートの座標）。新着は表示で先頭に固定されるため、
    /// 通常のゲームの前に新着（表示中のもの）しか無ければ、すでに「新着の直後」＝メニューが言う先頭にある。
    /// 新着自身は、前に何かあれば動かす余地がある。前に非表示のゲームがあるときも動かす余地を残す。
    public static func isAlreadyAtTop(
        id: String,
        orderedIDs: [String],
        hiddenIDs: Set<String>,
        newIDs: Set<String> = currentVersionIDs
    ) -> Bool {
        guard let index = orderedIDs.firstIndex(of: id) else { return true }
        let before = orderedIDs[..<index]
        if newIDs.contains(id) { return before.isEmpty }
        return before.allSatisfy { newIDs.contains($0) && !hiddenIDs.contains($0) }
    }

    /// 「いちばん上に置く」のあとの VoiceOver 案内。新着が先頭に固定されているときは、実際の位置（新着の次）を伝える。
    public static func moveToTopAnnouncement(
        title: String,
        id: String,
        orderedIDs: [String],
        hiddenIDs: Set<String>,
        newIDs: Set<String> = currentVersionIDs
    ) -> String {
        let pinnedAhead = !newIDs.contains(id) && orderedIDs.contains { newIDs.contains($0) && !hiddenIDs.contains($0) }
        return pinnedAhead ? tr("「%@」を新着の次に移しました", title) : tr("「%@」を先頭に移しました", title)
    }

    /// ハブ上部の1行。増えたゲームが無ければ nil（行ごと出さない）。
    public static func notice(count: Int) -> String? {
        guard count > 0 else { return nil }
        return tr("新しいあそびが%lld本増えました", count)
    }
}
