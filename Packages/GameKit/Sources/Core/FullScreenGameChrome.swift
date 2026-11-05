import SwiftUI

/// レイアウトパターン A（全画面・バナー下・タイトルあり）の共通枠（#2531・#2111）。
///
/// 会長決裁（2026-10-18・2026-10-19）: A は **盤（卓）を画面いっぱいに広げる**。バナーは画面最下部に残し、
/// タイトル（ゲーム名）も残す。ヘッダーは **1 行**（戻る ＋ ゲーム名 ＋ 手数などの札 ＋ 右のアイコン群）に詰め、
/// 盤は残りでできるだけ大きくする。A を採ったゲーム（大富豪・いろリレー・麻雀ソリティア・フリーセル・ソリティア・
/// 花札こいこい・腰痛おじさんパズル）は、通常の `gameChrome(title:review:…)` の代わりに
/// `gameChrome(title:review:fullScreen:ads:…)` を 1 回通す（走査テスト `GameChromeSourceTests` の「ちょうど 1 回」は
/// どちらの形でも同じ 1 回に数える）。
///
/// 通常の枠（`GameChrome.swift`）との違いは次の 3 点だけで、**それ以外（評価リクエストの紐づけ・ボタンの色・
/// 役の早見表 → ？ → 新規 の並び）は同じ**:
///
/// 1. OS のナビゲーションバーを出さず、自前の 1 行のヘッダー（`FullScreenGameLayoutMetrics.headerTotalHeight`）を置く。
///    ナビバー（iOS 26 で 54pt）より低く、ゲーム数・手番などの「ヘッダー下の帯」（`GameStatusBar`・44pt）を
///    ヘッダーの行に吸収するので、盤に回る高さが約 50pt 増える（大富豪の実測は README「大富豪: 今 vs A」）。
/// 2. 面（`FullScreenGameSurface`）を画面全体（安全域の外まで）に敷く。カード系は**共通の卓のフェルト**
///    （`CardTableStyle`・木枠なし）、それ以外は地の色。フェルトのときは卓の上の文字色（`cardTableInk`）も配る。
/// 3. バナーは画面最下部の**地の色の帯**（上の余白 8 + 50pt + 下の安全域）に置く（`safeAreaInset`）。
///    面はこの帯の裏までは敷かない（広告の面に卓の色が混ざらない）。
///
/// 盤の下の操作の段と「決着しても盤が動かない」契約（#148・#1485）はこの枠では決めない。盤が決着後も残る
/// ゲームは従来どおり `GameControlArea` で操作の段の高さをそろえる（この枠は段の高さに手を入れないので、
/// 中身がそろっていれば盤は動かない）。
///
/// 寸法は View の `static let` に置くと MainActor 隔離になりテストから読めないので、非隔離の enum に持つ
/// （`FullScreenGameChromeTests` が値を固定する）。

// MARK: - 寸法

public enum FullScreenGameLayoutMetrics {
    /// ヘッダーの行の高さ（戻る・右のアイコンの丸ボタンの一辺 = タップ標的の下限 44pt）。
    public static let headerHeight: CGFloat = 44
    /// ヘッダーの行の上下の余白（ステータスバーと盤から離す）。
    public static let headerVerticalPadding: CGFloat = 4
    /// ヘッダーが占める高さ（行 + 上下の余白）。iOS 26 のナビバー 54pt より低い。
    public static var headerTotalHeight: CGFloat { headerHeight + headerVerticalPadding * 2 }
    /// ヘッダーの部品どうしの間隔。
    public static let headerSpacing: CGFloat = 8
    /// 画面の左右の余白（ヘッダーと盤に共通）。通常の枠の `Theme.pad`（16）より詰める（モック A の値）。
    public static let sideInset: CGFloat = 8
    /// バナーの帯の、バナーの上の余白。
    public static let bannerTopPadding: CGFloat = 8
    /// バナーの高さ。`BannerSlot.height` と同じ値（View の `static let` は MainActor 隔離なのでここに写し、
    /// `FullScreenGameChromeTests` が一致を固定する）。
    public static let bannerHeight: CGFloat = 50

    /// 画面最下部のバナーの帯の高さ（上の余白 + バナー + 下の安全域）。
    public static func bannerBandHeight(safeAreaBottom: CGFloat) -> CGFloat {
        bannerTopPadding + bannerHeight + max(0, safeAreaBottom)
    }

    /// ヘッダーの下からバナーの帯の上までの、盤・操作の段に使える高さ。
    /// - Parameters:
    ///   - screenHeight: 画面の高さ（iPhone 17 は 874、iPhone SE は 667）。
    ///   - safeAreaTop: 上の安全域（ステータスバー。iPhone 17 は 62、SE は 20）。
    ///   - safeAreaBottom: 下の安全域（ホームインジケータ。iPhone 17 は 34、SE は 0）。
    public static func contentHeight(screenHeight: CGFloat, safeAreaTop: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        max(0, screenHeight - max(0, safeAreaTop) - headerTotalHeight - bannerBandHeight(safeAreaBottom: safeAreaBottom))
    }

