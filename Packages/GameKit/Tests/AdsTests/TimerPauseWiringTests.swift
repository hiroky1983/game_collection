import Testing
import Foundation
import GameKitTestSupport

/// 計時のあるゲームは、広告のロード〜視聴中に計時を止める（#1382）。
///
/// 全画面広告は `onDisappear` を発火させないので、View に結線が無いと広告の 15〜30 秒が
/// クリアタイム（自己ベスト）に乗る。ソースを走査して、対象画面の救済がすべて
/// `pausesTimerWhileWatching` に渡っていることを固定する。
@Suite("広告視聴中の計時停止の結線（#1382）")
struct TimerPauseWiringTests {
    private static let sourcesRoot = SourceScan.packageRoot.appendingPathComponent("Sources")

    /// 計時（`pauseTimer` を持つ）とリワード救済の両方があるゲームの View。
    private static let timedViews = [
        "GameSudoku/SudokuView.swift",
        "GameSolitaire/SolitaireView.swift",
        "GameFreeCell/FreeCellView.swift",
        "GameSpider/SpiderView.swift",
        "GameMahjongSolitaire/MahjongSolitaireView.swift",
    ]

    @Test("計時のあるゲームの救済は、すべて計時の一時停止に結線している")
    func everyRescueOfTimedGamesPausesTheTimer() throws {
        let declaration = try NSRegularExpression(pattern: #"var (\w+) = RewardedRescue\(\)"#)
        for path in Self.timedViews {
            let text = try String(contentsOf: Self.sourcesRoot.appendingPathComponent(path), encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            let names = declaration.matches(in: text, range: range).compactMap { match in
                Range(match.range(at: 1), in: text).map { String(text[$0]) }
            }
            #expect(!names.isEmpty, "\(path): 救済の宣言が読めていない")
            guard let start = text.range(of: ".pausesTimerWhileWatching([") else {
                Issue.record("\(path): pausesTimerWhileWatching が無い")
                continue
            }
            let list = text[start.upperBound...].prefix { $0 != "]" }
            for name in names {
                #expect(list.contains(name), "\(path): \(name) が計時の一時停止に渡っていない")
            }
        }
    }
}
