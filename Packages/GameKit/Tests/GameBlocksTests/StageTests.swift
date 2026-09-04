import Foundation
import Testing
@testable import GameBlocks

/// ステージ定義（#463）。
///
/// レイアウトは文字列なので、**打ち間違いが静かに「詰むステージ」になる**。
/// 目で見て気づける形ではないため、成立条件を機械的に確かめる。
@Suite("ブロック崩しのステージ")
struct StageTests {

    @Test("受け入れ条件どおり 10 面以上ある")
    func hasEnoughStages() {
        #expect(BlocksStage.all.count >= 10)
        #expect(BlocksRules.stageCount == BlocksStage.all.count)
    }

    @Test("ステージ番号は 1 から連番")
    func numbersAreSequential() {
        for (index, stage) in BlocksStage.all.enumerated() {
            #expect(stage.number == index + 1)
        }
        #expect(BlocksStage.stage(number: 1)?.number == 1)
        #expect(BlocksStage.stage(number: BlocksRules.stageCount)?.number == BlocksRules.stageCount)
        #expect(BlocksStage.stage(number: 0) == nil)
        #expect(BlocksStage.stage(number: BlocksRules.stageCount + 1) == nil)
    }

    @Test("どの行も列数ちょうど、既知の記号だけでできている")
    func layoutsAreWellFormed() {
        for stage in BlocksStage.all {
            for (row, line) in stage.rows.enumerated() {
                #expect(
                    line.count == BlocksField.Metrics.columns,
                    "ステージ\(stage.number) の \(row) 行目が \(line.count) 文字"
                )
                for character in line where character != "." {
                    #expect(
                        BlockKind.from(symbol: character) != nil,
                        "ステージ\(stage.number) に未知の記号 '\(character)'"
                    )
                }
            }
        }
    }

    @Test("どのステージにも壊せるブロックがあり、盤の高さに収まっている")
    func everyStageIsPlayable() {
        for stage in BlocksStage.all {
            let field = BlocksField(stage: stage, speed: stage.ballSpeed)
            #expect(field.remainingBreakableCount > 0, "ステージ\(stage.number) に壊せるブロックが無い")
            #expect(!field.isCleared)
            // 最下段のブロックがパドルより十分上にあること（開始直後に接触しない）。
            let lowest = BlocksField.blockRect(row: stage.rows.count - 1, column: 0).minY
            #expect(
                lowest > BlocksField.Metrics.restingBallY + BlocksField.Metrics.ballRadius * 4,
                "ステージ\(stage.number) の最下段が低すぎる（\(lowest)）"
            )
        }
    }

    /// 壊れないブロック（`solid`）が行や列を丸ごと塞ぐと、その向こう側のブロックへ球が
    /// 二度と届かなくなる＝**永遠にクリアできないステージ**になる。レイアウトを足すたびに
    /// 目視で確認するのは無理なので、ここで機械的に禁じる。
    @Test("壊れないブロックが行も列も塞いでいない")
    func solidBlocksNeverSealTheBoard() {
        for stage in BlocksStage.all {
            let field = BlocksField(stage: stage, speed: stage.ballSpeed)
            for row in 0..<field.rowCount {
                let solids = (0..<BlocksField.Metrics.columns)
                    .filter { field.block(row: row, column: $0)?.kind == .solid }
                #expect(
                    solids.count < BlocksField.Metrics.columns,
                    "ステージ\(stage.number) の \(row) 行目が壊れないブロックで塞がっている"
                )
            }
            for column in 0..<BlocksField.Metrics.columns {
                let solids = (0..<field.rowCount)
                    .filter { field.block(row: $0, column: column)?.kind == .solid }
                #expect(
                    solids.count < field.rowCount,
                    "ステージ\(stage.number) の \(column) 列目が壊れないブロックで塞がっている"
                )
            }
        }
    }

    @Test("進むほど球が速くなる")
    func speedIncreasesMonotonically() {
        for (previous, next) in zip(BlocksStage.all, BlocksStage.all.dropFirst()) {
            #expect(next.ballSpeed > previous.ballSpeed)
        }
        #expect(BlocksStage.all[0].ballSpeed == BlocksStage.baseSpeed)
    }

    @Test("硬いブロック・壊れないブロックは序盤には出てこない")
    func difficultyRampsUp() {
        func kinds(_ stage: BlocksStage) -> Set<BlockKind> {
            Set(stage.rows.flatMap { $0.compactMap(BlockKind.from(symbol:)) })
        }
        // 1〜3 面は通常ブロックだけ。
        for stage in BlocksStage.all.prefix(3) {
            #expect(kinds(stage) == [.normal], "ステージ\(stage.number) に通常以外のブロックがある")
        }
        // 4 面以降のどこかで硬い・壊れないブロックが出る。
        #expect(BlocksStage.all.contains { kinds($0).contains(.hard) })
        #expect(BlocksStage.all.contains { kinds($0).contains(.solid) })
    }

    @Test("ブロックの矩形は行・列の並びどおりで、重ならず隙間もない")
    func blockRectsTileTheGrid() {
        let width = BlocksField.Metrics.blockWidth
        let height = BlocksField.Metrics.blockHeight
        let first = BlocksField.blockRect(row: 0, column: 0)
        #expect(first.minX == 0)
        #expect(abs(first.maxY - (BlocksField.Metrics.height - BlocksField.Metrics.topMargin)) < 1e-12)

        for row in 0..<3 {
            for column in 0..<BlocksField.Metrics.columns {
                let rect = BlocksField.blockRect(row: row, column: column)
                #expect(abs((rect.maxX - rect.minX) - width) < 1e-9)
                #expect(abs((rect.maxY - rect.minY) - height) < 1e-9)
                if column > 0 {
                    let left = BlocksField.blockRect(row: row, column: column - 1)
                    #expect(abs(left.maxX - rect.minX) < 1e-9, "列のあいだに隙間・重なりがある")
                }
                if row > 0 {
                    let above = BlocksField.blockRect(row: row - 1, column: column)
                    #expect(abs(above.minY - rect.maxY) < 1e-9, "行のあいだに隙間・重なりがある")
                }
            }
        }
        // 右端がちょうど盤の幅で終わる。
        let last = BlocksField.blockRect(row: 0, column: BlocksField.Metrics.columns - 1)
        #expect(abs(last.maxX - BlocksField.Metrics.width) < 1e-9)
    }
}

