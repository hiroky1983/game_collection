import Testing
import Foundation
@testable import GameMinesweeper

/// 連鎖開放の演出（#203）。
///
/// 「どのマスがどの順で開いたか」は画面を見るまで分からないが、**波の割り当て**と
/// **遅延の上限**は純粋な値なのでここで固定できる。上限が外れると、上級（15×15）で
/// 盤面がほぼ全開になったときに最後のマスまで 0.7 秒以上かかり、その間タップが利かなくなる。
@Suite("マインスイーパーの連鎖開放")
@MainActor
struct MinesweeperRevealTests {

    typealias Metrics = MinesweeperMetrics

    // MARK: - 遅延の計算

    @Test("タップしたマス自身（第0波）は遅延なし")
    func firstWaveHasNoDelay() {
        #expect(Metrics.revealDelay(forWave: 0) == 0)
    }

    @Test("波が進むほど遅れる（上限に達するまで）")
    func delayGrowsWithWave() {
        #expect(Metrics.revealDelay(forWave: 1) == Metrics.revealWaveStep)
        #expect(Metrics.revealDelay(forWave: 2) == Metrics.revealWaveStep * 2)
        for wave in 1..<40 {
            #expect(Metrics.revealDelay(forWave: wave) <= Metrics.revealDelay(forWave: wave + 1))
        }
    }

    /// 受け入れ条件3「盤面全体が開くケースでも処理が重くならない」の機械的な担保。
    @Test("どれだけ波が進んでも遅延は上限を超えない")
    func delayIsCapped() {
        // 上級（15×15）の対角を横切る最悪ケースより十分大きい波でも上限内。
        for wave in [10, 15, 30, 100, 10_000] {
            #expect(Metrics.revealDelay(forWave: wave) <= Metrics.revealMaxDelay)
        }
        #expect(Metrics.revealDelay(forWave: 10_000) == Metrics.revealMaxDelay)
    }

    @Test("上級の盤を全開にしても、最後のマスが開き終わるまで 0.6 秒以内")
    func fullBoardCascadeStaysSnappy() {
        // 15×15 の盤で波は最大でも 14（Chebyshev 距離の最大値）。
        let worstWave = 14
        let total = Metrics.revealDelay(forWave: worstWave) + Metrics.revealDuration
        #expect(total < 0.6, "連鎖の待ち時間が長すぎる: \(total) 秒")
    }

    @Test("波が負でも遅延は 0 に丸められる（呼び出し側の取りこぼしで演出が止まらない）")
    func negativeWaveIsClamped() {
        #expect(Metrics.revealDelay(forWave: -1) == 0)
    }

    // MARK: - 波の割り当て（Model）

