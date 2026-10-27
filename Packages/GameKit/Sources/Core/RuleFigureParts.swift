import SwiftUI

/// 図の中の小さな文字（札の下の名前・矢印の脇の語）。図は固定寸法なので拡大はわずかに留める。
public struct RuleFigureLabel: View {
    private let text: String
    private let color: Color

    public init(_ text: String, color: Color = Theme.inkSubText) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .scaledFont(11, weight: .black, design: .rounded, maxScale: 1.15)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 「できる／できない」の印。色だけに頼らず ○ と ✕ の形でも区別する。
public struct RuleVerdictMark: View {
    private let isOK: Bool

    public init(_ isOK: Bool) {
        self.isOK = isOK
    }

    public var body: some View {
        Image(systemName: isOK ? "checkmark.circle.fill" : "xmark.circle.fill")
            .scaledFont(18, weight: .bold, maxScale: 1.15)
            .foregroundStyle(isOK ? Color(hex: 0x2E9D6B) : Theme.coralText)
    }
}
