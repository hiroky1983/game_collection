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

    @Test("「⋯」メニューを開いているあいだは待ち時間を数えない（開いた時点で出ていた吹き出しも隠す）")
    func menuOpenSuppressesTheNudge() {
        #expect(HintNudgePolicy.canSchedule(isEligible: true, isActive: true, isMenuOpen: false, shownCount: 0))
        #expect(!HintNudgePolicy.canSchedule(isEligible: true, isActive: true, isMenuOpen: true, shownCount: 0))
        #expect(!HintNudgePolicy.canSchedule(isEligible: false, isActive: true, isMenuOpen: false, shownCount: 0))
        #expect(!HintNudgePolicy.canSchedule(isEligible: true, isActive: false, isMenuOpen: false, shownCount: 0))
        #expect(!HintNudgePolicy.canSchedule(isEligible: true, isActive: true, isMenuOpen: false,
                                             shownCount: HintNudgePolicy.maxPerGame))
    }

    @Test("「⋯」の行はメニューの開閉を吹き出しに渡し、開閉で待ち時間を数え直す")
    func overflowBarWiresMenuState() throws {
        let bar = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/GameOverflowBar.swift"))
        #expect(bar.contains("GameControlMenu(items: menuItems, isOpen: $isMenuOpen)"))
        #expect(bar.contains(".hintNudge(nudge, isMenuOpen: isMenuOpen)"))
        let menu = try #require(SourceScan.declaration(of: "public struct GameControlMenu: View", in: bar))
        #expect(menu.contains(".onAppear { setOpen(true) }"), "メニューが開いたことを拾っていない")
        #expect(menu.contains(".onDisappear { setOpen(false) }"), "メニューが閉じたことを拾っていない")
        let nudge = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/HintNudge.swift"))
        let key = try #require(SourceScan.declaration(of: "private struct Key", in: nudge))
        #expect(key.contains("let isMenuOpen: Bool"), "開閉が待ち時間の数え直しの条件に入っていない")
        #expect(nudge.contains("isMenuOpen: key.isMenuOpen"))
    }

    @Test("吹き出しは「⋯」の左に、行の高さの中で出す（盤・広告に重ねない）")
    func bubbleSitsLeftOfTheMenu() throws {
        let nudge = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/HintNudge.swift"))
        #expect(nudge.contains(".overlay(alignment: .trailing)"))
        #expect(nudge.contains(".padding(.trailing, HintNudgeBubble.trailingInset)"))
        #expect(!nudge.contains("alignmentGuide(.top)"), "吹き出しが行の上（盤側）へはみ出す置き方が残っている")
        #expect(HintNudgeBubble.trailingInset >= BoardGameControlMetrics.minTapTarget, "吹き出しが「⋯」に重なる")
    }

    @Test("ナンプレと麻雀ソリティアの操作行が促しを受け取り、広告の視聴中は出さない")
    func adHintGamesWireTheNudge() throws {
        for (path, watching) in [("GameSudoku/SudokuView.swift", "!hintRescue.isWatching"),
                                 ("GameMahjongSolitaire/MahjongSolitaireView.swift", "!isWatchingRewardAd")] {
            let text = try SourceScan.packageSource("Sources/\(path)")
            #expect(text.contains("nudge: hintNudge"), "\(path) の GameOverflowBar に nudge を渡していない")
            let body = try #require(text.range(of: "private var hintNudge: HintNudge"))
            #expect(text[body.upperBound...].prefix(400).contains(watching), "\(path) の促しが広告の視聴中を除いていない")
        }
    }
}
