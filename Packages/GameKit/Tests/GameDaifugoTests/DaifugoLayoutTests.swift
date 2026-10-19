import Testing
import SwiftUI
import Core
import GameKitTestSupport
@testable import GameDaifugo

/// レイアウトパターン A（全画面・#2531）での大富豪の寸法。手札の札・タップ判定・SE での収まりを値で固定する。
///
/// 手札は `GridItem(.flexible())` の 7 列なので、実効幅は端末の画面幅で決まる。
/// 「シミュレータで見たら足りていた」では**最小構成の端末で割る**ことを防げないため、寸法の計算そのものを押さえる
/// （#195 のタップ判定・#2455 の SE の高さの再発防止）。
@Suite("大富豪: 全画面（A）の寸法")
struct DaifugoLayoutTests {
    typealias Layout = DaifugoLayoutA

    /// 検証する画面幅。iOS 17 の対応端末で最も狭いのは 375pt（iPhone SE 第2/第3世代・iPhone 8）。
    private static let screenWidths: [(name: String, width: CGFloat)] = [
        ("iPhone SE (375pt)", 375),
        ("iPhone 15 (393pt)", 393),
        ("iPhone 17 (402pt)", 402),
        ("iPhone 17 Pro Max (440pt)", 440),
    ]

    /// iPhone SE（第 3 世代）でヘッダーの下からバナーの帯の上までの使える高さ（全画面の枠）。
    private static let seContentHeight = FullScreenGameLayoutMetrics.contentHeight(screenHeight: 667, safeAreaTop: 20, safeAreaBottom: 0)

    @Test("対応する最小の端末幅でもタップ判定（列幅）が 44pt 以上ある")
    func tapTargetMeetsMinimumOnAllWidths() {
        for (name, width) in Self.screenWidths {
            let tap = DaifugoHandLayout.tapWidth(screenWidth: width)
            #expect(tap >= DaifugoHandLayout.minimumTapTarget, "\(name) でタップ判定が \(tap)pt しかなく 44pt を下回る")
        }
    }

    @Test("札は列幅 − 4pt で、SE でも札そのものが 44pt を超える（モックの実測: SE 47.3 / iPhone 17 51.1）")
    func cardFillsTheColumn() {
        for (name, width) in Self.screenWidths {
            let tap = DaifugoHandLayout.tapWidth(screenWidth: width)
            let card = DaifugoHandLayout.cardWidth(screenWidth: width)
            #expect(abs(tap - card - Layout.handGap) < 0.01, "\(name) で札が列幅 − 4pt になっていない（\(card) / \(tap)）")
            #expect(card >= DaifugoHandLayout.minimumTapTarget, "\(name) で札が \(card)pt しかない")
        }
        #expect(abs(DaifugoHandLayout.cardWidth(screenWidth: 375) - 47.29) < 0.01)
        #expect(abs(DaifugoHandLayout.cardWidth(screenWidth: 402) - 51.14) < 0.01)
    }

    @Test("場の札は手札と同じ倍率で、席の裏向きの札は 20 / 24pt")
    func fieldAndSeatCards() {
        let se = Layout.metrics(screenWidth: 375)
        let ip17 = Layout.metrics(screenWidth: 402)
        let scaleSE = se.handCard.width / PlayingCardMetrics.compact.width
        #expect(abs(se.fieldCard.width - PlayingCardMetrics.medium.width * scaleSE) < 0.01)
        #expect(se.fieldCard.height > se.handCard.height, "場の札は手札より大きい")
        #expect(se.seatDiameter == 44 && ip17.seatDiameter == 56)
        #expect(se.seatCardMetrics.width == 20 && ip17.seatCardMetrics.width == 24)
    }

    @Test("広い画面（iPad）では札の拡大に上限が掛かる（列幅いっぱいにしない）")
    func wideScreenCapsTheScale() {
        let ipad = Layout.metrics(screenWidth: 1024, elementScale: 1.5)
        #expect(ipad.handCard.width == PlayingCardMetrics.compact.width * Layout.maxCardScale * 1.5)
        #expect(ipad.handCard.width < Layout.columnWidth(screenWidth: 1024) - Layout.handGap)
        // iPhone では上限に届かない（列幅で決まる）。
        #expect(Layout.cardScale(screenWidth: 440) < Layout.maxCardScale)
        #expect(Layout.cardScale(screenWidth: 0) == 0, "幅が測れる前（0）でも負にならない")
    }