    /// 盤（卓）に残る高さ。中身の高さから、盤以外の固定の段（席・手札・操作の段など）の高さと、
    /// 段のあいだの間隔（固定の段の数だけ）を引いた値。
    public static func boardHeight(contentHeight: CGFloat, fixedRows: [CGFloat], spacing: CGFloat) -> CGFloat {
        let rows = fixedRows.reduce(0, +)
        return max(0, contentHeight - rows - spacing * CGFloat(fixedRows.count))
    }
}

// MARK: - 面

/// A の画面全体に敷く面。
public enum FullScreenGameSurface: Sendable, Equatable {
    /// 共通の卓のフェルト（木枠なし・画面全体）。カード系のゲーム。
    case felt
    /// 地の色（`Theme.background`）。カード系以外。
    case plain

    /// ヘッダーの題字・札の文字色。フェルトの上は白、地の上は墨。
    var headerInk: Color {
        self == .felt ? Color.white : Theme.ink
    }

    /// ヘッダーの丸ボタンの面。
    var buttonFill: Color {
        self == .felt ? Color.white.opacity(0.92) : Theme.surface
    }

    /// ヘッダーの丸ボタンのアイコン色。通常の枠のツールバーと同じ `Theme.coralText`（#2377）。
    /// フェルトの上の白い丸はライト / ダークで変えないので、ライトの値で固定する。
    var buttonInk: Color {
        self == .felt ? Color(hex: Theme.Hex.coralText.light) : Theme.coralText
    }

    /// 卓の上に置く空き枠・仕切り・文字の色。
    var tableInk: CardTableInk {
        self == .felt ? .felt : .plain
    }

    /// 木枠なし・角丸なし・影なしのフェルト（画面全体を卓にする）。
    public static let feltOnly = CardTableFrame(
        top: .points(0), leading: .points(0), bottom: .points(0), trailing: .points(0),
        innerShadow: nil, aspectRatio: nil, cornerRadius: 0, dropShadow: false)
}

// MARK: - フェルトの上か

private struct OnTableFeltKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// 全画面のフェルト（`gameChrome(fullScreen: .felt)`）の上か。淡い塗りの部品（広告で補充するカプセル #1897）が
    /// 緑に沈まないよう、地の面を下に敷くかを決めるのに読む（#2531）。
    var isOnTableFelt: Bool {
        get { self[OnTableFeltKey.self] }
        set { self[OnTableFeltKey.self] = newValue }
    }
}

// MARK: - 枠

public extension View {
    /// レイアウトパターン A の共通枠（#2531）。通常の `gameChrome(title:review:…)` の代わりに 1 回だけ通す。
    ///
    /// - Parameters:
    ///   - title: ヘッダー左寄せの表示名。長いときは縮めて 1 行に収める（iPhone SE でも 1 行）。
    ///   - review: 評価リクエストの実行をこの画面に紐づける（通常の枠と同じ）。
    ///   - fullScreen: 画面全体に敷く面（カード系は `.felt`）。
    ///   - ads: 画面最下部のバナー（`BannerSlot`）の取得元。ゲーム側に `BannerSlot` は置かない。
    ///   - condition: ヘッダーの表示名の下に出す今の条件のチップ（#1690）。幅が足りないときは
    ///     全文 → 難易度だけ → 出さない、の順に縮める（札の数字を最優先・ヘッダーが画面幅をはみ出さない）。
    ///   - reference: 役の早見表。あるゲームだけ渡す。
    ///   - newGame: 新規ボタン。あるゲームだけ渡す。
    ///   - status: ヘッダーの行に置く札（ゲーム数・手番など。`GameStatusBar` に置いていた中身）。
    ///     1 行に縮めて収める。無いゲームは `EmptyView()`。
    ///
    /// ヘッダー右の並びは通常の枠と同じ **役の早見表 → `?`（`.howToPlay`）→ 新規** で固定。
    /// `.howToPlay` はこの枠の**外側**に付ける（環境値は下にしか流れない）。
    func gameChrome<Status: View>(
        title: String,
        review: ReviewRequestService?,
        fullScreen surface: FullScreenGameSurface,
        ads: AdService,
        condition: GameChromeCondition? = nil,
        reference: GameChromeReference? = nil,
        newGame: GameChromeNewGame? = nil,
        @ViewBuilder status: () -> Status
    ) -> some View {
        modifier(GameChromeBase(review: review, paintsBackground: false))
            .modifier(FullScreenGameChromeModifier(title: title, surface: surface, ads: ads, condition: condition,
                                                   reference: reference, newGame: newGame, status: status()))
    }

