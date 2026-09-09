import Foundation
import SpriteKit

/// SpriteKit の描画・配色（#463）。
///
/// **SpriteKit の面は SwiftUI の `Theme` に追従しない**（`SKColor` はライト / ダークの動的色を
/// 持てる形で使えず、シーンの背景も自前で塗る）。盤・駒・牌と同じ「モードによらず固定の面」
/// として扱い、その上に載せる文字・図形も固定色で組む（`Theme.Fixed` と同じ考え方）。
enum BlocksPalette {
    /// プレイフィールドの地。暗い紺にして、その上のポップな差し色を目立たせる。
    static let field: UInt32 = 0x1E2233
    /// パドル。`Theme.Fill.coral` と同じ値。
    static let paddle: UInt32 = 0xFF8A7E
    /// 球。`Theme.Hex.background`（クリーム）と同じ値。
    static let ball: UInt32 = 0xFFF6EC
    /// 壊れないブロック。地に近い彩度の低い色で「触っても無駄」と分かるようにする。
    static let solid: UInt32 = 0x4A5068
    /// 硬いブロック（2 回ぶん残っている）。
    static let hardFull: UInt32 = 0x8E99BC
    /// 硬いブロック（あと 1 回）。明るくして「あと一撃」を色で伝える。
    static let hardCracked: UInt32 = 0xD3DAEE

    /// 通常ブロックの段ごとの色。`Theme.Fill.palette` と同じ 5 色を上から順に使う。
    static let normalRows: [UInt32] = [0xFF8A7E, 0xFFC24B, 0x22C3BE, 0xB3A6F0, 0xFF8FB1]

    static func color(_ hex: UInt32) -> SKColor {
        SKColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// 1 ブロックの色。行は上から数える。
    static func blockColor(_ block: Block, row: Int) -> SKColor {
        switch block.kind {
        case .solid:
            return color(solid)
        case .hard:
            return color(block.remaining == 1 ? hardCracked : hardFull)
        case .normal:
            return color(normalRows[row % normalRows.count])
        }
    }
}

/// ブロック崩しの描画とゲームループ（#463）。
///
/// **ここにゲームのルールは無い**。毎フレーム `BlocksModel.tick(dt:)` を呼び、
/// 結果として決まった `BlocksField` の状態をノードへ写すだけの層で、
/// 得点・残機・当たり判定は一切知らない（アクション枠の基盤規約）。
///
/// シーンの座標系はフィールドの抽象単位そのまま（100 × 150）で、`scaleMode = .aspectFit` により
/// 表示サイズへ一括で拡大される。**呼び出し側は SpriteView の枠を必ず同じ縦横比にすること**
/// （ずれると余白が出て、タップ位置とパドルの対応も狂う）。
@MainActor
final class BlocksScene: SKScene {
    private let model: BlocksModel
    private var lastUpdate: TimeInterval?
    /// ブロックのノードを作り直した時点の `BlocksModel.fieldGeneration`。
    private var renderedGeneration = -1

    private let ballNode = SKShapeNode(circleOfRadius: CGFloat(BlocksField.Metrics.ballRadius))
    private let paddleNode = SKShapeNode(
        rectOf: CGSize(
            width: BlocksField.Metrics.paddleWidth,
            height: BlocksField.Metrics.paddleHeight
        ),
        cornerRadius: CGFloat(BlocksField.Metrics.paddleHeight / 2)
    )
    private let blockLayer = SKNode()
    private var blockNodes: [[SKSpriteNode?]] = []

    init(model: BlocksModel) {
        self.model = model
        super.init(size: CGSize(
            width: BlocksField.Metrics.width,
            height: BlocksField.Metrics.height
        ))
        scaleMode = .aspectFit
        backgroundColor = BlocksPalette.color(BlocksPalette.field)
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BlocksScene はコードからのみ生成する")
    }

    override func didMove(to view: SKView) {
        guard blockLayer.parent == nil else { return }
        ballNode.fillColor = BlocksPalette.color(BlocksPalette.ball)
        ballNode.strokeColor = .clear
        paddleNode.fillColor = BlocksPalette.color(BlocksPalette.paddle)
        paddleNode.strokeColor = .clear
        addChild(blockLayer)
        addChild(paddleNode)
        addChild(ballNode)
        rebuildBlocks()
        sync()
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        // 初回フレームは経過時間が測れないので進めない。
        guard let last = lastUpdate, currentTime > last else { return }
        model.tick(dt: currentTime - last)
        sync()
    }

    /// ステージが変わったらブロックのノードを作り直す。
    private func rebuildBlocks() {
        blockLayer.removeAllChildren()
        blockNodes = []
        let field = model.field
        for row in 0..<field.rowCount {
            var nodes: [SKSpriteNode?] = []
            for column in 0..<BlocksField.Metrics.columns {
                guard let block = field.block(row: row, column: column) else {
                    nodes.append(nil)
                    continue
                }
                let rect = BlocksField.blockRect(row: row, column: column)
                // 隣どうしが地続きに見えないよう、実寸より少しだけ小さく描く（当たり判定は実寸のまま）。
                let node = SKSpriteNode(
                    color: BlocksPalette.blockColor(block, row: row),
                    size: CGSize(
                        width: BlocksField.Metrics.blockWidth - 0.6,
                        height: BlocksField.Metrics.blockHeight - 0.6
                    )
                )
                node.position = CGPoint(x: rect.midX, y: rect.midY)
                blockLayer.addChild(node)
                nodes.append(node)
            }
            blockNodes.append(nodes)
        }
        renderedGeneration = model.fieldGeneration
    }

    /// モデルの状態をノードへ写す。
    private func sync() {
        if renderedGeneration != model.fieldGeneration {
            rebuildBlocks()
        }
        let field = model.field
        ballNode.position = CGPoint(x: field.ball.x, y: field.ball.y)
        paddleNode.position = CGPoint(x: field.paddleX, y: BlocksField.Metrics.paddleY)
        for (row, nodes) in blockNodes.enumerated() {
            for (column, node) in nodes.enumerated() {
                guard let node else { continue }
                guard let block = field.block(row: row, column: column) else {
                    node.isHidden = true
                    continue
                }
                node.isHidden = false
                // 硬いブロックは残り耐久で色が変わる。毎フレーム代入しても
                // 同じ色なら SpriteKit 側で描画は変わらない。
                node.color = BlocksPalette.blockColor(block, row: row)
            }
        }
    }
}