    @Test("配った直後（手札 2 段）でも、ミニガイドと案内込みで iPhone SE の使える高さに収まる（#2455 の再発防止）")
    func fitsIPhoneSE() {
        #expect(Self.seContentHeight == 537)
        #expect(Layout.estimatedMinimumHeight(screenWidth: 375) <= Self.seContentHeight)
        #expect(Layout.estimatedMinimumHeight(screenWidth: 402)
                <= FullScreenGameLayoutMetrics.contentHeight(screenHeight: 874, safeAreaTop: 62, safeAreaBottom: 34))
    }

    @Test("寸法の前提（7列・列間 0・左右 8pt）が変わったら気付けるようにする")
    func layoutConstants() {
        #expect(DaifugoHandLayout.columns == 7)
        #expect(DaifugoHandLayout.columnSpacing == 0)
        #expect(DaifugoHandLayout.minimumTapTarget == 44)
        #expect(Layout.sideInset == FullScreenGameLayoutMetrics.sideInset)
        #expect(Layout.handGap == 4)
    }

    // MARK: - 画面の組み方（ソース走査）

    private static var source: String {
        get throws { SourceScan.strippingComments(try SourceScan.moduleSources("GameDaifugo")) }
    }

    @Test("全画面の枠を 1 回通し、バナー・卓はゲーム側に置かない")
    func usesFullScreenChrome() throws {
        let source = try Self.source
        #expect(source.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(source.contains("fullScreen: .felt, ads: services.ads"))
        #expect(!source.contains("BannerSlot("), "バナーを枠と二重に置いている")
        #expect(!source.contains(".cardTable("), "全画面のフェルトの上に卓を二重に敷いている")
        #expect(!source.contains("GameStatusBar {"), "ヘッダー下の帯が残っている（札はヘッダーの行へ）")
    }

    @Test("CPU の席は共通部品（いろリレーと同じ見せ方）で、読み上げは手番つきの席の文")
    func seatsUseTheSharedPart() throws {
        let source = try Self.source
        #expect(source.contains("OpponentSeat("), "相手の席を自前で組んでいる")
        #expect(source.contains("OpponentCardFan("), "裏向きの束を自前で組んでいる")
        #expect(source.contains("PlayingCardBack(metrics: back)"), "束の札がトランプの裏でない")
        #expect(source.contains("DaifugoAccessibility.seatLabel("), "席の読み上げ文（#2495）を渡していない")
        #expect(!source.contains(#"Image(systemName: "cpu")"#) || source.contains("fieldHeader"),
                "席の手番をアイコンの色で示す古い組み方が残っている")
    }

    @Test("出せない札はフェルトの上なので白を重ねて沈める（不透明度を落とさない）")
    func dimmingOnFelt() throws {
        let source = try Self.source
        let card = try #require(SourceScan.declaration(of: "struct DaifugoCardView", in: source))
        #expect(card.contains(".tableDimmed(isDimmed, cornerRadius: metrics.cornerRadius)"))
        #expect(!card.contains(".opacity(isDimmed"), "不透明度で沈める古い組み方が残っている（フェルトで緑に濁る）")
    }

    @Test("ヘッダーの札は幅が足りなければゲーム数を落とし、手番の札は残す")
    func statusChipsShrink() throws {
        let source = try Self.source
        let chips = try #require(SourceScan.declaration(of: "private var statusChips", in: source))
        #expect(chips.contains("ViewThatFits(in: .horizontal)"))
        #expect(SourceScan.matchCount(of: "TurnBadge\\(turnLabel, kind: turnKind\\)", in: chips) == 2)
        #expect(SourceScan.matchCount(of: "gameCountLabel", in: chips) == 1, "短い形にもゲーム数が残っている")
    }
}
