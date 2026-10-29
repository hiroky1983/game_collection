import SwiftUI

// MARK: - データ

/// 「はじめての遊び方」の 1 枚（#2827）。大きな図 1 つ＋短い言葉 2〜3 行。文章では説明しない。
///
/// 図の View はゲーム側のモジュールにあるので、`HowToPlayItem` と同じくクロージャで受ける。
public struct OnboardingPage: Sendable {
    /// このカードの見出し（「このゲームの目的」「1 回の番でやること」など）。
    public let heading: String
    /// 短い言葉。2〜3 行（`OnboardingGuide.lineRange`）。
    public let lines: [String]
    /// 大きな図。そのゲームで実際に使っている札・駒・盤の描き方を使う。
    public let figure: @MainActor @Sendable () -> AnyView

    public init(heading: String, lines: [String], figure: @escaping @MainActor @Sendable () -> AnyView) {
        self.heading = heading
        self.lines = lines
        self.figure = figure
    }
}

/// 1 ゲームぶんの「はじめての遊び方」（#2827）。カードを横にめくって見る、ボタンを押したときだけ開く案内。
///
/// カードの型（全ゲーム共通）: ①このゲームの目的 → ②1 回の番でやること → ③大事なルール（2〜3 枚）→
/// ④勝ち負けの決まり。枚数は `pageRange`（4〜6 枚）。各ゲームはページの配列を渡すだけで、
/// 見た目・めくり方・「閉じる」は `OnboardingGuideView` が持つ。#2810（荷物運びの操作の案内）も同じ型で足せる。
public struct OnboardingGuide: Sendable, Equatable {
    /// `GameModule.id` と同じ ID。
    public let gameID: String
    /// シートの題名（例: 「チェスのはじめての遊び方」）。
    public let title: String
    public let pages: [OnboardingPage]

    /// 1 ゲームのカードの枚数。
    public static let pageRange = 4...6
    /// 1 枚の言葉の行数。
    public static let lineRange = 2...3

    public init(gameID: String, title: String, pages: [OnboardingPage]) {
        self.gameID = gameID
        self.title = title
        self.pages = pages
    }

    /// 枚数・行数が型に収まっているか。テストが全ゲームで確かめる。
    public var isWellFormed: Bool {
        Self.pageRange.contains(pages.count)
            && pages.allSatisfy { Self.lineRange.contains($0.lines.count) && !$0.heading.isEmpty }
    }

    /// 図（クロージャ）は比べられないので、文言で比べる。
    public static func == (lhs: OnboardingGuide, rhs: OnboardingGuide) -> Bool {
        lhs.gameID == rhs.gameID && lhs.title == rhs.title
            && lhs.pages.map(\.heading) == rhs.pages.map(\.heading)
            && lhs.pages.map(\.lines) == rhs.pages.map(\.lines)
    }

    /// 画面と読み上げに出すすべての文言（英訳の検査に使う）。
    public var texts: [String] {
        [title] + pages.flatMap { [$0.heading] + $0.lines }
    }

    /// 入口を出すか。v1.1.14 では隠していた（#2944・会長決裁 2026-10-26。花札でページ送り中に固まって
    /// 落ちた件 #2905・PR #2943 などのため）が、Canvas の直し（#2905・#2943・#2945・#2948）が入った
    /// v1.1.15 では出し直す（#3002）。中身・図・テストは消さず、`OnboardingEntry` の入口をこの 1 か所で切り替える。
    public static let isAvailable = true
}

// MARK: - 入口のボタン

/// 「はじめての遊び方（図で見る）」の入口。押したときだけ案内を開く（自動では出さない）。
///
/// 遊び方シートの先頭には `.prominent`、新規ゲーム・開始シートには小さめの `.compact` を置く。
/// 中身のあるゲームだけに出すため、呼び出し側は `guide` が nil のときは何も置かない
/// （`OnboardingEntry(guide)` は nil を受けて何も描かない）。
public struct OnboardingEntry: View {
    public enum Style: Sendable {
        case prominent
        case compact
    }

    private let guide: OnboardingGuide?
    private let style: Style
    @State private var isPresented = false

