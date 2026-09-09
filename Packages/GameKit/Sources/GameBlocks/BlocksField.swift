import Foundation

/// 球の位置と速度。
public struct BlocksBall: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double

    public init(x: Double, y: Double, vx: Double = 0, vy: Double = 0) {
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
    }

    public var speed: Double { (vx * vx + vy * vy).squareRoot() }
    /// 動いているか（発射前は停止している）。
    public var isMoving: Bool { speed > 0 }
}

/// ブロック崩しの盤面そのもの（#463）。
///
/// **SpriteKit にも SwiftUI にも依存しない値型**で、`step(dt:)` を呼ぶと球が進む。
/// 得点・残機・ステージ進行は持たない（それは `BlocksModel` の仕事）。
/// この分離があるおかげで、当たり判定・反射・耐久・すり抜けをシミュレータ無しで検証できる。
///
/// 座標系は**左下が原点**（SpriteKit と同じ向き）で、単位はフィールド固有の抽象単位。
/// 画面 pt への変換は `BlocksScene` が `scaleMode = .aspectFit` で一括して行う。
public struct BlocksField: Equatable, Sendable {
    /// 盤の寸法。すべて抽象単位（`Metrics.width` × `Metrics.height` の枠に収まる）。
    public enum Metrics {
        public static let width: Double = 100
        public static let height: Double = 150
        /// ブロックの列数。ステージのレイアウト文字列の 1 行の長さでもある。
        public static let columns = 9
        public static let blockHeight: Double = 5
        /// 最上段のブロックの上と天井のあいだの余白。
        public static let topMargin: Double = 14
        public static let ballRadius: Double = 2
        public static let paddleWidth: Double = 17
        public static let paddleHeight: Double = 2.6
        /// パドルの中心の高さ。
        public static let paddleY: Double = 10

        public static var blockWidth: Double { width / Double(columns) }
        public static var paddleHalfWidth: Double { paddleWidth / 2 }
        public static var paddleTop: Double { paddleY + paddleHeight / 2 }
        /// 発射前に球が乗っている高さ。
        public static var restingBallY: Double { paddleTop + ballRadius }

        /// 反射角の下限（速さに対する `|vy|` の比）。sin(15°) ≒ 0.2588。
        public static let minimumVerticalRatio: Double = 0.26
        /// パドルの端で跳ね返るときの最大角（垂直から測る）。
        public static let maxPaddleAngle: Double = .pi / 3
        /// 発射時の角度（垂直から測る）。乱数を使わないので、同じ操作からは常に同じ軌道になる。
        public static let launchOffset: Double = 0.35
    }

    /// 上の行から順に並べたブロック。nil は空きマス。
    public private(set) var blocks: [[Block?]]
    /// パドル中心の x。`movePaddle(to:)` で動かす（範囲外は自動で丸める）。
    public private(set) var paddleX: Double
    public private(set) var ball: BlocksBall
    /// このステージでの球の速さ。発射・パドル反射のたびにこの値へ揃える。
    public private(set) var speed: Double

    public init(stage: BlocksStage, speed: Double) {
        self.blocks = stage.makeBlocks()
        self.paddleX = Metrics.width / 2
        self.speed = speed
        self.ball = BlocksBall(x: Metrics.width / 2, y: Metrics.restingBallY)
    }

    // MARK: - 盤面の問い合わせ

    public var rowCount: Int { blocks.count }

    public func block(row: Int, column: Int) -> Block? {
        guard row >= 0, row < blocks.count, column >= 0, column < Metrics.columns else { return nil }
        return blocks[row][column]
    }

    /// 壊せるブロックの残数。0 ならステージクリア。
    public var remainingBreakableCount: Int {
        var count = 0
        for row in blocks {
            for cell in row where cell?.isBreakable == true {
                count += 1
            }
        }
        return count
    }

    /// ステージをクリアしたか（壊せるブロックが 1 つも残っていない）。
    public var isCleared: Bool { remainingBreakableCount == 0 }

    /// ブロック 1 個ぶんの矩形。行は上から数える（row 0 が最上段）。
    public static func blockRect(row: Int, column: Int) -> BlocksPhysics.Rect {
        let top = Metrics.height - Metrics.topMargin - Double(row) * Metrics.blockHeight
        let minX = Double(column) * Metrics.blockWidth
        return BlocksPhysics.Rect(
            minX: minX,
            maxX: minX + Metrics.blockWidth,
            minY: top - Metrics.blockHeight,
            maxY: top
        )
    }

    // MARK: - 操作

    /// パドルを動かす。盤の外へは出ない。
    public mutating func movePaddle(to x: Double) {
        let half = Metrics.paddleHalfWidth
        paddleX = min(Metrics.width - half, max(half, x))
        // 発射前の球はパドルに乗せたまま一緒に動かす。
        if !ball.isMoving {
            ball.x = paddleX
            ball.y = Metrics.restingBallY
        }
    }

    /// 球を発射する。すでに動いていれば何もしない。
    public mutating func launch() {
        guard !ball.isMoving else { return }
        let velocity = BlocksPhysics.paddleBounce(offset: Metrics.launchOffset, speed: speed)
        ball.vx = velocity.vx
        ball.vy = velocity.vy
    }

    /// 球をパドルの上へ戻す（1 機失ったあと）。
    public mutating func resetBall() {
        ball = BlocksBall(x: paddleX, y: Metrics.restingBallY)
    }

    /// 球の速さを変える（ゆっくりモードの切り替え）。**向きは保ったまま**速さだけ差し替える。
    public mutating func setSpeed(_ newSpeed: Double) {
        speed = newSpeed
        guard ball.isMoving, newSpeed > 0 else { return }
        let scale = newSpeed / ball.speed
        ball.vx *= scale
        ball.vy *= scale
    }

