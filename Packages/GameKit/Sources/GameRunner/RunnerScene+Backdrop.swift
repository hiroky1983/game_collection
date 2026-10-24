import Core
import Foundation
import SpriteKit

extension RunnerScene {
    /// 世界が変わったときに、空の色と雲・遠景・丘を作り直す（#703）。
    ///
    /// 呼ぶのは `rebuildCourse` だけ。ステージごとには呼ばれない（同じ世界のあいだは
    /// 雲も丘も同じものが流れ続ける——従来の「ステージをまたいでも作り直さない」を保つ）。
    func applyWorld(_ next: RunnerWorld) {
        world = next
        renderedWorld = next
        backgroundColor = RunnerPalette.color(next.palette.sky)
        cloudLayer.removeAllChildren()
        clouds.removeAll()
        cloudBaseX.removeAll()
        backdropLayer.removeAllChildren()
        hillLayer.removeAllChildren()
        hillTiles.removeAll()
        hillBaseX.removeAll()
        buildClouds()
        buildBackdrop()
        buildHills()
    }

    /// 空を流れる雲。ステージをまたいでも作り直さない（`rebuildCourse` の対象外。
    /// 世界が変わるときだけ `applyWorld` が作り直す）。
    private func buildClouds() {
        let count = 8
        for i in 0..<count {
            let cloud = SKNode()
            let puffs: [(dx: Double, dy: Double, r: Double)] = [
                (0, 0, 3.4), (-3.2, -0.6, 2.4), (3.0, -0.4, 2.6), (0.6, 1.2, 2.2),
            ]
            for puff in puffs {
                let shape = SKShapeNode(circleOfRadius: puff.r)
                shape.fillColor = RunnerPalette.color(world.palette.cloud)
                shape.alpha = world.palette.cloudAlpha
                shape.strokeColor = .clear
                shape.position = CGPoint(x: puff.dx, y: puff.dy)
                cloud.addChild(shape)
            }
            // 高さを雲ごとに変えて、横一列に並んで見えないようにする。丘の稜線
            // （`buildHills`、最も高いもので地面+34=68）より確実に上、画面の上端付近に収める
            // ——`Metrics.height` を95に下げた際（#621）、旧来の帯（-52〜-12）のままだと
            // 丘の稜線に一部埋もれるため、丘より上の帯だけに詰めた。`Metrics.height` からの
            // 相対値で置いてあるので、115へ広げた（#636）あとも丘より上に収まる。
            let y = Metrics.height - 4 - Double(i % 4) * 6
            cloud.position = CGPoint(x: Double(i) * Self.cloudSpacing, y: y)
            cloudLayer.addChild(cloud)
            clouds.append(cloud)
            cloudBaseX.append(Double(i) * Self.cloudSpacing)
        }
    }

    /// 地平線側の丘の稜線。地面（`RunnerField.Metrics.groundY`）から上端
    /// （`RunnerField.Metrics.height`）までの帯が広く空くぶん、
    /// 何も無い空の帯にせず奥・手前 2 段の丘で埋める（2026-09-10 会長QA「縦を活かす」対応）。
    /// ステージをまたいでも作り直さない（`rebuildCourse` の対象外）——雲と同じ理由。
    /// 世界ごとの遠景の飾り（川・ビル）も同じタイルに載せて一緒に流す（#703）。
    private func buildHills() {
        let count = 6
        let palette = world.palette
        for i in 0..<count {
            let tile = SKNode()
            // 奥の丘（背が高く、色が薄い＝遠い）。
            addHillBump(to: tile, color: palette.hillFar, width: 42, height: 34, dx: 8)
            addHillBump(to: tile, color: palette.hillFar, width: 36, height: 27, dx: 42)
            // 手前の丘（背が低く、色が濃い＝近い）。奥の丘に重ねて奥行きを出す。
            addHillBump(to: tile, color: palette.hillNear, width: 34, height: 19, dx: 22)
            switch world.scenery {
            case .townHouses: addTownHouses(to: tile)
            case .riverside:  addRiver(to: tile)
            case .cityLights: addCityLights(to: tile)
            // 里山・港町（#1009）はタイルの番号で中身を変える（竹林・貨物船を毎タイルに置くと林と船団になる）。
            case .satoyama:   addSatoyama(to: tile, index: i)
            case .harbor:     addHarbor(to: tile, index: i)
            case .kyotoNara:  addKyotoNara(to: tile, index: i)
            case .onsen:      addOnsen(to: tile, index: i)
            case .snow:       addSnow(to: tile, index: i)
            case .tokyo:      addTokyo(to: tile, index: i)
            }
            tile.position = CGPoint(x: Double(i) * Self.hillSpacing, y: 0)
            hillLayer.addChild(tile)
            hillTiles.append(tile)
            hillBaseX.append(Double(i) * Self.hillSpacing)
        }
    }

    /// 動かない遠景。夕方だけ、地平線に橙の帯を敷いて「橙〜桃色の空」にする。
    /// 丘の後ろ（`backdropLayer`）に置くので、丘の切れ目からだけ覗く。
    private func buildBackdrop() {
        // 東京（#2729）も地平線に帯を敷く（茜の名残。夕方の帯と同じ組み立てで色だけが違う）。
        let glowColor: UInt32
        switch world.scenery {
        case .riverside: glowColor = RunnerWorld.SceneryPalette.sunsetGlow
        case .tokyo:     glowColor = RunnerWorld.SceneryPalette.duskGlow
        default:         return
        }
        let glow = SKSpriteNode(
            color: RunnerPalette.color(glowColor),
            size: CGSize(width: Metrics.width, height: 30)
        )
        glow.anchorPoint = .zero
        glow.position = CGPoint(x: 0, y: Metrics.groundY)
        backdropLayer.addChild(glow)
        // 帯の上端をぼかす代わりに、半透明の 1 枚を重ねて 2 段にする（テクスチャを使わない）。
        let haze = SKSpriteNode(
            color: RunnerPalette.color(glowColor),
            size: CGSize(width: Metrics.width, height: 14)
        )
        haze.anchorPoint = .zero
        haze.alpha = 0.45
        haze.position = CGPoint(x: 0, y: Metrics.groundY + 30)
        backdropLayer.addChild(haze)
    }

    /// 夕方の川（`RunnerWorld.Scenery.riverside`）。丘の手前・地面のすぐ上に横長の帯を敷く。
    /// 丘と同じタイルに載せるので、丘と同じ視差で流れる（川は道のすぐ向こうにある）。
    /// 走者の下半身はこの帯を背に描かれる——`RunnerWorld.SceneryPalette.riverWater` の注記を参照。
    private func addRiver(to tile: SKNode) {
        let height = 7.0
        let water = SKSpriteNode(
            color: RunnerPalette.color(RunnerWorld.SceneryPalette.riverWater),
            size: CGSize(width: Self.hillSpacing, height: height)
        )
        water.anchorPoint = .zero
        water.position = CGPoint(x: 0, y: Metrics.groundY)
        tile.addChild(water)
        // 照り返し。長さ・位置をずらした細い帯を 3 本置き、タイルの継ぎ目で揃わないようにする。
        for (dx, width, dy) in [(6.0, 14.0, 2.2), (28.0, 9.0, 4.6), (44.0, 11.0, 1.4)] {
            let glint = SKSpriteNode(
                color: RunnerPalette.color(RunnerWorld.SceneryPalette.riverGlint),
                size: CGSize(width: width, height: 0.6)
            )
            glint.anchorPoint = .zero
            glint.alpha = 0.8
            glint.position = CGPoint(x: dx, y: Metrics.groundY + dy)
            tile.addChild(glint)
        }
    }

