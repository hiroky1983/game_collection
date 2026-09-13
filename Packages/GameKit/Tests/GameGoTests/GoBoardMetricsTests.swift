import Testing
import CoreGraphics
import Core
@testable import GameGo

/// 縁の石が盤からはみ出さないこと（会長 QA 2026-09-13「囲碁の石の端っこがはみ出る」）。
@Suite("碁盤の余白")
struct GoBoardMetricsTests {
    /// iPhone SE（375 − 余白 32）・iPhone 17 Pro Max（393 − 32）・iPad。
    static let widths: [CGFloat] = [343, 361, 700]

    @Test("縁の石は落ち影まで含めて盤の角丸の内側に収まる", arguments: GoBoardSize.allCases, widths)
    func edgeStonesStayInside(size: GoBoardSize, width: CGFloat) {
        let pad = GoBoardMetrics.pad(boardWidth: width, size: size.rawValue)
        let s = GoBoardMetrics.spacing(boardWidth: width, size: size.rawValue)
        let reach = s * (GoBoardMetrics.stoneRadiusRatio + GoBoardMetrics.shadowReachRatio)
        #expect(pad >= reach, "\(size.label) 幅 \(width): 余白 \(pad) < 石と影 \(reach)")
        // 角の石: 角丸（半径 c）の内側にあるか。余白が c より狭いときだけ弧が最寄りの縁になる
        let c = Theme.corner
        let r = s * GoBoardMetrics.stoneRadiusRatio
        if pad < c {
            let toArcCenter = (c - pad) * 2.0.squareRoot()
            #expect(toArcCenter + r <= c, "\(size.label) 幅 \(width): 角の石が角丸を越える")
        }
    }

    @Test("余白と間隔は盤の幅をちょうど使い切る（タップの座標変換と描画が同じ格子）", arguments: GoBoardSize.allCases, widths)
    func gridFillsBoard(size: GoBoardSize, width: CGFloat) {
        let pad = GoBoardMetrics.pad(boardWidth: width, size: size.rawValue)
        let s = GoBoardMetrics.spacing(boardWidth: width, size: size.rawValue)
        #expect(abs(pad * 2 + s * CGFloat(size.rawValue - 1) - width) < 0.001)
        #expect(pad >= GoBoardMetrics.minPad)
    }

    @Test("9 路は余白が広がり、13 路は従来の 18pt とほぼ同じ（見た目を無闇に変えない）")
    func onlySmallBoardsGrow() {
        #expect(GoBoardMetrics.pad(boardWidth: 361, size: 9) > 24)
        let pad13 = GoBoardMetrics.pad(boardWidth: 361, size: 13)
        #expect(pad13 >= GoBoardMetrics.minPad && pad13 < 19.5, "13 路の余白 \(pad13)")
    }
}
