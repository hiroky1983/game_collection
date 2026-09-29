import Testing
import CoreGraphics
import Foundation
import GameKitTestSupport
@testable import GamePoker

/// ポーカーのアクションボタンのタップ標的（#207）。
/// 本文 14pt + 上下 10pt の余白しか無く、実測の高さは 34〜37pt で Apple HIG の 44pt を
/// 下回っていた。値が縮んだら気づけるように、定数と View 側の結線の両方を見る。
@Suite("ポーカーの操作まわりの寸法")
struct PokerMetricsTests {

    typealias Metrics = PokerMetrics

    @Test("アクションボタンの高さの下限は 44pt 以上")
    func actionButtonMeetsTapTarget() {
        #expect(Metrics.actionButtonMinHeight >= Metrics.minimumTapTarget)
        #expect(Metrics.minimumTapTarget >= 44)
    }

    @Test("アクションボタンが実際に下限の定数で組まれている")
    func actionButtonIsWiredToTheMetric() throws {
        // 定数だけでは View 側を小さいままにする改変を素通しするので、結線もソースで固定する
        // （麻雀ソリティアの `gameControlButtonsMeetTapTarget` と同じやり方）。
        let source = try Self.viewSource()
        // 44pt・角丸・押下フィードバックは `GameButtonStyle`（#1413）が持つ（#1423）。
        let button = SourceScan.functionSource(startingWith: "private func actionButton(", in: source)
        #expect(
            SourceScan.matchCount(of: #"GameButtonStyle\(role:\s*role,\s*shape:\s*\.block\)"#, in: button) == 1,
            "actionButton が GameButtonStyle(role:shape: .block) を使っていない"
        )
        #expect(
            SourceScan.matchCount(of: #"\.padding\(\.vertical,\s*10\)"#, in: button) == 0,
            "actionButton に高さを決める .padding(.vertical, 10) が残っている"
        )
    }

    /// 9 箇所すべての操作（チェック・ベット・フォールド・コール・交換・次のゲーム）が
    /// 同じ `actionButton` を通ることを固定する。個別に組み直されると 44pt を外れるため。
    @Test("主要な操作はすべて actionButton を経由している")
    func allActionsGoThroughActionButton() throws {
        let source = try Self.viewSource()
        let calls = SourceScan.matchCount(of: #"\bactionButton\("#, in: source)
        // 定義 1 箇所 + 呼び出し 9 箇所。
        #expect(calls >= 10, "actionButton の定義・呼び出しが想定より少ない（実測 \(calls) 箇所）")

        // 件数だけでは足りない（PR #267 の CodeRabbit 指摘）。1 箇所が `actionButton` を
        // 使わなくなっても、別の呼び出しが 1 つ増えれば件数は保たれてしまう
        // （そのため `== 10` に締めても同じ穴は残る）。**どの操作**が経由しているかを
        // ラベルで個別に見て、抜けた操作をそのまま名指しできるようにする。
        // ラベルは呼び出しと同じ行に書かれているので、行内で突き合わせる。
        for label in [
            "\"チェック\"",
            "\"ベット \\(20)枚\"",
            "\"フォールド\"",
            "\"コール \\(model.currentBet)枚\"",
            "\"\\(count)枚を交換\"",
            "\"次のゲーム\"",
        ] {
            let pattern = #"actionButton\([^\n]*"# + NSRegularExpression.escapedPattern(for: label)
            #expect(
                SourceScan.matchCount(of: pattern, in: source) >= 1,
                "\(label) の操作が actionButton を経由していない（個別に組み直されると 44pt を外れる）"
            )
        }
    }

    // MARK: - ヘルパー

    private static func viewSource() throws -> String {
        try SourceScan.moduleSources("GamePoker")
    }
}