    /// 朝の下町の家並み（`RunnerWorld.Scenery.townHouses`）。近景の丘の手前・道路の奥の帯に
    /// 1 段で 3 軒（寸法と色は `RunnerWorld.townHouses` / `TownHouse.Palette` の純データ・#929）。
    /// 壁は矩形、屋根は低い寄棟（台形のパス）、窓と戸は小さな矩形（#494 の意匠制約の内側）。
    /// 丘のループに載せる。以前の「幅より高い壁に急な三角屋根」は細長い建物に見えて
    /// 下品（会長 QA 2026-09-15）だったので、横に広い家に低い屋根を載せる形へ変えた。
    ///
    /// 家の部品はすべて丘の山（z 0）より前の z に置く（`HouseZ`）。屋根だけ z 1 で壁が 0 だと、
    /// 隣のタイルの山（追加順が後）が壁を隠して屋根だけ浮いて見える（会長 QA 2026-09-15、#942）。
    private func addTownHouses(to tile: SKNode) {
        typealias HousePalette = RunnerWorld.TownHouse.Palette
        for house in RunnerWorld.townHouses {
            let base = CGPoint(x: house.dx, y: Metrics.groundY)
            let wall = SKSpriteNode(
                color: RunnerPalette.color(HousePalette.wall),
                size: CGSize(width: house.width, height: house.wallHeight)
            )
            wall.anchorPoint = .zero
            wall.position = base
            wall.zPosition = HouseZ.wall
            tile.addChild(wall)

            // 屋根。軒を壁より 0.8 ずつ張り出し、棟は幅の中央 44% を平らにした寄棟。
            let eave = 0.8
            let roof = CGMutablePath()
            roof.move(to: CGPoint(x: -eave, y: 0))
            roof.addLine(to: CGPoint(x: house.width * 0.28, y: house.roofHeight))
            roof.addLine(to: CGPoint(x: house.width * 0.72, y: house.roofHeight))
            roof.addLine(to: CGPoint(x: house.width + eave, y: 0))
            roof.closeSubpath()
            let roofNode = SKShapeNode(path: roof)
            roofNode.fillColor = RunnerPalette.color(house.roof)
            roofNode.strokeColor = .clear
            roofNode.position = CGPoint(x: base.x, y: base.y + house.wallHeight)
            roofNode.zPosition = HouseZ.roof
            tile.addChild(roofNode)

            // 玄関の戸（1 階の左寄り）と窓（各階 2〜3 枚）。
            let floorHeight = house.wallHeight / Double(house.floors)
            let door = SKSpriteNode(
                color: RunnerPalette.color(HousePalette.door),
                size: CGSize(width: 2.0, height: min(3.2, floorHeight * 0.65))
            )
            door.anchorPoint = .zero
            door.position = CGPoint(x: base.x + house.width * 0.12, y: base.y)
            door.zPosition = HouseZ.fixtures
            tile.addChild(door)
            for floor in 0..<house.floors {
                // 1 階は戸の右に 2 枚、2 階以上は戸の上にも 1 枚。
                let columns = floor == 0 ? [0.45, 0.72] : [0.15, 0.45, 0.72]
                for column in columns {
                    let window = SKSpriteNode(
                        color: RunnerPalette.color(HousePalette.window),
                        size: CGSize(width: 2.0, height: 1.6)
                    )
                    window.anchorPoint = .zero
                    window.position = CGPoint(
                        x: base.x + house.width * column,
                        y: base.y + floorHeight * Double(floor) + floorHeight * 0.42
                    )
                    window.zPosition = HouseZ.fixtures
                    tile.addChild(window)
                }
            }
        }
    }

    /// 夜のビル（`RunnerWorld.Scenery.cityLights`）。近景の丘の手前に影を 3 棟と窓の灯りを置く。
    /// 矩形だけの単純な影（#494 の意匠制約の内側）。1 タイルあたり 3 棟＋窓 12 枚で、
    /// 丘のループに載せるので画面に出るノードは常にこの 6 倍まで。
    private func addCityLights(to tile: SKNode) {
        let buildings: [(dx: Double, width: Double, height: Double)] = [
            (3, 9, 12), (30, 7, 15), (47, 10, 10),
        ]
        for building in buildings {
            let body = SKSpriteNode(
                color: RunnerPalette.color(RunnerWorld.SceneryPalette.building),
                size: CGSize(width: building.width, height: building.height)
            )
            body.anchorPoint = .zero
            body.position = CGPoint(x: building.dx, y: Metrics.groundY)
            tile.addChild(body)
            // 窓は 2 列 × 2 段。すべて点けるとのっぺりするので、決まった 1 枚だけ消しておく
            // （乱数は使わない。撮影・QAで毎回同じ画になるように）。
            for row in 0..<2 {
                for column in 0..<2 where !(row == 1 && column == 1 && building.width < 8) {
                    let window = SKSpriteNode(
                        color: RunnerPalette.color(RunnerWorld.SceneryPalette.buildingWindow),
                        size: CGSize(width: 1.3, height: 1.6)
                    )
                    window.anchorPoint = .zero
                    window.position = CGPoint(
                        x: building.dx + 1.6 + Double(column) * (building.width - 4.5),
                        y: Metrics.groundY + 2.4 + Double(row) * 4.2
                    )
                    tile.addChild(window)
                }
            }
        }
    }

    /// 里山（`RunnerWorld.Scenery.satoyama`・#1009）。道路の奥にあぜ道と田んぼの帯（水面に苗の列）、
    /// 偶数番のタイルだけ近景の丘の手前に竹林を立てる（全タイルに置くと林が続きすぎて
    /// 「里」に見えない）。苗・竹の幹・節と葉はそれぞれ 1 本のパスにまとめ、1 タイルあたり
    /// 最大 6 ノード。色は `RunnerWorld.SceneryPalette`（どれも空と 2:1 未満で沈む・`WorldTests`）。
    private func addSatoyama(to tile: SKNode, index: Int) {
        typealias P = RunnerWorld.SceneryPalette
        let width = Self.hillSpacing
        let base = Metrics.groundY

        // 竹林。偶数タイルに 5 本。幹は細長い矩形、節は幹より濃い細い帯、葉は先端の三角 3 枚。
        if index.isMultiple(of: 2) {
            let stalks = CGMutablePath(), nodes = CGMutablePath(), leaves = CGMutablePath()
            for (i, stalk) in [(30.0, 17.0), (34.5, 20.0), (39.0, 15.5), (43.5, 19.0), (48.0, 16.5)].enumerated() {
                let (dx, height) = stalk
                let stalkWidth = 1.0
                stalks.addRect(CGRect(x: dx, y: base + 2, width: stalkWidth, height: height))
                var y = base + 5.5 + Double(i % 2) * 1.5
                while y < base + height - 1 {
                    nodes.addRect(CGRect(x: dx - 0.15, y: y, width: stalkWidth + 0.3, height: 0.45))
                    y += 4.0
                }
                let tipX = dx + stalkWidth / 2, tipY = base + 2 + height
                for (ox, oy) in [(-3.2, -1.2), (2.8, -0.6), (-0.6, 1.4)] {
                    leaves.move(to: CGPoint(x: tipX, y: tipY - 1.5))
                    leaves.addLine(to: CGPoint(x: tipX + ox, y: tipY + oy))
                    leaves.addLine(to: CGPoint(x: tipX + ox * 0.55, y: tipY + oy * 0.55 + 0.9))
                    leaves.closeSubpath()
                }
            }
            for (path, color) in [(stalks, P.bambooStalk), (nodes, P.bambooLeaf), (leaves, P.bambooLeaf)] {
                let shape = SKShapeNode(path: path)
                shape.fillColor = RunnerPalette.color(color)
                shape.strokeColor = .clear
                shape.zPosition = SceneryZ.back
                tile.addChild(shape)
            }
        }

        // 田んぼ。水面の帯にまっすぐな苗の列を 2 段。あぜ道の帯を手前（下）に敷く。
        let water = SKSpriteNode(color: RunnerPalette.color(P.paddyWater), size: CGSize(width: width, height: 5.0))
        water.anchorPoint = .zero
        water.position = CGPoint(x: 0, y: base + 1.2)
        water.zPosition = SceneryZ.middle
        tile.addChild(water)
        let seedlings = CGMutablePath()
        for (row, dy) in [2.0, 4.1].enumerated() {
            var x = 0.8 + Double(row) * 1.2
            while x < width - 0.5 {
                seedlings.addRect(CGRect(x: x, y: base + dy, width: 0.5, height: 1.1))
                x += 2.4
            }
        }
        let seedlingNode = SKShapeNode(path: seedlings)
        seedlingNode.fillColor = RunnerPalette.color(P.paddySeedling)
        seedlingNode.strokeColor = .clear
        seedlingNode.zPosition = SceneryZ.front
        tile.addChild(seedlingNode)
        let path = SKSpriteNode(color: RunnerPalette.color(P.fieldPath), size: CGSize(width: width, height: 1.2))
        path.anchorPoint = .zero
        path.position = CGPoint(x: 0, y: base)
        path.zPosition = SceneryZ.front
        tile.addChild(path)
    }

