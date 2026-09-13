import Testing
import Foundation
import SwiftUI
import Core
@testable import Game2048

/// 視聴のあいだに起きること（「もう一度」を押す等）を差し込める広告。常に視聴完了で返す。
@MainActor
private final class DuringAdService: AdService {
    private(set) var shownCount = 0
    var duringAd: (@MainActor () -> Void)?

    func makeBannerView(width: CGFloat) -> AnyView? { nil }
    func showInterstitial() async {}
    func showRewardedAd() async -> Bool {
        shownCount += 1
        duringAd?()
        return true
    }
}

/// 再起動をまたぐ挙動を、ファイルを触らずに再現するための中断データ置き場。
private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

/// #122: 広告視聴後のコンティニューが「盤面を動かせないまま戻される」不具合の回帰テスト。
/// 復活処理が決定的（乱数なし）になったので、盤面そのものを厳密な期待値で表明できる。
@Suite("2048 コンティニュー（#122）")
@MainActor
struct Game2048ContinueTests {
    /// 終局盤面（空きマス 0・合体可能な隣接 0）。
    static let deadBoard = [
        [2, 4, 8, 4],
        [16, 8, 32, 16],
        [4, 64, 128, 32],
        [16, 8, 4, 8],
    ]

    private func makeFinishedModel(score: Int = 1234) -> Game2048Model {
        let model = Game2048Model(board: Self.deadBoard, score: score)
        #expect(model.gameOver, "前提: 終局している盤面から始める")
        return model
    }

    @Test("コンティニュー直後に必ず動かせる（空きマス4・新タイルは沸かない）")
    func continueLeavesPlayableBoard() {
        let model = makeFinishedModel()
        model.continueAfterAd()

        #expect(!model.gameOver)
        #expect(model.continueUsed)
        #expect(Game2048Logic.emptyCells(model.board).count == 4, "新タイルを置かないので空きは4のまま")
        #expect(Direction.allCases.contains { Game2048Logic.slide(model.board, $0).moved })
    }

    @Test("スコアはコンティニュー前から引き継がれる")
    func continueKeepsScore() {
        let model = makeFinishedModel(score: 4321)
        model.continueAfterAd()
        #expect(model.score == 4321)
    }

    @Test("最大タイルはコンティニューで失われない")
    func continueKeepsHighestTile() {
        let model = makeFinishedModel()
        model.continueAfterAd()
        #expect(model.board.flatMap { $0 }.max() == 128)
    }

    @Test("コンティニューは1回だけ。2回目は盤面もフラグも変えない")
    func continueIsAllowedOnlyOnce() {
        let model = makeFinishedModel()
        model.continueAfterAd()
        let boardAfterFirst = model.board

        // 続きを遊んで再び終局させる。
        playUntilGameOver(model)
        #expect(model.gameOver)
        let boardAtSecondGameOver = model.board

        model.continueAfterAd()
        #expect(model.gameOver, "2回目のコンティニューは成立しない")
        #expect(model.board == boardAtSecondGameOver, "2回目では盤面に手を加えない")
        #expect(boardAfterFirst != boardAtSecondGameOver, "前提: 1回目の後に実際に遊べている")
    }

    @Test("コンティニュー後は最低4手動かせ、そのまま終局まで遊びきれる")
    func continuedGameCanBePlayedToTheEnd() {
        let model = makeFinishedModel()
        model.continueAfterAd()

        let moves = playUntilGameOver(model)
        #expect(moves >= 4, "空きマス4を確保しているので最低4手は保証される（実際は \(moves) 手）")
        #expect(model.gameOver, "終局まで到達できる（無限ループにも詰まりにもならない）")
    }

    @Test("再起動してもコンティニュー権は復活しない（スナップショットに使用済みを持つ）")
    func continueUsedSurvivesRestart() {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())

        let before = Game2048Model(services: services, board: Self.deadBoard, score: 1234)
        before.continueAfterAd()
        #expect(before.continueUsed)