    /// 札の無いゲーム用。
    func gameChrome(
        title: String,
        review: ReviewRequestService?,
        fullScreen surface: FullScreenGameSurface,
        ads: AdService,
        condition: GameChromeCondition? = nil,
        reference: GameChromeReference? = nil,
        newGame: GameChromeNewGame? = nil
    ) -> some View {
        gameChrome(title: title, review: review, fullScreen: surface, ads: ads, condition: condition,
                   reference: reference, newGame: newGame) { EmptyView() }
    }
}

private struct FullScreenGameChromeModifier<Status: View>: ViewModifier {
    typealias Metrics = FullScreenGameLayoutMetrics

    let title: String
    let surface: FullScreenGameSurface
    let ads: AdService
    let condition: GameChromeCondition?
    let reference: GameChromeReference?
    let newGame: GameChromeNewGame?
    let status: Status

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            FullScreenGameHeader(title: title, surface: surface, condition: condition,
                                 reference: reference, newGame: newGame, status: status)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surfaceBackground)
        .environment(\.cardTableInk, surface.tableInk)
        .environment(\.isOnTableFelt, surface == .felt)
        // 画面最下部のバナー（会長の方針: A のバナーは下）。地の色の帯に置き、下の安全域まで帯で埋める。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BannerSlot(ads: ads)
                .padding(.horizontal, Theme.pad)
                .padding(.top, Metrics.bannerTopPadding)
                .frame(maxWidth: .infinity)
                .background(Theme.background.ignoresSafeArea(edges: .bottom))
        }
        #if os(iOS)
        // OS のナビバーは出さず、上の 1 行のヘッダーで代える。フェルトの上ではステータスバーの文字を白にする
        // （iOS 26 では隠したナビバーの配色がステータスバーの文字色に使われる。iOS 17 の SE で実測したところ
        // 効かず黒い文字のままだったので、26 より前はフェルトをステータスバーの裏まで敷かない・下の `surfaceBackground`）。
        .toolbarColorScheme(surface == .felt && Self.statusBarFollowsHiddenToolbar ? .dark : nil, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    /// 隠したナビバーの配色（`toolbarColorScheme`）がステータスバーの文字色に反映される OS か。
    /// iOS 26 の iPhone 17 では白くなり、iOS 17 の iPhone SE では黒いままだった（2026-10-19 シミュレータ実測）。
    static var statusBarFollowsHiddenToolbar: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
    }

    /// 面。地の色をいちばん下に敷き（通常の枠の `popBackground` の代わり）、その上に面を重ねる。
    /// 面は安全域の外（左右・下）まで敷く。バナーの帯の裏には敷かない（帯は自分の地の色を持つ）。
    /// ステータスバーの裏は、文字色を白にできる OS でだけ面を敷く（できない OS では地の色のまま = 黒い文字が読める）。
    @ViewBuilder private var surfaceBackground: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if Self.statusBarFollowsHiddenToolbar {
                surfaceView.ignoresSafeArea()
            } else {
                surfaceView.ignoresSafeArea(edges: [.horizontal, .bottom])
            }
        }
    }

    @ViewBuilder private var surfaceView: some View {
        switch surface {
        case .felt: CardTableSurface(frame: FullScreenGameSurface.feltOnly)
        case .plain: Theme.background
        }
    }
}

// MARK: - ヘッダー

/// 1 行のヘッダー: 戻る ＋ 表示名（左寄せ・縮む）＋ 札 ＋ 役の早見表 → ？ → 新規。
///
/// 幅の配り方: ボタンは固定幅。表示名は `layoutPriority(1)` で札より先に幅をもらい、表示名だけで行に収まらない
/// ときだけ縮む（`minimumScaleFactor(0.6)`）。札（`status`）は残りの幅を受け取るので、ゲーム側は
/// `ViewThatFits` で短い言い回しに切り替えるか、1 行に縮めて収める（英語の長い語で iPhone SE に収めるため。
/// 札を先に配ると、英語の「Color Relay」のような表示名が 0.6 倍まで縮んで題字に見えなくなる）。
private struct FullScreenGameHeader<Status: View>: View {
    typealias Metrics = FullScreenGameLayoutMetrics

