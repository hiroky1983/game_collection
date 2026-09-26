import Testing
import Foundation
import CoreGraphics
import GameKitTestSupport
@testable import GameFreeCell

/// 拡大モード（会長QA #595 の項目10 = #604）。
///
/// フリーセルは**横に 8 列**が絶対条件で、画面幅から札の幅が決まる。等倍では iPhone の
/// どの幅でも HIG の最小タップ標的 44pt に届かないため、ナンプレ（#262）・マインスイーパー
/// （#203）と同じく**拡大モードを用意してそちらで 44pt を満たす**。等倍は盤全体を一望できる
/// 性質を守るためそのまま残す。
///
/// 見た目そのものはシミュレータでしか確認できないので、**寸法の算術**と**ソース**の
/// 2 方向から固定する（`FreeCellTopRowTests` と同じ形）。
@Suite("フリーセルの拡大モード")
struct FreeCellZoomTests {

    typealias Metrics = FreeCellMetrics

    /// 画面幅から盤の左右の余白（`boardSideInset` 4pt。以前は `Theme.pad` 16pt）を引いた、盤に使える幅。
    private static func contentWidth(screenWidth: CGFloat) -> CGFloat {
        screenWidth - Metrics.boardSideInset * 2
    }

    /// 対象にしている iPhone の論理幅。いちばん狭いのが iPhone SE の 375pt。
    private static let phoneWidths: [CGFloat] = [375, 393, 402, 430, 440]

    /// 等倍では 44pt に届かない幅。**Issue 本文の「iPhone では届かない」は全機種の話ではない**。
    /// 盤の左右の余白を 16pt → 4pt・列の間隔を 4pt → 3pt に詰めてから（札が小さすぎる問題の試作）は、
    /// 381pt で等倍がちょうど 44pt になり、届かないのは iPhone SE（375pt）だけになった
    /// （以前の境目は 412pt）。
    private static let narrowPhoneWidths: [CGFloat] = [375]

    // MARK: - 寸法

