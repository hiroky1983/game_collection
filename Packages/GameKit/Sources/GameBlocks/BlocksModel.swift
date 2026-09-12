import Core
import Foundation
import Observation

/// ブロック崩しの進行（#463）。
///
/// 盤面そのもの（球・パドル・ブロック）は `BlocksField` が持ち、ここは
/// **得点・残機・ステージ進行・中断復元・横断サービスへの通知**だけを担う。
/// SpriteKit には一切依存しないので、1 プレイ丸ごとをユニットテストで再生できる。
@MainActor
@Observable
public final class BlocksModel {
    /// 永続化キー・解析・リーダーボードで使う ID。
    ///
    /// `nonisolated` にしておくのは、`BlocksModule` のような MainActor 外の文脈からも
    /// 参照するため（値は不変の文字列なので分離する必要がない）。
    public nonisolated static let gameID = "blocks"

    public private(set) var field: BlocksField
    public private(set) var score: Int
    public private(set) var lives: Int
    /// 1 始まりのステージ番号。
    public private(set) var stageNumber: Int
    public private(set) var phase: BlocksPhase
    /// コンティニュー（リワード広告）を使ったか。1 プレイにつき 1 回まで。
    public private(set) var continueUsed: Bool
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// ゆっくりモード（アクセシビリティ）。設定の値をそのまま持ち、切り替えると即座に球へ効く。
    public private(set) var isSlowMode: Bool
    /// バー伸長が効いているか（#599）。画面の札の出し入れに使う。
    ///
    /// `field` は毎フレーム変わるため、画面が `field.isPaddleWide` を直接読むと
    /// **効果と関係なく毎フレーム再評価される**。ここで鏡を持ち、変わったときだけ代入することで
    /// `@Observable` の通知もそのときだけになる。
    public private(set) var isPaddleWide = false
    /// 盤を作り直すたびに 1 増える連番。
    ///
    /// 描画側（`BlocksScene`）が「ブロックのノードを作り直すべきか」を判断するのに使う。
    /// ステージ番号で見ると、ステージ 1 で「はじめから」を選んだときに番号が変わらず
    /// 崩し終えた盤がそのまま残る。
    public private(set) var fieldGeneration = 0

    /// 一時停止する前の状態。`resume()` で戻す。
    private var phaseBeforePause: BlocksPhase = .ready
    private let services: GameServices?
    private let preference: FeedbackPreference

    /// 本番の入口。中断スナップショットがあれば復元し、無ければステージ 1 から始める。
    public convenience init(
        services: GameServices? = nil,
        preference: FeedbackPreference = .actionSlowMode
    ) {
        let snapshot = services?.snapshots.load(BlocksSnapshot.self, for: BlocksModel.gameID)
        self.init(
            services: services,
            preference: preference,
            stage: snapshot?.stage ?? 1,
            score: snapshot?.score ?? 0,
            lives: snapshot?.lives ?? BlocksRules.initialLives,
            continueUsed: snapshot?.continueUsed ?? false,
            isFreshStart: snapshot == nil
        )
    }

    /// 状態を直接与えて始める。テスト・プレビューから狙った局面を作るための入口。
    ///
    /// **`startingAt` のラベルは必須**にしてある。省略できると上の復元付きの入口と
    /// 引数の並びが重なり、`preference` を渡しただけで「復元しないほう」が黙って選ばれる
    /// （実際にそれで中断復元のテストが素通りしかけた）。
    public convenience init(
        services: GameServices? = nil,
        startingAt stage: Int,
        score: Int = 0,
        lives: Int = BlocksRules.initialLives,
        continueUsed: Bool = false,
        preference: FeedbackPreference = .actionSlowMode
    ) {
        self.init(
            services: services,
            preference: preference,
            stage: stage,
            score: score,
            lives: lives,
            continueUsed: continueUsed,
            isFreshStart: true
        )
    }

