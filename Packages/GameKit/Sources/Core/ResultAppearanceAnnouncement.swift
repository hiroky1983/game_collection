import SwiftUI

/// 終局・クリアのカードが出たことを VoiceOver に 1 回だけ伝える（#2232）。
///
/// `.isModal` だけでは「出た」ことが読み上げられず、フォーカスも背後の盤に残る。
/// `ScreenChanged` に既存のラベルを渡して、読み上げとフォーカス移動を一度に済ませる。
public enum ResultAppearanceAnnouncement {
    /// `announced` が偽のときだけ `post` を呼び、真に立てる。再描画で `onAppear` が重なっても二重に鳴らさない。
    public static func announceOnce(label: String, announced: inout Bool,
                                    post: (String) -> Void = { AccessibilityNotification.ScreenChanged($0).post() }) {
        guard !announced else { return }
        announced = true
        post(label)
    }
}

private struct ResultAppearanceAnnouncementModifier: ViewModifier {
    let label: String
    @State private var announced = false

    func body(content: Content) -> some View {
        content.onAppear {
            ResultAppearanceAnnouncement.announceOnce(label: label, announced: &announced)
        }
    }
}

public extension View {
    /// 出現した時点で `label` を VoiceOver に 1 回だけ告げる。出入りする枝（`if` の中）に付けること。
    func announcesResultAppearance(_ label: String) -> some View {
        modifier(ResultAppearanceAnnouncementModifier(label: label))
    }
}
