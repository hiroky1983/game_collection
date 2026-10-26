import Testing
import CoreGraphics
import Foundation
import GameKitTestSupport
import Core
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

    /// 配る・ヒット・スタンド・スプリット・次の回へ（結果を見る）・結果まで進めるが
    /// 同じ `actionButton` を通ることを固定する。個別に組み直されると 44pt を外れるため。
    @Test("主要な操作はすべて actionButton を経由している")
    func allActionsGoThroughActionButton() throws {
        let source = try Self.viewSource()
        // 件数だけだと、1 箇所が外れても別の呼び出しが増えれば保たれてしまう（PR #267 の指摘）。
        // どの操作が経由しているかをラベルで個別に見る。ラベルは呼び出しと同じ行に書かれている。
        for label in [
            "tr(\"10回勝負で配る\")",
            "tr(\"単発戦で配る\")",
            "tr(\"スタンド\")",
            "tr(\"ヒット\")",
            "tr(\"スプリット\")",
            "model.isFinalRoundResult ? tr(\"結果を見る\") : tr(\"次の回へ\")",
            "tr(\"結果まで進める\")",
        ] {
            let pattern = #"actionButton\(\s*"# + NSRegularExpression.escapedPattern(for: label)
            #expect(
                SourceScan.matchCount(of: pattern, in: source) >= 1,
                "\(label) の操作が actionButton を経由していない（個別に組み直されると 44pt を外れる）"
            )
        }
    }

    // MARK: - レイアウトパターン A（#2531）

    @Test("全画面の枠（フェルト・バナーは枠が下に置く）を通り、ゲーム側に BannerSlot を置かない")
    func usesFullScreenChrome() throws {
        let code = SourceScan.strippingComments(try Self.viewSource())
        #expect(code.components(separatedBy: ".gameChrome(title:").count - 1 == 1)
        #expect(code.contains("fullScreen: .felt, ads: services.ads"), "全画面の枠にバナーの取得元を渡していない")
        #expect(!code.contains("BannerSlot("), "バナーを枠と二重に置いている")
        #expect(SourceScan.matchCount(of: "\\.cardTable\\(", in: code) == 0, "全画面のフェルトの上に卓を二重に敷いている")
    }

    /// iPhone SE / iPhone 17 の、ヘッダーの下からバナーの帯の上までの高さ（全画面の枠）。
    private static let seContentHeight = FullScreenGameLayoutMetrics.contentHeight(
        screenHeight: 667, safeAreaTop: 20, safeAreaBottom: 0)
    private static let iPhone17ContentHeight = FullScreenGameLayoutMetrics.contentHeight(
        screenHeight: 874, safeAreaTop: 62, safeAreaBottom: 34)

    @Test("スプリット中の中身は SE でも詰めた寸法で収まり、iPhone 17 は通常の寸法で収まる（#2498 の再発防止）")
    func splitFitsInFullScreenContent() {
        typealias V = BlackjackVerticalMetrics
        #expect(V.metrics(forHeight: Self.seContentHeight, isSplit: true) == .compact)
        #expect(V.compact.estimatedSplitMinimumHeight <= Self.seContentHeight)
        #expect(V.metrics(forHeight: Self.iPhone17ContentHeight, isSplit: true) == .regular)
        #expect(V.regular.estimatedSplitMinimumHeight <= Self.iPhone17ContentHeight)
        // 境目は通常の寸法が要る高さより上（境目ちょうどの端末でも通常の寸法で溢れない）。
        #expect(V.regular.estimatedSplitMinimumHeight <= V.compactHeightThreshold)
        // 1 手のときは詰めない。
        #expect(V.metrics(forHeight: Self.seContentHeight, isSplit: false) == .regular)
    }

    @Test("卓の高さはスプリット中の高さまでに抑え、卓と操作欄のまとまりを真ん中に置く（会長 QA 2026-10-22）")
    func tableIsCappedAndCentered() throws {
        typealias V = BlackjackVerticalMetrics
        // 1 手の卓（ディーラー 129 + あなた 129 + 間隔 20）とスプリット中の卓の差だけが、1 手のときの間になる。
        #expect(V.regular.estimatedSplitTableHeight == 363)
        #expect(V.regular.actionAreaMinHeight == BlackjackMetrics.actionButtonMinHeight * 2 + 8)
        let code = SourceScan.strippingComments(try Self.viewSource())
        #expect(code.contains(".frame(maxHeight: layout.scaled(metrics.estimatedSplitTableHeight))"),
                "卓の高さに上限が無い（全画面でディーラーとあなたの間が大きく空く）")
        #expect(code.contains(".frame(minHeight: metrics.actionAreaMinHeight, alignment: .top)"),
                "操作欄の高さを取っておかないと、ボタンの出入りで真ん中の卓が動く")
    }

    // MARK: - ヘルパー

    private static func viewSource() throws -> String {
        try SourceScan.packageSource("Sources/GameBlackjack/BlackjackView.swift")
    }
}
