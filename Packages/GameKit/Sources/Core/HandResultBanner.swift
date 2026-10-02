import SwiftUI

/// 1 ハンドの決着（ポーカー・ブラックジャック共通・#1754）。
///
/// 勝敗を卓の中央に大きく出すための表示用の値。**判定そのものは各ゲームの Model が持ち**、
/// ここには「何と書くか」だけを渡す（バッジの 12〜13pt では決着が見落とされるため）。
public struct HandResult: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case win, lose, draw }

    public let kind: Kind
    /// 大見出し（例: "勝ち！"）。
    public let headline: String
    /// 理由 1 行（例: "ツーペア 対 ワンペア" / "バスト（24）"）。
    public let reason: String
    /// このハンドでの手持ちチップの増減。取れないとき（旧い中断データから戻った局）は nil で行ごと出さない。
    public let chipDelta: Int?
    /// VoiceOver で勝敗として読む文。見出しと違い「勝ちです」のように文にする。
    public let spokenResult: String

    public init(kind: Kind, headline: String, reason: String, chipDelta: Int?, spokenResult: String) {
        self.kind = kind
        self.headline = headline
        self.reason = reason
        self.chipDelta = chipDelta
        self.spokenResult = spokenResult
    }

    /// 増減の表示（例: "+40枚" / "−20枚" / "±0枚"）。数値の桁区切りを避けるため文字列で組む。
    public var chipText: String? {
        guard let delta = chipDelta else { return nil }
        if delta > 0 { return "+\(delta)枚" }
        if delta < 0 { return "−\(-delta)枚" }
        return "±0枚"
    }

    /// 読み上げ全文。「勝ちです。ツーペア 対 ワンペア。チップ 40枚増えました」。
    public var spokenText: String {
        var parts = [spokenResult]
        if !reason.isEmpty { parts.append(reason) }
        if let delta = chipDelta {
            if delta > 0 { parts.append("チップが\(delta)枚増えました") }
            else if delta < 0 { parts.append("チップが\(-delta)枚減りました") }
            else { parts.append("チップの増減はありません") }
        }
        return parts.joined(separator: "。")
    }
}

/// 卓の中央に出す大きな勝敗表示。操作は受けない（`allowsHitTesting(false)`）。
public struct HandResultBanner: View {
    private let result: HandResult

    public init(_ result: HandResult) {
        self.result = result
    }

    private var fill: Color {
        switch result.kind {
        case .win:  return Theme.Fill.teal
        case .lose: return Theme.Fill.coral
        case .draw: return Theme.fillMuted
        }
    }

    private var textColor: Color { result.kind == .draw ? .white : Theme.onAccent }

    private var headline: some View {
        Text(result.headline)
            .themeTitle(32, weight: .black, maxScale: 1.4)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private var chips: some View {
        if let text = result.chipText {
            Text(verbatim: text)
                .themeBody(24, weight: .black, maxScale: 1.4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    public var body: some View {
        VStack(spacing: 2) {
            // 見出しと増減は 1 行に並べて高さを抑える（卓の中央に重ねるので、手札を覆う面積を減らしたい）。
            // 文字が大きくなったら縦に積み替える。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) { headline; chips }
                VStack(spacing: 0) { headline; chips }
            }
            if !result.reason.isEmpty {
                Text(result.reason)
                    .themeCaption(13, weight: .bold, maxScale: 1.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .frame(maxWidth: 320)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(fill))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Theme.ink.opacity(0.85), lineWidth: 2)
        )
        .shadow(color: Theme.cardShadow, radius: 10, y: 4)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.spokenText)
    }
}

public extension View {
    /// 1 ハンドの決着を、この View の中央に大きく重ねる（#1754）。
    ///
    /// - `result` が非 nil になったら `appearDelay` 待って出し、一定時間で自動的に消える。
    ///   `nil`（次のハンドが始まった）になれば即座に消える。操作は一切奪わない。
    /// - 出る瞬間に VoiceOver へ勝敗を読み上げる（バナーは消えるので、読み上げが本体）。
    /// - 同じ `result` が続けて来ても、間に `nil` を挟むので毎回出る。
    func handResultOverlay(_ result: HandResult?, appearDelay: Duration = .zero) -> some View {
        modifier(HandResultOverlay(result: result, appearDelay: appearDelay))
    }
}

private struct HandResultOverlay: ViewModifier {
    /// 出しっぱなしにしない。次のハンドの操作を待たせず、テンポを落とさない長さ。
    static let displayDuration: Duration = .milliseconds(2600)

    let result: HandResult?
    let appearDelay: Duration
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if isVisible, let result {
                        HandResultBanner(result)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
                .allowsHitTesting(false)
                .gameAnimation(.spring(response: 0.3, dampingFraction: 0.75), value: isVisible)
            }
            .task(id: result) {
                isVisible = false
                guard let result else { return }
                if appearDelay > .zero {
                    try? await Task.sleep(for: appearDelay)
                    guard !Task.isCancelled else { return }
                }
                isVisible = true
                AccessibilityNotification.Announcement(result.spokenText).post()
                #if DEBUG
                // 撮影用（#1754）: バナーを消さずに残す。自動で消えると撮影のタイミングが合わない。
                if ProcessInfo.processInfo.arguments.contains("-handResultHold") { return }
                #endif
                try? await Task.sleep(for: Self.displayDuration)
                guard !Task.isCancelled else { return }
                isVisible = false
            }
    }
}
