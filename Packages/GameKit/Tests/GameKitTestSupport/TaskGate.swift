/// CPU の思考・盤の生成といった非同期タスクを、処理の開始直前で止めておくためのゲート（#172・#419。#529 で集約）。
///
/// 以前は「タスクを積んだ直後に空タスクを積む」という MainActor のジョブ順序で待ち合わせて
/// いたが、これは「空タスクが走る時点で処理がまだ終わっていない」ことまでは保証できない。
/// オセロは初期盤面の合法手が4手しかなく探索が軽いため、CI の巡り合わせによっては前提の
/// `#require(model.isThinking)` のほうが落ちて、無関係な PR のマージを止めていた。
///
/// ここではモデル側の待ち合わせ点（`thinkingGate` / `generationGate`）で処理を明示的に止め、
/// テストが `release()` を呼ぶまで先へ進ませない。到達も解放もテストが制御するため、処理の所要時間に依存しない。
@MainActor
public final class TaskGate {
    private var hasArrived = false
    private var isReleased = false
    private var onArrival: CheckedContinuation<Void, Never>?
    private var onRelease: CheckedContinuation<Void, Never>?

    public init() {}

    /// タスク側。ゲートへの到達を知らせ、`release()` まで停止する。
    public func wait() async {
        hasArrived = true
        onArrival?.resume()
        onArrival = nil
        guard !isReleased else { return }
        await withCheckedContinuation { onRelease = $0 }
    }

    /// テスト側。タスクがゲートに到達するまで待つ。
    public func waitUntilArrived() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { onArrival = $0 }
    }

    /// テスト側。止めていたタスクを先へ進ませる。
    public func release() {
        isReleased = true
        onRelease?.resume()
        onRelease = nil
    }
}
