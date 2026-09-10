import Foundation
import Testing
@testable import Core

/// 開始前の設定シートが Core の共通枠（`GameSetupSheet`）から組まれていること（#527）。
///
/// タイル・節・シートの高さを各ゲームが持ち直すと、#220（濃い面の文字色）や
/// #189（文字を拡大したときのシートの高さ）のような**全ゲームに効く直しが片方だけに当たる**。
/// 実際そうなっていたため、この Suite は「戻っていないこと」をソースの形で固定する。
@Suite("設定シートの共通枠（#527）")
struct GameSetupSheetSourceTests {

    /// 共通枠に載せ替えたゲーム。ここから外すときは、なぜ共通枠に載らないのかを
    /// そのゲームのシートにコメントで書くこと（花札・ソリティアが `Form` で別仕立てなのが実例）。
    private static let migrated = [
        "GameChess/ChessView.swift",
        "GameConcentration/ConcentrationView.swift",
        "GameGo/GoView.swift",
        "GameGomoku/GomokuView.swift",
        "GameMinesweeper/MinesweeperView.swift",
        "GameOthello/OthelloView.swift",
        "GameShogi/ShogiView.swift",
        "GameSudoku/SudokuView.swift",
    ]

    @Test("設定シートを出すゲームは共通枠から組んでいる")
    func migratedGamesUseSharedFrame() throws {
        for path in Self.migrated {
            let source = try Self.read(path)
            #expect(source.contains("GameSetupSheet("), "\(path) が共通枠を使っていない")
            #expect(source.contains("GameSetupChooser("), "\(path) が共通のタイルを使っていない")
        }
    }

    /// タイルの塗り分け（選択中だけ差し色・非選択は `Theme.surface`）が Core の外に再実装されていないこと。
    ///
    /// 走査は Sources 一式に掛ける。ファイルを分割しても対象から外れないようにするため、
    /// 特定のファイル名を読み口にしない（#527 以前の走査テストはそれで空振りしていた）。
    @Test("選択タイルをゲーム側で再実装していない")
    func noReimplementedChooserOutsideCore() throws {
        let sources = Self.sourcesDirectory
        let files = try FileManager.default
            .subpathsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }
            // Core は共通のタイルそのものの実装なので対象外。
            .filter { !$0.hasPrefix("Core/") }

        #expect(files.count > 20, "走査対象が見つからない（パスの導出が壊れている可能性）")

        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                if trimmed.contains("selected ? accent : Theme.surface") {
                    offenders.append("\(file):\(index + 1) \(trimmed)")
                }
            }
        }

        #expect(
            offenders.isEmpty,
            """
            選択タイルの塗り分けがゲーム側に再実装されています。\
            Core の GameSetupChooser を使ってください:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    /// 標準のタイル寸法。**8ゲームの見た目がこの1組の値で決まる**ので、うっかり触ると
    /// 全ゲームが一斉に変わる。値を変えるときは、変えてよいと判断した根拠を PR に書くこと。
    @Test("標準のタイル寸法は 見出し22・副題12・上下余白16・縮小なし")
    @MainActor
    func standardMetricsAreUnchanged() {
        let metrics = GameSetupChooser.Metrics.standard
        if case .title(let size) = metrics.title {
            #expect(size == 22)
        } else {
            Issue.record("標準は見出し書体（themeTitle）で組む")
        }
        #expect(metrics.subtitleSize == 12)
        #expect(metrics.verticalPadding == 16)
        #expect(metrics.titleMinimumScale == nil, "標準では題名を縮めない（折り返す）")
        #expect(metrics.subtitleMinimumScale == nil, "標準では副題を縮めない（折り返す）")
    }

    // MARK: - ヘルパー

    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ThemeTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources")
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: sourcesDirectory.appendingPathComponent(path), encoding: .utf8)
    }
}
