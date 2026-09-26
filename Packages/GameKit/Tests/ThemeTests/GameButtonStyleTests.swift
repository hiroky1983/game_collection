import Foundation
import SwiftUI
import Testing
import GameKitTestSupport
@testable import Core

@Suite("意味別のボタンスタイル（#1413）")
struct GameButtonStyleTests {

    @Test("役割ごとの面色は決裁どおり（広告・投了・決定＝コーラル）")
    func roleFills() {
        #expect(GameButtonRole.primary.fill == Theme.Fill.coral)
        #expect(GameButtonRole.destructive.fill == Theme.Fill.coral)
        #expect(GameButtonRole.ad.fill == Theme.Fill.coral)
        #expect(GameButtonRole.undo.fill == Theme.Fill.teal)
        #expect(GameButtonRole.hint.fill == Theme.Fill.yellow)
        #expect(GameButtonRole.skip.fill == Theme.fillMuted)
        #expect(GameButtonRole.declaration.fill == Theme.Fill.purple)
    }

    @Test("見送りだけ白文字・それ以外は onAccent")
    func roleForegrounds() {
        for role in GameButtonRole.allCases {
            let expected = role == .skip ? Color.white : Theme.onAccent
            #expect(role.foreground == expected, "\(role)")
        }
    }

    @Test("ヒントは電球・広告は play.rectangle.fill・他は無し")
    func roleIcons() {
        #expect(GameButtonRole.hint.systemImage == "lightbulb.fill")
        #expect(GameButtonRole.ad.systemImage == "play.rectangle.fill")
        for role in GameButtonRole.allCases where role != .hint && role != .ad {
            #expect(role.systemImage == nil, "\(role)")
        }
    }

    @Test("横いっぱいの角丸は cornerSmall（12）・標的は 44pt")
    func metrics() {
        #expect(GameButtonMetrics.blockCorner == Theme.cornerSmall)
        #expect(GameButtonMetrics.blockCorner == 12)
        #expect(GameButtonMetrics.minTapTarget == 44)
    }
}

/// ゲーム側に**新しい**数字の角丸を書かせない（#1413）。
///
/// 角丸は `Theme.corner` / `Theme.cornerSmall` / `GameButtonStyle` から取る。既存の数字は
/// 各ゲームの移行 Issue で消すので、移行前の箇所は許可リストにファイルごとの件数で置く。
/// **許可リストは減る方向にだけ動かす**（増やす変更は、数字を書かずに Theme の値を使って避ける）。
@Suite("ゲーム側の数字の角丸の走査（#1413）")
struct NumericCornerRadiusScanTests {

    /// `cornerRadius: 10` / `.cornerRadius(10)` / `corner: 10`（`popCard(corner:)`）。
    private static let pattern = #"cornerRadius:\s*[0-9]|\.cornerRadius\(\s*[0-9]|corner:\s*[0-9]"#

    /// 移行前の箇所（`Sources/` からの相対パス → 件数）。
    private static let legacy: [String: Int] = [
        "Game2048/Game2048View.swift": 2,
        "GameBackgammon/BackgammonView.swift": 2,
        "GameBlackjack/BlackjackView.swift": 2,
        "GameChess/ChessView.swift": 7,
        "GameColorRelay/ColorRelayView.swift": 5,
        "GameConcentration/ConcentrationView.swift": 4,
        "GameDaifugo/DaifugoView.swift": 3,
        "GameFifteen/FifteenView.swift": 1,
        "GameFreeCell/FreeCellView.swift": 2,
        "GameMahjong/MahjongStartSheet.swift": 3,
        "GameMahjong/MahjongView+Hand.swift": 1,
        "GameMahjongSolitaire/MahjongSolitaireView.swift": 3,
        "GameMinesweeper/MinesweeperView.swift": 2,
        "GameOthello/OthelloView.swift": 1,
        "GamePoker/PokerSheets.swift": 6,
        "GamePoker/PokerView.swift": 1,
        "GameRoulette/RouletteView.swift": 3,
        "GameRunner/RunnerScene+Dressing.swift": 1,
        "GameRunner/RunnerStoryView.swift": 2,
        "GameRunner/RunnerWorldMap.swift": 1,
        "GameShiritori/ShiritoriView.swift": 4,
        "GameShogi/ShogiView.swift": 9,
        "GameSolitaire/SolitaireRescueOverlay.swift": 3,
        "GameSpeed/SpeedView.swift": 2,
        "GameSpider/SpiderView.swift": 2,
    ]

    private static func sourceFiles() throws -> [(path: String, source: String)] {
        let root = SourceScan.packageRoot.appendingPathComponent("Sources")
        let modules = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Game") && $0.lastPathComponent != "GameKitTestSupport" }
        var files: [(String, String)] = []
        for module in modules {
            let enumerator = FileManager.default.enumerator(at: module, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL, url.pathExtension == "swift" {
                let relative = module.lastPathComponent + String(url.path.dropFirst(module.path.count))
                files.append((relative, SourceScan.strippingComments(try String(contentsOf: url, encoding: .utf8))))
            }
        }
        // 空振り防止。パスの導出が外れて 0 件になると、何も見ずに緑になる。
        #expect(files.count > 100, "走査対象のソースが少なすぎる（\(files.count) 件）")
        return files
    }

    @Test("ゲーム側の数字の角丸は許可リストの件数を超えない")
    func noNewNumericCorners() throws {
        var found: [String: Int] = [:]
        for (path, source) in try Self.sourceFiles() {
            let count = SourceScan.matchCount(of: Self.pattern, in: source)
            if count > 0 { found[path] = count }
        }
        for (path, count) in found {
            let allowed = Self.legacy[path] ?? 0
            #expect(count <= allowed,
                    "\(path) に数字の角丸が \(count) 件（許可 \(allowed)）。Theme.corner / cornerSmall / GameButtonStyle を使う")
        }
        // 許可リストが古びないように、消えた・減った箇所は許可リストからも減らす。
        for (path, allowed) in Self.legacy {
            #expect((found[path] ?? 0) >= allowed, "\(path) の数字の角丸が減った。許可リストを \(found[path] ?? 0) に下げる")
        }
    }

    @Test("パターンが実際に数字の角丸を拾う（対照）")
    func patternMatchesControls() {
        #expect(SourceScan.matchCount(of: Self.pattern, in: "RoundedRectangle(cornerRadius: 10)") == 1)
        #expect(SourceScan.matchCount(of: Self.pattern, in: ".cornerRadius(8)") == 1)
        #expect(SourceScan.matchCount(of: Self.pattern, in: ".popCard(corner: 14)") == 1)
        #expect(SourceScan.matchCount(of: Self.pattern, in: "RoundedRectangle(cornerRadius: Theme.cornerSmall)") == 0)
        #expect(SourceScan.matchCount(of: Self.pattern, in: ".popCard(corner: Theme.cornerSmall)") == 0)
    }
}
