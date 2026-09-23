import Testing
@testable import GameFruits

@Suite("果物の種類")
struct KindTests {
    @Test("小さい順に並び、隣どうしの大きさの差は 1.15〜1.4 倍")
    func radiiGrowMonotonically() {
        let kinds = FruitKind.allCases
        for (small, large) in zip(kinds, kinds.dropFirst()) {
            let ratio = large.radius / small.radius
            #expect(ratio > 1.15 && ratio < 1.4, "\(small.name) → \(large.name) の比が \(ratio)")
        }
    }

    @Test("いちばん大きい果物でも盤の幅の半分に収まる（2 個並べられる）")
    func largestFitsTwiceAcross() {
        #expect(FruitKind.melon.radius * 4 <= FruitField.Metrics.width)
        #expect(FruitKind.melon.radius * 2 >= FruitField.Metrics.width * 0.4, "小さすぎると合体の手応えが薄い")
    }

    @Test("落とせる果物は小さい 5 種で、頭が天井に触れない")
    func dropPoolIsTheSmallFive() {
        #expect(FruitKind.dropPool == Array(FruitKind.allCases.prefix(5)))
        let largest = FruitKind.dropPool.map(\.radius).max()!
        #expect(FruitField.Metrics.spawnY + largest < FruitField.Metrics.height)
        #expect(FruitField.Metrics.spawnY - largest > FruitField.Metrics.deadlineY, "持っている果物が危険線に掛からない")
    }

    @Test("合体の連鎖はメロンで終わる")
    func chainEndsAtMelon() {
        var kind = FruitKind.blueberry
        var length = 1
        while let next = kind.next {
            kind = next
            length += 1
        }
        #expect(kind == .melon)
        #expect(length == FruitKind.allCases.count)
        #expect(FruitKind.melon.next == nil)
    }

    @Test("得点は三角数で、メロン 2 個を消す得点はメロンを作る得点より大きい")
    func pointsAreTriangular() {
        #expect(FruitKind.blueberry.points == 0)
        #expect(FruitKind.cherry.points == 3)
        #expect(FruitKind.strawberry.points == 6)
        #expect(FruitKind.lime.points == 10)
        #expect(FruitKind.melon.points == 66)
        #expect(FruitKind.melonVanishPoints > FruitKind.melon.points)
        for (small, large) in zip(FruitKind.allCases, FruitKind.allCases.dropFirst()) {
            #expect(large.points > small.points)
        }
    }

    @Test("地の色は全種で異なり、名前も重複しない")
    func colorsAndNamesAreDistinct() {
        let kinds = FruitKind.allCases
        #expect(Set(kinds.map(\.baseColor)).count == kinds.count)
        #expect(Set(kinds.map(\.shadeColor)).count == kinds.count)
        #expect(Set(kinds.map(\.name)).count == kinds.count)
        for kind in kinds {
            #expect(kind.baseColor != kind.shadeColor)
        }
    }

    @Test("質量は面積に比例する（大きい果物が小さい果物を押しのける）")
    func massGrowsWithArea() {
        #expect(FruitKind.melon.mass / FruitKind.blueberry.mass > 40)
    }
}
