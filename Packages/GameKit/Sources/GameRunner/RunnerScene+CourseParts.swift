import Core
import Foundation
import SpriteKit

extension RunnerScene {
    /// スピードアップアイテム。最初の実装は細い矩形2枚で稲妻を表していたが小さすぎて
    /// 「何なのかパッと見てわからない」という再QA（2026-09-10）を受け、後光（丸）の上に
    /// 稲妻を1枚のパスで大きく描き直した。稲妻は速さ・電気を連想させる定番の記号で、
    /// キャラクターが「おじさん」であることに引きずられた案（ビール等）は倫理的に
    /// 採用しないという会長判断も踏まえ、キャラクター性に依存しない記号にしてある。
    /// 取得すると `sync` がフェードアウト＋縮小で消す。戻り値は `sync` が取得済みかどうかを
    /// 追うためのノード参照。
    @discardableResult
    func addPickup(_ pickup: RunnerPickup) -> SKNode {
        let node = SKNode()
        let radius = 2.6
        node.position = CGPoint(x: pickup.start, y: Metrics.groundY + radius + 1.3)

        // 後光（丸）。
        let aura = SKShapeNode(circleOfRadius: radius)
        aura.fillColor = RunnerPalette.color(RunnerPalette.pickupAura)
        aura.strokeColor = .clear
        node.addChild(aura)

        // 稲妻（1枚の折れ線パス）。ゴール旗（`addGoalMarker`）と同じ「パスで図形を描く」
        // 作り方を踏襲し、輪郭線を付けて後光の上でも沈まないようにする。
        let boltPath = CGMutablePath()
        boltPath.move(to: CGPoint(x: 0.5, y: radius * 0.95))
        boltPath.addLine(to: CGPoint(x: -1.0, y: 0.1))
        boltPath.addLine(to: CGPoint(x: 0.1, y: 0.1))
        boltPath.addLine(to: CGPoint(x: -0.6, y: -radius * 0.95))
        boltPath.addLine(to: CGPoint(x: 1.2, y: 0))
        boltPath.addLine(to: CGPoint(x: 0.1, y: 0))
        boltPath.closeSubpath()
        let bolt = SKShapeNode(path: boltPath)
        bolt.fillColor = RunnerPalette.color(RunnerPalette.pickupBolt)
        bolt.strokeColor = RunnerPalette.color(RunnerPalette.pickupBoltOutline)
        bolt.lineWidth = 0.18
        bolt.zPosition = 1
        node.addChild(bolt)

        // 取得を誘う脈動（見た目だけ。当たり判定は `RunnerField` 側の矩形のまま）。
        let pulse = SKAction.sequence([
            .scale(to: 1.15, duration: 0.45),
            .scale(to: 1.0, duration: 0.45),
        ])
        node.run(.repeatForever(pulse))

        courseLayer.addChild(node)
        return node
    }

