import Foundation
import SwiftUI
import Testing
import GameKitTestSupport
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
        SourceScan.packageRoot.appendingPathComponent("Sources")
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: sourcesDirectory.appendingPathComponent(path), encoding: .utf8)
    }
}

// MARK: - CPU の強さ 5 段階（#1174）

/// CPU と 1 対 1 で戦う 4 ゲームの「CPUの強さ」が、**同じ部品・同じ寸法**で組まれていること。
///
/// 同じ役割の UI は寸法だけでなく部品まで同じにする（拡大トグル #641 と同じ約束）。
/// ここを各ゲームが持ち直すと、段を足すたびに 1 本だけ古い並びが残る。
@Suite("CPUの強さの選択 UI（#1174）")
struct CPUStrengthPickerSourceTests {

    /// `CPUStrength` を使う 4 本。囲碁・神経衰弱・花札は別の段階の型（`GoLevel` など）を
    /// 持つので対象外。
    private static let games = [
        "GameChess/ChessView.swift",
        "GameGomoku/GomokuView.swift",
        "GameOthello/OthelloView.swift",
        "GameShogi/ShogiView.swift",
    ]

    @Test("4ゲームとも共通のピッカーで組んでいる")
    func everyCPUGameUsesTheSharedPicker() throws {
        for path in Self.games {
            let source = try String(
                contentsOf: SourceScan.packageRoot
                    .appendingPathComponent("Sources").appendingPathComponent(path),
                encoding: .utf8)
            #expect(source.contains(#"GameSetupSection("CPUの強さ")"#), "\(path) に強さの節が無い")
            #expect(source.contains("CPUStrengthPicker(level: $level"),
                    "\(path) が共通のピッカーを使っていない")
            // 「ガチ」は v1.1.6 で一旦見送ったので、その説明（「とことん読む」）は書かれていない。
            #expect(!source.contains("とことん読む"), "\(path) に見送ったはずのガチの説明が残っている")
            // 段の呼び名はピッカー側（`CPUStrength.label`）が持つ。各ゲームに書き写さない。
            for label in CPUStrength.labels {
                #expect(!source.contains("title: \"\(label)\""),
                        "\(path) が段の呼び名を書き写している（\(label)）")
            }
        }
    }

    /// 段を選び直してもシートの高さが変わらないこと（説明は常に 1 行）。
    /// 伸び縮みすると、選んだ拍子に「対局開始」が動く。
    @Test("段を選び直しても高さが変わらない")
    @MainActor
    func heightIsStableAcrossSelections() {
        let details = ["手なりで指す", "駒得だけ", "囲いを作る", "定跡＋深読み"]
        var heights: [Int] = []
        for strength in CPUStrength.allCases {
            var level = strength.rawValue
            let picker = CPUStrengthPicker(
                level: Binding(get: { level }, set: { level = $0 }), details: details
            )
            let renderer = ImageRenderer(content: picker.frame(width: 343))
            renderer.scale = 1
            heights.append(renderer.cgImage?.height ?? 0)
        }
        #expect(heights.allSatisfy { $0 > 0 }, "ピッカーが描かれていない")
        #expect(Set(heights).count == 1, "段によって高さが違う: \(heights)")
    }
}
