import Testing
import CoreGraphics
import Foundation
import GameKitTestSupport
@testable import GameRoulette

/// ルーレットの操作まわりの寸法（#1318）。定数と View 側の結線の両方を見る
/// （ブラックジャックの `BlackjackMetricsTests`・#709 と同じやり方）。
@Suite("ルーレットの操作まわりの寸法")
struct RouletteMetricsTests {

    typealias Metrics = RouletteMetrics

    /// iPhone SE（第 3 世代）で中身に使える高さ（667 − ステータスバー 20 − ナビゲーションバー 44）。
    private static let seContentHeight: CGFloat = 603

    @Test("操作ボタンとチップ選択の高さは 44pt 以上")
    func buttonsMeetTapTarget() {
        #expect(Metrics.minimumTapTarget >= 44)
        #expect(Metrics.actionButtonMinHeight >= 44)
        #expect(Metrics.chipButtonSize >= 44)
    }

    @Test("縦が狭ければ詰めた寸法、そうでなければ通常の寸法")
    func sizingFollowsHeight() {
        #expect(Metrics.sizing(forHeight: Self.seContentHeight) == .compact, "iPhone SE")
        #expect(Metrics.sizing(forHeight: 687) == .compact, "iPhone 13 mini（通常の寸法は 681pt 要るので詰める側）")
        #expect(Metrics.sizing(forHeight: 715) == .regular, "iPhone 17")
        #expect(Metrics.sizing(forHeight: Metrics.compactHeightThreshold) == .regular)
        #expect(Metrics.sizing(forHeight: Metrics.compactHeightThreshold - 1) == .compact)
        #expect(Metrics.Sizing.compact.wheelDiameter < Metrics.Sizing.regular.wheelDiameter)
        #expect(Metrics.Sizing.compact.numberCellHeight < Metrics.Sizing.regular.numberCellHeight)
    }

    /// 画面の中身の高さの見積もり（初回ガイドの 1 行とバナーを含む・いちばん高くなる賭け中の局面）。
    /// VStack の子は tableCard / boardCard / HowToPlayHint / 操作欄 / Spacer / RecommendationSlot / BannerSlot の 7 つで、
    /// 間隔は 6 か所（Spacer と空の RecommendationSlot にも間隔は付く）。
    private static func estimatedHeight(_ sizing: Metrics.Sizing) -> CGFloat {
        let theme: CGFloat = 16                        // Theme.pad（上下）
        let table = sizing.wheelDiameter + sizing.cardVerticalPadding * 2
        let hint: CGFloat = 24
        let actions = Metrics.chipButtonSize + 8 + Metrics.actionButtonMinHeight + sizing.cardVerticalPadding * 2
        let banner: CGFloat = 50
        let gaps = sizing.stackSpacing * 6
        return theme * 2 + table + sizing.boardHeight + hint + actions + banner + gaps
    }

    /// チップが尽きた局面の見積もり。盤面は畳み、操作欄は見出し + 記録 + 復活 + やり直しの 4 段。
    private static func estimatedSessionOverHeight(_ sizing: Metrics.Sizing) -> CGFloat {
        let theme: CGFloat = 16
        let table = sizing.wheelDiameter + sizing.cardVerticalPadding * 2
        let hint: CGFloat = 24
        let sessionOver = 40 + 24 + 50 + 50 + 8 * 3 + sizing.cardVerticalPadding * 2
        let banner: CGFloat = 50
        let gaps = sizing.stackSpacing * 5             // 盤面が無いぶん 1 つ減る
        return theme * 2 + table + hint + sessionOver + banner + gaps
    }

