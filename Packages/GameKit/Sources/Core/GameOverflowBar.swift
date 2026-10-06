import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 盤（札）と広告バナーのあいだに置く「操作の段」と「⋯」の行（#1468・#1856。旧 `GameControlBar`）。
///
/// その場で使う操作（待った・戻す・ヒント・パス・ジョーカー・配る・並べ替え・メモ・旗モード）は
/// 役割の色のカプセルを**等幅**で並べる（`GameActionCapsule`・会長決裁 2026-10-06 案A・#1834）。
/// 投了・諦める・拡大・自動で上がるは右下の「⋯」メニュー（`GameControlMenu`）に残す。
/// ヘッダー下の状態の帯（`GameStatusBar`）にはボタンを置かない。
///
/// - 「⋯」は丸 44pt。全ゲーム同じ位置・同じ見た目（`GameControlMenu`）。
/// - 行は盤・札の**すぐ下**に置き、余白を吸う `Spacer` はこの行と広告のあいだに置く（#1485）。
/// - 行そのものは透明で、盤・札にも広告バナーにも重ならない 1 行ぶんの場所を確保するだけ
///   （AdMob の誤クリック誘導を避けるため、バナーに重ねも隣接もさせない）。
/// - 「⋯」は `menuItems` が空なら出さない（神経衰弱は待っただけで「⋯」が無い）。
public struct GameOverflowBar: View {
    private let menuItems: [GameControlMenuItem]
    /// 段に並べる操作。空なら「⋯」だけの行。
    private let actions: [GameActionItem]
    private let verticalPadding: CGFloat
    private let nudge: HintNudge?
    private let caption: GameOverflowCaption?
    /// 「⋯」メニューを開いているか。開いているあいだはヒントの促しを出さない（#1485）。
    @State private var isMenuOpen = false

    /// - Parameter actions: 段に並べる操作（左から。たたき台 4: 戻す → 助ける → 進める → 「⋯」）。
    /// - Parameter verticalPadding: 行の上下の余白。盤の大きさを決める高さの計算に効くので、
    ///   従来の操作行の余白を持つゲーム（ナンプレは 4pt）は、その値を渡して外寸を据え置く（#139）。
    /// - Parameter nudge: ヒントを促す表示（#1424）。ヒントを持つゲームだけ渡す。段にヒントがあれば
    ///   そのカプセルを光らせ、段が無い（ヒントが「⋯」にある）ときは「⋯」の左に吹き出しを出す。
    /// - Parameter caption: 表示だけの短い文字（スパイダーの配れない理由など、操作ではない情報）。
    ///   段が無ければ行の左端に、段があれば段と「⋯」のあいだに出す（出ているあいだ段のカプセルはその分だけ狭くなる）。
    public init(
        menuItems: [GameControlMenuItem] = [],
        actions: [GameActionItem] = [],
        verticalPadding: CGFloat = 8,
        nudge: HintNudge? = nil,
        caption: GameOverflowCaption? = nil
    ) {
        self.menuItems = menuItems
        self.actions = actions
        self.verticalPadding = verticalPadding
        self.nudge = nudge
        self.caption = caption
    }

    public var body: some View {
        HStack(spacing: 8) {
            if actions.isEmpty {
                captionText
                Spacer(minLength: 0)
            } else {
                ForEach(actions) { GameActionCapsule(item: $0) }
                captionText
            }
            if !menuItems.isEmpty {
                GameControlMenu(items: menuItems, isOpen: $isMenuOpen)
            }
        }
        .frame(minHeight: BoardGameControlMetrics.minTapTarget)
        .padding(.vertical, verticalPadding)
        .hintNudge(nudge, isMenuOpen: isMenuOpen, highlightsAction: !actions.isEmpty)
        // 盤で操作があった＝メニューは閉じている。閉じた知らせを取りこぼしても、吹き出しが止まったままにならないよう戻す。
        .onChange(of: nudge?.activity) { isMenuOpen = false }
    }

