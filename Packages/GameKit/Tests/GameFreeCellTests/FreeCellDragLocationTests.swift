import Testing
import Foundation
import CoreGraphics
@testable import GameFreeCell

/// ドラッグ中の再描画（#524 でソリティア #521 の対策を横展開した）。
///
/// フリーセルは #492 でクロンダイクの View を写して作られたが、指の位置は
/// `FreeCellDragState`（`@State` の構造体）に入ったままだった。1 サンプルごとに
/// `FreeCellView.body`（ステータスバー・8 列の場札・操作エリア）が作り直される形なので、
/// 共通基盤（`CardDragLocation`）へ寄せるのに合わせて参照型へ逃がしてある。
///
/// 見た目そのものはシミュレータでしか確認できないので、ソースから
/// **①ドラッグ状態が位置を持たないこと**・**②盤本体が位置を読まないこと**を見る
/// （`SolitaireDragLocationTests` と同じ形）。
@Suite("フリーセルのドラッグ位置")
@MainActor
struct FreeCellDragLocationTests {

    @Test("ドラッグ状態は指の位置を持たない（持つと @State の更新になり盤が作り直される）")
    func dragStateDoesNotCarryTheFingerPosition() throws {
        let source = try Self.viewSource()
        let block = try #require(Self.declaration(of: "struct FreeCellDragState", in: source))

        #expect(
            !block.contains("location"),
            "FreeCellDragState に位置が戻っている。毎サンプル @State が書き換わる"
        )
        #expect(block.contains("grab"), "取り違え防止。持ち上げ時にだけ決まる値はここに残す")
    }

    @Test("盤本体は指の位置を書くだけで読まない")
    func theBoardWritesTheFingerPositionButNeverReadsIt() throws {
        // 追従表示（`CardDragLayer`）は Core にあるので、このファイルは丸ごと「盤本体」になる。
        // コメントは落とす。**この規約そのものを説明した注記まで「読んでいる」と数える**ため。
        let board = Self.strippingComments(try Self.viewSource())

        let reads = Self.matchCount(of: #"\.point\b"#, in: board)
        let writes = Self.matchCount(of: #"\.point\s*=(?!=)"#, in: board)
        #expect(
            reads == writes,
            "盤本体が位置を読んでいる（出現 \(reads) 件のうち代入は \(writes) 件）。読むと指の動きを購読してしまう"
        )
        #expect(writes > 0, "取り違え防止。ドラッグの更新そのものは盤側に残っている")
    }

    // MARK: - ヘルパー

    private static func viewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameFreeCellTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GameFreeCell/FreeCellView.swift")
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
