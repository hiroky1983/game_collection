import Core
import GameKitTestSupport
import Testing
@testable import GameRunner

/// 世界（`RunnerWorld`・#703）。ステージ番号で固定に切り替わる景色（#1009 で 5 つ）の境界と配色を固定する。
@Suite("チャリンコおじさん: 世界")
struct RunnerWorldTests {

    @Test("1〜6 面は朝、7〜12 面は夕方、13〜18 面は夜、19〜24 面は里山、25〜30 面は港町（境界を含む）")
    func stageRanges() {
        #expect(RunnerWorld.world(forStage: 1) == .morning)
        #expect(RunnerWorld.world(forStage: 6) == .morning)
        #expect(RunnerWorld.world(forStage: 7) == .evening)
        #expect(RunnerWorld.world(forStage: 12) == .evening)
        #expect(RunnerWorld.world(forStage: 13) == .night)
        #expect(RunnerWorld.world(forStage: 18) == .night)
        #expect(RunnerWorld.world(forStage: 19) == .satoyama)
        #expect(RunnerWorld.world(forStage: 24) == .satoyama)
        #expect(RunnerWorld.world(forStage: 25) == .harbor)
        #expect(RunnerWorld.world(forStage: 30) == .harbor)
    }

    @Test("範囲外は夜（ショーケースの 0 番・最後の世界より後ろの 31 面以降も落ちずに描く）")
    func outOfRangeIsNight() {
        #expect(RunnerWorld.world(forStage: 0) == .night)
        #expect(RunnerWorld.world(forStage: -1) == .night)
        #expect(RunnerWorld.world(forStage: 31) == .night)
        #expect(RunnerWorld.world(forStage: RunnerRules.stageCount + 1) == .night)
    }

