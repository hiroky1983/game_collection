import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameSpider


/// 使い捨ての UserDefaults で PlayLog を作る。`reopen` は「アプリ再起動」を表し、同じ保存先から作り直す。
@MainActor
private struct LastStartFixture {
    let name = "asobiba.laststart.tests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let store = MemorySnapshotStore()
    init() {
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }
    func services() -> GameServices {
        GameServices(snapshots: store, ads: NoopAdService(), playLog: PlayLog(defaults: defaults))
    }
}

@MainActor
@Suite("最後に選んだ開始条件（#2611）・GameSpider")
struct GameSpiderLastStartTests {
    @Test("2 スートで始めると、次のモデルの初期ルールが 2 スートになる。記録が無ければ 1 スート")
    func remembersSuitCount() {
        let f = LastStartFixture()
        #expect(SpiderModel(services: f.services()).rules.suitCount == .one)
        SpiderModel(services: f.services()).newGame(rules: SpiderRuleSet(suitCount: .two))
        f.store.clear(for: "spider")   // 中断データが消えても（終局後でも）覚えている
        #expect(SpiderModel(services: f.services()).rules.suitCount == .two)
    }
}
