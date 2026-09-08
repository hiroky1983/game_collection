import Core
import Foundation
import Observation

/// 横スクロールランナーの進行（#494）。
///
/// コースそのもの（走者・地形・当たり判定）は `RunnerField` が持ち、ここは
/// **ステージ進行・タイム・チェックポイント・記録・横断サービスへの通知**だけを担う。
/// SpriteKit には一切依存しないので、1 ステージ丸ごとをユニットテストで走らせられる。
@MainActor
@Observable
public final class RunnerModel {
    /// 永続化キー・解析・リーダーボードで使う ID。
    ///
    /// `nonisolated` にしておくのは、`RunnerModule` のような MainActor 外の文脈からも
    /// 参照するため（値は不変の文字列なので分離する必要がない）。
    public nonisolated static let gameID = "runner"

    public private(set) var field: RunnerField
    /// 1 始まりのステージ番号。
    public private(set) var stageNumber: Int
    public private(set) var phase: RunnerPhase
    /// このステージに挑み始めてからの経過秒。
    public private(set) var elapsed: Double
    /// ステージごとのベストタイム（秒）。0 は未クリア。
    public private(set) var bestSeconds: [Int]
    /// このステージでチェックポイント再開（リワード広告）を使ったか。1 ステージ 1 回まで。
    public private(set) var checkpointUsed: Bool
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// ゆっくりモード（アクセシビリティ）。切り替えると即座に効く。
    public private(set) var isSlowMode: Bool
    /// コースを作り直すたびに 1 増える連番。
    ///
    /// 描画側（`RunnerScene`）が「地形のノードを作り直すべきか」を判断するのと、
    /// 広告のロード中に別のコースへ移っていないかの照合（#509 と同じ契約）に使う。
    public private(set) var runGeneration = 0

    /// ボタンを押しているか。**押し直すまで次のジャンプは出ない**。
    ///
    /// 押しっぱなしにすると着地のたびに自動で跳んでしまい、「押して伸ばす」操作と
    /// 「跳ぶ」操作が同じ入力で衝突する。
    private var isPressed = false
    /// 一時停止する前の状態。`resume()` で戻す。
    private var phaseBeforePause: RunnerPhase = .ready
    private let services: GameServices?
    private let preference: FeedbackPreference

    /// 本番の入口。中断データがあれば復元し、無ければステージ 1 から始める。
    public convenience init(
        services: GameServices? = nil,
        preference: FeedbackPreference = .actionSlowMode
    ) {
        let restored = services?.snapshots
            .load(RunnerSnapshot.self, for: RunnerModel.gameID)?
            .validated()
        self.init(
            services: services,
            preference: preference,
            stage: restored?.stage ?? 1,
            bestSeconds: restored?.bestSeconds ?? Array(repeating: 0, count: RunnerRules.stageCount),
            isFreshStart: restored == nil
        )
    }