    @Test("全 30 面がちょうど 6 面ずつ 5 つの世界に分かれる")
    func everyStageHasAWorld() {
        let counts = Dictionary(grouping: RunnerStage.all, by: { RunnerWorld.world(forStage: $0.number) })
            .mapValues(\.count)
        #expect(counts == [.morning: 6, .evening: 6, .night: 6, .satoyama: 6, .harbor: 6])
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

    /// 乗り手は空を背に描かれる。どの世界の空も、走者のドット絵（`OjisanPixel`・#701）で面積の
    /// 大きい服（`Y`）と車体（`R`）と同じ色にならないことを、色相の差で機械的に確かめる
    /// （同じ系統の濃淡は使わない）。ズボン（`B`・紺）は夜空と同系だが、ドット絵は全部品を
    /// 暗い輪郭（`K`）で締めているので、輪郭のなかった図形の頃とは違い空に溶けない。
    @Test("どの世界の空も乗り手の色（服・車体）と色相が離れている")
    func skiesAreFarFromRiderHues() {
        let shirt = OjisanPixel.palette["Y"]!, bike = OjisanPixel.palette["R"]!
        for world in RunnerWorld.allCases {
            for rider in [shirt, bike] {
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
            let bird = world.creatures.birdBody
            for hill in [world.palette.hillFar, world.palette.hillNear] {
                let lumaGap = abs(luma(hill) - luma(bird)) / 255
                #expect(
                    hueDistance(hill, bird) >= 40 || lumaGap >= 0.3,
                    "\(world) の丘 \(String(hill, radix: 16)) と鳥 \(String(bird, radix: 16))"
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
        let roads = RunnerWorld.allCases.map(\.road)
        #expect(Set(roads.map(\.asphalt)).count == RunnerWorld.allCases.count)
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

    /// 岩は地面（`road.asphalt` の上端）から生え、背後には丘 2 段が見える。本体の色が丘と
    /// 明度で並ぶと輪郭が立たない（#920「色味が明るいと岩がみえにくい」）。
    /// WCAG 2.1 の相対輝度でコントラスト比を出し、どの世界でも本体と丘 2 色が 3:1 以上あることを
    /// 固定する（`RunnerScene.addBoulder` が縁取りを足していても、面の色そのものが背景と離れて
    /// いなければ遠目には溶ける）。
    @Test("どの世界でも岩の本体は丘 2 色と 3:1 以上のコントラストがある")
    func rockBodyStandsOutFromHills() {
        for world in RunnerWorld.allCases {
            let palette = world.palette
            for hill in [palette.hillFar, palette.hillNear] {
                let ratio = WCAG.contrast(palette.rockBody, hill)
                #expect(
                    ratio >= 3.0,
                    "\(world) の岩 \(String(palette.rockBody, radix: 16)) と丘 \(String(hill, radix: 16)): \(ratio)"
                )
            }
        }
    }

    /// 岩の足元は路面（`road.asphalt`。`palette.groundTop` は道路化（会長 QA 2026-09-14）以降は
    /// 描かれていない）に接する。朝の路面は明るい灰で、本体を 3:1 まで暗くすると黒に近くなる
    /// （#920 の目安 0x6E7585 前後から大きく外れる）ので、**本体か縁取りのどちらか**が路面と
    /// 3:1 以上あれば輪郭が読めるとみなす。縁取りは `RunnerScene.addBoulder` が `rockDark` で
    /// 全世界共通に引く。
    @Test("どの世界でも岩の本体か縁取りが路面と 3:1 以上のコントラストがある")
    func rockEdgeStandsOutFromRoad() {
        for world in RunnerWorld.allCases {
            let palette = world.palette, asphalt = world.road.asphalt
            let body = WCAG.contrast(palette.rockBody, asphalt)
            let outline = WCAG.contrast(palette.rockDark, asphalt)
            #expect(
                max(body, outline) >= 3.0,
                "\(world) の岩 本体 \(body) / 縁取り \(outline) と路面 \(String(asphalt, radix: 16))"
            )
        }
    }

    /// 3 階調が同じ向きに並んでいないと、頂の面（`rockLight`）と陰の面・縁取り（`rockDark`）が
    /// 本体に溶けて立体に見えない。明るい岩（夕方）でも暗い岩（朝）でも順序は同じ。
    @Test("岩の 3 階調は 明 > 本体 > 陰 の順に並び、縁取りは本体から離れている")
    func rockShadesAreOrdered() {
        for world in RunnerWorld.allCases {
            let palette = world.palette
            let light = WCAG.relativeLuminance(palette.rockLight)
            let body = WCAG.relativeLuminance(palette.rockBody)
            let dark = WCAG.relativeLuminance(palette.rockDark)
            #expect(light > body && body > dark, "\(world) の岩の階調が並んでいない")
            #expect(WCAG.contrast(palette.rockBody, palette.rockDark) >= 2.0, "\(world) の縁取りが本体に溶ける")
        }
    }

    @Test("遠景の飾りは世界ごとに決まっている")
    func scenery() {
        #expect(RunnerWorld.morning.scenery == .townHouses)
        #expect(RunnerWorld.evening.scenery == .riverside)
        #expect(RunnerWorld.night.scenery == .cityLights)
        #expect(RunnerWorld.satoyama.scenery == .satoyama)
        #expect(RunnerWorld.harbor.scenery == .harbor)
    }

    // MARK: 背景は淡く沈め、手前は縁取る（#929）

    /// 背景（空・丘・路面・遠景の飾り）は互いに明度が並んでいてよい——むしろ並んでいるほうが
    /// 手前の物だけが浮く。「淡く沈める」を、背景のどれも空と 2:1 未満、で固定する
    /// （会長指示 2026-09-15「背景を全部淡い色にする」）。
    @Test("どの世界でも背景同士（空・丘・路面・遠景の飾り）は 2:1 未満で沈んでいる")
    func backdropsSinkTogether() {
        for world in RunnerWorld.allCases {
            let sky = world.palette.sky
            for (name, color) in world.groundBackdrops {
                let ratio = WCAG.contrast(color, sky)
                #expect(ratio < 2.0, "\(world) の \(name) \(String(color, radix: 16)) が空から浮いている: \(ratio)")
            }
            for (name, color) in world.skyBackdrops {
                let ratio = WCAG.contrast(color, sky)
                #expect(ratio < 2.0, "\(world) の \(name) \(String(color, radix: 16)) が空から浮いている: \(ratio)")
            }
        }
    }

    /// #929 の受け入れ条件そのもの: 犬・イノシシ・鳥の**主色だけで**、家の壁・屋根・路面・丘
    /// （夕方は川、夜はビル）の全部と 3:1 以上。縁取りに頼らない（縁取りは 1.5pt しかなく、
    /// 遠目には面の色で見分けている）。
    @Test("どの世界でも犬・イノシシ・鳥の主色は背景（壁・屋根・路面・丘・川・ビル）と 3:1 以上")
    func creatureBodiesStandOutFromBackdrops() {
        for world in RunnerWorld.allCases {
            let creatures = world.creatures
            let bodies = [("犬", creatures.dogBody), ("イノシシ", creatures.boarBody), ("鳥", creatures.birdBody)]
            for (animal, body) in bodies {
                for (name, backdrop) in world.groundBackdrops {
                    let ratio = WCAG.contrast(body, backdrop)
                    #expect(
                        ratio >= 3.0,
                        "\(world) の\(animal) \(String(body, radix: 16)) と \(name) \(String(backdrop, radix: 16)): \(ratio)"
                    )
                }
            }
        }
    }

    /// 鳥だけは丘の稜線の切れ目で空（夕方は夕焼けの帯も）を背にする。夕方の白鷺は橙の帯と
    /// 主色では 2:1 なので、ここは主色か縁取りのどちらかで 3:1 とする。
    @Test("どの世界でも鳥の主色か縁取りが空・夕焼けの帯と 3:1 以上")
    func birdStandsOutFromSky() {
        for world in RunnerWorld.allCases {
            for (name, backdrop) in world.skyBackdrops {
                let body = WCAG.contrast(world.creatures.birdBody, backdrop)
                let outline = WCAG.contrast(world.outline, backdrop)
                #expect(max(body, outline) >= 3.0, "\(world) の鳥 本体 \(body) / 縁取り \(outline) と \(name)")
            }
        }
    }

    /// 手前の物（岩・たこ焼き・台座の床板・旗・穴の柵・加速帯）は、主色か縁取りのどちらかが
    /// 背景の全部と 3:1 以上（会長指示 2026-09-15「手前は濃く縁取りで浮かせる」）。
    /// 主色で届くのは夜（背景が暗い）で、朝のパステルでは縁取りが担う。加速帯は路面の中に
    /// 描かれるので、路面とだけ比べる。
    @Test("どの世界でも手前の物は主色か縁取りが背景と 3:1 以上")
    func foregroundStandsOutFromBackdrops() {
        for world in RunnerWorld.allCases {
            let outline = world.outline
            let items: [(String, main: UInt32, outline: UInt32)] = [
                ("岩", world.palette.rockBody, world.palette.rockDark),
                // たこ焼きはドット絵（#956）。縁取りは世界によらず絵のパレットの `K`。
                ("たこ焼き", RunnerPixelArt.takoyakiDough, RunnerPixelArt.outline),
                ("台座の床板", RunnerPalette.platformDeck, outline),
                ("ゴールの旗", RunnerPalette.goal, outline),
                ("チェックポイントの旗", RunnerPalette.checkpoint, outline),
                ("穴の柵", RunnerPalette.pitEdge, RunnerPalette.pitEdgeDark),
            ]
            for item in items {
                for (name, backdrop) in world.groundBackdrops {
                    let main = WCAG.contrast(item.main, backdrop)
                    let edge = WCAG.contrast(item.outline, backdrop)
                    #expect(
                        max(main, edge) >= 3.0,
                        "\(world) の\(item.0) 主色 \(main) / 縁取り \(edge) と \(name) \(String(backdrop, radix: 16))"
                    )
                }
            }
            let asphalt = world.road.asphalt
            let floor = WCAG.contrast(RunnerPalette.boostFloorTop, asphalt)
            let edge = WCAG.contrast(RunnerPalette.boostFloorEdge, asphalt)
            #expect(max(floor, edge) >= 3.0, "\(world) の加速帯 帯 \(floor) / 縁 \(edge) と路面")
        }
    }

    /// 縁取りが主色より明るいと「輪郭」ではなく「光る縁」になる。暗い側の部品（耳・脚・たてがみ・
    /// 奥の翼）も体より暗くないと面の切れ目が読めない。
    @Test("動物の縁取り・暗い部品は主色より暗く、鳥の 3 階調は 胴 > 翼 > 奥の翼")
    func creatureShadesAreOrdered() {
        for world in RunnerWorld.allCases {
            let c = world.creatures
            let l = WCAG.relativeLuminance
            #expect(l(c.outline) < l(c.dogBody) && l(c.outline) < l(c.boarBody) && l(c.outline) < l(c.birdBody), "\(world)")
            #expect(l(c.dogDark) < l(c.dogBody), "\(world) の犬")
            #expect(l(c.boarDark) < l(c.boarBody), "\(world) のイノシシ")
            #expect(l(c.birdBody) > l(c.birdWing) && l(c.birdWing) > l(c.birdWingFar), "\(world) の鳥")
            #expect(l(c.dogBelly) > l(c.dogBody), "\(world) の犬の腹は差し色として明るい")
            #expect(l(c.birdBelly) > l(c.birdBody), "\(world) の鳥の腹は差し色として明るい")
        }
    }

    /// 夜の犬・鳥は世界を分ける前の値のまま（既に遊ばれている後半の見た目を変えない）。
    /// イノシシだけは夜の路面と 1.3:1 だったので明るくしてある（`creatureBodiesStandOutFromBackdrops`）。
    @Test("夜の犬・鳥の色は #929 の前と同じ")
    func nightCreaturesMatchLegacy() {
        let night = RunnerWorld.night.creatures
        #expect(night.dogBody == 0xD9944A)
        #expect(night.dogDark == 0x5A3418)
        #expect(night.birdBody == 0x4FAE71)
        #expect(night.birdWing == 0x2F7D4E)
        #expect(night.birdWingFar == 0x1F5C38)
    }

    // MARK: 家並み（#929）

    /// 「細長い家の形が下品」（会長 QA 2026-09-15）。幅 ≥ 高さ、低い屋根、画面の高さの 1/5 以下、
    /// タイルの中で重ならない、を純データで固定する。
    @Test("家並みは幅 ≥ 高さで、屋根は低く、画面の高さの 1/5 以下、タイルの中で重ならない")
    func townHousesAreWideAndLow() {
        let houses = RunnerWorld.townHouses
        #expect((2...3).contains(houses.count), "家は 2〜3 種: \(houses.count)")
        for house in houses {
            #expect(house.width >= house.height, "細長い家: \(house)")
            #expect(house.roofHeight <= house.width * 0.2, "屋根が急: \(house)")
            #expect(house.height <= RunnerField.Metrics.height / 5, "家が高い: \(house)")
            #expect(house.floors >= 1)
            #expect(house.dx >= 0 && house.dx + house.width <= RunnerWorld.sceneryTileWidth, "タイルからはみ出す: \(house)")
        }
        // 平屋と二階建ての両方があり、屋根の色が 2 種以上ある。
        #expect(Set(houses.map(\.floors)).count >= 2)
        #expect(Set(houses.map(\.roof)).count >= 2)
        // 左から順に並び、隣と重ならない（タイルの継ぎ目をまたいでも）。
        for (left, right) in zip(houses, houses.dropFirst()) {
            #expect(left.dx + left.width < right.dx, "家が重なる: \(left) と \(right)")
        }
        if let first = houses.first, let last = houses.last {
            #expect(last.dx + last.width < first.dx + RunnerWorld.sceneryTileWidth, "継ぎ目で家が重なる")
        }
    }

    /// 家は背景なので、壁も屋根も朝の丘・空と明度が並ぶ（沈む）。クリーム（旧 0xFFF1DC）は
    /// 手前の白い雲・車輪と被り、赤瓦（旧 0xC9624A）は浮いていた。
    @Test("家の壁と屋根は朝の丘・空と 2:1 未満で沈み、壁は白ではない")
    func townHousePaletteSinks() {
        typealias P = RunnerWorld.TownHouse.Palette
        let morning = RunnerWorld.morning.palette
        for color in [P.wall, P.roofTile, P.roofSlate, P.roofSage, P.window, P.door] {
            #expect(WCAG.contrast(color, morning.sky) < 2.0, "\(String(color, radix: 16)) が空から浮いている")
            #expect(WCAG.contrast(color, morning.hillNear) < 2.0, "\(String(color, radix: 16)) が丘から浮いている")
        }
        #expect(WCAG.relativeLuminance(P.wall) < 0.85, "壁が白に近すぎる（雲・車輪と被る）")
        #expect(WCAG.contrast(P.wall, RunnerPalette.cloud) > 1.1, "壁が雲と同じ色")
    }

    // MARK: 里山・港町の着せ替え（#1009）

    /// 会長決裁の表（#1009 本文「今ある障害の着せ替え」）そのもの。1〜18 面は元の絵のまま
    /// ——朝・夕方・夜が `originalDressing` であることが「描画経路を変えていない」の根拠の 1 つ
    /// （`RunnerScene` は `.construction` / `.boulder` / `.scaffold` / `.boostBand` のとき元の関数を通る）。
    @Test("着せ替えは決裁の表どおりで、1〜18 面の世界は元の絵のまま")
    func dressings() {
        typealias D = RunnerWorld.Dressing
        for world in [RunnerWorld.morning, .evening, .night] {
            #expect(world.dressing == RunnerWorld.originalDressing, "\(world)")
        }
        // 突き上げ（#1010）は 19 面以降にしか出ないので、1〜18 面の `shoot` は使われない
        // （QA 用ショーケースは `rebuildCourse` が朝の下町で走らせるので竹の子を入れてある）。
        #expect(RunnerWorld.originalDressing == D(
            pit: .construction, lowBlock: .boulder, tallBlock: .boulder, dog: .dog, boar: .boar,
            platform: .scaffold, boostFloor: .boostBand, shoot: .bambooShoot, sinkFloor: .paddy,
            crumblingPlatform: .suspensionBridge
        ))
        #expect(RunnerWorld.satoyama.dressing == D(
            pit: .irrigationDitch, lowBlock: .stump, tallBlock: .boulder, dog: .dog, boar: .boar,
            platform: .strawStack, boostFloor: .pavedFarmRoad, shoot: .bambooShoot, sinkFloor: .paddy,
            crumblingPlatform: .suspensionBridge
        ))
        #expect(RunnerWorld.harbor.dressing == D(
            pit: .quayGap, lowBlock: .ropeCoil, tallBlock: .drum, dog: .cat, boar: .forklift,
            platform: .crateStack, boostFloor: .conveyor, shoot: .seaSpray, sinkFloor: .tideland,
            crumblingPlatform: .woodenPier
        ))
        // 岩の枠の引き方。岩でない種類は nil（突き上げは自分の着せ替えを持つので岩の枠ではない）。
        #expect(RunnerWorld.harbor.dressing.block(for: .lowBlock) == .ropeCoil)
        #expect(RunnerWorld.harbor.dressing.block(for: .tallBlock) == .drum)
        #expect(RunnerWorld.satoyama.dressing.block(for: .tallBlock) == .boulder)
        for kind in [RunnerHazardKind.pit, .bird, .dog, .boar, .shoot] {
            #expect(RunnerWorld.harbor.dressing.block(for: kind) == nil, "\(kind)")
        }
    }

    /// 着せ替えた手前の物（切り株・ロープ・ドラム缶・わら積み・木箱・舗装・コンベア・防舷材）も
    /// #929 の規則どおり、主色か縁取りがその世界の背景の全部と 3:1 以上。ドット絵の縁取りは
    /// `RunnerPixelArt.outline`、図形の縁取りは世界の `outline`。
    @Test("里山・港町の着せ替えた手前の物は主色か縁取りが背景と 3:1 以上")
    func dressedForegroundStandsOutFromBackdrops() {
        typealias P = RunnerWorld.DressingPalette
        let art = RunnerPixelArt.palette
        let items: [(RunnerWorld, String, main: UInt32, outline: UInt32)] = [
            (.satoyama, "切り株", art["S"]!, RunnerPixelArt.outline),
            (.satoyama, "わら積み", P.strawBody, RunnerWorld.satoyama.outline),
            (.satoyama, "わら積みの上面", P.strawTop, RunnerWorld.satoyama.outline),
            (.satoyama, "用水路の壁", P.ditchWall, P.ditchWater),
            (.harbor, "ロープの束", art["H"]!, RunnerPixelArt.outline),
            (.harbor, "ドラム缶", art["N"]!, RunnerPixelArt.outline),
            (.harbor, "木箱", P.crateWood, RunnerWorld.harbor.outline),
            (.harbor, "木箱の上面", P.crateTop, RunnerWorld.harbor.outline),
            (.harbor, "防舷材", P.fender, RunnerPalette.pitEdge),
            // 突き上げ（#1010）。淡い皮（`T`）・淡い泡（`C`）はどちらも背景と 1.0〜1.4:1 しか無いので、
            // **3:1 を担っているのは縁取りと、面の中の濃い側**（竹の子は樹皮の `S`、波しぶきは
            // 水の陰の `N`）。主色にその濃い側を置いて、縁取りだけで通る空振りにしない
            // （2026-09-18 の敵対的検証で、`C` を港町の背景色そのものにしても緑だったのを実測）。
            (.satoyama, "竹の子", art["S"]!, RunnerPixelArt.outline),
            (.satoyama, "土の盛り上がり", art["S"]!, RunnerPixelArt.outline),
            (.harbor, "波しぶき", art["N"]!, RunnerPixelArt.outline),
            (.harbor, "泡", art["C"]!, RunnerPixelArt.outline),
        ]
        for item in items {
            for (name, backdrop) in item.0.groundBackdrops {
                let main = WCAG.contrast(item.main, backdrop)
                let edge = WCAG.contrast(item.outline, backdrop)
                #expect(
                    max(main, edge) >= 3.0,
                    "\(item.0) の\(item.1) 主色 \(main) / 縁取り \(edge) と \(name) \(String(backdrop, radix: 16))"
                )
            }
        }
        // 崩れる足場（#1090）は**縁取りのノードを持たない**（板 1 枚ずつに `SKShapeNode` を足すと
        // 1 基で 20 個増える）。したがって上の `items` の形（主色か縁取りのどちらかが通ればよい）に
        // 混ぜてはいけない——混ぜると縁取りの色だけで通ってしまい、板を背景と同じ色にしても緑になる
        // （2026-09-18 の敵対的検証で実測）。**主色だけで 3:1 を要求する**。
        //
        // 3:1 を担うのは板の木目（`crumbleDeckSeam`。板 1 枚ごとに下端へ入るので、抜け落ちていく
        // 途中でも残った板の輪郭が読める）と、崩れても残る柱・杭（`crumblePost`）。板の面
        // （`crumbleDeck`）は乗る面なのでいちばん明るく、淡い背景とは 1.0〜1.5:1 しか無い
        // ——竹の子・波しぶきとまったく同じ「濃い側が担う」形。
        for world in [RunnerWorld.satoyama, RunnerWorld.harbor] {
            for (part, color) in [("板の木目", P.crumbleDeckSeam), ("柱・杭", P.crumblePost)] {
                for (name, backdrop) in world.groundBackdrops {
                    #expect(
                        WCAG.contrast(color, backdrop) >= 3.0,
                        "\(world) の崩れる足場の\(part)が \(name) (\(String(backdrop, radix: 16))) に溶ける"
                    )
                }
            }
        }
        // 縄は板の**上**（空・丘を背に）に張るので、模様ではなく手前の物として背景と比べる。
        for (name, backdrop) in RunnerWorld.satoyama.groundBackdrops {
            #expect(
                WCAG.contrast(P.crumbleRope, backdrop) >= 3.0,
                "吊り橋の縄が \(name) (\(String(backdrop, radix: 16))) に溶ける"
            )
        }
        // ひびは板の面の上に描く模様なので、板とだけ比べる（矢印を床と比べるのと同じ扱い）。
        #expect(WCAG.contrast(P.crumbleCrack, P.crumbleDeck) >= 3.0, "崩れる予告のひびが板に溶ける")

        // 加速床は路面の中に描かれるので路面とだけ比べる（`foregroundStandsOutFromBackdrops` と同じ）。
        #expect(WCAG.contrast(P.pavedAsphalt, RunnerWorld.satoyama.road.asphalt) >= 3.0, "舗装が砂利道に溶ける")
        #expect(WCAG.contrast(P.pavedArrow, P.pavedAsphalt) >= 3.0, "舗装の矢印が読めない")
        #expect(WCAG.contrast(P.conveyorBelt, RunnerWorld.harbor.road.asphalt) >= 3.0, "ベルトが岸壁に溶ける")
        #expect(WCAG.contrast(P.conveyorArrow, P.conveyorBelt) >= 3.0, "ベルトの矢印が読めない")
        // ドラム缶・切り株の主色は縁取り無しでも路面・丘と 3:1 以上（岩塊の本体と同じ物差し）。
        for hill in [RunnerWorld.harbor.palette.hillFar, RunnerWorld.harbor.palette.hillNear, RunnerWorld.harbor.road.asphalt] {
            #expect(WCAG.contrast(art["N"]!, hill) >= 3.0, "ドラム缶が \(String(hill, radix: 16)) に溶ける")
        }
        for hill in [RunnerWorld.satoyama.palette.hillFar, RunnerWorld.satoyama.palette.hillNear, RunnerWorld.satoyama.road.asphalt] {
            #expect(WCAG.contrast(art["S"]!, hill) >= 3.0, "切り株が \(String(hill, radix: 16)) に溶ける")
        }
    }

    /// 穴に水を張っても「穴」だと分かること: 深い水は路面と 3:1 以上、水面の帯は深い水より明るく、
    /// 用水路の壁は路面より明るい（切れ目の縁が立つ）。
    @Test("用水路・岸壁の切れ目の水は路面と 3:1 以上で、水面は深い水より明るい")
    func waterPitsReadAsHoles() {
        typealias P = RunnerWorld.DressingPalette
        #expect(WCAG.contrast(P.ditchWater, RunnerWorld.satoyama.road.asphalt) >= 3.0)
        #expect(WCAG.contrast(P.gapSea, RunnerWorld.harbor.road.asphalt) >= 3.0)
        #expect(WCAG.relativeLuminance(P.ditchSurface) > WCAG.relativeLuminance(P.ditchWater))
        #expect(WCAG.relativeLuminance(P.gapSurface) > WCAG.relativeLuminance(P.gapSea))
        #expect(WCAG.relativeLuminance(P.ditchWall) > WCAG.relativeLuminance(RunnerWorld.satoyama.road.asphalt))
        // 奈落（1〜18 面）の色は変えていない。
        #expect(RunnerPalette.pitVoid == 0x141824)
    }

    /// 沈む床（#1089）が**踏み込む前に読める**こと。床は当たり判定を持たないので、
    /// 「ここから沈む」は色と模様だけで伝える必要がある:
    ///
    /// - 水面（泥）はその世界の路面と 3:1 以上（普通の地面ではないと分かる）
    /// - 模様（苗・カニの穴）と照りは水面（泥）と 3:1 以上（模様として読める）
    @Test("田んぼ・干潟は路面と 3:1 以上で、苗・カニの穴・照りは水面と 3:1 以上")
    func sinkFloorsReadAsWater() {
        typealias P = RunnerWorld.DressingPalette
        #expect(WCAG.contrast(P.paddyWater, RunnerWorld.satoyama.road.asphalt) >= 3.0, "田んぼが農道に溶ける")
        #expect(WCAG.contrast(P.tidelandMud, RunnerWorld.harbor.road.asphalt) >= 3.0, "干潟が岸壁に溶ける")
        #expect(WCAG.contrast(P.paddySeedling, P.paddyWater) >= 3.0, "苗が水面に溶ける")
        #expect(WCAG.contrast(P.waterGlint, P.paddyWater) >= 3.0, "水面の照りが読めない")
        #expect(WCAG.contrast(P.tidelandHole, P.tidelandMud) >= 3.0, "カニの穴が泥に溶ける")
        #expect(WCAG.contrast(P.tidelandSheen, P.tidelandMud) >= 3.0, "潮の照りが読めない")
        // 底は水面（泥）より暗い——段差で「深さ」が出る（用水路・岸壁の切れ目と同じ約束の裏返し）。
        #expect(WCAG.relativeLuminance(P.paddyDeep) < WCAG.relativeLuminance(P.paddyWater))
        #expect(WCAG.relativeLuminance(P.tidelandDeep) < WCAG.relativeLuminance(P.tidelandMud))
    }

    /// 鳥の頭とくちばしの色は #1009 で `Creatures` に入れた。朝・夕方・夜は**それまでと同じ値**
    /// （頭は胴と同じ、くちばしは `RunnerPalette.birdBeak`）で、1〜18 面の鳥の見た目は変わらない。
    /// 里山のカラスだけくちばしが炭色、港町のカモメだけ頭が白。
    @Test("鳥の頭・くちばしの色は 1〜18 面では従来どおりで、カラスは炭のくちばし・カモメは白い頭")
    func birdHeadAndBeakFollowTheWorld() {
        for world in [RunnerWorld.morning, .evening, .night] {
            #expect(world.creatures.birdHead == world.creatures.birdBody, "\(world)")
            #expect(world.creatures.birdBeak == RunnerPalette.birdBeak, "\(world)")
        }
        #expect(RunnerPalette.birdBeak == 0xFFB648)
        let crow = RunnerWorld.satoyama.creatures, gull = RunnerWorld.harbor.creatures
        #expect(crow.birdHead == crow.birdBody)
        #expect(WCAG.relativeLuminance(crow.birdBeak) < 0.1, "カラスのくちばしが橙のまま")
        #expect(WCAG.relativeLuminance(crow.birdBeak) > WCAG.relativeLuminance(crow.outline), "くちばしが縁取りに溶ける")
        #expect(WCAG.relativeLuminance(gull.birdHead) > 0.8, "カモメの頭が白くない")
        #expect(gull.birdBeak == RunnerPalette.birdBeak)
        // 白目は腹の色。カラスの腹は胴より明るい灰で、黒目（`RunnerPalette.birdEye`）が読める。
        #expect(WCAG.contrast(crow.birdBelly, RunnerPalette.birdEye) >= 3.0, "カラスの目が読めない")
    }

    @Test("読み上げにはステージ番号に世界の名前が添えられる")
    func accessibilityLabelIncludesWorld() {
        #expect(RunnerAccessibility.stageLabelWithWorld(number: 3, total: 18) == "ステージ 3 / 18、朝の下町")
        #expect(RunnerAccessibility.stageLabelWithWorld(number: 7, total: 18) == "ステージ 7 / 18、夕方の川沿い")
        #expect(RunnerAccessibility.stageLabelWithWorld(number: 18, total: 30) == "ステージ 18 / 30、夜の繁華街")
        #expect(RunnerAccessibility.stageLabelWithWorld(number: 19, total: 30) == "ステージ 19 / 30、里山")
        #expect(RunnerAccessibility.stageLabelWithWorld(number: 30, total: 30) == "ステージ 30 / 30、港町")
        // 見た目の文言（番号だけ）は変えない。
        #expect(RunnerAccessibility.stageLabel(number: 3, total: 18) == "ステージ 3 / 18")
    }
}

