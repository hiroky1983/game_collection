import Foundation

/// 球の反射計算（#463）。
///
/// **SpriteKit の物理エンジン（`SKPhysicsBody`）は使わない**。理由は 2 つある:
/// 1. 反射角・耐久・すり抜けの検証を Issue の要求どおりユニットテストで固定したい。
///    `SKPhysicsBody` の解決は内部実装で、同じ入力でも SDK の版で結果が動きうる
/// 2. ブロック崩しの「パドルの端で当てると横へ飛ぶ」は物理的に正しい反射ではなく
///    **意図的な嘘**であり、どのみち自前で書く必要がある
///
/// SpriteKit は**ゲームループと描画**だけを担当する（基盤規約・`docs/action-game-foundation.md`）。
public enum BlocksPhysics {
    /// 速度ベクトル。
    public struct Velocity: Equatable, Sendable {
        public var vx: Double
        public var vy: Double

        public init(vx: Double, vy: Double) {
            self.vx = vx
            self.vy = vy
        }

        public var speed: Double { (vx * vx + vy * vy).squareRoot() }
    }

    /// 衝突した面の向き。
    public enum Axis: Equatable, Sendable {
        /// 左右の面に当たった（`vx` が反転する）。
        case horizontal
        /// 上下の面に当たった（`vy` が反転する）。
        case vertical
    }

    /// 軸並行矩形（ブロック 1 個ぶん）。
    public struct Rect: Equatable, Sendable {
        public var minX: Double
        public var maxX: Double
        public var minY: Double
        public var maxY: Double

        public init(minX: Double, maxX: Double, minY: Double, maxY: Double) {
            self.minX = minX
            self.maxX = maxX
            self.minY = minY
            self.maxY = maxY
        }

        public var midX: Double { (minX + maxX) / 2 }
        public var midY: Double { (minY + maxY) / 2 }
    }

    /// 衝突の解決結果。めり込みを押し出した位置と、反転させる軸。
    public struct Collision: Equatable, Sendable {
        public var axis: Axis
        public var x: Double
        public var y: Double
        /// 円の中心から矩形の最近点までの距離の 2 乗。複数のブロックに重なったときの選択に使う。
        public var distanceSquared: Double
    }

    /// パドルで跳ね返ったあとの速度。
    ///
    /// `offset` はパドル中心からのずれを半幅で割った値（-1 = 左端 / 0 = 中央 / 1 = 右端）。
    /// 端で当てるほど横へ飛ぶ古典的な挙動で、**速さは保存する**（当てる場所で球が速くならない）。
    public static func paddleBounce(
        offset: Double,
        speed: Double,
        maxAngle: Double = BlocksField.Metrics.maxPaddleAngle
    ) -> Velocity {
        let clamped = min(1, max(-1, offset))
        let angle = clamped * maxAngle
        return clampVertical(Velocity(vx: speed * sin(angle), vy: speed * cos(angle)))
    }

    /// 真横に近い角度を弾く。
    ///
    /// 反射を繰り返すうちに `vy` がほぼ 0 になると、球が左右の壁を往復し続けて
    /// **ブロックにもパドルにも二度と触れない**（古典的な詰みバグ）。`|vy|` に下限を設け、
    /// 足りないぶんは `vx` から借りて**速さを保存**する。
    ///
    /// `vy == 0` ちょうどのときは上向きへ倒す（下向きに倒すと落ちるだけで救済にならない）。
    public static func clampVertical(
        _ velocity: Velocity,
        minimumRatio: Double = BlocksField.Metrics.minimumVerticalRatio
    ) -> Velocity {
        let speed = velocity.speed
        guard speed > 0 else { return velocity }
        let minimumVY = speed * minimumRatio
        guard abs(velocity.vy) < minimumVY else { return velocity }
        let sign: Double = velocity.vy < 0 ? -1 : 1
        let vy = minimumVY * sign
        // 速さを保存したまま |vy| を持ち上げる。残りを vx に配る（符号は元のまま）。
        let vxMagnitude = max(0, speed * speed - vy * vy).squareRoot()
        let vxSign: Double = velocity.vx < 0 ? -1 : 1
        return Velocity(vx: vxMagnitude * vxSign, vy: vy)
    }

    /// 円（球）と軸並行矩形（ブロック）の衝突。重なっていなければ nil。
    ///
    /// 反転させる軸は「どの面から入ったか」で決める:
    /// - 中心が矩形の x 範囲に収まっている → 上下の面 → `vertical`
    /// - 中心が矩形の y 範囲に収まっている → 左右の面 → `horizontal`
    /// - どちらでもない（角に当たった）→ 中心と最近点を結ぶベクトルの長いほうの成分で決める
    ///
    /// 中心が矩形の内側に入り込んでいる場合（極端に速い球）は、**押し出し量が最も小さい面**を選ぶ。
    public static func blockCollision(
        ballX: Double,
        ballY: Double,
        radius: Double,
        rect: Rect
    ) -> Collision? {
        let closestX = min(max(ballX, rect.minX), rect.maxX)
        let closestY = min(max(ballY, rect.minY), rect.maxY)
        let dx = ballX - closestX
        let dy = ballY - closestY
        let distanceSquared = dx * dx + dy * dy
        guard distanceSquared < radius * radius else { return nil }

        let insideX = ballX > rect.minX && ballX < rect.maxX
        let insideY = ballY > rect.minY && ballY < rect.maxY

        if insideX && insideY {
            // 完全にめり込んでいる。最も浅い面へ押し出す。
            let toLeft = ballX - rect.minX
            let toRight = rect.maxX - ballX
            let toBottom = ballY - rect.minY
            let toTop = rect.maxY - ballY
            let horizontal = min(toLeft, toRight)
            let vertical = min(toBottom, toTop)
            if horizontal < vertical {
                let x = toLeft < toRight ? rect.minX - radius : rect.maxX + radius
                return Collision(axis: .horizontal, x: x, y: ballY, distanceSquared: distanceSquared)
            }
            let y = toBottom < toTop ? rect.minY - radius : rect.maxY + radius
            return Collision(axis: .vertical, x: ballX, y: y, distanceSquared: distanceSquared)
        }

        let axis: Axis
        if insideX {
            axis = .vertical
        } else if insideY {
            axis = .horizontal
        } else {
            axis = abs(dx) > abs(dy) ? .horizontal : .vertical
        }

        switch axis {
        case .horizontal:
            let x = ballX < rect.midX ? rect.minX - radius : rect.maxX + radius
            return Collision(axis: .horizontal, x: x, y: ballY, distanceSquared: distanceSquared)
        case .vertical:
            let y = ballY < rect.midY ? rect.minY - radius : rect.maxY + radius
            return Collision(axis: .vertical, x: ballX, y: y, distanceSquared: distanceSquared)
        }
    }
}
