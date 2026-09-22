import Core
import Testing

/// 共通の走者ガード（`AITurnGuarded.withAITurnRunner`・#531）の単体テスト。
///
/// 花札・大富豪は本体のループ先頭でもキャンセルを見るため、ガード側の欠けがゲームのテストでは
/// 表に出ない。本体にキャンセル確認を持たない探針で、ガード単体の約束を固定する。
@MainActor
private final class RunnerProbe: AITurnGuarded {
    var isRunning = false
    var ran = false
}

@MainActor
@Suite("CPU 手番の共通ガード")
struct AITurnRunnerGuardTests {

    /// 待っている sleep がキャンセルで起きたのと同時に先行タスクが抜けると、待機ループは
    /// キャンセルを見ずに終わる。そこで走者を取ると、譲るべきタスクが手番を進めてしまう（PR #859 の CodeRabbit 指摘）。
    @Test("待機中にキャンセルされたタスクは、先行タスクが抜けても走者を取らない")
    func cancelledWaiterDoesNotTakeTheRunner() async {
        let probe = RunnerProbe()
        probe.isRunning = true
        let task = Task { @MainActor in
            await probe.withAITurnRunner(running: \.isRunning) { probe.ran = true }
        }
        // 後ろに積んだ空のジョブを待つ = task は待機ループの sleep に入っている。
        await Task { @MainActor in }.value
        // キャンセルと先行タスクの退出を同じ同期区間で起こす（task が起きる前に両方が確定する）。
        task.cancel()
        probe.isRunning = false
        await task.value

        #expect(!probe.ran, "キャンセル済みのタスクが走者を取って本体を走らせた")
        #expect(!probe.isRunning, "門番が残ると次の手番が始まらない")
    }

    @Test("先行タスクが抜けたら、キャンセルされていないタスクが引き継いで本体を走らせる")
    func waiterTakesOverAfterPredecessorExits() async {
        let probe = RunnerProbe()
        probe.isRunning = true
        let task = Task { @MainActor in
            await probe.withAITurnRunner(running: \.isRunning) { probe.ran = true }
        }
        await Task { @MainActor in }.value
        #expect(!probe.ran, "先行タスクが門番を握っている間は走らない")
        probe.isRunning = false
        await task.value

        #expect(probe.ran, "走者不在で本体が走らなかった")
        #expect(!probe.isRunning)
    }
}
