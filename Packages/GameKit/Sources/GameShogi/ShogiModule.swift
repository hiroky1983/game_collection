import SwiftUI
import Core

/// 将棋の `GameModule` 登録口。
public struct ShogiModule: GameModule {
    public let id = "shogi"
    public let title = "将棋"
    public let description = "CPU と本格的な将棋で対決しよう"
    public var icon: Image { Image(systemName: "square.grid.3x3.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(ShogiView(services: services))
    }

    /// 終局後の見返しも中断データに残る（`ShogiGameModel.persist`）。`.review` から対局へ戻る経路は
    /// `newGame` だけなので、検討に入った局には続きが無い（#809）。読めない中断データは Model も
    /// 新規対局として扱うので false。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        snapshots.load(ShogiSnapshot.self, for: id)?.phase == .playing
    }
}
