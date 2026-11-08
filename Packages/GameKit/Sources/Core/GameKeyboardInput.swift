import SwiftUI

/// 外付けキーボード（iPad の Magic Keyboard など）の入力口（#3400）。
///
/// これまでの盤はドラッグでしか動かせず、キーボードだけでは遊べなかった。
/// 矢印キー（と任意でスペース）を盤の操作へつなぐ共通の modifier。指の操作や VoiceOver は変わらない。
public extension View {
    /// 矢印キー（と `onSpace`）を受ける。つないだ向きのキーだけを処理し、つないでいないキーは素通しにする。
    /// 押しっぱなしのリピートも受ける（落ちものの連続移動のため）。
    func gameDirectionKeys(
        onUp: (() -> Void)? = nil,
        onDown: (() -> Void)? = nil,
        onLeft: (() -> Void)? = nil,
        onRight: (() -> Void)? = nil,
        onSpace: (() -> Void)? = nil
    ) -> some View {
        modifier(GameDirectionKeys(onUp: onUp, onDown: onDown, onLeft: onLeft, onRight: onRight, onSpace: onSpace))
    }
}

private struct GameDirectionKeys: ViewModifier {
    let onUp: (() -> Void)?
    let onDown: (() -> Void)?
    let onLeft: (() -> Void)?
    let onRight: (() -> Void)?
    let onSpace: (() -> Void)?

    /// キー入力はフォーカスを持つ View にしか届かないので、現れた時点で自分に当てる。
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            // フォーカスの枠は盤の見た目を変えるので出さない。
            .focusEffectDisabled()
            .onAppear { isFocused = true }
            .onKeyPress(phases: [.down, .repeat]) { press in
                guard let handler = handler(for: press.key) else { return .ignored }
                handler()
                return .handled
            }
    }

    private func handler(for key: KeyEquivalent) -> (() -> Void)? {
        switch key {
        case .upArrow: onUp
        case .downArrow: onDown
        case .leftArrow: onLeft
        case .rightArrow: onRight
        case .space: onSpace
        default: nil
        }
    }
}

extension GameButtonRole {
    /// 段のカプセルに付けるショートカット（#3400）。「待った／戻す」= ⌘Z、ヒント = ⇧⌘H
    /// （⌘H は iPadOS がホームへ戻る操作に使うので避ける）。他の役割には付けない。
    var keyboardShortcut: KeyboardShortcut? {
        switch self {
        case .undo: KeyboardShortcut("z", modifiers: .command)
        case .hint: KeyboardShortcut("h", modifiers: [.command, .shift])
        default: nil
        }
    }
}
