import Foundation
import SpriteKit

/// SpriteKit の描画・配色（#494）。
///
/// **SpriteKit の面は SwiftUI の `Theme` に追従しない**（`SKColor` はライト / ダークの動的色を
/// 持てる形で使えず、シーンの背景も自前で塗る）。盤・駒・牌と同じ「モードによらず固定の面」
/// として扱う（基盤規約 §4。値はブロック崩しの `BlocksPalette` と揃えてある）。
enum RunnerPalette {
    /// 空。ブロック崩しの地（`0x1E2233`）より明るくして、屋外の昼に見せる。
    static let sky: UInt32 = 0x2E4066
    /// 地面の上面（草）。
    static let groundTop: UInt32 = 0x22C3BE
    /// 地面の断面（土）。**空と系統の違う暖色にする**。同じ寒色の濃淡で塗ると、
    /// 地面と空の境目も穴の切れ目も見分けが付かない（最初の実機確認で判明）。
    static let groundBody: UInt32 = 0x6B4A32
    /// 障害物（岩）の明るい面。「何なのか分からない」というQAを受け、平らな矩形から
    /// 岩の塊に見える形へ変えた（会長QA）。
    static let rockLight: UInt32 = 0x9C8B7A
    /// 障害物（岩）の陰。
    static let rockDark: UInt32 = 0x6B5A4B
    /// 自転車の車体。`Theme.Fill.coral` と同じ値。
    static let bike: UInt32 = 0xFF8A7E
    /// 車輪。
    static let wheel: UInt32 = 0xFFF6EC
    /// おじさんの肌。
    static let skin: UInt32 = 0xF3C9A6
    /// 肌の陰（鼻・耳）。輪郭線を引かずに顔の起伏を出すため、肌より一段暗い色で置く。
    static let skinShade: UInt32 = 0xD9A57F
    /// おじさんの服。
    static let shirt: UInt32 = 0xB3A6F0
    /// 服の陰（奥の腕）。手前の胴と同じ色だと、腕が胴に溶けて1つの塊に見える。
    static let shirtShade: UInt32 = 0x8477C9
    /// ズボン（手前の脚）。**空（`sky`）と近い濃い青は使えない**。脚は空を背に描かれるので、
    /// 同系の暗い色にすると漕いでいるのに脚が見えない（最初の実機確認で判明）。
    static let pants: UInt32 = 0xE0B27C
    /// ズボンの陰（奥の脚）。左右の脚が重なる位相でも前後が分かるようにする。
    static let pantsShade: UInt32 = 0xAD8351
    /// 髪・口ひげ。「おじさん」と分かる要素はここだけなので、肌とはっきり差を付ける。
    static let hair: UInt32 = 0x4A3B33
    /// 靴。
    static let shoe: UInt32 = 0x2B2B33
    /// 金具（サドル・クランク・握り）。**空より明るい灰色**にする。暗い灰色にすると
    /// サドルだけが黒い塊として浮き、自転車の一部に見えない。
    static let metal: UInt32 = 0x8A93A6
    /// ゴールの旗。
    static let goal: UInt32 = 0xFF8FB1
    /// 穴の縁の警告帯。地面と同系色だと縁が分からず、落ちるかどうかの判断がつかない
    /// というQAを受けて追加（会長QA）。
    static let pitEdge: UInt32 = 0xFFD447
    /// 穴の中身（奈落）。縁の帯だけでは「穴の中はただの空」に見え、幅の実感が湧かない
    /// というQAを受けて追加（会長QA）。地面の断面よりさらに暗い色で、地面と穴を塗り分ける。
    static let pitVoid: UInt32 = 0x141824
    /// 雲。空より明るい半透明の白。
    static let cloud: UInt32 = 0xFFFFFF
    /// チェックポイントの目印。ゴール（`goal`）と見分けられる別の色にする。
    static let checkpoint: UInt32 = 0x5FA8FF
    /// 鳥（`RunnerHazardKind.bird`）の胴体。岩（`rockLight`/`rockDark`）の茶系とは
    /// 別系統の色にして、地を這う障害物と空を飛ぶ障害物を見分けられるようにする（会長QA）。
    static let birdBody: UInt32 = 0x4FAE71
    /// 鳥の翼。胴体より明るくして、羽ばたきのアニメーションで動きが見えるようにする。
    static let birdWing: UInt32 = 0x8FE3AE
    /// スピードアップアイテムの本体（丸）。「電気を帯びた玉」に見えるよう寒色にする。
    static let pickupBody: UInt32 = 0x5CE1E6
    /// スピードアップアイテムの稲妻（細い矩形2枚）。本体との対比を出すため明るい暖色にする。
    static let pickupBolt: UInt32 = 0xFFF4B8

