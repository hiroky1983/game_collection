import Core
import Foundation
import SpriteKit

extension RunnerScene {
    /// 地面・穴・障害物・ゴールをまとめて作り直す。
    func rebuildCourse() {
        courseLayer.removeAllChildren()
        let stage = model.field.stage
        // 世界はステージ番号で決まる（#703）。変わったときだけ背景を作り直す。
        // エンドレス（#675・`number == 0`）は朝の下町で走る。距離で世界を変えると、走行中に配色を
        // 差し替える `applyWorld` の組み直し（雲・丘・部品の作り直し）でコマ落ちしうるので固定。
        let nextWorld = stage.number == 0 ? RunnerWorld.morning : RunnerWorld.world(forStage: stage.number)
        if renderedWorld != nextWorld { applyWorld(nextWorld) }
        renderOrigin = 0

        if model.field.track != nil {
            // エンドレス（#1086）: 区画は走りながら `syncEndlessCourse` が枠に合わせて置く。
            // ここでは部品の置き場を用意するだけ（ゴールもチェックポイントも無い）。
            buildEndlessCourse()
            movingHazards = []
            pickupNodes = []
        } else {
            buildStageCourse(stage)
        }
        removedPickupIndices = []
        renderedJustLandingCount = 0
        isBlinkingInvincible = false
        renderedGeneration = model.runGeneration
        // 新しい走行の頭（もう一度・はじめから等）。前回の落下演出が沈める・フェードして
        // 終わった見た目のままだと、次の挑戦の走者が透けた/縮んだ状態で始まってしまう。
        player.removeAllActions()
        player.alpha = 1
        player.xScale = 1
        player.yScale = 1
        // 漕ぐ位相も走行の頭で 0 に戻す（#701）。コマは半回転ごとの二値なので、前の走行の位相を
        // 持ち越すと「もう一度」の最初のフレームだけ左ペダル前（`ride1`）で走り出しうる。
        // 距離の控えも消して、次の反映で「それまでに進んだ距離」をまとめて足し直す
        // （チェックポイント再開・撮影は接地距離だけでコマが決まる）。
        pedalPhase = 0
        lastRenderedDistance = nil
    }

    /// ステージ制のコースを丸ごと組む（`rebuildCourse` から呼ぶ）。
    private func buildStageCourse(_ stage: RunnerStage) {
        // 地面は「穴でないところ」を並べて描く。穴の場所には何も置かないので、
        // そこが空いていることが見た目でも当たり判定でも同じ意味になる。
        // スタートの手前（x < 0）にも道路を敷く。空けたままだと開始時の画面左が崖に見える
        // （会長 QA 2026-09-14「断崖絶壁から走り出す」）。
        var x: Double = -Metrics.width
        for pit in stage.hazards where pit.kind == .pit {
            if pit.start > x { addGround(from: x, to: pit.start) }
            addPitVoid(pit)
            addPitEdgeMarkers(pit)
            x = pit.end
        }
        if x < stage.length { addGround(from: x, to: stage.length + Metrics.width) }

        // スピードアップ床は地面の**上に重ねて**塗る（地面を作り直すのではなく、
        // 同じ路面の色と模様だけを差し替える）。地面より後に足すことで手前に来る。
        for floor in stage.boostFloors { courseLayer.addChild(makeBoostFloor(floor)) }
        // 沈む床（#1089）も同じく地面の上に重ねる。走者より**奥**（`zPosition` は既定の 0 のまま）
        // なので、沈んだ走者は水面の手前に描かれる——腰まで浸かって見せるのは走者ノードを
        // 下げること（`RunnerField.sinkDepth`）だけで足りる。
        for floor in stage.sinkFloors { courseLayer.addChild(makeSinkFloor(floor)) }

        movingHazards = []
        for hazard in stage.hazards where hazard.kind != .pit {
            switch hazard.kind {
            case .bird:                    movingHazards.append(addBird(hazard))
            case .dog:                     movingHazards.append(addDog(hazard))
            case .boar:                    movingHazards.append(addBoar(hazard))
            // 突き上げ（#1010）は位置は動かないが**伸びた高さが距離で決まる**ので、毎フレーム
            // `frame` を写す仲間（`movingHazards`）に入れる。
            case .shoot:                   movingHazards.append(addShoot(hazard))
            case .lowBlock, .tallBlock:    courseLayer.addChild(makeBlock(hazard))
            case .pit:                     break
            }
        }

        for platform in stage.platforms {
            courseLayer.addChild(makePlatform(platform))
        }

        pickupNodes = stage.pickups.map { pickup in
            switch pickup.kind {
            case .speed:      return addPickup(pickup)
            case .invincible: return addTakoyaki(pickup)
            }
        }

        addCheckpointMarker(at: stage.checkpoint, percent: stage.checkpointPercent)
        addGoalMarker(at: stage.length)
    }

