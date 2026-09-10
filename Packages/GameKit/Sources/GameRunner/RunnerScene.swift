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
    /// 障害物（岩）の明るい面（日の当たる頂の面）。**茶系は使えない**。地面の断面
    /// （`groundBody`）と同系になり、実機では遠景の丘（紺）とも地面とも見分けが付かず
    /// 「何なのか分からない」というQAが続いた（会長 2026-09-10「岩のデザインはNG」）。
    /// 空・丘の紺、地表のティール、断面の茶のどれとも系統の違う明るいストーングレー
    /// 3階調にして、輪郭線なしでも岩塊が浮き出るようにする。
    static let rockLight: UInt32 = 0xC2C8D2
    /// 障害物（岩）の本体（中間色）。
    static let rockBody: UInt32 = 0x939AA8
    /// 障害物（岩）の陰（陰の面・接地陰）。
    static let rockDark: UInt32 = 0x565D6B
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
    /// 遠景の丘（奥）。空より一段暗い寒色で、空との境目が分かる程度の差に留める。
    static let hillFar: UInt32 = 0x263A5C
    /// 近景の丘（手前）。奥の丘よりさらに暗く、地面（`groundBody`）との重なりでも
    /// 手前にあると分かるようにする。
    static let hillNear: UInt32 = 0x1F2F4C
    /// チェックポイントの旗。ゴール（`goal`）と見分けられる別の色にする。
    static let checkpoint: UInt32 = 0x5FA8FF
    /// チェックポイントの旗の陰（奥側）。ゴールの旗と同じ厚みの出し方を踏襲する。
    static let checkpointShade: UInt32 = 0x3D7BD9
    /// チェックポイントの旗の文字。白抜き（`wheel`）は旗の水色に対して薄く、実機で
    /// 読めなかった（会長QA「旗の文字もいまだに見えない」）。旗より十分暗い紺で
    /// コントラストを取る。
    static let checkpointText: UInt32 = 0x14284A
    /// 鳥（`RunnerHazardKind.bird`）の胴体。岩の茶系・空の寒色とは別系統の色にして、
    /// 地を這う障害物と空を飛ぶ障害物を見分けられるようにする（会長QA）。
    static let birdBody: UInt32 = 0x4FAE71
    /// 鳥の翼・尾羽の奥の1枚。旧版は胴体より明るい緑だったが、明るい腹・白目と
    /// 差し色が渋滞して面の切れ目が読めなかった。胴体より一段**濃い**緑にして、
    /// 畳んだ翼と尾羽の重なりが遠目でも影として見えるようにする（会長QA 2026-09-10
    /// 「鳥もデザイン改善して欲しい」）。
    static let birdWing: UInt32 = 0x2F7D4E
    /// 鳥のくちばし・脚。胴体と対比が付く暖色にする（「何の生き物か分からない」対策）。
    static let birdBeak: UInt32 = 0xFFB648
    /// 鳥の腹（明るい差し色）。胴体の丸だけだと単色の玉に見えるため、腹だけ明るくして
    /// 立体感と「鳥らしさ」を出す。
    static let birdBelly: UInt32 = 0xE8F5E0
    /// 鳥の目（小さな黒丸）。生き物だと分かる最小限の要素。
    static let birdEye: UInt32 = 0x1F2B22
    /// スピードアップアイテムの後光（丸）。「電気を帯びた玉」に見えるよう寒色にする。
    static let pickupAura: UInt32 = 0x5CE1E6
    /// スピードアップアイテムの稲妻（本体）。後光との対比を出すため明るい暖色にする。
    /// 以前は細い矩形2枚で稲妻を表していたが小さすぎて読めなかった（会長QA
    /// 「何なのかパッと見てわからない」・2026-09-10）ため、太い稲妻の1枚絵に描き直した。
    static let pickupBolt: UInt32 = 0xFFE066
    /// 稲妻の縁取り。後光と同系色の玉の上に置いても輪郭が沈まないようにする。
    static let pickupBoltOutline: UInt32 = 0xB8860B

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
/// シーンの座標系はコースの抽象単位そのまま（`RunnerField.Metrics.width` × `.height`）で、
/// `scaleMode = .aspectFit` により表示サイズへ一括で拡大される。
/// **呼び出し側は SpriteView の枠を必ず同じ縦横比にすること**。
@MainActor
final class RunnerScene: SKScene {
    private typealias Metrics = RunnerField.Metrics