    /// 唯一の指定イニシャライザ。
    ///
    /// `isFreshStart` は解析（#158）の数え方だけに効く。中断からの復元は「新しいプレイ」では
    /// ないので `game_start` を送らない。
    private init(
        services: GameServices?,
        preference: FeedbackPreference,
        stage: Int,
        score: Int,
        lives: Int,
        continueUsed: Bool,
        isFreshStart: Bool
    ) {
        self.services = services
        self.preference = preference
        self.score = score
        self.lives = lives
        self.continueUsed = continueUsed
        self.stageNumber = min(max(1, stage), BlocksRules.stageCount)
        self.phase = .ready
        let slow = preference.isEnabled
        self.isSlowMode = slow
        let number = min(max(1, stage), BlocksRules.stageCount)
        let stageDefinition = BlocksStage.all[number - 1]
        self.field = BlocksField(
            stage: stageDefinition,
            speed: Self.speed(of: stageDefinition, slow: slow)
        )
        persist()
        // 再描画で init が何度走っても増えない（`gameDidStart` は冪等）。
        if isFreshStart { services?.gameDidStart(gameID: Self.gameID, level: .stage(stageNumber)) }
    }

    // MARK: - 操作

    /// パドルを動かす。発射前は球も一緒に動く。
    public func movePaddle(to x: Double) {
        guard phase == .ready || phase == .playing else { return }
        field.movePaddle(to: x)
    }

    /// 球を発射する。
    public func launch() {
        guard phase == .ready else { return }
        field.launch()
        phase = .playing
        // 球が出た = 捨てたら途中離脱として数える盤面（#500）。
        services?.gameDidProgress(gameID: Self.gameID)
        services?.feedback.impact(.rigid)
    }

    /// 一時停止。`.ready` / `.playing` のときだけ効く（アクセシビリティ要件）。
    public func pause() {
        guard phase == .ready || phase == .playing else { return }
        phaseBeforePause = phase
        phase = .paused
    }

    /// 一時停止から戻る。止める前の状態（発射前 / 進行中）へ戻す。
    public func resume() {
        guard phase == .paused else { return }
        phase = phaseBeforePause
    }

    /// ゆっくりモードの切り替え。設定へ保存し、進行中の球にも即座に効く。
    public func setSlowMode(_ enabled: Bool) {
        guard enabled != isSlowMode else { return }
        isSlowMode = enabled
        preference.isEnabled = enabled
        field.setSpeed(Self.speed(of: BlocksStage.all[stageNumber - 1], slow: enabled))
    }

    /// 設定画面で変えられた値を取り込む（ゲーム画面へ戻ってきたときに呼ぶ）。
    ///
    /// 書き手は 1 か所（設定画面とポーズ画面）だが、`GameSettings` は App 層にあり
    /// GameKit からは見えないため、保存された値を読み直す形で同期する。
    public func syncSlowModeFromPreference() {
        setSlowMode(preference.isEnabled)
    }

    #if DEBUG
    /// テスト・撮影用に球の状態を直接置く。
    ///
    /// 落球の直前・ブロックの真下といった局面へ、通常の操作だけで到達しようとすると
    /// 数百フレームの再生が要り、検証がフレーム数と反射の偶然に依存してしまう。
    /// 製品コードからは呼ばない。呼び出し元は下の `applyDebugScenario` 側（同じく DEBUG 限定）と
    /// テストだけなので、Release ビルドからは丸ごと落とす（#514）。
    public func placeBallForTesting(x: Double, y: Double, vx: Double, vy: Double) {
        field.placeBall(x: x, y: y, vx: vx, vy: vy)
    }

    /// テスト・撮影用にアイテムを直接落とす（#599）。
    ///
    /// `field` は `private(set)` なので、盤面側の同名の入口へはここを通さないと届かない。
    public func dropItemForTesting(kind: BlocksItemKind, x: Double, y: Double) {
        field.dropItemForTesting(kind: kind, x: x, y: y)
    }
    #endif

