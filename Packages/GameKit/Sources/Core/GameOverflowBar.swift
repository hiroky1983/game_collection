import SwiftUI

/// 盤（札）と広告バナーのあいだに置く「⋯」の行（#1468。旧 `GameControlBar`）。
///
/// ユーザー操作（戻す・待った・ヒント・切り替え・投了など）は**すべて右下の「⋯」メニューに集める**
/// （会長決裁 2026-09-26 QA）。盤の下に操作のボタンを並べず、ヘッダー下の状態の帯（`GameStatusBar`）にも
/// ボタンを置かない。
///
/// - 「⋯」は丸 44pt。全ゲーム同じ位置・同じ見た目（`GameControlMenu`）。
/// - 行そのものは透明で、盤・札にも広告バナーにも重ならない 1 行ぶんの場所を確保するだけ
///   （AdMob の誤クリック誘導を避けるため、バナーに重ねも隣接もさせない）。
/// - 「⋯」は `menuItems` が空なら出さない。
public struct GameOverflowBar: View {
    private let menuItems: [GameControlMenuItem]
    private let verticalPadding: CGFloat
    private let nudge: HintNudge?
    private let caption: GameOverflowCaption?

    /// - Parameter caption: 左端に出す表示だけの短い文字（ソリティアの「3枚めくり」・スパイダーの配れない理由など、操作ではない情報）。
    /// - Parameter verticalPadding: 行の上下の余白。盤の大きさを決める高さの計算に効くので、
    ///   従来の操作行の余白を持つゲーム（ナンプレは 4pt）は、その値を渡して外寸を据え置く（#139）。
    /// - Parameter nudge: ヒントを促す吹き出し（#1424）。ヒントが「⋯」にあるゲームだけ渡す。
    public init(
        menuItems: [GameControlMenuItem] = [],
        verticalPadding: CGFloat = 8,
        nudge: HintNudge? = nil,
        caption: GameOverflowCaption? = nil
    ) {
        self.menuItems = menuItems
        self.verticalPadding = verticalPadding
        self.nudge = nudge
        self.caption = caption
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let caption {
                Text(caption.text)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(caption.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel(caption.accessibilityLabel ?? caption.text)
            }
            Spacer(minLength: 0)
            if !menuItems.isEmpty {
                GameControlMenu(items: menuItems)
            }
        }
        .frame(minHeight: BoardGameControlMetrics.minTapTarget)
        .padding(.vertical, verticalPadding)
        .hintNudge(nudge)
    }
}

/// 「⋯」の行の左端に出す、操作ではない表示。
public struct GameOverflowCaption {
    let text: String
    let color: Color
    let accessibilityLabel: String?

    public init(_ text: String, color: Color = Theme.inkSub, accessibilityLabel: String? = nil) {
        self.text = text
        self.color = color
        self.accessibilityLabel = accessibilityLabel
    }
}

/// 「⋯」メニューの 1 項目。
public struct GameControlMenuItem: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let isDestructive: Bool
    public let isEnabled: Bool
    /// チェックマーク付きのトグル項目にするときの現在の状態（メモ・拡大など）。nil なら普通の項目。
    public let isChecked: Bool?
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
        isChecked: Bool? = nil,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
    }
}

/// 右下の「⋯」。丸 44pt・全ゲーム共通の見た目。当たり判定は枠の中に取る（枠の外へはみ出させても Button は反応しない・#711）。
public struct GameControlMenu: View {
    let items: [GameControlMenuItem]

    public init(items: [GameControlMenuItem]) {
        self.items = items
    }

    /// 投了・あきらめるなどの破壊的操作はメニューの末尾に寄せる（元の並びは保つ）。
    static func ordered(_ items: [GameControlMenuItem]) -> [GameControlMenuItem] {
        items.filter { !$0.isDestructive } + items.filter(\.isDestructive)
    }

    public var body: some View {
        Menu {
            ForEach(Self.ordered(items)) { item in
                if let isChecked = item.isChecked {
                    Toggle(isOn: Binding(get: { isChecked }, set: { _ in item.action() })) {
                        Label(item.title, systemImage: item.systemImage)
                    }
                    .disabled(!item.isEnabled)
                    .accessibilityLabel(item.accessibilityLabel ?? item.title)
                    .accessibilityHint(item.accessibilityHint ?? "")
                } else {
                    Button(role: item.isDestructive ? .destructive : nil, action: item.action) {
                        Label(item.title, systemImage: item.systemImage)
                    }
                    .disabled(!item.isEnabled)
                    .accessibilityLabel(item.accessibilityLabel ?? item.title)
                    .accessibilityHint(item.accessibilityHint ?? "")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: BoardGameControlMetrics.minTapTarget, height: BoardGameControlMetrics.minTapTarget)
                .background(Circle().fill(Theme.fillMuted))
                .contentShape(Circle())
        }
        .accessibilityLabel("その他の操作")
    }
}
