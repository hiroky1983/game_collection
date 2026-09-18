import Core
import Foundation
import SpriteKit

/// 里山・港町（#1009）で今ある障害を着せ替えた部品。**動き・当たり判定・寸法は元の部品と同じ**で、
/// どれを描くかは `RunnerWorld.dressing` が決める（朝・夕方・夜はここを通らず、元の部品
/// `makeRock` / `makePlatform` / `makeBoostFloor` / `addPitVoid` / `addPitEdgeMarkers` がそのまま描く）。
///
/// 犬・イノシシ・鳥の着せ替えはここには無い——犬（猫）とイノシシ（フォークリフト）は
/// `RunnerPixelArt.walker` / `charger` のドット絵の差し替え（`addDog` / `addBoar` が世界の格子を貼る）、
/// 鳥（カラス・カモメ）は `RunnerWorld.creatures` の色だけで済む。
extension RunnerScene {
    // MARK: 岩の枠（切り株・ロープの束・ドラム缶）

    /// 低い岩・高い岩。岩塊のままの世界（と里山の大きな石）は `makeRock`、それ以外は着せ替えの
    /// ドット絵（`blockTextures`）を**当たり判定の箱いっぱい**に貼る。格子の縦横比は箱と同じ
    /// （12×15 = 4×5、12×27 = 4×9。`RunnerPixelArtTests` が固定）なので、貼っても伸びない。
    /// 接地の陰は岩塊と同じ平たい楕円。
    func makeBlock(_ hazard: RunnerHazard) -> SKNode {
        // 岩塊は明示的に元の経路へ（`blockTextures` に `.boulder` の項が無いことに寄りかからない）。
        guard let style = world.dressing.block(for: hazard.kind), style != .boulder,
              let texture = blockTextures[style] else {
            return makeRock(hazard)
        }
        let node = SKNode()
        node.position = CGPoint(x: hazard.start, y: Metrics.groundY)
        let w = hazard.length, h = hazard.height

        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 1.05, height: h * 0.14))
        shadow.fillColor = RunnerPalette.color(world.palette.rockDark)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: w / 2, y: 0)
        node.addChild(shadow)

        let sprite = SKSpriteNode(texture: texture)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.size = CGSize(width: w, height: h)
        sprite.position = CGPoint(x: w / 2, y: 0)
        sprite.zPosition = 1
        node.addChild(sprite)
        return node
    }

    // MARK: 高い塀（石垣・積まれたコンテナ・#1091）

    /// 二段ジャンプでしか越えられない高い塀。**当たり判定の箱いっぱい**（4 × `wallTop` = 18）に
    /// ドット絵を貼るだけで、岩の着せ替え（`makeBlock`）とまったく同じ作り。格子は 12×54 で
    /// 箱と同じ縦横比（`RunnerPixelArtTests.wallsFitTheWallHitBox` が固定）なので、貼っても伸びない。
    ///
    /// 絵は**その世界で最初に使うときに作ってキャッシュ**する（`RunnerScene.wallTexture`）。
    /// 接地の陰は岩と同じ平たい楕円——高さが 2 倍以上あるので、陰は箱の高さではなく**幅**から出す
    /// （岩と同じ式だと塀の足元に大きな黒い楕円が出て、地面が凹んで見える）。
    func makeWall(_ hazard: RunnerHazard) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: hazard.start, y: Metrics.groundY)
        let w = hazard.length, h = hazard.height

        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 1.15, height: w * 0.25))
        shadow.fillColor = RunnerPalette.color(world.palette.rockDark)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: w / 2, y: 0)
        node.addChild(shadow)

        let sprite = SKSpriteNode(texture: wallTexture(world.dressing.wall))
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        sprite.size = CGSize(width: w, height: h)
        sprite.position = CGPoint(x: w / 2, y: 0)
        sprite.zPosition = 1
        node.addChild(sprite)
        return node
    }

    // MARK: 穴（用水路・岸壁の切れ目）

    /// 用水路の水（`Dressing.Pit.irrigationDitch`）。奈落（`addPitVoid`）と同じ矩形を深い水で塗り、
    /// 路面の少し下に明るい水面の帯を敷く。幅は穴の当たり判定そのもの。
    func addDitchWater(_ pit: RunnerHazard, into parent: SKNode) {
        addWaterFilledPit(
            pit, into: parent,
            deep: RunnerWorld.DressingPalette.ditchWater, surface: RunnerWorld.DressingPalette.ditchSurface
        )
    }

    /// 岸壁の切れ目の海（`Dressing.Pit.quayGap`）。
    func addGapSea(_ pit: RunnerHazard, into parent: SKNode) {
        addWaterFilledPit(
            pit, into: parent,
            deep: RunnerWorld.DressingPalette.gapSea, surface: RunnerWorld.DressingPalette.gapSurface
        )
    }

    /// 水の入った穴。丘の楕円は地面より下にも半分伸びている（`addHillBump`）ので、奈落と同じく
    /// **画面の下端まで**塗って穴の中に丘が透けないようにする。水面の帯は路面の 1.6 下——
    /// 「落ちる高さがある」と読める段差。
    private func addWaterFilledPit(_ pit: RunnerHazard, into parent: SKNode, deep: UInt32, surface: UInt32) {
        let water = SKSpriteNode(
            color: RunnerPalette.color(deep),
            size: CGSize(width: pit.length, height: Metrics.groundY)
        )
        water.anchorPoint = .zero
        water.position = CGPoint(x: pit.start, y: 0)
        parent.addChild(water)

        let band = SKSpriteNode(
            color: RunnerPalette.color(surface),
            size: CGSize(width: pit.length, height: 0.9)
        )
        band.anchorPoint = .zero
        band.position = CGPoint(x: pit.start, y: Metrics.groundY - 2.5)
        parent.addChild(band)
        // 照り返し。水面の帯の上に細い明るい線を 1 本、両端を少し空けて置く。
        let glint = SKSpriteNode(
            color: RunnerPalette.color(RunnerWorld.DressingPalette.waterGlint),
            size: CGSize(width: max(0.5, pit.length - 2.4), height: 0.3)
        )
        glint.anchorPoint = .zero
        glint.alpha = 0.7
        glint.position = CGPoint(x: pit.start + 1.2, y: Metrics.groundY - 1.3)
        parent.addChild(glint)
    }

    /// 用水路のコンクリートの壁。穴の両端に、路面から水面の下まで明るい灰の縦帯を立てる
    /// （柵 `addPitEdgeMarkers` と同じく端の x を中心に置き、地面と穴にまたがる）。
    func addDitchWalls(_ pit: RunnerHazard, into parent: SKNode) {
        for edgeX in [pit.start, pit.end] {
            let wall = SKSpriteNode(
                color: RunnerPalette.color(RunnerWorld.DressingPalette.ditchWall),
                size: CGSize(width: 0.9, height: 4.0)
            )
            wall.anchorPoint = CGPoint(x: 0.5, y: 1)
            wall.position = CGPoint(x: edgeX, y: Metrics.groundY)
            parent.addChild(wall)
        }
    }

    /// 岸壁の切れ目の縁。黒いゴムの防舷材（古タイヤ）を両端に吊るし、縁の上端に穴の柵と同じ
    /// 黄の帯を 1 段だけ残す（このゲームで黄色は「縁に気をつけろ」の意味を持っている）。
    func addQuayFenders(_ pit: RunnerHazard, into parent: SKNode) {
        for edgeX in [pit.start, pit.end] {
            let edge = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.pitEdge),
                size: CGSize(width: 0.8, height: 0.6)
            )
            edge.anchorPoint = CGPoint(x: 0.5, y: 1)
            edge.position = CGPoint(x: edgeX, y: Metrics.groundY)
            parent.addChild(edge)

            let fender = SKShapeNode(rectOf: CGSize(width: 1.3, height: 1.9), cornerRadius: 0.5)
            fender.fillColor = RunnerPalette.color(RunnerWorld.DressingPalette.fender)
            fender.strokeColor = .clear
            fender.position = CGPoint(x: edgeX, y: Metrics.groundY - 1.7)
            parent.addChild(fender)
        }
    }

    // MARK: 台座（わら積み・木箱の山）

    /// 台座の上面（歩く面）の厚み。足場の床板（`makePlatform`）と同じ。
    private static let dressedDeckHeight = 1.6

    /// わら積み（`Dressing.Platform.strawStack`）。上面（歩く面）がいちばん明るい黄土、その下に
    /// わらの本体と横の筋、縄で縛った縦の帯。左端の警告帯（正面から突っ込むとミス）と
    /// 上面の縁取りは足場と同じ約束。
    func makeStrawStack(_ platform: RunnerPlatform) -> SKNode {
        typealias P = RunnerWorld.DressingPalette
        let node = SKNode()
        node.position = CGPoint(x: platform.start, y: Metrics.groundY)
        let w = platform.length, top = platform.top
        let bodyTop = top - Self.dressedDeckHeight - 0.5

        let body = SKSpriteNode(color: RunnerPalette.color(P.strawBody), size: CGSize(width: w, height: bodyTop))
        body.anchorPoint = .zero
        node.addChild(body)

        // わらの筋。長さ・位置をずらした細い帯を段ごとに並べ、1 本のパスにまとめる。
        let streaks = CGMutablePath()
        var y = 0.9
        var phase = 0
        while y < bodyTop - 0.5 {
            var x = Double(phase % 3) * 1.4
            while x < w - 1 {
                let length = min(3.2 + Double((phase + Int(x)) % 3) * 0.8, w - x - 0.5)
                streaks.addRect(CGRect(x: x, y: y, width: length, height: 0.35))
                x += length + 1.6
            }
            y += 1.5
            phase += 1
        }
        let streakNode = SKShapeNode(path: streaks)
        streakNode.fillColor = RunnerPalette.color(P.strawShade)
        streakNode.strokeColor = .clear
        node.addChild(streakNode)

        // 縄。12 単位ごとに縦の帯を 1 本（足場の支柱と同じ間隔）。
        let ropes = CGMutablePath()
        let ropeSpacing = 12.0
        var rx = ropeSpacing / 2
        while rx < w - 1 {
            ropes.addRect(CGRect(x: rx, y: 0, width: 0.6, height: top - Self.dressedDeckHeight))
            rx += ropeSpacing
        }
        let ropeNode = SKShapeNode(path: ropes)
        ropeNode.fillColor = RunnerPalette.color(P.strawRope)
        ropeNode.strokeColor = .clear
        node.addChild(ropeNode)

        addDressedDeck(to: node, width: w, top: top, deck: P.strawTop, shade: P.strawShade)
        return node
    }

    /// 木箱の山（`Dressing.Platform.crateStack`）。幅 8 の木箱を 1 段に並べ、上面（歩く面）を
    /// いちばん明るい板色にする。箱の縁・板の継ぎ目・斜めの補強材は暗い線で 1 本のパスに描く。
    func makeCrateStack(_ platform: RunnerPlatform) -> SKNode {
        typealias P = RunnerWorld.DressingPalette
        let node = SKNode()
        node.position = CGPoint(x: platform.start, y: Metrics.groundY)
        let w = platform.length, top = platform.top
        let bodyTop = top - Self.dressedDeckHeight - 0.5

        let body = SKSpriteNode(color: RunnerPalette.color(P.crateWood), size: CGSize(width: w, height: bodyTop))
        body.anchorPoint = .zero
        node.addChild(body)

        let lines = CGMutablePath()
        let crateWidth = 8.0
        let count = max(1, Int((w / crateWidth).rounded()))
        let actualWidth = w / Double(count)
        for i in 0..<count {
            let x0 = Double(i) * actualWidth
            // 箱の左の縁（最後の箱は右の縁も）。
            lines.addRect(CGRect(x: x0, y: 0, width: 0.45, height: bodyTop))
            if i == count - 1 { lines.addRect(CGRect(x: x0 + actualWidth - 0.45, y: 0, width: 0.45, height: bodyTop)) }
            // 板の継ぎ目（上下 2 本）。
            lines.addRect(CGRect(x: x0, y: bodyTop * 0.33, width: actualWidth, height: 0.3))
            lines.addRect(CGRect(x: x0, y: bodyTop * 0.66, width: actualWidth, height: 0.3))
            // 斜めの補強材（左下から右上へ）。
            let inset = 0.9, t = 0.5
            lines.addLines(between: [
                CGPoint(x: x0 + inset, y: 0.5), CGPoint(x: x0 + inset + t, y: 0.5),
                CGPoint(x: x0 + actualWidth - inset, y: bodyTop - 0.5),
                CGPoint(x: x0 + actualWidth - inset - t, y: bodyTop - 0.5),
            ])
            lines.closeSubpath()
        }
        // 箱の底の縁。
        lines.addRect(CGRect(x: 0, y: 0, width: w, height: 0.45))
        let lineNode = SKShapeNode(path: lines)
        lineNode.fillColor = RunnerPalette.color(P.crateLine)
        lineNode.strokeColor = .clear
        node.addChild(lineNode)

        addDressedDeck(to: node, width: w, top: top, deck: P.crateTop, shade: P.crateLine)
        return node
    }

    /// 着せ替えた台座の上面一式。足場の床板（`makePlatform`）と同じ構成——上面の下に暗い帯を 1 本、
    /// 上面に世界の縁取り、左端に穴の柵と同じ黄の警告帯（正面から突っ込むとミスになる面）。
    private func addDressedDeck(to node: SKNode, width w: Double, top: Double, deck: UInt32, shade: UInt32) {
        let deckHeight = Self.dressedDeckHeight
        let underShadow = SKSpriteNode(color: RunnerPalette.color(shade), size: CGSize(width: w, height: 0.5))
        underShadow.anchorPoint = .zero
        underShadow.position = CGPoint(x: 0, y: top - deckHeight - 0.5)
        underShadow.zPosition = 1
        node.addChild(underShadow)

        let deckNode = SKSpriteNode(color: RunnerPalette.color(deck), size: CGSize(width: w, height: deckHeight))
        deckNode.anchorPoint = .zero
        deckNode.position = CGPoint(x: 0, y: top - deckHeight)
        deckNode.zPosition = 2
        node.addChild(deckNode)

        let deckOutline = SKShapeNode(rect: CGRect(x: 0, y: top - deckHeight, width: w, height: deckHeight))
        deckOutline.fillColor = .clear
        outline(deckOutline)
        deckOutline.zPosition = 2.5
        node.addChild(deckOutline)

        let face = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.pitEdge), size: CGSize(width: 0.7, height: top))
        face.anchorPoint = .zero
        face.zPosition = 3
        node.addChild(face)
    }

    // MARK: 加速床（舗装された農道・ベルトコンベア）

    /// 舗装された農道（`Dressing.BoostFloor.pavedFarmRoad`）。砂利の農道（`road.asphalt`）の中に
    /// 黒いアスファルトの区間を敷き、白い山形の矢印を右へ流す。「前へ押される区間」を色と
    /// 形と動きで伝える約束（`makeBoostFloor`）はそのまま。
    func makePavedFarmRoad(_ floor: RunnerBoostFloor) -> SKNode {
        typealias P = RunnerWorld.DressingPalette
        let node = SKNode()
        node.position = CGPoint(x: floor.start, y: 0)
        let height = Self.roadHeight
        let bottom = Metrics.groundY - height
        addBand(to: node, color: P.pavedAsphalt, x: 0, y: bottom, width: floor.length, height: height)
        for edgeY in [bottom, Metrics.groundY - 0.5] {
            addBand(to: node, color: P.pavedEdge, x: 0, y: edgeY, width: floor.length, height: 0.5)
        }
        addFlowingChevrons(to: node, length: floor.length, bottom: bottom, height: height, color: P.pavedArrow)
        return node
    }

    /// ベルトコンベア（`Dressing.BoostFloor.conveyor`）。黒いゴムのベルトを鋼の枠で挟み、下の縁に
    /// ローラーを並べ、黄の矢印を右へ流す。ローラーは 1 本のパス（区間が長くても 1 ノード）。
    func makeConveyor(_ floor: RunnerBoostFloor) -> SKNode {
        typealias P = RunnerWorld.DressingPalette
        let node = SKNode()
        node.position = CGPoint(x: floor.start, y: 0)
        let height = Self.roadHeight
        let bottom = Metrics.groundY - height
        addBand(to: node, color: P.conveyorBelt, x: 0, y: bottom, width: floor.length, height: height)
        addBand(to: node, color: P.conveyorFrame, x: 0, y: Metrics.groundY - 0.6, width: floor.length, height: 0.6)
        addBand(to: node, color: P.conveyorFrame, x: 0, y: bottom, width: floor.length, height: 0.8)

        let rollers = CGMutablePath()
        let spacing = 4.0
        var x = spacing / 2
        while x < floor.length - 1 {
            rollers.addEllipse(in: CGRect(x: x - 0.7, y: bottom + 0.1, width: 1.4, height: 1.4))
            x += spacing
        }
        let rollerNode = SKShapeNode(path: rollers)
        rollerNode.fillColor = RunnerPalette.color(P.conveyorRoller)
        rollerNode.strokeColor = .clear
        rollerNode.zPosition = 1
        node.addChild(rollerNode)

        addFlowingChevrons(to: node, length: floor.length, bottom: bottom + 1.0, height: height - 1.6, color: P.conveyorArrow)
        return node
    }

    // MARK: 沈む床（田んぼ・干潟・#1089）

    /// 沈む床（#1089）。**路面を水面／泥に塗り替え、地面の線より上へ突き出す目印を並べる**。
    ///
    /// 加速床（`makeBoostFloor`）と同じく当たり判定を一切持たない区間なので、岩・鳥のような
    /// 「地面から生えた物」には見せない。代わりに、
    ///
    /// - 路面の厚み（`roadHeight`）を沈む色で塗り、上 7 割を水面／泥、下を底の暗がりにする
    ///   （段差で「深さ」が出る。走者は沈むほどこの暗がりに浸かって見える）
    /// - **地面の線より上へ 2.2〜2.5 だけ突き出す目印**（田んぼ＝苗・干潟＝穴から出た泡）を並べる。
    ///   走者の高さ 11 に対して十分低いので当たる物には見えないが、**踏み込む前に
    ///   「ここから沈む」と読める**（決裁の受け入れ条件「入る前に分かる見た目」）。
    ///   照り（下の `addGlint`）は水面のマスクで切られるので、この役目は担えない
    /// - 照りの線を右へ流して、止まっている地面ではないことを動きでも伝える
    ///
    /// 両端の岸（`RunnerRules.sinkFloorBankTiles`）はここでは描かない——区間の外は路面のままで、
    /// それがそのままあぜ道・岸に見える。
    func makeSinkFloor(_ floor: RunnerSinkFloor) -> SKNode {
        typealias P = RunnerWorld.DressingPalette
        let paddy = world.dressing.sinkFloor == .paddy
        let node = SKNode()
        node.position = CGPoint(x: floor.start, y: 0)
        let height = Self.roadHeight
        let bottom = Metrics.groundY - height
        let surfaceHeight = height * 0.7
        addBand(to: node, color: paddy ? P.paddyDeep : P.tidelandDeep,
                x: 0, y: bottom, width: floor.length, height: height)
        addBand(to: node, color: paddy ? P.paddyWater : P.tidelandMud,
                x: 0, y: Metrics.groundY - surfaceHeight, width: floor.length, height: surfaceHeight)

        // 水面（泥）の模様。田んぼは苗の列、干潟はカニの穴。どちらも 1 本のパスにまとめて
        // 1 ノードで描く（長い床でもノード数が増えない。`makeConveyor` のローラーと同じ作法）。
        let marks = CGMutablePath()
        let spacing = 5.0
        var x = spacing / 2
        while x < floor.length - 1 {
            if paddy {
                // 苗: 水面から 2.5 だけ突き出す細い縦線を 2 本ずつ。
                for dx in [-0.9, 0.9] {
                    marks.addRect(CGRect(x: x + dx - 0.35, y: Metrics.groundY - 1.4, width: 0.7, height: 3.9))
                }
            } else {
                // カニの穴: 泥の面に開いた小さな穴。
                marks.addEllipse(in: CGRect(x: x - 0.8, y: Metrics.groundY - 2.2, width: 1.6, height: 1.1))
                // 穴から出た泡（跳ねた泥）。**苗と同じく地面の線より上へ 2.4 突き出す**
                // ——これが無いと干潟には「踏み込む前に読める目印」が 1 つも無い
                // （穴も照りも地面の線より下で、照りは水面のマスクで切られる。PR #1110 の指摘）。
                marks.addEllipse(in: CGRect(x: x - 0.6, y: Metrics.groundY + 0.2, width: 1.2, height: 1.2))
                marks.addEllipse(in: CGRect(x: x + 0.9, y: Metrics.groundY + 1.4, width: 0.8, height: 0.8))
            }
            x += spacing
        }
        let markNode = SKShapeNode(path: marks)
        markNode.fillColor = RunnerPalette.color(paddy ? P.paddySeedling : P.tidelandHole)
        markNode.strokeColor = .clear
        markNode.zPosition = 2
        node.addChild(markNode)

        // 水面（泥）の照り。**水面のマスクで切るので地面の線より上には出ない**——踏み込む前の
        // 目印は上の `marks`（苗・泡）が担う。
        let glints = CGMutablePath()
        let glintSpacing = 9.0
        var gx = 0.0
        while gx < floor.length + glintSpacing {
            addGlint(to: glints, at: gx, groundY: Metrics.groundY, paddy: paddy)
            gx += glintSpacing
        }
        let glintNode = SKShapeNode(path: glints)
        glintNode.fillColor = RunnerPalette.color(paddy ? P.waterGlint : P.tidelandSheen)
        glintNode.strokeColor = .clear
        glintNode.alpha = 0.85
        glintNode.zPosition = 1
        // 1 周期ぶん右へ流して戻す（`addFlowingChevrons` と同じ、継ぎ目の出ない流し方）。
        glintNode.position = CGPoint(x: -glintSpacing, y: 0)
        glintNode.run(.repeatForever(.sequence([
            .moveBy(x: glintSpacing, y: 0, duration: 1.6),
            .moveBy(x: -glintSpacing, y: 0, duration: 0),
        ])), withKey: Self.loopActionKey)
        let crop = SKCropNode()
        let mask = SKSpriteNode(color: .white, size: CGSize(width: floor.length, height: surfaceHeight))
        mask.anchorPoint = .zero
        mask.position = CGPoint(x: 0, y: Metrics.groundY - surfaceHeight)
        crop.maskNode = mask
        crop.zPosition = 1
        crop.addChild(glintNode)
        node.addChild(crop)
        return node
    }

    /// 照り 1 つぶんの形。田んぼは水面の細い線、干潟は濡れた泥の丸い光沢＋泡。
    private func addGlint(to path: CGMutablePath, at x: Double, groundY: Double, paddy: Bool) {
        if paddy {
            path.addRect(CGRect(x: x, y: groundY - 1.3, width: 4.2, height: 0.5))
            path.addRect(CGRect(x: x + 2.0, y: groundY - 2.6, width: 2.8, height: 0.45))
        } else {
            path.addEllipse(in: CGRect(x: x, y: groundY - 1.5, width: 4.0, height: 0.9))
            path.addEllipse(in: CGRect(x: x + 2.4, y: groundY - 3.0, width: 1.2, height: 1.2))
        }
    }

    private func addBand(to node: SKNode, color: UInt32, x: Double, y: Double, width: Double, height: Double) {
        let band = SKSpriteNode(color: RunnerPalette.color(color), size: CGSize(width: width, height: height))
        band.anchorPoint = .zero
        band.position = CGPoint(x: x, y: y)
        node.addChild(band)
    }

    /// 右へ流れる山形の矢印（`makeBoostFloor` と同じ作り）。帯 `bottom`〜`bottom + height` の内側に
    /// 収め、1 本のパスをマスクで切って 1 周期ぶん流す。
    private func addFlowingChevrons(to node: SKNode, length: Double, bottom: Double, height: Double, color: UInt32) {
        let spacing: Double = 6
        let chevronWidth: Double = 3.2
        let inset: Double = 0.9
        let top = bottom + height
        let path = CGMutablePath()
        let count = Int(length / spacing) + 2
        for i in 0..<count {
            let x = Double(i) * spacing
            path.move(to: CGPoint(x: x, y: bottom + inset))
            path.addLine(to: CGPoint(x: x + chevronWidth * 0.55, y: bottom + inset))
            path.addLine(to: CGPoint(x: x + chevronWidth, y: bottom + height / 2))
            path.addLine(to: CGPoint(x: x + chevronWidth * 0.55, y: top - inset))
            path.addLine(to: CGPoint(x: x, y: top - inset))
            path.addLine(to: CGPoint(x: x + chevronWidth * 0.45, y: bottom + height / 2))
            path.closeSubpath()
        }
        let chevrons = SKShapeNode(path: path)
        chevrons.fillColor = RunnerPalette.color(color)
        chevrons.strokeColor = .clear
        chevrons.position = CGPoint(x: -spacing, y: 0)
        chevrons.run(.repeatForever(.sequence([
            .moveBy(x: spacing, y: 0, duration: 0.35),
            .moveBy(x: -spacing, y: 0, duration: 0),
        ])), withKey: Self.loopActionKey)
        let crop = SKCropNode()
        let mask = SKSpriteNode(color: .white, size: CGSize(width: length, height: height))
        mask.anchorPoint = .zero
        mask.position = CGPoint(x: 0, y: bottom)
        crop.maskNode = mask
        crop.zPosition = 2
        crop.addChild(chevrons)
        node.addChild(crop)
    }
}
