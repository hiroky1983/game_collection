import SwiftUI

/// 画面の下や上に短く出す案内の札（白いカード・角 12pt・13pt 文字）。
///
/// ハブの非表示の案内（#662・#2047）から切り出した共通部品で、お気に入りの案内（#3478）もこれを使う。
/// 文言は呼び出し側が同じ文言をアナウンスで流す前提で、VoiceOver からは隠す（二重に読ませない）。
/// 「元に戻す」ボタンだけは VoiceOver で辿れる。
public struct ToastNotice: View {
    /// 「元に戻す」ボタン。
    public struct Undo {
        public let title: String
        public let accessibilityLabel: String
        public let action: () -> Void

        public init(title: String, accessibilityLabel: String, action: @escaping () -> Void) {
            self.title = title
            self.accessibilityLabel = accessibilityLabel
            self.action = action
        }
    }

    public let message: String
    public var undo: Undo?
    /// 支援技術中は自動で消えないため、VoiceOver の「戻る」ジェスチャ（二本指のスクラブ）で閉じられるようにする（#2330）。
    public let onDismiss: () -> Void

    public init(message: String, undo: Undo? = nil, onDismiss: @escaping () -> Void) {
        self.message = message
        self.undo = undo
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .themeCaption(13)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            if let undo {
                Button(action: undo.action) {
                    Text(undo.title)
                        .themeCaption(13)
                        .fontWeight(.bold)
                        .underline()
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pop)
                .accessibilityLabel(undo.accessibilityLabel)
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.vertical, undo == nil ? 12 : 0)
        .popCard(corner: Theme.cornerSmall)
        .padding(Theme.pad)
        .accessibilityAction(.escape, onDismiss)
    }
}