@Suite("ブロックの耐久")
struct BlockDurabilityTests {

    @Test("通常ブロックは 1 回で壊れる")
    func normalBreaksInOneHit() {
        let result = Block(kind: .normal).damaged()
        #expect(result.destroyed)
        #expect(result.block == nil)
    }

    @Test("硬いブロックは 2 回当てないと壊れない")
    func hardNeedsTwoHits() {
        let first = Block(kind: .hard).damaged()
        #expect(!first.destroyed)
        #expect(first.block?.remaining == 1)

        let second = first.block!.damaged()
        #expect(second.destroyed)
        #expect(second.block == nil)
    }

    @Test("壊れないブロックは何度当てても残り、クリア条件に数えない")
    func solidNeverBreaks() {
        var block = Block(kind: .solid)
        #expect(!block.isBreakable)
        for _ in 0..<50 {
            let result = block.damaged()
            #expect(!result.destroyed)
            block = result.block!
        }
        #expect(block.kind == .solid)
    }

    @Test("記号と種類が 1 対 1 に対応する")
    func symbolRoundTrip() {
        for kind in BlockKind.allCases {
            #expect(BlockKind.from(symbol: kind.symbol) == kind)
        }
        #expect(BlockKind.from(symbol: ".") == nil)
        #expect(BlockKind.from(symbol: "x") == nil)
    }
}
