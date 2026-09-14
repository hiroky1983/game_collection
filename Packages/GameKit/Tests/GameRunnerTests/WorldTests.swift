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
        for world in RunnerWorld.allCases {
            for rider in [RunnerPalette.pants, RunnerPalette.bike] {
                #expect(
                    hueDistance(world.palette.sky, rider) >= 40,
                    "\(world) の空 \(String(world.palette.sky, radix: 16)) と乗り手 \(String(rider, radix: 16))"
                )
            }
        }
    }

    /// 鳥は丘を背に飛ぶ（鳥の帯は地面から 13〜17、丘は 19・34 まで届く）。鳥が出る面の世界と、
    /// 鳥が出るエンドレス（`number == 0` は朝の下町で描く・#675）の世界で、丘と鳥の胴が
    /// 色相か明るさで離れていることを確かめる（#818: 5・6 面の緑の鳥が朝の緑の丘に紛れた）。
    @Test("鳥が飛ぶ世界の丘は、鳥の胴と色相が 40° 以上か明るさが 0.3 以上離れている")
    func hillsAreFarFromBird() {
        let stageWorlds = Set(RunnerStage.all
            .filter { stage in stage.hazards.contains { $0.kind == .bird } }
            .map { RunnerWorld.world(forStage: $0.number) })
        // 空振り防止: 5・6 面（朝）と 13〜15・18 面（夜）の鳥を拾えていること。
        #expect(stageWorlds.isSuperset(of: [.morning, .night]))
        for world in stageWorlds.union([.morning]) {
            for hill in [world.palette.hillFar, world.palette.hillNear] {
                let lumaGap = abs(luma(hill) - luma(RunnerPalette.birdBody)) / 255
                #expect(
                    hueDistance(hill, RunnerPalette.birdBody) >= 40 || lumaGap >= 0.3,
                    "\(world) の丘 \(String(hill, radix: 16)) と鳥 \(String(RunnerPalette.birdBody, radix: 16))"
                )
            }
        }
    }

    private func hue(_ hex: UInt32) -> Double {
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

    private func hueDistance(_ a: UInt32, _ b: UInt32) -> Double {
        let d = abs(hue(a) - hue(b))
        return min(d, 360 - d)
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

/// ワールドマップ（#798）の純データ: 面の名前・「1-1」表記・世界との対応。
@Suite("チャリンコおじさん: ワールドマップの面の名前")
struct RunnerStageNameTests {

    @Test("18 面すべてに名前があり、重複せず、格子に収まる長さ")
    func everyStageHasAUniqueShortName() {
        let names = RunnerStage.all.compactMap { RunnerWorld.stageName(forStage: $0.number) }
        #expect(names.count == RunnerRules.stageCount, "名前の無い面がある")
        #expect(Set(names).count == names.count, "重複した名前がある: \(names)")
        for name in names {
            #expect(!name.isEmpty)
            #expect(
                name.count <= RunnerWorld.maxStageNameLength,
                "「\(name)」は \(RunnerWorld.maxStageNameLength) 文字を超える（iPhone SE の 3 列で 1 行に入らない）"
            )
        }
        // 各世界がちょうど 6 面ぶん持つ。
        for world in RunnerWorld.allCases {
            #expect(world.stageNames.count == RunnerWorld.stagesPerWorld, "\(world)")
        }
    }

    @Test("世界と面番号の対応: 1-1 は 1 面、2-1 は 7 面、3-6 は 18 面")
    func codesFollowWorldBoundaries() {
        #expect(RunnerWorld.morning.number == 1)
        #expect(RunnerWorld.evening.number == 2)
        #expect(RunnerWorld.night.number == 3)
        #expect(RunnerWorld.morning.stageRange == 1...6)
        #expect(RunnerWorld.evening.stageRange == 7...12)
        #expect(RunnerWorld.night.stageRange == 13...18)

        #expect(RunnerWorld.code(forStage: 1) == "1-1")
        #expect(RunnerWorld.code(forStage: 6) == "1-6")
        #expect(RunnerWorld.code(forStage: 7) == "2-1")
        #expect(RunnerWorld.code(forStage: 12) == "2-6")
        #expect(RunnerWorld.code(forStage: 13) == "3-1")
        #expect(RunnerWorld.code(forStage: 18) == "3-6")

        // 世界の範囲を順に並べると 1…18 を漏れなく 1 度ずつ覆う。
        let covered = RunnerWorld.allCases.flatMap { Array($0.stageRange) }
        #expect(covered == Array(1...RunnerRules.stageCount))
    }

    @Test("名前は世界の配列の順に引かれ、範囲外は nil")
    func namesFollowWorldOrder() {
        #expect(RunnerWorld.stageName(forStage: 1) == RunnerWorld.morning.stageNames[0])
        #expect(RunnerWorld.stageName(forStage: 1) == "商店街のあさ")
        #expect(RunnerWorld.stageName(forStage: 6) == RunnerWorld.morning.stageNames[5])
        #expect(RunnerWorld.stageName(forStage: 7) == RunnerWorld.evening.stageNames[0])
        #expect(RunnerWorld.stageName(forStage: 18) == RunnerWorld.night.stageNames[5])
        #expect(RunnerWorld.stageName(forStage: 0) == nil)
        #expect(RunnerWorld.stageName(forStage: 19) == nil)
        #expect(RunnerWorld.stageName(forStage: -1) == nil)
    }

    @Test("世界を塗り分ける色は 3 つとも違う")
    func mapColorsDiffer() {
        let colors = RunnerWorld.allCases.map(\.mapColor)
        #expect(Set(colors).count == RunnerWorld.allCases.count)
    }

    @Test("面のボタンの読み上げは「1-1 商店街のあさ、到達済み／未到達」")
    func stageMapLabel() {
        #expect(RunnerAccessibility.stageMapLabel(number: 1, reached: true) == "1-1 商店街のあさ、到達済み")
        #expect(RunnerAccessibility.stageMapLabel(number: 7, reached: false) == "2-1 土手のゆうひ、未到達")
        #expect(RunnerAccessibility.stageMapLabel(number: 18, reached: false) == "3-6 夜あけの大通り、未到達")
    }
}
