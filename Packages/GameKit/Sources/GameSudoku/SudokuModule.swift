import SwiftUI
import Core

public struct SudokuModule: GameModule {
    public let id = "sudoku"
    // 表示名は「ナンプレ」。「数独／SUDOKU」は株式会社ニコリの登録商標（日本）のため
    // ユーザーに見える場所では使わない（会長決裁 2026-08-30・リバーシ 5.2.1 の再発防止）。
    // 内部 ID（"sudoku"）は非表示の識別子なので据え置く。
    public let title = "ナンプレ"
    public let description = "9×9のマスに1〜9を埋めよう"
    public var icon: Image { Image(systemName: "square.grid.3x3.fill") }
    public init() {}
    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(SudokuView(services: services))
    }


    /// 1 マスも入力していない盤は「続き」ではない（#1912）。出題直後は盤が出題マスだけ・メモ無し・ヒント未使用。
    /// 経過時間は手を入れなくても進むので見ない。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(SudokuSnapshot.self, for: id) else { return false }
        let entered = snap.board.indices.contains { index in
            index < snap.given.count && !snap.given[index] && snap.board[index] != 0
        }
        let noted = snap.notes.contains { $0 != 0 }
        return entered || noted || snap.hintsUsed > 0 || (snap.mistakes ?? 0) > 0
    }
}
