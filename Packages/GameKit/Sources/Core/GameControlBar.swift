import SwiftUI

/// 盤の下の操作行の共通部品（#1422）。一人用パズル・ソリティア系で同じ並びにする。
///
/// 並びは **左 = 取り消し（戻す／待った・ティール）／ 中央 = ゲーム固有（メモ・自動で上がる・配る・並べ替え）／
/// 右端 = 「⋯」メニュー（あきらめる・ヒント）**（会長決裁 2026-09-25・#1011 の D1）。
/// 押し間違えると局が終わる「あきらめる」を、よく押す取り消しの隣に置かないための配置でもある。
///
/// - ボタンの枠は 44pt（`BoardGameControlCapsuleStyle`。押せない間は面が `fillMuted` に替わり、枠は残す・#198）。
/// - 「⋯」は `menuItems` が空なら出さない（メニューに入れるものが無いゲームは右端を空けたままにしない）。
/// - 外枠（余白・`popCard`）もここで持つ。呼び出し側が持つと、ゲームごとに高さがずれる。
public struct GameControlBar<Leading: View, Center: View>: View {
    private let menuItems: [GameControlMenuItem]
    private let verticalPadding: CGFloat
    private let leading: Leading
    private let center: Center

    /// - Parameter verticalPadding: 外枠の上下の余白。盤の大きさを決める高さの計算に効くので、
    ///   従来の操作行の余白を持つゲーム（ナンプレは 4pt）は、その値を渡して外寸を据え置く（#139）。
    public init(
        menuItems: [GameControlMenuItem] = [],
        verticalPadding: CGFloat = 8,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder center: () -> Center
    ) {
        self.menuItems = menuItems
        self.verticalPadding = verticalPadding
        self.leading = leading()
        self.center = center()
    }

    public var body: some View {
        HStack(spacing: 8) {
            leading
            center
            Spacer(minLength: 0)
            if !menuItems.isEmpty {
                GameControlMenu(items: menuItems)
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, verticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }
}

/// 操作行のカプセルボタン（#1422）。色は役割で決める（取り消し = ティール・特別な宣言 = 紫）。
///
/// `showsTitle` を false にすると記号だけになる（文字を大きくした設定で 3 つ並ぶ行用。
/// 読み上げは `title` のまま）。
public struct GameControlButton: View {
    private let title: String
    private let systemImage: String
    private let tint: Color
    private let showsTitle: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        systemImage: String,
        tint: Color,
        showsTitle: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.showsTitle = showsTitle
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            if showsTitle {
                Label(title, systemImage: systemImage).lineLimit(1)
            } else {
                Image(systemName: systemImage)
            }
        }
        .buttonStyle(BoardGameControlCapsuleStyle(fill: tint))
        .accessibilityLabel(title)
    }
}

/// 「⋯」メニューの 1 項目。
public struct GameControlMenuItem: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let isDestructive: Bool
    public let isEnabled: Bool
    /// 読み上げ。文字（残り回数付きの題など）と別に伝えたいときだけ渡す。
    public let accessibilityLabel: String?
    public let accessibilityHint: String?
    public let action: () -> Void

    public init(
        id: String,
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
    }
}

/// 操作行の右端の「⋯」。当たり判定は枠の中に 44pt 取る（枠の外へはみ出させても Button は反応しない・#711）。
struct GameControlMenu: View {
    let items: [GameControlMenuItem]

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button(role: item.isDestructive ? .destructive : nil, action: item.action) {
                    Label(item.title, systemImage: item.systemImage)
                }
                .disabled(!item.isEnabled)
                .accessibilityLabel(item.accessibilityLabel ?? item.title)
                .accessibilityHint(item.accessibilityHint ?? "")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.inkSub)
                .frame(minWidth: BoardGameControlMetrics.minTapTarget,
                       minHeight: BoardGameControlMetrics.minTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("その他の操作")
    }
}
