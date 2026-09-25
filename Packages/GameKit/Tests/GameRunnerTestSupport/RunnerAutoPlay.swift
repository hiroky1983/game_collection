import GameRunner

/// チャリンコおじさん（#494）を自動操縦で走らせるテスト用の部品（#1150）。
///
/// 横断のテスト（Analytics / Feedback / GameCenter / PlayRecord / ReviewRequest）と
/// `GameRunnerTests` が同じ塊を 6 つ持っていて、`RunnerPhase` にケースを 1 つ足すたびに
/// 全部を同時に直す必要があった（PR #1121 は 5 ターゲットを 4 行ずつ触っている）。
/// 製品の `GameRunner` にしか依存しないので、`GameKitTestSupport` ではなくここに置く。
public enum RunnerAutoPlay {
    /// 1 回の走行に許す最大フレーム数（60fps × 300 秒）。演出込みでも決着に十分な長さ。
    public static let defaultMaxFrames = 60 * 300
}

/// 自動操縦でいまのステージをゴールまで走らせる。
/// 判断は製品コードと同じ `RunnerAutoPilot`（撮影用の DEBUG シナリオも同じ関数を使う）。
/// - Returns: 決着したか（打ち切りに達したら false）。
@MainActor
@discardableResult
public func autoPlayCurrentStage(
    _ model: RunnerModel,
    maxFrames: Int = RunnerAutoPlay.defaultMaxFrames
) -> Bool {
    if model.phase == .ready {
        model.press()
        model.release()
    }
    var frames = 0
    // 決着の演出（`.falling` / ゴールの `.chasing`・#1092）は `isRunning` に含めない（演出中は
    // タップ・一時停止を効かせないための設計）ので、ここで打ち切らず `.failed` / `.cleared` に
    // 落ち着くまで回し続ける。
    while model.phase.isRunning || model.phase.isSettling, frames < maxFrames {
        frames += 1
        // 着地するまで離さない（`RunnerAutoPilot.shouldRelease`）。早く離すと `vy` が
        // 切り詰められて（会長QA「軽いタップなら本当に小ジャンプ」2026-09-10）
        // 地形を越えられなくなる。
        if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
        if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
        model.tick(dt: 1.0 / 60)
    }
    return frames < maxFrames
}

/// 跳ばずに走らせてミスさせる。
/// - Parameter stopAfterCheckpoint: チェックポイントを通過するまでは自動操縦で走り、
///   通過後に跳ぶのをやめてミスさせる（広告での再開が出せる状態を作る）。
@MainActor
public func failCurrentStage(
    _ model: RunnerModel,
    stopAfterCheckpoint: Bool = false,
    maxFrames: Int = RunnerAutoPlay.defaultMaxFrames
) {
    if model.phase == .ready {
        model.press()
        model.release()
    }
    var frames = 0
    // 同上: 演出時間ぶんも回して `.failed` まで進める。
    while model.phase.isRunning || model.phase.isSettling, frames < maxFrames {
        frames += 1
        // `stopAfterCheckpoint` のときだけ、チェックポイントを通過するまで自動操縦で走る。
        // それ以外は一度も跳ばないので、最初の障害で必ずミスになる。
        if stopAfterCheckpoint, !model.field.passedCheckpoint,
           RunnerAutoPilot.shouldJump(field: model.field) {
            model.press()
        }
        if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
        model.tick(dt: 1.0 / 60)
    }
}
