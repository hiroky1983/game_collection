import Testing
import Foundation
import Core
@testable import Game2048
import CoreTestSupport

/// #2615: プレイ中のヘッダーに出す「ベスト」。
@Suite("2048 プレイ中のベスト（#2615）")
@MainActor
struct Game2048LiveBestTests {
    private func makeServices(suite: String, savedBest: Int?) -> GameServices {
        let name = "asobiba.2048livebest.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        if let savedBest {
            _ = log.recordResult(gameID: "2048", outcome: .loss,
                                 score: GameScore(metric: .points, points: savedBest))
        }
        return GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: log)
    }

    private let board = [[2, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]

    @Test("記録もスコアも無ければ出さない")
    func hiddenWithoutRecordAndScore() {
        let model = Game2048Model(services: makeServices(suite: "none", savedBest: nil), board: board, score: 0)
        #expect(model.liveBestScore == nil)
    }

    @Test("記録が無くてもスコアが付けば、そのスコアがベストとして追従する")
    func followsScoreWithoutRecord() {
        let model = Game2048Model(services: makeServices(suite: "noRecord", savedBest: nil), board: board, score: 120)
        #expect(model.liveBestScore == 120)
    }

    @Test("保存済みの自己ベストが高ければそれを出し、スコアが超えた瞬間に追従する")
    func savedBestThenFollows() {
        let services = makeServices(suite: "saved", savedBest: 5000)
        let low = Game2048Model(services: services, board: board, score: 100)
        #expect(low.liveBestScore == 5000)
        let high = Game2048Model(services: services, board: board, score: 5200)
        #expect(high.liveBestScore == 5200)
    }

    @Test("今回の最高タイルは盤の最大値（#2812）")
    func highestTileIsBoardMax() {
        let model = Game2048Model(services: makeServices(suite: "tile", savedBest: nil),
                                  board: [[2, 512, 0, 0], [0, 64, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], score: 0)
        #expect(model.highestTile == 512)
    }
}
