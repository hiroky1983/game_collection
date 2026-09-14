import Testing
import Foundation
import Core
import GameKitTestSupport
@testable import GamePoker

// MARK: - Mocks

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

@MainActor
private final class SpyFeedbackService: FeedbackService {
    private(set) var impacts: [FeedbackImpact] = []
    private(set) var notices: [FeedbackNotice] = []
    func impact(_ style: FeedbackImpact) { impacts.append(style) }
    func notify(_ type: FeedbackNotice) { notices.append(type) }
}

// MARK: - 局面の組み立て

/// 2 巡目のベッティングを中断データとして注入する。CPU は役なしなので `bet2Action(.check)` に
/// チェックで受けてショーダウンになり、ワンペアのプレイヤーが勝つ（`PokerRuleSetTests` と同じ手口）。
@MainActor
private func makeModelBeforeShowdown(showdownRevealDelay: Duration) -> (PokerModel, SpyFeedbackService) {
    var nextCardID = 0
    func c(_ rank: Int, _ suit: PokerSuit) -> PokerCard {
        defer { nextCardID += 1 }
        return PokerCard(id: nextCardID, suit: suit, rank: rank)
    }
    let store = MemorySnapshotStore()
    let snap = PokerSnapshot(
        playerHand: [c(11, .spades), c(11, .diamonds), c(8, .clubs), c(4, .spades), c(2, .hearts)],
        cpuHand: [c(14, .hearts), c(10, .clubs), c(7, .diamonds), c(5, .clubs), c(3, .spades)],
        deck: [],
        playerChips: 100, cpuChips: 100, pot: 40,
        phase: .betting2, currentBet: 0,
        playerBetInRound: 0, cpuBetInRound: 0,
        cpuFolded: false, cpuAction: "", rules: .standard
    )
    try? store.save(snap, for: "poker")
    let spy = SpyFeedbackService()
    let model = PokerModel(
        services: GameServices(
            snapshots: store, ads: NoopAdService(), feedback: spy,
            playLog: PlayLog(defaults: UserDefaults(suiteName: "poker-pacing-\(UUID().uuidString)")!)
        ),
        showdownRevealDelay: showdownRevealDelay
    )
    return (model, spy)
}

// MARK: - Tests

@Suite("ポーカー: ショーダウンの間（#667）")
@MainActor
struct PokerShowdownPacingTests {

    @Test("遅れが 0 なら従来どおり決着の瞬間に勝敗の触覚を鳴らす")
    func zeroDelayNotifiesImmediately() {
        let (model, spy) = makeModelBeforeShowdown(showdownRevealDelay: .zero)

        model.bet2Action(.check)

        #expect(model.phase == .result)
        #expect(model.winner == .player)
        #expect(spy.notices == [.success])
        #expect(model.outcomeNoticeTask == nil)
    }

    @Test("遅れがあれば勝敗の触覚だけを役名が出るまで待たせ、精算と記録は遅らせない")
    func noticeWaitsForTheReveal() async {
        let (model, spy) = makeModelBeforeShowdown(showdownRevealDelay: .milliseconds(1))

        model.bet2Action(.check)

        #expect(model.phase == .result)
        #expect(model.winner == .player)
        #expect(model.pot == 0, "ポットの精算は従来どおり決着の瞬間")
        #expect(model.playerChips == 140)
        #expect(model.recordResult != nil, "記録の確定は遅らせない")
        #expect(spy.notices.isEmpty, "CPU の手札が裏向きのうちに勝敗が伝わっていない")

        await model.outcomeNoticeTask?.value

        #expect(spy.notices == [.success], "役名が出る瞬間に勝敗の触覚が 1 回だけ鳴る")
    }

    @Test("待っているあいだに次の局を始めたら、前の局の勝敗の触覚は鳴らさない")
    func staleNoticeIsDroppedAfterTheNextRoundStarts() async {
        let (model, spy) = makeModelBeforeShowdown(showdownRevealDelay: .milliseconds(1))
        model.bet2Action(.check)
        let task = model.outcomeNoticeTask

        model.startGame()
        await task?.value

        #expect(model.phase == .betting1)
        #expect(spy.notices.isEmpty, "次の局の配りのあとに前の局の勝敗が鳴っている")
    }

    @Test("待っているあいだにセッションをやり直したら、前の局の勝敗の触覚は鳴らさない")
    func staleNoticeIsDroppedAfterRestartingTheSession() async {
        let (model, spy) = makeModelBeforeShowdown(showdownRevealDelay: .milliseconds(1))
        model.bet2Action(.check)
        let task = model.outcomeNoticeTask
        #expect(task != nil)

        model.restartSession()
        await task?.value

        #expect(model.phase == .idle)
        #expect(model.outcomeNoticeTask == nil)
        #expect(spy.notices.isEmpty, "やり直した新しいセッションで前の局の勝敗が鳴っている")
    }

    // MARK: - 定数と結線

    @Test("役名が出る時刻は 5 枚の反転が終わる時刻と一致する")
    func revealDelayMatchesTheFlip() {
        #expect(PokerMotion.showdownRevealDelay
            == .milliseconds(Int((PokerMotion.showdownTotalDuration * 1000).rounded())))
    }

    @Test("ショーダウンのポットは反転が終わるまで動かず、画面が遅れを Model へ渡している")
    func viewAndMotionAreWired() throws {
        let motion = try Self.source("PokerMotion.swift")
        #expect(motion.contains("static let potSettle: Animation = potChange.delay(showdownTotalDuration)"))

        let view = try Self.source("PokerView.swift")
        #expect(view.contains(".gameAnimation(potAnimation, value: model.pot)"))
        #expect(view.contains(
            "model.phase == .result && !model.cpuFolded ? PokerMotion.potSettle : PokerMotion.potChange"
        ))
        #expect(view.contains(
            "showdownRevealDelay: Motion.isReduceMotionEnabled ? .zero : PokerMotion.showdownRevealDelay"
        ))
    }

    private static func source(_ file: String) throws -> String {
        try SourceScan.packageSource("Sources/GamePoker/\(file)")
    }
}
