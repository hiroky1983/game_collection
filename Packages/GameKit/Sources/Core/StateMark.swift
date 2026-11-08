import SwiftUI

/// 「色以外で区別」（`accessibilityDifferentiateWithoutColor`）が ON のときだけ、色で示している状態に
/// 記号や枠線を重ねる共通部品（#3415。ナンプレ #2405・将棋とチェス #2486 の個別対応を寄せたもの）。
/// OFF のときは何も描かないので、見た目・レイアウトは従来のまま。
public enum StateMark {
    /// 印を出すか。環境値の読みと `active` の掛け合わせを 1 か所に集める（テストはここを固定する）。
    public static func isVisible(active: Bool, differentiateWithoutColor: Bool) -> Bool {
        active && differentiateWithoutColor
    }
}

private struct StateMarkModifier<Mark: View>: ViewModifier {
    let active: Bool
    let alignment: Alignment
    let mark: Mark
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    func body(content: Content) -> some View {
        content.overlay(alignment: alignment) {
            if StateMark.isVisible(active: active, differentiateWithoutColor: differentiateWithoutColor) {
                mark
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// `active` かつ「色以外で区別」が ON のときだけ、`mark` を重ねる。印は当たり判定にも
    /// VoiceOver にも影響しない（状態の読み上げは呼び出し側の accessibilityLabel が持つ）。
    public func stateMark<Mark: View>(
        active: Bool = true,
        alignment: Alignment = .center,
        @ViewBuilder _ mark: () -> Mark
    ) -> some View {
        modifier(StateMarkModifier(active: active, alignment: alignment, mark: mark()))
    }
}

/// 行の中に差し込む記号つきの印（レイアウトに場所を取りたいとき用）。OFF のときは何も出ない。
public struct StateSymbolLabel: View {
    let active: Bool
    let symbol: String
    let text: String
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    public init(active: Bool, symbol: String, text: String) {
        self.active = active
        self.symbol = symbol
        self.text = text
    }

    public var body: some View {
        if StateMark.isVisible(active: active, differentiateWithoutColor: differentiateWithoutColor) {
            HStack(spacing: 2) {
                Image(systemName: symbol)
                Text(text)
            }
            .scaledFont(10, weight: .heavy, design: .rounded, maxScale: 1.15)
            .foregroundStyle(Theme.coralText)
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
        }
    }
}
