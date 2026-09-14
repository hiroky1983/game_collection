import Testing
import Foundation
import CoreGraphics
import GameKitTestSupport
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
        let block = try #require(SourceScan.declaration(of: "struct FreeCellDragState", in: source))

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
        try SourceScan.packageSource("Sources/GameFreeCell/FreeCellView.swift")
    }
}
