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

    /// ハブの一番上「ピックアップ」の区画に出すゲームの ID（#3358・会長決裁 2026-11-06）。
    /// 区画の中の順はこの並びで固定し、利用者の並び替え設定には従わない。**版を上げるときにここを書き換える**
    /// （`currentVersionIDs` と同じく、コード上の 1 か所の定数）。
    ///
    /// v1.1.16 はねこさがしとソリティア（#3447・会長指示 2026-11-09。当初の将棋から差し替え）。
    /// 柵越えおじさんは次のイベント（#2793）で上げるため今回は外す。
    public static let pickupIDs: [String] = ["catpuzzle", "solitaire"]

    /// ハブのカードに「1番人気」の札を出すゲームの ID（#3447・会長指示 2026-11-09）。
    /// 札を付けるゲームはここ 1 か所で持つ。入れ替えるときはここだけ書き換える。
    public static let mostPopularIDs: Set<String> = ["solitaire"]

    /// 区画に実際に出すゲーム（#3358）。区画を出す条件（カテゴリーが「すべて」・利用者が非表示にしていない）を
    /// 満たさないとき、および利用者がゲーム自体を非表示にしたものは出さない。区画の中の順は `pickupIDs` のまま。
    ///
    /// - Parameters:
    ///   - visibleIDs: 非表示のゲームを除いた、利用者の並びのゲーム ID。
    ///   - isHiddenByUser: 利用者が区画を非表示にしているか。版が変わっても保たれる（本人の選択を優先）。
    ///   - isAllCategory: カテゴリーが「すべて」か。絞り込み中は区画を出さない。
    public static func pickupShownIDs(
        visibleIDs: [String],
        isHiddenByUser: Bool,
        isAllCategory: Bool,
        pickupIDs: [String] = pickupIDs
    ) -> [String] {
        guard isAllCategory, !isHiddenByUser else { return [] }
        return pickupIDs.filter { visibleIDs.contains($0) }
    }

    /// ハブに並べるゲームの順。開催中のイベントのゲーム、この版の新着、そのあとに残りを並べる（#3321）。
    /// どれも元の順（利用者の並び替え設定を反映済みの順）を保つ。保存した並びは書き換えず、表示の順だけを変える
    /// ので、イベントが終われば元の並びに戻る。ピックアップ（#3358）はここでは扱わない
    /// （区画に出しているあいだ一覧から抜くのは呼び出し側）。
    ///
    /// - Parameters:
    ///   - visibleIDs: 非表示を除いた、利用者の並びのゲーム ID。非表示のゲームは入っていないので
    ///     新着でもイベントでも出てこない。
    ///   - eventIDs: いま「イベント開催中」の印が付いているゲーム（`HubEventBadge`）。期間外なら空。
    public static func pinned(
        visibleIDs: [String],
        newIDs: Set<String> = currentVersionIDs,
        eventIDs: Set<String> = []
    ) -> [String] {
        let events = visibleIDs.filter { eventIDs.contains($0) }
        let news = visibleIDs.filter { newIDs.contains($0) && !eventIDs.contains($0) }
        let rest = visibleIDs.filter { !newIDs.contains($0) && !eventIDs.contains($0) }
        return events + news + rest
    }

    /// 長押しメニューの「いちばん上に置く」（#662）が、すでに**表示上**その位置にあるか（#2124）。
    ///
    /// 位置は非表示も含む `orderedIDs` で数える（設定シートの座標）。新着・イベント中のゲームは表示で先頭に
    /// 固定されるため、通常のゲームの前に固定のゲーム（表示中のもの）しか無ければ、すでに「固定の直後」＝
    /// メニューが言う先頭にある。固定されたゲーム自身は、前に何かあれば動かす余地がある。
    /// 前に非表示のゲームがあるときも動かす余地を残す。
    public static func isAlreadyAtTop(
        id: String,
        orderedIDs: [String],
        hiddenIDs: Set<String>,
        newIDs: Set<String> = currentVersionIDs,
        eventIDs: Set<String> = []
    ) -> Bool {
        guard let index = orderedIDs.firstIndex(of: id) else { return true }
        let before = orderedIDs[..<index]
        let pinnedIDs = newIDs.union(eventIDs)
        if pinnedIDs.contains(id) { return before.isEmpty }
        return before.allSatisfy { pinnedIDs.contains($0) && !hiddenIDs.contains($0) }
    }

    /// 「いちばん上に置く」のあとの VoiceOver 案内。新着・イベント中が先頭に固定されているときは、実際の位置を伝える。
    public static func moveToTopAnnouncement(
        title: String,
        id: String,
        orderedIDs: [String],
        hiddenIDs: Set<String>,
        newIDs: Set<String> = currentVersionIDs,
        eventIDs: Set<String> = []
    ) -> String {
        func isPinnedAhead(_ ids: Set<String>) -> Bool {
            !ids.contains(id) && orderedIDs.contains { ids.contains($0) && !hiddenIDs.contains($0) }
        }
        if isPinnedAhead(newIDs) { return tr("「%@」を新着の次に移しました", title) }
        if isPinnedAhead(eventIDs) { return tr("「%@」をイベント開催中のゲームの次に移しました", title) }
        return tr("「%@」を先頭に移しました", title)
    }

    /// ハブ上部の1行。増えたゲームが無ければ nil（行ごと出さない）。
    public static func notice(count: Int) -> String? {
        guard count > 0 else { return nil }
        return tr("新しいあそびが%lld本増えました", count)
    }
}
