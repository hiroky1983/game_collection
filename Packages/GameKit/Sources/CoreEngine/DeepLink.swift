import Foundation

/// アプリのディープリンク（URL スキーム `asobiba`・#2141）を遷移先へ読み替える純粋関数。
///
/// App 内イベント（#1995）の審査で必須のため入れた。形は `asobiba://game/<game_id>` だけで、
/// `asobiba://` 単体や未知・非表示のゲームはハブを開くだけ（遷移しない）。開けるかどうかの判定は
/// 呼び出し側が渡す「いま表示中のゲーム ID」で決める（クイックアクションと同じく、設定で非表示に
/// したゲームは開かない）。`project.yml` の `CFBundleURLTypes` と `scheme` は揃えておくこと。
public enum DeepLink {
    /// `project.yml` の `CFBundleURLSchemes` に登録している値。
    public static let scheme = "asobiba"

    /// ディープリンクで開く先。
    public enum Destination: Equatable, Sendable {
        /// ハブのまま（遷移しない）。
        case hub
        /// そのゲームを開く。
        case game(String)
    }

    /// URL を遷移先に読み替える。自分のスキームでなければ nil。
    ///
    /// - Parameter openableGameIDs: いま開いてよいゲーム ID（表示中のゲーム）。含まれない ID は `.hub`。
    public static func destination(for url: URL, openableGameIDs: Set<String>) -> Destination? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard url.host?.lowercased() == "game" else { return .hub }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 1, let id = components.first, openableGameIDs.contains(id) else {
            return .hub
        }
        return .game(id)
    }
}