    /// たこ焼き（`RunnerPickupKind.invincible`・#797 → #956）。舟皿に 3 個を並べた図形は小さくて
    /// 「何か分からない」（会長 QA 2026-09-15）ので、走者と同じ SFC 級のドット絵で **1 個を大きく**
    /// 描く（`RunnerPixelArt.takoyaki`・15×18 ドット）。1 ドットは走者と同じ単位
    /// （`riderPlacement.unit` ≒ 0.33）で、高さ ≒ 6 単位＝走者の頭くらい。縁取りは絵に焼き込んである
    /// （#929 の「手前の物は縁取る」。世界ごとの `outline(_:)` は `SKSpriteNode` に掛けられない）。
    /// スピードアップ（稲妻）は「脈動」、たこ焼きは「上下にふわふわ浮く」で動きも変え、
    /// 色だけに頼らず見分けられるようにする。
    ///
    /// 原点は絵の底の中央（`anchorPoint = (0.5, 0)`。格子に余白が無いことは `RunnerPixelArtTests`
    /// が固定）。x は `pickup.start`（当たり判定の中心）、y は図形だった頃の舟皿の底と同じ高さ。
    /// 当たり判定は `RunnerField` 側の横の重なりだけで、この絵の寸法とは独立している
    /// （`addPickup` と同じ）。
    @discardableResult
    func addTakoyaki(_ pickup: RunnerPickup) -> SKNode {
        let sprite = RunnerPixelArt.takoyaki()
        let unit = Self.riderPlacement.unit
        let node = SKSpriteNode(texture: takoyakiTexture)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.size = CGSize(width: Double(sprite.width) * unit, height: Double(sprite.height) * unit)
        node.position = CGPoint(x: pickup.start, y: Metrics.groundY + 1.4)

        // ふわふわ浮く（見た目だけ。当たり判定は `RunnerField` 側の横の重なりのまま）。
        let rise = SKAction.moveBy(x: 0, y: 0.7, duration: 0.55)
        rise.timingMode = .easeInEaseOut
        let sink = SKAction.moveBy(x: 0, y: -0.7, duration: 0.55)
        sink.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([rise, sink])))

        courseLayer.addChild(node)
        return node
    }

    /// 取得済みのピックアップをフェードアウト＋縮小で消す。
    func removePickupNode(_ node: SKNode) {
        guard node.parent != nil else { return }
        // 脈動（`repeatForever`）を止めてからでないと、拡大縮小がぶつかって
        // 消える瞬間だけ縮み方が乱れる。
        node.removeAllActions()
        node.run(.sequence([
            .group([.fadeOut(withDuration: 0.25), .scale(to: 0.2, duration: 0.25)]),
            .removeFromParent(),
        ]))
    }

    /// 穴の中身（奈落）。縁の帯だけだと穴の内側が空と同じ色のままで、
    /// 「本当にここが穴なのか・幅はどれくらいか」が伝わらなかった（会長QA）。
    /// 地面と同じ矩形をそのまま塗り替えるだけなので、幅は `pit.start`〜`.end` の実寸そのもの
    /// ——当たり判定（`RunnerField.isPit`）が見ている境界と完全に一致する。
    func addPitVoid(_ pit: RunnerHazard) {
        let void = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.pitVoid),
            size: CGSize(width: pit.length, height: Metrics.groundY)
        )
        void.anchorPoint = .zero
        void.position = CGPoint(x: pit.start, y: 0)
        courseLayer.addChild(void)
    }

    /// 穴の縁の警告帯。地面と同系色の穴だけでは切れ目が分かりづらいというQAを受けて追加。
    /// 当たり判定には影響しない、純粋な見た目の追加。
    func addPitEdgeMarkers(_ pit: RunnerHazard) {
        // 黄と黒の 3 段（工事の柵）。道路の穴＝工事中の切れ目、という読みに揃える（会長 QA 2026-09-14）。
        for edgeX in [pit.start, pit.end] {
            for (i, hex) in [RunnerPalette.pitEdge, RunnerPalette.pitEdgeDark, RunnerPalette.pitEdge].enumerated() {
                let strip = SKSpriteNode(
                    color: RunnerPalette.color(hex),
                    size: CGSize(width: 0.8, height: 1.0)
                )
                strip.anchorPoint = CGPoint(x: 0.5, y: 1)
                strip.position = CGPoint(x: edgeX, y: Metrics.groundY - Double(i) * 1.0)
                courseLayer.addChild(strip)
            }
        }
    }

    /// 道路の断面（会長 QA 2026-09-14）。上からアスファルト・白い破線・縁石・路肩・地盤。
    /// 色は `RunnerWorld.road`。高さは物理（`Metrics.groundY`）に合わせ、路面の上端が地面。
    /// 破線は 1 本の `SKShapeNode` にまとめる（エンドレスは 6,400 m あるので、1 本ずつ
    /// ノードにすると数千個になる）。
    private static let roadHeight: Double = 5.0
    private static let curbHeight: Double = 1.0
    private static let shoulderHeight: Double = 4.0

    func addGround(from start: Double, to end: Double) {
        let road = world.road
        let width = end - start
        func band(_ hex: UInt32, y: Double, height: Double) {
            let node = SKSpriteNode(color: RunnerPalette.color(hex), size: CGSize(width: width, height: height))
            node.anchorPoint = .zero
            node.position = CGPoint(x: start, y: y)
            courseLayer.addChild(node)
        }
        let roadBottom = Metrics.groundY - Self.roadHeight
        let curbBottom = roadBottom - Self.curbHeight
        let shoulderBottom = curbBottom - Self.shoulderHeight
        band(road.subsoil, y: 0, height: shoulderBottom)
        band(road.shoulder, y: shoulderBottom, height: Self.shoulderHeight)
        band(road.curb, y: curbBottom, height: Self.curbHeight)
        band(road.asphalt, y: roadBottom, height: Self.roadHeight)

        // 中央の破線。長さ 4・間隔 4 で、区画の始点（64 の倍数）に位相を揃えて継ぎ目を目立たせない。
        let dashes = CGMutablePath()
        let dashLength = 4.0, dashGap = 4.0, dashHeight = 0.7
        var dx = (start / (dashLength + dashGap)).rounded(.down) * (dashLength + dashGap)
        while dx < end {
            let x0 = max(dx, start), x1 = min(dx + dashLength, end)
            if x1 > x0 {
                dashes.addRect(CGRect(x: x0, y: roadBottom + Self.roadHeight / 2 - dashHeight / 2,
                                      width: x1 - x0, height: dashHeight))
            }
            dx += dashLength + dashGap
        }
        let line = SKShapeNode(path: dashes)
        line.fillColor = RunnerPalette.color(road.line)
        line.strokeColor = .clear
        line.alpha = world == .night ? 0.75 : 0.9
        courseLayer.addChild(line)
    }

    /// スピードアップ床（#672）。**地面の路面だけを塗り替え、その上に進行方向の矢印を並べる**。
    ///
    /// 高さのある置物にしない理由は 2 つ。(1) 床は当たり判定を一切持たない
    /// （`RunnerField.isOnBoostFloor` は中心の x が区間に入っているかだけを見る）ので、
    /// 地面から生えた物として描くと岩・鳥と同じ「当たるもの」に見えてしまう。
    /// (2) 走者は床の上を走るので、走者より手前に物を置くと足元が隠れる。
    ///
    /// 矢印は丸・長方形では向きが出ないので三角のパスで描く（意匠制約 #494 は
    /// 「特定作品に寄せない」ことで、ゴール旗・稲妻と同じくパス自体は許容済み）。
    /// 色だけでなく**形**でも「前へ押される区間」だと伝わるようにしてある。
    func addBoostFloor(_ floor: RunnerBoostFloor) {
        // 路面全体（アスファルトの厚み）を加速帯の色で塗り替え、上下を暗い青で縁取る。
        // 以前は 2.2 の薄い帯に小さな三角で、走者の足元では気づけなかった（会長 QA 2026-09-14）。
        let height = Self.roadHeight
        let bottom = Metrics.groundY - height
        let surface = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.boostFloorTop),
            size: CGSize(width: floor.length, height: height)
        )
        surface.anchorPoint = .zero
        surface.position = CGPoint(x: floor.start, y: bottom)
        courseLayer.addChild(surface)
        for edgeY in [bottom, Metrics.groundY - 0.6] {
            let edge = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.boostFloorEdge),
                size: CGSize(width: floor.length, height: 0.6)
            )
            edge.anchorPoint = .zero
            edge.position = CGPoint(x: floor.start, y: edgeY)
            courseLayer.addChild(edge)
        }

        // 山形の矢印（シェブロン）を路面いっぱいの高さで並べ、右へ流して「前へ押される」ことを
        // 動きでも伝える。矢印はまとめて 1 本のパスにし、帯の内側だけ見えるようマスクで切る。
        let spacing: Double = 6
        let chevronWidth: Double = 3.2
        let inset: Double = 0.9
        let path = CGMutablePath()
        let count = Int(floor.length / spacing) + 2
        for i in 0..<count {
            let x = Double(i) * spacing
            path.move(to: CGPoint(x: x, y: bottom + inset))
            path.addLine(to: CGPoint(x: x + chevronWidth * 0.55, y: bottom + inset))
            path.addLine(to: CGPoint(x: x + chevronWidth, y: bottom + height / 2))
            path.addLine(to: CGPoint(x: x + chevronWidth * 0.55, y: Metrics.groundY - inset))
            path.addLine(to: CGPoint(x: x, y: Metrics.groundY - inset))
            path.addLine(to: CGPoint(x: x + chevronWidth * 0.45, y: bottom + height / 2))
            path.closeSubpath()
        }
        let chevrons = SKShapeNode(path: path)
        chevrons.fillColor = RunnerPalette.color(RunnerPalette.boostFloorArrow)
        chevrons.strokeColor = .clear
        chevrons.position = CGPoint(x: -spacing, y: 0)
        // 1 周期ぶん右へ流して戻す。周期パターンなので継ぎ目なく流れて見える。
        chevrons.run(.repeatForever(.sequence([
            .moveBy(x: spacing, y: 0, duration: 0.35),
            .moveBy(x: -spacing, y: 0, duration: 0),
        ])))
        let crop = SKCropNode()
        let mask = SKSpriteNode(color: .white, size: CGSize(width: floor.length, height: height))
        mask.anchorPoint = .zero
        crop.maskNode = mask
        crop.position = CGPoint(x: floor.start, y: 0)
        // マスクは crop の座標系（x = 0 が床の始点）なので、矢印パスも床の始点基準に置く。
        mask.position = CGPoint(x: 0, y: bottom)
        crop.addChild(chevrons)
        courseLayer.addChild(crop)
    }

    /// チェックポイントの目印。丸いバッジだけでは「これが何なのか分からない」というQAを受け、
    /// マラソンの距離標識のように**そのステージで実際に計算された到達率**を数字で出す板に
    /// 変えた（会長QA「50%と書かれた旗とか」——ただし実際の到達率は `checkpointPercent` の
    /// とおりステージごとに違うので、固定の "50%" ではなくその値をそのまま表示する）。
    /// 板は矩形・柱も矩形で「丸と長方形だけ」の意匠制約（#494）を保ったまま、
    /// ゴールの三角旗（`addGoalMarker`）とは形・色の両方で見分けが付く。
    /// ここより先で失敗すると、広告視聴でここから再開できる（`RunnerModel.canResumeFromCheckpoint`）。
    ///
    /// **数字はこの標識自体の意味そのもの**（盤面の説明の重複ではない）なので、
    /// 「SpriteKit の中に文字は描かない」（`RunnerAccessibility` の方針）はここでは適用しない。
    /// 読み上げは従来どおり `RunnerAccessibility.progressLabel` が進み具合として担う。
    func addCheckpointMarker(at x: Double, percent: Int) {
        let pole = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.wheel),
            size: CGSize(width: 1.4, height: 19)
        )
        pole.anchorPoint = CGPoint(x: 0.5, y: 0)
        pole.position = CGPoint(x: x, y: Metrics.groundY)
        courseLayer.addChild(pole)

        // 旗（つばめ尾型）。四角い「標識板」は道路標識に見えて「何なのか分からない」
        // という再QA（2026-09-10）を受け、ゴールの旗（`addGoalMarker`）と同じ
        // 「柱に付いた旗」という形の文法に揃えつつ、先端に三角の切れ込みを入れて
        // ゴールの単純な三角旗とは別物と分かるようにした。奥にもう1枚重ねて厚みを出す。
        // 大きさ・文字は2度直している：初版は小さすぎて実機で読めず（会長QA「旗の文字も
        // いまだに見えない」）、1.5倍版も文字が旗の左端からはみ出してポールに重なり、
        // 白抜き×水色でコントラストも足りなかった。旗をさらに広げ（幅17）、文字は
        // 切れ込みのない無地部分（x: 0〜13.5）に収まる位置・大きさで、旗より十分暗い紺
        // （`checkpointText`）に変えた（「%」の字幅が数字より広いことに注意。幅15では
        // 「51%」がまだ両端にはみ出た——実機確認で判明）。
        let flagPath = CGMutablePath()
        flagPath.move(to: CGPoint(x: 0, y: 4.6))
        flagPath.addLine(to: CGPoint(x: 17, y: 4.6))
        flagPath.addLine(to: CGPoint(x: 13.5, y: 0))
        flagPath.addLine(to: CGPoint(x: 17, y: -4.6))
        flagPath.addLine(to: CGPoint(x: 0, y: -4.6))
        flagPath.closeSubpath()

        let flagCenter = CGPoint(x: x, y: Metrics.groundY + 13.8)
        let flagShade = SKShapeNode(path: flagPath)
        flagShade.fillColor = RunnerPalette.color(RunnerPalette.checkpointShade)
        flagShade.strokeColor = .clear
        flagShade.position = CGPoint(x: flagCenter.x + 0.6, y: flagCenter.y - 0.6)
        courseLayer.addChild(flagShade)

        let flag = SKShapeNode(path: flagPath)
        flag.fillColor = RunnerPalette.color(RunnerPalette.checkpoint)
        // 旗には暗い縁取り（#929）。水色の旗は朝のパステルの空と明度が並ぶ。
        outline(flag)
        flag.position = flagCenter
        courseLayer.addChild(flag)

        // 到達率。旗の意味そのものなので大きく載せる（会長案「50%と書かれた旗とか」）。
        // 中心は切れ込みを除いた無地部分（x: 0〜13.5）の真ん中。
        let label = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        label.text = "\(percent)%"
        label.fontSize = 5.6
        label.fontColor = RunnerPalette.color(RunnerPalette.checkpointText)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: flagCenter.x + 6.75, y: flagCenter.y)
        label.zPosition = 1
        courseLayer.addChild(label)
    }

    /// ゴールの目印（旗）。細い柱だけでは「何のオブジェクトか分からない」というQAを受け、
    /// 三角の旗を足して一目でゴールと分かる形にした。
    ///
    /// 「着いた感」が薄い（#703 の要素分解）ので、旗をチェックポイントの旗と同じ寸法級まで
    /// 広げ、奥に陰の 1 枚を重ねて厚みを出し、「ゴール」と書く。**文字はこの旗の意味そのもの**
    /// なので、チェックポイントの到達率と同じく「SpriteKit の中に文字は描かない」
    /// （`RunnerAccessibility`）の例外にあたる。先端を尖らせた矢羽根型にしてあるのは、
    /// 先端に切れ込みのあるつばめ尾のチェックポイントと形で見分けるため（文字が三角の
    /// 細い先端に収まらないので、純粋な三角は捨てた）。旗は横にゆっくり伸び縮みさせて、
    /// 風にはためいて見せる（1 ノードの `SKAction` だけで、コースの他のノードには影響しない）。
    /// 到達した瞬間の音・触覚は `RunnerModel` が `feedback.notify(.success)` で鳴らす
    /// （`RunnerFeedbackCue`）。
    func addGoalMarker(at x: Double) {
        let poleHeight = 21.0
        let pole = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.wheel), size: CGSize(width: 1.4, height: poleHeight))
        pole.anchorPoint = CGPoint(x: 0.5, y: 0)
        pole.position = CGPoint(x: x, y: Metrics.groundY)
        courseLayer.addChild(pole)

        // 矢羽根型の旗。左辺を柱に付け、無地の矩形部分（x: 0〜12）の先を尖らせる。
        let flagHalfHeight = 4.4
        let flagPath = CGMutablePath()
        flagPath.move(to: CGPoint(x: 0, y: flagHalfHeight))
        flagPath.addLine(to: CGPoint(x: 12, y: flagHalfHeight))
        flagPath.addLine(to: CGPoint(x: 15.5, y: 0))
        flagPath.addLine(to: CGPoint(x: 12, y: -flagHalfHeight))
        flagPath.addLine(to: CGPoint(x: 0, y: -flagHalfHeight))
        flagPath.closeSubpath()

        // はためき。柱側（x=0）を軸に横だけ伸縮させる。旗・陰・文字をまとめて動かす。
        let flag = SKNode()
        flag.position = CGPoint(x: x + 0.7, y: Metrics.groundY + poleHeight - flagHalfHeight - 0.6)
        let wave = SKAction.sequence([
            .scaleX(to: 0.9, duration: 0.55),
            .scaleX(to: 1.0, duration: 0.55),
        ])
        wave.timingMode = .easeInEaseOut
        flag.run(.repeatForever(wave))
        courseLayer.addChild(flag)

        let shade = SKShapeNode(path: flagPath)
        shade.fillColor = RunnerPalette.color(RunnerPalette.goalShade)
        shade.strokeColor = .clear
        shade.position = CGPoint(x: 0.6, y: -0.6)
        flag.addChild(shade)

        let cloth = SKShapeNode(path: flagPath)
        cloth.fillColor = RunnerPalette.color(RunnerPalette.goal)
        // 旗には暗い縁取り（#929）。桃色の旗は朝のパステルの空・屋根と明度が並ぶ。
        outline(cloth)
        flag.addChild(cloth)

        // 「ゴール」。無地の矩形部分（x: 0〜12）の真ん中に置く（3 文字 × 3.6 ≒ 10.8 幅）。
        let label = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        label.text = "ゴール"
        label.fontSize = 3.6
        label.fontColor = RunnerPalette.color(RunnerPalette.goalText)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 6, y: 0)
        label.zPosition = 1
        flag.addChild(label)
    }
}