/// ワールドマップ（#798）の純データ: 「1-1」表記と世界との対応。面の名前（「商店街のあさ」等）は
/// #946 で外し、画面・読み上げとも番号だけにした。
@Suite("チャリンコおじさん: ワールドマップの面の表記")
struct RunnerStageCodeTests {

    @Test("全面の表記は重複せず、どれかの世界に収まる番号だけが有効")
    func everyStageHasAUniqueCode() {
        let codes = RunnerStage.all.map { RunnerWorld.code(forStage: $0.number) }
        #expect(codes.count == RunnerRules.stageCount)
        #expect(Set(codes).count == codes.count, "重複した表記がある: \(codes)")
        for stage in RunnerStage.all {
            #expect(RunnerWorld.contains(stage: stage.number), "\(stage.number)")
        }
        #expect(!RunnerWorld.contains(stage: 0))
        #expect(!RunnerWorld.contains(stage: RunnerRules.stageCount + 1))
        #expect(!RunnerWorld.contains(stage: -1))
    }

    @Test("世界と面番号の対応: 1-1 は 1 面、2-1 は 7 面、3-6 は 18 面、4-1 は 19 面、5-6 は 30 面")
    func codesFollowWorldBoundaries() {
        #expect(RunnerWorld.morning.number == 1)
        #expect(RunnerWorld.evening.number == 2)
        #expect(RunnerWorld.night.number == 3)
        #expect(RunnerWorld.satoyama.number == 4)
        #expect(RunnerWorld.harbor.number == 5)
        #expect(RunnerWorld.morning.stageRange == 1...6)
        #expect(RunnerWorld.evening.stageRange == 7...12)
        #expect(RunnerWorld.night.stageRange == 13...18)
        #expect(RunnerWorld.satoyama.stageRange == 19...24)
        #expect(RunnerWorld.harbor.stageRange == 25...30)

        #expect(RunnerWorld.code(forStage: 1) == "1-1")
        #expect(RunnerWorld.code(forStage: 6) == "1-6")
        #expect(RunnerWorld.code(forStage: 7) == "2-1")
        #expect(RunnerWorld.code(forStage: 12) == "2-6")
        #expect(RunnerWorld.code(forStage: 13) == "3-1")
        #expect(RunnerWorld.code(forStage: 18) == "3-6")
        #expect(RunnerWorld.code(forStage: 19) == "4-1")
        #expect(RunnerWorld.code(forStage: 24) == "4-6")
        #expect(RunnerWorld.code(forStage: 25) == "5-1")
        #expect(RunnerWorld.code(forStage: 30) == "5-6")

        // 世界の範囲を順に並べると 1…30 を漏れなく 1 度ずつ覆う。
        let covered = RunnerWorld.allCases.flatMap { Array($0.stageRange) }
        #expect(covered == Array(1...RunnerRules.stageCount))
    }

