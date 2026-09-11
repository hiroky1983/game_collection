import Foundation
import Testing
@testable import Core

/// 帯の上の ON/OFF トグル（拡大切り替え・旗モード）が Core の共通枠から組まれていること（#641）。
///
/// 麻雀ソリティア（#197）とマインスイーパー（#203）が同じ形を別々に手書きしていたため、
/// #203 は 44pt のタップ標的だけを移植して面の作りを揃え損ね、アイコン 13pt・角丸 8・枠線なしと
/// 一回り小さいまま 5 ヶ月残った。`GameSetupSheet`（#527）と同じ考え方で、
/// 「共通枠に載っていること」と「寸法が縮んでいないこと」をソースの形で固定する。
@Suite("帯のトグルの共通枠（#641）")
struct BoardToggleButtonTests {

    /// 共通枠に載せたゲーム。ここから外すときは、なぜ載らないのかをそのゲームにコメントで書くこと。
    private static let adopters = [
        "GameMahjongSolitaire/MahjongSolitaireView.swift",
        "GameMinesweeper/MinesweeperView.swift",
    ]

    @Test("帯のトグルを持つゲームは共通枠から組んでいる")
    func adoptersUseSharedToggle() throws {
        for path in Self.adopters {
            let source = try Self.read(path)
            #expect(source.contains("BoardToggleButton("), "\(path) が共通の BoardToggleButton を使っていない")
        }
    }

    /// 寸法の急所。**2 ゲームの見た目がこの 1 組の値で決まる**ので、触ると両方が一斉に変わる。
    @Test("寸法は タップ標的44・角丸10・アイコン15")
    func metricsAreUnchanged() {
        #expect(BoardToggleMetrics.minSide == 44, "Apple HIG の最小タップ標的を割っている")
        #expect(BoardToggleMetrics.corner == 10)
        #expect(BoardToggleMetrics.iconSize == 15)
        // 帯そのもののカードより角丸が大きいと、ボタンのほうが柔らかく見えて浮く。
        #expect(BoardToggleMetrics.corner < Theme.cornerSmall)
    }

    /// 定数だけ見ても意味が無い。共通枠が **この定数を** frame に渡していなければ、
    /// 値を 44 のままにして View 側だけ小さくする改変を素通ししてしまう。
    /// SwiftUI を実際に描いて測る仕組みがこのパッケージには無いので、結線をソースで固定する。
    @Test("共通枠が寸法を BoardToggleMetrics から取っている")
    func toggleIsWiredToMetrics() throws {
        let source = try Self.read("Core/BoardToggleButton.swift")
        for expected in [
            #"minWidth:\s*BoardToggleMetrics\.minSide"#,
            #"minHeight:\s*BoardToggleMetrics\.minSide"#,
            #"cornerRadius:\s*BoardToggleMetrics\.corner"#,
            #"size:\s*BoardToggleMetrics\.iconSize"#,
        ] {
            #expect(
                source.range(of: expected, options: .regularExpression) != nil,
                "BoardToggleButton が \(expected) を使っていない（寸法が BoardToggleMetrics から切れている）"
            )
        }
    }

    /// 押していない側を `Theme.surface`（＝帯のカードと同じ面色）に戻すと、輪郭がどこにも無くなり
    /// 「押せる物」に見えなくなる（#197 が直した症状。#641 以前のマインスイーパーがこれだった）。
    @Test("押していない側は薄い差し色と枠線で輪郭を残す")
    func inactiveSideKeepsItsOutline() throws {
        let source = try Self.read("Core/BoardToggleButton.swift")
        #expect(source.contains("accent.opacity(0.12)"), "押していない側の薄い面が無い")
        #expect(source.contains(".strokeBorder("), "押していない側の枠線が無い")
        // 実装行（コメントを除く）に `Theme.surface` が現れたら逆戻り。
        let offenders = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && $0.contains("Theme.surface") }
        #expect(offenders.isEmpty, "押していない側が Theme.surface に戻っています: \(offenders)")
    }

    // MARK: - ヘルパー

    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ThemeTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources")
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: sourcesDirectory.appendingPathComponent(path), encoding: .utf8)
    }
}
