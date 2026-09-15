import Core
import Foundation
import SpriteKit

extension RunnerScene {
    /// 動く障害（#796 飛び立つ鳥・#800 犬・#801 イノシシ）のノード一式。
    ///
    /// 位置は毎フレーム `RunnerHazard.frame(atRunnerDistance:)` から写す（`syncMovingHazards`）。
    /// ここには状態遷移のルールは無く、**止まっているか・動いているか**を `frame.advance` と
    /// 距離から読んで、部品のアニメーションを止める・回すだけ。
    final class MovingHazardView {
        enum State: Equatable {
            /// まだ動き出していない（止まった鳥）。
            case waiting
            /// 飛び立つ前の羽ばたき（鳥だけ）。
            case fluttering
            /// 動いている。
            case moving
            /// 動き終えて止まっている（岩で止まったイノシシ）。
            case stopped
        }

        let hazard: RunnerHazard
        let node: SKNode
        /// 地面に敷く影（鳥）。体が上がっても地面に残すので、`sync` が高さのぶん下げる。
        let shadow: SKNode?
        /// 影の、帯の床から見た y（`RunnerBirdArt.shadowCenter.y`）。
        let shadowBaseY: Double
        /// 動いているあいだだけ回す部品（翼・浮遊・脚）。止まっているあいだは `isPaused`。
        let animated: [SKNode]
        /// 動いているあいだだけ見せる部品（イノシシの土煙）。
        let movingOnly: SKNode?
        /// 歩きのコマを貼るスプライト（犬・イノシシ・#975）。鳥は図形の組み立てなので nil。
        let walkSprite: SKSpriteNode?
        /// 歩きのコマのテクスチャ（`RunnerPixelArt.WalkFrame` の `rawValue` 順）。
        let walkTextures: [SKTexture]
        /// 1 歩の距離（`RunnerPixelArt.dogWalkStride` / `boarWalkStride`）。
        let walkStride: Double
        var state: State?
        /// いま貼っている歩きのコマ。同じコマの貼り直しを省く控え（走者の `renderedRiderFrame` と同じ）。
        private var renderedWalkFrame: RunnerPixelArt.WalkFrame?

        init(
            hazard: RunnerHazard, node: SKNode, shadow: SKNode? = nil, shadowBaseY: Double = 0,
            animated: [SKNode], movingOnly: SKNode? = nil,
            walkSprite: SKSpriteNode? = nil, walkTextures: [SKTexture] = [], walkStride: Double = 1
        ) {
            self.hazard = hazard
            self.node = node
            self.shadow = shadow
            self.shadowBaseY = shadowBaseY
            self.animated = animated
            self.movingOnly = movingOnly
            self.walkSprite = walkSprite
            self.walkTextures = walkTextures
            self.walkStride = walkStride
        }

        /// 歩きのコマを、自分が進んだ距離に合わせて貼り替える（`RunnerPixelArt.walkFrame`）。
        /// 止まっているあいだは距離が増えないので、コマも自然に止まる（岩で止まったイノシシ）。
        func applyWalkFrame(travel: Double) {
            guard let walkSprite else { return }
            let frame = RunnerPixelArt.walkFrame(travel: travel, stride: walkStride)
            guard frame != renderedWalkFrame, walkTextures.indices.contains(frame.rawValue) else { return }
            renderedWalkFrame = frame
            walkSprite.texture = walkTextures[frame.rawValue]
        }

        /// 状態に合わせて部品を止める・回す。変わったフレームだけ触る（毎フレーム
        /// `isPaused` を書き直しても壊れはしないが、意図が読めるように）。
        func apply(_ next: State) {
            guard next != state else { return }
            state = next
            for part in animated {
                part.isPaused = next == .waiting || next == .stopped
                // 羽ばたきの予備動作は飛んでいるときより速く小刻みに。
                part.speed = next == .fluttering ? 2.5 : 1
            }
            movingOnly?.isHidden = next != .moving
        }
    }