    public init(_ guide: OnboardingGuide?, style: Style) {
        self.guide = guide
        self.style = style
    }

    /// 最初に開くカード。通常は先頭。撮影用（DEBUG 限定）の `-onboardingPage <番号>`（0 始まり）で替えられる。
    private static var firstPage: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-onboardingPage"), i + 1 < args.count, let n = Int(args[i + 1]) { return n }
        #endif
        return 0
    }

    public var body: some View {
        // `OnboardingGuide.isAvailable` が false の版では入口を出さない（#2944）。
        if let guide, OnboardingGuide.isAvailable {
            Button { isPresented = true } label: {
                switch style {
                case .prominent:
                    HStack(spacing: 10) {
                        Image(systemName: "play.rectangle.fill").scaledFont(20, weight: .bold, maxScale: 1.3)
                        Text(tr("はじめての遊び方（図で見る）"))
                            .themeBody(16, weight: .bold)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        DisclosureChevron(tint: nil)
                    }
                    .foregroundStyle(Theme.onAccent)
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).fill(Theme.Fill.coral))
                case .compact:
                    Label(tr("はじめての遊び方（図で見る）"), systemImage: "play.rectangle")
                        .themeBody(14, weight: .bold)
                        .foregroundStyle(Theme.coralText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Capsule().strokeBorder(Theme.coralText.opacity(0.5), lineWidth: 1.5))
                }
            }
            .buttonStyle(.pop)
            #if DEBUG
            // 撮影用（DEBUG 限定・#2827）: `-showOnboarding` で入口のボタンが現れた直後に案内を開く
            // （シミュレータはタップを自動化できないため）。「？」のシートの入口は `-showHowToPlay`、
            // 開始シートの入口は何も付けずに開く。開く最初のカードは `-onboardingPage <番号>`。
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-showOnboarding") else { return }
                try? await Task.sleep(for: .milliseconds(600))
                isPresented = true
            }
            #endif
            .sheet(isPresented: $isPresented) {
                OnboardingGuideView(guide, startingAt: Self.firstPage) { isPresented = false }
            }
        }
    }
}

// MARK: - カードをめくる画面

/// 「はじめての遊び方」本体。カードを横にめくり、最後のカードの「閉じる」で終わる。
public struct OnboardingGuideView: View {
    private let guide: OnboardingGuide
    private let onClose: () -> Void
    @State private var index: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameter page: 最初に開くカード（0 始まり）。範囲外は端に丸める。
    public init(_ guide: OnboardingGuide, startingAt page: Int = 0, onClose: @escaping () -> Void) {
        self.guide = guide
        self.onClose = onClose
        _index = State(initialValue: min(max(page, 0), max(guide.pages.count - 1, 0)))
    }

    private var isLast: Bool { index >= guide.pages.count - 1 }

    public var body: some View {
        VStack(spacing: 0) {
            header
            pager
            footer
        }
        .popBackground()
        .presentationDetents([.large])
    }

    private var header: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // 最大サイズでは見出しと「閉じる」を 1 行に並べると重なる・切れるので、縦に積む（#2858）。
                VStack(spacing: 4) {
                    HStack {
                        Spacer()
                        closeButton
                    }
                    title.lineLimit(3)
                }
            } else {
                ZStack {
                    title.lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 72)
                    HStack {
                        Spacer()
                        closeButton
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 20)
    }

    private var title: some View {
        Text(guide.title).themeBody(17, weight: .bold).foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }

    private var closeButton: some View {
        Button(tr("閉じる")) { onClose() }
            .themeBody(17, weight: .semibold)
            .foregroundStyle(Theme.coralText)
            .frame(minHeight: 44)
    }

    @ViewBuilder
    private var pager: some View {
        #if os(iOS)
        TabView(selection: $index) {
            ForEach(Array(guide.pages.enumerated()), id: \.offset) { offset, page in
                OnboardingPageView(page: page, number: offset + 1, total: guide.pages.count)
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        OnboardingPageView(page: guide.pages[index], number: index + 1, total: guide.pages.count)
        #endif
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<guide.pages.count, id: \.self) { i in
                    Circle()
                        .fill(i == index ? Theme.coralText : Theme.inkSub.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityHidden(true)
            HStack(spacing: 10) {
                if index > 0 {
                    Button { step(-1) } label: {
                        Text(tr("前へ")).themeBody(16, weight: .bold)
                            .foregroundStyle(Theme.coralText)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                                .strokeBorder(Theme.coralText.opacity(0.5), lineWidth: 1.5))
                    }
                    .buttonStyle(.pop)
                }
                Button {
                    if isLast { onClose() } else { step(1) }
                } label: {
                    Text(isLast ? tr("閉じる") : tr("次へ")).themeBody(16, weight: .bold)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                            .fill(Theme.Fill.coral))
                }
                .buttonStyle(.pop)
            }
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 8)
        .padding(.bottom, Theme.pad)
    }

    private func step(_ delta: Int) {
        let next = min(max(index + delta, 0), guide.pages.count - 1)
        withAnimation(Motion.resolve(.easeInOut(duration: 0.25), reduceMotion: Motion.isReduceMotionEnabled)) { index = next }
    }
}

