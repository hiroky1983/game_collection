import SwiftUI

// MARK: - 開始前の設定シートの共通枠（#527）

/// 対局・ゲームを始める前に「手番」「CPU の強さ」「盤面サイズ」などを選ばせるシートの共通枠。
///
/// 各ゲームは**選ばせる中身だけ**を書き、枠（背景・題名・キャンセル・開始ボタン・シートの高さ）は
/// ここが持つ。`docs/ai-devops.md`「1局=1RuleSet」原則で局に焼き込む値を組み立てる場所でもあるため、
/// 分岐が増えるゲームはこのシートに節（`GameSetupSection`）を足していく。
///
/// **シートの高さは並べ方から決まる**。`pinnedStart` は開始ボタンを下端に固定する代わりに
/// `.medium` から開き（`gameSheetDetents()`。文字を拡大したときだけ `.large`）、`scrolling` は
/// 節が 3 つ以上あって `.medium` に収まらないゲーム用で常に `.large` で開く。ここを取り違えると
/// 「開始ボタンがはみ出して押せない」（囲碁・五目並べで実際に起きた）に戻る。
public struct GameSetupSheet<Content: View>: View {
    public typealias Layout = GameSetupSheetLayout

    private let title: String
    private let startTitle: String
    private let startTint: Color
    private let spacing: CGFloat
    private let layout: Layout
    private let onStart: () -> Void
    private let onCancel: () -> Void
    private let content: Content

    /// - Parameters:
    ///   - title: シートの題名（「新規対局」「新規ゲーム」など）。
    ///   - startTitle: 開始ボタンの文言（「対局開始」「スタート」など）。
    ///   - startTint: 開始ボタンの面色。上に載る文字は `Theme.onAccent` 固定（#220）。
    ///   - spacing: 節と節の間隔。
    ///   - layout: 並べ方。上の注意を参照。
    public init(
        title: String,
        startTitle: String,
        startTint: Color = Theme.Fill.coral,
        spacing: CGFloat = 24,
        layout: Layout = .pinnedStart,
        onStart: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.startTitle = startTitle
        self.startTint = startTint
        self.spacing = spacing
        self.layout = layout
        self.onStart = onStart
        self.onCancel = onCancel
        self.content = content()
    }

    public var body: some View {
        NavigationStack {
            frame
                .popBackground()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { onCancel() }
                    }
                }
        }
        .modifier(SetupSheetDetents(layout: layout))
    }

    @ViewBuilder
    private var frame: some View {
        switch layout {
        case .pinnedStart:
            VStack(alignment: .leading, spacing: spacing) {
                content
                Spacer()
                startButton
            }
            .padding(Theme.pad)
        case .scrolling:
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    content
                    startButton
                }
                .padding(Theme.pad)
            }
        }
    }

    private var startButton: some View {
        Button { onStart() } label: {
            Text(startTitle).themeBody(18).frame(maxWidth: .infinity)
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.borderedProminent).controlSize(.large).tint(startTint)
    }
}

/// `GameSetupSheet` の中身の並べ方。
public enum GameSetupSheetLayout: Sendable {
    /// 選択肢を上に寄せ、開始ボタンを下端に固定する。`.medium` から開く。
    case pinnedStart
    /// 中身ごとスクロールさせ、開始ボタンも一緒に流す。常に `.large` で開く。
    case scrolling
}

/// 並べ方に応じたシートの高さ。分岐を修飾子の中に閉じ込め、呼び出し側の型を揃える。
private struct SetupSheetDetents: ViewModifier {
    let layout: GameSetupSheetLayout

    @ViewBuilder
    func body(content: Content) -> some View {
        switch layout {
        case .pinnedStart: content.gameSheetDetents()
        case .scrolling:   content.presentationDetents([.large])
        }
    }
}

// MARK: - 節

/// 設定シートの 1 節（見出し + 選択肢）。
public struct GameSetupSection<Content: View>: View {
    private let title: String
    private let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).themeBody(15).foregroundStyle(Theme.inkSub)
            content
        }
    }
}