    @ViewBuilder private var captionText: some View {
        if let caption {
            Text(caption.text)
                .themeCaption(12, maxScale: 1.3)
                .foregroundStyle(caption.color)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                // 段と並ぶときは文字を優先して確保し、カプセル側を縮める（文字が 1 文字ずつ折れるのを防ぐ）。
                .layoutPriority(1)
                .frame(maxWidth: Self.captionMaxWidth)
                .accessibilityLabel(caption.accessibilityLabel ?? caption.text)
        }
    }

    /// 段と並ぶ表示の幅の上限。SE（行 290pt）でも「戻す」のカプセルに 90pt 以上残す。
    static let captionMaxWidth: CGFloat = 150
}

/// 「⋯」の行に出す、操作ではない表示。
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
    private let isOpen: Binding<Bool>?

    /// - Parameter isOpen: メニューを開いているあいだ true にする（ヒントの吹き出しを止めるため・#1485）。
    ///   `Menu` の中身の出入り（onAppear / onDisappear）は実機で発火が確認できなかった（#1499）ため、
    ///   開いた合図は「⋯」自体へのタップでも重ねて取る（`simultaneousGesture` は Menu 本来のタップを妨げない）。
    public init(items: [GameControlMenuItem], isOpen: Binding<Bool>? = nil) {
        self.items = items
        self.isOpen = isOpen
    }

    private func setOpen(_ value: Bool) {
        guard let isOpen, isOpen.wrappedValue != value else { return }
        isOpen.wrappedValue = value
    }

    /// 投了・あきらめるなどの破壊的操作はメニューの末尾に寄せる（元の並びは保つ）。
    static func ordered(_ items: [GameControlMenuItem]) -> [GameControlMenuItem] {
        items.filter { !$0.isDestructive } + items.filter(\.isDestructive)
    }

    /// 項目のアイコン＋文字。押せない項目はアイコンも文字と同じグレーにする（いまはアイコンだけ差し色のコーラルに
    /// 残ってしまっていた・#1499）。押せる項目はここで色を触らず、従来どおりの見た目のまま。
    @ViewBuilder
    private static func label(for item: GameControlMenuItem) -> some View {
        if item.isEnabled {
            Label(item.title, systemImage: item.systemImage)
        } else {
            // iOS 標準のメニューはアイコンをアプリの差し色（`HubView` の `.tint(Theme.coral)`）で塗り直すため、
            // `.foregroundStyle` の指定は効かずコーラルのまま残った（会長 QA 2026-09-28）。色を焼き込んだ画像
            // （`alwaysOriginal`）で渡すと塗り直されないので、押せない項目だけアイコンを文字と同じグレーにできる。
            Label {
                Text(item.title)
            } icon: {
                disabledIcon(item.systemImage)
            }
        }
    }

    @ViewBuilder
    private static func disabledIcon(_ systemImage: String) -> some View {
        #if canImport(UIKit)
        if let image = UIImage(systemName: systemImage)?
            .withTintColor(.tertiaryLabel, renderingMode: .alwaysOriginal) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
        }
        #else
        Image(systemName: systemImage)
        #endif
    }

    public var body: some View {
        Menu {
            ForEach(Self.ordered(items)) { item in
                if let isChecked = item.isChecked {
                    Toggle(isOn: Binding(get: { isChecked }, set: { _ in setOpen(false); item.action() })) {
                        Self.label(for: item)
                    }
                    .disabled(!item.isEnabled)
                    .accessibilityLabel(item.accessibilityLabel ?? item.title)
                    .accessibilityHint(item.accessibilityHint ?? "")
                } else {
                    Button(role: item.isDestructive ? .destructive : nil) {
                        setOpen(false)
                        item.action()
                    } label: {
                        Self.label(for: item)
                    }
                    .disabled(!item.isEnabled)
                    .accessibilityLabel(item.accessibilityLabel ?? item.title)
                    .accessibilityHint(item.accessibilityHint ?? "")
                }
            }
            .onAppear { setOpen(true) }
            .onDisappear { setOpen(false) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: BoardGameControlMetrics.minTapTarget, height: BoardGameControlMetrics.minTapTarget)
                .background(Circle().fill(Theme.fillMuted))
                .contentShape(Circle())
        }
        .simultaneousGesture(TapGesture().onEnded { setOpen(true) })
        .accessibilityLabel("その他の操作")
    }
}
