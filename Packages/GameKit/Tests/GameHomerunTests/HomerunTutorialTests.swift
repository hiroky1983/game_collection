import Testing
import Foundation
@testable import GameHomerun

/// 操作の説明（#1763）: 初回の記録・1 球目の前の停止・匂わせの文言。
@MainActor
struct HomerunTutorialTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeDefaults() -> (UserDefaults, String) {
        let name = "asobiba.homerun.tutorial.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func 初回は未見で_見たと記録すると別のモデルでも見たことになる() {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let first = HomerunModel(defaults: defaults, now: Self.t0)
        #expect(!first.hasSeenTutorial)
        first.markTutorialSeen()
        #expect(first.hasSeenTutorial)
        // 端末に残るので、作り直したモデル（次の起動）でも自動では出さない。
        #expect(HomerunModel(defaults: defaults, now: Self.t0).hasSeenTutorial)
    }

    @Test func 別の端末_別の保存先では記録が共有されない() {
        let (a, nameA) = makeDefaults()
        let (b, nameB) = makeDefaults()
        defer {
            UserDefaults().removePersistentDomain(forName: nameA)
            UserDefaults().removePersistentDomain(forName: nameB)
        }
        HomerunModel(defaults: a, now: Self.t0).markTutorialSeen()
        #expect(!HomerunModel(defaults: b, now: Self.t0).hasSeenTutorial)
    }

    @Test func 説明を出している間は投球を止め_閉じたら1球目を始める() throws {
        let (defaults, name) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let model = HomerunModel(defaults: defaults, now: Self.t0)
        #expect(model.start(now: Self.t0))
        model.hold(.sheet, true, now: Self.t0)
        #expect(model.isHeld)
        #expect(model.pitchStart == nil)
        #expect(model.nextWake == nil)
        let closed = Self.t0.addingTimeInterval(5)
        model.hold(.sheet, false, now: closed)
        #expect(!model.isHeld)
        #expect(model.phase == .pitching)
        #expect(model.pitchStart != nil)
        // 止めていた間は球数を進めない。
        #expect(model.pitchNumber == 1)
    }

    @Test func 月の匂わせは条件の数値も答えも書かない() {
        let text = HomerunTutorial.text(page: 2)
        #expect(text.title == "？？？")
        #expect(text.body == "ど真ん中を、ジャストで打ち抜くと……？")
        #expect(HomerunTutorial.pageCount == HomerunTutorial.steps.count + 1)
        for page in 0..<HomerunTutorial.pageCount {
            let t = HomerunTutorial.text(page: page)
            #expect(t.body.allSatisfy { !$0.isNumber })
        }
    }
}
