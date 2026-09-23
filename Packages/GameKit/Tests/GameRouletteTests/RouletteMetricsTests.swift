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

    @Test("操作ボタンとチップ選択の高さは 44pt 以上")
    func buttonsMeetTapTarget() {
        #expect(Metrics.minimumTapTarget >= 44)
        #expect(Metrics.actionButtonMinHeight >= 44)
        #expect(Metrics.chipButtonSize >= 44)
    }

    @Test("盤面のマスは 4 段 × 9 列 + 0 で 37 個が 1 画面に収まる高さ")
    func boardFitsOnOneScreen() {
        // 4 段 + 区分 2 段 + 間隔で 250pt 以内（iPhone SE でホイール・操作欄・バナーと同居できる目安）。
        let board = Metrics.numberCellHeight * 4 + Metrics.outsideCellHeight * 2 + Metrics.cellSpacing * 5
        #expect(board <= 250)
        #expect(Metrics.numberCellHeight >= 30, "数字が読める最低限の高さ")
        #expect(Metrics.outsideCellHeight >= Metrics.numberCellHeight)
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

    @Test("チップ選択と盤面のマスも定数で組まれている")
    func chipsAndCellsAreWiredToTheMetrics() throws {
        let view = try Self.viewSource()
        let chip = SourceScan.functionSource(startingWith: "private func chipButton(", in: view)
        #expect(SourceScan.matchCount(of: #"RouletteMetrics\.chipButtonSize"#, in: chip) == 2, "直径と高さの両方")
        let cell = SourceScan.functionSource(startingWith: "private func betCell(", in: view)
        #expect(SourceScan.matchCount(of: #"\.buttonStyle\(\.pop\)"#, in: cell) == 1)
        #expect(SourceScan.matchCount(of: #"RouletteMetrics\.numberCellHeight"#, in: view) >= 2, "0 と 1〜36 の両方")
        #expect(SourceScan.matchCount(of: #"RouletteMetrics\.outsideCellHeight"#, in: view) == 2, "区分と赤黒などの 2 段")
        #expect(SourceScan.matchCount(of: #"RouletteMetrics\.wheelDiameter"#, in: view) == 2, "幅と高さ")
    }

    @Test("盤面は 0 + 1〜36 の 37 マスと区分 3 + 赤黒など 6 の 9 マスで組まれている")
    func boardEnumeratesEveryBet() throws {
        let board = SourceScan.functionSource(startingWith: "private var boardCard:", in: try Self.viewSource())
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
