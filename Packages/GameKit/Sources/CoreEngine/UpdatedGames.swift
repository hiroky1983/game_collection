import Foundation

/// 既存のゲームに中身が増えたことを知らせるタグの種類（#2790）。文言は種類ごとに持つ。
public enum UpdateTag: String, Sendable, CaseIterable {
    /// 新しいステージが入った。
    case newStage

    /// 表示中の言語の文言。
    public var label: String {
        switch self {
        case .newStage: tr("新ステージ追加")
        }
    }
}

/// 「その版で中身が増えたゲーム」の一覧（#2790）。ハブのタイルに NEW・イベントと同じ部品でタグを出す。
///
/// 新作の NEW（`NewGames.currentVersionIDs`）と同じ考え方で、**版を上げるときにここを書き換えるだけ**で
/// 付け外しできる。次の版で空にすれば消える。並び順には影響しない（NEW のように先頭へ固定しない）。
public enum UpdatedGames {
    /// この版のタグ。v1.1.15: チャリンコおじさん（`runner`）に世界 8・9（43〜54 面）が入る。
    public static let currentVersion: [String: UpdateTag] = ["runner": .newStage]

    /// ゲームに付けるタグ。一覧に無ければ nil。
    public static func tag(for gameID: String, in table: [String: UpdateTag] = currentVersion) -> UpdateTag? {
        table[gameID]
    }
}
