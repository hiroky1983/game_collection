import Foundation
import Testing
@testable import Core
import GameKitTestSupport

/// 「新規」で進行を捨てる画面が、確認なしで盤を捨てないこと（#3148）。
///
/// 確認の出し方は 3 通りあり、公開中の全ゲームの View がどれかを持つ:
/// 1. 共通部品に任せる: `GameChromeNewGame(…, hasProgressToLose:)` を渡す（共通の確認が出る）。
/// 2. 開始シートが「終了して…」の文言になる: `GameSetupSheet(discardsProgress:)` に連なる `discardsProgress`。
/// 3. 自前の確認ダイアログ（`confirmationDialog` / `.alert`）で、「新規」の経路から開く。
/// 倉庫ゲーム（registry 行がコメントアウトされたもの）は対象外。
@Suite("新規ボタンの進行確認")
struct NewGameConfirmationScanTests {
    /// 公開中のモジュール名（registry のコメントアウトされていない `XxxModule(),` の行）。
    private static func publishedModules() throws -> [String] {
        let url = SourceScan.repositoryRoot.appendingPathComponent("App/AppGameServices.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        return source.split(separator: "\n").compactMap { line -> String? in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasSuffix("Module(),"), !t.hasPrefix("//") else { return nil }
            return String(t.dropLast("Module(),".count))
        }
    }

    /// モジュール名 → 「新規」ボタンを持つ View のソース（無ければ nil）。
    private static func newGameSources() throws -> [(module: String, file: String, source: String)] {
        let fm = FileManager.default
        let sources = SourceScan.repositoryRoot.appendingPathComponent("Packages/GameKit/Sources")
        var result: [(String, String, String)] = []
        for name in try publishedModules() {
            let dir = name.hasPrefix("Game") ? name : "Game" + name
            let moduleDir = sources.appendingPathComponent(dir)
            guard let files = try? fm.contentsOfDirectory(atPath: moduleDir.path) else { continue }
            for file in files.sorted() where file.hasSuffix("View.swift") {
                let text = try String(contentsOf: moduleDir.appendingPathComponent(file), encoding: .utf8)
                let code = SourceScan.strippingComments(text)
                if code.contains("newGame: GameChromeNewGame(") { result.append((dir, file, code)) }
            }
        }
        return result
    }

    @Test("公開中のゲームの「新規」は、進行があれば確認か「終了して…」の開始シートを必ず通る")
    func everyPublishedNewGameConfirmsBeforeDiscarding() throws {
        let screens = try Self.newGameSources()
        #expect(screens.count >= 25, "走査対象が少なすぎる（registry の読み取りが壊れていないか）: \(screens.count)")
        for screen in screens {
            let usesCommon = screen.source.contains("hasProgressToLose:")
            let discardsSheet = screen.source.contains("discardsProgress")
            let ownConfirm = screen.source.contains("confirmationDialog(") || screen.source.contains(".alert(")
            #expect(usesCommon || discardsSheet || ownConfirm,
                    "\(screen.module)/\(screen.file) は進行があっても確認なしで盤を捨てる")
        }
    }

    @Test("チャリンコおじさんの「はじめから」は共通の確認に進行の有無を渡す")
    func runnerPassesProgressToCommonConfirmation() throws {
        let screens = try Self.newGameSources()
        let runner = try #require(screens.first { $0.file == "RunnerView.swift" })
        #expect(SourceScan.matchCount(
            of: #"GameChromeNewGame\(\.restart,[^{]*hasProgressToLose: model\.hasProgressToLose"#, in: runner.source) == 1)
    }

    @Test("共通の確認: 進行がなければ即実行、あれば確認を出して実行しない")
    func commonConfirmationGate() {
        var ran = 0
        var asked = 0
        GameChromeNewGame(.solo) { ran += 1 }.tapped { asked += 1 }
        #expect(ran == 1 && asked == 0)
        GameChromeNewGame(.solo, hasProgressToLose: true) { ran += 1 }.tapped { asked += 1 }
        #expect(ran == 1 && asked == 1, "進行があるのに確認を出さず実行した")
    }
}
