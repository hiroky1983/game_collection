import SwiftUI
import Testing
@testable import Core

/// ハブの描き直しで model が作り捨てられない（#1926）。入れ物は最初に読まれたときだけ作る。
@Suite("ゲーム画面の入れ物（#1926）")
@MainActor
struct GameScreenHostTests {
    @Test("作るのは最初に読まれたときだけで、2 回目以降は作らない")
    func buildsOnlyOnce() {
        var built = 0
        let holder = GameScreenHolder {
            built += 1
            return AnyView(EmptyView())
        }
        #expect(built == 0, "作る前に読まれていないのに作っている")
        _ = holder.screen
        _ = holder.screen
        _ = holder.screen
        #expect(built == 1, "読むたびに作り直している: \(built)")
    }

    @Test("入れ物を作っただけでは画面を作らない（親の評価で作り捨てが起きない）")
    func initDoesNotBuild() {
        var built = 0
        _ = GameScreenHost {
            built += 1
            return AnyView(EmptyView())
        }
        #expect(built == 0)
    }
}