    /// `dt` 秒ぶん進める。SpriteKit のゲームループから毎フレーム呼ばれる唯一の入口。
    public func tick(dt: Double) {
        #if DEBUG
        // 撮影用に時間だけを止める（#599）。一時停止と違って局面は `.playing` のままなので、
        // 結果パネルに隠れない素の盤面を撮れる。
        if isFrozenForDebug { return }
        #endif
        guard phase == .playing else { return }
        let events = field.step(dt: min(dt, BlocksRules.maxStep))
        for event in events {
            // 落球やステージクリアで状態が変わったら、同じフレームの残りは処理しない。
            guard phase == .playing else { break }
            handle(event)
        }
        syncEffects()
    }

    /// 効果の鏡（`isPaddleWide`）を盤面に合わせる。**変わったときだけ**代入する。
    private func syncEffects() {
        if isPaddleWide != field.isPaddleWide { isPaddleWide = field.isPaddleWide }
    }

    /// ステージクリアの表示から次のステージへ。
    public func advanceToNextStage() {
        guard phase == .stageCleared, stageNumber < BlocksRules.stageCount else { return }
        stageNumber += 1
        startStage()
    }

    /// 「はじめから」で失われる進行があるか（#515）。
    ///
    /// 誤タップで得点・ステージが丸ごと消えるのを防ぐため、画面側はこれが true のときだけ
    /// 確認を挟む。決着後（`gameOver` / `allCleared`）はもう失うものが無いので false
    /// （リザルトの「はじめから」に確認を挟むと、遊び直しの導線が一手増えるだけになる）。
    public var hasProgressToLose: Bool {
        guard !phase.isFinished else { return false }
        return score > 0 || stageNumber > 1 || phase == .playing
    }

    /// はじめから遊び直す。
    public func newGame() {
        stageNumber = 1
        score = 0
        lives = BlocksRules.initialLives
        continueUsed = false
        recordResult = nil
        startStage()
        services?.gameDidRestart(gameID: Self.gameID, level: .stage(stageNumber))
    }

    /// リワード広告の視聴後にコンティニューする。残機 1 で、落ちたステージの頭から再開する。
    ///
    /// 中断復元と同じ「ステージ頭から」に揃えてある（同じゲームの中に 2 通りの再開地点を作らない）。
    ///
    /// - Parameter generation: 広告を出す前に控えた `fieldGeneration`。**広告のロード〜視聴の間に
    ///   「はじめから」で盤が作り直されたら適用しない**。照合しないと、報酬が別の局に乗って
    ///   `cancelLoss` まで走る（ソリティアの `grantUndos(forDeal:)` と同じ契約。#509）。
    @discardableResult
    public func continueAfterAd(forRun generation: Int) -> Bool {
        guard phase == .gameOver, !continueUsed, generation == fieldGeneration else { return false }
        // 同じ 1 プレイの続きなので、直前に記録した「負け」は無かったことにする。
        services?.playLog?.cancelLoss(gameID: Self.gameID)
        recordResult = nil
        continueUsed = true
        lives = BlocksRules.continueLives
        startStage()
        // `game_end` は送信済みなので、続きは次の 1 プレイとして数え直す（#158）。
        services?.gameDidRestart(gameID: Self.gameID, level: .stage(stageNumber))
        return true
    }

    // MARK: - 内部

    /// 現在のステージ番号で盤を作り直し、ステージ頭の状態を保存する。
    private func startStage() {
        let stage = BlocksStage.all[stageNumber - 1]
        field = BlocksField(stage: stage, speed: Self.speed(of: stage, slow: isSlowMode))
        fieldGeneration += 1
        syncEffects()
        phase = .ready
        persist()
    }

    private func handle(_ event: BlocksEvent) {
        switch event {
        case .wallBounce:
            // 壁の反射は 1 秒に何度も起きるので鳴らさない（音が途切れなくなる）。
            break
        case .paddleBounce:
            services?.feedback.impact(.rigid)
        case .blockHit(_, _, let kind, let destroyed):
            score += BlocksScoring.blockPoints(kind: kind, destroyed: destroyed, stage: stageNumber)
            services?.feedback.impact(destroyed ? .medium : .light)
            if field.isCleared { clearStage() }
        case .itemCaught:
            // **得点は動かさない**（#599）。効果そのものは `BlocksField` が適用済みで、
            // ここでやるのは取れたと分かる手応えを返すことだけ。
            services?.feedback.notify(.success)
        case .ballLost:
            loseLife()
        }
    }