    /// 状態を直接与えて始める。テスト・プレビューから狙った局面を作るための入口。
    ///
    /// **`startingAt` のラベルは必須**にしてある。省略できると上の復元付きの入口と引数の並びが
    /// 重なり、`preference` を渡しただけで「復元しないほう」が黙って選ばれる
    /// （ブロック崩しで実際に中断復元のテストが素通りしかけた形）。
    public convenience init(
        services: GameServices? = nil,
        startingAt stage: Int,
        bestSeconds: [Int]? = nil,
        preference: FeedbackPreference = .actionSlowMode
    ) {
        self.init(
            services: services,
            preference: preference,
            stage: stage,
            bestSeconds: bestSeconds ?? Array(repeating: 0, count: RunnerRules.stageCount),
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
        bestSeconds: [Int],
        isFreshStart: Bool
    ) {
        self.services = services
        self.preference = preference
        let number = min(max(1, stage), RunnerRules.stageCount)
        self.stageNumber = number
        self.bestSeconds = bestSeconds
        self.checkpointUsed = false
        self.elapsed = 0
        self.phase = .ready
        self.isSlowMode = preference.isEnabled
        self.field = RunnerField(stage: RunnerStage.all[number - 1])
        persist()
        // 再描画で init が何度走っても増えない（`gameDidStart` は冪等）。
        if isFreshStart { services?.gameDidStart(gameID: Self.gameID) }
    }

    // MARK: - 問い合わせ

    /// 挑んでいるステージ。
    public var stage: RunnerStage { field.stage }
    /// このステージのベストタイム（秒）。未クリアなら nil。
    public var bestSecondsForCurrentStage: Int? { best(forStage: stageNumber) }
    /// ステージ番号（1 始まり）のベストタイム。未クリアなら nil。
    public func best(forStage number: Int) -> Int? {
        guard number >= 1, number <= bestSeconds.count else { return nil }
        let value = bestSeconds[number - 1]
        return value > 0 ? value : nil
    }
    /// チェックポイント再開を出せる状態か（通過済み・未使用・ミスした直後）。
    public var canResumeFromCheckpoint: Bool {
        phase == .failed && field.passedCheckpoint && !checkpointUsed
    }

    // MARK: - 操作

    /// ボタンを押した。走り出す前は「スタート」、走っている間は「ジャンプ」。
    public func press() {
        guard !isPressed else { return }
        isPressed = true
        switch phase {
        case .ready:
            phase = .running
            services?.feedback.impact(.rigid)
        case .running:
            if field.jump() { services?.feedback.impact(.light) }
        default:
            break
        }
    }

    /// ボタンを離した。これ以降このジャンプでは高さが伸びない。
    public func release() {
        isPressed = false
        field.endHold()
    }

    /// 一時停止。走っている / 走り出す前だけ効く（アクセシビリティ要件）。
    public func pause() {
        guard phase == .ready || phase == .running else { return }
        phaseBeforePause = phase
        phase = .paused
        // 押しっぱなしのまま止めると、再開した瞬間に押していない扱いとずれる。
        release()
    }

    /// 一時停止から戻る。
    public func resume() {
        guard phase == .paused else { return }
        phase = phaseBeforePause
    }

    /// ゆっくりモードの切り替え。設定へ保存し、走行中にも即座に効く。
    public func setSlowMode(_ enabled: Bool) {
        guard enabled != isSlowMode else { return }
        isSlowMode = enabled
        preference.isEnabled = enabled
    }

    /// 設定画面で変えられた値を取り込む（ゲーム画面へ戻ってきたときに呼ぶ）。
    public func syncSlowModeFromPreference() {
        setSlowMode(preference.isEnabled)
    }

    /// `dt` 秒ぶん進める。SpriteKit のゲームループから毎フレーム呼ばれる唯一の入口。
    ///
    /// **ゆっくりモードは走る速さではなく時間の進みを遅くする**（`RunnerRules.slowFactor`）。
    /// 速さだけを落とすとジャンプの飛距離が縮み、易しくするはずの設定が
    /// 「穴を跳び越せない = クリア不能」に変わる。
    public func tick(dt: Double) {
        guard phase.isRunning else { return }
        let step = min(dt, RunnerRules.maxStep) * (isSlowMode ? RunnerRules.slowFactor : 1)
        elapsed += step
        for event in field.step(dt: step) {
            guard phase.isRunning else { break }
            handle(event)
        }
    }

    /// ミスしたステージを頭からやり直す（無料・無制限）。
    public func retryStage() {
        guard phase == .failed else { return }
        startStage(from: 0, passedCheckpoint: false)
    }

    /// ステージクリアの表示から次のステージへ。
    public func advanceToNextStage() {
        guard phase == .cleared, stageNumber < RunnerRules.stageCount else { return }
        stageNumber += 1
        checkpointUsed = false
        startStage(from: 0, passedCheckpoint: false)
        // 1 ステージ = 1 プレイとして数え直す（#158。前のステージの `game_end` は送信済み）。
        services?.gameDidRestart(gameID: Self.gameID)
    }

    /// クリア済みのステージをもう一度走る（タイムアタック周回）。
    public func replayCurrentStage() {
        guard phase == .cleared || phase == .allCleared else { return }
        checkpointUsed = false
        startStage(from: 0, passedCheckpoint: false)
        services?.gameDidRestart(gameID: Self.gameID)
    }

    /// ステージ 1 からやり直す。
    public func newGame() {
        stageNumber = 1
        checkpointUsed = false
        startStage(from: 0, passedCheckpoint: false)
        services?.gameDidRestart(gameID: Self.gameID)
    }

    /// リワード広告の視聴後にチェックポイントから再開する。1 ステージ 1 回まで。
    ///
    /// - Parameter generation: 広告を出す前に控えた `runGeneration`。**広告のロード〜視聴の間に
    ///   「はじめから」等でコースが作り直されたら適用しない**（ソリティアの `grantUndos(forDeal:)` と
    ///   同じ契約。#509）。
    @discardableResult
    public func resumeFromCheckpoint(forRun generation: Int) -> Bool {
        guard canResumeFromCheckpoint, generation == runGeneration else { return false }
        checkpointUsed = true
        // タイムは続きから測る（ステージの頭に戻さないので経過秒も戻さない）。
        let resumedElapsed = elapsed
        startStage(from: stage.checkpoint, passedCheckpoint: true)
        elapsed = resumedElapsed
        return true
    }

    // MARK: - 内部

    /// 現在のステージのコースを作り直し、走り出す前の状態にする。
    private func startStage(from distance: Double, passedCheckpoint: Bool) {
        let stage = RunnerStage.all[stageNumber - 1]
        field = RunnerField(stage: stage, startingAt: distance, passedCheckpoint: passedCheckpoint)
        runGeneration += 1
        phase = .ready
        isPressed = false
        elapsed = 0
        recordResult = nil
        persist()
    }

    private func handle(_ event: RunnerEvent) {
        switch event {
        case .landed:
            services?.feedback.impact(.light)
        case .passedCheckpoint:
            services?.feedback.notify(.success)
        case .fell, .crashed:
            phase = .failed
            services?.feedback.notify(.error)
        case .reachedGoal:
            clearStage()
        }
    }

    private func clearStage() {
        let seconds = max(1, Int(elapsed.rounded()))
        // チェックポイント再開を使った回はベストタイムに残さない。ステージの半分しか
        // 走っていない回と通しで走った回を同じ表に混ぜない（#406 と同じ考え方）。
        if !checkpointUsed, best(forStage: stageNumber).map({ seconds < $0 }) ?? true {
            bestSeconds[stageNumber - 1] = seconds
        }
        services?.feedback.notify(.success)
        phase = stageNumber < RunnerRules.stageCount ? .cleared : .allCleared
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: .win,
            score: GameScore(
                metric: .points,
                // 記録は「到達ステージ数」。クリアした番号がそのまま到達点になる。
                points: stageNumber,
                // 広告で半分から再開した回は世界の順位表へ送らない（#406）。
                isLeaderboardEligible: !checkpointUsed
            )
        )
        persist()
    }