    /// 港町（`RunnerWorld.Scenery.harbor`・#1009）。道路の奥に海の帯、奇数番のタイルに桟橋、
    /// 偶数番のタイルに岸壁のコンテナの山、3 で割り切れるタイルに沖の貨物船。
    /// 波・杭・波板の筋はそれぞれ 1 本のパスにまとめ、1 タイルあたり最大 10 ノード。
    private func addHarbor(to tile: SKNode, index: Int) {
        typealias P = RunnerWorld.SceneryPalette
        let width = Self.hillSpacing
        let base = Metrics.groundY

        // 海。丘（岬）の手前・道路の奥。
        let sea = SKSpriteNode(color: RunnerPalette.color(P.seaWater), size: CGSize(width: width, height: 7.0))
        sea.anchorPoint = .zero
        sea.position = CGPoint(x: 0, y: base)
        sea.zPosition = SceneryZ.back
        tile.addChild(sea)
        let glints = CGMutablePath()
        for (dx, length, dy) in [(4.0, 10.0, 2.0), (26.0, 7.0, 4.4), (44.0, 9.0, 1.2)] {
            glints.addRect(CGRect(x: dx, y: base + dy, width: length, height: 0.5))
        }
        let glintNode = SKShapeNode(path: glints)
        glintNode.fillColor = RunnerPalette.color(P.seaGlint)
        glintNode.strokeColor = .clear
        glintNode.alpha = 0.8
        glintNode.zPosition = SceneryZ.back
        tile.addChild(glintNode)

        // 貨物船（沖）。船体は台形、喫水線に錆色の帯、右寄りに船橋と煙突。
        if index.isMultiple(of: 3) {
            let hullPath = CGMutablePath()
            hullPath.addLines(between: [
                CGPoint(x: 14, y: base + 3.5), CGPoint(x: 52, y: base + 3.5),
                CGPoint(x: 55, y: base + 7.5), CGPoint(x: 12, y: base + 7.5),
            ])
            hullPath.closeSubpath()
            let hull = SKShapeNode(path: hullPath)
            hull.fillColor = RunnerPalette.color(P.shipHull)
            hull.strokeColor = .clear
            hull.zPosition = SceneryZ.middle
            tile.addChild(hull)
            let waterline = SKSpriteNode(color: RunnerPalette.color(P.shipWaterline), size: CGSize(width: 37, height: 0.7))
            waterline.anchorPoint = .zero
            waterline.position = CGPoint(x: 14.5, y: base + 3.5)
            waterline.zPosition = SceneryZ.middle
            tile.addChild(waterline)
            let bridge = SKSpriteNode(color: RunnerPalette.color(P.shipBridge), size: CGSize(width: 8, height: 4.2))
            bridge.anchorPoint = .zero
            bridge.position = CGPoint(x: 43, y: base + 7.5)
            bridge.zPosition = SceneryZ.middle
            tile.addChild(bridge)
            let funnel = SKSpriteNode(color: RunnerPalette.color(P.shipFunnel), size: CGSize(width: 2.4, height: 2.6))
            funnel.anchorPoint = .zero
            funnel.position = CGPoint(x: 45.5, y: base + 11.7)
            funnel.zPosition = SceneryZ.middle
            tile.addChild(funnel)
        }

        if index.isMultiple(of: 2) {
            // 岸壁のコンテナ。下段 2 つ・上段 1 つ。波板の筋は明るい縦線で 1 本のパス。
            let ribs = CGMutablePath()
            for (dx, dy, color) in [(4.0, 0.0, P.containerRust), (19.0, 0.0, P.containerBlue), (10.0, 5.0, P.containerGreen)] {
                let box = SKSpriteNode(color: RunnerPalette.color(color), size: CGSize(width: 14, height: 5))
                box.anchorPoint = .zero
                box.position = CGPoint(x: dx, y: base + dy)
                box.zPosition = SceneryZ.front
                tile.addChild(box)
                var x = dx + 1.2
                while x < dx + 14 - 0.8 {
                    ribs.addRect(CGRect(x: x, y: base + dy + 0.6, width: 0.35, height: 3.8))
                    x += 1.6
                }
            }
            let ribNode = SKShapeNode(path: ribs)
            ribNode.fillColor = RunnerPalette.color(P.containerRib)
            ribNode.strokeColor = .clear
            ribNode.zPosition = SceneryZ.front
            tile.addChild(ribNode)
        } else {
            // 桟橋。海に突き出た板と、海に立つ杭。
            let planks = SKSpriteNode(color: RunnerPalette.color(P.pierPlank), size: CGSize(width: 30, height: 1.1))
            planks.anchorPoint = .zero
            planks.position = CGPoint(x: 8, y: base + 2.6)
            planks.zPosition = SceneryZ.front
            tile.addChild(planks)
            let posts = CGMutablePath()
            for dx in [9.5, 17.0, 24.5, 32.0] {
                posts.addRect(CGRect(x: dx, y: base, width: 0.9, height: 3.4))
            }
            let postNode = SKShapeNode(path: posts)
            postNode.fillColor = RunnerPalette.color(P.pierPost)
            postNode.strokeColor = .clear
            postNode.zPosition = SceneryZ.front
            tile.addChild(postNode)
        }
    }

