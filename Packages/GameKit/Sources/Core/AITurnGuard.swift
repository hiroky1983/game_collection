/// CPU 手番の再入・キャンセルガード（#531）。
///
/// `.task(id:)` から CPU を起動するモデルが守るべき定石を 1 か所に置く。定石をモデルごとに
/// 書き写していると、片方だけ欠けたときに「手番が止まる」「古い局面の手が新しい局面に指される」
/// のどちらかへ化けても気づけない（将棋 #145・大富豪 #287・麻雀 #311・花札 #726）。
///
/// - 読みを挟んで 1 手指すモデル（将棋・チェス・オセロ・五目並べ・囲碁）: `withAITurnGuard`
/// - 間合いを挟んで手番を連続で進めるモデル（麻雀・花札・大富豪）: `withAITurnRunner` と `pauseCPUTurn(for:)`
///
/// 準拠するだけで要件は無い。フラグやキーはキーパスで渡すので、各モデルの宣言（`private(set)` 等）はそのまま使える。
@MainActor
public protocol AITurnGuarded: AnyObject {}

extension AITurnGuarded {
    /// 開始時の `AITurnKey`（対局の通し番号 × 手数）を控えて `think` を待ち、完了時にキーが
    /// 一致する場合だけ `commit` を呼ぶ。読みの最中に新規対局・待ったが入ると、旧局面で選んだ手が
    /// 新しい局面に指されうるため（初期局面同士なら合法性の確認も通ってしまう）。
    ///
    /// `thinking` を渡すと、待っている間そのフラグを立てる。下ろすのは**同じ対局のまま**のときだけで、
    /// 別対局が始まっていたらフラグの持ち主は新しい対局のタスクなので触らない。
    /// 手番やフラグなど、キー以外の前提は `commit` の中で確かめ直すこと。
    public func withAITurnGuard<Value>(
        key: KeyPath<Self, AITurnKey>,
        thinking flag: ReferenceWritableKeyPath<Self, Bool>? = nil,
        think: () async -> Value,
        commit: (Value) -> Void
    ) async {
        let started = self[keyPath: key]
        if let flag { self[keyPath: flag] = true }
        defer {
            if let flag, self[keyPath: key].gameSerial == started.gameSerial { self[keyPath: flag] = false }
        }
        let value = await think()
        guard self[keyPath: key] == started else { return }
        commit(value)
    }

    /// 走者を 1 本に保ったまま `body` を走らせる。
    ///
    /// 「先行タスクがいたら即リターン」にすると、`.task(id:)` の差し替えで「新タスクが即リターン →
    /// 先行タスクがキャンセルで抜ける」の順になったとき走者が誰もいなくなり、キーはもう変わらないので
    /// 再起動も掛からず手番が止まる。そのため先行タスクの終了を待ってから引き継ぐ。待っている間に
    /// 自分もキャンセルされたら（さらに次のタスクへ差し替えられたら）そちらに譲って抜ける。
    public func withAITurnRunner(
        running flag: ReferenceWritableKeyPath<Self, Bool>,
        _ body: () async -> Void
    ) async {
        while self[keyPath: flag] {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        self[keyPath: flag] = true
        defer { self[keyPath: flag] = false }
        await body()
    }

    /// CPU の間合いを取る。キャンセルされていなければ `true`（そのまま手番を進めてよい）。
    ///
    /// `try? await Task.sleep` はキャンセルの `CancellationError` を握り潰して**即座に**返る。
    /// 戻ったあとにキャンセルを見ないと、画面を離れた瞬間に残りの CPU 手番が間合いゼロで走り抜け、
    /// その結果が中断データに残る。状態の guard は状態しか見ないので、これの代わりにはならない。
    public func pauseCPUTurn(for duration: Duration) async -> Bool {
        try? await Task.sleep(for: duration)
        return !Task.isCancelled
    }
}
