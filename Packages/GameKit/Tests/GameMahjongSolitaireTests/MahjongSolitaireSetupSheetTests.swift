import Testing
import Foundation
import GameKitTestSupport
@testable import GameMahjongSolitaire

/// 盤面のかたちは開始シートで選ぶ（会長 QA 2026-09-28）。ほかのゲームの難易度選びと同じ導線で、
/// 初回（中断データが無いとき）とナビバーの「新規ゲーム」でシートを開き、中断データがあれば続きから。
/// SwiftUI の表示状態はユニットテストから覗けないので、配線をソースで押さえる。
@Suite("麻雀ソリティアの開始シート")
struct MahjongSolitaireSetupSheetTests {

    private static func viewSource() throws -> String {
        SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameMahjongSolitaire/MahjongSolitaireView.swift"))
    }

    @Test("ナビバーの新規ゲームは共通の GameChromeNewGame から開始シートを開く（「＋」メニューを持たない）")
    func newGameOpensTheSetupSheet() throws {
        let source = try Self.viewSource()
        #expect(source.contains("newGame: GameChromeNewGame(.solo"), "共通の新規ゲームボタンを使っていない")
        #expect(source.contains("MahjongSolitaireSetupSheet("), "開始シートを出していない")
        #expect(!source.contains("Menu {"), "かたちを選ぶメニューが残っている")
        #expect(!source.contains("confirmationDialog(\"新規ゲームを始めますか？\""),
                "確認ダイアログが残っている（途中の盤面の警告は開始シートが兼ねる）")
    }

    @Test("初回だけシートから始め、中断データがあれば出さない。-mahjongLayout 指定時も出さない")
    func initialSheetDependsOnSnapshot() throws {
        let source = try Self.viewSource()
        #expect(source.contains("snapshots.exists(for: MahjongSolitaireModel.snapshotID)"))
        #expect(source.contains("let showsInitialSetup = launchLayout == nil && !hasSnapshot"))
        #expect(source.contains("_showSetup = State(initialValue: showsInitialSetup)"))
        // シートを出す初回は game_start を保留し、シートを閉じたときに数える。
        #expect(source.contains("defersInitialStart: showsInitialSetup"))
        #expect(source.contains("model.startPlayIfPending()"))
        #expect(source.contains("\"-mahjongLayout\""), "撮影用の起動引数が消えている")
        #expect(MahjongSolitaireModel.snapshotID == "mahjong", "中断データのキーが変わると再開できなくなる")
    }

    @Test("シートのタイルは MahjongSolitaireLayout.all の表示名で並ぶ")
    func sheetListsEveryLayout() throws {
        let source = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameMahjongSolitaire/MahjongSolitaireSetupSheet.swift"))
        #expect(source.contains("ForEach(MahjongSolitaireLayout.all)"))
        #expect(source.contains("title: layout.displayName"))
        #expect(source.contains("GameSetupChooser("))
    }
}