    /// 京都・奈良（`RunnerWorld.Scenery.kyotoNara`・#1824）。道の奥に土塀（瓦の笠つき）が全タイルに続き、
    /// その後ろにタイルの番号で五重塔（3 で割り切れる番号）・鳥居（余り 1）・寺の本堂と石段（余り 2）を
    /// 立て、紅葉の木を添える。五重塔の層・鳥居の柱と笠木・石段・柱はそれぞれ 1 本のパスにまとめ、
    /// 1 タイルあたり最大 11 ノード。色は `RunnerWorld.SceneryPalette`（どれも空と 2:1 未満・`WorldTests`）。
    private func addKyotoNara(to tile: SKNode, index: Int) {
        typealias P = RunnerWorld.SceneryPalette
        let width = Self.hillSpacing
        let base = Metrics.groundY

        switch index % 3 {
        case 0:
            // 五重塔。近景の丘の後ろ側（x 30〜44）に 5 層。軸部は上へ行くほど狭く、屋根は軸部より両側へ
            // 2.4 張り出す。てっぺんに相輪（細い棒）。
            let bodies = CGMutablePath(), roofs = CGMutablePath()
            let centerX = 37.0
            var y = base + 4.0
            for tier in 0..<5 {
                let bodyWidth = 9.0 - Double(tier) * 1.1
                let bodyHeight = 2.6
                bodies.addRect(CGRect(x: centerX - bodyWidth / 2, y: y, width: bodyWidth, height: bodyHeight))
                y += bodyHeight
                let roofWidth = bodyWidth + 4.8
                roofs.addRect(CGRect(x: centerX - roofWidth / 2, y: y, width: roofWidth, height: 1.1))
                y += 1.1
            }
            roofs.addRect(CGRect(x: centerX - 0.35, y: y, width: 0.7, height: 3.2))
            for (path, color) in [(bodies, P.pagodaBody), (roofs, P.pagodaRoof)] {
                let shape = SKShapeNode(path: path)
                shape.fillColor = RunnerPalette.color(color)
                shape.strokeColor = .clear
                shape.zPosition = SceneryZ.back
                tile.addChild(shape)
            }
            addMaple(to: tile, x: 12, canopyRadius: 4.2, trunkHeight: 4.5)
        case 1:
            // 鳥居。2 本の柱と、貫（下の横木）・笠木（上の横木。柱より両側へ張り出す）。
            // 土塀（高さ 4）の後ろに立つので、塀の上に 11 以上出る高さにする。
            let posts = CGMutablePath(), beams = CGMutablePath()
            for x in [10.0, 21.0] {
                posts.addRect(CGRect(x: x, y: base, width: 1.7, height: 15.0))
            }
            beams.addRect(CGRect(x: 8.6, y: base + 10.8, width: 15.6, height: 1.2))
            beams.addRect(CGRect(x: 7.0, y: base + 14.4, width: 18.8, height: 1.9))
            for path in [posts, beams] {
                let shape = SKShapeNode(path: path)
                shape.fillColor = RunnerPalette.color(P.toriiVermilion)
                shape.strokeColor = .clear
                shape.zPosition = SceneryZ.middle
                tile.addChild(shape)
            }
            addMaple(to: tile, x: 38, canopyRadius: 5.0, trunkHeight: 5.0)
            addMaple(to: tile, x: 50, canopyRadius: 3.6, trunkHeight: 3.8)
        default:
            // 寺の本堂。土塀の上に石段 3 段が顔を出し（寺は道より高い所に建つ）、その上に白壁、柱 3 本、
            // 軒の張り出した瓦屋根（台形）と棟。石段の下端は土塀の笠（base + 4.0）のすぐ上。
            let templeBase = base + 4.0
            let steps = CGMutablePath()
            for (i, stepWidth) in [26.0, 22.0, 18.0].enumerated() {
                steps.addRect(CGRect(x: 30 - stepWidth / 2, y: templeBase + Double(i) * 1.1, width: stepWidth, height: 1.1))
            }
            let stepNode = SKShapeNode(path: steps)
            stepNode.fillColor = RunnerPalette.color(P.templeSteps)
            stepNode.strokeColor = .clear
            stepNode.zPosition = SceneryZ.middle
            tile.addChild(stepNode)

            let wallBottom = templeBase + 3.3
            let wall = SKSpriteNode(color: RunnerPalette.color(P.templeWall), size: CGSize(width: 20, height: 5.2))
            wall.anchorPoint = .zero
            wall.position = CGPoint(x: 20, y: wallBottom)
            wall.zPosition = SceneryZ.middle
            tile.addChild(wall)

            let pillars = CGMutablePath()
            for x in [21.5, 29.6, 37.7] {
                pillars.addRect(CGRect(x: x, y: wallBottom, width: 0.8, height: 5.2))
            }
            let pillarNode = SKShapeNode(path: pillars)
            pillarNode.fillColor = RunnerPalette.color(P.wallCoping)
            pillarNode.strokeColor = .clear
            pillarNode.zPosition = SceneryZ.middle
            tile.addChild(pillarNode)

            let eave = wallBottom + 5.2
            let roof = CGMutablePath()
            roof.addLines(between: [
                CGPoint(x: 13, y: eave), CGPoint(x: 22, y: eave + 5.0),
                CGPoint(x: 38, y: eave + 5.0), CGPoint(x: 47, y: eave),
            ])
            roof.closeSubpath()
            roof.addRect(CGRect(x: 21, y: eave + 5.0, width: 18, height: 0.9))
            let roofNode = SKShapeNode(path: roof)
            roofNode.fillColor = RunnerPalette.color(P.templeRoof)
            roofNode.strokeColor = .clear
            roofNode.zPosition = SceneryZ.middle
            tile.addChild(roofNode)
            addMaple(to: tile, x: 5, canopyRadius: 3.8, trunkHeight: 4.0)
        }

        // 土塀。道のすぐ奥に全タイル続く。漆喰の壁の上に瓦の笠、足元に腰の線、12 おきに柱の線
        // （笠・腰・柱は 1 本のパス）。
        let wall = SKSpriteNode(color: RunnerPalette.color(P.earthenWall), size: CGSize(width: width, height: 3.2))
        wall.anchorPoint = .zero
        wall.position = CGPoint(x: 0, y: base)
        wall.zPosition = SceneryZ.front
        tile.addChild(wall)
        let trim = CGMutablePath()
        trim.addRect(CGRect(x: 0, y: base + 3.2, width: width, height: 0.8))
        trim.addRect(CGRect(x: 0, y: base, width: width, height: 0.5))
        var px = 6.0
        while px < width {
            trim.addRect(CGRect(x: px - 0.3, y: base, width: 0.6, height: 3.2))
            px += 12
        }
        let trimNode = SKShapeNode(path: trim)
        trimNode.fillColor = RunnerPalette.color(P.wallCoping)
        trimNode.strokeColor = .clear
        trimNode.zPosition = SceneryZ.front
        tile.addChild(trimNode)
    }

    /// 紅葉の木 1 本（京都・奈良）。幹の上に房状の樹冠（楕円 2 つ）。土塀の後ろ（`SceneryZ.middle`）に立つ。
    /// 樹冠は**別ノード**で重ねる——1 本のパスに楕円を重ねると nonZero 塗りで重なりに穴が開く。
    private func addMaple(to tile: SKNode, x: Double, canopyRadius r: Double, trunkHeight: Double) {
        typealias P = RunnerWorld.SceneryPalette
        let trunk = SKSpriteNode(color: RunnerPalette.color(P.mapleTrunk), size: CGSize(width: 1.2, height: trunkHeight + r))
        trunk.anchorPoint = CGPoint(x: 0.5, y: 0)
        trunk.position = CGPoint(x: x, y: Metrics.groundY)
        trunk.zPosition = SceneryZ.middle
        tile.addChild(trunk)
        let cy = Metrics.groundY + trunkHeight + r * 0.9
        for (dx, dy, w, h) in [(0.0, 0.0, r * 2.2, r * 1.6), (-r * 0.6, r * 0.45, r * 1.4, r * 1.2), (r * 0.55, r * 0.5, r * 1.3, r * 1.1)] {
            let puff = SKShapeNode(ellipseOf: CGSize(width: w, height: h))
            puff.fillColor = RunnerPalette.color(P.mapleCanopy)
            puff.strokeColor = .clear
            puff.position = CGPoint(x: x + dx, y: cy + dy)
            puff.zPosition = SceneryZ.middle
            tile.addChild(puff)
        }
    }

