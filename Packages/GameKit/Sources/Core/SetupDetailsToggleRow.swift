import SwiftUI

/// 開始シート・設定シートの「くわしい説明」を開閉する行（#3506）。
///
/// 麻雀・しりとり・柵越えおじさん・腰痛おじさんパズルの 4 か所に同じ作りでコピーされ、どれも
/// `lineLimit(1)` で大きい文字だと末尾が切れていた。文字は折り返し可、高さは `minTapTarget` 以上、
/// VoiceOver の開閉状態（`accessibilityValue`）は部品に内蔵する。開閉の動き（`withGameAnimation`）は呼び出し側が
/// `action` で `isOpen` を切り替える形にして、状態は持たない。
public struct SetupDetailsToggleRow: View {
    private let title: String
    private let systemImage: String
    private let isOpen: Bool
    private let action: () -> Void

    public init(title: String, systemImage: String, isOpen: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isOpen = isOpen
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .themeBody(15)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                DisclosureChevron("chevron.down")
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: GameButtonMetrics.minTapTarget, alignment: .leading)
            .popCard(corner: Theme.cornerSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pop)
        .foregroundStyle(Theme.ink)
        .accessibilityValue(isOpen ? tr("開いている") : tr("閉じている"))
    }
}
