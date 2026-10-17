import Testing
import CoreGraphics
import Foundation
import GameKitTestSupport
@testable import GameRoulette

/// ルーレットの操作まわりの寸法（#1318・#2364）。定数と View 側の結線の両方を見る
/// （ブラックジャックの `BlackjackMetricsTests`・#709 と同じやり方）。
@Suite("ルーレットの操作まわりの寸法")
struct RouletteMetricsTests {

    typealias Metrics = RouletteMetrics

    /// iPhone SE（第 3 世代）で中身に使える高さ（667 − ステータスバー 20 − ナビゲーションバー 44）。
    private static let seContentHeight: CGFloat = 603
    /// iPhone 17 Pro で中身に使える高さ（874 − ステータスバー 62 − ナビゲーションバー 54 − ホームバー 34）。
    private static let pro17ContentHeight: CGFloat = 724
    /// 中身の幅（画面幅 − `Theme.pad` × 2）。
    private static let seContentWidth: CGFloat = 375 - 32
    private static let pro17ContentWidth: CGFloat = 402 - 32

    private static let themePad: CGFloat = 16
    private static let hint: CGFloat = 24
    private static let banner: CGFloat = 50

    @Test("操作ボタンとチップ選択の高さは 44pt 以上")
    func buttonsMeetTapTarget() {
        #expect(Metrics.minimumTapTarget >= 44)
        #expect(Metrics.actionButtonMinHeight >= 44)
        #expect(Metrics.chipButtonSize >= 44)
        // 賭けの表のタブもボタン自体が 44pt 以上。外枠の余白はその外に足す（余白ぶん削って割らない）。
        #expect(Metrics.tabButtonHeight >= 44)
        #expect(Metrics.tabTrackHeight == Metrics.tabButtonHeight + Metrics.tabTrackInset * 2)
        // 「赤黒・区分」タブのマスは数字の表と同じ高さを 2 段で分け合うので 44pt を超える。
        for sizing in [Metrics.Sizing.regular, .compact] {
            #expect(sizing.outsideCellHeight >= 44)
        }
    }

    @Test("縦が狭ければ詰めた寸法、そうでなければ通常の寸法")
    func sizingFollowsHeight() {
        #expect(Metrics.sizing(forHeight: Self.seContentHeight) == .compact, "iPhone SE")
        #expect(Metrics.sizing(forHeight: 687) == .compact, "iPhone 13 mini")
        #expect(Metrics.sizing(forHeight: 715) == .regular, "iPhone 17")
        #expect(Metrics.sizing(forHeight: Self.pro17ContentHeight) == .regular, "iPhone 17 Pro")
        #expect(Metrics.sizing(forHeight: Metrics.compactHeightThreshold) == .regular)
        #expect(Metrics.sizing(forHeight: Metrics.compactHeightThreshold - 1) == .compact)
        #expect(Metrics.Sizing.compact.numberCellHeight < Metrics.Sizing.regular.numberCellHeight)
    }

    @Test("ホイールの直径は枠の短い辺。大きさ 0 や負の枠でも負にならない")
    func wheelDiameterFitsTheFrame() {
        #expect(Metrics.wheelDiameter(fitting: CGSize(width: 343, height: 200)) == 200)
        #expect(Metrics.wheelDiameter(fitting: CGSize(width: 300, height: 500)) == 300)
        #expect(Metrics.wheelDiameter(fitting: .zero) == 0)
        #expect(Metrics.wheelDiameter(fitting: CGSize(width: -10, height: 40)) == 0)
    }

    // MARK: - 見積もり

    /// 賭けの画面（案 A）でホイールに残る直径。VStack の子は ホイールのカード / 表 / 初回ガイド / 操作欄 /
    /// RecommendationSlot / BannerSlot の 6 つで、間隔は 5 か所（空の子にも間隔は付く）。
    private static func bettingWheel(height: CGFloat, width: CGFloat, hint showsHint: Bool) -> CGFloat {
        let sizing = Metrics.sizing(forHeight: height)
        let fixed = themePad * 2 + sizing.tableCardHeight + (showsHint ? hint : 0) + sizing.actionBarHeight
            + banner + sizing.stackSpacing * 5
        let card = height - fixed
        return Metrics.wheelDiameter(fitting: CGSize(width: width - Metrics.wheelCardPadding * 2,
                                                     height: card - Metrics.wheelCardChromeHeight))
    }

