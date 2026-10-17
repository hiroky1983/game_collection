import SwiftUI

/// 盤ゲームで CPU が着手したことを VoiceOver に 1 回だけ伝える（#2280）。
///
/// 盤は図形の集まりなので、CPU の着手は「直前の手」の印を探りに行かないと分からない。
/// モデルは CPU が着手した直後の `aiTurnKey` を `cpuMoveKey` に控え、View は `aiTurnKey` が
/// 変わったとき、その値が `cpuMoveKey` と一致する場合にだけ読み上げる。
/// 人間の着手・待った・新規対局は `cpuMoveKey` と一致しないので鳴らない。
public enum CPUMoveAnnouncement {
    /// `key` が CPU の着手で動いた鍵なら、読み上げ文を返す。そうでなければ nil。
    public static func text(key: AITurnKey, cpuMoveKey: AITurnKey?, message: () -> String?) -> String? {
        guard let cpuMoveKey, cpuMoveKey == key else { return nil }
        return message()
    }
}

private struct CPUMoveAnnouncementModifier: ViewModifier {
    let key: AITurnKey
    let cpuMoveKey: AITurnKey?
    let message: () -> String?

    func body(content: Content) -> some View {
        content.onChange(of: key) { _, newKey in
            if let text = CPUMoveAnnouncement.text(key: newKey, cpuMoveKey: cpuMoveKey, message: message) {
                AccessibilityNotification.Announcement(text).post()
            }
        }
    }
}

public extension View {
    /// CPU の着手で `key` が変わったときに `message()` を VoiceOver へ 1 回読み上げる。
    func cpuMoveAnnouncement(key: AITurnKey, cpuMoveKey: AITurnKey?, message: @escaping () -> String?) -> some View {
        modifier(CPUMoveAnnouncementModifier(key: key, cpuMoveKey: cpuMoveKey, message: message))
    }
}