    private let model: RunnerModel
    private var lastUpdate: TimeInterval?
    /// コースのノードを作り直した時点の `RunnerModel.runGeneration`。
    private var renderedGeneration = -1
    /// 直前の `sync()` で見た `phase`。`.falling` に入った最初のフレームだけ落下演出を
    /// 発火させるための「前回反映した世代」パターン（`renderedGeneration` と同じ考え方）。
    private var lastSyncedPhase: RunnerPhase = .ready

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

    /// 遠景の丘（奥・手前の2層）。画面を縦長にした分だけ空が広がるので、
    /// 何も無い帯にせず地平線側を丘の稜線で埋める（2026-09-10 会長QA「縦を活かす」対応）。
    /// 雲と同じく無限スクロールにするので、コースとは別レイヤーに持つ。
    private let hillLayer = SKNode()
    /// 丘の稜線を並べる間隔（ワールド単位）。
    private static let hillSpacing: Double = 60
    /// コースに対する丘の流れる速さの比率（視差）。雲より近い＝雲より速いが、
    /// コースそのもの（1.0）よりは遅い。
    private static let hillParallax: Double = 0.55

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
        addChild(hillLayer)
        buildHills()
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
            // 高さを雲ごとに変えて、横一列に並んで見えないようにする。縦長にした分だけ
            // 帯を広く使う（丘の稜線 `buildHills` より上、画面の上端 8 単位手前まで）。
            let y = Metrics.height - 12 - Double(i % 5) * 10
            cloud.position = CGPoint(x: Double(i) * Self.cloudSpacing, y: y)
            cloudLayer.addChild(cloud)
            clouds.append(cloud)
            cloudBaseX.append(Double(i) * Self.cloudSpacing)
        }
    }

    /// 丘のタイルそのもの（`hillBaseX` と対で、`sync` が毎フレーム位置を計算し直す）。
    private var hillTiles: [SKNode] = []
    /// 丘タイルの基準 x（雲と同じ「距離に応じて全タイル幅でループする」座標の仕組み）。
    private var hillBaseX: [Double] = []

    /// 地平線側の丘の稜線。縦長にした画面で地面から上の帯が広く空くぶん、
    /// 何も無い空の帯にせず奥・手前 2 段の丘で埋める（2026-09-10 会長QA「縦を活かす」対応）。
    /// ステージをまたいでも作り直さない（`rebuildCourse` の対象外）——雲と同じ理由。
    private func buildHills() {
        let count = 6
        for i in 0..<count {
            let tile = SKNode()
            // 奥の丘（背が高く、色が薄い＝遠い）。
            addHillBump(to: tile, color: RunnerPalette.hillFar, width: 42, height: 34, dx: 8)
            addHillBump(to: tile, color: RunnerPalette.hillFar, width: 36, height: 27, dx: 42)
            // 手前の丘（背が低く、色が濃い＝近い）。奥の丘に重ねて奥行きを出す。
            addHillBump(to: tile, color: RunnerPalette.hillNear, width: 34, height: 19, dx: 22)
            tile.position = CGPoint(x: Double(i) * Self.hillSpacing, y: 0)
            hillLayer.addChild(tile)
            hillTiles.append(tile)
            hillBaseX.append(Double(i) * Self.hillSpacing)
        }
    }

    /// 丘の山ひとつ。半分だけ地面から顔を出す楕円（下半分は `courseLayer` の地面に隠れる）。
    private func addHillBump(to tile: SKNode, color: UInt32, width: Double, height: Double, dx: Double) {
        let bump = SKShapeNode(ellipseOf: CGSize(width: width, height: height * 2))
        bump.fillColor = RunnerPalette.color(color)
        bump.strokeColor = .clear
        bump.position = CGPoint(x: dx, y: Metrics.groundY)
        tile.addChild(bump)
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
        // 新しい走行の頭（もう一度・はじめから等）。前回の落下演出が沈める・フェードして
        // 終わった見た目のままだと、次の挑戦の走者が透けた/縮んだ状態で始まってしまう。
        player.removeAllActions()
        player.alpha = 1
        player.xScale = 1
        player.yScale = 1
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
    private func addRock(_ hazard: RunnerHazard) {
        let node = SKNode()
        node.position = CGPoint(x: hazard.start, y: Metrics.groundY)
        let w = hazard.length, h = hazard.height

        // 接地の陰。岩の重みで地面に沈んでいるように、幅いっぱいの平たい楕円を敷く。
        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 1.05, height: h * 0.14))
        shadow.fillColor = RunnerPalette.color(RunnerPalette.rockDark)
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

        courseLayer.addChild(node)
    }

    /// 岩塊（ボルダー）1個。底が平らで頂がやや左に寄った角ばった多角形に、
    /// 日の当たる頂の面（明）と足元の陰の面（暗）を重ね、輪郭線なしで立体に見せる。
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
        body.fillColor = RunnerPalette.color(RunnerPalette.rockBody)
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
        top.fillColor = RunnerPalette.color(RunnerPalette.rockLight)
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
        shade.fillColor = RunnerPalette.color(RunnerPalette.rockDark)
        shade.strokeColor = .clear
        boulder.addChild(shade)

        node.addChild(boulder)
    }

    /// 鳥（`RunnerHazardKind.bird`）。「棒と穴しかない」というQAを受けて追加した敵の1つ
    /// （会長QA「鳥とか右から車が来るとか要素はいる」）。最初の実装は丸1つ+翼の細い矩形2枚
    /// だけで「何の生き物か分からない」という再QA（2026-09-10）を受け、尾・翼・胴・腹・頭・
    /// くちばし・目の7パーツに描き直した——シルエットで頭とくちばしが前（進行方向）、
    /// 尾が後ろに分かるようにする。丸と長方形が基本だが、翼・尾・くちばしは既存のゴール旗
    /// （`addGoalMarker`）と同じ「パスで描く三角形」の踏襲（#494 の権利チェックはこの2つの
    /// 形だけで新作品の意匠に寄せないことが要点で、パス自体は既に許容されている）。
    /// 当たり判定は `RunnerField.isHittingBlock` が岩と同じ `hazard.start`〜`.end`/`.height`
    /// の矩形で見ており、この見た目の変更とは独立している。
    private func addBird(_ hazard: RunnerHazard) {
        let node = SKNode()
        let w = hazard.length, h = hazard.height
        // 鳥は止まっている障害物で、追いかけても向かってもこない（会長への回答どおり）。
        // ただし走者は左から近づくので、頭・くちばしは**走者側（-x）**を向かせる。
        // 各パーツは元々 +x 側を頭にする前提で組んであるので、丸ごと左右反転させるだけで
        // 座標を1つずつ書き直さずに済む——ただし `xScale = -1` は自分のローカル原点
        // （= `hazard.start`）を軸に反転するので、そのままだと絵が当たり判定の外
        // （`hazard.start` より左）へはみ出す。原点を右へ `w` ぶんずらして帳尻を合わせる。
        node.position = CGPoint(x: hazard.start + w, y: Metrics.groundY)
        node.xScale = -1

        // 旧デザイン（胴の半径 1.6）は当たり判定の箱（4×7）の半分も使っておらず、
        // 走者（8×11）と並ぶと豆粒で「緑の塊」にしか見えなかった（会長QA 2026-09-10
        // 「鳥もデザイン改善して欲しい」）。岩と同じ教訓——**箱いっぱいに大きく**、
        // **シルエットで正体が分かるように**——を鳥にも適用する。
        // 横向きの「地面にとまった小鳥」として組み直す：足で接地させ（旧版は宙に
        // 浮いて見えた）、胴＋頭をひとつながりの丸いシルエットにし、畳んだ翼・
        // 段付きの尾羽・白目の入った目で読み取れるパーツだけを大きく描く。
        let bodyR = h * 0.36                                  // ≒2.5。箱の幅 4 に収まる最大級の丸
        let center = CGPoint(x: w * 0.5, y: bodyR + 0.9)      // 足の高さぶん持ち上げて接地させる

        // 尾羽（後方＝-x 側）。1枚の三角ではなく2枚ずらして重ね、「羽が重なっている」
        // 段差で鳥らしさを出す。奥の1枚は翼と同じ濃色にして厚みを見せる。
        let tailSpecs: [(dx: Double, dy: Double, len: Double, lift: Double, color: UInt32)] = [
            (0.2, 0.4, 2.6, 1.9, RunnerPalette.birdWing),
            (0.3, 0.0, 2.4, 1.2, RunnerPalette.birdBody),
        ]
        for spec in tailSpecs {
            let tailPath = CGMutablePath()
            tailPath.move(to: CGPoint(x: -bodyR * 0.5, y: 0))
            tailPath.addLine(to: CGPoint(x: -bodyR * 0.5 - spec.len, y: spec.lift + 0.9))
            tailPath.addLine(to: CGPoint(x: -bodyR * 0.5 - spec.len + 0.7, y: spec.lift - 0.6))
            tailPath.closeSubpath()
            let tail = SKShapeNode(path: tailPath)
            tail.fillColor = RunnerPalette.color(spec.color)
            tail.strokeColor = .clear
            tail.position = CGPoint(x: center.x + spec.dx, y: center.y + spec.dy)
            node.addChild(tail)
        }

        // 足（2本）。とまっている鳥だと一目で分かる最重要パーツ。くちばしと同じ
        // 暖色にして、地表のティール帯の上でも沈まないようにする。
        for legX in [center.x - 0.7, center.x + 0.7] {
            let leg = SKShapeNode(rectOf: CGSize(width: 0.35, height: 1.4))
            leg.fillColor = RunnerPalette.color(RunnerPalette.birdBeak)
            leg.strokeColor = .clear
            leg.position = CGPoint(x: legX, y: 0.7)
            node.addChild(leg)
        }

        // 胴体（大きい丸）。頭は別の丸を上前方に重ね、ひとつながりの丸いシルエットにする。
        let body = SKShapeNode(circleOfRadius: bodyR)
        body.fillColor = RunnerPalette.color(RunnerPalette.birdBody)
        body.strokeColor = .clear
        body.position = center
        node.addChild(body)

        let headRadius = bodyR * 0.66
        let head = CGPoint(x: center.x + bodyR * 0.62, y: center.y + bodyR * 0.72)
        let headNode = SKShapeNode(circleOfRadius: headRadius)
        headNode.fillColor = RunnerPalette.color(RunnerPalette.birdBody)
        headNode.strokeColor = .clear
        headNode.position = head
        node.addChild(headNode)

        // 腹（明るい差し色）。胴の下前方に置き、地面と接する側を明るくして
        // ティールの地表帯との境目も立てる。
        let belly = SKShapeNode(circleOfRadius: bodyR * 0.62)
        belly.fillColor = RunnerPalette.color(RunnerPalette.birdBelly)
        belly.strokeColor = .clear
        belly.position = CGPoint(x: center.x + bodyR * 0.25, y: center.y - bodyR * 0.42)
        node.addChild(belly)

        // 畳んだ翼（1枚・横向きなので見えるのは手前の1枚だけ）。胴より濃い色で
        // 面を分け、肩を軸にした小さな羽ばたきだけ残す（当たり判定は動かさない）。
        let shoulder = CGPoint(x: center.x + bodyR * 0.3, y: center.y + bodyR * 0.35)
        let wingPath = CGMutablePath()
        wingPath.move(to: .zero)
        wingPath.addLine(to: CGPoint(x: -bodyR * 1.5, y: -bodyR * 0.1))
        wingPath.addLine(to: CGPoint(x: -bodyR * 0.5, y: -bodyR * 0.95))
        wingPath.closeSubpath()
        let wing = SKShapeNode(path: wingPath)
        wing.fillColor = RunnerPalette.color(RunnerPalette.birdWing)
        wing.strokeColor = .clear
        wing.position = shoulder
        node.addChild(wing)
        let flap = SKAction.rotate(byAngle: 0.22, duration: 0.4)
        flap.timingMode = .easeInEaseOut
        wing.run(.repeatForever(.sequence([flap, flap.reversed()])))

        // くちばし（進行方向側の三角）。頭の大きさに比例させ、遠目でも尖りが分かる長さにする。
        let beakPath = CGMutablePath()
        beakPath.move(to: CGPoint(x: headRadius * 0.7, y: headRadius * 0.35))
        beakPath.addLine(to: CGPoint(x: headRadius * 1.9, y: -headRadius * 0.05))
        beakPath.addLine(to: CGPoint(x: headRadius * 0.7, y: -headRadius * 0.45))
        beakPath.closeSubpath()
        let beak = SKShapeNode(path: beakPath)
        beak.fillColor = RunnerPalette.color(RunnerPalette.birdBeak)
        beak.strokeColor = .clear
        beak.position = head
        node.addChild(beak)

        // 目。白目の上に黒目を重ねる。旧版は暗緑に暗色の点でほぼ見えなかった。
        let eyeWhite = SKShapeNode(circleOfRadius: headRadius * 0.34)
        eyeWhite.fillColor = RunnerPalette.color(RunnerPalette.birdBelly)
        eyeWhite.strokeColor = .clear
        eyeWhite.position = CGPoint(x: head.x + headRadius * 0.3, y: head.y + headRadius * 0.18)
        node.addChild(eyeWhite)

        let pupil = SKShapeNode(circleOfRadius: headRadius * 0.17)
        pupil.fillColor = RunnerPalette.color(RunnerPalette.birdEye)
        pupil.strokeColor = .clear
        // 進行方向（走者側）を見ている黒目。白目の中で少し前に寄せる。
        pupil.position = CGPoint(x: eyeWhite.position.x + headRadius * 0.12, y: eyeWhite.position.y)
        node.addChild(pupil)

        courseLayer.addChild(node)
    }

    /// スピードアップアイテム。最初の実装は細い矩形2枚で稲妻を表していたが小さすぎて
    /// 「何なのかパッと見てわからない」という再QA（2026-09-10）を受け、後光（丸）の上に
    /// 稲妻を1枚のパスで大きく描き直した。稲妻は速さ・電気を連想させる定番の記号で、
    /// キャラクターが「おじさん」であることに引きずられた案（ビール等）は倫理的に
    /// 採用しないという会長判断も踏まえ、キャラクター性に依存しない記号にしてある。
    /// 取得すると `sync` がフェードアウト＋縮小で消す。戻り値は `sync` が取得済みかどうかを
    /// 追うためのノード参照。
    @discardableResult
    private func addPickup(_ pickup: RunnerPickup) -> SKNode {
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

    /// 取得済みのピックアップをフェードアウト＋縮小で消す。
    private func removePickupNode(_ node: SKNode) {
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
        flag.strokeColor = .clear
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
        // 丘は雲より近く（速く）、コースより遠く（遅く）流す。仕組みは雲と同じ無限スクロール。
        let hillTotalWidth = Self.hillSpacing * Double(hillTiles.count)
        for (i, tile) in hillTiles.enumerated() {
            let raw = (hillBaseX[i] - field.distance * Self.hillParallax)
                .truncatingRemainder(dividingBy: hillTotalWidth)
            let wrapped = raw < 0 ? raw + hillTotalWidth : raw
            tile.position.x = wrapped
        }
        // 走者の画面上の x は動かさず、コースのほうを左へ流す。
        courseLayer.position = CGPoint(x: Metrics.playerX - field.distance, y: 0)
        if model.phase == .falling {
            // ミスした瞬間に `field` は凍る（`RunnerModel.tick` が `field.step` を呼ばなくなる）ので
            // 値は変わらない。最初のフレームだけ、ミスした瞬間の位置・向きへきっちり合わせてから
            // 演出を始める（以後 `player.position` / `.zRotation` はここでは触らず、演出の
            // `SKAction` に専有させる。毎フレーム上書きすると動きが打ち消される）。
            if lastSyncedPhase != .falling {
                player.position = CGPoint(x: Metrics.playerX, y: field.footY)
                player.zRotation = field.isGrounded ? 0 : CGFloat(max(-0.3, min(0.3, field.vy / 300)))
                playFallAnimation()
            }
        } else {
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
        lastSyncedPhase = model.phase
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

    /// 穴に落ちる/ぶつかった瞬間だけ流す演出（`.falling` に入った最初のフレームで 1 回発火）。
    ///
    /// 新規アセットは作らず、既存の丸と長方形だけの走者ノード（`player`）をそのまま
    /// 沈める・回す・フェードする。当たり判定・進行のタイミングは `RunnerModel` 側の
    /// `RunnerRules.fallDuration` が決めており、ここは見た目だけを作る。
    private func playFallAnimation() {
        player.removeAllActions()
        let duration = RunnerRules.fallDuration

        // 序盤から倒れ始める。`easeIn` は終盤に速度が乗る動きで、演出時間の前半は
        // ほとんど回っておらず「立ったまま」に見えていた（会長QA「穴の横に落ちて
        // 縦になってるように見える」・2026-09-10）。
        let topple = SKAction.rotate(byAngle: .pi * 0.85, duration: duration)
        topple.timingMode = .easeOut

        if model.field.isPit(at: model.field.distance) {
            // 穴の奈落は `Metrics.groundY` の深さまである（`addPitVoid`）。以前の沈み幅
            // （-3.5）はその1割ほどしかなく、穴の底へ落ちる前に演出が終わって
            // 「穴の横で止まっている」ように見えていた。奈落の深さに合わせて沈める。
            let sink = SKAction.moveBy(x: 0, y: -Metrics.groundY * 0.7, duration: duration)
            sink.timingMode = .easeIn
            let fade = SKAction.sequence([
                .wait(forDuration: duration * 0.25),
                .fadeAlpha(to: 0, duration: duration * 0.75),
            ])
            player.run(.group([sink, topple, fade]))
        } else {
            // 障害物への激突。足元に地面はあるので沈めず、その場でつんのめって倒れる。
            let jolt = SKAction.moveBy(x: -1.0, y: 0, duration: duration)
            jolt.timingMode = .easeOut
            let fade = SKAction.sequence([
                .wait(forDuration: duration * 0.5),
                .fadeAlpha(to: 0.35, duration: duration * 0.5),
            ])
            player.run(.group([jolt, topple, fade]))
        }
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
