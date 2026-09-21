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
        /// 盤の高さ。**幅に対するこの比が、画面上での盤の大きさを決める**（#597）。
        ///
        /// 盤は `.aspectRatio(_:contentMode: .fit)` で枠に収めるため、比が縦長すぎると
        /// 縦で頭打ちになり、左右に余白が残ったまま横幅を使い切れない。150 だった頃の実測では
        /// iPhone 17 Pro で使える幅 370pt に対し盤は 286pt（77%）、iPhone SE では 343pt に
        /// 対し 205pt（59%）しか無かった。
        ///
        /// 幅と同じ 100 = **正方形**にすると、対象実機のすべてで横幅を使い切れる
        /// （`BlocksLayoutTests` が実測値で固定している）。1 つの比で全機種を満たす値はここだけで、
        /// これより高くすると iPhone SE が、低くすると縦の可動域が削られる。
        public static let height: Double = 100
        /// ブロックの列数。ステージのレイアウト文字列の 1 行の長さでもある。
        public static let columns = 9
        public static let blockHeight: Double = 5
        /// 最上段のブロックの上と天井のあいだの余白。
        ///
        /// 盤が低くなったぶん（#597）詰めて、球が動ける縦の可動域を確保する。
        /// 球の直径（`ballRadius * 2` = 4）より広いので、最上段の上へ回り込む classic な
        /// 攻略ルートは残る。
        public static let topMargin: Double = 6
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

        // MARK: - 画面へ載せるときの寸法（#597）

        /// 盤の縦横比（幅 / 高さ）。View はこの比で枠を作る（`BlocksView.playfield`）。
        ///
        /// シーンは `scaleMode = .aspectFit` なので、**枠の比がこれとずれると左右か上下に
        /// 余白が出て、タップ位置とパドルの対応も狂う**。
        public static var aspectRatio: Double { width / height }

        /// 使える枠（pt）に収まる盤の実寸（pt）。
        ///
        /// `.aspectRatio(_:contentMode: .fit)` が行う計算そのもので、幅ごとの見え方を
        /// テストで固定するために値として取り出している。**縦で頭打ちになると横幅が余る**ので、
        /// 対象実機の枠を入れて余りが許容範囲かを `BlocksLayoutTests` が確かめる。
        /// `ratio` は縦横比（幅 / 高さ）。既定は盤の比で、**テストが正方形以外の比でも
        /// 頭打ちの向きを確かめられる**よう引数にしてある（現在の盤は 100 × 100 なので、
        /// 比が 1 のままだと幅と高さを取り違えても結果が変わらず、変異を見逃す）。
        public static func boardSize(
            availableWidth: Double,
            availableHeight: Double,
            ratio: Double = aspectRatio
        ) -> (width: Double, height: Double) {
            guard availableWidth > 0, availableHeight > 0, ratio > 0 else { return (0, 0) }
            let heightLimited = availableHeight * ratio
            if heightLimited <= availableWidth {
                return (heightLimited, availableHeight)
            }
            return (availableWidth, availableWidth / ratio)
        }

        /// 「タップで発射」の札を盤の下端から浮かせる高さ（抽象単位）。
        ///
        /// 発射前の球の頭（`restingBallY + ballRadius`）より上に置く。ここを pt の固定値に
        /// すると、盤が大きい機種ほどパドルが上に来て札とぶつかる（#597）。
        public static var readyHintClearance: Double { restingBallY + ballRadius * 3 }

        /// 盤の実寸（pt）における 1 抽象単位の大きさ。
        ///
        /// バー・玉・ブロックの pt 寸法はすべてこれに比例する（描画は SpriteKit の
        /// `scaleMode = .aspectFit` が担うので、View 側が使うのは**盤の上に重ねる部品**の
        /// 位置決めだけ）。
        public static func pointsPerUnit(boardWidth: Double) -> Double { boardWidth / width }

        /// タップ位置（盤の枠のなかでの x・pt）を盤の x（抽象単位）へ写す。
        ///
        /// 盤の外へはみ出した指は端に丸める。パドル自身の可動域の制限は
        /// `BlocksField.movePaddle(to:)` が持つので、ここでは盤の座標に写すだけ。
        public static func fieldX(viewX: Double, viewWidth: Double) -> Double {
            guard viewWidth > 0 else { return width / 2 }
            return min(width, max(0, viewX / viewWidth * width))
        }

        /// 落ちてくるアイテムの寸法（#599）。ブロック（11.1 × 5）より小さく、角を丸めて
        /// 「盤の部品ではなく拾うもの」と分かる形にする。
        ///
        /// 球（直径 4）より大きくないと、落ちてきたことに気づけないまま床まで抜ける。
        public static let itemWidth: Double = 8
        public static let itemHeight: Double = 3.8

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
    /// 盤上の球。**増える**（#599）ので配列で持つ。空になるのは全部落ちた瞬間だけ。
    public private(set) var balls: [BlocksBall]
    /// 落下中のアイテム（#599）。
    public private(set) var items: [BlocksItem]
    /// バー伸長の残り時間（秒）。0 なら効いていない。
    public private(set) var widePaddleRemaining: Double
    /// このステージで壊したブロックの通算数。アイテムの出現条件（#599）に使う。
    ///
    /// 盤はステージごとに作り直されるので、ステージをまたいで持ち越されない。
    public private(set) var destroyedCount: Int
    /// このステージでの球の速さ。発射・パドル反射のたびにこの値へ揃える。
    public private(set) var speed: Double
    /// 1 機失うことなく連続で壊したブロックの数（#1202）。フレンジー増殖の発動条件に使う。
    ///
    /// `destroyedCount` と違い**落球でリセットされる**（`resetBall()`）。ノーミスを維持する
    /// 動機になるよう「連続」を条件にしているため。
    public private(set) var comboCount: Int
    /// このステージでのフレンジー増殖のしきい値。nil ならこのステージでは発動しない（#1202）。
    private let frenzyThreshold: Int?
    /// 盤上の金庫（#1250）。レイアウトの `w` から自動で決まる（`BlocksVault.detect`）。
    public private(set) var vaults: [BlocksVault]
    /// 空にした金庫の数。描画側が「一斉に崩れる」演出を出すきっかけの検知に使う。
    public private(set) var vaultsClearedCount: Int

    public init(stage: BlocksStage, speed: Double) {
        self.blocks = stage.makeBlocks()
        self.paddleX = Metrics.width / 2
        self.speed = speed
        self.balls = [BlocksBall(x: Metrics.width / 2, y: Metrics.restingBallY)]
        self.items = []
        self.widePaddleRemaining = 0
        self.destroyedCount = 0
        self.comboCount = 0
        self.frenzyThreshold = stage.frenzyThreshold
        self.vaults = BlocksVault.detect(in: blocks)
        self.vaultsClearedCount = 0
    }

    // MARK: - 盤面の問い合わせ

    public var rowCount: Int { blocks.count }

    /// 先頭の球。
    ///
    /// 球の本体は `balls`（#599）。1 個だけを見れば足りる呼び出し（発射前の位置・速さの確認など）が
    /// 多いので入口を残してある。**球が 1 個も無いのは全部落ちた瞬間だけ**で、そのとき
    /// `step` は `.ballLost` を返して即座に抜け、Model が `resetBall()` するか決着させる。
    public var ball: BlocksBall { balls.first ?? BlocksBall(x: paddleX, y: Metrics.restingBallY) }

    /// バー伸長が効いているか（#599）。
    public var isPaddleWide: Bool { widePaddleRemaining > 0 }

    /// いま効いているパドルの半幅。伸長中だけ `BlocksRules.widePaddleFactor` 倍になる。
    ///
    /// **当たり判定も可動域の丸めもこの値を見る**（`Metrics.paddleHalfWidth` は素の値）。
    public var paddleHalfWidth: Double {
        Metrics.paddleHalfWidth * (isPaddleWide ? BlocksRules.widePaddleFactor : 1)
    }

    /// いま効いているパドルの幅。描画（`BlocksScene`）が横方向の拡大率に使う。
    public var paddleWidth: Double { paddleHalfWidth * 2 }

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
        // 伸びているあいだは半幅が広いぶん、端で止まる位置も内側になる（#599）。
        let half = paddleHalfWidth
        paddleX = min(Metrics.width - half, max(half, x))
        // 発射前の球はパドルに乗せたまま一緒に動かす。
        for index in balls.indices where !balls[index].isMoving {
            balls[index].x = paddleX
            balls[index].y = Metrics.restingBallY
        }
    }

    /// 球を発射する。すでに動いている球には触らない。
    public mutating func launch() {
        let velocity = BlocksPhysics.paddleBounce(offset: Metrics.launchOffset, speed: speed)
        for index in balls.indices where !balls[index].isMoving {
            balls[index].vx = velocity.vx
            balls[index].vy = velocity.vy
        }
    }

    /// 球をパドルの上へ戻す（1 機失ったあと）。
    ///
    /// **増えた球・落下中のアイテム・効いている効果もここで消える**（#599）。持ち越すと、
    /// わざと落として効果だけ貯める遊び方ができてしまう。
    public mutating func resetBall() {
        balls = [BlocksBall(x: paddleX, y: Metrics.restingBallY)]
        items.removeAll()
        widePaddleRemaining = 0
        // フレンジーのコンボもここで切れる（#1202）。ノーミスを維持できなかった、という扱い。
        comboCount = 0
        // 縮んだパドルの位置で球を乗せ直す。
        movePaddle(to: paddleX)
    }

    /// 球の速さを変える（ゆっくりモードの切り替え）。**向きは保ったまま**速さだけ差し替える。
    public mutating func setSpeed(_ newSpeed: Double) {
        speed = newSpeed
        guard newSpeed > 0 else { return }
        for index in balls.indices where balls[index].isMoving {
            let scale = newSpeed / balls[index].speed
            balls[index].vx *= scale
            balls[index].vy *= scale
        }
    }

    /// テスト・撮影用に球の状態を直接置く。**盤上の球はこの 1 個だけになる**。
    ///
    /// 通常の操作（発射 → 反射）だけでは特定の局面（落球の直前など）へ数百フレームかけないと
    /// 到達できず、検証がフレーム数に依存してしまうため用意している。製品コードからは使わない。
    public mutating func placeBall(x: Double, y: Double, vx: Double, vy: Double) {
        balls = [BlocksBall(x: x, y: y, vx: vx, vy: vy)]
    }

    #if DEBUG
    /// テスト・撮影用にアイテムを直接落とす（#599）。
    ///
    /// 本来の出現条件はブロックを `BlocksRules.itemDropInterval` 個壊すことなので、
    /// 効果そのものを確かめたいだけのときに 7 個壊す手順を毎回書くと、テストが
    /// 出現条件の変更でまとめて壊れる。出現条件は専用のテストで別に固定する。
    public mutating func dropItemForTesting(kind: BlocksItemKind, x: Double, y: Double) {
        items.append(BlocksItem(kind: kind, x: x, y: y))
    }

    /// テスト用に、当たり判定を経由せず 1 個のブロックを直接壊す（#1202）。
    ///
    /// フレンジー増殖の上限・コンボのリセットは「壊した瞬間の `balls` の状態」に依存する。
    /// `placeBall` は球を 1 個に差し替えてしまうため、複数球が既にある状態を保ったまま
    /// ブロックを壊すテストが書けない。ここでは `resolveBlocks` の後半（耐久を減らし、
    /// アイテム出現とコンボ進行を行う部分）だけを、当たり判定を飛ばして再利用する。
    /// 実際の衝突が無いので、種は「動いている球のうち先頭のもの」で代用する
    /// （このヘルパー自体は特定の球が衝突したことを模擬しないため）。
    @discardableResult
    public mutating func destroyBlockForTesting(row: Int, column: Int) -> [BlocksEvent] {
        guard let block = blocks[row][column] else { return [] }
        let result = block.damaged()
        blocks[row][column] = result.block
        if result.destroyed { spawnItemIfDue(row: row, column: column) }
        var events: [BlocksEvent] = []
        let seed = balls.first(where: { $0.isMoving })
        if result.destroyed { events += advanceVault(row: row, column: column, seed: seed) }
        events.append(.blockHit(row: row, column: column, kind: block.kind, destroyed: result.destroyed))
        if result.destroyed, let seed, let ballCount = progressCombo(seed: seed) {
            events.append(.frenzyTriggered(ballCount: ballCount))
        }
        return events
    }

    /// テスト用に、盤上の球を複数まとめて直接置く（#1202）。
    ///
    /// `placeBall` は 1 個に限定されるため、「配列の先頭とは別の球が実際に衝突した」
    /// という複数球のシナリオを組み立てるのに使う。
    public mutating func placeBallsForTesting(_ newBalls: [BlocksBall]) {
        balls = newBalls
    }
    #endif

    // MARK: - 進行

    /// `dt` 秒ぶん盤面を進め、その間に起きたできごとを順に返す。
    ///
    /// **盤上の球がすべて落ちた時点（`.ballLost`）で打ち切る**。以降のできごとは
    /// 「もう存在しない球」のもので、続けて処理すると 1 回の落球で 2 機失うような取り違えを生む。
    /// 球が増えているあいだ（#599）は、1 個落ちても残りが動いていれば何も起きない。
    public mutating func step(dt: Double) -> [BlocksEvent] {
        guard dt > 0 else { return [] }
        let hadBalls = !balls.isEmpty
        var events: [BlocksEvent] = []

        // 1 サブステップの移動量を球の半径以下に抑える（速い球が薄いブロックをすり抜けるのを防ぐ）。
        // 盤上でいちばん速いものに合わせる（球が止まっていてもアイテムは落ちている）。
        let fastest = max(balls.map(\.speed).max() ?? 0, BlocksRules.itemFallSpeed)
        let substeps = max(1, Int((fastest * dt / Metrics.ballRadius).rounded(.up)))
        let substepDT = dt / Double(substeps)

        for _ in 0..<substeps {
            var index = 0
            while index < balls.count {
                var ball = balls[index]
                guard ball.isMoving else { index += 1; continue }
                ball.x += ball.vx * substepDT
                ball.y += ball.vy * substepDT

                if resolveWalls(&ball) { events.append(.wallBounce) }
                if resolvePaddle(&ball) { events.append(.paddleBounce) }
                resolveBlocks(&ball, events: &events)

                if ball.y < 0 {
                    // 増えた球のうちの 1 個が落ちただけ。残機が減るのは最後の 1 個のときだけ。
                    balls.remove(at: index)
                    continue
                }
                balls[index] = ball
                index += 1
            }

            events.append(contentsOf: advanceItems(dt: substepDT))
            expireEffects(dt: substepDT)

            if hadBalls, balls.isEmpty {
                events.append(.ballLost)
                return events
            }
        }
        return events
    }

    /// 左右の壁と天井。床は `step` 側で落球として扱う。
    private func resolveWalls(_ ball: inout BlocksBall) -> Bool {
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
    ///
    /// 伸びているあいだ（#599）も**当てた位置と角度の対応は同じ**にする
    /// （半幅で割るので、端は端のまま最大角で返る）。
    private func resolvePaddle(_ ball: inout BlocksBall) -> Bool {
        guard ball.vy < 0 else { return false }
        let r = Metrics.ballRadius
        let top = Metrics.paddleTop
        let half = paddleHalfWidth
        // 天面を跨いだフレームだけを拾う。下限を切らないと、パドルの真下を通過中の球まで
        // 拾い上げてしまう（サブステップの移動量は半径以下なのでこの帯を飛び越すことはない）。
        guard ball.y - r <= top, ball.y >= Metrics.paddleY - Metrics.paddleHeight else { return false }
        guard abs(ball.x - paddleX) <= half + r else { return false }

        ball.y = top + r
        let offset = (ball.x - paddleX) / half
        let velocity = BlocksPhysics.paddleBounce(offset: offset, speed: speed)
        ball.vx = velocity.vx
        ball.vy = velocity.vy
        return true
    }

    /// ブロック。**1 サブステップにつき 1 個だけ**解決する。
    ///
    /// 隣り合う 2 個に同時に重なったときに両方で反転させると、角に挟まれた球が元の向きへ
    /// 戻ってしまう（2 回反転 = 反転なし）。最も深く重なっている 1 個だけを見る。
    ///
    /// 起きたできごとは `events` へ直接追記する（`.blockHit` に加え、コンボがしきい値に
    /// 達すれば `.frenzyTriggered` も同じ 1 回の破壊から出るため、単一の戻り値では表せない）。
    private mutating func resolveBlocks(_ ball: inout BlocksBall, events: inout [BlocksEvent]) {
        let r = Metrics.ballRadius
        // 球の周りにある候補だけを見る。行と列は座標から直接引けるので全走査はしない。
        let minColumn = max(0, Int(((ball.x - r) / Metrics.blockWidth).rounded(.down)))
        let maxColumn = min(Metrics.columns - 1, Int(((ball.x + r) / Metrics.blockWidth).rounded(.down)))
        guard minColumn <= maxColumn else { return }
        let topEdge = Metrics.height - Metrics.topMargin
        let minRow = max(0, Int(((topEdge - (ball.y + r)) / Metrics.blockHeight).rounded(.down)))
        let maxRow = min(blocks.count - 1, Int(((topEdge - (ball.y - r)) / Metrics.blockHeight).rounded(.down)))
        guard minRow <= maxRow else { return }

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
        guard let hit = best, let block = blocks[hit.row][hit.column] else { return }

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
        if result.destroyed { spawnItemIfDue(row: hit.row, column: hit.column) }
        // 金庫の効果は `blockHit` より前に並べる（`BlocksEvent.vaultWallOpened` 参照）。
        if result.destroyed { events += advanceVault(row: hit.row, column: hit.column, seed: ball) }
        events.append(.blockHit(
            row: hit.row,
            column: hit.column,
            kind: block.kind,
            destroyed: result.destroyed
        ))
        if result.destroyed, let ballCount = progressCombo(seed: ball) {
            events.append(.frenzyTriggered(ballCount: ballCount))
        }
    }

    // MARK: - 金庫（#1250）

    /// 壊したブロックが金庫の中身なら数え、開いた壁ごとに球を 1 個足す。空になったら一斉ダメージ。
    ///
    /// 球の追加は既存の上限 `BlocksRules.maxBalls` の枠内（`multiBall` と同じ扱い）。
    /// **乱数は使わない**（基盤規約）。
    private mutating func advanceVault(row: Int, column: Int, seed: BlocksBall?) -> [BlocksEvent] {
        let cell = BlocksVault.Cell(row: row, column: column)
        guard let index = vaults.firstIndex(where: { $0.contentCells.contains(cell) }) else { return [] }
        var events: [BlocksEvent] = []
        for wall in vaults[index].recordDestroyed() {
            blocks[wall.row][wall.column] = nil
            if let seed { addVaultBall(seed: seed) }
            events.append(.vaultWallOpened(vault: index, row: wall.row, column: wall.column))
        }
        if vaults[index].isEmpty {
            vaultsClearedCount += 1
            events.append(.vaultCleared(vault: index, hits: shockwave()))
        }
        return events
    }

    /// 金庫の壁が開いたぶんの球を 1 個足す。上限に達していれば何もしない。
    private mutating func addVaultBall(seed: BlocksBall) {
        guard seed.isMoving, balls.count < BlocksRules.maxBalls else { return }
        let sign: Double = balls.count % 2 == 0 ? 1 : -1
        let rotated = Self.rotate(vx: seed.vx, vy: seed.vy, by: sign * BlocksRules.multiBallSpread)
        let clamped = BlocksPhysics.clampVertical(rotated)
        balls.append(BlocksBall(x: seed.x, y: seed.y, vx: clamped.vx, vy: clamped.vy))
    }

    /// 金庫を空にした瞬間の一斉ダメージ。**まだ閉じている他の金庫の中身は巻き込まない**
    /// （そちらの壁が開く数え方と再帰的に絡むため）。アイテム出現・フレンジーのコンボにも数えない。
    private mutating func shockwave() -> [BlocksBlockHit] {
        var hits: [BlocksBlockHit] = []
        for row in blocks.indices {
            for column in blocks[row].indices {
                guard let block = blocks[row][column], block.isBreakable else { continue }
                let cell = BlocksVault.Cell(row: row, column: column)
                guard !vaults.contains(where: { $0.contentCells.contains(cell) }) else { continue }
                let result = block.damaged()
                blocks[row][column] = result.block
                hits.append(BlocksBlockHit(row: row, column: column, kind: block.kind, destroyed: result.destroyed))
            }
        }
        return hits
    }

    // MARK: - フレンジー増殖（#1202）

    /// 連続で壊したブロックの数を進め、しきい値に達していればフレンジー増殖を発動する。
    ///
    /// `seed` は**今まさに衝突してブロックを壊した球**（衝突・反射を解決した後の値）。
    /// `balls` 配列から「動いている球」を検索して選ぶと、複数球のときに衝突していない
    /// 別の球を、単一球でも衝突前の（反射前の）値を拾ってしまう
    /// （`balls[index] = ball` の書き戻しは `resolveBlocks` の呼び出し元・後で行われるため。
    /// CodeRabbit 指摘・Major）。
    ///
    /// **乱数は使わない**（基盤規約）。しきい値の倍数に達するたびに発動するので、
    /// コンボを維持し続ける限り何度でも起きる（`spawnItemIfDue` と同じ modulo の形）。
    private mutating func progressCombo(seed: BlocksBall) -> Int? {
        guard let threshold = frenzyThreshold, threshold > 0 else { return nil }
        comboCount += 1
        guard comboCount % threshold == 0 else { return nil }
        return triggerFrenzy(seed: seed)
    }

    /// `seed` を種にして、`BlocksRules.frenzyMaxBalls` に達するまで扇状に増やす。
    ///
    /// 既存の `multiBall`（アイテム取得トリガー・`splitBalls()`・上限 `maxBalls`=3）とは
    /// 規模もトリガーも別物（会長決裁 2026-09-21）。複数の球を種にすると増える方向が偏り、
    /// 「画面を均等に埋める」体験にならないため、種は 1 個に絞る。
    /// すでに上限に達している（or 種が止まっている）ときは何もしない。
    private mutating func triggerFrenzy(seed: BlocksBall) -> Int? {
        guard seed.isMoving else { return nil }
        let capacity = BlocksRules.frenzyMaxBalls - balls.count
        guard capacity > 0 else { return nil }

        var added: [BlocksBall] = []
        for index in 0..<capacity {
            let fraction = capacity > 1 ? Double(index) / Double(capacity - 1) - 0.5 : 0
            let rotated = Self.rotate(vx: seed.vx, vy: seed.vy, by: fraction * BlocksRules.frenzySpreadAngle)
            let clamped = BlocksPhysics.clampVertical(rotated)
            added.append(BlocksBall(x: seed.x, y: seed.y, vx: clamped.vx, vy: clamped.vy))
        }
        balls.append(contentsOf: added)
        return balls.count
    }

    // MARK: - アイテム（#599）

    /// 壊した通算数が `BlocksRules.itemDropInterval` の倍数に達したら、その場所からアイテムを落とす。
    ///
    /// **乱数は使わない**（基盤規約）。出る個数も順番も崩し方だけで決まるので、
    /// 同じ操作からは常に同じ盤面になり、不具合をテストで再現できる。
    private mutating func spawnItemIfDue(row: Int, column: Int) {
        destroyedCount += 1
        guard destroyedCount % BlocksRules.itemDropInterval == 0 else { return }
        let order = destroyedCount / BlocksRules.itemDropInterval - 1
        let kind = BlocksItemKind.dropOrder[order % BlocksItemKind.dropOrder.count]
        let rect = Self.blockRect(row: row, column: column)
        items.append(BlocksItem(kind: kind, x: rect.midX, y: rect.midY))
    }

    /// アイテムを落とし、受け止められたものの効果を出す。床まで落ちたものは黙って消える。
    private mutating func advanceItems(dt: Double) -> [BlocksEvent] {
        guard !items.isEmpty else { return [] }
        var events: [BlocksEvent] = []
        var index = 0
        while index < items.count {
            items[index].y -= BlocksRules.itemFallSpeed * dt
            let item = items[index]
            if isCaught(item) {
                items.remove(at: index)
                apply(item.kind)
                events.append(.itemCaught(kind: item.kind))
                continue
            }
            if item.y + Metrics.itemHeight / 2 < 0 {
                items.remove(at: index)
                continue
            }
            index += 1
        }
        return events
    }

    /// アイテムがパドルに重なっているか。矩形どうしの重なりで見る
    /// （球と違って反射しないので、面で触れたら取れたことにしてよい）。
    private func isCaught(_ item: BlocksItem) -> Bool {
        let halfW = Metrics.itemWidth / 2
        let halfH = Metrics.itemHeight / 2
        guard item.y - halfH <= Metrics.paddleTop else { return false }
        guard item.y + halfH >= Metrics.paddleY - Metrics.paddleHeight / 2 else { return false }
        return abs(item.x - paddleX) <= paddleHalfWidth + halfW
    }

    private mutating func apply(_ kind: BlocksItemKind) {
        switch kind {
        case .widePaddle:
            // 重ねがけで太り続けないよう、**幅は固定で残り時間だけ**を上書きする。
            widePaddleRemaining = BlocksRules.widePaddleDuration
            // 広がったぶんが盤の外へはみ出さないよう入れ直す。
            movePaddle(to: paddleX)
        case .multiBall:
            splitBalls()
        }
    }

    /// 時間で切れる効果を進める。
    ///
    /// 切れてもパドルの位置は動かさない。**縮むときは可動域が広がるだけ**なので、
    /// いまの位置が盤の外へ出ることはない。
    private mutating func expireEffects(dt: Double) {
        guard widePaddleRemaining > 0 else { return }
        widePaddleRemaining = max(0, widePaddleRemaining - dt)
    }

    /// 動いている球を左右へ振り分けて増やす。上限は `BlocksRules.maxBalls`。
    ///
    /// 増やすのは**向きだけ**で、速さは元の球のまま（増えた球が速いと避けようが無くなる）。
    private mutating func splitBalls() {
        let spread = BlocksRules.multiBallSpread
        var added: [BlocksBall] = []
        for ball in balls where ball.isMoving {
            for sign in [1.0, -1.0] {
                guard balls.count + added.count < BlocksRules.maxBalls else { break }
                var copy = ball
                let rotated = Self.rotate(vx: ball.vx, vy: ball.vy, by: sign * spread)
                let clamped = BlocksPhysics.clampVertical(rotated)
                copy.vx = clamped.vx
                copy.vy = clamped.vy
                added.append(copy)
            }
        }
        balls.append(contentsOf: added)
    }

    private static func rotate(vx: Double, vy: Double, by angle: Double) -> BlocksPhysics.Velocity {
        BlocksPhysics.Velocity(
            vx: vx * cos(angle) - vy * sin(angle),
            vy: vx * sin(angle) + vy * cos(angle)
        )
    }
}
