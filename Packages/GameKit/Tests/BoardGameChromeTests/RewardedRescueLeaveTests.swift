import Foundation
import Testing
@testable import Core

/// 広告ヒントの読みは画面を離れたら取り消す（#2195。無料経路は #1903）。
@MainActor
@Suite("広告救済の離脱取り消し（#2195）")
struct RewardedRescueLeaveTests {

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test("読みの最中に画面を離れると Task が cancel され、結果の通知も出ない")
    func leavingCancelsTheRead() async {
        let generation = GameScreenGeneration()
        let rescue = RewardedRescue()
        var sawCancelled = false
        var gate: CheckedContinuation<Void, Never>?
        var granted = false
        rescue.requestHandledByModel(withOutcome: {
            await withCheckedContinuation { gate = $0 }
            sawCancelled = Task.isCancelled
            return .unavailable
        }, until: generation, whenGranted: { granted = true })
        await settle()
        #expect(rescue.isWatching)

        generation.advance()
        gate?.resume()
        await settle()

        #expect(sawCancelled, "画面を離れても読みの Task が生きている")
        #expect(!rescue.isWatching)
        #expect(!rescue.showsUnavailable, "離脱後に出す先の無いアラートを立てている")
        #expect(!granted)
    }

    @Test("離脱しなければ従来どおり結果が通知される")
    func staysTheSameWithoutLeaving() async {
        let generation = GameScreenGeneration()
        let rescue = RewardedRescue()
        var granted = false
        rescue.requestHandledByModel(withOutcome: { .granted }, until: generation, whenGranted: { granted = true })
        await settle()
        #expect(granted)
        #expect(!rescue.isWatching)

        let other = RewardedRescue()
        other.requestHandledByModel(withOutcome: { .unavailable }, until: generation)
        await settle()
        #expect(other.showsUnavailable)
    }

    @Test("先読みつきの形も離脱で cancel される")
    func readAheadVariantIsCancelledToo() async {
        let generation = GameScreenGeneration()
        let rescue = RewardedRescue()
        var gate: CheckedContinuation<Void, Never>?
        var sawCancelled = false
        rescue.requestHandledByModel(withOutcome: { _ in
            await withCheckedContinuation { gate = $0 }
            sawCancelled = Task.isCancelled
            return .notEarned
        }, until: generation)
        await settle()

        generation.advance()
        gate?.resume()
        await settle()

        #expect(sawCancelled)
        #expect(!rescue.showsNotEarned)
        #expect(!rescue.isReading && !rescue.isWatching)
    }
}
