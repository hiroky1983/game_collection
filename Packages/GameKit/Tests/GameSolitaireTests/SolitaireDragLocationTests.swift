import Testing
import Foundation
import CoreGraphics
@testable import GameSolitaire

/// ドラッグ中の再描画（#521）。
///
/// 指の位置を `@State` の構造体に持たせると、1 サンプルごとに `SolitaireView.body`
/// （ステータスバー・7 列の場札・操作エリア）がまるごと作り直される。位置だけを
/// 参照型（`CardDragLocation`）へ逃がし、**追従表示のサブビューだけが読む**形にした。
///
/// 見た目そのものはシミュレータでしか確認できないので、ここでは
/// **①ドラッグ状態が位置を持たないこと**・**②盤本体が位置を読まないこと**
/// （逃がした意味が残っている）をソースから見る（演出テスト `SolitaireMotionTests` と同じやり方）。
/// 位置の共有・位置合わせの算術・追従表示が位置を読むことは、共通基盤へ移したので
/// `CardTableTests`（Core）が受け持つ（#524）。
@Suite("ソリティアのドラッグ位置")
@MainActor
struct SolitaireDragLocationTests {

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
        // 追従表示（`CardDragLayer`）は Core へ移したので、ゲーム側のソースは丸ごと「盤本体」になる。
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
        try SolitaireSources.joined()
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
