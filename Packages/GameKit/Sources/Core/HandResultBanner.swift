import SwiftUI

/// 1 ハンドの決着（ポーカー・ブラックジャック共通・#1754）。
///
/// 勝敗を卓の中央に大きく出すための表示用の値。**判定そのものは各ゲームの Model が持ち**、
/// ここには「何と書くか」だけを渡す（バッジの 12〜13pt では決着が見落とされるため）。
public struct HandResult: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case win, lose, draw }
    /// 増減の単位。チップを賭けるゲームは枚、勝ち点を競うゲーム（ブラックジャック・ポーカー）は点（#2702）。
    public enum Unit: Equatable, Sendable { case chips, points }

    public let kind: Kind
    /// 大見出し（例: "勝ち！"）。
    public let headline: String
    /// 理由 1 行（例: "ツーペア 対 ワンペア" / "バスト（24）"）。
    public let reason: String
    /// このハンドでの手持ちチップの増減。取れないとき（旧い中断データから戻った局）は nil で行ごと出さない。
    public let chipDelta: Int?
    /// `chipDelta` の単位。
    public let unit: Unit
    /// VoiceOver で勝敗として読む文。見出しと違い「勝ちです」のように文にする。
    public let spokenResult: String
    /// 強い役で勝ったときの強調（#2593）。拡大・きらめきと役名（`reason`）の強調に使う。既定は無し。
    public let isEmphasized: Bool

    public init(kind: Kind, headline: String, reason: String, chipDelta: Int?, unit: Unit = .chips,
                spokenResult: String, isEmphasized: Bool = false) {
        self.kind = kind
        self.headline = headline
        self.reason = reason
        self.chipDelta = chipDelta
        self.unit = unit
        self.spokenResult = spokenResult
        self.isEmphasized = isEmphasized && kind == .win
    }

    /// 増減の表示（例: "+40枚" / "−20枚" / "±0枚"）。数値の桁区切りを避けるため文字列で組む。
    public var chipText: String? {
        guard let delta = chipDelta else { return nil }
        switch unit {
        case .chips:
            if delta > 0 { return tr("+%lld枚", delta) }
            if delta < 0 { return tr("−%lld枚", -delta) }
            return tr("±0枚")
        case .points:
            if delta > 0 { return tr("+%lld点", delta) }
            if delta < 0 { return tr("−%lld点", -delta) }
            return tr("±0点")
        }
    }

    /// 読み上げ全文。「勝ちです。ツーペア 対 ワンペア。チップ 40枚増えました」。
    public var spokenText: String {
        var parts = [spokenResult]
        if !reason.isEmpty { parts.append(reason) }
        if let delta = chipDelta {
            switch unit {
            case .chips:
                if delta > 0 { parts.append(tr("チップが%lld枚増えました", delta)) }
                else if delta < 0 { parts.append(tr("チップが%lld枚減りました", -delta)) }
                else { parts.append(tr("チップの増減はありません")) }
            case .points:
                if delta > 0 { parts.append(tr("%lld点入りました", delta)) }
                else if delta < 0 { parts.append(tr("%lld点減りました", -delta)) }
                else { parts.append(tr("点の増減はありません")) }
            }
        }
        return parts.joined(separator: tr("。"))
    }
}

/// 卓の中央に出す大きな勝敗表示。操作は受けない（`allowsHitTesting(false)`）。
public struct HandResultBanner: View {
    private let result: HandResult
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsed = false

    public init(_ result: HandResult) {
        self.result = result
    }

    private var fill: Color {
        // 強い役の勝ちは色でも分かるように黄に替える。Reduce Motion ではこの色と枠の太さだけが強調になる。
        if result.isEmphasized { return Theme.Fill.yellow }
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

    /// 四隅のきらめき。動くのは強調された勝ち、かつ Reduce Motion オフのときだけ。
    @ViewBuilder
    private var sparkles: some View {
        if result.isEmphasized && !reduceMotion {
            GeometryReader { geo in
                ForEach(Array(Self.sparkleSpots.enumerated()), id: \.offset) { index, spot in
                    Image(systemName: "sparkle")
                        .font(.system(size: spot.size, weight: .black)) // fixed-size: 装飾のきらめき（文字ではない）
                        .foregroundStyle(Theme.ink)
                        .opacity(pulsed ? 1 : 0.15)
                        .scaleEffect(pulsed ? 1 : 0.4)
                        .animation(.easeInOut(duration: 0.45).repeatCount(4, autoreverses: true)
                            .delay(Double(index) * 0.12), value: pulsed)
                        .position(x: geo.size.width * spot.x, y: geo.size.height * spot.y)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private static let sparkleSpots: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.04, 0.0, 16), (0.96, 0.05, 20), (0.1, 1.0, 18), (0.93, 0.98, 14),
    ]

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
                    .themeCaption(result.isEmphasized ? 15 : 13, weight: result.isEmphasized ? .black : .bold, maxScale: 1.5)
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
                .strokeBorder(Theme.ink.opacity(0.85), lineWidth: result.isEmphasized ? 3 : 2)
        )
        .overlay { sparkles }
        .scaleEffect(result.isEmphasized && !reduceMotion && pulsed ? 1.06 : 1)
        .onAppear {
            guard result.isEmphasized, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatCount(3, autoreverses: true)) { pulsed = true }
        }
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
