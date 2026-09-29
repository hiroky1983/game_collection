import Testing
import CoreGraphics
import Foundation
import GameKitTestSupport
@testable import GameBlackjack

/// ブラックジャックの操作ボタンのタップ標的と押下フィードバック（#709）。
/// 本文 14pt + 上下 10pt の余白しか無く高さは約 37pt で Apple HIG の 44pt を下回り、
/// `.buttonStyle(.plain)` のため押しても沈まなかった。定数と View 側の結線の両方を見る
/// （ポーカーの `PokerMetricsTests`・#207 と同じやり方）。
@Suite("ブラックジャックの操作まわりの寸法")
struct BlackjackMetricsTests {

    typealias Metrics = BlackjackMetrics

    @Test("操作ボタンの高さの下限は 44pt 以上")
    func actionButtonMeetsTapTarget() {
        #expect(Metrics.actionButtonMinHeight >= 44)
        #expect(Metrics.minimumTapTarget >= 44)
    }

    @Test("操作ボタンが実際に下限の定数で組まれている")
    func actionButtonIsWiredToTheMetric() throws {
        // 定数だけでは View 側を小さいままにする改変を素通しするので、結線もソースで固定する。
        let button = SourceScan.functionSource(startingWith: "private func actionButton(", in: try Self.viewSource())
        #expect(!button.isEmpty, "actionButton の定義が見つからない")
        // 44pt・角丸・押下フィードバックは `GameButtonStyle`（#1413）が持つ（#1423）。
        #expect(
            SourceScan.matchCount(of: #"GameButtonStyle\(role:\s*role,\s*shape:\s*\.block\)"#, in: button) == 1,
            "actionButton が GameButtonStyle(role:shape: .block) を使っていない"
        )
        #expect(
            SourceScan.matchCount(of: #"\.padding\(\.vertical,\s*10\)"#, in: button) == 0,
            "actionButton に高さを決める .padding(.vertical, 10) が残っている"
        )
    }

    @Test("画面に .buttonStyle(.plain) が残っていない")
    func noPlainButtonStyle() throws {
        // `.plain` は押下フィードバックが消える（`Core/Theme.swift` の `PopButtonStyle` の注記）。
        // 行頭のコメントは数えない（説明のために `.plain` と書くことはあるため）。
        let code = try Self.viewSource()
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        #expect(
            SourceScan.matchCount(of: #"\.buttonStyle\(\.plain\)"#, in: code) == 0,
            "BlackjackView に .buttonStyle(.plain) が残っている"
        )
    }

    /// ベット・ヒット・スタンド・ダブルダウン・スプリット・次のゲーム・結果まで進めるが
    /// 同じ `actionButton` を通ることを固定する。個別に組み直されると 44pt を外れるため。
    @Test("主要な操作はすべて actionButton を経由している")
    func allActionsGoThroughActionButton() throws {
        let source = try Self.viewSource()
        // 件数だけだと、1 箇所が外れても別の呼び出しが増えれば保たれてしまう（PR #267 の指摘）。
        // どの操作が経由しているかをラベルで個別に見る。ラベルは呼び出しと同じ行に書かれている。
        for label in [
            "\"\\(amount)枚\"",
            "\"スタンド\"",
            "\"ヒット\"",
            "\"ダブルダウン\"",
            "\"スプリット\"",
            "\"次のゲーム\"",
            "\"結果まで進める\"",
        ] {
            let pattern = #"actionButton\(\s*"# + NSRegularExpression.escapedPattern(for: label)
            #expect(
                SourceScan.matchCount(of: pattern, in: source) >= 1,
                "\(label) の操作が actionButton を経由していない（個別に組み直されると 44pt を外れる）"
            )
        }
    }

    // MARK: - ヘルパー

    private static func viewSource() throws -> String {
        try SourceScan.packageSource("Sources/GameBlackjack/BlackjackView.swift")
    }
}