    private func loseLife() {
        lives -= 1
        guard lives > 0 else {
            phase = .gameOver
            services?.feedback.notify(.error)
            finish(outcome: .loss)
            return
        }
        services?.feedback.notify(.warning)
        field.resetBall()
        syncEffects()
        phase = .ready
        // 減った残機をその場で保存する。しないと、落球のたびに強制終了すれば
        // ステージ頭の残機へ戻せてしまい、広告コンティニューより条件が良くなる（#508）。
        persist()
    }

    private func clearStage() {
        score += BlocksScoring.stageClearBonus(stage: stageNumber, remainingLives: lives)
        services?.feedback.notify(.success)
        guard stageNumber < BlocksRules.stageCount else {
            phase = .allCleared
            finish(outcome: .win)
            return
        }
        phase = .stageCleared
        persist()
    }

    private func finish(outcome: GameOutcome) {
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: outcome,
            score: GameScore(
                metric: .points,
                points: score,
                // コンティニューを使った回は世界の順位表へ送らない（#406 と同じ考え方）。
                // 広告を見た回数で順位が決まる表にしないため。手元の自己ベストには残す。
                isLeaderboardEligible: !continueUsed
            )
        )
        services?.snapshots.clear(for: Self.gameID)
    }

    /// 区切りの状態だけを保存する（規約どおりフレーム単位では保存しない）。
    /// 保存するのはステージ頭・落球直後・ステージクリア直後の 3 か所。
    private func persist() {
        guard !phase.isFinished else { return }
        // クリア表示中に中断したら、進み先（次のステージ頭）として保存する。
        // 表示中のステージ番号のまま保存すると、崩し終えたステージをボーナス込みの
        // 得点でもう一度遊べてしまう。
        let resumeStage = phase == .stageCleared ? stageNumber + 1 : stageNumber
        try? services?.snapshots.save(
            BlocksSnapshot(
                stage: resumeStage,
                score: score,
                lives: lives,
                continueUsed: continueUsed
            ),
            for: Self.gameID
        )
    }

    private static func speed(of stage: BlocksStage, slow: Bool) -> Double {
        stage.ballSpeed * (slow ? BlocksRules.slowFactor : 1)
    }

    #if DEBUG
    /// 撮影用に時間を止めているか（#599）。
    ///
    /// 状態を作って放置すると、シャッターを切るまでの数秒で球が落ち、アイテムも画面外へ出て
    /// **狙ったのと別の画になる**。`pause()` では結果パネルが盤を覆ってしまうので、
    /// 局面はそのままに `tick` だけを止める。
    private var isFrozenForDebug = false

    /// 撮影・動作確認用に狙った画面まで進める（起動引数 `-simulateBlocks <名前>`）。
    ///
    /// 一時停止・ステージクリア・ゲームオーバーの画は、実機では**指で遊ばないと**出せない。
    /// シミュレータには自動タップの手段が無いため、`-simulate2048Move`（#438）と同じ形で
    /// 起動引数から状態を作る。DEBUG ビルド限定で、製品には入らない。
    public func applyDebugScenario(_ name: String) {
        switch name {
        case "playing":
            launch()
            breakBlocksForDebug(limit: 14)
        case "paused":
            launch()
            breakBlocksForDebug(limit: 14)
            pause()
        case "cleared":
            launch()
            breakBlocksForDebug(limit: .max)
        case "itemdrop":
            // 1 個目（バー伸長）が落ちてくる途中の画。パドルはまだ素の幅（#599）。
            launch()
            breakBlocksForDebug(limit: BlocksRules.itemDropInterval)
            parkBallForDebug(frames: 120)
            isFrozenForDebug = true
        case "items":
            // アイテムが 1 個落ちてくる途中で、1 個目（バー伸長）は受け取り済みの画（#599）。
            launch()
            catchNextItemForDebug()
            breakBlocksForDebug(limit: BlocksRules.itemDropInterval)
            parkBallForDebug(frames: 90)  // アイテムが盤の中ほどまで落ちるのを待つ
            isFrozenForDebug = true
        case "multiball":
            // 2 個目（球増加）まで受け取って球が 3 個ある画（#599）。
            launch()
            catchNextItemForDebug()
            catchNextItemForDebug()
            isFrozenForDebug = true
        case "gameover":
            var guardCount = 0
            while !phase.isFinished, guardCount < 100 {
                guardCount += 1
                launch()
                movePaddle(to: 5)
                placeBallForTesting(x: BlocksField.Metrics.width - 5, y: 5, vx: 0, vy: -60)
                // 落ちるまで**進め続ける**。1 フレームだけ進めて位置を置き直すと
                // 球が床に届かず、残機がいつまでも減らない（無限ループになる）。
                var frames = 0
                while phase == .playing, frames < 60 {
                    frames += 1
                    tick(dt: 1.0 / 60)
                }
            }
        default:
            break
        }
    }

    /// 壊せるブロックを上から順に `limit` 個まで消す。球を狙ったブロックの中心へ置いて
    /// 1 フレーム進めるだけなので、反射の偶然に左右されない。
    private func breakBlocksForDebug(limit: Int) {
        var broken = 0
        var guardCount = 0
        while broken < limit, phase == .playing, guardCount < 4_000 {
            guardCount += 1
            guard let target = firstBreakableForDebug() else { break }
            let rect = BlocksField.blockRect(row: target.row, column: target.column)
            placeBallForTesting(x: rect.midX, y: rect.midY, vx: 0, vy: 1)
            let before = field.remainingBreakableCount
            tick(dt: 1.0 / 60)
            if field.remainingBreakableCount < before { broken += 1 }
        }
        // 撮影で球が変な場所に残らないよう、盤の中ほどへ戻す（**上向き**にしておかないと
        // シャッターを切る前に落ちて残機が減った画になる）。
        if phase == .playing {
            placeBallForTesting(x: field.paddleX, y: BlocksField.Metrics.height * 0.3, vx: 22, vy: 30)
        }
    }

    /// 次のアイテムが出るまでブロックを壊し、落ちてくるのをパドルで受け止める（#599）。
    ///
    /// アイテムは落下に約 3 秒かかるので、そのあいだ球を落とさないよう毎フレーム同じ場所へ
    /// 置き直す（実際には進まない）。**止まった球にはしない**: 球増加は動いている球を
    /// 振り分けて増やすので、速度が 0 だと何も起きない。
    private func catchNextItemForDebug() {
        breakBlocksForDebug(limit: BlocksRules.itemDropInterval)
        guard let item = field.items.first else { return }
        movePaddle(to: item.x)
        var frames = 0
        while !field.items.isEmpty, phase == .playing, frames < 900 {
            frames += 1
            parkBallForDebug(frames: 1)
        }
        // 増えた球は同じ点から出るので、重なったままだと 1 個に見える。少し離れるまで進める。
        var spread = 0
        while phase == .playing, spread < 60 {
            spread += 1
            tick(dt: 1.0 / 60)
        }
    }

    /// 球を落とさずに時間だけ進める。
    ///
    /// 毎フレーム同じ場所へ置き直すので球は実際には動かない。**速度は持たせる**:
    /// 球増加は動いている球を振り分けて増やすので、速度 0 だと何も起きない。
    private func parkBallForDebug(frames: Int) {
        for _ in 0..<frames {
            placeBallForTesting(
                x: field.paddleX,
                y: BlocksField.Metrics.height * 0.3,
                vx: 0,
                vy: 20
            )
            tick(dt: 1.0 / 60)
        }
    }

    private func firstBreakableForDebug() -> (row: Int, column: Int)? {
        for row in 0..<field.rowCount {
            for column in 0..<BlocksField.Metrics.columns
            where field.block(row: row, column: column)?.isBreakable == true {
                return (row, column)
            }
        }
        return nil
    }
    #endif
}
