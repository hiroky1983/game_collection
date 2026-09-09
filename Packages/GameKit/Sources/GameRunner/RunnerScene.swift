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
    /// おじさんの服。
    static let shirt: UInt32 = 0xB3A6F0
    /// ゴールの旗。
    static let goal: UInt32 = 0xFF8FB1
    /// 穴の縁の警告帯。地面と同系色だと縁が分からず、落ちるかどうかの判断がつかない
    /// というQAを受けて追加（会長QA）。
    static let pitEdge: UInt32 = 0xFFD447
    /// 雲。空より明るい半透明の白。
    static let cloud: UInt32 = 0xFFFFFF

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
    /// 空の雲。何も障害が無い区間が静止画に見える、というQAを受けて追加（会長QA）。
    /// コースより遅い速度で流す（視差）ので、コースとは別レイヤーに持つ。
    private let cloudLayer = SKNode()
    /// 雲を並べる間隔（ワールド単位）。地面を作り直しても雲は作り直さないので、
    /// ステージが変わっても同じ雲がそのまま流れ続ける。
    private static let cloudSpacing: Double = 46
    /// コースに対する雲の流れる速さの比率（視差）。1 未満で遠くに見える。
    private static let cloudParallax: Double = 0.3

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
    private func buildPlayer() {
        for wheel in [frontWheel, rearWheel] {
            wheel.fillColor = .clear
            wheel.strokeColor = RunnerPalette.color(RunnerPalette.wheel)
            wheel.lineWidth = 0.7
            player.addChild(wheel)
        }
        frontWheel.position = CGPoint(x: 2.6, y: 2.6)
        rearWheel.position = CGPoint(x: -2.6, y: 2.6)

        // 車体（前後の車輪をつなぐ棒とハンドル）。
        let frame = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.bike),
                                 size: CGSize(width: 7.4, height: 1.1))
        frame.position = CGPoint(x: 0, y: 4.2)
        let handle = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.bike),
                                  size: CGSize(width: 1.0, height: 2.4))
        handle.position = CGPoint(x: 2.6, y: 5.6)
        player.addChild(frame)
        player.addChild(handle)

        // 乗っているおじさん（胴・頭・帽子）。
        let torso = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.shirt),
                                 size: CGSize(width: 3.4, height: 3.6))
        torso.position = CGPoint(x: -0.6, y: 6.6)
        let head = SKShapeNode(circleOfRadius: 1.5)
        head.fillColor = RunnerPalette.color(RunnerPalette.skin)
        head.strokeColor = .clear
        head.position = CGPoint(x: 0.2, y: 9.6)
        let cap = SKSpriteNode(color: RunnerPalette.color(RunnerPalette.bike),
                               size: CGSize(width: 3.6, height: 0.9))
        cap.position = CGPoint(x: 0.2, y: 10.9)
        player.addChild(torso)
        player.addChild(head)
        player.addChild(cap)

        player.position = CGPoint(x: Metrics.playerX, y: Metrics.groundY)
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
            addPitEdgeMarkers(pit)
            x = pit.end
        }
        if x < stage.length { addGround(from: x, to: stage.length + Metrics.width) }

        for hazard in stage.hazards where hazard.kind != .pit {
            addRock(hazard)
        }

        addCheckpointMarker(at: stage.checkpoint)
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

    /// チェックポイントの目印（細い柱のみ。旗はゴールと見分けるために付けない）。
    private func addCheckpointMarker(at x: Double) {
        let pole = SKSpriteNode(
            color: RunnerPalette.color(RunnerPalette.groundTop),
            size: CGSize(width: 1, height: 9)
        )
        pole.anchorPoint = CGPoint(x: 0.5, y: 0)
        pole.position = CGPoint(x: x, y: Metrics.groundY)
        courseLayer.addChild(pole)
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
        // 空中では前のめりにする。跳んでいることが動きだけで分かるようにするため。
        player.zRotation = field.isGrounded ? 0 : CGFloat(max(-0.3, min(0.3, field.vy / 300)))
    }
}
