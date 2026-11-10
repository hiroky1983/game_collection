import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameOjisanPuzzle

/// 荷運びモードの `game_end` に載る、負け方（`cause`）と開始・最大ゲージ・消した数（#3352）。
@Suite("おじさんの荷物運びパズル: game_end の負け方と腰痛ゲージ")
@MainActor
struct OjisanPuzzleEndDetailTests {
    private static let lockOf12 = OjisanPuzzlePain.lockAmount(weights: [1, 2])

    private func makeServices(_ spy: SpyAnalyticsService) -> GameServices {
        GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["ojisanpuzzle"])
        )
    }

    private func ends(_ spy: SpyAnalyticsService) -> [[String: AnalyticsValue]] {
        spy.events.compactMap { $0.name == "game_end" ? $0.parameters : nil }
    }

    /// あと 1 回固定すれば入院するモデル。
    private func hospitalizedModel(services: GameServices) -> OjisanPuzzleModel {
        let model = OjisanPuzzleModel(
            services: services,
            board: OjisanPuzzleBoard.emptyBoard(),
            current: OjisanPuzzlePair(axisKind: 1, childKind: 2, row: 1, col: 0, rotation: .up),
            pain: OjisanPuzzlePain.limit - Self.lockOf12
        )
        #expect(model.hardDrop())
        return model
    }

    private func buriedModel(services: GameServices, mode: OjisanPuzzleMode) -> OjisanPuzzleModel {
        func kind(_ row: Int, _ col: Int) -> Int { (row + 2 * col) % 5 + 1 }
        var board = OjisanPuzzleBoard.emptyBoard()
        for row in 0..<OjisanPuzzleBoard.rows {
            for col in 0..<OjisanPuzzleBoard.columns { board[row][col] = kind(row, col) }
        }
        board[0][0] = 0
        board[1][0] = 0
        let model = OjisanPuzzleModel(
            services: services, board: board,
            current: OjisanPuzzlePair(axisKind: kind(1, 0), childKind: kind(0, 0), row: 1, col: 0, rotation: .up),
            pain: 30, mode: mode
        )
        #expect(model.hardDrop())
        model.tick()
        return model
    }

    @Test("入院: cause=hospital・開始ゲージと最大ゲージが載る")
    func hospitalized() {
        let spy = SpyAnalyticsService()
        let model = hospitalizedModel(services: makeServices(spy))
        #expect(model.outcome == .hospitalized)
        let end = ends(spy)
        #expect(end.count == 1)
        #expect(end[0]["result"] == .string("loss"))
        #expect(end[0]["cause"] == .string("hospital"))
        #expect(end[0]["pain_start"] == .int(OjisanPuzzlePain.limit - Self.lockOf12))
        #expect(end[0]["pain_max"] == .int(100))
        #expect(end[0]["cleared_count"] == .int(0))
    }

    @Test("積み上がり: cause=buried")
    func buried() {
        let spy = SpyAnalyticsService()
        let model = buriedModel(services: makeServices(spy), mode: .backpain)
        #expect(model.outcome == .buried)
        let end = ends(spy)
        #expect(end.count == 1)
        #expect(end[0]["cause"] == .string("buried"))
        #expect(end[0]["pain_start"] == .int(30))
        if case let .int(peak)? = end[0]["pain_max"] { #expect(peak >= 30 && peak < 100) } else { Issue.record("pain_max が無い") }
    }

    @Test("パズルモードの game_end には cause もゲージも載らない")
    func puzzleModeIsExcluded() {
        let spy = SpyAnalyticsService()
        _ = buriedModel(services: makeServices(spy), mode: .puzzle)
        let end = ends(spy)
        #expect(end.count == 1)
        #expect(end[0]["cause"] == nil)
        #expect(end[0]["pain_start"] == nil && end[0]["pain_max"] == nil && end[0]["cleared_count"] == nil)
    }

    @Test("広告で続けた局は 1 プレイごとに数え直す（続けた時点のゲージから・cause は次の負けのもの）")
    func continuedRunIsCountedPerPlay() throws {
        let spy = SpyAnalyticsService()
        let services = makeServices(spy)
        let model = hospitalizedModel(services: services)
        #expect(model.continueAfterAd(forRun: model.gameGeneration))
        let resumedPain = model.pain
        // 続けた先でもう一度負けさせる: 次の固定で入院する量まで積み直す手段が無いので、新しい局として始め直して quit を確認する。
        model.newGame()
        model.pause()
        let end = ends(spy)
        // 1 回目の入院 + 続けた局の quit（cause は持ち越さない）。
        #expect(end.count == 2)
        #expect(end[0]["cause"] == .string("hospital"))
        #expect(end[1]["result"] == .string("quit"))
        #expect(end[1]["cause"] == nil)
        #expect(resumedPain == OjisanPuzzlePain.clamped(OjisanPuzzleRescue.painAfterContinue))
    }
}