    let title: String
    let surface: FullScreenGameSurface
    let condition: GameChromeCondition?
    let reference: GameChromeReference?
    let newGame: GameChromeNewGame?
    let status: Status
    @State private var confirmsNewGame = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.howToPlayTrigger) private var howToPlay
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let showsChip = condition != nil && !dynamicTypeSize.isAccessibilitySize
        HStack(spacing: Metrics.headerSpacing) {
            FullScreenHeaderButton(systemImage: "chevron.left", label: tr("戻る"), surface: surface) { dismiss() }
            Text(title)
                .themeBody(20, weight: .bold, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(surface.headerInk)
                .shadow(color: surface == .felt ? .black.opacity(0.35) : .clear, radius: 2, y: 1)
                .accessibilityAddTraits(.isHeader)
                .anchorPreference(key: HeaderFramesKey.self, value: .bounds) { [.title: $0] }
                // 条件のチップは表示名の真下に重ねる（下の `overlayPreferenceValue`）。重ねる分の高さだけ空けて、
                // 表示名＋チップの組が行の中央に来るようにする。
                .padding(.bottom, showsChip ? Self.chipHeight : 0)
                .layoutPriority(1)
            Spacer(minLength: 0)
            status
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(surface.headerInk)
                .anchorPreference(key: HeaderFramesKey.self, value: .bounds) { [.status: $0] }
            // 並びはここで固定する: 役の早見表 → ？ → 新規（通常の枠 `GameChromeToolbar` と同じ）。
            HStack(spacing: Metrics.headerSpacing) {
                if let reference {
                    FullScreenHeaderButton(systemImage: "list.bullet.rectangle", label: reference.accessibilityLabel,
                                           surface: surface, action: reference.action)
                }
                if let howToPlay {
                    FullScreenHeaderButton(systemImage: "questionmark.circle", label: tr("遊び方"),
                                           surface: surface, action: howToPlay.present)
                }
                if let newGame {
                    FullScreenHeaderButton(systemImage: newGame.kind.systemImage, label: newGame.kind.accessibilityLabel,
                                           surface: surface) { newGame.tapped { confirmsNewGame = true } }
                        .disabled(newGame.isDisabled)
                }
            }
            .anchorPreference(key: HeaderFramesKey.self, value: .bounds) { [.buttons: $0] }
        }
        .modifier(GameChromeNewGameConfirmation(newGame: newGame, isPresented: $confirmsNewGame))
        .padding(.horizontal, Metrics.sideInset)
        .padding(.vertical, Metrics.headerVerticalPadding)
        .frame(height: Metrics.headerTotalHeight)
        // 条件のチップ: 行の配置には関わらせず（札・ボタンを押し出さない）、表示名の下から「札またはボタンの手前」までの
        // 幅に、全文 → 難易度だけ → 出さない、の順で収める。得点の札の数字を必ず優先する（会長決裁 2026-10-25）。
        .overlayPreferenceValue(HeaderFramesKey.self) { frames in
            GeometryReader { proxy in
                if showsChip, let condition, let titleAnchor = frames[.title] {
                    let title = proxy[titleAnchor]
                    let right = [frames[.status], frames[.buttons]].compactMap { $0 }.map { proxy[$0].minX }.min()
                        ?? proxy.size.width
                    let available = max(0, right - Metrics.headerSpacing - title.minX)
                    ViewThatFits(in: .horizontal) {
                        GameConditionChip(text: condition.fullText, ink: surface.headerInk)
                        if condition.hasShortForm {
                            GameConditionChip(text: condition.shortText, ink: surface.headerInk)
                        }
                        Color.clear.frame(width: 0, height: 0)
                    }
                    .shadow(color: surface == .felt ? .black.opacity(0.35) : .clear, radius: 2, y: 1)
                    .frame(width: available, alignment: .leading)
                    .offset(x: title.minX, y: title.maxY)
                }
            }
        }
    }

    /// 条件のチップの高さ（12pt の文字 + 上下の余白。`GameConditionChip` の `minHeight` と同じ）。
    private static var chipHeight: CGFloat { 16 }
}

/// ヘッダーの部品の枠（チップの置き場の幅を測る）。
private struct HeaderFramesKey: PreferenceKey {
    enum Part: Hashable { case title, status, buttons }
    static var defaultValue: [Part: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Part: Anchor<CGRect>], nextValue: () -> [Part: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// ヘッダーの丸ボタン（44pt）。当たり判定は丸の中に取る（枠の外へはみ出させても Button は反応しない・#711）。
/// 押せないときは面を薄くする（通常の枠の `.disabled` と同じく見た目に出す）。
private struct FullScreenHeaderButton: View {
    typealias Metrics = FullScreenGameLayoutMetrics

    let systemImage: String
    let label: String
    let surface: FullScreenGameSurface
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .scaledFont(18, weight: .semibold, maxScale: 1.3)
                .foregroundStyle(surface.buttonInk)
                .frame(width: Metrics.headerHeight, height: Metrics.headerHeight)
                .background(
                    Circle()
                        .fill(surface.buttonFill)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                )
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.pop)
        .accessibilityLabel(label)
    }
}
