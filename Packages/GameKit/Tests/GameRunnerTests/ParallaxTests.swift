import Testing
@testable import GameRunner

/// 雲・丘の無限スクロール（#921）。折り返しで画面左に空白が出ないこと。
@Suite("背景の無限スクロール")
struct ParallaxTests {
    /// 丘: 6 枚 × 間隔 60、各タイルは左端原点で幅 78（奥の丘 dx 8 + 幅 42、手前 dx 22 + 34 …右端は 78）。
    /// 左端の空白を出さないには、覆う範囲の左端が 0 以下であること。丘の絵は dx 8 から始まるので
    /// タイル幅は「8 を引いた 70」で見る（保守的）。
    @Test("丘のタイルは距離 0〜20,000 のどこでも画面 [0, 幅] を隙間なく覆う")
    func hillsCoverTheScreenAtEveryDistance() {
        let width = RunnerField.Metrics.width
        for step in 0..<4000 {
            let distance = Double(step) * 5.0
            #expect(RunnerParallax.covers(width: width, tileWidth: 70, spacing: 60, count: 6,
                                          parallax: 0.55, distance: distance),
                    "距離 \(distance) で丘に空白")
        }
    }

    @Test("以前の折り返し（[0, 全幅)）では空白が出る（回帰の目安）")
    func oldWrapLeavesAGap() {
        // 2 間隔ぶんのずらしを打ち消すと、折り返し直前に左端が空く距離が存在する。
        let width = RunnerField.Metrics.width
        var gapSeen = false
        for step in 0..<4000 where !gapSeen {
            let distance = Double(step) * 5.0
            let xs = (0..<6).map {
                RunnerParallax.wrappedX(base: Double($0) * 60, distance: distance, parallax: 0.55, spacing: 60, count: 6) + 120
            }
            let minX = xs.min()!
            if minX + 8 > 0 && minX + 8 < width { gapSeen = true }
        }
        #expect(gapSeen)
    }

    /// 雲は隙間を埋める帯ではなく点在するので「覆う」検査は当たらない。代わりに、`buildClouds` と同じ
    /// 8 個・間隔 46・視差 0.3 で、どの距離でも「画面の左の外に 1 つ以上・右端を越えて 1 つ以上」
    /// あること（雲の列が画面を跨いで途切れない）を固定する。
    @Test("雲の列はどの距離でも画面を跨いで途切れない（左の外と右の外に必ず 1 つずつ）")
    func cloudsSpanTheScreenAtEveryDistance() {
        let width = RunnerField.Metrics.width
        let spacing = 46.0, count = 8
        for step in 0..<4000 {
            let distance = Double(step) * 5.0
            let xs = (0..<count).map {
                RunnerParallax.wrappedX(base: Double($0) * spacing, distance: distance, parallax: 0.3,
                                        spacing: spacing, count: count)
            }
            #expect(xs.min()! < 0, "距離 \(distance) で左の外に雲が無い")
            #expect(xs.max()! >= width, "距離 \(distance) で右端を越える雲が無い")
            // 隣どうしは 1 間隔（列が崩れていない）
            let sorted = xs.sorted()
            for i in 1..<sorted.count { #expect(abs((sorted[i] - sorted[i - 1]) - spacing) < 0.001) }
        }
    }

    @Test("折り返した x は [−2 間隔, 全幅 − 2 間隔) に収まる")
    func wrappedRange() {
        for step in 0..<2000 {
            let distance = Double(step) * 3.3
            for i in 0..<6 {
                let x = RunnerParallax.wrappedX(base: Double(i) * 60, distance: distance, parallax: 0.55, spacing: 60, count: 6)
                #expect(x >= -120 && x < 240)
            }
        }
    }
}
