import Foundation
import SwiftUI
import Testing
import Core
import GameKitTestSupport

/// レイアウトパターン A（全画面・バナー下・タイトルあり）の共通枠（#2531）。
///
/// ヘッダーの高さ・盤に残る高さの計算を値で固定し、枠の中身（ナビバーを出さない・バナーは最下部の帯・
/// 面は画面全体）がソースに残っていることを走査で見る。
@Suite("レイアウトパターン A の共通枠")
struct FullScreenGameChromeTests {
    typealias Metrics = FullScreenGameLayoutMetrics

    /// 端末の寸法（モック `docs/design/layout-patterns-2111/*/mock_generator.swift` と同じ値）。
    private static let iPhone17 = (height: CGFloat(874), safeTop: CGFloat(62), safeBottom: CGFloat(34))
    private static let iPhoneSE = (height: CGFloat(667), safeTop: CGFloat(20), safeBottom: CGFloat(0))

    @Test("ヘッダーは 44pt の行 + 上下 4pt = 52pt（iOS 26 のナビバー 54pt より低い）")
    func headerMetrics() {
        #expect(Metrics.headerHeight == 44)
        #expect(Metrics.headerVerticalPadding == 4)
        #expect(Metrics.headerTotalHeight == 52)
        #expect(Metrics.headerTotalHeight < 54)
        #expect(Metrics.headerSpacing == 8)
        #expect(Metrics.sideInset == 8)
    }

    @Test("バナーの帯は上の余白 8 + バナー 50 + 下の安全域")
    @MainActor
    func bannerBand() {
        #expect(Metrics.bannerHeight == BannerSlot.height, "寸法の写しが BannerSlot.height とずれている")
        #expect(Metrics.bannerTopPadding == 8)
        #expect(Metrics.bannerBandHeight(safeAreaBottom: 34) == 92)
        #expect(Metrics.bannerBandHeight(safeAreaBottom: 0) == 58)
        #expect(Metrics.bannerBandHeight(safeAreaBottom: -5) == 58, "負の安全域は 0 とみなす")
    }

    @Test("盤と操作の段に使える高さ: iPhone 17 は 668pt・iPhone SE は 537pt")
    func contentHeight() {
        let ip17 = Self.iPhone17, se = Self.iPhoneSE
        #expect(Metrics.contentHeight(screenHeight: ip17.height, safeAreaTop: ip17.safeTop, safeAreaBottom: ip17.safeBottom) == 668)
        #expect(Metrics.contentHeight(screenHeight: se.height, safeAreaTop: se.safeTop, safeAreaBottom: se.safeBottom) == 537)
        // 通常の枠（ナビバー 54 + ヘッダー下の帯 44 + 間隔 8 + 外周 16 × 2 + バナー 50）より 78pt 多く盤・操作の段に回る
        // （A はヘッダー 52 + バナーの帯 58 を引いた残り。SE で中身が溢れていた #2455 の超過 17〜30pt を吸収して余る）。
        let legacySE = se.height - se.safeTop - 54 - 44 - 8 - 16 * 2 - 50
        #expect(Metrics.contentHeight(screenHeight: se.height, safeAreaTop: se.safeTop, safeAreaBottom: se.safeBottom) - legacySE == 78)
        #expect(Metrics.contentHeight(screenHeight: 10, safeAreaTop: 62, safeAreaBottom: 34) == 0, "足りないときは負にしない")
    }

    @Test("盤に残る高さは、中身から固定の段とその数だけの間隔を引いた値")
    func boardHeight() {
        // 席 110 + 手札 175 + 操作の段 60 の 3 段・間隔 8 → SE では 537 − 345 − 24 = 168。
        #expect(Metrics.boardHeight(contentHeight: 537, fixedRows: [110, 175, 60], spacing: 8) == 168)
        #expect(Metrics.boardHeight(contentHeight: 668, fixedRows: [], spacing: 8) == 668, "固定の段が無ければ全部盤")
        #expect(Metrics.boardHeight(contentHeight: 100, fixedRows: [80, 40], spacing: 8) == 0, "足りないときは負にしない")
    }

    @Test("面: フェルトはヘッダーの文字を白に、地は墨に。卓の上の色もそれぞれ")
    func surfaces() {
        #expect(FullScreenGameSurface.felt != .plain)
        // フェルトの面は共通の卓（CardTableStyle）の色で、木枠なし・角丸なし。
        let felt = FullScreenGameSurface.feltOnly
        #expect(felt.insets(width: 393) == EdgeInsets())
        #expect(felt.cornerRadius == 0)
        #expect(felt.innerShadow == nil)
        #expect(felt.aspectRatio == nil)
        #expect(felt.dropShadow == false)
    }

    // MARK: - ソース走査

    private static var source: String {
        get throws { SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/FullScreenGameChrome.swift")) }
    }

    @Test("ナビバーは出さず、バナーは最下部の帯（safeAreaInset）、面は安全域の外まで敷く")
    func chromeInternals() throws {
        let source = try Self.source
        #expect(source.contains(".toolbar(.hidden, for: .navigationBar)"), "OS のナビバーが出たままになる")
        #expect(source.contains(".safeAreaInset(edge: .bottom, spacing: 0)"), "バナーが最下部の帯に無い")
        #expect(source.contains("BannerSlot(ads: ads)"), "共通のバナー枠を使っていない")
        #expect(source.contains("Theme.background.ignoresSafeArea(edges: .bottom)"), "帯が下の安全域まで地の色で埋まらない")
        #expect(source.contains("surfaceView.ignoresSafeArea()"), "面が安全域の外まで敷かれない")
        #expect(source.contains("if #available(iOS 26.0, *)"), "iOS 26 より前でステータスバーの文字がフェルトに埋もれる")
        #expect(source.contains("GameChromeBase(review: review, paintsBackground: false)"),
                "通常の枠の地の色が面の上に乗る（評価リクエスト・ボタン色の共通部分は通す）")
    }

