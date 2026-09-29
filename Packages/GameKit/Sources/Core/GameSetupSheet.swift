import SwiftUI

// MARK: - 開始前の設定シートの共通枠（#527）

/// 対局・ゲームを始める前に「手番」「CPU の強さ」「盤面サイズ」などを選ばせるシートの共通枠。
///
/// 各ゲームは**選ばせる中身だけ**を書き、枠（背景・題名・キャンセル・開始ボタン・シートの高さ）は
/// ここが持つ。`docs/ai-devops.md`「1局=1RuleSet」原則で局に焼き込む値を組み立てる場所でもあるため、
/// 分岐が増えるゲームはこのシートに節（`GameSetupSection`）を足していく。
///
/// **並べ方は 1 種類だけ**（#1415・会長決裁 D3）: シートは常に `.large` 固定で、上に題名とキャンセル、
/// 中身はスクロール、開始ボタンは下端に固定する。中身の長さはゲームごとに自由。かつては
/// 「`.medium` から開く」「開始ボタンも一緒に流れる」など 3 種類あり、ゲームによってシートの高さも
/// 開始ボタンの位置も違っていた。題名と開始ボタンの文言も、引数ではなく種別（`GameSetupKind`）で決める。
public struct GameSetupSheet<Content: View>: View {
    private let kind: GameSetupKind
    private let startTitle: String
    private let startTint: Color
    private let spacing: CGFloat
    private let onStart: () -> Void
    private let onCancel: () -> Void
    private let content: Content

    /// - Parameters:
    ///   - kind: 対戦か一人用か。題名と開始ボタンの文言はこれで決まる。
    ///   - discardsProgress: 途中の盤面を捨てて始め直すシートのとき true。開始ボタンが
    ///     「終了してスタート」のような確認の文言になる（誤って押して進行を失わないため）。
    ///   - startTint: 開始ボタンの面色。上に載る文字は `Theme.onAccent` 固定（#220）。
    ///   - spacing: 節と節の間隔。
    public init(
        kind: GameSetupKind,
        discardsProgress: Bool = false,
        startTint: Color = Theme.Fill.coral,
        spacing: CGFloat = 24,
        onStart: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.kind = kind
        self.startTitle = discardsProgress ? "終了して\(kind.startTitle)" : kind.startTitle
        self.startTint = startTint
        self.spacing = spacing
        self.onStart = onStart
        self.onCancel = onCancel
        self.content = content()
    }

    public var body: some View {
        // NavigationStack は使わない。シートの `.medium` では中身の上端がナビゲーションバーの分だけ
        // 押し下げられず、最初の節の見出しがバー（キャンセル・題名）と重なった（#1252。
        // `.navigationBarTitleDisplayMode(.inline)` を足しても直らない）。題名とキャンセルは
        // 中身の上に積む行として自前で描き、重なりが構造上起きないようにする。
        VStack(spacing: 0) {
            header
            frame
        }
        .popBackground()
        .presentationDetents([.large])
    }

    private var header: some View {
        ZStack {
            Text(kind.title).themeBody(17, weight: .bold).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button("キャンセル") { onCancel() }
                    .themeBody(17, weight: .regular)
                Spacer()
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Theme.pad)
        .padding(.top, 30)
        .padding(.bottom, 4)
    }

    private var frame: some View {
        // 開始ボタンだけを `ScrollView` の外に出し、スクロールしなくても押せるようにする。
        // `VStack{ ScrollView; button }` で組むと、`ScrollView` が `VStack` に入れ子になった
        // ぶん「余った分だけ使う」高さの伝播が効かず、button がシートの外へ押し出されて
        // 見えなくなった（実機確認・2026-09-22）。`.safeAreaInset` なら `ScrollView` 自身が
        // 直接の子のまま、下にボタンの場所を安全に確保できる。
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(Theme.pad)
        }
        .safeAreaInset(edge: .bottom) {
            startButton
                .padding(.horizontal, Theme.pad)
                .padding(.top, 12)
                .padding(.bottom, Theme.pad)
                .background(.regularMaterial)
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

/// 開始シートの種別。題名と開始ボタンの文言は種別で決まり、ゲームごとには変えない（#1415・#1011 決裁）。
public enum GameSetupKind: Sendable {
    /// CPU や相手と勝負するゲーム（将棋・チェス・囲碁など）。「新規対局」「対局開始」。
    case versus
    /// 一人で遊ぶゲーム（マインスイーパー・数独など）。「新規ゲーム」「スタート」。
    case solo

    public var title: String {
        switch self {
        case .versus: "新規対局"
        case .solo:   "新規ゲーム"
        }
    }

    public var startTitle: String {
        switch self {
        case .versus: "対局開始"
        case .solo:   "スタート"
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
                // 副題が空のときは行ごと出さない（CPU の強さの5段階だけは、狭い端末で
                // 読める大きさを保つため副題をタイルの外へ出している。`CPUStrengthPicker`）。
                if !subtitle.isEmpty { subtitleText }
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
