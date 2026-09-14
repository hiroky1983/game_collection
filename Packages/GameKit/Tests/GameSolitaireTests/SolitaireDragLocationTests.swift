import Testing
import Foundation
import CoreGraphics
import GameKitTestSupport
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
        let block = try #require(SourceScan.declaration(of: "struct SolitaireDragState", in: source))

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
        let board = SourceScan.strippingComments(try Self.viewSource())

        let reads = SourceScan.matchCount(of: #"\.point\b"#, in: board)
        let writes = SourceScan.matchCount(of: #"\.point\s*=(?!=)"#, in: board)
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
}
