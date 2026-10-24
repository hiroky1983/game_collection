import Testing
import Foundation
@testable import CoreEngine

@Suite("遊んだことがあるか（ハブの「未プレイ」の印・#2849）")
@MainActor
struct HasPlayedTests {
    private func makeLog(_ name: String) -> (PlayLog, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (PlayLog(defaults: defaults), defaults)
    }

    @Test("何も遊んでいなければ未プレイ。1回遊ぶとそのゲームだけ消え、再起動後も保たれる")
    func playedOnlyAfterFinish() {
        let name = "asobiba.hasplayed.tests.finish"
        let (log, defaults) = makeLog(name)
        #expect(!log.hasPlayed(gameID: "a"))
        log.recordFinish(gameID: "a")
        #expect(log.hasPlayed(gameID: "a"))
        #expect(!log.hasPlayed(gameID: "b"))
        #expect(PlayLog(defaults: defaults).hasPlayed(gameID: "a"))
        defaults.removePersistentDomain(forName: name)
    }

    @Test("記録だけが残っている（区分つきのキー）場合も遊んだとみなし、前方一致の別ゲームは巻き込まない")
    func recordsCountAndPrefixIsExact() {
        let name = "asobiba.hasplayed.tests.records"
        let (log, defaults) = makeLog(name)
        log.recordResult(gameID: "ab", outcome: .win, score: GameScore(metric: .winLoss, variant: "hard"))
        #expect(log.hasPlayed(gameID: "ab"))
        #expect(!log.hasPlayed(gameID: "a"))
        defaults.removePersistentDomain(forName: name)
    }

    @Test("記録を消去すると全部が未プレイに戻る")
    func clearResets() {
        let name = "asobiba.hasplayed.tests.clear"
        let (log, defaults) = makeLog(name)
        log.recordFinish(gameID: "a")
        log.clear()
        #expect(!log.hasPlayed(gameID: "a"))
        defaults.removePersistentDomain(forName: name)
    }
}
