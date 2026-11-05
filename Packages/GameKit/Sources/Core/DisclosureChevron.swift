import SwiftUI

/// ボタンの行末に置く飾りのシェブロン（`chevron.right` / `chevron.down`）。
///
/// 開閉や遷移の意味はボタン名と状態で伝わるので、VoiceOver にはシンボル名を読ませない（#3053）。
/// 読み上げから隠すのを忘れないよう、行末のシェブロンはこの部品で描く。
public struct DisclosureChevron: View {
    private let systemName: String
    private let size: CGFloat
    private let weight: Font.Weight
    private let tint: Color?

    /// - Parameter tint: nil なら親の `foregroundStyle` を引き継ぐ（塗りの上に載せる行用）。
    public init(
        _ systemName: String = "chevron.right",
        size: CGFloat = 13,
        weight: Font.Weight = .bold,
        tint: Color? = Theme.inkSubText
    ) {
        self.systemName = systemName
        self.size = size
        self.weight = weight
        self.tint = tint
    }

    public var body: some View {
        Group {
            if let tint {
                Image(systemName: systemName).scaledFont(size, weight: weight).foregroundStyle(tint)
            } else {
                Image(systemName: systemName).scaledFont(size, weight: weight)
            }
        }
        .accessibilityHidden(true)
    }
}
