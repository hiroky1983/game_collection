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
        /// 縦持ちの画面に載る帯の横幅なので、**広くしすぎない**。広げるほど 1 単位が
        /// 小さく描かれ、走者も地形も豆粒になる。最速のステージ（50.8 / 秒）でも
        /// 走者の前に 74 単位 = 約 1.5 秒ぶんの地形が見えるので、初見でも反応できる。
        public static let width: Double = 100
        /// 画面に見える縦幅。
        ///
        /// 元は 80（`width` に対してほぼ正方形）→ 140（「正方形である意味がない」という
        /// 会長QAで縦長化・2026-09-10）→ **95**（「プレイ画面の横幅を上部セクションと揃えて
        /// 不変にしてほしい」という会長QAを受けて再調整・2026-09-11）と変遷している。
        ///
        /// `RunnerView.course`は`.aspectRatio(width/height, contentMode: .fit)`でこの比率に
        /// 固定されるため、比率が縦長すぎると実機の縦の余白が足りずに**横幅が`topSummary`より
        /// 狭く縮む**（#621）。実機計測で「横幅優先で縮まない」ために必要な比率は概ね
        /// 1.0（正方形）以上と分かったため、140（比率0.71）から95（比率1.05）まで戻した
        /// ——完全に80まで戻さなかったのは、丘・雲レイヤー（`RunnerScene`）の縦の見せ場を
        /// 多少残すため。`width`はそのまま（横方向に見える地形の量・1単位の大きさは変えない）。
        public static let height: Double = 95
        /// 地面の高さ（走者の足がここに乗る）。
        ///
        /// 跳んでも足が届くのは 34 + 21（大ジャンプの頂点）= 55 までなので、上端
        /// （`Metrics.height`）まで空にすると余る。地面をやや厚くしてその余りの一部を詰め、残りは
        /// `RunnerScene` の丘・雲で埋める（見た目の都合だけで、当たり判定はすべて
        /// 地面からの相対値で書いてあるため軌道は変わらない）。
        public static let groundY: Double = 34
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
    /// 接地してから使ったジャンプの回数。着地すると 0 に戻る（`RunnerRules.maxJumps` まで）。
    public private(set) var jumpCount: Int
    /// ジャンプボタンを押し続けているか（大ジャンプ）。**離した瞬間にまだ true なら**、
    /// `endHold()` が上昇速度を切り詰める（`RunnerRules.jumpCutVelocity`）。
    /// 着地すると自動的に `false` へ戻る。
    public private(set) var isHolding: Bool
    /// 踏み切ってからの経過秒（`isHolding` のあいだだけ進む）。`jumpCutGraceTime` に
    /// 達するまでは `endHold()` が呼ばれても実際には切り詰めず、猶予が明けた瞬間に
    /// `pendingCut` があれば切り詰める（会長QA「進まねえ」2026-09-11 への対応。詳細は
    /// `RunnerRules.jumpCutGraceTime` のドキュメントを参照）。
    private var holdElapsed: Double = 0
    /// 猶予中に `endHold()` が呼ばれ、猶予明けに切り詰めを適用すべきか。
    private var pendingCut: Bool = false
    /// チェックポイントを通過済みか。
    public private(set) var passedCheckpoint: Bool
    /// ペダルの乗り（#569）。1.0 が下限で、`RunnerRules.maxPedalBoost` が上限。
    ///
    /// 接地して漕いでいるあいだに上がり、跳んでいるあいだは漕げないので落ちる。
    /// **速さに効くのは接地しているあいだだけ**（`currentSpeed`）。
    public private(set) var pedalBoost: Double
    /// スピードアップアイテムを取った直後だけ乗る、上限（`maxPedalBoost`）を超える一時的な
    /// 上乗せ分。時間経過で 0 まで減衰する（`RunnerRules.pickupOverboostDuration`）。
    ///
    /// **「もう乗りが上限に達している状態で取っても意味がない」という会長QA
    /// （2026-09-10）への対応**。`pedalBoost` 自体の上限は変えず、取った瞬間だけ別枠で
    /// 上乗せすることで、どんな乗り具合で取っても必ず体感できる加速になる。
    public private(set) var pickupOverboost: Double = 0
    /// `pickupOverboost` が 0 になるまでの残り秒数。
    private var pickupOverboostRemaining: Double = 0
    /// 取得済みのスピードアップアイテムの数。まだ消していないノードを消すのに描画側が使う。
    public private(set) var collectedPickupCount: Int = 0
    /// `stage.pickups` のうち、すでに取得した添字。**同じ走行中に同じアイテムは 1 回しか取れない**。
    private var collectedPickupIndices: Set<Int> = []

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
        self.jumpCount = 0
        self.isHolding = false
        self.passedCheckpoint = passedCheckpoint
        self.pedalBoost = 1
    }

    // MARK: - 問い合わせ

    /// ゴールまでの進み具合（0〜1）。
    public var progress: Double {
        guard stage.length > 0 else { return 1 }
        return min(1, max(0, distance / stage.length))
    }

    /// いま実際に進んでいる速さ（ワールド単位 / 秒）。
    ///
    /// **空中では必ず `stage.speed`**（ペダルを漕げないので乗りが効かない・#569）。
    /// この一点で「跳んで進む距離 = `speed × 滞空時間`」が乗りに左右されなくなり、
    /// ステージの成立条件（`RunnerStageTests`）を丸ごと据え置ける。`pickupOverboost` も
    /// 同じ理由で接地中にしか効かせない。
    public var currentSpeed: Double {
        isGrounded ? stage.speed * (pedalBoost + pickupOverboost) : stage.speed
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

    /// 踏み切る。接地中か、空中でもまだ二段目が残っていれば効く（`RunnerRules.maxJumps`）。
    ///
    /// 二段目も初速は一段目と同じ `jumpVelocity` にする。踏み切った時点の `vy` へ足し込むと
    /// 頂点付近で踏み切るほど高く跳べてしまい、地形の成立条件が踏み切りのタイミング次第で
    /// 変わってしまう（`RunnerStageTests` が前提にできなくなる）。
    @discardableResult
    public mutating func jump() -> Bool {
        guard jumpCount < RunnerRules.maxJumps else { return false }
        vy = RunnerRules.jumpVelocity
        isGrounded = false
        jumpCount += 1
        isHolding = true
        holdElapsed = 0
        pendingCut = false
        return true
    }

    /// ボタンを離す。
    ///
    /// **猶予時間（`RunnerRules.jumpCutGraceTime`）を過ぎていれば、その場で `vy` を
    /// 切り詰める**（会長QA「軽いタップなら本当に小ジャンプぐらいの感じにしたい」
    /// 2026-09-10）。踏み切った直後にすぐ離すほど高い `vy` のまま切り詰められて低い
    /// ホップになり、離すのが遅くなる（＝長押しする）ほど重力で `vy` がすでに下がっている
    /// ため切り詰めの影響が薄れ、十分粘れば無傷の全弾道（`RunnerRules.jumpApex`）まで伸びる
    /// ——重力そのものはどちらの場合も一定のまま（旧方式の「押している間だけ重力を弱める」
    /// より単純）。
    ///
    /// **猶予時間の間に呼ばれた場合は、その場では切り詰めず `pendingCut` を立てるだけ**にする
    /// （`advance(dt:)` が猶予明けに適用する）。`press()`→`release()` が同じフレーム内で
    /// ほぼ同時に呼ばれるタップ操作で `vy` がまだ何も減っていないまま切り詰められ、
    /// ステージ1の最初の穴にすら届かない、という不具合（会長QA「進まねえ」2026-09-11）
    /// への対応。
    public mutating func endHold() {
        guard isHolding else { return }
        if holdElapsed >= RunnerRules.jumpCutGraceTime {
            applyCutIfNeeded()
            isHolding = false
        } else {
            pendingCut = true
        }
    }

    private mutating func applyCutIfNeeded() {
        if vy > RunnerRules.jumpCutVelocity {
            vy = RunnerRules.jumpCutVelocity
        }
    }

    /// テスト・撮影用に走者を直接置く。製品コードからは呼ばない。
    public mutating func placeForTesting(distance: Double, altitude: Double, vy: Double) {
        self.distance = distance
        self.footY = Metrics.groundY + altitude
        self.vy = vy
        self.isGrounded = altitude <= 0 && vy <= 0
        self.jumpCount = self.isGrounded ? 0 : 1
        self.isHolding = false
        self.holdElapsed = 0
        self.pendingCut = false
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
        // 横は**この dt のあいだに出しうる最大の速さ**で見積もる。いまの速さで割ると、
        // 同じ dt の中でペダルが乗ったぶんだけ 1 サブステップの移動量が見積もりを超える。
        let horizontal = stage.speed * RunnerRules.maxPedalBoost * dt
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
        // ペダルは地面でしか漕げない（#569）。跳んでいるあいだは乗りが落ちる。
        let rate = isGrounded ? RunnerRules.pedalGain : -RunnerRules.pedalLoss
        pedalBoost = min(RunnerRules.maxPedalBoost, max(1, pedalBoost + rate * dt))
        // アイテムの上乗せ分は時間で線形に減衰する。取った瞬間の乗り具合に関わらず、
        // 必ず一定時間ぶんの加速が体感できる（`currentSpeed` を参照）。
        if pickupOverboostRemaining > 0 {
            pickupOverboostRemaining = max(0, pickupOverboostRemaining - dt)
            pickupOverboost = RunnerRules.pickupOverboost
                * (pickupOverboostRemaining / RunnerRules.pickupOverboostDuration)
        }
        distance += currentSpeed * dt

        if !isGrounded || vy != 0 {
            // 重力は押している間も一定（大ジャンプの高さは `endHold()` の切り詰めだけで決まる）。
            vy -= RunnerRules.gravity * dt
            footY += vy * dt
        }

        // 猶予時間ぶん経過したら、猶予中に来ていた `endHold()` を今適用する。
        if isHolding {
            holdElapsed += dt
            if pendingCut, holdElapsed >= RunnerRules.jumpCutGraceTime {
                applyCutIfNeeded()
                isHolding = false
                pendingCut = false
            }
        }

        // 障害物は矩形どうしの重なりで見る。走者の足が上端より上にあれば飛び越えている。
        if isHittingBlock {
            events.append(.crashed)
            return
        }

        // スピードアップアイテム。「触れると得する」だけなので、穴・障害物と違って
        // 高さは問わず横方向の重なりだけで見る。`currentSpeed` の「空中では必ず基準速度」
        // という不変条件には触れない（接地しているあいだしか乗りは効かないので、
        // 跳んで取ってもその場では速くならない）。
        //
        // 効果は2つ: (1) `pedalBoost` を即座に上限へ引き上げる（乗れていない状態で取った
        // 場合の底上げ）、(2) それとは別枠の `pickupOverboost` を一時的に乗せる（会長QA
        // 「取るタイミングが大体もうMAX速度で意味がない」2026-09-10 への対応。`pedalBoost`
        // 自体はどの道 `maxPedalBoost` で頭打ちなので、上限に張り付いた状態で取っても
        // (1) だけでは何も変わらない。上限を超える一時的な上乗せにすることで、
        // 乗り具合に関わらず必ず体感できる加速にする）。
        for (index, pickup) in stage.pickups.enumerated() where !collectedPickupIndices.contains(index) {
            guard playerMinX <= pickup.start, pickup.start <= playerMaxX else { continue }
            collectedPickupIndices.insert(index)
            collectedPickupCount += 1
            pedalBoost = RunnerRules.maxPedalBoost
            pickupOverboost = RunnerRules.pickupOverboost
            pickupOverboostRemaining = RunnerRules.pickupOverboostDuration
            events.append(.collectedSpeedItem)
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
            jumpCount = 0
            isHolding = false
            pendingCut = false
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
