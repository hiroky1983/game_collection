import Foundation
import Testing
import GameKitTestSupport
@testable import Core

/// ヒントを促す表示（#1424）。時間の待ち合わせはテストしない（実時間に頼るとフレークする）ので、
/// 決まりの値と、ヒントが「⋯」にある 5 本すべてが促しを配線していることだけを固定する。
@Suite("ヒントを促す表示")
struct HintNudgeTests {

    @Test("30 秒待ち、1 局に出す回数は 2 回まで")
    func policyValues() {
        #expect(HintNudgePolicy.idleDelay == .seconds(30))
        #expect(HintNudgePolicy.canShow(shownCount: 0))
        #expect(HintNudgePolicy.canShow(shownCount: HintNudgePolicy.maxPerGame - 1))
        #expect(!HintNudgePolicy.canShow(shownCount: HintNudgePolicy.maxPerGame))
    }

    @Test("ナンプレと麻雀ソリティアの操作行が促しを受け取り、広告の視聴中は出さない")
    func adHintGamesWireTheNudge() throws {
        for (path, watching) in [("GameSudoku/SudokuView.swift", "!hintRescue.isWatching"),
                                 ("GameMahjongSolitaire/MahjongSolitaireView.swift", "!isWatchingRewardAd")] {
            let text = try SourceScan.packageSource("Sources/\(path)")
            #expect(text.contains("nudge: hintNudge"), "\(path) の GameControlBar に nudge を渡していない")
            let body = try #require(text.range(of: "private var hintNudge: HintNudge"))
            #expect(text[body.upperBound...].prefix(400).contains(watching), "\(path) の促しが広告の視聴中を除いていない")
        }
    }
}