    @Test("ヘッダー右の並びは通常の枠と同じ: 役の早見表 → ？ → 新規")
    func headerOrder() throws {
        let source = try Self.source
        let reference = try #require(source.range(of: "if let reference {"))
        let howToPlay = try #require(source.range(of: "if let howToPlay {", range: reference.upperBound..<source.endIndex))
        let newGame = try #require(source.range(of: "if let newGame {", range: howToPlay.upperBound..<source.endIndex))
        #expect(reference.lowerBound < howToPlay.lowerBound && howToPlay.lowerBound < newGame.lowerBound)
        #expect(source.contains(#"systemImage: "list.bullet.rectangle""#))
        #expect(source.contains(#"systemImage: "questionmark.circle""#))
        #expect(source.contains("newGame.kind.systemImage"), "新規の絵柄は GameChromeNewGame.Kind の 1 つ（#2370）")
    }

    @Test("ヘッダーのボタンは 44pt の丸で、当たり判定も丸の中。戻る・遊び方は読み上げ名を持つ")
    func headerButtons() throws {
        let source = try Self.source
        #expect(source.contains(".frame(width: Metrics.headerHeight, height: Metrics.headerHeight)"))
        #expect(source.contains(".contentShape(Circle())"))
        #expect(source.contains(".accessibilityLabel(label)"))
        #expect(source.contains(#"label: tr("戻る")"#))
        #expect(source.contains(#"label: tr("遊び方")"#))
    }

    @Test("表示名は 1 行で、長ければ縮む（iPhone SE で 1 行に収める）")
    func titleShrinks() throws {
        let source = try Self.source
        let title = try #require(source.range(of: "Text(title)"))
        let head = String(source[title.lowerBound...].prefix(600))
        #expect(head.contains(".lineLimit(1)"))
        #expect(head.contains(".minimumScaleFactor(0.6)"))
        #expect(head.contains(".layoutPriority(1)"), "表示名が札より先に幅をもらわないと、英語の題字が 0.6 倍まで縮む")
        #expect(head.contains("Spacer(minLength: 0)"), "表示名と札のあいだの余りを吸う Spacer が無い")
    }

    /// 通常の枠の走査（`GameChromeSourceTests`）は `.gameChrome(title:` の回数を数える。全画面の形も同じ接頭辞なので
    /// 1 回に数えられる（別名にすると「0 回」で落ちる）。
    @Test("全画面の枠も .gameChrome(title: の形で呼ぶ（走査の 1 回に数えられる）")
    func sameEntryPointPrefix() throws {
        let source = try Self.source
        #expect(SourceScan.matchCount(of: #"func gameChrome<Status: View>\(\s*title: String"#, in: source) == 1)
        #expect(source.contains("fullScreen surface: FullScreenGameSurface"))
    }

    /// 広告で補充するカプセル（#1897）の淡い塗りは、フェルトの上では緑に沈んで墨の文字が読めない。
    /// 枠が「フェルトの上か」を配り、カプセルがそれを読んで地の面を下に敷く。
    @Test("フェルトの上かを配り、広告のカプセルが地の面を敷く")
    func feltFlagReachesAdCapsule() throws {
        #expect(try Self.source.contains(".environment(\\.isOnTableFelt, surface == .felt)"))
        let capsule = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/GameActionRow.swift"))
        #expect(capsule.contains("@Environment(\\.isOnTableFelt)"))
        #expect(capsule.contains("isOnTableFelt ? Theme.surface"))
    }

    /// レイアウトパターン A に載せ替えたゲーム（#2531）。バナーは枠が最下部に置くので、ゲーム側に
    /// `BannerSlot` を書くと二重になる。いろリレー・大富豪はそれぞれのテストで見ている。
    @Test("A のゲームは全画面の枠にバナーの取得元を渡し、ゲーム側に BannerSlot を置かない", arguments: [
        "GameMahjongSolitaire", "GameFreeCell", "GameSolitaire",
    ])
    func fullScreenGamesLeaveBannerToChrome(module: String) throws {
        let code = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        #expect(code.contains("fullScreen: .felt, ads: services.ads"), "\(module) が全画面の枠にバナーの取得元を渡していない")
        #expect(!code.contains("BannerSlot("), "\(module) がバナーを枠と二重に置いている")
    }

    @Test("ヘッダー下の低い札（A の一人用）は 44pt の帯より低く、下限は残す")
    func compactStatusBar() {
        #expect(GameStatusBarStyle.compactMinHeight > 0)
        #expect(GameStatusBarStyle.compactMinHeight < GameStatusBarStyle.minHeight)
        #expect(GameStatusBarStyle.compactVerticalPadding <= GameStatusBarStyle.verticalPadding)
    }

    @Test("枠は MainActor の環境で組める（ヘッダー付きの中身が描ける）")
    @MainActor
    func renders() throws {
        let view = Color.clear
            .frame(height: 200)
            .gameChrome(title: "テスト", review: nil, fullScreen: .felt, ads: NoopAdService()) { Text("札") }
            .frame(width: 375, height: 400)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 375)
        #expect(image.height == 400)
    }
}
