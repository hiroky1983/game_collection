import Testing
import Foundation
import GameKitTestSupport
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

    /// `HomerunTutorial.swift` は `Canvas` の中で文字を描かない（花札の帯の文字と同じ形・#2905・#2945）。
    /// `TimelineView(.animation)` で毎フレーム描き直す図（`HomerunTutorialFigure.marks`）の中で `ctx.draw(Text)`
    /// を使うと、描き直すたびに文字の組版をやり直し、主スレッドが詰まる危険がある。「離す」「離す！」の文字と
    /// 指のアイコンは、Canvas の外（overlay の `Text`/`Image`）に出してある。
    @Test("HomerunTutorial.swift は Canvas の中で文字を描いていない")
    func doesNotDrawTextInCanvas() throws {
        let code = try SourceScan.packageSource("Sources/GameHomerun/HomerunTutorial.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        #expect(!code.contains(".draw(Text"), "Canvas の中で文字を描いている")
        #expect(!code.contains("resolve(Text"), "Canvas の中で文字を測っている・描いている")
        // 実際の描画が overlay の Text/Image に移っていること（退行防止の素振り）。
        #expect(code.contains("Text(released ? tr(\"離す！\") : tr(\"離す\"))"))
        #expect(code.contains("hand.point.up.left.fill"))
    }
}
