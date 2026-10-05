import Testing
import Foundation
import GameKitTestSupport

/// 計時のあるゲームは背面に回ったら計時を止めて保存する（#1734・#1781）。
///
/// 止めないと 30 秒刻みの保存を待たずに計時が進み、アプリ終了で直近の保存値に戻せてしまう
/// （順位表の最短タイムを縮められる）。経過秒の保存そのものはモデル層のテスト（`pauseTimer`）が見ているので、
/// ここでは View が `scenePhase` から `pauseTimer()` / `resumeTimerIfNeeded()` を呼ぶ結線をソースで守る。
@Suite("計時のあるゲームの背面での一時停止（#1734）")
struct TimedGamesPauseInBackgroundTests {
    @Test("数独・マインスイーパー・麻雀ソリティア・ソリティア・スパイダー・フリーセルの View が scenePhase で計時を止めて再開する",
          arguments: [
            "Sources/GameSudoku/SudokuView.swift",
            "Sources/GameMinesweeper/MinesweeperView.swift",
            "Sources/GameMahjongSolitaire/MahjongSolitaireView.swift",
            "Sources/GameSolitaire/SolitaireView.swift",
            "Sources/GameSpider/SpiderView.swift",
            "Sources/GameFreeCell/FreeCellView.swift",
          ])
    func viewObservesScenePhase(path: String) throws {
        let source = try SourceScan.packageSource(path)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let range = try #require(source.range(of: ".onChange(of: scenePhase)"))
        // 後ろに続く `.pausesTimerWhileWatching` などの呼び出しを拾わないよう、このクロージャの閉じまでで切る。
        let rest = source[range.upperBound...]
        let body = String(rest[..<(try #require(rest.range(of: "\n        }\n"))).lowerBound])
        #expect(body.contains("model.pauseTimer()"))
        #expect(body.contains("model.resumeTimerIfNeeded()"))
    }
}
