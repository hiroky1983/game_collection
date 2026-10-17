import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameOjisanPuzzle

/// 負けたあとの「広告を見て続ける」（リワード・1 局 1 回・#2013）。広告の段取りは `RewardedRescue` が持つので、
/// ここは報酬を受け取ったあとの `continueAfterAd(forRun:)` の効果だけを見る。
@Suite("おじさんの荷物運びパズル: 広告で続ける")
@MainActor
struct OjisanPuzzleContinueTests {
    private static let lockOf12 = OjisanPuzzlePain.lockAmount(weights: [1, 2])

    private func makeLog(_ suite: String) -> PlayLog {
        let name = "asobiba.ojisanpuzzle.continue.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PlayLog(defaults: defaults)
    }

    private func makeServices(_ log: PlayLog) -> GameServices {
        GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
    }

    /// あと 1 回固定すれば入院するモデル（荷運びモード）。
    private func hospitalizedModel(services: GameServices?) -> OjisanPuzzleModel {
        let model = OjisanPuzzleModel(
            services: services,
            board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            pain: OjisanPuzzlePain.limit - Self.lockOf12
        )
        #expect(model.hardDrop())
        return model
    }

    /// 何も消えない並びで全面を埋め、次の固定で積み上がりになるモデル。
    private func buriedModel(services: GameServices?, mode: OjisanPuzzleMode) -> OjisanPuzzleModel {
        func kind(_ row: Int, _ col: Int) -> Int { (row + 2 * col) % 5 + 1 }
        var board = OjisanPuzzleBoard.emptyBoard()
        for row in 0..<OjisanPuzzleBoard.rows {
            for col in 0..<OjisanPuzzleBoard.columns { board[row][col] = kind(row, col) }
        }
        board[0][0] = 0
        board[1][0] = 0
        let model = OjisanPuzzleModel(
            services: services,
            board: board,
            current: OjisanPuzzlePair(axisKind: kind(1, 0), childKind: kind(0, 0), row: 1, col: 0, rotation: .up),
            mode: mode
        )
        #expect(model.hardDrop())
        model.tick()
        return model
    }

    @Test("入院から続けると腰痛ゲージが半分に戻り、盤と得点はそのまま")
    func continueFromHospitalized() throws {
        let log = makeLog("hospital")
        let model = hospitalizedModel(services: makeServices(log))
        #expect(model.outcome == .hospitalized)
        #expect(model.canContinue)
        let boardBefore = model.board
        let scoreBefore = model.score
        #expect(log.record(gameID: OjisanPuzzleModel.gameID, variant: "backpain")?.losses == 1)

        #expect(model.continueAfterAd(forRun: model.gameGeneration))
        #expect(model.pain == OjisanPuzzleRescue.painAfterContinue)
        #expect(model.outcome == nil)
        #expect(model.continueUsed)
        #expect(model.score == scoreBefore)
        #expect(model.board == boardBefore)
        #expect(model.recordResult == nil)
        // 直前の負けは無かったことになる（1 プレイを 2 回と数えない）。
        #expect(log.record(gameID: OjisanPuzzleModel.gameID, variant: "backpain")?.losses == 0)

        // 後片付けのあと、次の組が出て遊びが続く。
        model.tick()
        model.tick()
        #expect(model.outcome == nil)
        #expect(model.current != nil)
    }

    @Test("積み上がりから続けると上から 4 段が片づき、次の組が出る")
    func continueFromBuried() {
        let log = makeLog("buried")
        let model = buriedModel(services: makeServices(log), mode: .backpain)
        #expect(model.outcome == .buried)
        #expect(model.canContinue)

        #expect(model.continueAfterAd(forRun: model.gameGeneration))
        for row in 0..<OjisanPuzzleRescue.clearedRows {
            #expect(model.board[row].allSatisfy { $0 == 0 }, "行 \(row) は片づいている")
        }
        #expect(model.board[OjisanPuzzleRescue.clearedRows].contains { $0 != 0 }, "5 段目以降は残る")
        model.tick()
        model.tick()
        #expect(model.outcome == nil)
        #expect(model.current != nil)
    }

    @Test("パズルモードでも積み上がりから続けられ、得点は引き継ぐ")
    func continueInPuzzleMode() {
        let log = makeLog("puzzle")
        let model = buriedModel(services: makeServices(log), mode: .puzzle)
        #expect(model.outcome == .buried)
        #expect(log.record(gameID: OjisanPuzzleModel.gameID, variant: "puzzle")?.losses == 1)
        #expect(model.continueAfterAd(forRun: model.gameGeneration))
        #expect(model.pain == 0, "ゲージの無いモードでゲージは動かない")
        #expect(log.record(gameID: OjisanPuzzleModel.gameID, variant: "puzzle")?.losses == 0)
        model.tick()
        model.tick()
        #expect(model.current != nil)
    }

    @Test("続けられるのは 1 局に 1 回だけ")
    func continueOnlyOnce() {
        let model = buriedModel(services: nil, mode: .puzzle)
        #expect(model.continueAfterAd(forRun: model.gameGeneration))
        #expect(!model.canContinue)
        #expect(!model.continueAfterAd(forRun: model.gameGeneration))
    }

    @Test("決着していない局・クリアでは続けられない")
    func notOfferedWithoutLoss() {
        let model = OjisanPuzzleModel(services: nil, mode: .backpain, seed: 1)
        #expect(!model.canContinue)
        #expect(!model.continueAfterAd(forRun: model.gameGeneration))
    }

    @Test("広告中に始め直されたら適用しない")
    func rejectedAfterNewGame() {
        let model = buriedModel(services: nil, mode: .puzzle)
        let generation = model.gameGeneration
        model.newGame()
        #expect(model.gameGeneration > generation)
        #expect(!model.continueAfterAd(forRun: generation))
        #expect(!model.continueUsed)
    }

    @Test("始め直すと、また 1 回続けられる")
    func newGameResetsContinue() {
        let model = buriedModel(services: nil, mode: .puzzle)
        #expect(model.continueAfterAd(forRun: model.gameGeneration))
        model.newGame()
        #expect(!model.continueUsed)
    }

    @Test("片づける段数は荷物のある一番上の行から数える")
    func clearingTopRowsStartsAtTopLuggage() {
        var board = OjisanPuzzleBoard.emptyBoard()
        for row in 5..<OjisanPuzzleBoard.rows { board[row][0] = 1 }
        let cleared = OjisanPuzzleRescue.clearingTopRows(board)
        #expect(OjisanPuzzleCleanup.topLuggageRow(cleared) == 5 + OjisanPuzzleRescue.clearedRows)
        #expect(OjisanPuzzleRescue.clearingTopRows(OjisanPuzzleBoard.emptyBoard()) == OjisanPuzzleBoard.emptyBoard())
    }
}
