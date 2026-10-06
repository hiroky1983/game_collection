import Foundation
import Testing
import GameKitTestSupport
@testable import Core

/// ヒントを促す表示（#1424）。時間の待ち合わせはテストしない（実時間に頼るとフレークする）ので、
/// 決まりの値と、ヒントを持つ 5 本すべてが促しを配線していることだけを固定する。
/// 見せ方は 2 つ（#1856）: 段にヒントのカプセルがあればそれを光らせ、ヒントが「⋯」の中にあれば吹き出しを出す。
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
        #expect(bar.contains(".hintNudge(nudge, isMenuOpen: isMenuOpen, highlightsAction: !actions.isEmpty)"))
        let menu = try #require(SourceScan.declaration(of: "public struct GameControlMenu: View", in: bar))
        #expect(menu.contains(".onAppear { setOpen(true) }"), "メニューが開いたことを拾っていない")
        #expect(menu.contains(".onDisappear { setOpen(false) }"), "メニューが閉じたことを拾っていない")
        // onAppear / onDisappear は実機で発火が確認できなかった（#1499）。「⋯」自体へのタップでも
        // 開いた合図を重ねて取る（Menu 本来のタップは simultaneousGesture なら妨げない）。
        #expect(menu.contains(".simultaneousGesture(TapGesture().onEnded { setOpen(true) })"),
                "「⋯」へのタップでも開いたことを拾っていない")
        let nudge = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/HintNudge.swift"))
        let key = try #require(SourceScan.declaration(of: "private struct Key", in: nudge))
        #expect(key.contains("let isMenuOpen: Bool"), "開閉が待ち時間の数え直しの条件に入っていない")
        #expect(nudge.contains("isMenuOpen: key.isMenuOpen"))
    }

    @Test("押せない項目はアイコンも文字と同じグレーにする")
    func disabledItemGreysIconToo() throws {
        let bar = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/GameOverflowBar.swift"))
        let menu = try #require(SourceScan.declaration(of: "public struct GameControlMenu: View", in: bar))
        let label = try #require(SourceScan.declaration(
            of: "private static func label(for item: GameControlMenuItem) -> some View", in: menu))
        #expect(label.contains("if item.isEnabled {"), "押せる項目の色を分岐で変えていない前提が崩れている")
        // `.foregroundStyle` はメニューがアプリの差し色でアイコンを塗り直すため効かない（会長 QA 2026-09-28）。
        // 色を焼き込んだ画像（alwaysOriginal）で渡していることを固定する。
        #expect(label.contains("disabledIcon(item.systemImage)"), "押せない項目のアイコンを専用の画像で描いていない")
        let icon = try #require(SourceScan.declaration(
            of: "private static func disabledIcon(_ systemImage: String) -> some View", in: menu))
        #expect(icon.contains("renderingMode: .alwaysOriginal"), "アイコンの色を焼き込んでいない（差し色で塗り直される）")
        // 押せる分岐（if item.isEnabled の直後、else の手前）には色の上書きが無く、従来どおりの見た目のまま。
        let enabledBranch = try #require(label.range(of: "if item.isEnabled {"))
        let elseBranch = try #require(label.range(of: "} else {"))
        #expect(!label[enabledBranch.upperBound..<elseBranch.lowerBound].contains(".foregroundStyle"),
                "押せる項目の見た目まで変えてしまっている")
    }

    @Test("吹き出しは「⋯」の左に、行の高さの中で出す（盤・広告に重ねない）")
    func bubbleSitsLeftOfTheMenu() throws {
        let nudge = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/HintNudge.swift"))
        #expect(nudge.contains(".overlay(alignment: .trailing)"))
        #expect(nudge.contains(".padding(.trailing, HintNudgeBubble.trailingInset)"))
        #expect(!nudge.contains("alignmentGuide(.top)"), "吹き出しが行の上（盤側）へはみ出す置き方が残っている")
        #expect(HintNudgeBubble.trailingInset >= BoardGameControlMetrics.minTapTarget, "吹き出しが「⋯」に重なる")
    }

    /// 段にヒントのカプセルがあるときは吹き出しを出さず、環境値でカプセルを光らせる（#1856）。
    /// 光らせるのは縁（枠の内側）と影なので、段の高さも隣のカプセルの位置も変えない。
    @Test("段にヒントがあるときは吹き出しではなくヒントのカプセルを光らせる")
    func actionRowGlowsInsteadOfBubble() throws {
        let nudge = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/HintNudge.swift"))
        #expect(nudge.contains(".environment(\\.hintNudgeIsShowing, isShowing && highlightsAction)"),
                "促しの状態を環境値で段へ渡していない")
        #expect(nudge.contains("if !highlightsAction {"), "段があるときも吹き出しが出る")
        let glow = try #require(SourceScan.declaration(of: "private struct HintNudgeGlowModifier", in: nudge))
        #expect(glow.contains("if isOn, !reduceMotion {"), "Reduce Motion で脈打つ")
        #expect(glow.contains(".phaseAnimator([false, true])"), "繰り返しの脈動になっていない")
        #expect(glow.contains("Capsule().strokeBorder("), "縁が枠の内側（strokeBorder）でない")
        #expect(!glow.contains(".padding(-"), "光が枠の外へはみ出して段の高さを変える")
        let row = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/GameActionRow.swift"))
        #expect(row.contains("@Environment(\\.hintNudgeIsShowing) private var isNudging"), "カプセルが促しを読んでいない")
        #expect(row.contains("item.role == .hint && item.isEnabled && isNudging"), "ヒント以外のカプセルまで光る")
        #expect(row.contains(".hintNudgeGlow(glows, reduceMotion: reduceMotion)"))
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
