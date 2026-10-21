import Testing
import Foundation
@testable import CoreEngine

@Suite("最後に選んだ開始条件（#2611）")
@MainActor
struct LastStartTests {
    private struct Choice: Codable, Equatable { var level: Int; var name: String }

    private func makeLog(_ name: String) -> (PlayLog, UserDefaults) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (PlayLog(defaults: defaults), defaults)
    }

    @Test("未保存は nil。保存→読み出しの往復・ゲームごとに独立・上書き・再起動で復元")
    func roundTrip() {
        let name = "asobiba.laststart.tests.roundtrip"
        let (log, defaults) = makeLog(name)
        #expect(log.lastStart(Choice.self, gameID: "a") == nil)

        log.saveLastStart(Choice(level: 2, name: "むずかしい"), gameID: "a")
        log.saveLastStart(Choice(level: 1, name: "ふつう"), gameID: "b")
        #expect(log.lastStart(Choice.self, gameID: "a") == Choice(level: 2, name: "むずかしい"))
        #expect(log.lastStart(Choice.self, gameID: "b") == Choice(level: 1, name: "ふつう"))

        log.saveLastStart(Choice(level: 0, name: "かんたん"), gameID: "a")
        #expect(PlayLog(defaults: defaults).lastStart(Choice.self, gameID: "a") == Choice(level: 0, name: "かんたん"))
        defaults.removePersistentDomain(forName: name)
    }

    @Test("形式が合わない値は nil に倒れる（既定値で起動できる）")
    func mismatchedShapeIsNil() {
        let name = "asobiba.laststart.tests.mismatch"
        let (log, defaults) = makeLog(name)
        log.saveLastStart("turtle", gameID: "a")
        #expect(log.lastStart(Choice.self, gameID: "a") == nil)
        defaults.set(["a": Data("壊れた".utf8)], forKey: PlayLog.lastStartKey)
        #expect(log.lastStart(String.self, gameID: "a") == nil)
        defaults.removePersistentDomain(forName: name)
    }

    @Test("「プレイ記録を消去」で消える。キーは allKeys に入り、保存は 1 キーだけ")
    func clearedWithPlayRecords() {
        let name = "asobiba.laststart.tests.clear"
        let (log, defaults) = makeLog(name)
        log.saveLastStart(Choice(level: 2, name: "x"), gameID: "a")
        log.saveLastStart(Choice(level: 1, name: "y"), gameID: "b")
        #expect(PlayLog.allKeys.contains(PlayLog.lastStartKey))
        #expect(Set((defaults.persistentDomain(forName: name) ?? [:]).keys) == [PlayLog.lastStartKey])

        log.clear()
        #expect(defaults.object(forKey: PlayLog.lastStartKey) == nil)
        #expect(log.lastStart(Choice.self, gameID: "a") == nil)
        defaults.removePersistentDomain(forName: name)
    }
}