    /// 温泉街（`RunnerWorld.Scenery.onsen`・#1938）。山の頂に雪、道の奥に提灯の並ぶ低い柵が全タイルに続き、
    /// その後ろにタイルの番号で旅館（3 で割り切れる番号）・外湯（のれんと提灯・余り 1）・源泉の櫓（余り 2）を
    /// 立て、湯けむりを添える。色は `RunnerWorld.SceneryPalette`（どれも空と 2:1 未満）。
    private func addOnsen(to tile: SKNode, index: Int) {
        typealias P = RunnerWorld.SceneryPalette
        let width = Self.hillSpacing
        let base = Metrics.groundY

        // 山の雪。丘の山（`buildHills` の 3 つ）と同じ楕円を白で描き、頂から 28% だけをマスクで残す
        // （稜線に沿った雪の帯になる）。
        for (dx, w, h) in [(8.0, 42.0, 34.0), (42.0, 36.0, 27.0), (22.0, 34.0, 19.0)] {
            let crop = SKCropNode()
            let mask = SKSpriteNode(color: .white, size: CGSize(width: w, height: h * 0.2))
            mask.anchorPoint = CGPoint(x: 0.5, y: 0)
            mask.position = CGPoint(x: dx, y: base + h * 0.8)
            crop.maskNode = mask
            let cap = SKShapeNode(ellipseOf: CGSize(width: w, height: h * 2))
            cap.fillColor = RunnerPalette.color(P.snow)
            cap.strokeColor = .clear
            cap.position = CGPoint(x: dx, y: base)
            crop.addChild(cap)
            crop.zPosition = SceneryZ.back
            tile.addChild(crop)
        }

        switch index % 3 {
        case 0:
            // 旅館。3 階建ての木造。壁に窓（障子の灯り）が 3 段、各階の軒に横の梁、上に雪をかぶった瓦屋根。
            let x0 = 8.0, w = 32.0, floorH = 3.4
            let wall = SKSpriteNode(color: RunnerPalette.color(P.ryokanWall), size: CGSize(width: w, height: floorH * 3))
            wall.anchorPoint = .zero
            wall.position = CGPoint(x: x0, y: base)
            wall.zPosition = SceneryZ.middle
            tile.addChild(wall)
            let timber = CGMutablePath(), glow = CGMutablePath()
            for f in 0..<3 {
                let y = base + Double(f) * floorH
                timber.addRect(CGRect(x: x0, y: y + floorH - 0.6, width: w, height: 0.6))
                var wx = x0 + 2.0
                while wx + 2.4 <= x0 + w - 1.5 {
                    glow.addRect(CGRect(x: wx, y: y + 0.9, width: 2.4, height: 1.8))
                    wx += 4.2
                }
            }
            timber.addRect(CGRect(x: x0 - 0.4, y: base, width: 0.8, height: floorH * 3))
            timber.addRect(CGRect(x: x0 + w - 0.4, y: base, width: 0.8, height: floorH * 3))
            for (path, color) in [(glow, P.windowGlow), (timber, P.ryokanTimber)] {
                let shape = SKShapeNode(path: path)
                shape.fillColor = RunnerPalette.color(color)
                shape.strokeColor = .clear
                shape.zPosition = SceneryZ.middle
                tile.addChild(shape)
            }
            addSnowRoof(to: tile, left: x0 - 2.5, right: x0 + w + 2.5, eave: base + floorH * 3, rise: 3.2)
            addSteam(to: tile, x: x0 + w + 6, y: base + 2, scale: 1.0)
        case 1:
            // 外湯。平屋の湯屋。入口に藍ののれん（3 枚）、両脇に提灯、屋根に雪。裏手から湯けむり。
            let x0 = 16.0, w = 22.0, h = 5.6
            let wall = SKSpriteNode(color: RunnerPalette.color(P.ryokanWall), size: CGSize(width: w, height: h))
            wall.anchorPoint = .zero
            wall.position = CGPoint(x: x0, y: base)
            wall.zPosition = SceneryZ.middle
            tile.addChild(wall)
            let noren = CGMutablePath()
            for i in 0..<3 {
                noren.addRect(CGRect(x: x0 + 7.4 + Double(i) * 2.5, y: base + 1.6, width: 2.2, height: 2.6))
            }
            let norenNode = SKShapeNode(path: noren)
            norenNode.fillColor = RunnerPalette.color(P.noren)
            norenNode.strokeColor = .clear
            norenNode.zPosition = SceneryZ.middle
            tile.addChild(norenNode)
            let timber = CGMutablePath()
            timber.addRect(CGRect(x: x0 + 7.0, y: base + 4.2, width: 8.2, height: 0.6))
            timber.addRect(CGRect(x: x0 + 6.6, y: base, width: 0.7, height: 4.6))
            timber.addRect(CGRect(x: x0 + 14.9, y: base, width: 0.7, height: 4.6))
            let timberNode = SKShapeNode(path: timber)
            timberNode.fillColor = RunnerPalette.color(P.ryokanTimber)
            timberNode.strokeColor = .clear
            timberNode.zPosition = SceneryZ.middle
            tile.addChild(timberNode)
            for lx in [x0 + 3.2, x0 + w - 3.2] {
                addLantern(to: tile, x: lx, y: base + 3.0, z: SceneryZ.middle)
            }
            addSnowRoof(to: tile, left: x0 - 2.0, right: x0 + w + 2.0, eave: base + h, rise: 2.6)
            addSteam(to: tile, x: x0 + w + 4, y: base + 3, scale: 1.2)
            addSteam(to: tile, x: x0 - 4, y: base + 1, scale: 0.7)
        default:
            // 源泉の櫓。木の脚 4 本（台形）に小さな屋根、てっぺんから太い湯けむり。横に小さな旅館。
            let cx = 44.0
            let legs = CGMutablePath()
            legs.addLines(between: [
                CGPoint(x: cx - 4.0, y: base), CGPoint(x: cx - 2.2, y: base + 11),
                CGPoint(x: cx - 1.2, y: base + 11), CGPoint(x: cx - 3.0, y: base),
            ])
            legs.closeSubpath()
            legs.addLines(between: [
                CGPoint(x: cx + 4.0, y: base), CGPoint(x: cx + 2.2, y: base + 11),
                CGPoint(x: cx + 1.2, y: base + 11), CGPoint(x: cx + 3.0, y: base),
            ])
            legs.closeSubpath()
            legs.addRect(CGRect(x: cx - 3.4, y: base + 4.0, width: 6.8, height: 0.6))
            legs.addRect(CGRect(x: cx - 2.8, y: base + 7.6, width: 5.6, height: 0.6))
            legs.addRect(CGRect(x: cx - 3.2, y: base + 11, width: 6.4, height: 0.8))
            let legNode = SKShapeNode(path: legs)
            legNode.fillColor = RunnerPalette.color(P.ryokanTimber)
            legNode.strokeColor = .clear
            legNode.zPosition = SceneryZ.middle
            tile.addChild(legNode)
            addSnowRoof(to: tile, left: cx - 4.5, right: cx + 4.5, eave: base + 11.8, rise: 2.0)
            addSteam(to: tile, x: cx, y: base + 13, scale: 1.5)

            let x0 = 6.0, w = 24.0, floorH = 3.4
            let wall = SKSpriteNode(color: RunnerPalette.color(P.ryokanWall), size: CGSize(width: w, height: floorH * 2))
            wall.anchorPoint = .zero
            wall.position = CGPoint(x: x0, y: base)
            wall.zPosition = SceneryZ.middle
            tile.addChild(wall)
            let timber = CGMutablePath(), glow = CGMutablePath()
            for f in 0..<2 {
                let y = base + Double(f) * floorH
                timber.addRect(CGRect(x: x0, y: y + floorH - 0.6, width: w, height: 0.6))
                var wx = x0 + 2.0
                while wx + 2.4 <= x0 + w - 1.5 {
                    glow.addRect(CGRect(x: wx, y: y + 0.9, width: 2.4, height: 1.8))
                    wx += 4.2
                }
            }
            for (path, color) in [(glow, P.windowGlow), (timber, P.ryokanTimber)] {
                let shape = SKShapeNode(path: path)
                shape.fillColor = RunnerPalette.color(color)
                shape.strokeColor = .clear
                shape.zPosition = SceneryZ.middle
                tile.addChild(shape)
            }
            addSnowRoof(to: tile, left: x0 - 2.0, right: x0 + w + 2.0, eave: base + floorH * 2, rise: 2.8)
        }

        // 道の奥の低い柵と提灯。柵は全タイル続き、12 おきに柱を立てて提灯を吊るす。
        let fence = SKSpriteNode(color: RunnerPalette.color(P.fence), size: CGSize(width: width, height: 1.6))
        fence.anchorPoint = .zero
        fence.position = CGPoint(x: 0, y: base + 0.6)
        fence.zPosition = SceneryZ.front
        tile.addChild(fence)
        let posts = CGMutablePath()
        var px = 6.0
        while px < width {
            posts.addRect(CGRect(x: px - 0.35, y: base, width: 0.7, height: 5.4))
            px += 12
        }
        let postNode = SKShapeNode(path: posts)
        postNode.fillColor = RunnerPalette.color(P.ryokanTimber)
        postNode.strokeColor = .clear
        postNode.zPosition = SceneryZ.front
        tile.addChild(postNode)
        px = 6.0
        while px < width {
            addLantern(to: tile, x: px, y: base + 3.6, z: SceneryZ.front)
            px += 12
        }
    }

