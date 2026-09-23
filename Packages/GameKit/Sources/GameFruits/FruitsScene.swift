import Core
import Foundation
import SpriteKit

/// SpriteKit の面の配色（#1319）。
///
/// **SpriteKit の面は SwiftUI の `Theme` に追従しない**（ブロック崩し #463 と同じ）。盤・駒・牌と同じ
/// 「モードによらず固定の面」として扱い、値は `Theme.Hex` から取って揃える。
enum FruitsPalette {
    /// 箱の地。アプリの背景（クリーム）より少し濃くして、果物の明るい色を浮かせる。
    static let box: UInt32 = 0xF6E7CF
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

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> SKColor {
        SKColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// くっつきフルーツの描画とゲームループ（#1319）。
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
    /// 手に持っている果物のノード。種類が変わるたびにテクスチャを差し替えて使い回す。
    private let heldNode = SKSpriteNode()
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
    private var renderedWarning = false

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
        deadlineNode.lineWidth = 0.7
        deadlineNode.zPosition = 1
        addChild(deadlineNode)

        guideNode.lineWidth = 0.5
        guideNode.strokeColor = FruitsPalette.color(FruitsPalette.guide, alpha: 0.45)
        guideNode.zPosition = 1
        addChild(guideNode)

        heldNode.zPosition = 3
        addChild(heldNode)
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
                // 合体で生まれた果物は少し小さく出て膨らむ。落とした果物も同じ経路で出るが、
                // 落とし始めは手の果物と同じ大きさなので違和感は無い。
                if !reduceMotion, fruit.age == 0 {
                    node.setScale(0.7)
                    node.run(.scale(to: 1, duration: 0.14))
                }
            }
            node.position = CGPoint(x: fruit.x, y: fruit.y)
            node.zRotation = CGFloat(fruit.angle)
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
        if let kind = model.heldKind {
            heldNode.isHidden = false
            heldNode.texture = texture(for: kind)
            heldNode.size = spriteSize(for: kind)
            heldNode.position = CGPoint(x: field.cursorX, y: FruitField.Metrics.spawnY)
        } else {
            heldNode.isHidden = true
        }
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
        guard warning != renderedWarning || deadlineNode.strokeColor == .clear else { return }
        renderedWarning = warning
        deadlineNode.strokeColor = warning
            ? FruitsPalette.color(FruitsPalette.deadlineWarning)
            : FruitsPalette.color(FruitsPalette.deadline, alpha: 0.6)
        deadlineNode.lineWidth = warning ? 1.1 : 0.7
    }

    /// 合体・消滅の輪。モデルが積んだ合図のうち、まだ描いていないものを描く。
    private func syncEffects() {
        let reduceMotion = Motion.isReduceMotionEnabled
        for effect in model.effects where effect.serial > consumedEffectSerial {
            consumedEffectSerial = effect.serial
            guard !reduceMotion else { continue }
            let radius: Double
            switch effect.kind {
            case .merge(let kind): radius = kind.radius
            case .vanish:          radius = FruitKind.melon.radius
            }
            let ring = SKShapeNode(circleOfRadius: radius)
            ring.position = CGPoint(x: effect.x, y: effect.y)
            ring.strokeColor = FruitsPalette.color(FruitsPalette.ring, alpha: 0.9)
            ring.lineWidth = 1.2
            ring.fillColor = .clear
            ring.zPosition = 4
            addChild(ring)
            ring.run(.sequence([.group([.scale(to: 1.6, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        }
    }

    // MARK: - ノード

    private func makeFruitNode(_ kind: FruitKind) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture(for: kind))
        node.size = spriteSize(for: kind)
        node.zPosition = 2
        return node
    }

    /// 見た目の一辺。茎・葉のぶん円より大きい（`FruitArt.canvasScale`）。
    private func spriteSize(for kind: FruitKind) -> CGSize {
        let side = kind.radius * 2 * FruitArt.canvasScale
        return CGSize(width: side, height: side)
    }

    /// 種類ごとのテクスチャ。大きい果物ほど高い解像度で描く（iPad ではメロンが 300pt を超える）。
    private func texture(for kind: FruitKind) -> SKTexture? {
        if let cached = textures[kind] { return cached }
        let pixels = kind.radius >= FruitKind.kiwi.radius ? 512 : 256
        guard let image = FruitArtCache.image(kind, pixels: pixels) else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        textures[kind] = texture
        return texture
    }
}
