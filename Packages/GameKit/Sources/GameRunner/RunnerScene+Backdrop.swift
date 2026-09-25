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
        guard world.scenery == .riverside else { return }
        let glow = SKSpriteNode(
            color: RunnerPalette.color(RunnerWorld.SceneryPalette.sunsetGlow),
            size: CGSize(width: Metrics.width, height: 30)
        )
        glow.anchorPoint = .zero
        glow.position = CGPoint(x: 0, y: Metrics.groundY)
        backdropLayer.addChild(glow)
        // 帯の上端をぼかす代わりに、半透明の 1 枚を重ねて 2 段にする（テクスチャを使わない）。
        let haze = SKSpriteNode(
            color: RunnerPalette.color(RunnerWorld.SceneryPalette.sunsetGlow),
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

    /// 里山・港町の遠景の部品の相対 z（`hillLayer` の中。丘の山は 0）。家並みの `HouseZ` と同じ考え方。
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