    @Test("詰めた寸法なら iPhone SE の高さに、初回ガイドとバナーを含めて収まる")
    func compactSizingFitsIPhoneSE() {
        let compact = Self.estimatedHeight(.compact)
        #expect(compact <= Self.seContentHeight, "見積もり \(compact)pt が SE の \(Self.seContentHeight)pt を超えている")
        // 通常の寸法は SE には収まらない（だから詰める側が要る）。境目の意味を固定する。
        #expect(Self.estimatedHeight(.regular) > Self.seContentHeight)
        // 通常の寸法を選ぶ高さでは、通常の寸法が必ず収まる（境目を必要高さより下に置くと、そのあいだで溢れる）。
        #expect(Self.estimatedHeight(.regular) <= Metrics.compactHeightThreshold,
                "通常の寸法に \(Self.estimatedHeight(.regular))pt 要るのに境目が \(Metrics.compactHeightThreshold)pt")
    }

    @Test("チップが尽きた局面も、盤面を畳めば SE に収まる")
    func sessionOverFitsIPhoneSE() throws {
        let compact = Self.estimatedSessionOverHeight(.compact)
        #expect(compact <= Self.seContentHeight, "見積もり \(compact)pt が SE の \(Self.seContentHeight)pt を超えている")
        #expect(Self.estimatedSessionOverHeight(.regular) <= Metrics.compactHeightThreshold)
        // 畳んでいなければ賭け中より高くなって溢れる。畳む結線をソースで固定する。
        let view = try Self.viewSource()
        #expect(SourceScan.matchCount(of: #"if !model\.sessionOver \{\s*boardCard\(sizing\)"#, in: view) == 1,
                "チップが尽きたときに盤面を畳んでいない")
    }

    @Test("数字のマスは読める最低限の高さを保つ")
    func cellsStayLegible() {
        for sizing in [Metrics.Sizing.regular, .compact] {
            #expect(sizing.numberCellHeight >= 30)
            #expect(sizing.outsideCellHeight >= sizing.numberCellHeight)
            #expect(sizing.wheelDiameter >= 100)
        }
    }

    @Test("操作ボタンが実際に下限の定数で組まれている")
    func actionButtonIsWiredToTheMetric() throws {
        let button = SourceScan.functionSource(startingWith: "private func actionButton(", in: try Self.viewSource())
        #expect(!button.isEmpty, "actionButton の定義が見つからない")
        #expect(
            SourceScan.matchCount(of: #"minHeight:\s*RouletteMetrics\.actionButtonMinHeight"#, in: button) == 1,
            "actionButton が RouletteMetrics.actionButtonMinHeight を使っていない"
        )
        #expect(
            SourceScan.matchCount(of: #"\.buttonStyle\(\.pop\)"#, in: button) == 1,
            "actionButton が押下フィードバック付きの .pop になっていない"
        )
    }

    @Test("画面は高さを測って寸法を選び、チップ選択と盤面のマスも定数で組まれている")
    func chipsAndCellsAreWiredToTheMetrics() throws {
        let view = try Self.viewSource()
        #expect(SourceScan.matchCount(of: #"RouletteMetrics\.sizing\(forHeight: geometry\.size\.height\)"#, in: view) == 1,
                "高さから寸法を選んでいない")
        let chip = SourceScan.functionSource(startingWith: "private func chipButton(", in: view)
        #expect(SourceScan.matchCount(of: #"RouletteMetrics\.chipButtonSize"#, in: chip) == 2, "直径と高さの両方")
        let cell = SourceScan.functionSource(startingWith: "private func betCell(", in: view)
        #expect(SourceScan.matchCount(of: #"\.buttonStyle\(\.pop\)"#, in: cell) == 1)
        #expect(SourceScan.matchCount(of: #"sizing\.numberCellHeight"#, in: view) >= 2, "0 と 1〜36 の両方")
        #expect(SourceScan.matchCount(of: #"sizing\.outsideCellHeight"#, in: view) == 2, "区分と赤黒などの 2 段")
        #expect(SourceScan.matchCount(of: #"sizing\.wheelDiameter"#, in: view) == 2, "幅と高さ")
        // 固定 pt を直書きして寸法の束を迂回していない。
        #expect(SourceScan.matchCount(of: #"RouletteMetrics\.(numberCellHeight|outsideCellHeight|wheelDiameter)"#, in: view) == 0)
    }

    @Test("盤面は 0 + 1〜36 の 37 マスと区分 3 + 赤黒など 6 の 9 マスで組まれている")
    func boardEnumeratesEveryBet() throws {
        let board = SourceScan.functionSource(startingWith: "private func boardCard(", in: try Self.viewSource())
        #expect(board.contains("betCell(.straight(0)"))
        #expect(board.contains("ForEach(0..<4"))
        #expect(board.contains("ForEach(1...9"))
        #expect(board.contains("row * 9 + column"))
        #expect(board.contains("RouletteBetKind.dozens"))
        #expect(board.contains("RouletteBetKind.evenMoney"))
        #expect(RouletteBetKind.dozens.count + RouletteBetKind.evenMoney.count == 9)
    }

    private static func viewSource() throws -> String {
        try SourceScan.packageSource("Sources/GameRoulette/RouletteView.swift")
    }
}
