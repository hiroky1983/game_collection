import Foundation
import Testing
import GameKitTestSupport
@testable import Core

/// CPU 手番の `.task` を持つ View は、開始シート・遊び方シートが開いているあいだ止める（#3218）。
///
/// 「前回の条件を覚える開始シート」（#2611・#3151）で前回が後手だと、シートの裏で CPU が先に着手し、
/// `game_start` の過剰計上（#1372 の再発）や裏での読み上げを招いた。View の `.task` は実行では確かめられないので、
/// ソースの形で守る。新しいゲームが `performAIMoveIfNeeded` を直接呼ぶ形に戻すと、ここで落ちる。
@Suite("CPU 手番の一時停止（開始シートの裏で動かさない）")
struct PausableTurnScanTests {
    /// `Sources/Game*/` 直下の View ファイル（`*View.swift`）の相対パス。
    private func viewFiles() throws -> [String] {
        let sources = SourceScan.packageRoot.appendingPathComponent("Sources")
        let modules = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasPrefix("Game") }.sorted()
        var files: [String] = []
        for module in modules {
            let dir = sources.appendingPathComponent(module)
            for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
            where name.hasSuffix("View.swift") {
                files.append("Sources/\(module)/\(name)")
            }
        }
        return files
    }

    @Test("performAIMoveIfNeeded を呼ぶ View は PausableTurn で止められる")
    func viewsCallingAIMoveUsePausableTurn() throws {
        var checked: [String] = []
        for path in try viewFiles() {
            let source = SourceScan.strippingComments(try SourceScan.packageSource(path))
            guard source.contains("performAIMoveIfNeeded()") else { continue }
            checked.append(path)
            #expect(source.contains("PausableTurn(key: model.aiTurnKey"), "\(path) が PausableTurn を使っていない")
            #expect(!source.contains(".task(id: model.aiTurnKey)"), "\(path) に止められない CPU 手番の .task が残っている")
            // 遊び方（「？」）と開始シートの両方で止める。
            #expect(source.contains("guard !isHowToPlayOpen, !showNewGame"), "\(path) の guard が遊び方・開始シートを見ていない")
            #expect(source.contains("isHowToPlayOpen = true"), "\(path) が遊び方シートの表示を拾っていない")
        }
        // 空振り防止。走査が 0 件になって素通りしないよう、既知のゲーム数を下限にする。
        #expect(checked.count >= 8, "走査できた View が少ない: \(checked)")
    }

    @Test("PausableTurn は止めた・再開したで別の鍵になる")
    func pausableTurnDiffersByPaused() {
        let key = AITurnKey(gameSerial: 1, ply: 3)
        #expect(PausableTurn(key: key, paused: true) != PausableTurn(key: key, paused: false))
        #expect(PausableTurn(key: key, paused: true) == PausableTurn(key: key, paused: true))
    }
}
