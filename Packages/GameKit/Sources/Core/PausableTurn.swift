import Foundation

/// CPU 手番の `.task(id:)` の鍵。手番の鍵に「止めているか」を足し、止めた・再開したの両方でタスクを起こし直す（#2827）。
///
/// 開始シートや「？」（遊び方）を開いているあいだに CPU が先に着手すると、シートの裏で盤が動き
/// `game_start` の過剰計上や裏での読み上げを招く（#3218）。CPU 手番の `.task` を持つ View は
/// `.task(id: PausableTurn(key:, paused:))` とし、本体の先頭で `guard !paused` する。
public struct PausableTurn: Equatable {
    public let key: AITurnKey
    public let paused: Bool

    public init(key: AITurnKey, paused: Bool) {
        self.key = key
        self.paused = paused
    }
}

extension PausableTurn {
    /// 先行タスクの読み（`isThinking`）が終わるまで待つ。キャンセルされたら `false`（そのまま抜ける）。
    ///
    /// 読みの最中にシートを開閉すると `.task(id:)` が作り直され、旧タスクは取り消されて着手を確定しない。
    /// なのに旧タスクの `isThinking` は読みが終わるまで残るので、新タスクが `performAIMoveIfNeeded` を
    /// すぐ呼ぶと即 return し、キーはもう変わらないため CPU の手番が止まったままになる（#3218 のレビュー指摘）。
    /// 先行の読みが終わるのを待ってから呼べば、取り消された手番をやり直せる。
    @MainActor
    public static func waitWhileThinking(_ isThinking: () -> Bool) async -> Bool {
        while isThinking() {
            guard !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return !Task.isCancelled
    }
}