    /// 雪をかぶった屋根（温泉街）。軒 `left`〜`right` から棟へ上がる台形の瓦屋根と、その上に白い雪の帯。
    private func addSnowRoof(to tile: SKNode, left: Double, right: Double, eave: Double, rise: Double) {
        typealias P = RunnerWorld.SceneryPalette
        let inset = rise * 1.4
        let roof = CGMutablePath()
        roof.addLines(between: [
            CGPoint(x: left, y: eave), CGPoint(x: left + inset, y: eave + rise),
            CGPoint(x: right - inset, y: eave + rise), CGPoint(x: right, y: eave),
        ])
        roof.closeSubpath()
        let roofNode = SKShapeNode(path: roof)
        roofNode.fillColor = RunnerPalette.color(P.ryokanRoof)
        roofNode.strokeColor = .clear
        roofNode.zPosition = SceneryZ.middle
        tile.addChild(roofNode)
        let snow = CGMutablePath()
        snow.addLines(between: [
            CGPoint(x: left + 0.3, y: eave + rise * 0.55), CGPoint(x: left + inset, y: eave + rise),
            CGPoint(x: right - inset, y: eave + rise), CGPoint(x: right - 0.3, y: eave + rise * 0.55),
            CGPoint(x: right - inset + 0.6, y: eave + rise + 1.0), CGPoint(x: left + inset - 0.6, y: eave + rise + 1.0),
        ])
        snow.closeSubpath()
        let snowNode = SKShapeNode(path: snow)
        snowNode.fillColor = RunnerPalette.color(P.snow)
        snowNode.strokeColor = .clear
        snowNode.zPosition = SceneryZ.middle
        tile.addChild(snowNode)
    }

    /// 提灯 1 つ（温泉街）。朱の丸い胴に上下の黒い口輪は付けず（背景は縁取りしない）、胴だけ。
    private func addLantern(to tile: SKNode, x: Double, y: Double, z: CGFloat) {
        let body = SKShapeNode(ellipseOf: CGSize(width: 1.8, height: 2.3))
        body.fillColor = RunnerPalette.color(RunnerWorld.SceneryPalette.lantern)
        body.strokeColor = .clear
        body.position = CGPoint(x: x, y: y)
        body.zPosition = z
        tile.addChild(body)
    }

    /// 湯けむり（温泉街）。白い丸を 4 つ、上へ行くほど小さく散らして半透明で重ね、ゆっくり上下させる。
    private func addSteam(to tile: SKNode, x: Double, y: Double, scale: Double) {
        let node = SKNode()
        for (dx, dy, r) in [(0.0, 0.0, 2.6), (-1.8, 2.4, 2.1), (1.6, 4.2, 1.8), (-0.4, 6.4, 1.3)] {
            let puff = SKShapeNode(circleOfRadius: r * scale)
            puff.fillColor = RunnerPalette.color(RunnerWorld.SceneryPalette.steam)
            puff.strokeColor = .clear
            puff.alpha = 0.78
            puff.position = CGPoint(x: dx * scale, y: dy * scale)
            node.addChild(puff)
        }
        node.position = CGPoint(x: x, y: y)
        node.zPosition = SceneryZ.back
        runAmbientLoop(.sequence([
            .moveBy(x: 0, y: 1.2, duration: 1.8),
            .moveBy(x: 0, y: -1.2, duration: 1.8),
        ]), on: node)
        tile.addChild(node)
    }

    /// 雪国（`RunnerWorld.Scenery.snow`・#2729）。道の奥に雪の壁が全タイルに続き、その後ろにタイルの番号で
    /// かまくら（3 で割り切れる番号）・雪をかぶった瓦屋根の家（余り 1）・枯れ木の並びと小さな家（余り 2）を立て、
    /// **遠くだけに雪がちらつく**（湯けむりと同じ「遠くだけ」の扱い。走者の手前には降らせず、踏み切る地点を隠さない）。
    /// 遠くの白い山は丘の 2 階調（`palette.hillFar` / `hillNear`）そのもの。色は `RunnerWorld.SceneryPalette`
    /// （どれも空と 2:1 未満・手前のキタキツネと 3:1 以上・`WorldTests`）。
    private func addSnow(to tile: SKNode, index: Int) {
        typealias P = RunnerWorld.SceneryPalette
        let width = Self.hillSpacing
        let base = Metrics.groundY

        switch index % 3 {
        case 0:
            // かまくら。雪の白いドーム（地面を中心にした円の上半分）に、右側へ青灰の陰をずらして重ね、
            // 入り口は中の暗がりのアーチ（背景なので黒くはしない）。
            let cx = 30.0, r = 9.5
            let shade = SKShapeNode(circleOfRadius: r)
            shade.fillColor = RunnerPalette.color(P.snowShade)
            shade.strokeColor = .clear
            shade.position = CGPoint(x: cx + 1.6, y: base - 0.4)
            shade.zPosition = SceneryZ.middle
            tile.addChild(shade)
            let dome = SKShapeNode(circleOfRadius: r)
            dome.fillColor = RunnerPalette.color(P.snow)
            dome.strokeColor = .clear
            dome.position = CGPoint(x: cx, y: base)
            dome.zPosition = SceneryZ.middle
            tile.addChild(dome)
            let door = SKShapeNode(ellipseOf: CGSize(width: 5.2, height: 9.0))
            door.fillColor = RunnerPalette.color(P.kamakuraDoor)
            door.strokeColor = .clear
            door.position = CGPoint(x: cx - 1.0, y: base)
            door.zPosition = SceneryZ.front
            tile.addChild(door)
            addBareTree(to: tile, x: 9, height: 12)
            addBareTree(to: tile, x: 51, height: 14)
        case 1:
            // 雪をかぶった瓦屋根の家 2 軒（平屋と二階建て）。障子窓に灯り。
            addSnowHouse(to: tile, x0: 5, width: 20, floors: 1)
            addSnowHouse(to: tile, x0: 33, width: 18, floors: 2)
        default:
            // 枯れ木の並びと、小さな家 1 軒。
            addBareTree(to: tile, x: 7, height: 14)
            addBareTree(to: tile, x: 18, height: 10)
            addSnowHouse(to: tile, x0: 28, width: 20, floors: 1)
            addBareTree(to: tile, x: 55, height: 12)
        }

        // 道の奥の雪の壁（除雪で寄せた雪）。全タイル続く白い帯の上に、雪の影の線を 1 本。
        let bank = SKSpriteNode(color: RunnerPalette.color(P.snow), size: CGSize(width: width, height: 2.6))
        bank.anchorPoint = .zero
        bank.position = CGPoint(x: 0, y: base)
        bank.zPosition = SceneryZ.front
        tile.addChild(bank)
        let bankShade = SKSpriteNode(color: RunnerPalette.color(P.snowShade), size: CGSize(width: width, height: 0.6))
        bankShade.anchorPoint = .zero
        bankShade.position = CGPoint(x: 0, y: base + 2.6)
        bankShade.zPosition = SceneryZ.front
        tile.addChild(bankShade)

        // ちらつく雪。小さな丸を 1 本のパスに散らし（乱数は使わない。撮影・QA で毎回同じ画）、
        // ゆっくり下へ流して戻す。丘のタイルに載せるので遠景の視差で流れ、走者の手前には来ない。
        let flakes = CGMutablePath()
        for (dx, dy, r) in [
            (4.0, 28.0, 0.55), (15.0, 36.0, 0.45), (27.0, 22.0, 0.5), (38.0, 40.0, 0.4), (49.0, 30.0, 0.55),
            (57.0, 18.0, 0.45), (9.0, 14.0, 0.4), (33.0, 12.0, 0.45), (45.0, 8.0, 0.4), (21.0, 44.0, 0.4),
        ] {
            flakes.addEllipse(in: CGRect(x: dx - r, y: base + dy - r, width: r * 2, height: r * 2))
        }
        let flakeNode = SKShapeNode(path: flakes)
        flakeNode.fillColor = RunnerPalette.color(P.snowflake)
        flakeNode.strokeColor = .clear
        flakeNode.alpha = 0.9
        flakeNode.zPosition = SceneryZ.back
        runAmbientLoop(.sequence([
            .moveBy(x: 0, y: -6, duration: 2.4),
            .moveBy(x: 0, y: 6, duration: 0),
        ]), on: flakeNode)
        tile.addChild(flakeNode)
    }

