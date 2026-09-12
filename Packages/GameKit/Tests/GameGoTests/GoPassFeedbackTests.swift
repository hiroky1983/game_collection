import Testing
import Foundation
import Core
@testable import GameGo

/// パスと着手拒否の手応え（#664）。
///
/// パスは**盤が一切変わらない唯一の着手**で、石も震えも出ない。拒否も同じく盤が動かない。
/// どちらも「押せたのか」を伝える経路がモデル側の合図だけなので、ここで固定する。

private final class MemoryStore: SnapshotStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func save<T: Codable>(_ value: T, for key: String) throws {
        storage[key] = try JSONEncoder().encode(value)
    }
    func load<T: Codable>(_ type: T.Type, for key: String) -> T? {
        guard let data = storage[key] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for key: String) { storage[key] = nil }
    func exists(for key: String) -> Bool { storage[key] != nil }
}

@MainActor
private final class SpyFeedback: FeedbackService {
    private(set) var impacts: [FeedbackImpact] = []
    private(set) var notices: [FeedbackNotice] = []

    func impact(_ style: FeedbackImpact) { impacts.append(style) }
    func notify(_ type: FeedbackNotice) { notices.append(type) }
}

@MainActor
private func makeModel(_ feedback: FeedbackService) -> GoModel {
    GoModel(services: GameServices(snapshots: MemoryStore(), ads: NoopAdService(), feedback: feedback))
}

@Suite("囲碁のパスの手応え")
@MainActor
struct GoPassFeedbackTests {

    @Test("人間のパスは札の契機を増やし、軽い触覚を鳴らす")
    func humanPassRaisesBannerAndHaptic() {
        let spy = SpyFeedback()
        let model = makeModel(spy)
        model.newGame(humanSide: .black, level: .easy)
        let before = model.passEventID

        model.pass()

        #expect(model.passEventID == before + 1)
        #expect(spy.impacts == [.light], "パスは盤が動かないので、触覚が唯一の手応えになる")
    }

    @Test("CPU のパスも札の契機を増やすが、触覚は鳴らさない")
    func cpuPassRaisesBannerOnly() {
        let spy = SpyFeedback()
        let model = makeModel(spy)
        model.newGame(humanSide: .black, level: .easy)
        model.tap(row: 4, col: 4)                 // 人間の着手（medium が 1 回鳴る）
        let before = model.passEventID

        model.applyMoveForTesting(.pass)          // CPU（白）のパス

        #expect(model.passEventID == before + 1, "相手がパスしたことが分からないと終局へ進めない")
        #expect(spy.impacts == [.medium], "CPU の手では触覚を鳴らさない")
    }

    @Test("終局になる 2 回目のパスでは、軽い触覚を終局の合図に重ねない")
    func secondPassDoesNotStackHaptics() {
        let spy = SpyFeedback()
        let model = makeModel(spy)
        model.newGame(humanSide: .white, level: .easy)   // 黒（CPU）が先番
        model.applyMoveForTesting(.pass)                 // CPU のパス
        #expect(!model.isAITurn)

        model.pass()                                     // 人間の 2 回目のパス

        #expect(model.phase == .scoring)
        #expect(spy.impacts.isEmpty, "同じ着手で 2 度鳴ると合図が濁る")
        #expect(spy.notices == [.warning])
    }

    @Test("盤の意味が変わる操作は、出したままの札を畳む契機を増やす")
    func boardChangingActionsDismissBanner() async {
        let model = makeModel(SpyFeedback())

        // 新規対局
        var before = model.passBannerDismissID
        model.newGame(humanSide: .black, level: .easy)
        #expect(model.passBannerDismissID == before + 1)

        // 待った（人間 → CPU の 2 手を戻す）
        model.tap(row: 4, col: 4)
        model.applyMoveForTesting(.play(row: 2, col: 2))
        #expect(model.canUndo)
        before = model.passBannerDismissID
        model.undoLastExchange()
        #expect(model.passBannerDismissID == before + 1)

        // 対局続行（連続パスを解く）
        model.applyMoveForTesting(.pass)
        model.applyMoveForTesting(.pass)
        #expect(model.phase == .scoring)
        before = model.passBannerDismissID
        model.resumePlay()
        #expect(model.phase == .playing)
        #expect(model.passBannerDismissID == before + 1)

        // 終局の確定
        model.applyMoveForTesting(.pass)
        model.applyMoveForTesting(.pass)
        await model.evaluateEndgameIfNeeded()
        #expect(model.endgame != nil)
        before = model.passBannerDismissID
        model.acceptEndgame()
        #expect(model.phase == .finished)
        #expect(model.passBannerDismissID == before + 1)
    }