    /// 乗れる台座（#674）。工事の足場に架かった歩板——街の中の「高い場所」。
    ///
    /// 意匠は「丸と長方形＋パス」の規約（#494 の権利チェック）の内側で、**上面がいちばん明るく、
    /// 骨組みがその下に沈む**構成にしてある。台座は乗るものなので、遊ぶ人が最初に読み取るべきは
    /// 「どこに足が着くか」——岩（越えるもの）とは逆に、上端の床板を主役にする。
    ///
    /// 左端の面には穴の縁と同じ安全色の帯（`pitEdge`）を立てる。**正面から突っ込めば
    /// 高い障害物と同じくミス**（`RunnerField.isHittingPlatformFace`）で、
    /// このゲームで黄色はすでに「縁に気をつけろ」の意味を持っているので色を増やさずに済む。
    ///
    /// 当たり判定は `RunnerField` が `platform.start`〜`.end`／上面 `platform.top` で見ており、
    /// この見た目とは独立している——床板の上端をちょうど `top` に合わせてあるだけ。
    ///
    /// 作ったノードは左端 `platform.start` に置いて返す（コース層へ足すのは呼び出し側。エンドレスは
    /// 同じ長さの台座を使い回す・#1086）。
    func makePlatform(_ platform: RunnerPlatform) -> SKNode {
        // 里山・港町の着せ替え（#1009）。足場の描画はそのまま残し、別の物はここで分岐する。
        switch world.dressing.platform {
        case .scaffold:   break
        case .strawStack: return makeStrawStack(platform)
        case .crateStack: return makeCrateStack(platform)
        }
        let node = SKNode()
        node.position = CGPoint(x: platform.start, y: Metrics.groundY)
        let w = platform.length, top = platform.top

        // 床板（歩く面）。上端を当たり判定の上面にぴったり合わせる。
        let deckHeight = 1.6
        let deck = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.platformDeck),
            size: CGSize(width: w, height: deckHeight)
        )
        deck.anchorPoint = .zero
        deck.position = CGPoint(x: 0, y: top - deckHeight)
        deck.zPosition = 2

        // 床板の下の影。骨組みと床板のあいだに 1 本暗い帯を挟むと、輪郭線なしでも
        // 「板が骨組みの上に載っている」段差に見える。
        let underShadow = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.platformShade),
            size: CGSize(width: w, height: 0.5)
        )
        underShadow.anchorPoint = .zero
        underShadow.position = CGPoint(x: 0, y: top - deckHeight - 0.5)
        underShadow.zPosition = 1

        // 骨組みの高さ（床板と影の下）。
        let frameTop = top - deckHeight - 0.5

        // 横に通す単管（中段の水平材）。
        let rail = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.platformFrame),
            size: CGSize(width: w, height: 0.7)
        )
        rail.anchorPoint = .zero
        rail.position = CGPoint(x: 0, y: frameTop * 0.45)
        node.addChild(rail)

        // 支柱と筋交い。等間隔に立てるだけだと縞模様に見えるので、区間ごとに斜材を 1 本渡す。
        let postSpacing = 12.0
        let postWidth = 1.1
        let posts = max(2, Int((w / postSpacing).rounded()) + 1)
        for i in 0..<posts {
            let x = w * Double(i) / Double(posts - 1) - (i == posts - 1 ? postWidth : 0)
            let post = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.platformFrame),
                size: CGSize(width: postWidth, height: frameTop)
            )
            post.anchorPoint = .zero
            post.position = CGPoint(x: x, y: 0)
            node.addChild(post)

            // 筋交い（次の支柱へ渡す斜材）。奥にある材なので骨組みより暗い色にする。
            guard i < posts - 1 else { continue }
            let nextX = w * Double(i + 1) / Double(posts - 1)
            let dx = nextX - x, dy = frameTop
            let brace = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.platformShade),
                size: CGSize(width: (dx * dx + dy * dy).squareRoot(), height: 0.5)
            )
            brace.anchorPoint = CGPoint(x: 0, y: 0.5)
            brace.position = CGPoint(x: x, y: 0)
            brace.zRotation = CGFloat(atan2(dy, dx))
            brace.zPosition = -1
            node.addChild(brace)
        }

        node.addChild(underShadow)
        node.addChild(deck)
        // 床板の縁取り。クリームの床板は朝のパステルの空・壁と明度が並ぶので、輪郭で浮かせる（#929）。
        let deckOutline = SKShapeNode(rect: CGRect(x: 0, y: top - deckHeight, width: w, height: deckHeight))
        deckOutline.fillColor = .clear
        outline(deckOutline)
        deckOutline.zPosition = 2.5
        node.addChild(deckOutline)

        // 正面（左端）の警告帯。ここに足元の高さで突っ込むとミスになる面。
        let face = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.pitEdge),
            size: CGSize(width: 0.7, height: top)
        )
        face.anchorPoint = .zero
        face.position = CGPoint(x: 0, y: 0)
        face.zPosition = 3
        node.addChild(face)

        return node
    }

    /// 障害物（岩）。丸2枚重ね→多角形1枚→矩形の積み石、と直してきたがいずれも
    /// 「何なのか分からない」というQAが続いた（会長 2026-09-10「岩のデザインはNG」）。
    /// 敗因は2つ：(1) 多角形1枚は縦横比の違う `tallBlock` に引き伸ばされて刃物のように潰れ、
    /// 積み石の矩形は角が丸く「石」の硬さが出ない、(2) 茶系の配色が地面の断面・遠景の丘に
    /// 溶けて実機ではシルエット自体が読めない。そこで**縦横比がほぼ正方形の「岩塊
    /// （ボルダー）1個」を描く部品を作り、当たり判定の縦横比から積む個数を導出する**
    /// 方式に変えた——低い障害物（4×5）は1個、高い障害物（4×9）は2個積み。岩塊は常に
    /// 自分の縦横比で描かれるので、どちらでも潰れない。色はストーングレー3階調
    /// （`rockLight`/`rockBody`/`rockDark`）。
    /// 多角形のパスは既存のゴール旗と同じ技法（#494 の権利チェックの要点は特定作品の
    /// 意匠に寄せないことで、パス自体は許容済み）。
    /// 当たり判定は `RunnerField` が `hazard.start`〜`.end`/`.height` の矩形で見ており、
    /// この見た目の変更とは独立している——中に収まる大きさで描いているだけ。
    ///
    /// 作ったノードは `hazard.start` に置いて返す（コース層へ足すのは呼び出し側・#1086）。
    func makeRock(_ hazard: RunnerHazard) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: hazard.start, y: Metrics.groundY)
        let w = hazard.length, h = hazard.height

        // 接地の陰。岩の重みで地面に沈んでいるように、幅いっぱいの平たい楕円を敷く。
        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 1.05, height: h * 0.14))
        shadow.fillColor = RunnerPalette.color(world.palette.rockDark)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: w / 2, y: 0)
        node.addChild(shadow)

        // 岩塊の個数は当たり判定の縦横比から決める（幅4×高さ5 → 1個、幅4×高さ9 → 2個）。
        // 上下 15% ずつ重ねて積み、全体の頂が当たり判定の高さ h に一致するようにする。
        let count = max(1, Int((h / w).rounded()))
        let overlap = 0.15
        let boulderHeight = h / (1 + Double(count - 1) * (1 - overlap))
        var baseY = 0.0
        for i in 0..<count {
            // 上の岩塊は幅を絞り、少し右へずらして「同じ形の複製」に見せない。
            // 左右反転で変化を付ける案は、光の向き（左上）が上下の岩塊で食い違い、
            // 段差に黒い切れ込みのような影が出たので使わない（実機確認で判明）。
            addBoulder(
                to: node,
                centerX: w / 2 + (i == 0 ? 0 : w * 0.05),
                baseY: baseY,
                width: i == 0 ? w : w * 0.78,
                height: boulderHeight
            )
            baseY += boulderHeight * (1 - overlap)
        }

        return node
    }

    /// 手前の物（岩・犬・イノシシ・鳥・たこ焼き・台座・旗）の縁取りの太さ（コースの単位）。
    /// シーンは幅 `Metrics.width`（100）を画面幅へ `aspectFit` で広げるので、iPhone（幅 390pt 前後）
    /// では 1 単位 ≒ 3.9pt、0.4 単位 ≒ 1.5pt。縁取りは輪郭の上に**中心線で**描かれるので、
    /// 外へはみ出すのはこの半分（≒ 0.75pt）だけ。当たり判定（`RunnerField`）は見た目と独立なので、
    /// 縁取りで判定は変わらない（#920 の岩から #929 で動く障害・アイテムへ広げた）。
    private static let outlineWidth: CGFloat = 0.4

    /// 塗りのある形に、いまの世界の縁取り（`RunnerWorld.outline`）を引く。
    /// 面の色だけだと背景に溶ける明るさの世界（朝のパステル）で輪郭を立てるため（#929）。
    func outline(_ shape: SKShapeNode) {
        shape.strokeColor = RunnerPalette.color(world.outline)
        shape.lineWidth = Self.outlineWidth
        shape.lineJoin = .round
    }

    /// 岩塊（ボルダー）1個。底が平らで頂がやや左に寄った角ばった多角形に、
    /// 日の当たる頂の面（明）と足元の陰の面（暗）を重ね、最後に暗い縁取り（`rockDark`）で
    /// 輪郭を締める（#920: 朝の下町など明るい世界では面の色だけだと背景に溶ける）。
    private func addBoulder(
        to node: SKNode, centerX: Double, baseY: Double,
        width: Double, height: Double
    ) {
        let boulder = SKNode()
        boulder.position = CGPoint(x: centerX, y: baseY)

        // 頂点は幅・高さそれぞれの比率で置く。岩塊は count の導出により常にほぼ正方形の
        // 縦横比で描かれるので、この比率が潰れることはない。
        func pt(_ fx: Double, _ fy: Double) -> CGPoint {
            CGPoint(x: fx * width, y: fy * height)
        }

        let bodyPath = CGMutablePath()
        bodyPath.move(to: pt(-0.48, 0))
        bodyPath.addLine(to: pt(-0.5, 0.38))
        bodyPath.addLine(to: pt(-0.28, 0.82))
        bodyPath.addLine(to: pt(-0.02, 1.0))
        bodyPath.addLine(to: pt(0.3, 0.88))
        bodyPath.addLine(to: pt(0.5, 0.42))
        bodyPath.addLine(to: pt(0.46, 0))
        bodyPath.closeSubpath()
        let body = SKShapeNode(path: bodyPath)
        body.fillColor = RunnerPalette.color(world.palette.rockBody)
        body.strokeColor = .clear
        boulder.addChild(body)

        // 日の当たる頂の面。
        let topPath = CGMutablePath()
        topPath.move(to: pt(-0.28, 0.82))
        topPath.addLine(to: pt(-0.02, 1.0))
        topPath.addLine(to: pt(0.3, 0.88))
        topPath.addLine(to: pt(0.06, 0.6))
        topPath.addLine(to: pt(-0.16, 0.56))
        topPath.closeSubpath()
        let top = SKShapeNode(path: topPath)
        top.fillColor = RunnerPalette.color(world.palette.rockLight)
        top.strokeColor = .clear
        boulder.addChild(top)

        // 足元の陰の面（光と反対側）。
        let shadePath = CGMutablePath()
        shadePath.move(to: pt(0.5, 0.42))
        shadePath.addLine(to: pt(0.46, 0))
        shadePath.addLine(to: pt(0.08, 0))
        shadePath.addLine(to: pt(0.2, 0.34))
        shadePath.closeSubpath()
        let shade = SKShapeNode(path: shadePath)
        shade.fillColor = RunnerPalette.color(world.palette.rockDark)
        shade.strokeColor = .clear
        boulder.addChild(shade)

        // 縁取り。本体と同じ輪郭を、塗り無しの線だけで**面の上に**重ねる（本体の `strokeColor` に
        // すると、頂の面・陰の面が線の内側半分を覆って輪郭が途切れる）。
        let outline = SKShapeNode(path: bodyPath)
        outline.fillColor = .clear
        outline.strokeColor = RunnerPalette.color(world.palette.rockDark)
        outline.lineWidth = Self.outlineWidth
        outline.lineJoin = .round
        outline.zPosition = 1
        boulder.addChild(outline)

        node.addChild(boulder)
    }
}