    @Test("標準幅までの iPhone は等倍で 44pt に届かない（拡大モードが要る根拠）",
          arguments: narrowPhoneWidths)
    func theFittedWidthMissesTheTapTargetOnNarrowPhones(_ screenWidth: CGFloat) {
        let card = Metrics.cardWidth(availableWidth: Self.contentWidth(screenWidth: screenWidth))
        #expect(card < Metrics.minimumTapTarget,
                "等倍で 44pt に届いているなら、この画面幅では拡大モードの根拠が無い（\(card)pt）")
    }

    /// 「届かない」の境目を数値で固定する。ここがずれると `narrowPhoneWidths` の分け方も変わる。
    @Test("等倍が 44pt に届く境目は画面幅 381pt")
    func theFittedWidthReachesTheTapTargetAt381() {
        #expect(Metrics.cardWidth(availableWidth: Self.contentWidth(screenWidth: 381))
                == Metrics.minimumTapTarget)
        #expect(Metrics.cardWidth(availableWidth: Self.contentWidth(screenWidth: 380))
                < Metrics.minimumTapTarget)
    }

    @Test("拡大するとどの iPhone でも札が 44pt 以上になる", arguments: phoneWidths)
    func theZoomedWidthClearsTheTapTarget(_ screenWidth: CGFloat) {
        let card = Metrics.zoomedCardWidth(availableWidth: Self.contentWidth(screenWidth: screenWidth))
        #expect(card >= Metrics.minimumTapTarget, "拡大しても 44pt に届いていない（\(card)pt）")
    }

    /// 44pt はあくまで**下限**で、44pt へ引き上げるだけでは iPhone 17 Pro で差が 1.25pt しか
    /// 出ない（等倍 42.75pt）。会長の申告「操作しにくい」を解くには、一望性を捨てた分だけ
    /// 大きくならなければ意味が無い。
    @Test("拡大は等倍より 3 割以上大きい（44pt へ切り上げるだけでは足りない）",
          arguments: phoneWidths)
    func theZoomedWidthIsSubstantiallyLargerThanFitted(_ screenWidth: CGFloat) {
        let available = Self.contentWidth(screenWidth: screenWidth)
        let fitted = Metrics.cardWidth(availableWidth: available)
        let zoomed = Metrics.zoomedCardWidth(availableWidth: available)
        #expect(zoomed / fitted >= 1.3, "拡大率が \(zoomed / fitted) 倍しかない")
    }

    /// 画面幅・等倍・拡大の実測値。iPhone SE と iPhone 17 Pro（Issue 本文の時点では 42.75pt だった）。
    /// 盤の余白 4pt × 2・列の間隔 3pt での値。
    static let measured: [(screen: CGFloat, fitted: CGFloat, zoomed: CGFloat)] = [
        (375, 43.25, 352.0 / 6),
        (402, 46.625, 379.0 / 6),
    ]

    @Test("狭い画面ぴったりの実測値", arguments: measured)
    func measuredWidths(_ row: (screen: CGFloat, fitted: CGFloat, zoomed: CGFloat)) {
        let available = Self.contentWidth(screenWidth: row.screen)
        #expect(Metrics.cardWidth(availableWidth: available) == row.fitted)
        #expect(Metrics.zoomedCardWidth(availableWidth: available) == row.zoomed)
    }

    /// iPad では等倍のほうが 44pt より大きい。44pt や「6 列ぶん」へ**切り下げる**と
    /// 拡大モードが縮小モードになる（マインスイーパー `zoomedCellSize`・麻雀ソリティア
    /// `comfortableTileWidth` と同じ手当て）。
    @Test("広い画面では拡大が等倍を下回らない", arguments: [CGFloat(700), 900, 1024, 1366])
    func zoomingNeverShrinksTheCard(_ availableWidth: CGFloat) {
        let fitted = Metrics.cardWidth(availableWidth: availableWidth)
        let zoomed = Metrics.zoomedCardWidth(availableWidth: availableWidth)
        #expect(zoomed >= fitted, "拡大が縮小になっている（等倍 \(fitted)pt → 拡大 \(zoomed)pt）")
    }

    @Test("拡大でも札の幅の上限は等倍と同じ（広い画面で札だけが間延びしない）")
    func theZoomedWidthRespectsTheSameCeiling() {
        // 上限に張り付く広さ。6 列ぶんの生値（146.7pt）がそのまま通れば間延びする。
        let zoomed = Metrics.zoomedCardWidth(availableWidth: 900, maxWidth: Metrics.maxCardWidth)
        #expect(zoomed == Metrics.maxCardWidth)
    }

    @Test("上限の差し替え（iPad の倍率・#458）は拡大にも効く")
    func theCeilingOverrideAlsoAppliesWhenZoomed() {
        let zoomed = Metrics.zoomedCardWidth(availableWidth: 900, maxWidth: 88)
        #expect(zoomed == 88)
    }

    // MARK: - 当たり判定（ドロップ枠）が拡大後もズレないこと

    /// 上段（4 セル + 4 組札）と下段（8 列）は同じ 8 枠で、`boardWidth` に 1pt の余りも無い。
    /// この関係は**札の幅に依らず**成り立っていなければならない。崩れると、拡大したときに
    /// 上段の枠と下段の列が横にズレ、指を離した位置が隣の列のドロップ枠に入る。
    @Test("拡大後も 8 枠 + 隙間 7 つが盤の幅と一致する", arguments: phoneWidths)
    func slotsStillTileExactlyWhenZoomed(_ screenWidth: CGFloat) {
        let card = Metrics.zoomedCardWidth(availableWidth: Self.contentWidth(screenWidth: screenWidth))
        let row = card * 8 + Metrics.columnGap * 7
        #expect(row == Metrics.boardWidth(cardWidth: card))
    }

    @Test("拡大した盤は使える幅をはみ出す（横スクロールが要る）", arguments: phoneWidths)
    func theZoomedBoardOverflowsTheScreen(_ screenWidth: CGFloat) {
        let available = Self.contentWidth(screenWidth: screenWidth)
        let board = Metrics.boardWidth(cardWidth: Metrics.zoomedCardWidth(availableWidth: available))
        #expect(board > available, "はみ出さないなら拡大できていない（盤 \(board)pt ≦ 使える幅 \(available)pt）")
    }

    /// 8 列のうち `zoomedVisibleColumns` 列ぶんがちょうど画面に収まる設計。
    /// 収まる列数が減ると、はみ出す列が増えてスクロール量だけが伸びる。
    @Test("拡大後に画面へ収まる列数が設計どおり", arguments: phoneWidths)
    func theZoomedBoardShowsTheDesignedNumberOfColumns(_ screenWidth: CGFloat) {
        let available = Self.contentWidth(screenWidth: screenWidth)
        let card = Metrics.zoomedCardWidth(availableWidth: available)
        let visible = Metrics.boardWidth(cardWidth: card) <= available
            ? FreeCellBoard.pileCount
            : Int((available + Metrics.columnGap) / (card + Metrics.columnGap))
        #expect(visible == Metrics.zoomedVisibleColumns)
    }

    // MARK: - ソース（分岐が 1 か所であること）

    @Test("等倍と拡大の分岐は札の幅を決める 1 か所だけにある")
    func theZoomBranchLivesInExactlyOnePlace() throws {
        let source = SourceScan.strippingComments(try Self.viewSource())
        let branches = SourceScan.matchCount(of: #"zoomMode\s*\?"#, in: source)
        #expect(
            branches == Self.expectedZoomBranches,
            """
            拡大の分岐が \(branches) か所ある（想定 \(Self.expectedZoomBranches) か所: \
            札の幅・スクロール方向・「⋯」の拡大項目の読み上げのラベルとヒント）。\
            寸法の分岐を各所に撒くと、拡大したのに当たり判定だけ等倍のまま、という形のズレが生まれる
            """
        )
        let width = try #require(SourceScan.declaration(of: "private func cardWidth", in: source))
        #expect(SourceScan.strippingComments(width).contains("zoomMode"), "札の幅の分岐がここから消えている")
        #expect(width.contains("zoomedCardWidth"), "取り違え防止")
    }

    /// 札の幅・スクロール方向・「⋯」の拡大項目の読み上げのラベルとヒント（#1468）。
    private static let expectedZoomBranches = 4

    @Test("盤は 1 つの札幅から作った metrics を上段と場札へ配る")
    func theBoardFeedsOneMetricsToBothRows() throws {
        let source = try Self.viewSource()
        let block = try #require(SourceScan.declaration(of: "private var board:", in: source))
        let body = SourceScan.strippingComments(block)
        #expect(SourceScan.matchCount(of: #"let metrics = "#, in: body) == 1, "metrics が複数ある")
        #expect(body.contains("topRow(metrics: metrics)"))
        // 場札には段差（`stack`）も渡すが、札の寸法は上段と同じ `metrics`。
        #expect(body.contains("tableau(metrics: metrics, stack: stack)"))
        #expect(!body.contains("FreeCellMetrics.cardWidth("),
                "盤が等倍の幅を直接呼んでいる。拡大しても当たり判定が等倍のまま残る")
    }

    /// 帯には表示だけを置く（#1468）。拡大は右下の「⋯」のチェック付き項目にある。
    @Test("拡大は帯ではなく「⋯」メニューにある")
    func theToggleLivesInTheMenu() throws {
        let source = try Self.viewSource()
        let readout = try #require(SourceScan.declaration(of: "private var statusReadout:", in: source))
        #expect(readout.contains("children: .ignore"), "取り違え防止。畳んでいるのはこちら")

        let bar = try #require(SourceScan.declaration(of: "private var statusBar:", in: source))
        #expect(!SourceScan.strippingComments(bar).contains("Button"), "帯にボタンが戻っている")
        #expect(!bar.contains("BoardToggleButton"), "帯に切り替えボタンが戻っている")

        let controls = try #require(SourceScan.declaration(of: "private var gameControls:", in: source))
        #expect(controls.contains(#"id: "zoom""#) && controls.contains("zoomMode.toggle()"),
                "拡大が「⋯」から消えている")
    }

    // MARK: - ヘルパー

    private static func viewSource() throws -> String {
        try SourceScan.moduleSources("GameFreeCell")
    }
}