    @Test("投了も札を畳む契機を増やす")
    func resignDismissesBanner() {
        let model = makeModel(SpyFeedback())
        model.newGame(humanSide: .black, level: .easy)
        let before = model.passBannerDismissID

        model.resign()

        #expect(model.passBannerDismissID == before + 1)
    }

    @Test("札の通し番号は対局をまたいでも 0 に戻さない")
    func passEventIDIsMonotonic() {
        let model = makeModel(SpyFeedback())
        model.newGame(humanSide: .black, level: .easy)
        model.pass()
        let afterPass = model.passEventID
        #expect(afterPass > 0)

        model.newGame(humanSide: .black, level: .easy)

        // 0 に戻すと、View が「値が変わった」を札を出す合図として誤読する（将棋 #519）。
        #expect(model.passEventID == afterPass)
    }
}

@Suite("囲碁の着手拒否の理由")
@MainActor
struct GoRejectionNoticeTests {

    @Test("拒否理由は打てた時点で消える")
    func rejectionClearsOnNextMove() {
        let model = makeModel(SpyFeedback())
        model.newGame(humanSide: .black, level: .easy)
        model.tap(row: 4, col: 4)
        model.applyMoveForTesting(.play(row: 2, col: 2))   // 人間の手番に戻す

        model.tap(row: 4, col: 4)                          // すでに石がある
        #expect(model.lastRejection == .illegal(.occupied))

        model.tap(row: 0, col: 0)                          // 打てる交点
        #expect(model.lastRejection == nil, "次に打てたら理由の 1 行は引っ込む")
    }

    @Test("パスでも拒否理由は消える")
    func rejectionClearsOnPass() {
        let model = makeModel(SpyFeedback())
        model.newGame(humanSide: .black, level: .easy)
        model.tap(row: 4, col: 4)
        model.applyMoveForTesting(.play(row: 2, col: 2))
        model.tap(row: 4, col: 4)
        #expect(model.lastRejection != nil)

        model.pass()

        #expect(model.lastRejection == nil)
    }

    @Test("待った・新規対局でも拒否理由は消える")
    func rejectionClearsOnUndoAndNewGame() {
        let model = makeModel(SpyFeedback())
        model.newGame(humanSide: .black, level: .easy)
        model.tap(row: 4, col: 4)
        model.applyMoveForTesting(.play(row: 2, col: 2))
        model.tap(row: 4, col: 4)
        #expect(model.lastRejection != nil)

        model.undoLastExchange()
        #expect(model.lastRejection == nil)

        model.tap(row: 4, col: 4)
        model.applyMoveForTesting(.play(row: 2, col: 2))
        model.tap(row: 4, col: 4)
        #expect(model.lastRejection != nil)

        model.newGame(humanSide: .black, level: .easy)
        #expect(model.lastRejection == nil)
    }

    /// View は `message` をそのまま帯に出す（#664 で初めて参照した）。空文字だと帯だけが出る。
    @Test("View が出す拒否理由は空にならない")
    func rejectionMessagesAreNotEmpty() {
        let reasons: [GoTapRejection] = [
            .notYourTurn,
            .illegal(.outOfBoard), .illegal(.occupied), .illegal(.suicide),
            .illegal(.ko), .illegal(.superko), .illegal(.gameOver),
        ]
        for reason in reasons {
            #expect(!reason.message.isEmpty, "\(reason) の理由が空")
        }
    }
}
