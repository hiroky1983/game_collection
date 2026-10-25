import Core
import Foundation
import SpriteKit

/// SpriteKit の面の配色（#1319）。
///
/// **SpriteKit の面は SwiftUI の `Theme` に追従しない**（ブロック崩し #463 と同じ）。盤・駒・牌と同じ
/// 「モードによらず固定の面」として扱い、値は `Theme.Hex` から取って揃える。
enum FruitsPalette {
    /// 庭（箱）の地。砂利の色（#2361）。アプリの背景（クリーム）より少し灰色寄りにして、盆栽の色を浮かせる。
    static let box: UInt32 = 0xEFE7D3
    /// 砂利の箒目（ほうきめ）の線。
    static let rake: UInt32 = 0xDCD0B6
    /// 砂利の中の石。
    static let stone: UInt32 = 0xC9BEA8
    /// 縁側の板（SwiftUI 側の `BonsaiEngawaBoards` が使う）。
    static let wood: UInt32 = 0xC89E6B
    static let woodDark: UInt32 = 0xA87D4E
    static let woodLight: UInt32 = 0xD9B484
    /// 箱の縁。`Theme.Hex.fillMuted` のライト側。
    static let boxEdge: UInt32 = Theme.Hex.fillMuted.light
    /// 危険線（通常）。`Theme.Hex.inkSub` のライト側。
    static let deadline: UInt32 = Theme.Hex.inkSub.light
    /// 危険線（果物が掛かっている）。`Theme.Hex.coral`。
    static let deadlineWarning: UInt32 = Theme.Hex.coral
    /// 落とす位置の案内線。
    static let guide: UInt32 = Theme.Hex.inkSub.light
    /// 合体の輪。
    static let ring: UInt32 = 0xFFFFFF
    /// 金の松ができた瞬間の祝いの輪と火花（#2865）。
    static let gold: UInt32 = 0xFFC83D

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> SKColor {
        SKColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// おじさんの盆栽（#2361。もとは くっつきフルーツ #1319）の庭（盤）の描画とゲームループ。
///
/// 盆栽は**回転させない**（会長決裁 2026-10-17。物理の円が転がっても鉢は傾けない）。絵の置き方は
/// `BonsaiArt.spriteFrame`（絵の全体が当たり判定の円の内側に収まる）。手に持っている盆栽は
/// ここでは描かず、縁側のおじさん（SwiftUI 側の `BonsaiOjisanLayer`）が持つ。
///
/// **ここにゲームのルールは無い**。毎フレーム `FruitsModel.tick(dt:)` を呼び、結果として決まった
/// `FruitField` の状態をノードへ写すだけの層で、得点・合体の条件・終局は一切知らない
/// （アクション枠の基盤規約・`docs/action-game-foundation.md`）。
///
/// シーンの座標系は盤の抽象単位そのまま（`FruitField.Metrics.width` × `.height`）で、
/// `scaleMode = .aspectFit` により表示サイズへ一括で拡大される。**呼び出し側は SpriteView の枠を必ず
/// 同じ縦横比にすること**（ずれると余白が出て、タップ位置と落とす位置の対応も狂う）。
@MainActor
final class FruitsScene: SKScene {
    private let model: FruitsModel
    private var lastUpdate: TimeInterval?
    /// 盤の果物のノード（`Fruit.id` → ノード）。
    private var fruitNodes: [Int: SKSpriteNode] = [:]
    /// 落とす位置の案内線。
    private let guideNode = SKShapeNode()
    private let deadlineNode = SKShapeNode()
    private var textures: [FruitKind: SKTexture] = [:]
    /// 描画済みの `FruitsModel.gameSerial`。変わったら果物のノードを全部捨てる。
    private var renderedGameSerial = -1
    /// 拾い終えた演出の合図の通し番号。
    private var consumedEffectSerial = -1
    /// 案内線を最後に描いた x。毎フレーム作り直さないため。
    private var renderedGuideX: Double = -1
    /// 描画済みの危険線の状態（警告か）。nil は「まだ一度も塗っていない」。
    /// `SKColor` の比較は色空間違いで一致しないので、色ではなくこの値で判定する。
    private var renderedWarning: Bool?

    /// 1 フレーム描き終えるたびに呼ぶ（#522）。呼び出し側が描画ループを止めてよいかを判断する合図。
    var onFrameRendered: (() -> Void)?
    /// 一度でも描いたか。**一度も描かないうちに止めると盤が出ないまま暗い矩形になる**ので、
    /// 止める側はこれが true になるまで待つ（撮影用の `-simulateFruits gameover` で実測）。
    private(set) var hasRenderedFrame = false

    init(model: FruitsModel) {
        self.model = model
        super.init(size: CGSize(width: FruitField.Metrics.width, height: FruitField.Metrics.height))
        scaleMode = .aspectFit
        backgroundColor = FruitsPalette.color(FruitsPalette.box)
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FruitsScene はコードからのみ生成する")
    }

    override func didMove(to view: SKView) {
        guard deadlineNode.parent == nil else { return }
        addGarden()
        // 箱の縁。
        let edge = SKShapeNode(rect: CGRect(x: 0.4, y: 0.4, width: FruitField.Metrics.width - 0.8, height: FruitField.Metrics.height - 0.8))
        edge.strokeColor = FruitsPalette.color(FruitsPalette.boxEdge, alpha: 0.6)
        edge.lineWidth = 0.8
        edge.fillColor = .clear
        edge.zPosition = 0.5
        addChild(edge)

        // 危険線（点線）。
        let dashed = CGMutablePath()
        dashed.move(to: CGPoint(x: 0, y: FruitField.Metrics.deadlineY))
        dashed.addLine(to: CGPoint(x: FruitField.Metrics.width, y: FruitField.Metrics.deadlineY))
        deadlineNode.path = dashed.copy(dashingWithPhase: 0, lengths: [2.2, 1.6])
        deadlineNode.zPosition = 1
        addChild(deadlineNode)
        // `SKShapeNode` の既定の線は不透明の白で、地（クリーム）とほぼ見分けが付かない。ここで通常色を塗る
        // （`sync()` が塗るのは状態が変わったときだけ）。
        applyDeadlineStyle(warning: false)

        guideNode.lineWidth = 0.5
        guideNode.strokeColor = FruitsPalette.color(FruitsPalette.guide, alpha: 0.45)
        guideNode.zPosition = 1
        addChild(guideNode)

        sync()
    }

    override func didFinishUpdate() {
        hasRenderedFrame = true
        onFrameRendered?()
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        // 初回フレームは経過時間が測れないので進めない。
        guard let last = lastUpdate, currentTime > last else { return }
        let dt = currentTime - last
        // 描画ループを止めていたあいだ（終局の幕・背景に回ったとき）も `currentTime` は進み続ける。
        // 再開の 1 フレーム目には止まっていた時間がまるごと入るので、モデルは進めず時計だけ合わせ直す
        // （ブロック崩し #522 と同じ）。描画は写す（コンティニューで盤が片づく経路がある）。
        guard dt <= FruitsModel.staleFrameThreshold else {
            sync()
            return
        }
        model.tick(dt: dt)
        sync()
    }

    // MARK: - 写す

    /// モデルの状態をノードへ写す。
    private func sync() {
        if renderedGameSerial != model.gameSerial {
            for node in fruitNodes.values { node.removeFromParent() }
            fruitNodes = [:]
            renderedGameSerial = model.gameSerial
            consumedEffectSerial = model.effects.last?.serial ?? -1
        }
        syncFruits()
        syncHeld()
        syncDeadline()
        syncEffects()
    }

    private func syncFruits() {
        let reduceMotion = Motion.isReduceMotionEnabled
        var present = Set<Int>()
        for fruit in model.field.fruits {
            present.insert(fruit.id)
            let node: SKSpriteNode
            if let existing = fruitNodes[fruit.id] {
                node = existing
            } else {
                node = makeFruitNode(fruit.kind)
                fruitNodes[fruit.id] = node
                addChild(node)
                // 合体で生まれた果物は少し小さく出て膨らむ。「このフレームで生まれた」は年齢が 1 フレーム以内か
                // で見る（`FruitField.step` は年齢を進めてから合体を適用するので、同じフレームの後半の
                // サブステップで生まれた果物の年齢はぴったり 0 にならない）。落とした果物も同じ経路で出るが、
                // 落とし始めは手の果物と同じ大きさなので違和感は無い。
                if !reduceMotion, fruit.age <= FruitsModel.maxStep {
                    node.setScale(0.7)
                    node.run(.scale(to: 1, duration: 0.14))
                }
            }
            // 絵を囲む円の中心（anchorPoint）を当たり判定の円の中心に置く。`fruit.angle` は使わない（回転させない）。
            node.position = CGPoint(x: fruit.x, y: fruit.y)
            // 小さい盆栽ほど前に重ねる（#2388。大きい盆栽の木の陰に小さい盆栽が隠れない）。
            node.zPosition = Self.zPosition(for: fruit.kind, bottomY: fruit.y - fruit.radius)
        }
        for (id, node) in fruitNodes where !present.contains(id) {
            fruitNodes.removeValue(forKey: id)
            if reduceMotion {
                node.removeFromParent()
            } else {
                node.run(.sequence([.group([.fadeOut(withDuration: 0.1), .scale(to: 1.15, duration: 0.1)]), .removeFromParent()]))
            }
        }
    }

    private func syncHeld() {
        let field = model.field
        // 手に持っている盆栽は縁側のおじさんが持つ（SwiftUI 側）。ここは案内線だけ。
        // 案内線は手が空でも出す（次の果物をどこへ落とすか狙えるように）。終局の幕の裏では消す。
        guideNode.isHidden = model.phase != .playing
        if renderedGuideX != field.cursorX {
            renderedGuideX = field.cursorX
            let path = CGMutablePath()
            path.move(to: CGPoint(x: field.cursorX, y: 0.6))
            path.addLine(to: CGPoint(x: field.cursorX, y: FruitField.Metrics.spawnY))
            guideNode.path = path.copy(dashingWithPhase: 0, lengths: [1.6, 1.6])
        }
    }

    private func syncDeadline() {
        let warning = model.isOverLine
        guard warning != renderedWarning else { return }
        applyDeadlineStyle(warning: warning)
    }

    /// 危険線の色と太さ。果物が掛かっているあいだは赤く太くする。
    private func applyDeadlineStyle(warning: Bool) {
        renderedWarning = warning
        deadlineNode.strokeColor = warning
            ? FruitsPalette.color(FruitsPalette.deadlineWarning)
            : FruitsPalette.color(FruitsPalette.deadline, alpha: 0.6)
        deadlineNode.lineWidth = warning ? 1.1 : 0.7
    }

    /// 危険線が警告色か（テスト用）。
    var isDeadlineWarning: Bool? { renderedWarning }

    /// 合体・消滅の輪。モデルが積んだ合図のうち、まだ描いていないものを描く。
    private func syncEffects() {
        let reduceMotion = Motion.isReduceMotionEnabled
        for effect in model.effects where effect.serial > consumedEffectSerial {
            consumedEffectSerial = effect.serial
            guard !reduceMotion else { continue }
            let radius: Double
            switch effect.kind {
            case .merge(let kind): radius = kind.radius
            case .vanish:          radius = FruitKind.kinmatsu.radius
            }
            let ring = SKShapeNode(circleOfRadius: radius)
            ring.position = CGPoint(x: effect.x, y: effect.y)
            ring.strokeColor = FruitsPalette.color(FruitsPalette.ring, alpha: 0.9)
            ring.lineWidth = 1.2
            ring.fillColor = .clear
            ring.zPosition = 4
            addChild(ring)
            ring.run(.sequence([.group([.scale(to: 1.6, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
            if effect.kind == .merge(.kinmatsu) {
                celebrateKinmatsu(at: CGPoint(x: effect.x, y: effect.y))
            }
        }
    }

    /// 金の松ができた瞬間だけの演出（#2865）。金色の輪を 2 重に広げ、火花を放射状に散らす。
    /// 合体の輪（白・`zPosition` 4）より前に出す。Reduce Motion では呼ばれない（`syncEffects` が先に抜ける）。
    private func celebrateKinmatsu(at center: CGPoint) {
        let base = FruitKind.kinmatsu.radius
        for (index, scale) in [2.4, 3.4].enumerated() {
            let ring = SKShapeNode(circleOfRadius: base)
            ring.position = center
            ring.strokeColor = FruitsPalette.color(FruitsPalette.gold)
            ring.lineWidth = 2.2
            ring.fillColor = .clear
            ring.zPosition = 5
            addChild(ring)
            ring.run(.sequence([
                .wait(forDuration: 0.08 * Double(index)),
                .group([.scale(to: scale, duration: 0.5), .fadeOut(withDuration: 0.5)]),
                .removeFromParent(),
            ]))
        }
        let sparkCount = 12
        for index in 0..<sparkCount {
            let angle = Double(index) / Double(sparkCount) * 2 * .pi
            let spark = SKShapeNode(circleOfRadius: 1.4)
            spark.position = center
            spark.fillColor = FruitsPalette.color(FruitsPalette.gold)
            spark.strokeColor = .clear
            spark.zPosition = 5
            addChild(spark)
            let distance = base * 2.2
            let move = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.6)
            move.timingMode = .easeOut
            spark.run(.sequence([.group([move, .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
        }
    }

    // MARK: - ノード

    private func makeFruitNode(_ kind: FruitKind) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture(for: kind))
        node.size = BonsaiArt.spriteSize(for: kind)
        // 絵を囲む円の中心を基準にする（円の中心に置く・`BonsaiArt.spriteFrame`）。
        node.anchorPoint = BonsaiArt.anchor(for: kind)
        return node
    }

    /// 盆栽の重なり順（#2388）。**小さい段ほど前**に描く。絵が当たり判定の円より大きかった（木が上へはみ出した）
    /// ころ、大きい盆栽の上に小さい盆栽が載ると、鉢の底の高さで重ねていたときは小さいほうが大きい木の陰に隠れた。
    /// 今は絵が円の内側に収まるが、円が少し重なったときに小さい盆栽が前なら小さい盆栽は全部見える。
    /// 同じ段どうしは鉢の底が低い（手前の）ものを前にする。2〜3 の範囲に収め、危険線（1）より前・合体の輪（4）より奥。
    static func zPosition(for kind: FruitKind, bottomY: Double) -> CGFloat {
        let tiers = Double(FruitKind.allCases.count - 1)
        // 段の帯: 金の松 2.0 → 桜 2.9（帯の幅 0.09）。帯の中で鉢の底の高さぶん 0〜0.08 を足す。
        let band = 2 + 0.9 * (1 - Double(kind.rawValue) / tiers)
        let depth = min(max(bottomY / FruitField.Metrics.height, 0), 1)
        return CGFloat(band + 0.08 * (1 - depth))
    }

    /// 盆栽のノード（テスト用）。`Fruit.id` で引く。
    func node(forFruit id: Int) -> SKSpriteNode? { fruitNodes[id] }

    /// 庭の砂利。箒目（横の線）と石を少し。盆栽より奥（`zPosition` 0.1〜0.2）。
    private func addGarden() {
        let rake = CGMutablePath()
        for y in stride(from: 4.0, to: FruitField.Metrics.height, by: 4.0) {
            rake.move(to: CGPoint(x: 0, y: y))
            rake.addLine(to: CGPoint(x: FruitField.Metrics.width, y: y))
        }
        let rakeNode = SKShapeNode(path: rake)
        rakeNode.strokeColor = FruitsPalette.color(FruitsPalette.rake, alpha: 0.7)
        rakeNode.lineWidth = 0.35
        rakeNode.zPosition = 0.1
        addChild(rakeNode)
        for (x, y, r) in [(12.0, 6.0, 3.6), (86.0, 4.5, 2.8), (50.0, 2.5, 2.2)] {
            let stone = SKShapeNode(ellipseOf: CGSize(width: r * 2, height: r * 1.2))
            stone.position = CGPoint(x: x, y: y)
            stone.fillColor = FruitsPalette.color(FruitsPalette.stone)
            stone.strokeColor = .clear
            stone.zPosition = 0.2
            addChild(stone)
        }
    }

    /// 段ごとのテクスチャ（`BonsaiArt` の PNG をそのまま使う）。
    private func texture(for kind: FruitKind) -> SKTexture? {
        if let cached = textures[kind] { return cached }
        guard let image = BonsaiArt.image(kind) else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        textures[kind] = texture
        return texture
    }
}
