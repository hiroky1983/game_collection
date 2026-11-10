import SwiftUI

// MARK: - 開始シートの「段を選ぶ」共通部品（#3363）

/// `SetupStepSelector` の選択肢 1 つ。
public struct SetupStepOption<Value: Hashable>: Identifiable {
    public var id: Value { value }
    public let value: Value
    public let title: String
    /// 一言の説明（1 行に収まる長さ）。空なら出さない。
    public let detail: String
    /// 段の面色。文字は `Theme.onAccent` を載せる（`DifficultyTile` / `CPUStrength.accent` の色を引き継ぐ）。
    public let accent: Color

    public init(value: Value, title: String, detail: String = "", accent: Color) {
        self.value = value
        self.title = title
        self.detail = detail
        self.accent = accent
    }
}

/// 難易度・CPU の強さ・盤の大きさ・置き石・手合い・レベルなど、**段が増えうる項目**を選ぶ共通部品。
///
/// 選んでいる値を 1 つだけ大きく出し、左右の ‹ › で 1 段ずつ動かす（左右スワイプでも動く）。
/// 値をタップすると全選択肢の一覧が開き、直接選べる（30 段でも使える）。
/// 端の段では、その側の矢印を薄くする（消さない・位置を動かさない）。
///
/// **大きさは選択肢の数・言語・文字サイズで変わらない**（値の面は固定の高さ。文字は縮めず折り返す）。
/// 順番のある項目は値の下に目盛り（バー＋「3 / 5」）を出す。
public struct SetupStepSelector<Value: Hashable>: View {
    private let options: [SetupStepOption<Value>]
    private let showsScale: Bool
    @Binding private var selection: Value
    @State private var showsList = false
    /// 値の面の高さ。文字サイズに比例させるだけで、選択肢の数や中身には依存させない。
    @ScaledMetric(relativeTo: .body) private var faceHeight: CGFloat = 92

    public init(options: [SetupStepOption<Value>], selection: Binding<Value>, showsScale: Bool = true) {
        self.options = options
        self.showsScale = showsScale
        _selection = selection
    }

    private var index: Int { options.firstIndex { $0.value == selection } ?? 0 }
    private var current: SetupStepOption<Value>? { options.indices.contains(index) ? options[index] : nil }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                arrow(systemName: "chevron.left", label: tr("ひとつ前"), enabled: index > 0) { move(-1) }
                face
                arrow(systemName: "chevron.right", label: tr("ひとつ次"), enabled: index < options.count - 1) { move(1) }
            }
            scale
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current.map { $0.title + ($0.detail.isEmpty ? "" : tr("、") + $0.detail) } ?? "")
        .accessibilityValue(tr("%lld / %lld", index + 1, options.count))
        .accessibilityHint(tr("上下にスワイプして変更します"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(1)
            case .decrement: move(-1)
            @unknown default: break
            }
        }
        .accessibilityAction(named: tr("一覧から選ぶ")) { showsList = true }
        .onAppear {
            // 選択肢に無い値が渡されたときは、表示している先頭の段に揃える（開始ボタンが別の値で始めないため）。
            if let first = options.first, !options.contains(where: { $0.value == selection }) { selection = first.value }
        }
        .sheet(isPresented: $showsList) {
            SetupStepList(options: options, selection: $selection) { showsList = false }
        }
    }

    private func move(_ delta: Int) {
        let next = index + delta
        guard options.indices.contains(next) else { return }
        selection = options[next].value
    }

    private func arrow(systemName: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .scaledFont(20, weight: .bold, maxScale: 1.2)
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pop)
        .opacity(enabled ? 1 : 0.25)
        .disabled(!enabled)
        .accessibilityHidden(true)
        .accessibilityLabel(label)
    }

    private var face: some View {
        Button { showsList = true } label: {
            VStack(spacing: 4) {
                Text(current?.title ?? "")
                    .themeTitle(22)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let detail = current?.detail, !detail.isEmpty {
                    Text(detail)
                        .themeBody(13)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: faceHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(current?.accent ?? Theme.surface)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            )
        }
        .buttonStyle(.pop)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                move(value.translation.width < 0 ? 1 : -1)
            }
        )
    }

    /// 目盛り（バー＋「3 / 5」）。段が 1 つ以下のときは出さず、高さは常に同じだけ確保する。
    private var scale: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                let fraction = options.count > 1 ? CGFloat(index) / CGFloat(options.count - 1) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.inkSubText.opacity(0.25))
                    Capsule().fill(current?.accent ?? Theme.inkSubText)
                        .frame(width: max(8, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            Text(tr("%lld / %lld", index + 1, options.count))
                .themeBody(13)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSubText)
                .lineLimit(1)
                .frame(minWidth: 64, alignment: .trailing) // 段の数で目盛りの長さが変わらないよう幅を確保
        }
        .padding(.horizontal, 52) // 矢印（44pt + 間隔 8pt）と左右を揃える
        .frame(height: 20)
        .opacity(showsScale && options.count > 1 ? 1 : 0)
    }
}

/// 全選択肢の一覧（今の段が中央・印付き）。
private struct SetupStepList<Value: Hashable>: View {
    let options: [SetupStepOption<Value>]
    @Binding var selection: Value
    let close: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(options) { option in
                        row(option).id(option.value)
                    }
                }
                .padding(Theme.pad)
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
        .popBackground()
        .presentationDetents([.large])
    }

    private func row(_ option: SetupStepOption<Value>) -> some View {
        let selected = option.value == selection
        return Button { // a11y-ok: 行全体が minHeight 44 の面で、14pt は飾りの丸だけ
            selection = option.value
            close()
        } label: {
            HStack(spacing: 10) {
                Circle().fill(option.accent).frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).themeBody(17).foregroundStyle(Theme.ink)
                    if !option.detail.isEmpty {
                        Text(option.detail).themeBody(13, weight: .regular).foregroundStyle(Theme.inkSubText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark").scaledFont(16, weight: .bold, maxScale: 1.2)
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(selected ? option.accent.opacity(0.35) : Theme.surface)
            )
        }
        .buttonStyle(.pop)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

public extension SetupStepSelector {
    /// やさしい順に並んだ段を、`DifficultyTile` と同じ色の並びで出す（難易度・モード・レベルなど）。
    init(ladder steps: [(value: Value, title: String, detail: String)], selection: Binding<Value>, showsScale: Bool = true) {
        self.init(
            options: steps.enumerated().map { step, item in
                SetupStepOption(value: item.value, title: item.title, detail: item.detail,
                                accent: DifficultyTile.accent(step: step, of: steps.count))
            },
            selection: selection, showsScale: showsScale)
    }
}
