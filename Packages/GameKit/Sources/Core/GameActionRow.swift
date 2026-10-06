import SwiftUI

/// 盤の下の「操作の段」（#1834・#1856。会長決裁 2026-10-06 の案A）。
///
/// 役割の色で塗ったカプセルを**等幅**で横一列に並べ、右端に今までどおりの「⋯」（`GameOverflowBar`）を置く。
/// 2 行目に「あと n 回」（無料の残り）か「▶ 広告を見て」（次の 1 回に広告が要る）を出し、広告の有無を文字で読めるようにする。
/// v1.1.7 で待った・ヒント・戻すを「⋯」に入れたあと広告の入口が押されなくなった（`reward_request` 56→10/日・#1815）ので、
/// **広告が絡む操作だけ**（待った・ヒント・戻す・並べ替え）を段に戻す（会長決裁 2026-10-06 追加）。
/// 広告の無い操作（パス・ジョーカー・配る・メモ・旗モード・投了・諦める・拡大・自動で上がる）は「⋯」に残す。
///
/// - ボタンは 44pt（`GameButtonMetrics.minTapTarget`）。段の高さは各ゲームの今の「⋯」の行と同じで、盤は縮まない。
/// - 押せないときは消さずに薄くする（グレーの面 + 0.55。`GameButtonStyle` の disabled と同じ）。

/// 2 行目の回数・広告の表示（たたき台 6）。
public enum GameActionBadge: Equatable, Sendable {
    /// 残り回数。無料の残り（使い切ると `.ad` に変わる）にも、広告に変わらない回数（スパイダーの「配る」）にも使う。
    case count(Int)
    /// 次の 1 回に広告が要る。上限のあるもの（ナンプレのヒント 3 回・盤ゲームの広告ヒント 5 回）は残りを添える。
    case ad(remaining: Int? = nil)
    case none

    /// 2 行目の文字（▶ のアイコンを除く）。無ければ nil。
    public var text: String? {
        switch self {
        case .count(let n): "あと\(n)回"
        case .ad(let remaining): remaining.map { "あと\($0)回" } ?? "広告を見て"
        case .none: nil
        }
    }

    /// ▶ を添えるか（次の 1 回に広告が要るか）。
    public var needsAd: Bool {
        if case .ad = self { return true }
        return false
    }

    /// 読み上げ。「▶」は文字では読めないので「広告を見て」を必ず含める。
    public var accessibilityValue: String? {
        switch self {
        case .count: text
        case .ad(let remaining): remaining.map { "広告を見て、あと\($0)回" } ?? "広告を見て"
        case .none: nil
        }
    }
}

/// 段に置く 1 つの操作。
public struct GameActionItem: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let role: GameButtonRole
    public let badge: GameActionBadge
    /// 2 行目の先頭に添える短い一言（神経衰弱の「今だけ！」）。「⋯」の行の左端にあった表示だけの文字のうち、
    /// そのボタン自身の状態を知らせるものの置き場所（段のボタンの幅を変えずに出せる）。
    public let note: String?
    public let isEnabled: Bool
    /// 読み上げ。渡した文字に 2 行目の内容（残り回数・広告）まで含めること（渡すと 2 行目は読み上げに足さない。
    /// 「1手戻す、残り3回」のあとに「あと3回」を重ねて読まないため）。nil なら題と 2 行目をそのまま読む。
    public let accessibilityLabel: String?
    public let accessibilityHint: String?
    public let action: () -> Void

    public init(
        id: String,
        title: String,
        systemImage: String,
        role: GameButtonRole,
        badge: GameActionBadge = .none,
        note: String? = nil,
        isEnabled: Bool = true,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.badge = badge
        self.note = note
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
    }
}

/// 段のカプセル 1 つ。
struct GameActionCapsule: View {
    let item: GameActionItem
    /// ヒントの促し（#1424）。段にヒントがあるときは吹き出しではなく、ヒントのカプセルを光らせて指す。
    @Environment(\.hintNudgeIsShowing) private var isNudging
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glows: Bool { item.role == .hint && item.isEnabled && isNudging }

    var body: some View {
        Button(action: item.action) {
            label
        }
        .buttonStyle(GameActionCapsuleStyle(role: item.role))
        .disabled(!item.isEnabled)
        .hintNudgeGlow(glows, reduceMotion: reduceMotion)
        .accessibilityLabel(item.accessibilityLabel ?? item.title)
        .accessibilityHint(item.accessibilityHint ?? "")
        .accessibilityValue(accessibilityValue)
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: item.systemImage)
                .font(.system(size: 16, weight: .bold))
            VStack(alignment: .leading, spacing: -1) {
                Text(item.title).themeBody(14, weight: .bold, maxScale: 1.3)
                secondLine
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// 2 行目: 一言（note）→ ▶ → 回数。どれも無ければ出さない（1 行目だけが縦に中央へ寄る）。
    @ViewBuilder private var secondLine: some View {
        if item.note != nil || item.badge != .none {
            HStack(spacing: 2) {
                if let note = item.note {
                    Text(note)
                }
                if item.badge.needsAd {
                    Image(systemName: "play.rectangle.fill").font(.system(size: 9))
                }
                if let text = item.badge.text {
                    Text(text)
                }
            }
            .themeCaption(10, maxScale: 1.3)
            .opacity(0.85)
        }
    }

    /// 2 行目の読み上げ。専用の読み上げ文（残り回数まで含む）を渡された項目では重ねて読まない。
    private var accessibilityValue: String {
        guard item.accessibilityLabel == nil else { return "" }
        return [item.note, item.badge.accessibilityValue].compactMap { $0 }.joined(separator: "、")
    }
}

/// カプセルの見た目（`GameButtonStyle.capsule` の延長。等幅・44pt）。
struct GameActionCapsuleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let role: GameButtonRole

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? role.foreground : Color.white)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: GameButtonMetrics.minTapTarget)
            .background(Capsule().fill(isEnabled ? role.fill : Theme.fillMuted))
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.55)
    }
}
