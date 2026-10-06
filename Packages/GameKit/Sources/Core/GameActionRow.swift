import SwiftUI

/// 操作の段（#1834・案A の試作）。役割の色で塗ったカプセルを等幅で並べ、右端に今の「⋯」。
///
/// 2 行目に「あと n 回」（無料の残り）か「▶ 広告を見て」（次の 1 回に広告が要る）を出す。
/// 見た目は `docs/design/action-row/mock.swift` の `RowA` を写したもの。

/// 回数・広告の見せ方（たたき台 6）。
public enum GameActionBadge: Equatable, Sendable {
    /// 無料の残り回数。使い切ると広告（`.ad`）に変わる操作に使う。
    case free(Int)
    /// 残り回数の表示だけ（広告に変わらない。スパイダーの「配る」）。
    case count(Int)
    /// 次の 1 回に広告が要る。
    case ad
    case none
}

/// 段に置く 1 つの操作。
public struct GameActionItem: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let role: GameButtonRole
    public let badge: GameActionBadge
    public let isEnabled: Bool
    /// チェック付きの切り替え（メモ・旗モード）の現在の状態。nil なら普通の操作。
    public let isOn: Bool?
    public let accessibilityLabel: String?
    public let accessibilityHint: String?
    public let action: () -> Void

    public init(
        id: String,
        title: String,
        systemImage: String,
        role: GameButtonRole,
        badge: GameActionBadge = .none,
        isEnabled: Bool = true,
        isOn: Bool? = nil,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.badge = badge
        self.isEnabled = isEnabled
        self.isOn = isOn
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    /// 「⋯」の項目をそのまま段に出す（囲碁のパスなど）。役割は見送り（グレー）。
    public init(menuItem: GameControlMenuItem, role: GameButtonRole = .skip, badge: GameActionBadge = .none) {
        self.init(
            id: menuItem.id, title: menuItem.title, systemImage: menuItem.systemImage, role: role,
            badge: badge, isEnabled: menuItem.isEnabled, isOn: menuItem.isChecked,
            accessibilityLabel: menuItem.accessibilityLabel, accessibilityHint: menuItem.accessibilityHint,
            action: menuItem.action
        )
    }
}

/// 試作の確認用の起動引数（試作ブランチ限り）。
///
/// - `-actionRowWorstCase`: 文字が最も長い状態（無料を使い切って「▶ 広告を見て」）を、押せる見た目で描く。
///   はみ出し・切れの確認用。モデルの状態は変えない（ボタン自体は本来の有効／無効のまま）。
public enum GameActionRowPreview {
    public static let isWorstCase = ProcessInfo.processInfo.arguments.contains("-actionRowWorstCase")
}

/// 段のカプセル 1 つ。
struct GameActionCapsule: View {
    let item: GameActionItem

    private var badge: GameActionBadge {
        if GameActionRowPreview.isWorstCase, case .free = item.badge { return .ad }
        return item.badge
    }

    private var looksEnabled: Bool { item.isEnabled || GameActionRowPreview.isWorstCase }

    var body: some View {
        Button(action: item.action) {
            label
        }
        .buttonStyle(GameActionCapsuleStyle(role: item.role, isOn: item.isOn, looksEnabled: looksEnabled))
        .disabled(!item.isEnabled)
        .accessibilityLabel(item.accessibilityLabel ?? item.title)
        .accessibilityHint(item.accessibilityHint ?? "")
        .accessibilityValue(accessibilityValue)
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: item.isOn == true ? "checkmark.circle.fill" : item.systemImage)
                .font(.system(size: 16, weight: .bold))
            VStack(alignment: .leading, spacing: -1) {
                Text(item.title).themeBody(14, weight: .bold, maxScale: 1.3)
                badgeText
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    @ViewBuilder private var badgeText: some View {
        switch badge {
        case .free(let n), .count(let n):
            Text("あと\(n)回").themeCaption(10, maxScale: 1.3).opacity(0.85)
        case .ad:
            HStack(spacing: 2) {
                Image(systemName: "play.rectangle.fill").font(.system(size: 9))
                Text("広告を見て").themeCaption(10, maxScale: 1.3)
            }
            .opacity(0.9)
        case .none:
            EmptyView()
        }
    }

    private var accessibilityValue: String {
        switch badge {
        case .free(let n), .count(let n): "あと\(n)回"
        case .ad: "広告を見て"
        case .none: ""
        }
    }
}

/// カプセルの見た目（`GameButtonStyle.capsule` の延長。等幅・44pt・切り替えのオン／オフ）。
struct GameActionCapsuleStyle: ButtonStyle {
    let role: GameButtonRole
    let isOn: Bool?
    let looksEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let on = isOn ?? true
        let fill: Color = !looksEnabled ? Theme.fillMuted : (on ? role.fill : Color.clear)
        let foreground: Color = !looksEnabled ? Color.white : (on ? role.foreground : Theme.ink)
        configuration.label
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: GameButtonMetrics.minTapTarget)
            .background(
                Capsule().fill(fill)
                    .overlay(Capsule().strokeBorder(Theme.inkSub.opacity(isOn == false ? 0.7 : 0), lineWidth: 1.5))
            )
            .contentShape(Capsule())
            .opacity(looksEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.55)
    }
}
