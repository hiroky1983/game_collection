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

// MARK: - カードゲーム向け（#3424）

/// カードゲームで CPU が札を出した・引いたことを VoiceOver に伝える 1 件分（#3424）。
///
/// 盤ゲームの `aiTurnKey` の突き合わせ（上）は手数が 1 本の数列になる盤ゲーム向け。
/// カードゲームは手番の進み方がゲームごとに違うので、モデルが CPU の動きのたびに `serial` を
/// 進めて文面を控え、View は `serial` が変わったときだけ読み上げる。人間の操作・新規対局では
/// モデルが控えを書かない（または nil に戻す）ので鳴らない。
public struct CPUEventAnnouncement: Equatable, Sendable {
    public let serial: Int
    public let text: String

    public init(serial: Int, text: String) {
        self.serial = serial
        self.text = text
    }

    /// 前回の控えの次の番号で、新しい控えを作る。
    public static func next(after previous: CPUEventAnnouncement?, text: String) -> CPUEventAnnouncement {
        CPUEventAnnouncement(serial: (previous?.serial ?? 0) + 1, text: text)
    }
}

private struct CPUEventAnnouncementModifier: ViewModifier {
    let event: CPUEventAnnouncement?
    let throttle: Duration?
    /// 間引き待ちのあいだに溜まった最新の 1 件。待ち終えたら読み上げて空にする。
    @State private var pending: CPUEventAnnouncement?
    @State private var throttleTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: event) { _, new in
                guard let new else { return }
                guard let throttle else {
                    AccessibilityNotification.Announcement(new.text).post()
                    return
                }
                // 間引き: 待ちの最中に来た分は最後の 1 件だけ残し、待ち終えたときに読む。
                pending = new
                guard throttleTask == nil else { return }
                throttleTask = Task { @MainActor in
                    try? await Task.sleep(for: throttle)
                    guard !Task.isCancelled else { return }
                    if let latest = pending { AccessibilityNotification.Announcement(latest.text).post() }
                    pending = nil
                    throttleTask = nil
                }
            }
            .onDisappear {
                throttleTask?.cancel()
                throttleTask = nil
                pending = nil
            }
    }
}

public extension View {
    /// CPU の動きの控え（`event`）が新しくなるたびに、その文面を VoiceOver へ読み上げる（#3424）。
    ///
    /// `throttle` を渡すと、その間隔に 1 回だけ最新の 1 件を読む（スピード・麻雀のように動きが速く、
    /// 全部読むと次の読み上げに遮られて何も聞こえなくなるゲーム向け）。nil なら 1 件ずつ即座に読む。
    func cpuEventAnnouncement(_ event: CPUEventAnnouncement?, throttle: Duration? = nil) -> some View {
        modifier(CPUEventAnnouncementModifier(event: event, throttle: throttle))
    }
}