    /// ホイールの画面（案 B・回転中）でホイールに残る直径。上の札・ホイール・あなたの賭け（間隔 8）の束と、
    /// 初回ガイド / 「結果まで進める」 / RecommendationSlot / BannerSlot。
    private static func spinningWheel(height: CGFloat, width: CGFloat, hint showsHint: Bool) -> CGFloat {
        let sizing = Metrics.sizing(forHeight: height)
        let actions = Metrics.actionButtonMinHeight + sizing.cardVerticalPadding * 2
        let fixed = themePad * 2 + Metrics.wheelScreenStatsHeight + 8 + 8 + Metrics.betSummaryHeight
            + (showsHint ? hint : 0) + actions + banner + sizing.stackSpacing * 4
        return Metrics.wheelDiameter(fitting: CGSize(width: width, height: height - fixed))
    }

    /// チップが尽きた局面（ホイールの画面・あなたの賭けは畳む）。操作欄は見出し + 記録 + 復活 + やり直しの 4 段。
    private static func sessionOverWheel(height: CGFloat, width: CGFloat) -> CGFloat {
        let sizing = Metrics.sizing(forHeight: height)
        let sessionOver = 40 + 24 + 50 + 50 + 8 * 3 + sizing.cardVerticalPadding * 2
        let fixed = themePad * 2 + Metrics.wheelScreenStatsHeight + 8 + hint + sessionOver + banner
            + sizing.stackSpacing * 4
        return Metrics.wheelDiameter(fitting: CGSize(width: width, height: height - fixed))
    }

    @Test("賭けの画面は、初回ガイドが出ている SE でもホイールの最小の直径を保って収まる")
    func bettingScreenFitsIPhoneSE() {
        let se = Self.bettingWheel(height: Self.seContentHeight, width: Self.seContentWidth, hint: true)
        #expect(se >= Metrics.minimumBettingWheelDiameter, "SE の賭けの画面のホイールが \(se)pt")
        // 通常の寸法を選ぶいちばん低い高さ（境目）でも最小の直径を保つ（境目を必要高さより下に置くと溢れる）。
        let edge = Self.bettingWheel(height: Metrics.compactHeightThreshold, width: Self.pro17ContentWidth, hint: true)
        #expect(edge >= Metrics.minimumBettingWheelDiameter, "境目の高さで \(edge)pt")
        // 通常の寸法は SE には収まらない（だから詰める側が要る）。
        let regularOnSE = Self.seContentHeight - (Self.themePad * 2 + Metrics.Sizing.regular.tableCardHeight + Self.hint
            + Metrics.Sizing.regular.actionBarHeight + Self.banner + Metrics.Sizing.regular.stackSpacing * 5
            + Metrics.wheelCardChromeHeight)
        #expect(regularOnSE < Metrics.minimumBettingWheelDiameter)
    }

    @Test("ホイールは旧レイアウト（17 Pro 132pt / SE 104pt）より大きく、回すと画面いっぱいになる")
    func wheelIsTheStar() {
        let proBetting = Self.bettingWheel(height: Self.pro17ContentHeight, width: Self.pro17ContentWidth, hint: false)
        let seBetting = Self.bettingWheel(height: Self.seContentHeight, width: Self.seContentWidth, hint: false)
        #expect(proBetting >= 200, "17 Pro の賭けの画面 \(proBetting)pt")
        #expect(seBetting >= 120, "SE の賭けの画面 \(seBetting)pt")

        let proSpin = Self.spinningWheel(height: Self.pro17ContentHeight, width: Self.pro17ContentWidth, hint: false)
        let seSpin = Self.spinningWheel(height: Self.seContentHeight, width: Self.seContentWidth, hint: false)
        #expect(proSpin == Self.pro17ContentWidth, "17 Pro の回転中は幅いっぱい（\(proSpin)pt）")
        #expect(seSpin >= 270, "SE の回転中 \(seSpin)pt")
        // 回すと賭けの画面より必ず大きくなる（案 B の「ホイールが主役」）。
        #expect(proSpin > proBetting * 1.5)
        #expect(seSpin > seBetting * 1.8)
    }

