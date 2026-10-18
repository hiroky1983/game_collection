import Testing
import SwiftUI
@testable import GameDaifugo

/// 縦の狭い画面で固定 pt の中身が使える高さを超えないことを固定する（#2455）。
@Suite("大富豪: 縦の寸法")
struct DaifugoVerticalMetricsTests {
    typealias Metrics = DaifugoVerticalMetrics

    /// iPhone SE（第 3 世代）でナビバー下から画面下までの使える高さ。
    private static let seContentHeight: CGFloat = 593

    @Test("iPhone SE は詰める側、iPhone 17 は通常の側")
    func choosesBySize() {
        #expect(Metrics.metrics(forHeight: Self.seContentHeight) == .compact)
        #expect(Metrics.metrics(forHeight: 724) == .regular)
        #expect(Metrics.metrics(forHeight: Metrics.compactHeightThreshold) == .regular)
        #expect(Metrics.metrics(forHeight: Metrics.compactHeightThreshold - 1) == .compact)
    }

    @Test("詰めた寸法はミニガイド・案内込みでも iPhone SE の使える高さに収まる")
    func compactFitsSE() {
        #expect(Metrics.compact.estimatedMinimumHeight <= Self.seContentHeight)
    }

    @Test("通常の寸法が要る高さは境目より下（境目未満では詰める側に落ちる）")
    func regularNeedIsBelowThreshold() {
        #expect(Metrics.regular.estimatedMinimumHeight <= Metrics.compactHeightThreshold)
    }

    @Test("通常の寸法は従来値のまま（iPhone 17 の見た目を変えない）")
    func regularKeepsLegacyValues() {
        #expect(Metrics.regular.spacing == 8)
        #expect(Metrics.regular.pad == 16)
        #expect(Metrics.regular.seatVerticalPadding == 10)
        #expect(Metrics.regular.fieldVerticalPadding == 22)
        #expect(Metrics.regular.handVerticalPadding == 12)
    }
}
