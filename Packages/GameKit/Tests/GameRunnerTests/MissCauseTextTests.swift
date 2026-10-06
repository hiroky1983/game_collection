import Testing
import Core
@testable import GameRunner

/// ミスの原因の 1 行（#1755）。すべての原因に空でない文が付く。
@Suite("RunnerView.missCauseText")
struct MissCauseTextTests {
    @Test("全ての原因に別々の文が付く")
    func everyCauseHasDistinctText() {
        let texts = AnalyticsEndCause.allCases.map { RunnerView.missCauseText($0) }
        #expect(texts.allSatisfy { !$0.isEmpty })
        #expect(Set(texts).count == texts.count)
        #expect(RunnerView.missCauseText(.pit) == "穴に落ちた")
        #expect(RunnerView.missCauseText(.rock) == "岩にぶつかった")
    }
}