    /// 区切りの状態だけを保存する（規約どおりフレーム単位では保存しない）。
    ///
    /// **決着してもファイルは消さない**。ここにはステージごとのベストタイムが入っており、
    /// 消すと全ステージの記録がまとめて失われる。代わりに「次に開いたときどこから始めるか」を
    /// 書き換える（クリア表示中なら次のステージ、それ以外は今のステージ）。
    private func persist() {
        let resume: Int
        switch phase {
        case .cleared:    resume = min(stageNumber + 1, RunnerRules.stageCount)
        case .allCleared: resume = RunnerRules.stageCount
        default:          resume = stageNumber
        }
        try? services?.snapshots.save(
            RunnerSnapshot(stage: resume, bestSeconds: bestSeconds),
            for: Self.gameID
        )
    }

    #if DEBUG
    /// 撮影・動作確認用に狙った画面まで進める（起動引数 `-simulateRunner <名前>`）。
    ///
    /// 走行中・一時停止・ミス・クリアの画は、実機では**指で遊ばないと**出せない。
    /// シミュレータには自動タップの手段が無いため、`-simulateBlocks`（#463）と同じ形で
    /// 起動引数から状態を作る。DEBUG ビルド限定で、製品には入らない。
    public func applyDebugScenario(_ name: String) {
        switch name {
        case "running":
            press(); release()
            advanceFramesForDebug(seconds: 1.2)
        case "paused":
            press(); release()
            advanceFramesForDebug(seconds: 1.2)
            pause()
        case "failed":
            press(); release()
            // 跳ばずに走り続ければ、最初の障害で必ずミスになる。
            advanceFramesForDebug(seconds: 30)
        case "cleared":
            press(); release()
            autoPlayForDebug()
        default:
            break
        }
    }

    /// 指定秒ぶん 60fps で進める。
    private func advanceFramesForDebug(seconds: Double) {
        var remaining = seconds
        while remaining > 0, phase.isRunning {
            tick(dt: 1.0 / 60)
            remaining -= 1.0 / 60
        }
    }

    /// 地形を読んで自動で跳びながらゴールまで走る（撮影用）。
    ///
    /// 判断は `RunnerAutoPilot` に置いてある。**テストが全ステージのクリア可能性を
    /// 確かめるのに使うのと同じ関数**なので、撮影用にだけ都合の良い操作を書き足す余地がない。
    private func autoPlayForDebug() {
        var frames = 0
        while phase.isRunning, frames < 60 * 120 {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: field) { press(); release() }
            tick(dt: 1.0 / 60)
        }
    }
    #endif
}