    @Test("世界を塗り分ける色は全部違う")
    func mapColorsDiffer() {
        let colors = RunnerWorld.allCases.map(\.mapColor)
        #expect(Set(colors).count == RunnerWorld.allCases.count)
    }

    /// 「違う値」だけでは足りない——里山・港町の空は朝と同じ淡い帯で、空のままだと 3 つが同じ色に
    /// 見えた（#1009）。どの 2 世界も色相が 20° 以上か明度（コントラスト比）が 1.5:1 以上離れていること。
    /// あわせて、開始シートの主ボタンの文字（`RunnerView.onWorld` = 0x1A1410）がどの世界の色の上でも 4.5:1 以上。
    @Test("世界を塗り分ける色は色相か明度で見分けられ、濃い茶の文字が載る")
    func mapColorsAreDistinguishable() {
        let worlds = RunnerWorld.allCases
        for (i, a) in worlds.enumerated() {
            for b in worlds.dropFirst(i + 1) {
                let hueGap = hueDistance(a.mapColor, b.mapColor)
                let ratio = WCAG.contrast(a.mapColor, b.mapColor)
                // **色相差を根拠にしてよいのは、両方に彩度があるときだけ**（#1100 の敵対的検証）。
                // 里山を空の色（0xD6ECE4・彩度 9%）に戻しても、朝（0xCFE6F5）との色相差が 45° 付いて
                // このテストが緑のままだった——淡すぎる色の色相は目では読めないのに、式の上では離れる。
                // 彩度は HSV の S（最大値に対する幅）で見る。朝の空 0xCFE6F5 で 16%、夜のマップ色で 45%。
                let hueCounts = min(saturation(a.mapColor), saturation(b.mapColor)) >= 0.12
                #expect((hueGap >= 20 && hueCounts) || ratio >= 1.5,
                        "\(a) と \(b): 色相差 \(hueGap)° / 明度比 \(ratio) / 彩度 \(saturation(a.mapColor))・\(saturation(b.mapColor))")
            }
            #expect(WCAG.contrast(a.mapColor, 0x1A1410) >= 4.5, "\(a) の色の上で文字が読めない")
        }
    }

    /// HSV の S（0…1）。0 に近いほど灰色に寄り、色相が目では読めなくなる。
    private func saturation(_ hex: UInt32) -> Double {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        let maxC = max(r, g, b), minC = min(r, g, b)
        guard maxC > 0 else { return 0 }
        return (maxC - minC) / maxC
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

    @Test("面のボタンの読み上げは「1-1、到達済み／未到達」（名前は付けない・#946）")
    func stageMapLabel() {
        #expect(RunnerAccessibility.stageMapLabel(number: 1, reached: true) == "1-1、到達済み")
        #expect(RunnerAccessibility.stageMapLabel(number: 7, reached: false) == "2-1、未到達")
        #expect(RunnerAccessibility.stageMapLabel(number: 18, reached: false) == "3-6、未到達")
        #expect(RunnerAccessibility.stageMapLabel(number: 30, reached: false) == "5-6、未到達")
    }
}