    /// 雪国の家 1 軒（#2729）。板張りの壁に障子窓の灯り、雪をかぶった瓦屋根（温泉街の `addSnowRoof` を使い回す）。
    private func addSnowHouse(to tile: SKNode, x0: Double, width w: Double, floors: Int) {
        typealias P = RunnerWorld.SceneryPalette
        let base = Metrics.groundY
        let floorH = 3.4
        let wall = SKSpriteNode(color: RunnerPalette.color(P.snowHouseWall), size: CGSize(width: w, height: floorH * Double(floors)))
        wall.anchorPoint = .zero
        wall.position = CGPoint(x: x0, y: base)
        wall.zPosition = SceneryZ.middle
        tile.addChild(wall)
        let glow = CGMutablePath()
        for f in 0..<floors {
            var wx = x0 + 2.0
            while wx + 2.4 <= x0 + w - 1.5 {
                glow.addRect(CGRect(x: wx, y: base + Double(f) * floorH + 0.9, width: 2.4, height: 1.8))
                wx += 4.6
            }
        }
        let glowNode = SKShapeNode(path: glow)
        glowNode.fillColor = RunnerPalette.color(P.windowGlow)
        glowNode.strokeColor = .clear
        glowNode.zPosition = SceneryZ.middle
        tile.addChild(glowNode)
        addSnowRoof(to: tile, left: x0 - 2.2, right: x0 + w + 2.2, eave: base + floorH * Double(floors), rise: 3.0)
    }

    /// 枯れ木 1 本（雪国・#2729）。幹の上に左右へ 3 本の枝。幹と枝は 1 本のパス（1 ノード）。
    private func addBareTree(to tile: SKNode, x: Double, height: Double) {
        typealias P = RunnerWorld.SceneryPalette
        let base = Metrics.groundY
        let path = CGMutablePath()
        path.addRect(CGRect(x: x - 0.6, y: base, width: 1.2, height: height))
        // 枝: 幹の途中から斜め上へ伸びる細い四角形（太さ 0.6）。
        for (fromY, dx, dy) in [(height * 0.45, -4.0, 3.5), (height * 0.6, 3.6, 3.2), (height * 0.8, -2.6, 2.8)] {
            let x0 = x + (dx > 0 ? 0.4 : -0.4), y0 = base + fromY
            path.addLines(between: [
                CGPoint(x: x0, y: y0), CGPoint(x: x0, y: y0 + 0.6),
                CGPoint(x: x0 + dx, y: y0 + dy + 0.6), CGPoint(x: x0 + dx, y: y0 + dy),
            ])
            path.closeSubpath()
        }
        let tree = SKShapeNode(path: path)
        tree.fillColor = RunnerPalette.color(P.bareTree)
        tree.strokeColor = .clear
        tree.zPosition = SceneryZ.middle
        tile.addChild(tree)
    }

