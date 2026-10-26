import Testing
import Foundation
import Core
@testable import GameFruits
import CoreTestSupport

/// 図で見る「はじめての遊び方」（#2826）の図と文言が、実装のルールのとおりになっていること。
@MainActor
@Suite("おじさんの盆栽: はじめての遊び方")
struct FruitsOnboardingTests {
    /// 盤を `seconds` 秒ぶん進め、起きたできごとを全部返す。
    private func run(_ field: inout FruitField, seconds: Double) -> [FruitEvent] {
        var events: [FruitEvent] = []
        var elapsed = 0.0
        while elapsed < seconds {
            events += field.step(dt: 1.0 / 60)
            elapsed += 1.0 / 60
        }
        return events
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(FruitsOnboarding.guide.isWellFormed)
        #expect(FruitsOnboarding.guide.gameID == FruitsModel.gameID)
        #expect(FruitsOnboarding.guide.gameID == FruitsModule().id)
    }

    @Test("目的: 盆栽は 11 種類で、いちばん立派なのは金の松（その上は無い）")
    func lineup() {
        #expect(FruitKind.allCases.count == 11)
        #expect(FruitKind.allCases.last == .kinmatsu)
        #expect(FruitKind.kinmatsu.next == nil)
        #expect(FruitKind.allCases.dropLast().allSatisfy { $0.next != nil })
    }

    @Test("合体の図: 同じ 2 鉢が触れると 1 つ上の段の 1 鉢になる")
    func mergeFigure() {
        let merge = FruitsHowToFigures.merge
        #expect(merge.from.next == merge.into)
        var field = FruitField()
        let r = merge.from.radius
        field.placeFruitForTesting(merge.from, x: 30, y: r)
        field.placeFruitForTesting(merge.from, x: 30 + r * 2, y: r)
        let events = run(&field, seconds: 0.2)
        #expect(events.contains { if case let .merged(from, into, _, _, _) = $0 { from == merge.from && into == merge.into } else { false } })
        #expect(field.fruits.map(\.kind) == [merge.into])
    }

    @Test("違う盆栽どうしは触れてもくっつかない")
    func differentKindsDoNotMerge() {
        var field = FruitField()
        let a = FruitKind.ume
        let b = FruitKind.mikan
        field.placeFruitForTesting(a, x: 30, y: a.radius)
        field.placeFruitForTesting(b, x: 30 + a.radius + b.radius, y: b.radius)
        let events = run(&field, seconds: 1)
        #expect(!events.contains { if case .merged = $0 { true } else { false } })
        #expect(field.fruits.map(\.kind).sorted() == [a, b])
    }

    @Test("金の松どうしがくっつくと 2 つとも消えて 100 点。立派な段を作るほど得点が高い")
    func kinmatsuVanishAndPoints() {
        #expect(FruitKind.kinmatsuVanishPoints == 100)
        #expect(FruitsOnboarding.guide.pages[2].lines[2].contains("\(FruitKind.kinmatsuVanishPoints)"))
        var field = FruitField()
        let r = FruitKind.kinmatsu.radius
        field.placeFruitForTesting(.kinmatsu, x: r, y: r)
        field.placeFruitForTesting(.kinmatsu, x: r * 3, y: r)
        let events = run(&field, seconds: 0.2)
        #expect(events.contains { if case .vanished = $0 { true } else { false } })
        #expect(field.fruits.isEmpty, "2 つとも消える")
        let made = FruitKind.allCases.dropFirst().map(\.points)
        #expect(zip(made, made.dropFirst()).allSatisfy { $0 < $1 }, "1 つ上の段ほど得点が高い")
    }

    @Test("出てくる盆栽の図: 落とす盆栽は小さいほうの 5 種だけ")
    func dropPool() {
        #expect(FruitKind.dropPool.count == 5)
        #expect(FruitKind.dropPool == Array(FruitKind.allCases.prefix(5)))
        for seed in UInt64(1)...UInt64(40) {
            let model = FruitsModel(seed: seed)
            #expect(FruitKind.dropPool.contains(model.heldKind!))
            #expect(FruitKind.dropPool.contains(model.nextKind))
        }
    }

