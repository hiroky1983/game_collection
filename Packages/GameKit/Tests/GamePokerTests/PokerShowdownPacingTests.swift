import Testing
import Foundation
import Core
import GameKitTestSupport
@testable import GamePoker
import CoreTestSupport

// MARK: - Mocks

// MARK: - 局面の組み立て

/// 「もう 1 回交換」を使い終えた 1 回めの交換前を注入する。確定すると CPU の交換のあと待たずに決着し、
/// CPU は全部残す形なので、フラッシュのプレイヤーが勝つ。
@MainActor
private func makeModelBeforeShowdown(showdownRevealDelay: Duration) -> (PokerModel, SpyFeedbackService) {
    let spy = SpyFeedbackService()
    let (model, _) = PokerFixture.model(
        PokerFixture.snapshot(player: PokerFixture.flush, extraExchangeUsed: true),
        playLog: PokerFixture.freshPlayLog(), feedback: spy,
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

        model.confirmExchange()

        #expect(model.phase == .result)
        #expect(model.winner == .player)
        #expect(spy.notices == [.success])
        #expect(model.outcomeNoticeTask == nil)
    }

    @Test("遅れがあれば勝敗の触覚だけを役名が出るまで待たせ、精算と記録は遅らせない")
    func noticeWaitsForTheReveal() async {
        let (model, spy) = makeModelBeforeShowdown(showdownRevealDelay: .milliseconds(1))

        model.confirmExchange()

        #expect(model.phase == .result)
        #expect(model.winner == .player)
        #expect(model.totalPoints == 12, "点の加算は決着の瞬間")
        #expect(spy.notices.isEmpty, "CPU の手札が裏向きのうちに勝敗が伝わっていない")

        await model.outcomeNoticeTask?.value

        #expect(spy.notices == [.success], "役名が出る瞬間に勝敗の触覚が 1 回だけ鳴る")
    }

    @Test("待っているあいだに次の回を配ったら、前の回の勝敗の触覚は鳴らさない")
    func staleNoticeIsDroppedAfterTheNextRoundStarts() async {
        let (model, spy) = makeModelBeforeShowdown(showdownRevealDelay: .milliseconds(1))
        model.confirmExchange()
        let task = model.outcomeNoticeTask

        model.nextRound()
        await task?.value

        #expect(model.phase == .exchange)
        #expect(spy.notices.isEmpty, "次の回の配りのあとに前の回の勝敗が鳴っている")
    }

    // MARK: - 定数と結線

    @Test("役名が出る時刻は 5 枚の反転が終わる時刻と一致する")
    func revealDelayMatchesTheFlip() {
        #expect(PokerMotion.showdownRevealDelay
            == .milliseconds(Int((PokerMotion.showdownTotalDuration * 1000).rounded())))
    }

    @Test("画面が遅れを Model へ渡している")
    func viewIsWired() throws {
        let view = try SourceScan.moduleSources("GamePoker")
        #expect(view.contains(
            "showdownRevealDelay: Motion.isReduceMotionEnabled ? .zero : PokerMotion.showdownRevealDelay"
        ))
    }

    private static func source(_ file: String) throws -> String {
        try SourceScan.packageSource("Sources/GamePoker/\(file)")
    }
}
