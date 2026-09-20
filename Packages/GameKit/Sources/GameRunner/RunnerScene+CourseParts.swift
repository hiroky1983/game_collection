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
        node.run(.repeatForever(pulse), withKey: Self.loopActionKey)

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
        node.run(.repeatForever(.sequence([rise, sink])), withKey: Self.loopActionKey)

        courseLayer.addChild(node)
        return node
    }

    /// 部品に掛けた繰り返しの動き（脈動・浮遊・羽ばたき・土煙・床の矢印）の `SKAction` のキー（#1086）。
    ///
    /// エンドレスは部品を使い回すので、使い回す前に動きを止めて最初の姿勢へ戻し、キーから取り出した
    /// 同じ動きを掛け直す（`EndlessRenderer.Part`）。キーを付けずに掛けると取り出せず、使い回した
    /// 部品が止まったままになる。ステージ制の見た目には関わらない。
    static let loopActionKey = "loop"

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
    func addPitVoid(_ pit: RunnerHazard, into parent: SKNode? = nil) {
        // 里山・港町の着せ替え（#1009）。奈落の描画はそのまま残し、水の入った穴はここで分岐する。
        switch world.dressing.pit {
        case .construction:    break
        case .irrigationDitch: return addDitchWater(pit, into: parent ?? courseLayer)
        case .quayGap:         return addGapSea(pit, into: parent ?? courseLayer)
        }
        let void = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.pitVoid),
            size: CGSize(width: pit.length, height: Metrics.groundY)
        )
        void.anchorPoint = .zero
        void.position = CGPoint(x: pit.start, y: 0)
        (parent ?? courseLayer).addChild(void)
    }

    /// 穴の縁の警告帯。地面と同系色の穴だけでは切れ目が分かりづらいというQAを受けて追加。
    /// 当たり判定には影響しない、純粋な見た目の追加。
    func addPitEdgeMarkers(_ pit: RunnerHazard, into parent: SKNode? = nil) {
        // 里山・港町の着せ替え（#1009）。柵の描画はそのまま残し、壁・防舷材はここで分岐する。
        switch world.dressing.pit {
        case .construction:    break
        case .irrigationDitch: return addDitchWalls(pit, into: parent ?? courseLayer)
        case .quayGap:         return addQuayFenders(pit, into: parent ?? courseLayer)
        }
        // 黄と黒の 3 段（工事の柵）。道路の穴＝工事中の切れ目、という読みに揃える（会長 QA 2026-09-14）。
        for edgeX in [pit.start, pit.end] {
            for (i, hex) in [RunnerPalette.pitEdge, RunnerPalette.pitEdgeDark, RunnerPalette.pitEdge].enumerated() {
                let strip = SKSpriteNode(
                    color: RunnerPalette.color(hex),
                    size: CGSize(width: 0.8, height: 1.0)
                )
                strip.anchorPoint = CGPoint(x: 0.5, y: 1)
                strip.position = CGPoint(x: edgeX, y: Metrics.groundY - Double(i) * 1.0)
                (parent ?? courseLayer).addChild(strip)
            }
        }
    }

    /// 道路の断面（会長 QA 2026-09-14）。上からアスファルト・白い破線・縁石・路肩・地盤。
    /// 色は `RunnerWorld.road`。高さは物理（`Metrics.groundY`）に合わせ、路面の上端が地面。
    /// 破線は 1 本の `SKShapeNode` にまとめる（ステージ制は穴と穴のあいだを 1 本の地面で描くので、
    /// 1 本ずつノードにすると長い面で数百個になる）。エンドレスは区画ごとの地面を使い回す（#1086）。
    ///
    /// - Parameters:
    ///   - bandStart: 帯（アスファルト〜地盤）だけを `start` より手前から塗る x。破線の位相は `start` で
    ///     決める。エンドレスの区画ごとの地面が、隣の区画との継ぎ目に細い隙間を見せないよう重ねるのに使う。
    ///   - parent: 足す先。省略するとコース層。
    /// 路面（アスファルト）の厚み。加速床の着せ替え（`RunnerScene+Dressing`・#1009）も同じ厚みを塗り替える。
    static let roadHeight: Double = 5.0
    private static let curbHeight: Double = 1.0
    private static let shoulderHeight: Double = 4.0

    func addGround(from start: Double, to end: Double, bandStart: Double? = nil, into parent: SKNode? = nil) {
        let road = world.road
        let parent = parent ?? courseLayer
        let bandStart = min(start, bandStart ?? start)
        let width = end - bandStart
        func band(_ hex: UInt32, y: Double, height: Double) {
            let node = SKSpriteNode(color: RunnerPalette.color(hex), size: CGSize(width: width, height: height))
            node.anchorPoint = .zero
            node.position = CGPoint(x: bandStart, y: y)
            parent.addChild(node)
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
        parent.addChild(line)
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
    ///
    /// 部品は 1 つのノードにまとめ、左端 `floor.start` に置いて返す（コース層へ足すのは呼び出し側。
    /// エンドレスは同じ長さの床を使い回す・#1086）。
    func makeBoostFloor(_ floor: RunnerBoostFloor) -> SKNode {
        // 里山・港町の着せ替え（#1009）。青い加速帯の描画はそのまま残し、別の物はここで分岐する。
        switch world.dressing.boostFloor {
        case .boostBand:     break
        case .pavedFarmRoad: return makePavedFarmRoad(floor)
        case .conveyor:      return makeConveyor(floor)
        }
        // 路面全体（アスファルトの厚み）を加速帯の色で塗り替え、上下を暗い青で縁取る。
        // 以前は 2.2 の薄い帯に小さな三角で、走者の足元では気づけなかった（会長 QA 2026-09-14）。
        let node = SKNode()
        node.position = CGPoint(x: floor.start, y: 0)
        let height = Self.roadHeight
        let bottom = Metrics.groundY - height
        let surface = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.boostFloorTop),
            size: CGSize(width: floor.length, height: height)
        )
        surface.anchorPoint = .zero
        surface.position = CGPoint(x: 0, y: bottom)
        node.addChild(surface)
        for edgeY in [bottom, Metrics.groundY - 0.6] {
            let edge = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.boostFloorEdge),
                size: CGSize(width: floor.length, height: 0.6)
            )
            edge.anchorPoint = .zero
            edge.position = CGPoint(x: 0, y: edgeY)
            node.addChild(edge)
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
        ])), withKey: Self.loopActionKey)
        let crop = SKCropNode()
        let mask = SKSpriteNode(color: .white, size: CGSize(width: floor.length, height: height))
        mask.anchorPoint = .zero
        crop.maskNode = mask
        crop.position = CGPoint(x: 0, y: 0)
        // マスクは crop の座標系（x = 0 が床の始点）なので、矢印パスも床の始点基準に置く。
        mask.position = CGPoint(x: 0, y: bottom)
        crop.addChild(chevrons)
        node.addChild(crop)
        return node
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

    /// ゴールの目印（**ひらひら浮いている宝くじ**・#1092）。
    ///
    /// 会長決裁 2026-09-18 でゴールは旗から宝くじに変わった——おじさんが追いかけているのは
    /// 風に飛ばされた当たり券で、毎面のゴールはその券に**追いつきかける**場面だからである
    /// （着いた瞬間にまた飛ばされる演出が `RunnerScene.syncGoalChase`）。「ゴール」と書いた
    /// 矢羽根型の旗と、その柱は丸ごと廃止した。**チェックポイントの旗（`addCheckpointMarker`）は
    /// そのまま**で、形も色も文字の有無も別物なので取り違えない。
    ///
    /// 高さは**走者の胴の高さ**（`goalTicketY`）。跳んで取るものだと誤解させないためで、
    /// 着いたかの判定は今までどおり距離だけ（`RunnerField` の `distance >= stage.length`）——
    /// 地面を走っていても跳んでいても同じ地点でゴールになる。
    ///
    /// ゆらゆら揺れる（`SKAction`）のは「浮いている紙」だと動きで伝えるため。**Reduce Motion が
    /// オンなら揺らさない**（決裁の受け入れ条件）。到達した瞬間の音・触覚は `RunnerModel` が
    /// `feedback.notify(.success)` で鳴らす（`RunnerFeedbackCue`）。
    @discardableResult
    func addGoalMarker(at x: Double) -> SKSpriteNode {
        let sprite = RunnerPixelArt.lotteryTicket()
        let unit = Self.riderPlacement.unit
        let node = SKSpriteNode(texture: lotteryTicketTexture)
        // 浮いている物なので**絵の中心**を置き場に合わせる（底合わせのたこ焼きとは違う）。
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.size = CGSize(width: Double(sprite.width) * unit, height: Double(sprite.height) * unit)
        node.position = CGPoint(x: x, y: Self.goalTicketY)
        courseLayer.addChild(node)
        goalTicket = node
        goalTicketBase = node.position
        applyGoalTicketSway(node)
        applyGoalSparkle(to: node)
        return node
    }

    /// ゴールの宝くじを浮かべる高さ（地面からの絶対 y）。
    ///
    /// 走者の見た目の高さは `RunnerRider.visualHeight`（11.9）で、その 6 割ほど＝胴のあたりに
    /// 券の中心を置く。券の高さは 13 ドット ≒ 4.3 単位なので、下端は地面から 2 単位ほど上に
    /// 浮き、上端は走者の頭より下に収まる——**接地したまま重なる高さ**で、跳ぶ必要は無い。
    static let goalTicketY: Double = Metrics.groundY + RunnerRider.visualHeight * 0.6

    /// ゆらゆら（上下 + わずかな傾き）。Reduce Motion がオンなら掛けない（#1092）。
    func applyGoalTicketSway(_ node: SKNode) {
        node.removeAction(forKey: Self.loopActionKey)
        node.zRotation = 0
        guard !reducesMotion else { return }
        let rise = SKAction.moveBy(x: 0, y: 0.9, duration: 0.7)
        rise.timingMode = .easeInEaseOut
        let sink = SKAction.moveBy(x: 0, y: -0.9, duration: 0.7)
        sink.timingMode = .easeInEaseOut
        let tiltLeft = SKAction.rotate(toAngle: 0.10, duration: 0.7)
        tiltLeft.timingMode = .easeInEaseOut
        let tiltRight = SKAction.rotate(toAngle: -0.10, duration: 0.7)
        tiltRight.timingMode = .easeInEaseOut
        node.run(.repeatForever(.group([
            .sequence([rise, sink]),
            .sequence([tiltLeft, tiltRight]),
        ])), withKey: Self.loopActionKey)
    }

    /// 宝くじの周りで瞬く小さな光の粒（#1171）。「これが当たり券だ」という目印を強調する
    /// もので、廃止した紙吹雪（お祝い）とは別の意図——**逃げられた場面で祝うのは話と合わない**
    /// という #1092 の決裁はここでは動かない（決裁済みなのは「派手な達成の演出」で、常時の目印は別）。
    ///
    /// 券の**子ノード**にする。券本体の揺れ（`applyGoalTicketSway`）は `loopActionKey` を券自身に
    /// 掛けるため、同じキーで粒にも掛けると揺れを上書きしてしまう——粒は自分自身に別々の
    /// `loopActionKey` を持つので競合しない。子ノードなので、ゴールの演出（`syncGoalChase`）で
    /// 券が飛んで消えていくときも、位置・透明度をそのまま一緒に引き継ぐ（追加の同期コード不要）。
    ///
    /// 位置は決め打ち（乱数は使わない。撮影・QAで毎回同じ画になるように）。**Reduce Motion が
    /// オンなら点滅させず、そのまま光ったまま**にする（揺れと違って粒ごと消すと「目印が減る」
    /// だけになり、動きを止める効果に見合わないため）。
    func applyGoalSparkle(to ticket: SKSpriteNode) {
        let halfW = ticket.size.width / 2
        let halfH = ticket.size.height / 2
        // (dx, dy, radius, 点滅の位相ずれ) — 券の四隅の外側に置く。
        let specs: [(dx: CGFloat, dy: CGFloat, r: CGFloat, phase: TimeInterval)] = [
            (halfW + 0.6, halfH + 0.4, 0.55, 0.0),
            (-halfW - 0.5, halfH + 0.7, 0.4, 0.35),
            (halfW + 0.3, -halfH - 0.6, 0.4, 0.65),
            (-halfW - 0.7, -halfH - 0.3, 0.5, 0.9),
        ]
        for spec in specs {
            let sparkle = SKShapeNode(circleOfRadius: spec.r)
            sparkle.name = Self.goalSparkleNodeName
            sparkle.fillColor = RunnerPalette.color(RunnerPalette.pickupBolt)
            sparkle.strokeColor = .clear
            sparkle.zPosition = 1
            sparkle.position = CGPoint(x: spec.dx, y: spec.dy)
            ticket.addChild(sparkle)
            guard !reducesMotion else {
                sparkle.alpha = 0.9
                continue
            }
            sparkle.alpha = 0.25
            let blinkIn = SKAction.fadeAlpha(to: 1.0, duration: 0.5)
            blinkIn.timingMode = .easeInEaseOut
            let blinkOut = SKAction.fadeAlpha(to: 0.25, duration: 0.5)
            blinkOut.timingMode = .easeInEaseOut
            let loop = SKAction.repeatForever(.sequence([blinkIn, blinkOut]))
            sparkle.run(.sequence([.wait(forDuration: spec.phase), loop]), withKey: Self.loopActionKey)
        }
    }

    /// 宝くじの周りの光の粒の名前。ゴールに1つしか無い前提で数を数えるテストが目印にする。
    static let goalSparkleNodeName = "goalSparkle"
}