    static func color(_ hex: UInt32) -> SKColor {
        SKColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// チャリンコおじさんの描画とゲームループ（#494）。
///
/// **ここにゲームのルールは無い**。毎フレーム `RunnerModel.tick(dt:)` を呼び、結果として
/// 決まった `RunnerField` の状態をノードへ写すだけの層で、当たり判定も進行も知らない
/// （アクション枠の基盤規約）。
///
/// シーンの座標系はコースの抽象単位そのまま（120 × 80）で、`scaleMode = .aspectFit` により
/// 表示サイズへ一括で拡大される。**呼び出し側は SpriteView の枠を必ず同じ縦横比にすること**。
@MainActor
final class RunnerScene: SKScene {
    private typealias Metrics = RunnerField.Metrics

    private let model: RunnerModel
    private var lastUpdate: TimeInterval?
    /// コースのノードを作り直した時点の `RunnerModel.runGeneration`。
    private var renderedGeneration = -1

    /// コース（地面・障害物・ゴール）。走者は動かさず、こちらを左へ流す。
    private let courseLayer = SKNode()
    private let player = SKNode()
    private let frontWheel = SKShapeNode(circleOfRadius: 2.6)
    private let rearWheel = SKShapeNode(circleOfRadius: 2.6)
    /// 漕ぐ脚（奥・手前）と、それに合わせて回るクランクの腕（#569）。
    /// 形は毎フレーム `RunnerRider` が返す座標で置き直す（寸法をここに書かない）。
    private let farThigh = SKSpriteNode()
    private let farShin = SKSpriteNode()
    private let farKnee = SKShapeNode(circleOfRadius: 0.55)
    private let farShoe = SKSpriteNode()
    private let nearThigh = SKSpriteNode()
    private let nearShin = SKSpriteNode()
    private let nearKnee = SKShapeNode(circleOfRadius: 0.55)
    private let nearShoe = SKSpriteNode()
    private let crankArm = SKSpriteNode()
    /// クランクの位相。接地して進んだぶんだけ回す（空中では止まる）。
    private var pedalPhase: Double = 0
    /// 前のフレームの `distance`（進んだぶんを出すため）。
    private var lastRenderedDistance: Double?
    /// 空の雲。何も障害が無い区間が静止画に見える、というQAを受けて追加（会長QA）。
    /// コースより遅い速度で流す（視差）ので、コースとは別レイヤーに持つ。
    private let cloudLayer = SKNode()
    /// 雲を並べる間隔（ワールド単位）。地面を作り直しても雲は作り直さないので、
    /// ステージが変わっても同じ雲がそのまま流れ続ける。
    private static let cloudSpacing: Double = 46
    /// コースに対する雲の流れる速さの比率（視差）。1 未満で遠くに見える。
    private static let cloudParallax: Double = 0.3
    /// このコースのスピードアップアイテムのノード（`stage.pickups` と同じ並び）。
    /// `rebuildCourse` で作り直し、`sync` が `field.collectedPickupCount` を見て順に消す。
    private var pickupNodes: [SKNode] = []
    /// すでに消したピックアップの数。**走者は後退しないので、取得順は常に `pickups` の並びどおり**
    /// ——`collectedPickupCount` 件目までを毎フレーム照合すれば、どれが取得済みか特定できる。
    private var removedPickupCount = 0

    init(model: RunnerModel) {
        self.model = model
        super.init(size: CGSize(
            width: RunnerField.Metrics.width,
            height: RunnerField.Metrics.height
        ))
        scaleMode = .aspectFit
        backgroundColor = RunnerPalette.color(RunnerPalette.sky)
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RunnerScene はコードからのみ生成する")
    }

    override func didMove(to view: SKView) {
        guard courseLayer.parent == nil else { return }
        addChild(cloudLayer)
        buildClouds()
        addChild(courseLayer)
        buildPlayer()
        addChild(player)
        rebuildCourse()
        sync()
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        // 初回フレームは経過時間が測れないので進めない。
        guard let last = lastUpdate, currentTime > last else { return }
        model.tick(dt: currentTime - last)
        sync()
    }

    // MARK: - 組み立て

    /// 自転車に乗ったおじさん。**既存作品の意匠には寄せず**、丸と長方形だけで組む（#494 の権利チェック）。
    ///
    /// 「棒人間レベル」というQAを受けた底上げ（#569 決裁A）。**輪郭線は引かず**、色の差だけで
    /// 面を分ける（1 単位が数 pt にしか描かれないので、線を足すと潰れて滲む）。増やしたのは
    /// ①漕ぐ脚 ②ハンドルを握る腕 ③顔（目・鼻・口ひげ）とつばのある帽子 ④スポーク——
    /// いずれも当たり判定には関わらない見た目だけの追加で、走者の占める寸法
    /// （`Metrics.playerWidth` / `.playerHeight`）は変えていない。
    private func buildPlayer() {
        buildBike()
        buildLegs()
        buildRiderBody()
        buildFace()
        player.position = CGPoint(x: Metrics.playerX, y: Metrics.groundY)
    }

    /// 自転車（車輪・スポーク・車体・サドル・クランク）。
    private func buildBike() {
        for wheel in [frontWheel, rearWheel] {
            wheel.fillColor = .clear
            wheel.strokeColor = RunnerPalette.color(RunnerPalette.wheel)
            wheel.lineWidth = 0.7
            // スポーク。無地の円は回しても回転が見えず、止まっているように見えていた。
            // 車輪の子にしておけば `zRotation` にそのまま追従する。
            for i in 0..<3 {
                let spoke = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.wheel),
                                         size: CGSize(width: 5.0, height: 0.35))
                spoke.zRotation = CGFloat(Double(i) * .pi / 3)
                wheel.addChild(spoke)
            }
            player.addChild(wheel)
        }
        frontWheel.position = CGPoint(x: 2.6, y: 2.6)
        rearWheel.position = CGPoint(x: -2.6, y: 2.6)

        // 車体。**太い1本の棒ではなく細い管を組む**。棒1枚だとクランクとペダルが棒に
        // 埋まって漕いでいるのが見えず、自転車の形にも見えなかった（最初の実機確認で判明）。
        addTube(from: RunnerRider.rearHub, to: RunnerRider.crank)     // チェーンステー
        addTube(from: RunnerRider.crank, to: RunnerRider.seatBase)    // シートチューブ
        addTube(from: RunnerRider.seatBase, to: RunnerRider.rearHub)  // シートステー
        addTube(from: RunnerRider.crank, to: RunnerRider.headTop)     // ダウンチューブ
        addTube(from: RunnerRider.seatBase, to: RunnerRider.headTop)  // トップチューブ
        addTube(from: RunnerRider.headTop, to: RunnerRider.frontHub)  // フォーク
        addTube(from: RunnerRider.headTop, to: RunnerRider.grip)      // ステム

        // 握りとサドル。手と腰の行き先を絵の上でも示す（腕と脚の付け根が浮かないようにする）。
        let grip = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.metal),
                                size: CGSize(width: 1.4, height: 0.5))
        grip.position = CGPoint(x: RunnerRider.grip.x, y: RunnerRider.grip.y)
        let saddle = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.metal),
                                  size: CGSize(width: 2.2, height: 0.6))
        saddle.position = CGPoint(x: RunnerRider.seatBase.x, y: RunnerRider.seatBase.y + 0.3)
        for node in [grip, saddle] { player.addChild(node) }

        // クランク（ペダルの回転中心と、回る腕）。
        let chainring = SKShapeNode(circleOfRadius: 0.8)
        chainring.fillColor = .clear
        chainring.strokeColor = RunnerPalette.color(RunnerPalette.metal)
        chainring.lineWidth = 0.4
        chainring.position = CGPoint(x: RunnerRider.crank.x, y: RunnerRider.crank.y)
        player.addChild(chainring)

        crankArm.color = RunnerPalette.color(RunnerPalette.metal)
        crankArm.size = CGSize(width: RunnerRider.crankRadius, height: 0.45)
        crankArm.anchorPoint = CGPoint(x: 0, y: 0.5)
        crankArm.position = CGPoint(x: RunnerRider.crank.x, y: RunnerRider.crank.y)
        crankArm.zPosition = 1
        player.addChild(crankArm)
    }

    /// 車体の管を1本。2点を結ぶ細い矩形を、始点で回して置く。
    private func addTube(from start: RunnerPoint, to end: RunnerPoint) {
        let dx = end.x - start.x, dy = end.y - start.y
        let tube = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.bike),
            size: CGSize(width: (dx * dx + dy * dy).squareRoot(), height: 0.55)
        )
        tube.anchorPoint = CGPoint(x: 0, y: 0.5)
        tube.position = CGPoint(x: start.x, y: start.y)
        tube.zRotation = CGFloat(atan2(dy, dx))
        player.addChild(tube)
    }

    /// 漕ぐ脚。奥の脚は車体より後ろ、手前の脚は胴より前に置く（重なる位相でも前後が分かる）。
    private func buildLegs() {
        configureLeg(thigh: farThigh, shin: farShin, knee: farKnee, shoe: farShoe,
                     color: RunnerPalette.pantsShade, z: -1)
        configureLeg(thigh: nearThigh, shin: nearShin, knee: nearKnee, shoe: nearShoe,
                     color: RunnerPalette.pants, z: 3)
    }

    private func configureLeg(
        thigh: SKSpriteNode, shin: SKSpriteNode, knee: SKShapeNode, shoe: SKSpriteNode,
        color: UInt32, z: CGFloat
    ) {
        thigh.color = RunnerPalette.color(color)
        thigh.size = CGSize(width: RunnerRider.thigh, height: 1.15)
        shin.color = RunnerPalette.color(color)
        shin.size = CGSize(width: RunnerRider.shin, height: 0.9)
        for segment in [thigh, shin] {
            // 関節を軸に回すので、左端の中央を基準にする。
            segment.anchorPoint = CGPoint(x: 0, y: 0.5)
            segment.zPosition = z
            player.addChild(segment)
        }
        knee.fillColor = RunnerPalette.color(color)
        knee.strokeColor = .clear
        knee.zPosition = z
        player.addChild(knee)
        // 付け根。腿が胴からいきなり生えて見えるのを防ぐ（動かないので子ノードで置くだけ）。
        let joint = SKShapeNode(circleOfRadius: 0.7)
        joint.fillColor = RunnerPalette.color(color)
        joint.strokeColor = .clear
        joint.position = CGPoint(x: RunnerRider.hip.x, y: RunnerRider.hip.y)
        joint.zPosition = z
        player.addChild(joint)
        shoe.color = RunnerPalette.color(RunnerPalette.shoe)
        shoe.size = CGSize(width: 1.2, height: 0.5)
        shoe.zPosition = z
        player.addChild(shoe)
    }

    /// おじさんの胴・腹・腕・首。
    private func buildRiderBody() {
        // 前かがみの胴。楕円1枚を傾けて置く（矩形だと肩と腰の丸みが出ない）。
        let torso = SKShapeNode(ellipseOf: CGSize(width: 4.2, height: 3.4))
        torso.fillColor = RunnerPalette.color(RunnerPalette.shirt)
        torso.strokeColor = .clear
        torso.zRotation = 0.72
        torso.position = CGPoint(x: -0.3, y: 7.4)
        torso.zPosition = 2
        player.addChild(torso)

        // 腹。「おじさん」の体型はこの丸みだけで伝える（顔だけでは年齢が読めない）。
        let belly = SKShapeNode(circleOfRadius: 1.45)
        belly.fillColor = RunnerPalette.color(RunnerPalette.shirt)
        belly.strokeColor = .clear
        belly.position = CGPoint(x: 0.85, y: 6.9)
        belly.zPosition = 2
        player.addChild(belly)

        // ハンドルへ伸びる腕（肩から握りまで1本の棒）と手。
        let arm = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.shirtShade),
                               size: CGSize(width: armLength, height: 0.95))
        arm.anchorPoint = CGPoint(x: 0, y: 0.5)
        arm.position = CGPoint(x: RunnerRider.shoulder.x, y: RunnerRider.shoulder.y)
        arm.zRotation = CGFloat(atan2(
            RunnerRider.grip.y - RunnerRider.shoulder.y,
            RunnerRider.grip.x - RunnerRider.shoulder.x
        ))
        arm.zPosition = 4
        player.addChild(arm)

        let hand = SKShapeNode(circleOfRadius: 0.55)
        hand.fillColor = RunnerPalette.color(RunnerPalette.skin)
        hand.strokeColor = .clear
        hand.position = CGPoint(x: RunnerRider.grip.x, y: RunnerRider.grip.y + 0.3)
        hand.zPosition = 4
        player.addChild(hand)
    }

    /// 肩から握りまでの長さ。
    private var armLength: Double {
        let dx = RunnerRider.grip.x - RunnerRider.shoulder.x
        let dy = RunnerRider.grip.y - RunnerRider.shoulder.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// 顔と帽子。**「おじさん」と分かるのはここだけ**なので、目・鼻・口ひげを省かない。
    private func buildFace() {
        let head = SKShapeNode(circleOfRadius: 1.5)
        head.fillColor = RunnerPalette.color(RunnerPalette.skin)
        head.strokeColor = .clear
        head.position = CGPoint(x: 1.0, y: 9.9)
        head.zPosition = 5
        player.addChild(head)

        // 後頭部の髪（帽子とうなじの間）。
        let hair = SKShapeNode(circleOfRadius: 0.85)
        hair.fillColor = RunnerPalette.color(RunnerPalette.hair)
        hair.strokeColor = .clear
        hair.position = CGPoint(x: -0.1, y: 9.6)
        hair.zPosition = 5
        player.addChild(hair)

        // 帽子（山とつば）。つばを前に出すことで、向いている方向が一目で分かる。
        let crown = SKShapeNode(ellipseOf: CGSize(width: 3.2, height: 1.8))
        crown.fillColor = RunnerPalette.color(RunnerPalette.bike)
        crown.strokeColor = .clear
        crown.position = CGPoint(x: 0.9, y: 11.0)
        crown.zPosition = 6
        player.addChild(crown)

        let brim = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.bike),
                                size: CGSize(width: 1.9, height: 0.45))
        brim.position = CGPoint(x: 2.7, y: 10.7)
        brim.zPosition = 6
        player.addChild(brim)

        let eye = SKShapeNode(circleOfRadius: 0.3)
        eye.fillColor = RunnerPalette.color(RunnerPalette.hair)
        eye.strokeColor = .clear
        eye.position = CGPoint(x: 1.85, y: 10.15)
        eye.zPosition = 7
        player.addChild(eye)

        let nose = SKShapeNode(circleOfRadius: 0.45)
        nose.fillColor = RunnerPalette.color(RunnerPalette.skinShade)
        nose.strokeColor = .clear
        nose.position = CGPoint(x: 2.4, y: 9.7)
        nose.zPosition = 7
        player.addChild(nose)

        let mustache = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.hair),
                                    size: CGSize(width: 1.3, height: 0.45))
        mustache.position = CGPoint(x: 1.95, y: 9.2)
        mustache.zPosition = 7
        player.addChild(mustache)
    }

    /// 雲ノードそのもの（`cloudBaseX` と対で、`sync` が毎フレーム位置を計算し直す）。
    private var clouds: [SKNode] = []
    /// 雲の基準 x（`0, spacing, 2*spacing, …`）。`cloudLayer` は動かさず、
    /// 各雲を「距離に応じて `cloudSpacing * clouds.count` 幅でループする」座標に置き直すことで、
    /// ステージがどれだけ長くても雲を作り直さずに無限スクロールへ流せる。
    private var cloudBaseX: [Double] = []

    /// 空を流れる雲。ステージをまたいでも作り直さない（`rebuildCourse` の対象外）。
    private func buildClouds() {
        let count = 8
        for i in 0..<count {
            let cloud = SKNode()
            let puffs: [(dx: Double, dy: Double, r: Double)] = [
                (0, 0, 3.4), (-3.2, -0.6, 2.4), (3.0, -0.4, 2.6), (0.6, 1.2, 2.2),
            ]
            for puff in puffs {
                let shape = SKShapeNode(circleOfRadius: puff.r)
                shape.fillColor = RunnerPalette.color(RunnerPalette.cloud)
                shape.alpha = 0.55
                shape.strokeColor = .clear
                shape.position = CGPoint(x: puff.dx, y: puff.dy)
                cloud.addChild(shape)
            }
            // 高さを雲ごとに変えて、横一列に並んで見えないようにする。
            let y = Metrics.height - 10 - Double(i % 3) * 7
            cloud.position = CGPoint(x: Double(i) * Self.cloudSpacing, y: y)
            cloudLayer.addChild(cloud)
            clouds.append(cloud)
            cloudBaseX.append(Double(i) * Self.cloudSpacing)
        }
    }

    /// 地面・穴・障害物・ゴールをまとめて作り直す。
    private func rebuildCourse() {
        courseLayer.removeAllChildren()
        let stage = model.field.stage

        // 地面は「穴でないところ」を並べて描く。穴の場所には何も置かないので、
        // そこが空いていることが見た目でも当たり判定でも同じ意味になる。
        var x: Double = 0
        for pit in stage.hazards where pit.kind == .pit {
            if pit.start > x { addGround(from: x, to: pit.start) }
            addPitVoid(pit)
            addPitEdgeMarkers(pit)
            x = pit.end
        }
        if x < stage.length { addGround(from: x, to: stage.length + Metrics.width) }

        for hazard in stage.hazards where hazard.kind != .pit {
            if hazard.kind == .bird {
                addBird(hazard)
            } else {
                addRock(hazard)
            }
        }

        pickupNodes = stage.pickups.map { addPickup($0) }
        removedPickupCount = 0

        addCheckpointMarker(at: stage.checkpoint, percent: stage.checkpointPercent)
        addGoalMarker(at: stage.length)
        renderedGeneration = model.runGeneration
    }

    /// 障害物（岩）。平らな矩形1枚だと「何なのか分からない」というQAを受け、
    /// 明るい面 + 陰の2つの丸を重ねただけの塊に変えた（丸と長方形だけで組む規約を維持）。
    /// 当たり判定は `RunnerField` が `hazard.start`〜`.end`/`.height` の矩形で見ており、
    /// この見た目の変更とは独立している——中に収まる大きさで描いているだけ。
    private func addRock(_ hazard: RunnerHazard) {
        let node = SKNode()
        node.position = CGPoint(x: hazard.start, y: Metrics.groundY)
        let w = hazard.length, h = hazard.height

        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 0.9, height: h * 0.85))
        shadow.fillColor = RunnerPalette.color(RunnerPalette.rockDark)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: w / 2, y: h * 0.42)
        node.addChild(shadow)

        let body = SKShapeNode(ellipseOf: CGSize(width: w * 0.76, height: h * 0.7))
        body.fillColor = RunnerPalette.color(RunnerPalette.rockLight)
        body.strokeColor = .clear
        body.position = CGPoint(x: w * 0.42, y: h * 0.5)
        node.addChild(body)

        courseLayer.addChild(node)
    }

    /// 鳥（`RunnerHazardKind.bird`）。「棒と穴しかない」というQAを受けて追加した敵の1つ
    /// （会長QA「鳥とか右から車が来るとか要素はいる」）。丸（胴体）+ 長方形2枚（翼）の
    /// 組み合わせだけで描く（岩と同じ権利チェック上の制約）。羽ばたきは `SKAction` の
    /// 純粋な見た目の演出で、当たり判定（`RunnerField.isHittingBlock`）には一切影響しない
    /// ——判定は岩と同じ `hazard.start`〜`.end`/`.height` の矩形のまま。
    private func addBird(_ hazard: RunnerHazard) {
        let node = SKNode()
        node.position = CGPoint(x: hazard.start, y: Metrics.groundY)
        let w = hazard.length, h = hazard.height
        let bodyRadius = min(w, h) * 0.45
        let center = CGPoint(x: w / 2, y: h * 0.55)

        for side in [-1.0, 1.0] {
            let wing = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.birdWing),
                size: CGSize(width: bodyRadius * 1.7, height: bodyRadius * 0.55)
            )
            wing.anchorPoint = CGPoint(x: side > 0 ? 0 : 1, y: 0.5)
            wing.position = center
            wing.zRotation = CGFloat(side > 0 ? 0.2 : .pi - 0.2)
            node.addChild(wing)
            // 羽ばたき。当たり判定の矩形は動かさない、純粋な見た目の周期アニメーション。
            let flapAmount = CGFloat(side) * 0.5
            let up = SKAction.rotate(byAngle: flapAmount, duration: 0.16)
            wing.run(.repeatForever(.sequence([up, up.reversed()])))
        }

        let body = SKShapeNode(circleOfRadius: bodyRadius)
        body.fillColor = RunnerPalette.color(RunnerPalette.birdBody)
        body.strokeColor = .clear
        body.position = center
        node.addChild(body)

        courseLayer.addChild(node)
    }

    /// スピードアップアイテム。丸（本体）+ 長方形2枚（稲妻）の組み合わせで描く
    /// （会長QA「スピードアップアイテムor床とかあったほうがいい」）。取得すると `sync` が
    /// フェードアウト＋縮小で消す。戻り値は `sync` が取得済みかどうかを追うためのノード参照。
    @discardableResult
    private func addPickup(_ pickup: RunnerPickup) -> SKNode {
        let node = SKNode()
        let radius = 1.8
        node.position = CGPoint(x: pickup.start, y: Metrics.groundY + radius + 1.5)

        let body = SKShapeNode(circleOfRadius: radius)
        body.fillColor = RunnerPalette.color(RunnerPalette.pickupBody)
        body.strokeColor = .clear
        node.addChild(body)

        // 稲妻。中心をジグザグに横切る細い矩形2枚（丸と長方形だけで組む規約を維持）。
        let boltUpper = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.pickupBolt),
            size: CGSize(width: 0.6, height: radius * 1.1)
        )
        boltUpper.anchorPoint = CGPoint(x: 0.5, y: 1)
        boltUpper.position = CGPoint(x: -0.35, y: radius * 0.6)
        boltUpper.zRotation = 0.35
        node.addChild(boltUpper)

        let boltLower = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.pickupBolt),
            size: CGSize(width: 0.6, height: radius * 1.1)
        )
        boltLower.anchorPoint = CGPoint(x: 0.5, y: 1)
        boltLower.position = CGPoint(x: 0.35, y: -radius * 0.1)
        boltLower.zRotation = -0.35
        node.addChild(boltLower)

        courseLayer.addChild(node)
        return node
    }

    /// 取得済みのピックアップをフェードアウト＋縮小で消す。
    private func removePickupNode(_ node: SKNode) {
        guard node.parent != nil else { return }
        node.run(.sequence([
            .group([.fadeOut(withDuration: 0.25), .scale(to: 0.2, duration: 0.25)]),
            .removeFromParent(),
        ]))
    }

    /// 穴の中身（奈落）。縁の帯だけだと穴の内側が空と同じ色のままで、
    /// 「本当にここが穴なのか・幅はどれくらいか」が伝わらなかった（会長QA）。
    /// 地面と同じ矩形をそのまま塗り替えるだけなので、幅は `pit.start`〜`.end` の実寸そのもの
    /// ——当たり判定（`RunnerField.isPit`）が見ている境界と完全に一致する。
    private func addPitVoid(_ pit: RunnerHazard) {
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
    private func addPitEdgeMarkers(_ pit: RunnerHazard) {
        for edgeX in [pit.start, pit.end] {
            let strip = SKSpriteNode(
                color: RunnerPalette.color(RunnerPalette.pitEdge),
                size: CGSize(width: 0.6, height: 2.6)
            )
            strip.anchorPoint = CGPoint(x: 0.5, y: 1)
            strip.position = CGPoint(x: edgeX, y: Metrics.groundY)
            courseLayer.addChild(strip)
        }
    }

    private func addGround(from start: Double, to end: Double) {
        let body = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.groundBody),
            size: CGSize(width: end - start, height: Metrics.groundY)
        )
        body.anchorPoint = .zero
        body.position = CGPoint(x: start, y: 0)
        let top = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.groundTop),
            size: CGSize(width: end - start, height: 2.2)
        )
        top.anchorPoint = .zero
        top.position = CGPoint(x: start, y: Metrics.groundY - 2.2)
        courseLayer.addChild(body)
        courseLayer.addChild(top)
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
    private func addCheckpointMarker(at x: Double, percent: Int) {
        let pole = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.checkpoint),
            size: CGSize(width: 1, height: 9)
        )
        pole.anchorPoint = CGPoint(x: 0.5, y: 0)
        pole.position = CGPoint(x: x, y: Metrics.groundY)
        courseLayer.addChild(pole)

        let signCenter = CGPoint(x: x, y: Metrics.groundY + 9)
        let sign = SKShapeNode(rectOf: CGSize(width: 6.6, height: 3.6), cornerRadius: 0.6)
        sign.fillColor = RunnerPalette.color(RunnerPalette.checkpoint)
        sign.strokeColor = RunnerPalette.color(RunnerPalette.wheel)
        sign.lineWidth = 0.4
        sign.position = signCenter
        courseLayer.addChild(sign)

        let label = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        label.text = "\(percent)%"
        label.fontSize = 2.5
        label.fontColor = RunnerPalette.color(RunnerPalette.wheel)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = signCenter
        label.zPosition = 1
        courseLayer.addChild(label)
    }

    /// ゴールの目印（旗）。細い柱だけでは「何のオブジェクトか分からない」というQAを受け、
    /// 三角の旗を足して一目でゴールと分かる形にした。
    private func addGoalMarker(at x: Double) {
        let pole = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.wheel), size: CGSize(width: 1, height: 16))
        pole.anchorPoint = CGPoint(x: 0.5, y: 0)
        pole.position = CGPoint(x: x, y: Metrics.groundY)
        courseLayer.addChild(pole)

        let flagPath = CGMutablePath()
        flagPath.move(to: .zero)
        flagPath.addLine(to: CGPoint(x: 4.4, y: -1.3))
        flagPath.addLine(to: CGPoint(x: 0, y: -2.6))
        flagPath.closeSubpath()
        let flag = SKShapeNode(path: flagPath)
        flag.fillColor = RunnerPalette.color(RunnerPalette.goal)
        flag.strokeColor = .clear
        flag.position = CGPoint(x: x + 0.5, y: Metrics.groundY + 14.5)
        courseLayer.addChild(flag)
    }

    // MARK: - 反映

    private func sync() {
        if renderedGeneration != model.runGeneration { rebuildCourse() }
        let field = model.field
        // 雲はコースより遅く流す（視差）。`cloudLayer` 自体は動かさず、
        // 雲1つ1つを「全雲の帯の幅」でラップする座標に置き直す（無限スクロール）。
        let totalWidth = Self.cloudSpacing * Double(clouds.count)
        for (i, cloud) in clouds.enumerated() {
            let raw = (cloudBaseX[i] - field.distance * Self.cloudParallax)
                .truncatingRemainder(dividingBy: totalWidth)
            let wrapped = raw < 0 ? raw + totalWidth : raw
            cloud.position.x = wrapped
        }
        // 走者の画面上の x は動かさず、コースのほうを左へ流す。
        courseLayer.position = CGPoint(x: Metrics.playerX - field.distance, y: 0)
        player.position = CGPoint(x: Metrics.playerX, y: field.footY)
        // 車輪は進んだ距離ぶんだけ回す（半径 2.6 の円周で 1 回転）。
        let angle = -field.distance / 2.6
        frontWheel.zRotation = CGFloat(angle)
        rearWheel.zRotation = CGFloat(angle)
        syncPedaling(field)
        // 空中では前のめりにする。跳んでいることが動きだけで分かるようにするため。
        player.zRotation = field.isGrounded ? 0 : CGFloat(max(-0.3, min(0.3, field.vy / 300)))
        syncPickups(field)
    }

    /// 取得済みのピックアップのノードを消す。走者は後退しないので、`collectedPickupCount` は
    /// 常に `pickups` の並びの先頭からの件数と一致する（`pickupNodes` の宣言を参照）。
    private func syncPickups(_ field: RunnerField) {
        guard field.collectedPickupCount > removedPickupCount else { return }
        let upper = min(field.collectedPickupCount, pickupNodes.count)
        for i in removedPickupCount..<upper {
            removePickupNode(pickupNodes[i])
        }
        removedPickupCount = field.collectedPickupCount
    }

    /// 漕ぐ脚を進める（#569）。
    ///
    /// 位相は**接地して進んだ距離**から出す。時計で回すと、ゆっくりモードや一時停止のあいだも
    /// 脚だけが動いてしまう。速く走れば漕ぐのも速くなる（`pedalBoost` が距離に乗るため、
    /// ケイデンスはここで何もしなくても乗りに追従する）。
    private func syncPedaling(_ field: RunnerField) {
        // 初回は 0 から数える。`field.distance` を初期値にすると、シーンが出るより前に
        // 進んでいた場合（撮影用の `-simulateRunner`）にその区間だけ漕いでいない扱いになる。
        let delta = field.distance - (lastRenderedDistance ?? 0)
        lastRenderedDistance = field.distance
        pedalPhase = RunnerRider.advance(
            phase: pedalPhase, by: delta, isPedaling: field.isGrounded
        )
        place(thigh: farThigh, shin: farShin, knee: farKnee, shoe: farShoe,
              leg: RunnerRider.leg(phase: pedalPhase, isFar: true))
        let near = RunnerRider.leg(phase: pedalPhase, isFar: false)
        place(thigh: nearThigh, shin: nearShin, knee: nearKnee, shoe: nearShoe, leg: near)
        crankArm.zRotation = CGFloat(atan2(
            near.pedal.y - RunnerRider.crank.y, near.pedal.x - RunnerRider.crank.x
        ))
    }

    /// 片脚のノードを、求めた形（腰 → 膝 → ペダル）へ置き直す。
    private func place(
        thigh: SKSpriteNode, shin: SKSpriteNode, knee: SKShapeNode, shoe: SKSpriteNode,
        leg: RunnerRider.Leg
    ) {
        thigh.position = CGPoint(x: leg.hip.x, y: leg.hip.y)
        thigh.zRotation = CGFloat(atan2(leg.knee.y - leg.hip.y, leg.knee.x - leg.hip.x))
        shin.position = CGPoint(x: leg.knee.x, y: leg.knee.y)
        shin.zRotation = CGFloat(atan2(leg.pedal.y - leg.knee.y, leg.pedal.x - leg.knee.x))
        knee.position = CGPoint(x: leg.knee.x, y: leg.knee.y)
        // 靴はペダルに乗っているので水平のまま（回すと足首が回転して見える）。
        shoe.position = CGPoint(x: leg.pedal.x, y: leg.pedal.y + 0.15)
    }
}
