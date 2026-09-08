import Foundation

/// 横スクロールランナーのコースそのもの（#494）。
///
/// **SpriteKit にも SwiftUI にも依存しない値型**で、`step(dt:)` を呼ぶと走者が進む。
/// ステージ番号・タイム・記録は持たない（それは `RunnerModel` の仕事）。
/// この分離のおかげで、当たり判定・ジャンプの軌道・ゴール判定をシミュレータ無しで検証できる。
///
/// 座標系は**左下が原点**（SpriteKit と同じ向き）。単位はコース固有の抽象単位で、
/// 画面 pt への変換は `RunnerScene` が `scaleMode = .aspectFit` で一括して行う。
/// 走者の画面上の x は動かず、**コースのほうが左へ流れる**（`distance` が世界での位置）。
public struct RunnerField: Equatable, Sendable {
    /// コースと走者の寸法。すべて抽象単位。
    public enum Metrics {
        /// 画面に見える横幅。
        ///
        /// 縦持ちの画面に横長の帯として載るので、**広くしすぎない**。広げるほど 1 単位が
        /// 小さく描かれ、走者も地形も豆粒になる。最速のステージ（50.8 / 秒）でも
        /// 走者の前に 74 単位 = 約 1.5 秒ぶんの地形が見えるので、初見でも反応できる。
        public static let width: Double = 100
        public static let height: Double = 80
        /// 地面の高さ（走者の足がここに乗る）。
        ///
        /// 跳んでも足が届くのは 26 + 21（大ジャンプの頂点）= 47 までなので、上端 80 まで
        /// 空にすると余る。地面を厚くしてその余りを詰めてある（見た目の都合だけで、
        /// 当たり判定はすべて地面からの相対値で書いてあるため軌道は変わらない）。
        public static let groundY: Double = 26
        /// 走者の画面上の x（固定）。左に寄せて、先の地形を読む余裕を作る。
        public static let playerX: Double = 26
        public static let playerWidth: Double = 8
        public static let playerHeight: Double = 11

        public static var playerHalfWidth: Double { playerWidth / 2 }
        /// 1 サブステップで進んでよい最大距離。
        ///
        /// 障害 1 つの最小の長さ（`RunnerRules.tileWidth` = 4）より小さくしないと、
        /// 速いステージで 1 フレームぶん進んだ先が障害の向こう側になり、当たり判定を素通りする。
        public static let maxSubstep: Double = 2
    }

    public let stage: RunnerStage
    /// 走者の中心のワールド x。ステージ先頭が 0、`stage.length` でゴール。
    public private(set) var distance: Double
    /// 足元の高さ。`Metrics.groundY` が接地。
    public private(set) var footY: Double
    /// 上下の速度。
    public private(set) var vy: Double
    public private(set) var isGrounded: Bool
    /// ジャンプボタンを押し続けているか（大ジャンプ）。
    public private(set) var isHolding: Bool
    /// このジャンプで重力を弱めてきた累計時間。
    public private(set) var holdElapsed: Double
    /// チェックポイントを通過済みか。
    public private(set) var passedCheckpoint: Bool

    /// ステージの頭から始める。
    public init(stage: RunnerStage) {
        self.init(stage: stage, startingAt: 0, passedCheckpoint: false)
    }

    /// 指定した地点から始める（チェックポイント再開・テスト用）。
    public init(stage: RunnerStage, startingAt distance: Double, passedCheckpoint: Bool) {
        self.stage = stage
        self.distance = distance
        self.footY = Metrics.groundY
        self.vy = 0
        self.isGrounded = true
        self.isHolding = false
        self.holdElapsed = 0
        self.passedCheckpoint = passedCheckpoint
    }

    // MARK: - 問い合わせ

    /// ゴールまでの進み具合（0〜1）。
    public var progress: Double {
        guard stage.length > 0 else { return 1 }
        return min(1, max(0, distance / stage.length))
    }

    /// 走者の当たり判定の矩形。
    public var playerMinX: Double { distance - Metrics.playerHalfWidth }
    public var playerMaxX: Double { distance + Metrics.playerHalfWidth }
    /// 足元の地面からの高さ。
    public var altitude: Double { footY - Metrics.groundY }

