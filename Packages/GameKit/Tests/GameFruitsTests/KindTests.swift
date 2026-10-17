import Testing
@testable import GameFruits

@Suite("盆栽の段")
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
        #expect(FruitKind.kinmatsu.radius * 4 <= FruitField.Metrics.width)
        #expect(FruitKind.kinmatsu.radius * 2 >= FruitField.Metrics.width * 0.4, "小さすぎると合体の手応えが薄い")
    }

    @Test("落とせる果物は小さい 5 種で、頭が天井に触れない")
    func dropPoolIsTheSmallFive() {
        #expect(FruitKind.dropPool == Array(FruitKind.allCases.prefix(5)))
        let largest = FruitKind.dropPool.map(\.radius).max()!
        #expect(FruitField.Metrics.spawnY + largest < FruitField.Metrics.height)
        #expect(FruitField.Metrics.spawnY - largest > FruitField.Metrics.deadlineY, "持っている果物が危険線に掛からない")
    }

    @Test("合体の連鎖は金の松で終わる")
    func chainEndsAtKinmatsu() {
        var kind = FruitKind.sakura
        var length = 1
        while let next = kind.next {
            kind = next
            length += 1
        }
        #expect(kind == .kinmatsu)
        #expect(length == FruitKind.allCases.count)
        #expect(FruitKind.kinmatsu.next == nil)
    }

    @Test("得点は三角数で、金の松 2 鉢を消す得点は金の松を作る得点より大きい")
    func pointsAreTriangular() {
        #expect(FruitKind.sakura.points == 0)
        #expect(FruitKind.tsubaki.points == 3)
        #expect(FruitKind.fuji.points == 6)
        #expect(FruitKind.ume.points == 10)
        #expect(FruitKind.kinmatsu.points == 66)
        #expect(FruitKind.kinmatsuVanishPoints > FruitKind.kinmatsu.points)
        for (small, large) in zip(FruitKind.allCases, FruitKind.allCases.dropFirst()) {
            #expect(large.points > small.points)
        }
    }

    @Test("11 段の並びは会長決裁どおり（#2361）で、名前と絵の素材名が重複しない")
    func tierOrderMatchesTheDecision() {
        // 桜 → 椿 → 藤 → 梅 → みかん → 銀杏 → 南天 → 紅葉 → 真柏 → 黒松 → 金の松（2026-10-17 会長決裁）。
        #expect(FruitKind.allCases.map(\.name) == ["桜", "椿", "藤", "梅", "みかん", "銀杏", "南天", "紅葉", "真柏", "黒松", "金の松"])
        #expect(FruitKind.dropPool.map(\.name) == ["桜", "椿", "藤", "梅", "みかん"], "落ちてくるのは 1〜5 段")
        #expect(FruitKind.allCases.map(\.artName) == [
            "Bonsai_01_sakura", "Bonsai_02_tsubaki", "Bonsai_03_fuji", "Bonsai_04_ume", "Bonsai_05_mikan",
            "Bonsai_06_icho", "Bonsai_07_nanten", "Bonsai_08_momiji", "Bonsai_09_shinpaku", "Bonsai_10_kuromatsu",
            "Bonsai_11_kinmatsu",
        ])
        let kinds = FruitKind.allCases
        #expect(Set(kinds.map(\.name)).count == kinds.count)
    }

    @Test("段の rawValue は くっつきフルーツ時代のまま（中断データの互換）")
    func rawValuesAreStable() {
        // ブルーベリー(0) → 桜 … メロン(10) → 金の松。並びを変えると保存済みの盤が別の段になる。
        #expect(FruitKind.sakura.rawValue == 0)
        #expect(FruitKind.mikan.rawValue == 4)
        #expect(FruitKind.kinmatsu.rawValue == 10)
        #expect(FruitKind.allCases.count == 11)
    }

    @Test("質量は面積に比例する（大きい果物が小さい果物を押しのける）")
    func massGrowsWithArea() {
        #expect(FruitKind.kinmatsu.mass / FruitKind.sakura.mass > 40)
    }
}
