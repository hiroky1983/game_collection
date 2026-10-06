import Foundation

/// ホーム画面アイコン長押し（Quick Actions・#1642）に出す項目を決める純粋関数。
///
/// 並びと件数の規則は `RecentGames`（ハブ最上部の「つづき・最近」行）をそのまま使う。
/// **この機能のために新しく保存するものは無い**（項目は OS 側が保持するが、中身は
/// 中断データと `PlayLog` から毎回組み立て直す）。`UIApplicationShortcutItem` は UIKit なので、
/// ここでは種別の文字列・タイトル・補足だけを返し、変換は App ターゲットが行う。
public enum QuickActions {
    /// 項目の種別の接頭辞。後ろにゲーム ID が続く。
    public static let typePrefix = "quickaction.open."

    /// 1 項目ぶん。
    public struct Item: Equatable, Sendable {
        /// `UIApplicationShortcutItem.type` に入れる値。
        public let type: String
        public let gameID: String
        public let title: String
        /// 中断データがあるときだけ「続きから」。無ければ nil（記録だけの最近遊んだゲーム）。
        public let subtitle: String?
    }

    /// 項目を並び順で返す。**空配列なら項目を出さない**（記録ゼロ・全部非表示）。
    ///
    /// - Parameters:
    ///   - candidates: `RecentGames.candidates` の結果。非表示のゲームはそちらで既に除かれている。
    ///   - title: ゲーム名。登録外・対象外のゲームは nil を返すと項目から外れる。
    public static func items(
        candidates: [RecentGames.Candidate],
        title: (String) -> String?
    ) -> [Item] {
        candidates.compactMap { candidate in
            guard let name = title(candidate.gameID) else { return nil }
            return Item(
                type: typePrefix + candidate.gameID,
                gameID: candidate.gameID,
                title: name,
                subtitle: candidate.hasResume ? "続きから" : nil
            )
        }
        .prefix(RecentGames.maxCount)
        .map { $0 }
    }

    /// 項目の種別からゲーム ID を取り出す。自分の項目でなければ nil。
    public static func gameID(fromType type: String) -> String? {
        guard type.hasPrefix(typePrefix) else { return nil }
        let id = String(type.dropFirst(typePrefix.count))
        return id.isEmpty ? nil : id
    }
}
