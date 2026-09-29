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
