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
