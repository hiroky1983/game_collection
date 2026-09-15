import Core
import Foundation
import Observation

/// 横スクロールランナーの進行（#494）。
///
/// コースそのもの（走者・地形・当たり判定）は `RunnerField` が持ち、ここは
/// **ステージ進行・到達面・チェックポイント・記録・横断サービスへの通知**だけを担う。
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
    /// 遊び方のモード（#675）。**走行の開始時に焼き込み、走行中は読み替えない**
    /// （`docs/ai-devops.md`「1局=1RuleSet」）。切り替わるのは `newGame(mode:)` の 1 か所だけ。
    public private(set) var mode: RunnerMode = .stages
    /// エンドレスのコースを作った種（ステージ制では nil）。同じ種なら同じコースになるので、
    /// 不具合の再現に使う。**中断データには保存しない**（1 回完結・会長決裁）。
    public private(set) var endlessSeed: UInt64?
    /// エンドレスの自己ベスト（走行距離・ワールド単位）。`PlayLog` の区分 `endless` から読み、
    /// 決着のたびに手元でも更新する（記録を持たない構成でも画面に出せるように）。
    public private(set) var endlessBestDistance: Int?
    /// 直前のエンドレスの決着で自己ベストを更新したか。リザルトのバッジに使う。
    public private(set) var didSetBestDistance = false
    /// 1 始まりのステージ番号。エンドレス中も**そのまま保持する**（戻ってきたときの続き）。
    public private(set) var stageNumber: Int
    /// 到達した最大のステージ番号（1 始まり・#798）。ワールドマップで選べる面の上限で、
    /// 常に `stageNumber` 以上。クリアで次の面が到達済みになり、面を選んで遊んでも巻き戻らない。
    /// 中断データ（`RunnerSnapshot.reachedStage`）に残す。
    public private(set) var reachedStage: Int
    public private(set) var phase: RunnerPhase
    /// いまの走行でチェックポイント再開（リワード広告）を使ったか。**1 回の走行につき 1 回まで**。
    /// 「もう一度」で頭から走り直せば戻る（会長決裁 2026-09-15・#958。以前は 1 ステージ 1 回で、
    /// クリアできない面で 2 回目以降が頭からだけになり離脱につながるとの判断）。
    public private(set) var checkpointUsed: Bool
    /// 直前のクリアで**初めて次の面に到達した**か（`reachedStage` が伸びた）。クリア表示の
    /// 「新しい面に到達！」のバッジに使う（#931。秒数の廃止で「ベストタイム更新！」の代わり）。
    /// 到達済みの面を選び直してクリアしても立たない。
    public private(set) var didReachNewStage = false
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
    /// `.falling` に入ってからの経過秒。`RunnerRules.fallDuration` に達すると `.failed` へ移る。
    private var fallElapsed: Double = 0
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
            reachedStage: restored?.reachedStage ?? 1,
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
        preference: FeedbackPreference = .actionSlowMode
    ) {
        self.init(
            services: services,
            preference: preference,
            stage: stage,
            // 狙った局面から始めるので、その面までは到達済みとみなす。
            reachedStage: stage,
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
        reachedStage: Int,
        isFreshStart: Bool
    ) {
        self.services = services
        self.preference = preference
        let number = min(max(1, stage), RunnerRules.stageCount)
        self.stageNumber = number
        // 到達点は再開面より前にはならない（`RunnerSnapshot.validated()` と同じ丸め）。
        self.reachedStage = min(max(number, reachedStage), RunnerRules.stageCount)
        self.checkpointUsed = false
        self.phase = .ready
        self.isSlowMode = preference.isEnabled
        self.field = RunnerField(stage: RunnerStage.all[number - 1])
        self.endlessBestDistance = services?.playLog?
            .record(gameID: Self.gameID, variant: RunnerMode.endless.recordVariant)?
            .bestPoints
        persist()
        // 再描画で init が何度走っても増えない（`gameDidStart` は冪等）。
        if isFreshStart {
            services?.gameDidStart(
                gameID: Self.gameID, level: .stage(stageNumber), mode: RunnerMode.stages.analyticsMode
            )
        }
    }

    // MARK: - 問い合わせ

    /// 挑んでいるステージ。
    public var stage: RunnerStage { field.stage }
    /// 走行距離（ワールド単位）。エンドレス（#675）の記録はこの値の整数部。
    public var distance: Double { field.distance }
    /// 走行距離の表示・記録用の値（m）。**1 タイル（`RunnerRules.tileWidth` 単位）＝ 1 m** と
    /// 数える。ワールド単位のままだと 400 区画で 25,600 m・時速 140 km 超の表示になり実感と
    /// 合わないため（社長レビュー 2026-09-14）。6,400 m を 8 分前後で走る＝時速 48 km ほど。
    public var distanceMeters: Int { Int(field.distance / RunnerRules.tileWidth) }
    /// ステージ番号（1 始まり）が到達済み（ワールドマップで選べる）か（#798）。
    /// 1 面は常に到達済み。範囲外は false。
    public func isStageReached(_ number: Int) -> Bool {
        number >= 1 && number <= min(reachedStage, RunnerRules.stageCount)
    }
    /// スタート画面（#931）で、モードや面を選び直せる状態か。
    ///
    /// 真ならスタート画面に「次の面」「エンドレス」「マップ」の 3 つを出し、偽の `.ready`
    /// （チェックポイント再開の直後）は「つづきから」の 1 つだけにする——広告を見て手に入れた
    /// 途中からの再開を、誤タップで捨てさせない。純関数版は `canChooseMode(phase:passedCheckpoint:)`。
    public var canChooseMode: Bool {
        Self.canChooseMode(phase: phase, passedCheckpoint: field.passedCheckpoint)
    }

    /// `canChooseMode` の実体。走り出す前（`.ready`）で、コースの頭にいるときだけ真。
    public static func canChooseMode(phase: RunnerPhase, passedCheckpoint: Bool) -> Bool {
        phase == .ready && !passedCheckpoint
    }

    /// チェックポイント再開を出せる状態か（通過済み・未使用・ミスした直後）。
    public var canResumeFromCheckpoint: Bool {
        // エンドレスにチェックポイントは無い（1 回完結・#675）。
        mode == .stages && phase == .failed && field.passedCheckpoint && !checkpointUsed
    }
    /// 1 回の走行が終わって、リザルトを出している状態か。
    ///
    /// ステージ制は全ステージクリアだけが「終わり」で、ミスは何度でもやり直せる途中。
    /// エンドレスはミスした時点で 1 回が終わり、コースを走り切った場合も同じ扱い。
    public var isRunOver: Bool {
        switch mode {
        case .stages:  return phase == .allCleared
        case .endless: return phase == .failed || phase == .allCleared
        }
    }

    // MARK: - 操作

    /// ボタンを押した。走り出す前は「スタート」、走っている間は「ジャンプ」。
    public func press() {
        guard !isPressed else { return }
        isPressed = true
        switch phase {
        case .ready:
            beginRun()
        case .running:
            // 跳ぶ音（#703）。踏み切りが成立したときだけ鳴らす——二段目も同じく成立すれば鳴り、
            // 三度目（`RunnerRules.maxJumps` 超え）や押しっぱなしでは鳴らない。
            if field.jump() { services?.feedback.impact(.light) }
        default:
            break
        }
    }

    /// 走り出す前（`.ready`）から走行中へ。フィールドのタップ（`press`）・スタート画面の
    /// ボタン（`start(_:)`）・面をまたぐ導線（`retryStage` / `advanceToNextStage` /
    /// `replayCurrentStage`・#941）の共通の実体。
    private func beginRun() {
        phase = .running
        // 走り出した = 捨てたら途中離脱として数える走行（#500）。
        services?.gameDidProgress(gameID: Self.gameID)
        // このゲームの中断データは再開する面と到達点の控えで、決着後も消さない
        // （消すと到達点が失われる）。走行そのものは復元せず必ずステージの頭から
        // 始まるので、「中断データが在る = 続きから戻れる」の既定を打ち消す（PR #572 の指摘）。
        services?.gameWillNotResume(gameID: Self.gameID)
        services?.feedback.impact(.rigid)
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
        if phase == .falling {
            // 演出中は `field.step` を呼ばない。物理を進め続けると走者が穴の底・画面外まで
            // 無限に落ち続けてしまう（`field` はミスした瞬間の状態で凍らせたままにする）。
            fallElapsed += dt
            if fallElapsed >= RunnerRules.fallDuration { phase = .failed }
            return
        }
        guard phase.isRunning else { return }
        #if DEBUG
        // 撮影用に止めているあいだは進めない（下記 `applyDebugScenario` を参照）。
        if isFrozenForCapture { return }
        #endif
        let step = min(dt, RunnerRules.maxStep) * (isSlowMode ? RunnerRules.slowFactor : 1)
        for event in field.step(dt: step) {
            guard phase.isRunning else { break }
            handle(event)
        }
    }

    /// ミスしたステージを頭からやり直す（無料・無制限）。
    ///
    /// ステージ制は**その場で走り出す**（#941。面をまたぐたびにスタート画面を挟んで
    /// もう 1 タップさせない、会長指示 2026-09-15）。
    /// エンドレス（#675）では**新しい種でもう 1 回**走る（コースを走り切った後も同じ）。
    /// 同じコースを走り直す導線は出さない——「冒頭は同じ・以降は毎回違う」が決裁の形で、
    /// 同じ並びを覚えて距離を伸ばすモードにはしない。ミスの時点で 1 回が決着しているので、
    /// 次の 1 回は新しいプレイとして数え直す（ステージ制のやり直しは同じプレイの続き）。
    /// エンドレスの「もう一度」はこれまでどおりスタート画面（`.ready`）に戻す（#941 の対象外）。
    public func retryStage() {
        switch mode {
        case .stages:
            guard phase == .failed else { return }
            // 頭からの走り直しは新しい走行。再開権（広告）も戻す（#958）。
            checkpointUsed = false
            startStage(from: 0, passedCheckpoint: false)
            beginRun()
        case .endless:
            guard isRunOver else { return }
            startEndless(seed: Self.randomSeed())
            services?.gameDidRestart(gameID: Self.gameID, mode: mode.analyticsMode)
        }
    }

    /// ステージクリアの表示から次のステージへ。スタート画面を挟まず**その場で走り出す**（#941）。
    ///
    /// 解析の順序は `gameDidRestart`（新しいプレイの `game_start`）→ `beginRun`（そのプレイの
    /// `gameDidProgress`）。逆にすると「1 手指した」印が終わった前のプレイに付き、新しいプレイを
    /// 途中で捨てても `game_end`（quit）が出なくなる。
    public func advanceToNextStage() {
        guard mode == .stages, phase == .cleared, stageNumber < RunnerRules.stageCount else { return }
        stageNumber += 1
        checkpointUsed = false
        startStage(from: 0, passedCheckpoint: false)
        // 1 ステージ = 1 プレイとして数え直す（#158。前のステージの `game_end` は送信済み）。
        services?.gameDidRestart(gameID: Self.gameID, level: .stage(stageNumber), mode: mode.analyticsMode)
        beginRun()
    }

    /// クリア済みのステージをもう一度走る。`advanceToNextStage` と同じくその場で走り出す（#941）。
    public func replayCurrentStage() {
        guard mode == .stages, phase == .cleared || phase == .allCleared else { return }
        checkpointUsed = false
        startStage(from: 0, passedCheckpoint: false)
        services?.gameDidRestart(gameID: Self.gameID, level: .stage(stageNumber), mode: mode.analyticsMode)
        beginRun()
    }

    /// いまのモードではじめから。ステージ制はステージ 1 から、エンドレスは新しい種で。
    public func newGame() {
        newGame(mode: mode)
    }

    /// モードを選んではじめから（開始シート・#675）。ここが**モードを焼き込む唯一の入口**。
    ///
    /// ステージ制はステージ 1 から（従来の「はじめから」と同じ）。エンドレスは新しい種で
    /// コースを作る。どちらも走行中のプレイを捨てて数え直す（`gameDidRestart` が、捨てた
    /// プレイに 1 手でも動きがあれば `game_end`（quit）を先に送る・#500）。
    public func newGame(mode newMode: RunnerMode) {
        switch newMode {
        case .stages:
            startStages(at: 1)
        case .endless:
            newEndlessGame(seed: Self.randomSeed())
        }
    }

    /// ワールドマップで選んだ面からステージ制をはじめから（#798）。
    ///
    /// **到達済みの面しか受け付けない**（`isStageReached`）。未到達なら何もせず false を返す
    /// ——画面側は未到達の面を押せなくしてあるが、二重に守る。1 面を渡せば
    /// `newGame(mode: .stages)` と同じ。到達点（`reachedStage`）は下の面を選んでも動かないので、
    /// 選んで遊んだあとに開き直しても先の面が選べなくなることはない。
    @discardableResult
    public func newGame(startingAtStage number: Int) -> Bool {
        guard isStageReached(number) else { return false }
        startStages(at: number)
        return true
    }

    /// ステージ制を `number` 面の頭から始め直す。`newGame(mode:)` / `newGame(startingAtStage:)` の実体。
    ///
    /// 走行中のプレイを捨てて数え直す（`gameDidRestart` が、捨てたプレイに 1 手でも動きがあれば
    /// `game_end`（quit）を先に送る・#500）。解析の `level` は選んだ面の番号（1 面から順に
    /// 進んだときの `advanceToNextStage` と同じ形）。
    private func startStages(at number: Int) {
        mode = .stages
        stageNumber = number
        checkpointUsed = false
        startStage(from: 0, passedCheckpoint: false)
        services?.gameDidRestart(
            gameID: Self.gameID, level: .stage(stageNumber), mode: mode.analyticsMode
        )
    }

    /// 種を指定してエンドレスをはじめから（#675）。
    ///
    /// 実プレイは `newGame(mode: .endless)` が毎回ランダムな種で呼ぶ。種を外から渡せるのは
    /// **同じコースを再現するため**——テストの決定論と、撮影（`-simulateRunner endless`）で
    /// 毎回同じ画を撮るため。
    public func newEndlessGame(seed: UInt64) {
        mode = .endless
        startEndless(seed: seed)
        services?.gameDidRestart(gameID: Self.gameID, mode: mode.analyticsMode)
    }

    /// スタート画面（#931）のボタンで走り出す。開始シートを経ずにモードを選んで**その場で走り出す**入口。
    ///
    /// **走り出す前（`.ready`）だけ効き**、走行中・一時停止中・リザルトでは何もしない。
    /// いまのモードと同じなら、作ってあるコースをそのまま走り出す（`press()` と同じ。エンドレスの
    /// 種はそのまま——「もう一度」で作った新しいコースを二重に作り直さない）。
    /// モードが違えば作り直してから走り出す:
    /// - ステージ制へは**「つづき」の面（`stageNumber`）**から。エンドレス中も `stageNumber` は
    ///   保持してあるので、ハブから開いたときと同じ面に戻る。1 面や到達点（`reachedStage`）に
    ///   飛ばないのは、開始シートの「はじめから」と区別するため。
    /// - エンドレスへは新しい種で（`newGame(mode: .endless)` と同じ）。
    ///
    /// モードの切り替えは `canChooseMode` のときだけ——チェックポイント再開の直後は、広告で得た
    /// 途中からの再開を捨てさせない（画面側はそのとき「つづきから」しか出さないが、二重に守る）。
    ///
    /// - Returns: 走り出したか。
    @discardableResult
    public func start(_ newMode: RunnerMode) -> Bool {
        guard phase == .ready else { return false }
        if newMode != mode {
            guard canChooseMode else { return false }
            switch newMode {
            case .stages:  startStages(at: stageNumber)
            case .endless: newEndlessGame(seed: Self.randomSeed())
            }
        }
        // ボタンからの開始なので押下の状態は持ち込まない（押しっぱなしのジャンプにしない）。
        isPressed = false
        beginRun()
        return true
    }

    /// リワード広告の視聴後にチェックポイントから再開する。1 回の走行につき 1 回まで（「もう一度」で戻る・#958）。
    ///
    /// ここは走り出さず `.ready` に置く（#941 の対象外）——広告から戻った直後に不意に走り出さない
    /// よう、スタート画面の「つづきから」1 つを押してもらう。
    ///
    /// - Parameter generation: 広告を出す前に控えた `runGeneration`。**広告のロード〜視聴の間に
    ///   「はじめから」等でコースが作り直されたら適用しない**（ソリティアの `grantUndos(forDeal:)` と
    ///   同じ契約。#509）。
    @discardableResult
    public func resumeFromCheckpoint(forRun generation: Int) -> Bool {
        guard canResumeFromCheckpoint, generation == runGeneration else { return false }
        checkpointUsed = true
        startStage(from: stage.checkpoint, passedCheckpoint: true)
        return true
    }

    // MARK: - 内部

    /// 現在のステージのコースを作り直し、走り出す前の状態にする。
    ///
    /// `.ready` に置くだけで走り出さない。走り出すかは呼び出し側が決める——ハブから入った直後
    /// （`init`）・「はじめから」・マップで面を選んだとき（`startStages`）・チェックポイント再開は
    /// スタート画面を出し、面をまたぐ導線（#941）は続けて `beginRun()` を呼ぶ。
    private func startStage(from distance: Double, passedCheckpoint: Bool) {
        let stage = RunnerStage.all[stageNumber - 1]
        // 挑み始めた面は到達済み（#798）。次の面へ進んだとき・QA 用の `stage:N` で飛んだときも
        // ここを通るので、到達点の更新はこの 1 か所と `clearStage`（次の面を開ける）だけ。
        reachedStage = max(reachedStage, stageNumber)
        resetRun(RunnerField(stage: stage, startingAt: distance, passedCheckpoint: passedCheckpoint))
        persist()
    }

    /// 種からエンドレスのコースを作り、走り出す前の状態にする（#675）。
    ///
    /// `mode` は呼び出し側（`newGame(mode:)` / `retryStage()`）が確定させてから来る。
    /// 中断データには触れない（`persist` を呼ばない）——エンドレスは 1 回完結で、
    /// アプリを閉じたら消える（会長決裁）。ステージ制の続き（`stageNumber`）はそのまま残る。
    private func startEndless(seed: UInt64) {
        endlessSeed = seed
        resetRun(RunnerField(stage: RunnerEndlessCourse.makeStage(seed: seed)))
    }

    /// 新しいコースで走り出す前の状態に戻す。ステージ制・エンドレス・QA用の差し替えで共通。
    private func resetRun(_ newField: RunnerField) {
        field = newField
        runGeneration += 1
        phase = .ready
        isPressed = false
        fallElapsed = 0
        recordResult = nil
        didReachNewStage = false
        didSetBestDistance = false
    }

    /// エンドレスの種。実プレイでは毎回ランダム（種を注入した再現は `RunnerEndlessCourse` の
    /// 入口から行う）。
    private static func randomSeed() -> UInt64 {
        var generator = SystemRandomNumberGenerator()
        return generator.next()
    }

    private func handle(_ event: RunnerEvent) {
        // 手応え（触覚と、それに相乗りする効果音）。対応表は `RunnerFeedbackCue` に置いてある。
        // 演出の土煙・紙吹雪は `RunnerScene` が出す。
        // エンドレス（#675）にチェックポイントは無い（`RunnerStage` が中点に計算はするが、
        // 標識も出さず・再開もさせず・手応えも返さない）。
        if !(mode == .endless && event == .passedCheckpoint) {
            services?.feedback.play(
                RunnerFeedbackCue.cue(for: event, lastLandingWasJust: field.lastLandingWasJust)
            )
        }
        switch event {
        case .landed, .passedCheckpoint, .collectedSpeedItem, .collectedInvincibleItem, .boarCharging, .dogBarking:
            break
        case .fell, .crashed:
            // 即座に `.failed` にはせず、短い演出（`RunnerScene`）を挟んでから移る（会長QA）。
            phase = .falling
            fallElapsed = 0
            // 死因を解析に覚えさせる（#796）。イベントは出ず、このプレイの `game_end` に載る。
            if let cause = field.lastMissCause {
                services?.gameDidMiss(gameID: Self.gameID, cause: cause)
            }
            // エンドレスはミスした時点で 1 回が決着する（#675）。記録は演出を待たずに確定させ、
            // 演出明けの `.failed` のリザルトに出す。
            if mode == .endless { finishEndlessRun(outcome: .loss) }
        case .reachedGoal:
            switch mode {
            case .stages:
                clearStage()
            case .endless:
                // 固定長（`RunnerRules.endlessSegments`）を走り切った。第 1 弾はここで打ち切り、
                // 走った距離をそのまま記録する（真の無限は第 2 弾・Issue #675）。
                phase = .allCleared
                finishEndlessRun(outcome: .win)
            }
        }
    }

    /// エンドレスの 1 回を記録する（#675）。
    ///
    /// 記録は**走行距離**（`GameScore(metric: .points)`・`distanceMeters`。1 タイル＝1 m）。区分
    /// `RunnerMode.endless.recordVariant` で保存するので、ステージ制の到達ステージ数
    /// （区分 nil）とは別の行になり、互いを汚さない。順位表は `asobiba.runner.distance`
    /// （`GameCenterLeaderboard.runnerDistance`）。コンティニューは無いので常に送信対象。
    ///
    /// ミスで終わる回は `.loss`、走り切った回は `.win`（2048 のゲームオーバーと同じ数え方。
    /// 毎回を勝ちにすると通算勝利数の実績が走るたびに進んでしまう）。
    private func finishEndlessRun(outcome: GameOutcome) {
        let meters = distanceMeters
        // 同点は更新扱いにしない（`PlayRecord.applying` と同じ規則）。
        didSetBestDistance = meters > (endlessBestDistance ?? Int.min)
        if didSetBestDistance { endlessBestDistance = meters }
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: outcome,
            score: GameScore(
                metric: .points,
                points: meters,
                variant: mode.recordVariant,
                variantLabel: mode.recordVariantLabel
            )
        )
    }

    private func clearStage() {
        #if DEBUG
        // QA用ショーケース（`RunnerStage.debugShowcase`、`number == 0`）は `stageNumber` を
        // 動かさない差し替えなので、ここを素通りすると**通常ステージの記録を誤って上書きする**
        // （CodeRabbit指摘）。ショーケースのクリアは記録を一切書かずに打ち切る。
        guard field.stage.number > 0 else {
            phase = .allCleared
            return
        }
        #endif
        phase = stageNumber < RunnerRules.stageCount ? .cleared : .allCleared
        // クリアした面の次がワールドマップで選べるようになる（#798）。下の面を選んで
        // クリアしても `max` なので到達点は戻らない。到達点が伸びた回だけ
        // 「新しい面に到達！」（#931。秒数の廃止で記録の主役は到達面）。
        let nextReached = max(reachedStage, min(stageNumber + 1, RunnerRules.stageCount))
        didReachNewStage = nextReached > reachedStage
        reachedStage = nextReached
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
    /// **決着してもファイルは消さない**。ここには到達点（`reachedStage`）が入っており、
    /// 消すとワールドマップで選べる面が 1 面に戻る。代わりに「次に開いたときどこから始めるか」を
    /// 書き換える（クリア表示中なら次のステージ、それ以外は今のステージ）。
    /// 旧形式のベストタイム（`RunnerSnapshot.bestSeconds`）は空で書く（#931）。
    private func persist() {
        // エンドレスは保存しない（1 回完結・#675）。書くべき値（ステージ番号・到達点）は
        // エンドレス中に変わらないので、書いても壊れはしないが、意図として呼ばない。
        guard mode == .stages else { return }
        let resume: Int
        switch phase {
        case .cleared:    resume = min(stageNumber + 1, RunnerRules.stageCount)
        case .allCleared: resume = RunnerRules.stageCount
        default:          resume = stageNumber
        }
        try? services?.snapshots.save(
            RunnerSnapshot(stage: resume, reachedStage: reachedStage),
            for: Self.gameID
        )
    }

    #if DEBUG
    /// 撮影中はゲームループを止める（`-simulateRunner` の静止画用）。
    ///
    /// 走るゲームなので、状態を作って放っておくと**シャッターを切る前に先へ進んでしまう**
    /// （最初の撮影では「走行中」を撮ったつもりが、待っているあいだに最初の穴へ落ちて
    /// ミスの画になった）。止まったブロック崩しと違い、狙った画を撮るには時間ごと
    /// 止める必要がある。DEBUG ビルド限定で、製品には入らない。
    private var isFrozenForCapture = false
    /// 撮影用のエンドレスの種（#675）。毎回同じコースを撮るための固定値で、意味は無い。
    private static let captureSeed: UInt64 = 675

    /// 撮影・動作確認用に狙った画面まで進める（起動引数 `-simulateRunner <名前>`）。
    ///
    /// 走行中・一時停止・ミス・クリアの画は、実機では**指で遊ばないと**出せない。
    /// シミュレータには自動タップの手段が無いため、`-simulateBlocks`（#463）と同じ形で
    /// 起動引数から状態を作る。
    public func applyDebugScenario(_ name: String) {
        switch name {
        case "running":
            press(); release()
            // 最初の障害を跳び越している最中で止める（走っていることが 1 枚で分かる画）。
            autoPlayForDebug(until: { $0.field.altitude > RunnerRules.jumpApex * 0.6 })
            isFrozenForCapture = true
        case "pedaling":
            press(); release()
            // 漕いでいる画を撮る。`running` は空中で止めるので、そちらは `jump` のコマになる（#569）。
            // 漕ぐコマは 2 枚（#701）で、`ride0` は走り出す前と同じ絵なので、**左ペダルが前の
            // `ride1` が出る瞬間**で止める。シーンは最初の反映で「それまでに進んだ距離」を
            // まとめて位相に足すので、凍らせた画のコマは接地距離だけで決まる。
            autoPlayForDebug(until: {
                $0.field.isGrounded && $0.field.distance > 34
                    && RunnerRider.pedalFrame(
                        phase: RunnerRider.phase(forGroundedDistance: $0.field.distance)
                    ) == .ride1
            })
            isFrozenForCapture = true
        case "paused":
            press(); release()
            autoPlayForDebug(until: { $0.field.distance > 80 })
            pause()
        case "failed":
            press(); release()
            // 跳ばずに走り続ければ、最初の障害で必ずミスになる。
            advanceFramesForDebug(seconds: 30)
        case "cleared":
            press(); release()
            autoPlayForDebug(until: { _ in false })
        case "showcase":
            // QA用: 低い障害物・高い障害物・鳥・穴3サイズを1本で見比べる（`RunnerStage.debugShowcase`）。
            // `.ready` のまま渡すので、実機・シミュレータで普通にタップして遊べる。
            applyDebugStage(.debugShowcase)
        case "bird":
            // 飛び立つ前（羽ばたきの予備動作中）で止める（#796 の受け入れ条件の画 1/3）。
            // ショーケース（`RunnerStage.debugShowcase`）の鳥を使う。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                guard let bird = model.field.stage.hazards.first(where: { $0.kind == .bird }) else { return true }
                return model.field.distance >= bird.birdTakeoffDistance - RunnerRules.birdFlutterDistance / 2
            })
            isFrozenForCapture = true
        case "bird-low":
            // 飛び立った直後、まだ頭より低いところを上がっている途中（画 2/3・#945）。
            // 帯の下端が止まっていた上端（5）を越え、頭（11）にはまだ届いていないところで止める
            // ——おじさんはまだ手前を走っている。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                guard let bird = field.stage.hazards.first(where: { $0.kind == .bird }),
                      let frame = bird.frame(atRunnerDistance: field.distance) else { return true }
                return frame.bottom >= RunnerHazardKind.birdLowTop
                    && frame.bottom < RunnerField.Metrics.playerHeight
            })
            isFrozenForCapture = true
        case "bird-up":
            // 上がりきった鳥の真下を走ったまま抜けている瞬間（画 3/3・#945 の受け入れ条件そのもの）。
            // 接地したまま帯と横に重なったところで止める——帯の下端は頭の 3 上（`birdMeetBottom`）。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                guard let bird = field.stage.hazards.first(where: { $0.kind == .bird }),
                      let frame = bird.frame(atRunnerDistance: field.distance) else { return true }
                return field.isGrounded && frame.bottom >= RunnerHazardKind.birdMeetBottom
                    && field.playerMaxX > frame.start && field.playerMinX < frame.end
            })
            isFrozenForCapture = true
        case "dog":
            // 犬が走者の真横〜少し前を抜ける瞬間（#944）。跳んでいる走者の中心を犬の左端が
            // 越えた最初のフレーム（犬の箱が走者の右半分に重なり、足の下を抜けていく画）で止める。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                guard let dog = field.stage.hazards.first(where: { $0.kind == .dog }),
                      let frame = dog.frame(atRunnerDistance: field.distance) else { return false }
                return !field.isGrounded && frame.start >= field.distance
            })
            isFrozenForCapture = true
        case "boar":
            // イノシシが画面に入って突進している瞬間（#801）。出会う手前で止める。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                guard let boar = field.stage.hazards.first(where: { $0.kind == .boar }),
                      let frame = boar.frame(atRunnerDistance: field.distance) else { return false }
                return field.isGrounded && frame.start - field.distance < 40
            })
            isFrozenForCapture = true
        case "platform":
            // 台座の上を走っている瞬間で止める（#674 の受け入れ条件「台座の上を走っている瞬間」の画）。
            // 本番では台座は 16 面以降にしか出ないので、ショーケースの台座を使う。端から 8 単位
            // 内側に入ってから止め、乗った直後・降りる直前の画にならないようにする。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                return field.isGrounded
                    && field.stage.platforms.contains { $0.start + 8 <= field.distance && field.distance < $0.end - 8 }
            })
            isFrozenForCapture = true
        case "floor":
            // スピードアップ床の上を走っている瞬間で止める（#672 の受け入れ条件の画）。
            // 区間に入って 20 単位進んだところで止め、矢印模様が走者の足元に見えるようにする。
            applyDebugStage(.debugShowcase)
            press(); release()
            autoPlayForDebug(until: { model in
                let field = model.field
                return field.isOnBoostFloor
                    && field.stage.boostFloors.contains { $0.start + 20 <= field.distance }
            })
            isFrozenForCapture = true
        case "invincible":
            // たこ焼き（#797）を取って無敵のまま最初の岩に重なっている瞬間で止める
            // （受け入れ条件「無敵中に岩へ当たっても crashed が出ない」「残り時間が画面で分かる」の画）。
            // 本番では 4 面以降にしか出ないので、ショーケースの `k`（最初の岩の直前）を使う。
            // 自動操縦は無敵でも岩の手前で跳んでしまうので、**跳ばずに**走らせて岩の中に
            // 居る瞬間（接地したまま岩と重なっている＝無敵でなければミスの位置）で止める。
            applyDebugStage(.debugShowcase)
            press(); release()
            var frames = 0
            while phase.isRunning, frames < 60 * 30 {
                let field = self.field
                guard let rock = field.stage.hazards.first(where: { $0.kind != .pit }) else { break }
                if field.isInvincible, field.playerMaxX > rock.start, field.playerMinX < rock.end { break }
                frames += 1
                tick(dt: 1.0 / 60)
            }
            isFrozenForCapture = true
        case "endless":
            // エンドレス（#675）の走り出す前の画。上部セクションが「走行距離」表示に変わる。
            // 種を固定して毎回同じコースを撮る。
            newEndlessGame(seed: Self.captureSeed)
        case "endless-running":
            // エンドレスの走行中（距離が伸びている画）。冒頭の固定区画（#930 で 4 区画に短縮）を
            // 抜けたランダム区画で、跳んでいる最中の瞬間で止める（距離 600 超・跳躍の 6 割以上）。
            newEndlessGame(seed: Self.captureSeed)
            press(); release()
            autoPlayForDebug(until: { $0.field.distance > 600 && $0.field.altitude > RunnerRules.jumpApex * 0.6 })
            isFrozenForCapture = true
        case "endless-failed":
            // エンドレスのリザルト（走行距離・自己ベスト）。冒頭を自動操縦で抜けてから
            // 跳ぶのをやめ、ランダム区画の最初の障害でミスさせる。
            newEndlessGame(seed: Self.captureSeed)
            press(); release()
            autoPlayForDebug(until: { $0.field.distance > 700 })
            advanceFramesForDebug(seconds: 60)
        case let name where name.hasPrefix("bird:"):
            // 本番ステージの鳥を、その面の世界の背景の上で撮る（例 `-simulateRunner bird:5`）。
            // `bird` はショーケースで走るので、面ごとの世界の配色で鳥が見分けられるか（#818）は
            // こちらで確かめる。最初の鳥が走者の少し前方（画面の中央付近）に来た接地中の瞬間で止める。
            if let number = Int(name.dropFirst("bird:".count)),
               RunnerStage.stage(number: number)?.hazards.contains(where: { $0.kind == .bird }) == true {
                stageNumber = number
                startStage(from: 0, passedCheckpoint: false)
                press(); release()
                autoPlayForDebug(until: { model in
                    let field = model.field
                    guard let bird = field.stage.hazards.first(where: { $0.kind == .bird }) else { return true }
                    return field.isGrounded && (8...45).contains(bird.start - field.distance)
                })
                isFrozenForCapture = true
            }
        case let name where name.hasPrefix("map:"):
            // 撮影用: ワールドマップ（#798）の到達面を作る（例 `-simulateRunner map:8` で 8 面まで到達済み）。
            // 開始シートは `RunnerView` が `-showRunnerStartSheet` で開く。
            if let number = Int(name.dropFirst("map:".count)) {
                reachedStage = min(max(number, 1), RunnerRules.stageCount)
            }
        case let name where name.hasPrefix("stage:"):
            // QA用: 本番ステージを番号で指定して最初から遊ぶ（例 `-simulateRunner stage:16`）。
            // 後半の面を確かめるのに 1 面目から遊び直す手間を省く（会長QA 2026-09-12）。
            // `applyDebugStage` ではなく `stageNumber` ごと差し替える——番号を動かさないと、
            // ミスして「もう一度」を押した瞬間に `startStage` が 1 面目を読み直す
            // （会長QA「ミスると元のステージに戻る」）。ヘッダーの番号も記録先もその面になる。
            if let number = Int(name.dropFirst("stage:".count)),
               RunnerStage.stage(number: number) != nil {
                stageNumber = number
                startStage(from: 0, passedCheckpoint: false)
            }
        default:
            break
        }
    }

    /// `RunnerStage.all` を経由せず、任意のステージ定義で走らせ直す（QA用）。
    ///
    /// `stageNumber`（ヘッダーの「ステージ N/18」表示・到達点の記録先）はそのまま
    /// 動かさない。「もう一度」「はじめから」を押すと `startStage` が `RunnerStage.all` から
    /// 引き直すので、ショーケースからは抜ける——QA専用の一時的な差し替えとして割り切る。
    private func applyDebugStage(_ customStage: RunnerStage) {
        resetRun(RunnerField(stage: customStage))
    }

    /// 指定秒ぶん 60fps で進める。
    ///
    /// `.falling` は `isRunning` に含めていないので、ミスの演出中で止まらないよう
    /// ループの継続条件にも加える（そうしないと `-simulateRunner failed` が `.falling` で
    /// 止まってしまい `.failed` の画が撮れない）。
    private func advanceFramesForDebug(seconds: Double) {
        var remaining = seconds
        while remaining > 0, phase.isRunning || phase == .falling {
            tick(dt: 1.0 / 60)
            remaining -= 1.0 / 60
        }
    }

    /// 地形を読んで自動で跳びながら、`until` が真になるかゴールに着くまで走る（撮影用）。
    ///
    /// 判断は `RunnerAutoPilot` に置いてある。**テストが全ステージのクリア可能性を
    /// 確かめるのに使うのと同じ関数**なので、撮影用にだけ都合の良い操作を書き足す余地がない。
    private func autoPlayForDebug(until stop: (RunnerModel) -> Bool) {
        var frames = 0
        while phase.isRunning, !stop(self), frames < 60 * 120 {
            frames += 1
            // 着地するまで離さない（`RunnerAutoPilot.shouldRelease` を参照。早く離すと
            // ジャンプが切り詰められて越えられない）。
            if RunnerAutoPilot.shouldJump(field: field) { press() }
            if RunnerAutoPilot.shouldRelease(field: field) { release() }
            tick(dt: 1.0 / 60)
        }
    }
    #endif
}
