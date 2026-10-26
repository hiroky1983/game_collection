import Testing
@testable import GameGomoku

/// 禁じ手の読み上げ文（#1574）。
@Suite("五目並べ: 読み上げ文")
struct GomokuAccessibilityTests {

    @Test("禁じ手で断ったときは、種類と禁じ手であることを読む", arguments: [
        (GomokuForbidden.doubleThree, "三三は打てません（禁じ手）"),
        (.doubleFour, "四四は打てません（禁じ手）"),
        (.overline, "長連は打てません（禁じ手）"),
    ])
    func forbiddenAnnouncement(reason: GomokuForbidden, expected: String) {
        #expect(GomokuAccessibility.forbiddenAnnouncement(reason: reason) == expected)
    }
}

/// CPU の着手の読み上げ（#2280）。
@MainActor
@Suite("五目並べ: CPU の着手の読み上げ")
struct GomokuCPUMoveAnnouncementTests {
    @Test("文言は 1 始まりの行列で読む")
    func text() {
        #expect(GomokuAccessibility.cpuMoveAnnouncement(row: 3, col: 4) == "CPUは4行5列に打ちました")
    }

    @Test("CPU が打った直後の鍵だけが控えられ、人間が打つと外れる")
    func keyTracksCPUMoveOnly() async throws {
        let model = GomokuModel(services: nil)
        model.newGame(humanSide: .white, aiLevel: 1) // CPU=黒(先手)
        #expect(model.lastCPUMoveKey == nil)
        await model.performAIMoveIfNeeded()
        #expect(model.lastCPUMoveKey == model.aiTurnKey)
        let (r, c) = try #require((0..<gomokuBoardSize).lazy.flatMap { r in (0..<gomokuBoardSize).map { (r, $0) } }
            .first { model.board[$0.0, $0.1] == nil })
        model.tap(row: r, col: c)
        #expect(model.lastCPUMoveKey != model.aiTurnKey)
    }
}

/// 結果カードの補足行（#2799）。
@Suite("五目並べ: 結果カードの補足行")
struct GomokuResultCardDetailsTests {
    @Test("五連で終わったときは手数と決め手を 1 始まりの行列で出す")
    func win() {
        let line = (0..<5).map { GomokuPoint(row: 7, col: $0) }
        let details = GomokuAccessibility.resultCardDetails(
            moveCount: 21, winningLine: line, lastMove: (row: 7, col: 4))
        #expect(details == ["21手", "決め手 8行5列"])
    }

    @Test("五連でなければ（投了・引き分け）手数だけ出す")
    func noWinningLine() {
        let details = GomokuAccessibility.resultCardDetails(
            moveCount: 225, winningLine: nil, lastMove: (row: 0, col: 0))
        #expect(details == ["225手"])
    }
}
