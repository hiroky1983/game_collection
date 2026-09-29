import SwiftUI
import Core

/// 2048 の `GameModule` 登録口。M2 で中身（ロジック・Model・操作）を実装する。
public struct Game2048Module: GameModule {
    public let id = "2048"
    public let title = "2048"
    public let description = "タイルを合体させて2048を目指そう"
    public var icon: Image { Image(systemName: "square.grid.2x2") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(Game2048View(services: services))
    }

    /// 開いただけで一度も動かしていない盤（初期タイル 2 個・得点 0）は「続き」ではない（#1572）。
    /// 一手動かすと、合体すれば得点が入り、しなければタイルが 3 個以上になるので、この 2 条件で見分けられる。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(Game2048Snapshot.self, for: id) else { return false }
        let tiles = snap.board.reduce(0) { $0 + $1.filter { $0 != 0 }.count }
        return snap.score > 0 || tiles > 2
    }
}