    /// `x` に穴が開いているか（点で見る）。
    public func isPit(at x: Double) -> Bool {
        stage.hazards.contains { $0.kind == .pit && $0.start <= x && x < $0.end }
    }

    /// 走者の**前方**にある最も近い障害。自動操縦テストと先読みの読み上げが使う。
    public func nextHazard(from x: Double) -> RunnerHazard? {
        stage.hazards.first { $0.end > x }
    }

    // MARK: - 操作

    /// 踏み切る。接地しているときだけ効く（空中での二段ジャンプは無し）。
    @discardableResult
    public mutating func jump() -> Bool {
        guard isGrounded else { return false }
        vy = RunnerRules.jumpVelocity
        isGrounded = false
        isHolding = true
        holdElapsed = 0
        return true
    }

    /// ボタンを離す。以降このジャンプでは重力が弱まらない。
    public mutating func endHold() {
        isHolding = false
    }

    /// テスト・撮影用に走者を直接置く。製品コードからは呼ばない。
    public mutating func placeForTesting(distance: Double, altitude: Double, vy: Double) {
        self.distance = distance
        self.footY = Metrics.groundY + altitude
        self.vy = vy
        self.isGrounded = altitude <= 0 && vy <= 0
        self.isHolding = false
        self.holdElapsed = 0
    }

    // MARK: - 進行

    /// `dt` 秒ぶん進め、その間に起きたできごとを順に返す。
    ///
    /// **決着（ミス・ゴール）が起きた時点で打ち切る**。以降のできごとは「もう走っていない走者」の
    /// もので、続けて処理するとミスとゴールが同じフレームに並ぶ。
    public mutating func step(dt: Double) -> [RunnerEvent] {
        guard dt > 0 else { return [] }
        var events: [RunnerEvent] = []

        // 1 サブステップの移動量を障害の最小寸法より小さく抑える（すり抜け防止）。
        let horizontal = stage.speed * dt
        let vertical = abs(vy) * dt + RunnerRules.gravity * dt * dt
        let travel = max(horizontal, vertical)
        let substeps = max(1, Int((travel / Metrics.maxSubstep).rounded(.up)))
        let substepDT = dt / Double(substeps)

        for _ in 0..<substeps {
            advance(dt: substepDT, into: &events)
            if events.last?.isTerminal == true { return events }
        }
        return events
    }

    /// 1 サブステップ。
    private mutating func advance(dt: Double, into events: inout [RunnerEvent]) {
        distance += stage.speed * dt

        if !isGrounded || vy != 0 {
            // 上昇中に押し続けているあいだだけ重力が弱まる（大ジャンプ）。
            let boosted = isHolding && vy > 0 && holdElapsed < RunnerRules.maxHoldTime
            if boosted { holdElapsed += dt }
            vy -= (boosted ? RunnerRules.holdGravity : RunnerRules.gravity) * dt
            footY += vy * dt
        }

        // 障害物は矩形どうしの重なりで見る。走者の足が上端より上にあれば飛び越えている。
        if isHittingBlock {
            events.append(.crashed)
            return
        }

        if footY <= Metrics.groundY {
            // 穴の判定は**中心の x** で行う。矩形で見ると爪先が縁を越えた瞬間に落ちてしまう。
            if isPit(at: distance) {
                events.append(.fell)
                return
            }
            let wasAirborne = !isGrounded
            footY = Metrics.groundY
            vy = 0
            isGrounded = true
            isHolding = false
            if wasAirborne { events.append(.landed) }
        }

        if !passedCheckpoint, distance >= stage.checkpoint {
            passedCheckpoint = true
            events.append(.passedCheckpoint)
        }

        if distance >= stage.length {
            distance = stage.length
            events.append(.reachedGoal)
        }
    }

    /// いま障害物に当たっているか。足が上端より上にあれば飛び越えている。
    private var isHittingBlock: Bool {
        stage.hazards.contains { hazard in
            guard hazard.kind != .pit else { return false }
            guard hazard.start < playerMaxX, playerMinX < hazard.end else { return false }
            return footY < Metrics.groundY + hazard.height
        }
    }
}
