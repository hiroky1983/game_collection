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
    /// バー伸長のアイテム。`Theme.Fill.palette` の黄。
    static let itemWidePaddle: UInt32 = 0xFFC24B
    /// 球増加のアイテム。同じく `Theme.Fill.palette` の青緑。
    static let itemMultiBall: UInt32 = 0x22C3BE
    /// アイテムの中の印。**地と同じ濃い色**にして、明るい面の上で形がはっきり出るようにする
    /// （色が見分けにくくても、1 本のバーと 3 つの玉という形の違いで区別できる）。
    static let itemMark: UInt32 = 0x1E2233

    /// アイテムの地の色。
    static func itemColor(_ kind: BlocksItemKind) -> UInt32 {
        switch kind {
        case .widePaddle: return itemWidePaddle
        case .multiBall:  return itemMultiBall
        }
    }

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
/// シーンの座標系はフィールドの抽象単位そのまま（`BlocksField.Metrics.width` × `.height`）で、
/// `scaleMode = .aspectFit` により
/// 表示サイズへ一括で拡大される。**呼び出し側は SpriteView の枠を必ず同じ縦横比にすること**
/// （ずれると余白が出て、タップ位置とパドルの対応も狂う）。
@MainActor
final class BlocksScene: SKScene {
    private let model: BlocksModel
    private var lastUpdate: TimeInterval?
    /// ブロックのノードを作り直した時点の `BlocksModel.fieldGeneration`。
    private var renderedGeneration = -1

    /// 球のノード。**上限ぶん先に作って余りを隠す**（#599）。増えるたびに作ると、
    /// 球が増えた最初のフレームだけノードの生成が挟まって画が飛ぶ。
    private var ballNodes: [SKShapeNode] = []
    /// 落下中のアイテムのノード。種類ごとに見た目が違うので種類別に持つ。
    private var itemNodes: [BlocksItemKind: [SKNode]] = [:]
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
        paddleNode.fillColor = BlocksPalette.color(BlocksPalette.paddle)
        paddleNode.strokeColor = .clear
        addChild(blockLayer)
        addChild(paddleNode)
        for _ in 0..<BlocksRules.maxBalls {
            let node = SKShapeNode(circleOfRadius: CGFloat(BlocksField.Metrics.ballRadius))
            node.fillColor = BlocksPalette.color(BlocksPalette.ball)
            node.strokeColor = .clear
            node.isHidden = true
            ballNodes.append(node)
            addChild(node)
        }
        rebuildBlocks()
        sync()
    }

    /// 1 フレーム描き終えるたびに呼ぶ（#522）。
    ///
    /// 呼び出し側が描画ループを止めてよいかを判断する合図。**一度も描かないうちに止めると
    /// 盤ごと出ないまま暗い矩形になる**ので、止める側はこれを待つ。止まったあとは
    /// このフックも来なくなり、再開の判断は画面側の局面の変化が担う。
    var onFrameRendered: (() -> Void)?

    override func didFinishUpdate() {
        onFrameRendered?()
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        // 初回フレームは経過時間が測れないので進めない。
        guard let last = lastUpdate, currentTime > last else { return }
        let dt = currentTime - last
        // 描画ループを止めていたあいだ（#522 の `isPaused`）も `currentTime` は進み続ける。
        // 再開の 1 フレーム目には止まっていた時間がまるごと入り、`BlocksRules.maxStep` で
        // 刻んでも**そのフレームだけ 3 倍速で進む**。計時の穴とみなしてモデルは進めず、
        // 時計だけ合わせ直す。**描画は写す**（広告後のコンティニューのように、
        // 止まっているあいだに盤が作り直される経路がある）。
        guard dt <= BlocksRules.staleFrameThreshold else {
            sync()
            return
        }
        model.tick(dt: dt)
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
        for (index, node) in ballNodes.enumerated() {
            guard index < field.balls.count else {
                node.isHidden = true
                continue
            }
            node.isHidden = false
            node.position = CGPoint(x: field.balls[index].x, y: field.balls[index].y)
        }
        paddleNode.position = CGPoint(x: field.paddleX, y: BlocksField.Metrics.paddleY)
        // 伸長中は横だけ引き伸ばす（#599）。`SKShapeNode` は生成時の寸法を持つので、
        // 幅を変えるには拡大率を動かす。
        paddleNode.xScale = CGFloat(field.paddleWidth / BlocksField.Metrics.paddleWidth)
        syncItems(field.items)
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

    /// 落下中のアイテムをノードへ写す（#599）。
    ///
    /// 同時に落ちる数はブロックの壊れ方で決まり上限が無いので、足りなくなったら足して使い回す
    /// （毎フレーム作り直すと 60fps ぶんのノード生成が乗る）。
    private func syncItems(_ items: [BlocksItem]) {
        for kind in BlocksItemKind.allCases {
            let ofKind = items.filter { $0.kind == kind }
            var nodes = itemNodes[kind] ?? []
            while nodes.count < ofKind.count {
                let node = Self.makeItemNode(kind: kind)
                nodes.append(node)
                addChild(node)
            }
            for (index, node) in nodes.enumerated() {
                guard index < ofKind.count else {
                    node.isHidden = true
                    continue
                }
                node.isHidden = false
                node.position = CGPoint(x: ofKind[index].x, y: ofKind[index].y)
            }
            itemNodes[kind] = nodes
        }
    }

    /// アイテム 1 個ぶんのノード。
    ///
    /// **色だけで区別しない**。地の色に加えて、バー伸長は横 1 本の印、球増加は玉 3 つの印を
    /// 中に描く（色が見分けにくくても形で分かる）。
    private static func makeItemNode(kind: BlocksItemKind) -> SKNode {
        let width = BlocksField.Metrics.itemWidth
        let height = BlocksField.Metrics.itemHeight
        let body = SKShapeNode(
            rectOf: CGSize(width: width, height: height),
            cornerRadius: CGFloat(height / 2)
        )
        body.fillColor = BlocksPalette.color(BlocksPalette.itemColor(kind))
        body.strokeColor = .clear
        // ブロックより手前に置く（落ちてくる途中でブロックの列と重なる）。
        body.zPosition = 1
        let mark = BlocksPalette.color(BlocksPalette.itemMark)
        switch kind {
        case .widePaddle:
            let bar = SKSpriteNode(
                color: mark,
                size: CGSize(width: width * 0.62, height: height * 0.26)
            )
            body.addChild(bar)
        case .multiBall:
            for offset in [-1.0, 0, 1.0] {
                let dot = SKShapeNode(circleOfRadius: CGFloat(height * 0.17))
                dot.fillColor = mark
                dot.strokeColor = .clear
                dot.position = CGPoint(x: offset * width * 0.22, y: 0)
                body.addChild(dot)
            }
        }
        return body
    }
}