    @Test("チップが尽きた局面も、あなたの賭けを畳めば SE でホイールが残る")
    func sessionOverFitsIPhoneSE() throws {
        let se = Self.sessionOverWheel(height: Self.seContentHeight, width: Self.seContentWidth)
        #expect(se >= 150, "SE のチップ切れの画面のホイールが \(se)pt")
        let view = try Self.viewSource()
        #expect(SourceScan.matchCount(of: #"if !model\.sessionOver \{\s*betSummaryCard"#, in: view) == 1,
                "チップが尽きたときにあなたの賭けを畳んでいない")
    }

    @Test("数字のマスは読める最低限の高さを保つ")
    func cellsStayLegible() {
        for sizing in [Metrics.Sizing.regular, .compact] {
            #expect(sizing.numberCellHeight >= 30)
            #expect(sizing.tableCardHeight >= Metrics.tabTrackHeight + sizing.tableContentHeight,
                    "表のカードの見積もりにタブの外枠（ボタン 44pt + 余白）が入っていない")
        }
    }

    // MARK: - 結線

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

    @Test("操作欄は 1 段目にチップ額 4 つ + 戻す、2 段目にスピンを全幅") @MainActor
    func actionBarHasTwoRows() throws {
        let betting = SourceScan.functionSource(startingWith: "private func bettingView(", in: try Self.viewSource())
        let chips = try #require(betting.range(of: "chipButton(amount)"))
        let undo = try #require(betting.range(of: "tr(\"戻す\")"))
        let spin = try #require(betting.range(of: "tr(\"スピン\")"))
        #expect(chips.lowerBound < undo.lowerBound && undo.lowerBound < spin.lowerBound)
        // 戻すはチップ額と同じ HStack、スピンはその外（VStack の 2 段目）。
        let firstRow = betting[betting.range(of: "HStack(spacing: 8) {")!.lowerBound..<spin.lowerBound]
        #expect(firstRow.contains("chipButton(amount)") && firstRow.contains("tr(\"戻す\")"))
        #expect(SourceScan.matchCount(of: #"RouletteMetrics\.actionRowSpacing"#, in: betting) == 1)
        #expect(RouletteModel.chipOptions.count == 4)
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
        #expect(SourceScan.matchCount(of: #"sizing\.numberCellHeight"#, in: view) >= 2, "0 の幅と 1〜36")
        #expect(SourceScan.matchCount(of: #"sizing\.outsideCellHeight"#, in: view) == 2, "区分と赤黒などの 2 段")
        // タブのボタンは 44pt の定数をそのまま高さの下限にする（余白を引かない）。
        let tabs = SourceScan.functionSource(startingWith: "private var betTabs", in: view)
        #expect(SourceScan.matchCount(of: #"minHeight:\s*RouletteMetrics\.tabButtonHeight\)"#, in: tabs) == 1)
        #expect(SourceScan.matchCount(of: #"tabButtonHeight\s*-"#, in: view) == 0, "タップ領域を余白ぶん削っている")
        #expect(SourceScan.matchCount(of: #"\.padding\(inset\)"#, in: tabs) == 1, "余白はボタンの外側")
        // ホイールは固定の直径ではなく、枠から測った直径で描く。
        #expect(SourceScan.matchCount(of: #"RouletteMetrics\.wheelDiameter\(fitting: proxy\.size\)"#, in: view) == 1)
    }

    @Test("賭けの表は 0 + 1〜36 の 37 マスと区分 3 + 赤黒など 6 の 9 マスを 2 つのタブに分けて組む")
    func boardEnumeratesEveryBet() throws {
        let view = try Self.viewSource()
        let numbers = SourceScan.functionSource(startingWith: "private func numberGrid(", in: view)
        #expect(numbers.contains("betCell(.straight(0)"))
        #expect(numbers.contains("ForEach(0..<4"))
        #expect(numbers.contains("ForEach(1...9"))
        #expect(numbers.contains("row * 9 + column"))
        let outside = SourceScan.functionSource(startingWith: "private func outsideGrid(", in: view)
        #expect(outside.contains("RouletteBetKind.dozens"))
        #expect(outside.contains("RouletteBetKind.evenMoney"))
        #expect(RouletteBetKind.dozens.count + RouletteBetKind.evenMoney.count == 9)
        let table = SourceScan.functionSource(startingWith: "private func tableCard(", in: view)
        #expect(table.contains("case .numbers: numberGrid(sizing)"))
        #expect(table.contains("case .outside: outsideGrid(sizing)"))
        #expect(table.contains("sizing.tableContentHeight"), "2 つのタブで高さをそろえる")
    }

    private static func viewSource() throws -> String {
        try SourceScan.packageSource("Sources/GameRoulette/RouletteView.swift")
    }
}