// MARK: - 選択肢のタイル

/// 設定シートで 1 つを選ぶタイル（「先手／後手」「弱／普通／強」など）。
///
/// 選択中は面が `accent` で塗られ、文字は `onAccent` になる。**濃い面（`fillStrong` /
/// `fillMuted`）に載せるときだけ呼び出し側が白を渡す**（差し色の面に白は AA 未達・#220）。
public struct GameSetupChooser: View {
    /// 題名の書体。ゲームによって見出し（`themeTitle`）と本文（`themeBody`）が使い分けられている。
    public enum TitleFont: Sendable {
        case title(CGFloat)
        case body(CGFloat)
    }

    /// タイルの寸法。既定は最も多い形（見出し22・副題12・上下余白16・縮小なし）。
    /// 選択肢が 3 つ以上並ぶゲームや文字数が多いゲームだけ値を差し替える。
    public struct Metrics: Sendable {
        public var title: TitleFont
        public var subtitleSize: CGFloat
        public var verticalPadding: CGFloat
        /// 1 行に収まらないとき、題名をどこまで縮めるか。`nil` なら折り返す（＝縮めない）。
        public var titleMinimumScale: CGFloat?
        /// 副題の縮小率。同上。
        public var subtitleMinimumScale: CGFloat?

        public init(
            title: TitleFont = .title(22),
            subtitleSize: CGFloat = 12,
            verticalPadding: CGFloat = 16,
            titleMinimumScale: CGFloat? = nil,
            subtitleMinimumScale: CGFloat? = nil
        ) {
            self.title = title
            self.subtitleSize = subtitleSize
            self.verticalPadding = verticalPadding
            self.titleMinimumScale = titleMinimumScale
            self.subtitleMinimumScale = subtitleMinimumScale
        }

        public static let standard = Metrics()
    }

    private let title: String
    private let subtitle: String
    private let selected: Bool
    private let accent: Color
    private let onAccent: Color
    private let metrics: Metrics
    private let action: () -> Void

    /// - Parameter onAccent: 選択中（＝面が `accent` で塗られている状態）の文字色。
    ///   差し色の面には `Theme.onAccent`、`fillStrong` / `fillMuted` のような濃い面には白を渡す（#220）。
    public init(
        title: String,
        subtitle: String,
        selected: Bool,
        accent: Color,
        onAccent: Color = Theme.onAccent,
        metrics: Metrics = .standard,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        self.accent = accent
        self.onAccent = onAccent
        self.metrics = metrics
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                titleText
                subtitleText
            }
            .frame(maxWidth: .infinity).padding(.vertical, metrics.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(selected ? accent : Theme.surface)
                    .shadow(color: .black.opacity(selected ? 0.15 : 0.06), radius: 6, y: 3)
            )
        }
        .buttonStyle(.plain)
        // 選択中であることを VoiceOver にも伝える（面の色だけでは読み上げに出ない）。
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var titleText: some View {
        Group {
            switch metrics.title {
            case .title(let size): Text(title).themeTitle(size)
            case .body(let size):  Text(title).themeBody(size)
            }
        }
        .foregroundStyle(selected ? onAccent : Theme.ink)
        .modifier(ShrinkToFit(minimumScale: metrics.titleMinimumScale))
    }

    private var subtitleText: some View {
        Text(subtitle)
            .font(.system(size: metrics.subtitleSize, weight: .semibold, design: .rounded))
            .foregroundStyle(selected ? onAccent : Theme.inkSub)
            .modifier(ShrinkToFit(minimumScale: metrics.subtitleMinimumScale))
    }
}

/// 1 行に収まらない文字を縮めて収める。`nil` のときは何もしない（＝従来どおり折り返す）。
private struct ShrinkToFit: ViewModifier {
    let minimumScale: CGFloat?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let minimumScale {
            content.lineLimit(1).minimumScaleFactor(minimumScale)
        } else {
            content
        }
    }
}
