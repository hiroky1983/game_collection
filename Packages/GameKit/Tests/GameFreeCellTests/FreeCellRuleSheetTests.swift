import Testing
import Core
@testable import GameFreeCell

@Suite("フリーセルのルールシート")
struct FreeCellRuleSheetTests {

    @Test("「操作」に2回タップと自動で上がるを書き、画面に無い「盤の下に出ています」は書かない（#2710）")
    func operationMatchesTheActualScreen() throws {
        let operation = try #require(FreeCellRuleSheet.rules.first { $0.0 == tr("操作") }).1
        #expect(operation.contains("ドラッグ"))
        #expect(operation.contains("2回タップ"))
        #expect(operation.contains("自動で上がる"))
        let text = FreeCellRuleSheet.rules.map { $0.0 + $0.1 }.joined()
        #expect(!text.contains("盤の下に出ています"))
    }
}
