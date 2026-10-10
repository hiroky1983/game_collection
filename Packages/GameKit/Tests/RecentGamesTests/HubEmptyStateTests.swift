import Foundation
import Testing
@testable import Core

/// ハブの空状態（#2002）。View は App ターゲットにあるので、出す条件と文言だけをここで固定する。
@Suite("ハブの空状態")
struct HubEmptyStateTests {
    @Test("見えているゲームが 0 本なら出す")
    func shownWhenNothingVisible() {
        #expect(HubEmptyState.isShown(visibleGameIDs: []))
    }

    @Test("特別枠のゲーム 1 本だけでも空ではない")
    func notShownWithOnlyHeroGame() {
        #expect(!HubEmptyState.isShown(visibleGameIDs: ["homerun"]))
        #expect(!HubEmptyState.isShown(visibleGameIDs: ["2048", "shogi"]))
    }

    @Test("文言は設定への導線を含む")
    func messageMentionsSettings() {
        #expect(HubEmptyState.message == "表示するゲームがありません。設定で選べます")
        #expect(HubEmptyState.buttonTitle == "設定を開く")
    }
}