    @Test("1 回でやること: 左右に動かした位置の真下へ落ちる")
    func moveAndDrop() throws {
        let model = FruitsModel(seed: 3)
        let held = try #require(model.heldKind)
        model.moveCursor(to: 30)
        model.drop()
        let fruit = try #require(model.field.fruits.last)
        #expect(fruit.kind == held)
        #expect(fruit.x == 30)
        #expect(fruit.y == FruitField.Metrics.spawnY)
        model.tick(dt: 1.0 / 30)
        #expect(model.field.fruits.last!.y < FruitField.Metrics.spawnY, "下へ落ちる")
        #expect(model.field.fruits.last!.x == 30, "真下に落ちる")
    }

    @Test("ゲームオーバー: 点線より上に 3 秒以上とどまると終わり（3 秒より前は終わらない）")
    func overLineThreeSeconds() {
        #expect(FruitField.Metrics.overLineLimit == 3)
        func column() -> FruitField {
            var field = FruitField()
            let kinmatsu = FruitKind.kinmatsu.radius
            let kuromatsu = FruitKind.kuromatsu.radius
            let shinpaku = FruitKind.shinpaku.radius
            field.placeFruitForTesting(.kinmatsu, x: kinmatsu, y: kinmatsu)
            field.placeFruitForTesting(.kuromatsu, x: kuromatsu, y: kinmatsu * 2 + kuromatsu)
            field.placeFruitForTesting(.shinpaku, x: shinpaku, y: kinmatsu * 2 + kuromatsu * 2 + shinpaku)
            return field
        }
        var early = column()
        #expect(!run(&early, seconds: 2.5).contains(.gameOver))
        #expect(early.isOverLine, "点線より上にいる")
        var late = column()
        #expect(run(&late, seconds: 3.5).contains(.gameOver))
    }

    @Test("ゲームオーバーのあと、広告で続けられるのは 1 回だけ")
    func continueOnlyOnce() throws {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService(), feedback: SpyFeedbackService())
        let kinmatsu = FruitKind.kinmatsu.radius
        let kuromatsu = FruitKind.kuromatsu.radius
        let shinpaku = FruitKind.shinpaku.radius
        let column = [
            Fruit(id: 0, kind: .kinmatsu, x: kinmatsu, y: kinmatsu, age: 5, hasTouched: true),
            Fruit(id: 1, kind: .kuromatsu, x: kuromatsu, y: kinmatsu * 2 + kuromatsu, age: 5, hasTouched: true),
            Fruit(id: 2, kind: .shinpaku, x: shinpaku, y: kinmatsu * 2 + kuromatsu * 2 + shinpaku, age: 5, hasTouched: true),
        ]
        let snapshot = FruitsSnapshot(fruits: column, cursorX: 50, score: 0, heldKind: .tsubaki, nextKind: .ume,
                                      continueUsed: false, seed: 1, drawCount: 0, dropCount: 3, hasMadeKinmatsu: false)
        try store.save(snapshot, for: FruitsModel.gameID)
        let model = FruitsModel(services: services)
        for _ in 0..<(60 * 4) { model.tick(dt: 1.0 / 60) }
        #expect(model.phase == .gameOver)
        #expect(model.continueAfterAd(forGame: model.gameSerial))
        #expect(model.phase == .playing)
        // 同じ柱を積み直して、もう一度終わらせても 2 回目は無い。
        let again = FruitsSnapshot(fruits: column, cursorX: 50, score: 0, heldKind: .tsubaki, nextKind: .ume,
                                   continueUsed: model.continueUsed, seed: 1, drawCount: 0, dropCount: 3, hasMadeKinmatsu: false)
        try store.save(again, for: FruitsModel.gameID)
        let reopened = FruitsModel(services: services)
        for _ in 0..<(60 * 4) { reopened.tick(dt: 1.0 / 60) }
        #expect(reopened.phase == .gameOver)
        #expect(!reopened.continueAfterAd(forGame: reopened.gameSerial))
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        let figureTexts = ["落ちてくるのはこの 5 種", "左右に動かす", "指を離す", "真下に落ちる", "同じ盆栽が触れる",
                           "1つ立派に", "小さい", "金の松", "点線より上は危ない"]
        for text in FruitsOnboarding.guide.texts + figureTexts {
            #expect(GameFruits.tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
