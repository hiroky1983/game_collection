import Testing
import Foundation
import CoreGraphics
import Observation
@testable import GameSolitaire

/// ドラッグ中の再描画（#521）。
///
/// 指の位置を `@State` の構造体に持たせると、1 サンプルごとに `SolitaireView.body`
/// （ステータスバー・7 列の場札・操作エリア）がまるごと作り直される。位置だけを
/// 参照型（`SolitaireDragLocation`）へ逃がし、**追従表示のサブビューだけが読む**形にした。
///
/// 見た目そのものはシミュレータでしか確認できないので、ここでは
/// **①位置の更新が購読者に届くこと**（追従が壊れていない）・**②盤本体が位置を読まないこと**
/// （逃がした意味が残っている）・**③位置合わせの算術**を固定する。
/// ②は演出テスト（`SolitaireMotionTests`）と同じやり方でソースから見る。
@Suite("ソリティアのドラッグ位置")
@MainActor
struct SolitaireDragLocationTests {

    // MARK: - 受け入れ条件: 追従表示は指について来る

    @Test("位置の更新は購読しているビューに届く")
    func locationUpdateNotifiesObservers() async {
        let location = SolitaireDragLocation()
        // 「point を読んだビューが無効化される」= 持ち上げた札が指について来る、の最小形。
        await confirmation("位置を読んだ購読者が起きる") { observed in
            withObservationTracking {
                _ = location.point
            } onChange: {
                observed()
            }

            location.point = CGPoint(x: 120, y: 240)
        }
    }

    @Test("参照型なので、渡した先から見ても同じ位置になる")
    func locationIsSharedByReference() {
        let location = SolitaireDragLocation(point: CGPoint(x: 1, y: 2))
        let handedToDragLayer = location

        location.point = CGPoint(x: 30, y: 40)

        #expect(handedToDragLayer.point == CGPoint(x: 30, y: 40))
    }

    // MARK: - 受け入れ条件: 盤本体の body 再評価が起きない

    @Test("ドラッグ状態は指の位置を持たない（持つと @State の更新になり盤が作り直される）")
    func dragStateDoesNotCarryTheFingerPosition() throws {
        let source = try Self.viewSource()
        let block = try #require(Self.declaration(of: "struct SolitaireDragState", in: source))

        #expect(
            !block.contains("location"),
            "SolitaireDragState に位置が戻っている。毎サンプル @State が書き換わる"
        )
        #expect(block.contains("grab"), "取り違え防止。持ち上げ時にだけ決まる値はここに残す")
    }

    @Test("盤本体は指の位置を書くだけで読まない")
    func theBoardWritesTheFingerPositionButNeverReadsIt() throws {
        let source = try Self.viewSource()
        // ファイル前半（`SolitaireView` とその補助ビュー）と、後半（追従表示 `SolitaireDragLayer`）に分ける。
        let split = try #require(source.range(of: "// MARK: - ドラッグ&ドロップ（会長要望 2026-09-02）\n\n/// ドラッグ中の札の状態"))
        // コメントは落とす。**この規約そのものを説明した注記まで「読んでいる」と数える**ため。
        let board = Self.strippingComments(String(source[source.startIndex..<split.lowerBound]))
        let dragLayer = Self.strippingComments(String(source[split.lowerBound...]))

        let reads = Self.matchCount(of: #"\.point\b"#, in: board)
        let writes = Self.matchCount(of: #"\.point\s*=(?!=)"#, in: board)
        #expect(
            reads == writes,
            "盤本体が位置を読んでいる（出現 \(reads) 件のうち代入は \(writes) 件）。読むと指の動きを購読してしまう"
        )
        #expect(writes > 0, "取り違え防止。ドラッグの更新そのものは盤側に残っている")

        #expect(
            Self.matchCount(of: #"\.point\b"#, in: dragLayer) > 0,
            "追従表示が位置を読んでいない = 札が指について来ない"
        )
    }

    // MARK: - 位置合わせ

    @Test("持ち上げた札の左上は、指の位置からつかんだ点のずれを引いた場所")
    func originSubtractsTheGrabOffset() {
        let origin = SolitaireDragLayout.origin(
            location: CGPoint(x: 100, y: 200),
            grab: CGSize(width: 38, height: 36)
        )
        #expect(origin == CGPoint(x: 62, y: 164))
    }

    @Test("つかんだ点のずれが無ければ、指の位置がそのまま左上になる")
    func originWithoutGrabIsTheFingerPosition() {
        let origin = SolitaireDragLayout.origin(location: CGPoint(x: 7, y: 9), grab: .zero)
        #expect(origin == CGPoint(x: 7, y: 9))
    }

    // MARK: - ヘルパー

    private static func viewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameSolitaireTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GameSolitaire/SolitaireView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// `header` で始まる宣言の本体（対応する閉じ括弧まで）を取り出す。
    private static func declaration(of header: String, in source: String) -> String? {
        guard let start = source.range(of: header) else { return nil }
        guard let open = source[start.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 { return String(source[open...index]) }
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// 行コメント（`//` 以降）を落とす。URL の `://` は落とさない。
    private static func strippingComments(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            var search = line.startIndex
            while let slashes = line.range(of: "//", range: search..<line.endIndex) {
                let precedesURL = slashes.lowerBound > line.startIndex
                    && line[line.index(before: slashes.lowerBound)] == ":"
                if !precedesURL { return line[line.startIndex..<slashes.lowerBound] }
                search = slashes.upperBound
            }
            return line[...]
        }.joined(separator: "\n")
    }

    private static func matchCount(of pattern: String, in source: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(
            in: source, range: NSRange(source.startIndex..., in: source)
        )
    }
}