        // アプリを起動し直した状態を、同じスナップショット置き場から作り直して再現する。
        let restored = Game2048Model(services: services)
        #expect(restored.continueUsed, "使用済みフラグが復元される")
        #expect(restored.board == before.board)
        #expect(restored.score == 1234)

        // 続きを遊んで再び終局しても、2回目のコンティニューは成立しない。
        playUntilGameOver(restored)
        let boardAtGameOver = restored.board
        restored.continueAfterAd()
        #expect(restored.gameOver)
        #expect(restored.board == boardAtGameOver)
    }

    @Test("`continueUsed` を持たない旧バージョンの中断データも読める")
    func decodesLegacySnapshotWithoutContinueUsed() throws {
        let legacy = Data(#"{"board":[[2,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]],"score":8}"#.utf8)
        let snapshot = try JSONDecoder().decode(Game2048Snapshot.self, from: legacy)
        #expect(snapshot.score == 8, "キーが増えても既存の中断データを失わせない")
        #expect(snapshot.continueUsed == false, "欠けていたら『まだ使っていない』として読む")
    }

    @Test("広告のあいだに新規ゲームを始めたら、前の局のコンティニューは新しい局に乗らない（#729）")
    func continueForReplacedGameIsRejected() {
        let model = makeFinishedModel()
        let game = model.gameSerial
        model.newGame()
        // 新しい局も終局させ、「終局していない」という状態の確認だけでは弾けない形にする。
        playUntilGameOver(model)
        let boardAtGameOver = model.board

        #expect(!model.continueAfterAd(forGame: game), "入れ替わった局へコンティニューを適用している")
        #expect(model.gameOver)
        #expect(!model.continueUsed, "新しい局のコンティニュー権が前の局の広告で消えている")
        #expect(model.board == boardAtGameOver)
        #expect(model.continueAfterAd(forGame: model.gameSerial), "今の局に対する広告なら適用できる")
    }

    @Test("広告のロード中に「もう一度」を押したら、見終えても適用せず失敗アラートを出す（#729）")
    func rescueReportsUnavailableWhenGameIsReplacedDuringAd() async {
        let ads = DuringAdService()
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: ads)
        let model = Game2048Model(services: services, board: Self.deadBoard, score: 1234)
        #expect(model.gameOver, "前提: 終局している盤面から始める")
        let rescue = RewardedRescue()
        ads.duringAd = { model.newGame() }

        // View と同じく、広告を出す前にどの局に対するコンティニューかを控える。
        let game = model.gameSerial
        rescue.request(services, gameID: model.gameID, purpose: .continue, guardedBy: .checkedByGrant) {
            model.continueAfterAd(forGame: game)
        }
        // スタブの広告は中断点を持たないので、MainActor のジョブが一巡すれば走り切っている。
        for _ in 0..<10 { await Task.yield() }

        #expect(ads.shownCount == 1)
        #expect(rescue.showsUnavailable, "見終えたのに適用できなかったことを知らせていない")
        #expect(!rescue.showsNotEarned, "見終えたのに「最後まで視聴しなかった」と知らせている")
        #expect(!model.continueUsed, "入れ替わった局にコンティニュー済みの印が付いている")
        #expect(!model.gameOver)
    }

    /// 動かせる方向が無くなるまで動かし続け、実際に動いた手数を返す。
    /// 新タイルの生成は乱数なので、手数は実行ごとに変わる。
    @discardableResult
    private func playUntilGameOver(_ model: Game2048Model, limit: Int = 10_000) -> Int {
        var moves = 0
        while !model.gameOver, moves < limit {
            guard let direction = Direction.allCases.first(where: {
                Game2048Logic.slide(model.board, $0).moved
            }) else {
                Issue.record("終局していないのに動かせる方向が無い: \(model.board)")
                break
            }
            model.move(direction)
            moves += 1
        }
        #expect(moves < limit, "上限に達した = 終局に到達できていない")
        return moves
    }
}