    /// 東京（`RunnerWorld.Scenery.tokyo`・#2729）。宵の口。丘の 2 つの山（`palette.hillFar` / `hillNear`）の上に、同じ色で
    /// **タイルの幅いっぱいに続く四角いビル街**を 2 列（奥は高く、手前は低く）重ねて稜線を隠し、手前のビルには黄色い
    /// 窓の灯りとネオン看板（桃・水色・黄）を点す。タイルの番号で遠くの高い塔（3 で割り切れる番号 = 赤く灯る鉄塔、
    /// 余り 1 = 針のような塔。文言に名前は出さない）か信号機（余り 2）を立て、塔のてっぺんの航空灯は点滅する。
    /// 道の奥には全タイルに高架が続き、その上を窓に灯りの点いた電車がゆっくり左へ流れる（乱数は使わない。撮影・QA で
    /// 毎回同じ画）。面で塗る色は `RunnerWorld.SceneryPalette`（どれも空と 2:1 未満・手前の明るい犬・タクシー・ハトと
    /// 3:1 以上・`WorldTests`）。灯りは小さな点なので背景の帯には入れない（夜の繁華街の窓と同じ）。
    private func addTokyo(to tile: SKNode, index: Int) {
        typealias P = RunnerWorld.SceneryPalette
        let width = Self.hillSpacing
        let base = Metrics.groundY

        // 奥のビル街（丘の奥の山と同じ色・高さ 22〜34）。隙間なく並べて丘の稜線を覆う。
        let farBlocks = CGMutablePath()
        for (x0, x1, h) in [(0.0, 14.0, 34.0), (14.0, 24.0, 29.0), (24.0, 38.0, 31.0), (38.0, 50.0, 30.0), (50.0, 60.0, 28.0)] {
            farBlocks.addRect(CGRect(x: x0, y: base, width: x1 - x0, height: h))
        }
        let farNode = SKShapeNode(path: farBlocks)
        farNode.fillColor = RunnerPalette.color(world.palette.hillFar)
        farNode.strokeColor = .clear
        farNode.zPosition = SceneryZ.back
        tile.addChild(farNode)

        switch index % 3 {
        case 0:
            // 鉄塔の格子の高い塔。脚を広げた台形の塔体に、展望台の帯と細いアンテナ。
            let tower = CGMutablePath()
            let cx = 30.0
            tower.addLines(between: [
                CGPoint(x: cx - 6.5, y: base), CGPoint(x: cx + 6.5, y: base),
                CGPoint(x: cx + 1.2, y: base + 40), CGPoint(x: cx - 1.2, y: base + 40),
            ])
            tower.closeSubpath()
            tower.addRect(CGRect(x: cx - 4.0, y: base + 22, width: 8.0, height: 1.8))
            tower.addRect(CGRect(x: cx - 0.5, y: base + 40, width: 1.0, height: 6.0))
            let towerNode = SKShapeNode(path: tower)
            towerNode.fillColor = RunnerPalette.color(P.tower)
            towerNode.strokeColor = .clear
            towerNode.zPosition = SceneryZ.back
            tile.addChild(towerNode)
            addAviationLight(to: tile, x: cx, y: base + 46.5)
        case 1:
            // 針のような塔。細い塔体の途中に展望台の丸い帯、てっぺんにアンテナ。
            let needle = CGMutablePath()
            let cx = 44.0
            needle.addLines(between: [
                CGPoint(x: cx - 2.4, y: base), CGPoint(x: cx + 2.4, y: base),
                CGPoint(x: cx + 1.0, y: base + 44), CGPoint(x: cx - 1.0, y: base + 44),
            ])
            needle.closeSubpath()
            needle.addEllipse(in: CGRect(x: cx - 3.4, y: base + 30, width: 6.8, height: 3.0))
            needle.addRect(CGRect(x: cx - 0.4, y: base + 44, width: 0.8, height: 5.0))
            let needleNode = SKShapeNode(path: needle)
            needleNode.fillColor = RunnerPalette.color(P.needleTower)
            needleNode.strokeColor = .clear
            needleNode.zPosition = SceneryZ.back
            tile.addChild(needleNode)
            addAviationLight(to: tile, x: cx, y: base + 49.5)
        default:
            break
        }

        // 手前のビル街（丘の手前の山と同じ色・高さ 12〜20）。窓は黄色い灯り。決まった 1 枚おきに消して（乱数は使わない）
        // のっぺりさせない。
        let nearBlocks = CGMutablePath(), windows = CGMutablePath()
        var lit = 0
        for (x0, x1, h) in [(0.0, 8.0, 12.0), (8.0, 20.0, 17.0), (20.0, 30.0, 20.0), (30.0, 44.0, 14.0), (44.0, 60.0, 18.0)] {
            nearBlocks.addRect(CGRect(x: x0, y: base, width: x1 - x0, height: h))
            var wy = base + 8.0
            while wy + 1.6 < base + h - 1.0 {
                var wx = x0 + 1.4
                while wx + 1.2 <= x1 - 1.2 {
                    lit += 1
                    if lit % 5 != 0 { windows.addRect(CGRect(x: wx, y: wy, width: 1.2, height: 1.6)) }
                    wx += 3.0
                }
                wy += 3.4
            }
        }
        let nearNode = SKShapeNode(path: nearBlocks)
        nearNode.fillColor = RunnerPalette.color(world.palette.hillNear)
        nearNode.strokeColor = .clear
        nearNode.zPosition = SceneryZ.middle
        tile.addChild(nearNode)
        let windowNode = SKShapeNode(path: windows)
        windowNode.fillColor = RunnerPalette.color(P.cityWindow)
        windowNode.strokeColor = .clear
        windowNode.zPosition = SceneryZ.middle
        tile.addChild(windowNode)

        // ネオン看板。手前のビルの壁に縦長・横長の板を 3 枚（桃・水色・黄）。ゆっくり明滅する。
        for (x, y, w, h, color) in [
            (10.0, 2.0, 1.6, 7.0, P.neonPink), (22.5, 3.0, 5.0, 1.8, P.neonCyan), (47.0, 2.0, 1.6, 6.0, P.neonYellow),
        ] {
            let sign = SKSpriteNode(color: RunnerPalette.color(color), size: CGSize(width: w, height: h))
            sign.anchorPoint = .zero
            sign.position = CGPoint(x: x, y: base + y)
            sign.zPosition = SceneryZ.middle
            runAmbientLoop(.sequence([.fadeAlpha(to: 0.55, duration: 1.1), .fadeAlpha(to: 1.0, duration: 1.1)]), on: sign)
            tile.addChild(sign)
        }

        // 高架。道の奥に全タイル続くコンクリートの桁と、15 おきの柱。1 本のパス。
        let viaduct = CGMutablePath()
        let girderY = base + 3.6
        viaduct.addRect(CGRect(x: 0, y: girderY, width: width, height: 2.4))
        var px = 7.5
        while px < width {
            viaduct.addRect(CGRect(x: px - 0.8, y: base, width: 1.6, height: girderY - base))
            px += 15
        }
        let viaductNode = SKShapeNode(path: viaduct)
        viaductNode.fillColor = RunnerPalette.color(P.viaduct)
        viaductNode.strokeColor = .clear
        viaductNode.zPosition = SceneryZ.front
        tile.addChild(viaductNode)

        // 高架の上の電車（2 両）。車体に帯と窓の列。タイルの中で左へ流れて戻る（丘のタイルに載るので遠景の視差で動く）。
        let trainTop = girderY + 2.4
        let train = SKNode()
        for car in 0..<2 {
            let x0 = Double(car) * 25.0
            let body = SKSpriteNode(color: RunnerPalette.color(P.train), size: CGSize(width: 24, height: 3.6))
            body.anchorPoint = .zero
            body.position = CGPoint(x: x0, y: trainTop)
            train.addChild(body)
            let stripe = SKSpriteNode(color: RunnerPalette.color(P.trainStripe), size: CGSize(width: 24, height: 0.7))
            stripe.anchorPoint = .zero
            stripe.position = CGPoint(x: x0, y: trainTop + 0.9)
            train.addChild(stripe)
            let carWindows = CGMutablePath()
            var wx = x0 + 1.5
            while wx + 2.2 <= x0 + 24 - 1.0 {
                carWindows.addRect(CGRect(x: wx, y: trainTop + 1.9, width: 2.2, height: 1.2))
                wx += 3.4
            }
            let carWindowNode = SKShapeNode(path: carWindows)
            carWindowNode.fillColor = RunnerPalette.color(P.trainWindow)
            carWindowNode.strokeColor = .clear
            train.addChild(carWindowNode)
        }
        train.position = CGPoint(x: 8, y: 0)
        train.zPosition = SceneryZ.front
        runAmbientLoop(.sequence([
            .moveBy(x: -20, y: 0, duration: 3.2),
            .moveBy(x: 20, y: 0, duration: 0),
        ]), on: train)
        tile.addChild(train)

        if index % 3 == 2 {
            // 信号機。柱の上に横向きの筐体、左から青・（消灯）・赤の 3 灯。
            let pole = CGMutablePath()
            pole.addRect(CGRect(x: 51.3, y: base, width: 1.4, height: 15.0))
            pole.addRect(CGRect(x: 44.0, y: base + 15.0, width: 9.6, height: 3.0))
            let poleNode = SKShapeNode(path: pole)
            poleNode.fillColor = RunnerPalette.color(P.signalPole)
            poleNode.strokeColor = .clear
            poleNode.zPosition = SceneryZ.front
            tile.addChild(poleNode)
            for (dx, color) in [(45.0, P.signalGreen), (50.6, P.signalRed)] {
                let lamp = SKShapeNode(circleOfRadius: 0.95)
                lamp.fillColor = RunnerPalette.color(color)
                lamp.strokeColor = .clear
                lamp.position = CGPoint(x: dx + 0.95, y: base + 16.5)
                lamp.zPosition = SceneryZ.front
                tile.addChild(lamp)
            }
        }
    }

    /// 塔のてっぺんの航空灯（東京・#2729）。赤い点がゆっくり点滅する。
    private func addAviationLight(to tile: SKNode, x: Double, y: Double) {
        let light = SKShapeNode(circleOfRadius: 0.7)
        light.fillColor = RunnerPalette.color(RunnerWorld.SceneryPalette.aviationLight)
        light.strokeColor = .clear
        light.position = CGPoint(x: x, y: y)
        light.zPosition = SceneryZ.back
        runAmbientLoop(.sequence([.fadeAlpha(to: 0.15, duration: 0.9), .fadeAlpha(to: 1.0, duration: 0.9)]), on: light)
        tile.addChild(light)
    }

    /// 里山・港町・京都・奈良の遠景の部品の相対 z（`hillLayer` の中。丘の山は 0）。家並みの `HouseZ` と同じ考え方。
    private enum SceneryZ {
        static let back: CGFloat = 1
        static let middle: CGFloat = 2
        static let front: CGFloat = 3
    }

    /// 丘の山ひとつ。半分だけ地面から顔を出す楕円（下半分は `courseLayer` の地面に隠れる）。
    private func addHillBump(to tile: SKNode, color: UInt32, width: Double, height: Double, dx: Double) {
        let bump = SKShapeNode(ellipseOf: CGSize(width: width, height: height * 2))
        bump.fillColor = RunnerPalette.color(color)
        bump.strokeColor = .clear
        bump.position = CGPoint(x: dx, y: Metrics.groundY)
        tile.addChild(bump)
    }
}