    /// 鳥（`RunnerHazardKind.bird`）。「棒と穴しかない」というQAを受けて追加した敵の1つ
    /// （会長QA「鳥とか右から車が来るとか要素はいる」）。丸1つ+矩形2枚 →「とまった小鳥」→
    /// 宙に浮いて飛ぶ鳥（#671）と直してきて、#796 で**地面に止まっていて近づくと飛び立つ鳥**になった。
    /// 絵は #671 の飛ぶ鳥（`RunnerBirdArt`）をそのまま流用し、止まっているあいだは翼と浮遊を
    /// 止め、飛び立つ直前に速く羽ばたく予備動作を入れる（`MovingHazardView.apply`）。
    /// 翼・尾・くちばしのパスは既存のゴール旗（`addGoalMarker`）と同じ技法（#494 の
    /// 権利チェックの要点は特定作品の意匠に寄せないことで、パス自体は許容されている）。
    /// 当たり判定は `RunnerField` が `RunnerHazard.frame(atRunnerDistance:)` の**帯**で見ており、
    /// 絵はその帯の床に合わせて置く（`syncMovingHazards` が毎フレーム帯の位置へ動かす）。
    ///
    /// **横は絵が矩形から導かれ、縦は帯が絵から導かれる**（#609 / #671 会長決裁 2026-09-12）。
    /// かつてはここに座標を直書きしており、「絵は矩形の内側に収まる寸法で組む」と書いていた
    /// にもかかわらず、実際にはくちばし・尾羽・翼が外へ出て**絵の幅が矩形の 1.5 倍**あった。
    /// 今はくちばしの先端・尾羽の先端・翼の振り切った先端が**絵の箱**の縁にちょうど一致し、
    /// 帯の床に絵の底が一致する。絵の箱は当たり判定を `RunnerBirdArt.visualScale`（2.5）倍に
    /// 広げて中央を揃えたもの（#943・会長QA 2026-09-15「鳥が小さすぎて見えない」）で、絵は
    /// 前後と上へ張り出す——**当たり判定が絵から出ることは無い**（張り出しは走者に甘い側だけ）。
    /// 当たり判定の帯は倍率 1 の絵から導いたままなので、遊びは変わらない。この関係は
    /// `BirdArtTests` が寸法の計算で確かめるので、パーツを動かすとテストが落ちる。
    ///
    /// **座標・大きさをここに直書きしないこと。** この関数は `art` が持つ値をそのまま
    /// 使うだけにしてあり、直書きしたパーツは `RunnerBirdArt` の測定（= `BirdArtTests`）の
    /// 網から外れる。パーツを増やすときは `RunnerBirdArt` に足し、`discs` / `fixedParts` /
    /// `rotatingParts` のいずれかに登録してから使う。
    func addBird(_ hazard: RunnerHazard) -> MovingHazardView {
        // 箱は当たり判定の**帯**（#671）。原点を帯の床に置く。影は地面に敷きたいので、
        // 帯が上がるぶんだけ `syncMovingHazards` が影を下げる（`groundDrop` は 0 で組む）。
        //
        // 帯の高さは渡さない——**帯の厚みのほうが絵に合わせて決まる**（会長決裁 2026-09-12。
        // `RunnerHazardKind.birdBandHeight` が `art.bandHeight` から導出する）。
        // 見た目の倍率（#943）は `RunnerBirdArt` の既定値に任せる。座標系の約束（x=0 が帯の
        // 後端・y=0 が帯の床）は倍率で変わらないので、ここは値を写すだけでよい。
        let art = RunnerBirdArt(width: hazard.length, groundDrop: 0)
        // 色は世界ごと（`RunnerWorld.creatures`・#929）。胴・翼・尾羽・くちばしには暗い縁取りを引く
        // （腹・目・足は差し色なので引かない）。縁取りは輪郭の上に中心線で描かれ、当たり判定・
        // `RunnerBirdArt` の張り出し（`BirdArtTests`）には関わらない。
        let colors = world.creatures
        let node = SKNode()
        // 走者は左から近づくので、頭・くちばしは**走者側（-x）**を向かせる。`RunnerBirdArt` は
        // +x 側を頭にして組んであるので、丸ごと左右反転させるだけで済む——ただし `xScale = -1` は
        // 自分のローカル原点を軸に反転するので、そのままだと絵が当たり判定の外（帯の左）へ
        // はみ出す。原点を帯の右端に置いて帳尻を合わせる（`syncMovingHazards` も `frame.end` に置く）。
        node.position = CGPoint(x: hazard.end, y: Metrics.groundY + hazard.bottom)
        node.xScale = -1

        // 地面に落ちる影。体との間に空いたすき間が「飛んでいる」ことの一番の手がかり。
        // 影は浮遊に合わせて動かさない（`bobber` の外に置く）——地面側は止まっている
        // ほうが、上下しているのが鳥のほうだと分かる。
        let shadow = SKShapeNode(ellipseOf: art.shadowSize)
        shadow.fillColor = RunnerPalette.color(RunnerPalette.pitVoid)
        shadow.strokeColor = .clear
        shadow.alpha = 0.4
        shadow.position = art.shadowCenter
        node.addChild(shadow)

        // 浮遊はこの入れ物ごと上下させる（各パーツの座標は静止時のまま書ける）。
        // 振れ幅は `art.bobAmplitude` に織り込み済みで、翼の振り上げを足しても箱をはみ出さない。
        let bobber = SKNode()
        node.addChild(bobber)
        let bob = SKAction.moveBy(x: 0, y: art.bobAmplitude, duration: 0.7)
        bob.timingMode = .easeInEaseOut
        bobber.run(.repeatForever(.sequence([bob, bob.reversed()])))

        // 尾羽（後方＝-x 側）。2枚ずらして重ね、飛行姿勢に合わせて斜め上へ流す。
        // 長いほうの先端が当たり判定の後端にちょうど届く長さ（`RunnerBirdArt` が導出する）。
        for (index, spec) in art.tails.enumerated() {
            let tailPath = CGMutablePath()
            tailPath.addLines(between: spec.points)
            tailPath.closeSubpath()
            let tail = SKShapeNode(path: tailPath)
            tail.fillColor = RunnerPalette.color(index == 0 ? colors.birdWingFar : colors.birdBody)
            outline(tail)
            tail.position = spec.anchor
            bobber.addChild(tail)
        }

        // 翼。肩を軸に回すので、パスは肩（原点）から後方へ伸びる形で書く。
        // 手前・奥の2枚を逆位相で大きく振り、横からでも「羽ばたいている」と読めるようにする。
        // 止まっているあいだは `MovingHazardView.apply` が回転を止める（畳んだ姿勢＝振り下ろした端）。
        var wings: [SKNode] = []
        func addWing(
            _ spec: RunnerBirdArt.RotatingPart, color: UInt32, z: CGFloat, startsLow: Bool
        ) {
            let wingPath = CGMutablePath()
            wingPath.addLines(between: spec.points)
            wingPath.closeSubpath()
            let wing = SKShapeNode(path: wingPath)
            wing.fillColor = RunnerPalette.color(color)
            outline(wing)
            wing.position = spec.pivot
            wing.zPosition = z
            // 羽ばたきは `spec.rotation` の両端を往復する。ここを外れる角度で振ると、
            // `RunnerBirdArt` が測った張り出しより絵が外へ出る。手前と奥で始点を
            // 逆の端に取り、2枚が逆位相で振れるようにする。
            let span = spec.rotation.upperBound - spec.rotation.lowerBound
            wing.zRotation = startsLow ? spec.rotation.lowerBound : spec.rotation.upperBound
            let flap = SKAction.rotate(byAngle: startsLow ? span : -span, duration: 0.24)
            flap.timingMode = .easeInEaseOut
            wing.run(.repeatForever(.sequence([flap, flap.reversed()])))
            bobber.addChild(wing)
            wings.append(wing)
        }

        func addDisc(_ disc: RunnerBirdArt.Disc, color: UInt32, outlined: Bool = false) {
            let node = SKShapeNode(circleOfRadius: disc.radius)
            node.fillColor = RunnerPalette.color(color)
            if outlined { outline(node) } else { node.strokeColor = .clear }
            node.position = disc.center
            bobber.addChild(node)
        }

        // 奥の翼（胴の向こう側）。濃色+背面に置き、手前の翼と逆位相で振る。
        addWing(art.farWing, color: colors.birdWingFar, z: -1, startsLow: true)

        // 胴体（大きい丸）。頭は別の丸を上前方に重ね、ひとつながりの丸いシルエットにする。
        // 腹は単色の玉に見えないための明るい差し色。
        addDisc(art.bodyDisc, color: colors.birdBody, outlined: true)
        addDisc(art.headDisc, color: colors.birdBody, outlined: true)
        addDisc(art.belly, color: colors.birdBelly)

        // 畳んだ足。飛行中の鳥は足を体へ引き込むので、ぶら下げず腹の後ろ寄りに
        // 小さく畳んで添える（接地時代の「立つ2本足」の置き換え）。
        let foot = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.birdBeak),
                                size: art.footSize)
        foot.position = art.foot.pivot
        foot.zRotation = art.foot.rotation.lowerBound
        foot.zPosition = 1
        bobber.addChild(foot)

        // 手前の翼。奥の翼と逆位相・大振り。
        addWing(art.nearWing, color: colors.birdWing, z: 3, startsLow: false)

        // くちばし（進行方向側の三角）。先端が当たり判定の走者側の端にちょうど届く長さ。
        let beakPath = CGMutablePath()
        beakPath.addLines(between: art.beak.points)
        beakPath.closeSubpath()
        let beak = SKShapeNode(path: beakPath)
        beak.fillColor = RunnerPalette.color(RunnerPalette.birdBeak)
        outline(beak)
        beak.position = art.beak.anchor
        bobber.addChild(beak)

        // 目。白目の上に、進行方向（走者側）へ寄せた黒目を重ねる
        // （暗緑に暗色の点では見えない、の教訓）。
        addDisc(art.eyeWhite, color: colors.birdBelly)
        addDisc(art.pupil, color: RunnerPalette.birdEye)

        courseLayer.addChild(node)
        return MovingHazardView(
            hazard: hazard, node: node, shadow: shadow, shadowBaseY: Double(art.shadowCenter.y),
            animated: wings + [bobber]
        )
    }

    /// 犬（`RunnerHazardKind.dog`・#800 → #955 → #975）。画面の右（前方）から走者の方へ**左向きに**
    /// トコトコ歩いて来てすれ違う。絵は走者・たこ焼きと同じドット絵（`RunnerPixelArt.dogWalk0Rows` /
    /// `dogWalk1Rows`・30×21 ドット・左向きに描いてあるので反転しない）。#943 までの図形の組み立て
    /// （楕円・パス＋脚の振り子）は「猫に見える・脚が長い」（会長 QA 2026-09-15）で #975 で捨てた。
    ///
    /// 1 ドットは走者と同じ単位（`riderPlacement.unit` ≒ 0.33）で、絵は幅 ≒ 10 × 高さ ≒ 7 単位。
    /// 当たり判定（`RunnerField` が見る `frame(atRunnerDistance:)` の矩形 1 タイル × 高さ 5）は
    /// 変えず、絵の**底の中央**を当たり判定の底の中央に合わせる（前後に等しく張り出す。張り出しは
    /// 「触れて見えるのに当たらない」走者に甘い側だけ・#943）。原点は当たり判定の左下で、
    /// `syncMovingHazards` が `frame.start` に置く。歩きの 2 コマは進んだ距離で交互
    /// （`MovingHazardView.applyWalkFrame`）。立ち止まって吠える挙動は #944 で無くなったので吹き出しは持たない。
    func addDog(_ hazard: RunnerHazard) -> MovingHazardView {
        let node = SKNode()
        node.position = CGPoint(x: hazard.start, y: Metrics.groundY)
        let textures = dogTextures[world] ?? []
        let (sprite, w, _) = addWalkSprite(
            to: node, rows: RunnerPixelArt.dogWalk0Rows, textures: textures,
            anchor: CGPoint(x: 0.5, y: 0), x: hazard.length / 2
        )
        addGroundShadow(to: node, centerX: hazard.length / 2, width: w * 0.9)
        courseLayer.addChild(node)
        return MovingHazardView(
            hazard: hazard, node: node, animated: [],
            walkSprite: sprite, walkTextures: textures, walkStride: RunnerPixelArt.dogWalkStride
        )
    }

    /// イノシシ（`RunnerHazardKind.boar`・#801 → #975）。右から左へ突進してくるので、頭は左向き。
    /// 絵はドット絵（`RunnerPixelArt.boarWalk0Rows` / `boarWalk1Rows`・33×23 ドット）で、幅 ≒ 11 ×
    /// 高さ ≒ 7.7 単位。当たり判定（1 タイル × 高さ 5）は変えない。
    ///
    /// **鼻先（絵の左端の列）を当たり判定の左端に合わせ、張り出しはすべて後ろ（右）**——岩に
    /// ぶつかると当たり判定の左端を岩の右端に密着させて止まる（`RunnerHazard.stopAt` = 岩の
    /// `end`）ので、中央合わせだと頭が岩にめり込んで見える（#943 の `boarSnout` と同じ約束。
    /// `RunnerPixelArtTests` が鼻先＝列 0 を固定）。走者が出会う側（頭）は見た目と当たり判定が一致する。
    ///
    /// 走っているあいだは後ろ脚の足元（`RunnerPixelArt.boarRearFootX`）に土煙を立てる。岩で止まると
    /// コマと土煙が止まり、低い岩と同じ置物として岩の右側に並ぶ。
    func addBoar(_ hazard: RunnerHazard) -> MovingHazardView {
        let node = SKNode()
        node.position = CGPoint(x: hazard.start, y: Metrics.groundY)
        let textures = boarTextures[world] ?? []
        let (sprite, w, h) = addWalkSprite(
            to: node, rows: RunnerPixelArt.boarWalk0Rows, textures: textures,
            anchor: CGPoint(x: 0, y: 0), x: 0
        )
        addGroundShadow(to: node, centerX: w / 2, width: w * 0.95)

        // 土煙。**後ろ脚の足元（地面の高さ）**に立て、走っているあいだだけ見せて膨らんで消えるを
        // 繰り返す。位置は絵の後ろ脚の列から導く（#943: かつては箱の外の後方・地面より上に置いて
        // いて「地面のよくわからんところからおならみたいなのが出る」と会長QAで見えた）。本体の
        // 右（後ろ）にぶら下がる構造上、右から入ってくる本体より土煙が先に画面へ出ることはなく、
        // 本体が画面内にいるときだけ見える。
        let dust = SKNode()
        let rearFoot = RunnerPixelArt.boarRearFootX * Self.riderPlacement.unit
        for (index, spec) in [(0.0, 0.05, 0.14), (0.10, 0.12, 0.10)].enumerated() {
            let puff = SKShapeNode(circleOfRadius: h * spec.2)
            puff.fillColor = RunnerPalette.color(RunnerPalette.cloud)
            puff.strokeColor = .clear
            puff.alpha = 0.6
            puff.position = CGPoint(x: rearFoot + h * spec.0, y: h * spec.1)
            puff.zPosition = -1
            let grow = SKAction.group([.scale(to: 1.6, duration: 0.3), .fadeAlpha(to: 0, duration: 0.3)])
            let reset = SKAction.group([.scale(to: 0.6, duration: 0), .fadeAlpha(to: 0.6, duration: 0)])
            puff.run(.repeatForever(.sequence([.wait(forDuration: 0.1 * Double(index)), grow, reset])))
            dust.addChild(puff)
        }
        dust.isHidden = true
        node.addChild(dust)

        courseLayer.addChild(node)
        return MovingHazardView(
            hazard: hazard, node: node, animated: [], movingOnly: dust,
            walkSprite: sprite, walkTextures: textures, walkStride: RunnerPixelArt.boarWalkStride
        )
    }

    /// 動物の歩きのコマを貼るスプライトを `node` に足す（犬・イノシシ共通）。1 ドットは走者と同じ
    /// 単位（`riderPlacement.unit`）で、`rows` は寸法を測るためだけに使う（全コマ同じ格子・
    /// `RunnerPixelArtTests` が固定）。`anchor` と `x` で絵の底のどこを原点に合わせるかを選ぶ。
    /// 戻り値はスプライトと、絵の幅・高さ（ワールド単位）。
    private func addWalkSprite(
        to node: SKNode, rows: [String], textures: [SKTexture], anchor: CGPoint, x: Double
    ) -> (sprite: SKSpriteNode, w: Double, h: Double) {
        let unit = Self.riderPlacement.unit
        let w = Double(rows.first?.count ?? 0) * unit
        let h = Double(rows.count) * unit
        let sprite = SKSpriteNode(texture: textures.first)
        sprite.anchorPoint = anchor
        sprite.size = CGSize(width: w, height: h)
        sprite.position = CGPoint(x: x, y: 0)
        sprite.zPosition = 1
        node.addChild(sprite)
        return (sprite, w, h)
    }

    /// 地面に敷く薄い影（犬・イノシシ）。絵の下に置き、動物が地面に立っていることの手がかりにする。
    private func addGroundShadow(to node: SKNode, centerX: Double, width: Double) {
        let shadow = SKShapeNode(ellipseOf: CGSize(width: width, height: 0.5))
        shadow.fillColor = RunnerPalette.color(RunnerPalette.pitVoid)
        shadow.strokeColor = .clear
        shadow.alpha = 0.35
        shadow.position = CGPoint(x: centerX, y: 0.25)
        node.addChild(shadow)
    }

    /// 動く障害を、いまの当たり判定の位置へ置き直し、状態に合わせて部品を止める・回す（#796）。
    ///
    /// **位置はルール層の `frame` をそのまま写す**（描画側で独自に動かさない）。当たり判定と
    /// 絵がズレる余地を作らないため。
    func syncMovingHazards(_ field: RunnerField) {
        for view in movingHazards {
            let hazard = view.hazard
            guard let frame = hazard.frame(atRunnerDistance: field.distance) else {
                view.node.isHidden = true
                continue
            }
            view.node.isHidden = false
            // 現れた瞬間の予告の土煙は立てない。イノシシの突進（#801）の予告は**手応え（ドドド）だけ**
            // （Model が鳴らす）。かつては画面の右端の地面に土煙を立てていたが、イノシシはまだ 148 先
            // （画面は 74 先まで）で本体が見えず、「地面のよくわからんところからおならみたいなのが
            // 出る」と会長QAで指摘された（#943・2026-09-15）。土煙はイノシシの後ろ脚の足元に
            // 付けてあり（`addBoar`）、本体と一緒に画面へ入ってくる。
            // 犬（#955）は予告なしに画面の右の外に現れて歩いて入って来るだけ。土煙も鳴らさない。
            switch hazard.kind {
            case .bird:
                // 原点は帯の右端（左右反転しているため）。影は帯が上がっても地面に残す。
                view.node.position = CGPoint(x: frame.end, y: Metrics.groundY + frame.bottom)
                view.shadow?.position.y = CGFloat(view.shadowBaseY - frame.bottom)
                let state: MovingHazardView.State
                if frame.advance > 0 {
                    state = .moving
                } else if field.distance >= hazard.birdTakeoffDistance - RunnerRules.birdFlutterDistance {
                    state = .fluttering
                } else {
                    state = .waiting
                }
                view.apply(state)
            case .dog:
                // 原点は当たり判定の左下（`addDog`）。現れてから画面の左へ消えるまで歩き続ける
                // （#955）。歩きのコマは出現点から自分が歩いた距離で刻む。
                view.node.position = CGPoint(x: frame.start, y: Metrics.groundY)
                view.apply(.moving)
                view.applyWalkFrame(travel: hazard.dogSpawn - frame.start)
            case .boar:
                // 岩で止まると `frame.start` が動かなくなるので、コマもそこで止まる。
                view.node.position = CGPoint(x: frame.start, y: Metrics.groundY)
                view.apply(frame.advance < 0 ? .moving : .stopped)
                view.applyWalkFrame(travel: hazard.boarSpawn - frame.start)
            case .pit, .lowBlock, .tallBlock:
                break
            }
        }
    }
}