/// カード 1 枚。大きな図（残りの高さいっぱいに拡大）の下に、短い言葉を 2〜3 行。
private struct OnboardingPageView: View {
    let page: OnboardingPage
    let number: Int
    let total: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // 最大サイズでは見出し・言葉が画面の高さを超えるので、縦にスクロールさせ、図は一定の高さで置く（#2858）。
            ScrollView {
                VStack(spacing: 14) {
                    headingBlock
                    figureCard.frame(height: 220)
                    linesBlock
                }
                .padding(.horizontal, Theme.pad)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
        } else {
            VStack(spacing: 14) {
                headingBlock
                figureCard.frame(maxWidth: .infinity, maxHeight: .infinity)
                linesBlock
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private var headingBlock: some View {
        VStack(spacing: 4) {
            Text(tr("%1$lld / %2$lld", number, total))
                .scaledFont(12, weight: .black, design: .rounded, maxScale: 1.2)
                .foregroundStyle(Theme.inkSubText)
            Text(page.heading).themeBody(20, weight: .black)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var figureCard: some View {
        ScaledFigure(content: page.figure())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .popCard(corner: Theme.cornerSmall)
            // 図は説明の絵なので、読み上げは下の言葉に任せる。
            .accessibilityHidden(true)
    }

    private var linesBlock: some View {
        VStack(spacing: 6) {
            ForEach(Array(page.lines.enumerated()), id: \.offset) { _, line in
                Text(line).themeBody(17, weight: .bold)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 図を本来の大きさで測り、置き場に収まる範囲で大きく見せる（最大 1.7 倍）。
/// 図の部品は盤の寸法に縛られない固定寸法で描かれているので、拡大して使う。
private struct ScaledFigure: View {
    let content: AnyView
    @State private var natural: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let scale = Self.scale(natural: natural, available: geo.size)
            content
                .fixedSize()
                .background(GeometryReader { inner in
                    Color.clear.preference(key: NaturalSizeKey.self, value: inner.size)
                })
                .scaleEffect(scale)
                .frame(width: max(natural.width * scale, 1), height: max(natural.height * scale, 1))
                .frame(width: geo.size.width, height: geo.size.height)
                .opacity(natural == .zero ? 0 : 1)
        }
        // 測った大きさが 0.5pt 未満しか変わらないときは書き戻さない。書き戻すたびに図を組み直すので、
        // 端数の揺れで測り直しが止まらなくなると、ページ送りの間じゅう描き直しが続く（#2905）。
        .onPreferenceChange(NaturalSizeKey.self) { size in
            if Self.differs(size, from: natural) { natural = size }
        }
    }

    nonisolated static func differs(_ a: CGSize, from b: CGSize) -> Bool {
        abs(a.width - b.width) >= 0.5 || abs(a.height - b.height) >= 0.5
    }

    static func scale(natural: CGSize, available: CGSize) -> CGFloat {
        guard natural.width > 0, natural.height > 0 else { return 1 }
        return min(available.width / natural.width, available.height / natural.height, 1.7)
    }
}

private struct NaturalSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
