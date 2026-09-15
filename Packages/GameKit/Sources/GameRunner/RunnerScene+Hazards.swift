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
        var state: State?

        init(
            hazard: RunnerHazard, node: SKNode, shadow: SKNode? = nil, shadowBaseY: Double = 0,
            animated: [SKNode], movingOnly: SKNode? = nil
        ) {
            self.hazard = hazard
            self.node = node
            self.shadow = shadow
            self.shadowBaseY = shadowBaseY
            self.animated = animated
            self.movingOnly = movingOnly
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

    /// 走る 4 本脚（犬・イノシシ共通）。付け根を軸に前後へ振る。原点は箱の左下、`facing` は
    /// 進行方向（+1 で右・-1 で左）。戻り値は脚のノード（動いているあいだだけ回す）。
    private func addRunningLegs(
        to node: SKNode, xs: [Double], hipY: Double, length: Double, thickness: Double,
        color: UInt32, z: CGFloat
    ) -> [SKNode] {
        var legs: [SKNode] = []
        for (index, x) in xs.enumerated() {
            // 付け根（上端）を軸に振る。縁取り付きの矩形（#929）。
            let leg = outlinedRect(
                size: CGSize(width: thickness, height: length), anchor: CGPoint(x: 0.5, y: 1), color: color
            )
            leg.position = CGPoint(x: x, y: hipY)
            leg.zPosition = z
            // 前後の脚を逆位相に。
            let phase = index.isMultiple(of: 2) ? 1.0 : -1.0
            leg.zRotation = CGFloat(0.45 * phase)
            let swing = SKAction.rotate(byAngle: CGFloat(-0.9 * phase), duration: 0.14)
            swing.timingMode = .easeInEaseOut
            leg.run(.repeatForever(.sequence([swing, swing.reversed()])))
            node.addChild(leg)
            legs.append(leg)
        }
        return legs
    }

    /// 犬（`RunnerHazardKind.dog`・#800 → #955）。画面の右（前方）から走者の方へ**左向きに**
    /// トコトコ歩いて来てすれ違う。丸と長方形＋三角のパスだけで組む（#494 の権利チェック）。
    ///
    /// 部品は #800 の右向きの絵のまま（頭が x の大きい側）で、**ノード全体を `xScale = -1` で
    /// 左右反転**して左向きにする。反転すると箱のローカル x `[0, w]` は `[-w, 0]` に写るので、
    /// 原点は**当たり判定の右端**（`syncMovingHazards` が `frame.end` に置く。左右反転した鳥と
    /// 同じ作法）——箱はそのまま `[frame.start, frame.end]` に重なり、当たり判定の外へずれない。
    /// 絵を当たり判定より大きく描く（#943・PR #950 の `addAnimalArtBox`）ときも、箱を当たり判定に
    /// 対して中央合わせにしておけば反転で張り出しが左右入れ替わるだけで、位置は変わらない。
    ///
    /// 当たり判定は `RunnerField` が `frame(atRunnerDistance:)` の矩形（1 タイル × 高さ 5）で
    /// 見ており、絵はその箱を `animalVisualScale` 倍に広げた箱（`addAnimalArtBox`・#943）の中に
    /// 収まる寸法。立ち止まって吠える挙動は #944 で無くなったので吹き出しは持たない。
    func addDog(_ hazard: RunnerHazard) -> MovingHazardView {
        let node = SKNode()
        node.position = CGPoint(x: hazard.end, y: Metrics.groundY)
        node.xScale = -1
        let (art, w, h) = addAnimalArtBox(to: node, hazard: hazard, leadingEdge: nil)
        // 色は世界ごと（`RunnerWorld.creatures`・#929）。胴・頭・耳・口元・尻尾・脚に暗い縁取りを
        // 引き、朝のパステルの背景でも輪郭が立つようにする（鼻・目・腹は差し色なので引かない）。
        let colors = world.creatures

        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 0.95, height: 0.5))
        shadow.fillColor = RunnerPalette.color(RunnerPalette.pitVoid)
        shadow.strokeColor = .clear
        shadow.alpha = 0.35
        shadow.position = CGPoint(x: w / 2, y: 0.25)
        art.addChild(shadow)

        // 脚（4 本）。体より奥に置く。
        let legs = addRunningLegs(
            to: art, xs: [w * 0.28, w * 0.4, w * 0.62, w * 0.74], hipY: h * 0.5,
            length: h * 0.5, thickness: w * 0.11, color: colors.dogDark, z: 0
        )

        // 胴（横長の楕円）と腹の差し色。
        let body = SKShapeNode(ellipseOf: CGSize(width: w * 0.7, height: h * 0.34))
        body.fillColor = RunnerPalette.color(colors.dogBody)
        outline(body)
        body.position = CGPoint(x: w * 0.5, y: h * 0.52)
        body.zPosition = 1
        art.addChild(body)
        let belly = SKShapeNode(ellipseOf: CGSize(width: w * 0.42, height: h * 0.14))
        belly.fillColor = RunnerPalette.color(colors.dogBelly)
        belly.strokeColor = .clear
        belly.position = CGPoint(x: w * 0.52, y: h * 0.44)
        belly.zPosition = 2
        art.addChild(belly)

        // 尻尾（後ろ上に立てた短い棒）。
        let tail = outlinedRect(
            size: CGSize(width: w * 0.1, height: h * 0.3), anchor: CGPoint(x: 0.5, y: 0), color: colors.dogBody
        )
        tail.position = CGPoint(x: w * 0.16, y: h * 0.56)
        tail.zRotation = -0.6
        tail.zPosition = 1
        art.addChild(tail)

        // 頭（丸）と、立った耳・鼻・目。頭は箱の右上（反転後は進行方向の左）。
        let head = SKShapeNode(circleOfRadius: w * 0.2)
        head.fillColor = RunnerPalette.color(colors.dogBody)
        outline(head)
        head.position = CGPoint(x: w * 0.8, y: h * 0.74)
        head.zPosition = 3
        art.addChild(head)
        let earPath = CGMutablePath()
        earPath.addLines(between: [
            CGPoint(x: -w * 0.16, y: h * 0.08), CGPoint(x: -w * 0.06, y: h * 0.3), CGPoint(x: 0, y: h * 0.1),
        ])
        earPath.closeSubpath()
        let ear = SKShapeNode(path: earPath)
        ear.fillColor = RunnerPalette.color(colors.dogDark)
        outline(ear)
        ear.position = head.position
        ear.zPosition = 2
        art.addChild(ear)
        let muzzle = SKShapeNode(ellipseOf: CGSize(width: w * 0.2, height: h * 0.12))
        muzzle.fillColor = RunnerPalette.color(colors.dogBelly)
        outline(muzzle)
        muzzle.position = CGPoint(x: w * 0.94, y: h * 0.7)
        muzzle.zPosition = 4
        art.addChild(muzzle)
        let nose = SKShapeNode(circleOfRadius: w * 0.04)
        nose.fillColor = RunnerPalette.color(colors.dogDark)
        nose.strokeColor = .clear
        nose.position = CGPoint(x: w * 1.0, y: h * 0.72)
        nose.zPosition = 5
        art.addChild(nose)
        let eye = SKShapeNode(circleOfRadius: w * 0.035)
        eye.fillColor = RunnerPalette.color(colors.dogDark)
        eye.strokeColor = .clear
        eye.position = CGPoint(x: w * 0.86, y: h * 0.8)
        eye.zPosition = 5
        art.addChild(eye)

        courseLayer.addChild(node)
        return MovingHazardView(hazard: hazard, node: node, animated: legs)
    }

    /// 地面を走る動物（犬・イノシシ）の絵の倍率（#943・会長QA 2026-09-15「鳥、犬、イノシシ全体的に
    /// 敵のオブジェクトが小さい。おじさんと同じ位の大きさはいるかと」）。
    ///
    /// 当たり判定（1 タイル幅 × 高さ 5 = 低い岩と同じ）とジャンプ物理はそのまま、**絵だけ**を
    /// この倍率で描く。基準にした走者の絵（`buildPlayer`。当たり判定は 8 × 11）は、帽子の天辺
    /// （`buildFace` の crown 11.0 + 0.9）まで**全高 11.9**、車輪の外径で全幅およそ 11。
    /// これに対して倍率 2 で **犬 8 × 10.4**（耳の先まで）・**イノシシ 8 × 9.2**（耳の先まで）になり、
    /// 走者と同じ位。**鳥は `RunnerBirdArt.defaultVisualScale`（2.5）で 10 × 10.8**（帯 4 × 4.34 の
    /// 絵を倍率で大きく描く。当たり判定の帯は不変）。
    ///
    /// 絵が当たり判定より大きい方向のズレは「触れて見えるのに当たらない」（走者に甘い）だけで、
    /// #609 で潰した「見えていないのに当たる」は起きない。箱の置き方は `addAnimalArtBox`。
    static let animalVisualScale = 2.0

    /// 動物の絵を組む箱（#943）。当たり判定（`hazard.length` × `hazard.height`）を
    /// `animalVisualScale` 倍に広げ、**縦は地面合わせ**で `node`（原点 = 当たり判定の左下）の下に
    /// 置く。戻り値は絵を足すノードと箱の幅・高さで、`addDog` / `addBoar` は箱の中の座標を
    /// すべて `w` / `h` の比で書く。
    ///
    /// 横の合わせ方は `leadingEdge` で選ぶ:
    /// - `nil`（犬）: 当たり判定に**中央合わせ**。前後に等しく張り出す
    /// - 値あり（イノシシ）: 絵の一番左の点（箱ローカル x を箱の幅に対する比で。イノシシなら
    ///   鼻先の楕円の左端 `boarSnout`）を当たり判定の左端にぴったり合わせ、張り出しを**すべて
    ///   後ろ（右）へ回す**。イノシシは岩にぶつかると当たり判定の左端を岩の右端に密着させて
    ///   止まる（`RunnerHazard.stopAt` = 岩の `end`）ので、中央合わせだと頭が岩に 2 めり込んで
    ///   見える（PR の敵対的検証で指摘）。鼻先を合わせれば岩に触れた形で止まり、走者が出会う側
    ///   （頭）は見た目と当たり判定が一致する。縁取り（#929）は輪郭の上に中心線で乗る線なので、
    ///   鳥（`RunnerBirdArt`）と同じく張り出しには数えない
    private func addAnimalArtBox(
        to node: SKNode, hazard: RunnerHazard, leadingEdge: Double?
    ) -> (art: SKNode, w: Double, h: Double) {
        let w = hazard.length * Self.animalVisualScale
        let h = hazard.height * Self.animalVisualScale
        let art = SKNode()
        let x = leadingEdge.map { -w * $0 } ?? (hazard.length - w) / 2
        art.position = CGPoint(x: x, y: 0)
        node.addChild(art)
        return (art, w, h)
    }

    /// イノシシの鼻先の楕円（`addBoar`）の中心 x と半幅（箱の幅に対する比）。絵の一番左（頭側の
    /// 先端）で、`addAnimalArtBox` が当たり判定の左端に合わせるのはこの左端。頭の丸（中心 0.2・
    /// 半径 0.22 → 左端 -0.02）より左に出ている。
    private static let boarSnout = (centerX: 0.06, halfWidth: 0.11)

    /// イノシシ（`RunnerHazardKind.boar`・#801）。右から左へ突進してくるので、頭は左向き。
    /// 丸と長方形＋三角のパスだけで組む（#494 の権利チェック）。原点は絵の箱の左下（頭側）。
    /// 絵の箱は当たり判定を `animalVisualScale` 倍に広げたもの（`addAnimalArtBox`・#943）で、
    /// **鼻先（`boarSnout` の左端）を当たり判定の左端に合わせ、張り出しはすべて後ろ（右）**
    /// ——岩で止まったとき鼻先が岩に触れた形になり、頭が岩にめり込まない。
    ///
    /// 走っているあいだは後ろ脚の足元に土煙を立てる。岩で止まると脚と土煙が止まり、
    /// 低い岩と同じ置物として岩の右側に並ぶ。
    func addBoar(_ hazard: RunnerHazard) -> MovingHazardView {
        let node = SKNode()
        node.position = CGPoint(x: hazard.start, y: Metrics.groundY)
        let (art, w, h) = addAnimalArtBox(
            to: node, hazard: hazard, leadingEdge: Self.boarSnout.centerX - Self.boarSnout.halfWidth
        )
        // 色は世界ごと（`RunnerWorld.creatures`・#929）。胴・頭・鼻先・牙・耳・脚に暗い縁取りを引く
        // （たてがみは胴の内側、目は差し色なので引かない）。
        let colors = world.creatures

        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 1.0, height: 0.55))
        shadow.fillColor = RunnerPalette.color(RunnerPalette.pitVoid)
        shadow.strokeColor = .clear
        shadow.alpha = 0.35
        shadow.position = CGPoint(x: w / 2, y: 0.25)
        art.addChild(shadow)

        let legXs = [w * 0.3, w * 0.42, w * 0.66, w * 0.78]
        let legs = addRunningLegs(
            to: art, xs: legXs, hipY: h * 0.46,
            length: h * 0.46, thickness: w * 0.13, color: colors.boarDark, z: 0
        )

        // 胴（犬より太い楕円）と、背中のたてがみ（暗い帯）。
        let body = SKShapeNode(ellipseOf: CGSize(width: w * 0.86, height: h * 0.46))
        body.fillColor = RunnerPalette.color(colors.boarBody)
        outline(body)
        body.position = CGPoint(x: w * 0.54, y: h * 0.56)
        body.zPosition = 1
        art.addChild(body)
        let mane = SKShapeNode(ellipseOf: CGSize(width: w * 0.6, height: h * 0.14))
        mane.fillColor = RunnerPalette.color(colors.boarDark)
        mane.strokeColor = .clear
        mane.position = CGPoint(x: w * 0.5, y: h * 0.76)
        mane.zPosition = 2
        art.addChild(mane)

        // 頭（左）。鼻先を前へ突き出し、牙を白で 1 本。
        let head = SKShapeNode(circleOfRadius: w * 0.22)
        head.fillColor = RunnerPalette.color(colors.boarBody)
        outline(head)
        head.position = CGPoint(x: w * 0.2, y: h * 0.58)
        head.zPosition = 3
        art.addChild(head)
        // 鼻先。絵の一番左で、`addAnimalArtBox` がここを当たり判定の左端に合わせる（`boarSnout`）。
        let snout = SKShapeNode(ellipseOf: CGSize(width: w * Self.boarSnout.halfWidth * 2, height: h * 0.14))
        snout.fillColor = RunnerPalette.color(colors.boarSnout)
        outline(snout)
        snout.position = CGPoint(x: w * Self.boarSnout.centerX, y: h * 0.52)
        snout.zPosition = 4
        art.addChild(snout)
        let tuskPath = CGMutablePath()
        tuskPath.addLines(between: [
            CGPoint(x: 0, y: 0), CGPoint(x: -w * 0.08, y: h * 0.12), CGPoint(x: w * 0.06, y: h * 0.02),
        ])
        tuskPath.closeSubpath()
        let tusk = SKShapeNode(path: tuskPath)
        tusk.fillColor = RunnerPalette.color(RunnerPalette.boarTusk)
        outline(tusk)
        tusk.position = CGPoint(x: w * 0.1, y: h * 0.42)
        tusk.zPosition = 5
        art.addChild(tusk)
        let earPath = CGMutablePath()
        earPath.addLines(between: [
            CGPoint(x: 0, y: 0), CGPoint(x: w * 0.06, y: h * 0.2), CGPoint(x: w * 0.16, y: h * 0.04),
        ])
        earPath.closeSubpath()
        let ear = SKShapeNode(path: earPath)
        ear.fillColor = RunnerPalette.color(colors.boarDark)
        outline(ear)
        ear.position = CGPoint(x: w * 0.22, y: h * 0.72)
        ear.zPosition = 2
        art.addChild(ear)
        let eye = SKShapeNode(circleOfRadius: w * 0.04)
        eye.fillColor = RunnerPalette.color(RunnerPalette.boarTusk)
        eye.strokeColor = .clear
        eye.position = CGPoint(x: w * 0.14, y: h * 0.66)
        eye.zPosition = 5
        art.addChild(eye)

        // 土煙。**後ろ脚の足元（地面の高さ）**に立て、走っているあいだだけ見せて膨らんで消えるを
        // 繰り返す。位置と大きさは本体の寸法から導く（#943 の倍率で本体と一緒に大きくなる）。
        // かつては箱の外の後方（x = 1.1〜1.35 w・地面より上）に置いていたが、会長QA（2026-09-15）で
        // 「地面のよくわからんところからおならみたいなのが出る」と見えた。本体の右（後ろ）に
        // ぶら下がる構造上、右から入ってくる本体より土煙が先に画面へ出ることはなく、本体が
        // 画面内にいるときだけ見える。
        let dust = SKNode()
        let rearFoot = legXs[3]
        for (index, spec) in [(0.0, 0.05, 0.14), (0.14, 0.12, 0.1)].enumerated() {
            let puff = SKShapeNode(circleOfRadius: h * spec.2)
            puff.fillColor = RunnerPalette.color(RunnerPalette.cloud)
            puff.strokeColor = .clear
            puff.alpha = 0.6
            puff.position = CGPoint(x: rearFoot + w * spec.0, y: h * spec.1)
            puff.zPosition = -1
            let grow = SKAction.group([.scale(to: 1.6, duration: 0.3), .fadeAlpha(to: 0, duration: 0.3)])
            let reset = SKAction.group([.scale(to: 0.6, duration: 0), .fadeAlpha(to: 0.6, duration: 0)])
            puff.run(.repeatForever(.sequence([.wait(forDuration: 0.1 * Double(index)), grow, reset])))
            dust.addChild(puff)
        }
        dust.isHidden = true
        art.addChild(dust)

        courseLayer.addChild(node)
        return MovingHazardView(hazard: hazard, node: node, animated: legs, movingOnly: dust)
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
                // 左向きに反転しているので原点は当たり判定の右端（`addDog`）。現れてから画面の左へ
                // 消えるまで歩き続ける（#955）。
                view.node.position = CGPoint(x: frame.end, y: Metrics.groundY)
                view.apply(.moving)
            case .boar:
                view.node.position = CGPoint(x: frame.start, y: Metrics.groundY)
                view.apply(frame.advance < 0 ? .moving : .stopped)
            case .pit, .lowBlock, .tallBlock:
                break
            }
        }
    }
}