    /// テスト・撮影用に球の状態を直接置く。
    ///
    /// 通常の操作（発射 → 反射）だけでは特定の局面（落球の直前など）へ数百フレームかけないと
    /// 到達できず、検証がフレーム数に依存してしまうため用意している。製品コードからは使わない。
    public mutating func placeBall(x: Double, y: Double, vx: Double, vy: Double) {
        ball = BlocksBall(x: x, y: y, vx: vx, vy: vy)
    }

    // MARK: - 進行

    /// `dt` 秒ぶん球を進め、その間に起きたできごとを順に返す。
    ///
    /// **落球（`.ballLost`）が起きた時点で打ち切る**。以降のできごとは「もう存在しない球」のもので、
    /// 続けて処理すると 1 回の落球で 2 機失うような取り違えを生む。
    public mutating func step(dt: Double) -> [BlocksEvent] {
        guard dt > 0, ball.isMoving else { return [] }
        var events: [BlocksEvent] = []

        // 1 サブステップの移動量を球の半径以下に抑える（速い球が薄いブロックをすり抜けるのを防ぐ）。
        let distance = ball.speed * dt
        let substeps = max(1, Int((distance / Metrics.ballRadius).rounded(.up)))
        let substepDT = dt / Double(substeps)

        for _ in 0..<substeps {
            ball.x += ball.vx * substepDT
            ball.y += ball.vy * substepDT

            if resolveWalls() { events.append(.wallBounce) }
            if resolvePaddle() { events.append(.paddleBounce) }
            if let hit = resolveBlocks() { events.append(hit) }

            if ball.y < 0 {
                events.append(.ballLost)
                return events
            }
        }
        return events
    }

    /// 左右の壁と天井。床は `step` 側で落球として扱う。
    private mutating func resolveWalls() -> Bool {
        let r = Metrics.ballRadius
        var bounced = false
        if ball.x - r < 0 {
            ball.x = r
            ball.vx = abs(ball.vx)
            bounced = true
        } else if ball.x + r > Metrics.width {
            ball.x = Metrics.width - r
            ball.vx = -abs(ball.vx)
            bounced = true
        }
        if ball.y + r > Metrics.height {
            ball.y = Metrics.height - r
            ball.vy = -abs(ball.vy)
            bounced = true
        }
        return bounced
    }

    /// パドル。当てた位置で反射角が変わる（`BlocksPhysics.paddleBounce`）。
    private mutating func resolvePaddle() -> Bool {
        guard ball.vy < 0 else { return false }
        let r = Metrics.ballRadius
        let top = Metrics.paddleTop
        // 天面を跨いだフレームだけを拾う。下限を切らないと、パドルの真下を通過中の球まで
        // 拾い上げてしまう（サブステップの移動量は半径以下なのでこの帯を飛び越すことはない）。
        guard ball.y - r <= top, ball.y >= Metrics.paddleY - Metrics.paddleHeight else { return false }
        guard abs(ball.x - paddleX) <= Metrics.paddleHalfWidth + r else { return false }

        ball.y = top + r
        let offset = (ball.x - paddleX) / Metrics.paddleHalfWidth
        let velocity = BlocksPhysics.paddleBounce(offset: offset, speed: speed)
        ball.vx = velocity.vx
        ball.vy = velocity.vy
        return true
    }

    /// ブロック。**1 サブステップにつき 1 個だけ**解決する。
    ///
    /// 隣り合う 2 個に同時に重なったときに両方で反転させると、角に挟まれた球が元の向きへ
    /// 戻ってしまう（2 回反転 = 反転なし）。最も深く重なっている 1 個だけを見る。
    private mutating func resolveBlocks() -> BlocksEvent? {
        let r = Metrics.ballRadius
        // 球の周りにある候補だけを見る。行と列は座標から直接引けるので全走査はしない。
        let minColumn = max(0, Int(((ball.x - r) / Metrics.blockWidth).rounded(.down)))
        let maxColumn = min(Metrics.columns - 1, Int(((ball.x + r) / Metrics.blockWidth).rounded(.down)))
        guard minColumn <= maxColumn else { return nil }
        let topEdge = Metrics.height - Metrics.topMargin
        let minRow = max(0, Int(((topEdge - (ball.y + r)) / Metrics.blockHeight).rounded(.down)))
        let maxRow = min(blocks.count - 1, Int(((topEdge - (ball.y - r)) / Metrics.blockHeight).rounded(.down)))
        guard minRow <= maxRow else { return nil }

        var best: (row: Int, column: Int, collision: BlocksPhysics.Collision)?
        for row in minRow...maxRow {
            for column in minColumn...maxColumn {
                guard blocks[row][column] != nil else { continue }
                guard let collision = BlocksPhysics.blockCollision(
                    ballX: ball.x,
                    ballY: ball.y,
                    radius: r,
                    rect: Self.blockRect(row: row, column: column)
                ) else { continue }
                if best == nil || collision.distanceSquared < best!.collision.distanceSquared {
                    best = (row, column, collision)
                }
            }
        }
        guard let hit = best, let block = blocks[hit.row][hit.column] else { return nil }

        ball.x = hit.collision.x
        ball.y = hit.collision.y
        switch hit.collision.axis {
        case .horizontal: ball.vx = -ball.vx
        case .vertical:   ball.vy = -ball.vy
        }
        let clamped = BlocksPhysics.clampVertical(BlocksPhysics.Velocity(vx: ball.vx, vy: ball.vy))
        ball.vx = clamped.vx
        ball.vy = clamped.vy

        let result = block.damaged()
        blocks[hit.row][hit.column] = result.block
        return .blockHit(
            row: hit.row,
            column: hit.column,
            kind: block.kind,
            destroyed: result.destroyed
        )
    }
}