    /// 地雷 0 の盤は全マスが `adjacentMines == 0` なので必ず全開になる。
    /// このとき波はタップ地点からの Chebyshev 距離（8 近傍の BFS の深さ）と一致するはず。
    @Test("連鎖の波はタップ地点からの距離になる")
    func waveMatchesChebyshevDistance() {
        let model = MinesweeperModel(rows: 5, cols: 5, mines: 0)
        model.tap(row: 2, col: 2)

        for r in 0..<5 {
            for c in 0..<5 {
                #expect(model.cells[r][c].isRevealed, "(\(r),\(c)) が開いていない")
                let expected = max(abs(r - 2), abs(c - 2))
                #expect(
                    model.cells[r][c].revealWave == expected,
                    "(\(r),\(c)) の波が \(model.cells[r][c].revealWave)（期待 \(expected)）"
                )
            }
        }
    }

    @Test("角からの連鎖でも波は非減少に並ぶ")
    func wavesAreMonotonicFromCorner() {
        let model = MinesweeperModel(rows: 6, cols: 6, mines: 0)
        model.tap(row: 0, col: 0)

        #expect(model.cells[0][0].revealWave == 0)
        #expect(model.cells[5][5].revealWave == 5)
        // 隣り合うマスの波の差は 1 以内（BFS なので飛び番にならない）。
        for r in 0..<6 {
            for c in 0..<6 where c + 1 < 6 {
                #expect(abs(model.cells[r][c].revealWave - model.cells[r][c + 1].revealWave) <= 1)
            }
        }
    }

    @Test("地雷を踏んだときの一斉公開には波を付けない（全部同時に出す）")
    func revealAllMinesHasNoWave() {
        let model = MinesweeperModel(rows: 6, cols: 6, mines: 8)
        // 1 手目は必ず安全なので、地雷が置かれるまで 1 度タップする。
        model.tap(row: 0, col: 0)
        model.giveUp()

        for r in 0..<6 {
            for c in 0..<6 where model.cells[r][c].isMine && model.cells[r][c].isRevealed {
                #expect(model.cells[r][c].revealWave == 0)
            }
        }
    }

    @Test("新規ゲームで波がリセットされる")
    func newGameResetsWaves() {
        let model = MinesweeperModel(rows: 5, cols: 5, mines: 0)
        model.tap(row: 2, col: 2)
        #expect(model.cells[0][0].revealWave > 0)

        model.newGame(rows: 5, cols: 5, mines: 0)
        for r in 0..<5 {
            for c in 0..<5 {
                #expect(model.cells[r][c].revealWave == 0)
            }
        }
    }

    // MARK: - タップ標的（#203 受け入れ条件2）

    @Test("切り替えボタンの一辺は Apple HIG の 44pt 以上")
    func toggleMeetsTapTarget() {
        #expect(Metrics.minimumTapTarget >= 44)
        #expect(Metrics.toggleButtonMinSide >= Metrics.minimumTapTarget)
    }

    /// 定数を用意しただけで View 側が使っていなければ意味が無いので、実際の使用箇所を見る。
    /// **`statusBar` の宣言ブロックだけを切り出してから**走査する（ファイル全体を対象にすると、
    /// 後から別の場所に同じ文字列が入ったときに検証対象が静かにすり替わる・#201 の教訓）。
    @Test("ステータスバーの切り替えボタンが 2 つとも定数で 44pt を確保している")
    func statusBarTogglesUseTheConstant() throws {
        let block = try Self.declarationBlock(
            containing: "private var statusBar: some View {",
            inSourceFile: "GameMinesweeper/MinesweeperView.swift"
        )

        let buttons = block.filter { $0.contains("Button {") }.count
        #expect(buttons == 2, "ステータスバーのボタン数が変わっている（\(buttons) 個）")

        let uses = block.filter { $0.contains("MinesweeperMetrics.toggleButtonMinSide") }.count
        #expect(
            uses == 4,
            "44pt を確保する frame の指定が \(uses) 箇所しかない（ボタン 2 個 × minWidth/minHeight = 4 箇所のはず）"
        )

        // 旧実装の余白指定が残っていたら、それは 44pt を潰す指定なので落とす。
        #expect(!block.contains { $0.contains("padding(.vertical, 5)") })
    }

    /// マスの演出の修飾子はマスに 1 つだけ（入れ子にすると内側が外側を打ち消す・#199 の教訓）。
    @Test("マスの演出は gameAnimation 1 つだけで書かれている")
    func cellViewHasASingleAnimationModifier() throws {
        let block = try Self.declarationBlock(
            containing: "private func cellView(row: Int, col: Int, size: CGFloat) -> some View {",
            inSourceFile: "GameMinesweeper/MinesweeperView.swift"
        )
        let modifiers = block.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix(".gameAnimation(") }.count
        #expect(modifiers == 1, "cellView の .gameAnimation が \(modifiers) 個ある（1 個であること）")
    }

    // MARK: - Helpers

    /// 宣言行からインデントが戻るまでを 1 ブロックとして切り出す。
    /// ファイル全体を走査すると、同じ文字列が前方に増えた瞬間に検証対象が変わってしまう（#201）。
    private static func declarationBlock(
        containing declaration: String,
        inSourceFile path: String
    ) throws -> [String] {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameMinesweeperTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources")
        let text = try String(contentsOf: sources.appendingPathComponent(path), encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let starts = lines.indices.filter { lines[$0].contains(declaration) }
        #expect(starts.count == 1, "宣言 '\(declaration)' が \(starts.count) 箇所にある（1 箇所であること）")
        let start = try #require(starts.first)

        let indent = lines[start].prefix { $0 == " " }.count
        var end = start + 1
        while end < lines.count {
            let trimmed = lines[end].trimmingCharacters(in: .whitespaces)
            let lineIndent = lines[end].prefix { $0 == " " }.count
            if !trimmed.isEmpty, lineIndent <= indent, trimmed.hasPrefix("}") { break }
            end += 1
        }
        return Array(lines[start...min(end, lines.count - 1)])
    }
}
