import Testing
import SwiftUI
@testable import Core

/// 「色以外で区別」の共通部品（#3415）。印は設定 ON かつ状態が有効なときだけ出る。
@Suite("StateMark")
struct StateMarkTests {
    @Test func 設定オンで状態が有効なときだけ印が出る() {
        #expect(StateMark.isVisible(active: true, differentiateWithoutColor: true))
        #expect(!StateMark.isVisible(active: false, differentiateWithoutColor: true))
    }

    @Test func 設定オフでは状態が有効でも印は出ない() {
        #expect(!StateMark.isVisible(active: true, differentiateWithoutColor: false))
        #expect(!StateMark.isVisible(active: false, differentiateWithoutColor: false))
    }
}
