import Testing
@testable import GameRunner

/// 世界（`RunnerWorld`・#703）。ステージ番号で固定に切り替わる 3 つの景色の境界と配色を固定する。
@Suite("チャリンコおじさん: 世界")
struct RunnerWorldTests {

    @Test("1〜6 面は朝、7〜12 面は夕方、13〜18 面は夜（境界を含む）")
    func stageRanges() {
        #expect(RunnerWorld.world(forStage: 1) == .morning)
        #expect(RunnerWorld.world(forStage: 6) == .morning)
        #expect(RunnerWorld.world(forStage: 7) == .evening)
        #expect(RunnerWorld.world(forStage: 12) == .evening)
        #expect(RunnerWorld.world(forStage: 13) == .night)
        #expect(RunnerWorld.world(forStage: 18) == .night)
    }

    @Test("範囲外は夜（ショーケースの 0 番・将来足す 19 面以降も従来の見た目で出す）")
    func outOfRangeIsNight() {
        #expect(RunnerWorld.world(forStage: 0) == .night)
        #expect(RunnerWorld.world(forStage: -1) == .night)
        #expect(RunnerWorld.world(forStage: 19) == .night)
        #expect(RunnerWorld.world(forStage: RunnerRules.stageCount + 1) == .night)
    }

    @Test("全 18 面がちょうど 6 面ずつ 3 つの世界に分かれる")
    func everyStageHasAWorld() {
        let counts = Dictionary(grouping: RunnerStage.all, by: { RunnerWorld.world(forStage: $0.number) })
            .mapValues(\.count)
        #expect(counts == [.morning: 6, .evening: 6, .night: 6])
        #expect(RunnerWorld.stagesPerWorld * RunnerWorld.allCases.count == RunnerRules.stageCount)
    }

    @Test("世界ごとに空の色が全部違う")
    func skiesDiffer() {
        let skies = RunnerWorld.allCases.map(\.palette.sky)
        #expect(Set(skies).count == RunnerWorld.allCases.count)
    }

    /// **既に遊ばれている 13〜18 面の見た目を変えない**。夜の配色は世界を分ける前の
    /// `RunnerPalette` の値そのもの（リテラルで固定する——定数参照だと定数を変えたとき
    /// テストが黙って追随する）。
    @Test("夜の配色は世界を分ける前の値と一致する")
    func nightMatchesLegacyPalette() {
        let night = RunnerWorld.night.palette
        #expect(night.sky == 0x2E4066)
        #expect(night.cloud == 0xFFFFFF)
        #expect(night.cloudAlpha == 0.55)
        #expect(night.hillFar == 0x263A5C)
        #expect(night.hillNear == 0x1F2F4C)
        #expect(night.groundTop == 0x22C3BE)
        #expect(night.groundBody == 0x6B4A32)
        #expect(night.rockLight == 0xC2C8D2)
        #expect(night.rockBody == 0x939AA8)
        #expect(night.rockDark == 0x565D6B)
        // `RunnerPalette` 側の定数も同じ値のまま（描画以外の参照先として残してある）。
        #expect(RunnerPalette.sky == night.sky)
        #expect(RunnerPalette.groundTop == night.groundTop)
        #expect(RunnerPalette.groundBody == night.groundBody)
        #expect(RunnerPalette.hillFar == night.hillFar)
        #expect(RunnerPalette.hillNear == night.hillNear)
    }

    /// 乗り手は空を背に描かれる（`RunnerPalette.pants` の注記）。どの世界の空も、脚・車体・服と
    /// 同じ色にならないことを、色相の差で機械的に確かめる（同じ系統の濃淡は使わない）。
    @Test("どの世界の空も乗り手の色（脚・車体・服）と色相が離れている")
    func skiesAreFarFromRiderHues() {
        func hue(_ hex: UInt32) -> Double {
            let r = Double((hex >> 16) & 0xFF) / 255
            let g = Double((hex >> 8) & 0xFF) / 255
            let b = Double(hex & 0xFF) / 255
            let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
            guard delta > 0 else { return 0 }
            var h: Double
            if maxC == r { h = (g - b) / delta }
            else if maxC == g { h = 2 + (b - r) / delta }
            else { h = 4 + (r - g) / delta }
            h *= 60
            return h < 0 ? h + 360 : h
        }
        func hueDistance(_ a: UInt32, _ b: UInt32) -> Double {
            let d = abs(hue(a) - hue(b))
            return min(d, 360 - d)
        }
        for world in RunnerWorld.allCases {
            for rider in [RunnerPalette.pants, RunnerPalette.bike] {
                #expect(
                    hueDistance(world.palette.sky, rider) >= 40,
                    "\(world) の空 \(String(world.palette.sky, radix: 16)) と乗り手 \(String(rider, radix: 16))"
                )
            }
        }
    }

    @Test("道路の配色は世界ごとに違い、路面と白線・路肩の明度差がある")
    func roadPalettes() {
        let roads = [RunnerWorld.morning, .evening, .night].map(\.road)
        #expect(Set(roads.map(\.asphalt)).count == 3)
        for road in roads {
            // 白線は路面より明るい（読める）、路肩は路面と違う色（縁石で区切れる）
            #expect(luma(road.line) > luma(road.asphalt) + 60, "白線が路面に埋もれる: \(road)")
            #expect(road.shoulder != road.asphalt)
        }
    }

    private func luma(_ hex: UInt32) -> Double {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    @Test("遠景の飾りは世界ごとに決まっている")
    func scenery() {
        #expect(RunnerWorld.morning.scenery == .townHouses)
        #expect(RunnerWorld.evening.scenery == .riverside)
        #expect(RunnerWorld.night.scenery == .cityLights)
    }

    @Test("読み上げにはステージ番号に世界の名前が添えられる")
    func accessibilityLabelIncludesWorld() {
        #expect(RunnerAccessibility.stageLabelWithWorld(number: 3, total: 18) == "ステージ 3 / 18、朝の下町")
        #expect(RunnerAccessibility.stageLabelWithWorld(number: 7, total: 18) == "ステージ 7 / 18、夕方の川沿い")
        #expect(RunnerAccessibility.stageLabelWithWorld(number: 18, total: 18) == "ステージ 18 / 18、夜の繁華街")
        // 見た目の文言（番号だけ）は変えない。
        #expect(RunnerAccessibility.stageLabel(number: 3, total: 18) == "ステージ 3 / 18")
    }
}
