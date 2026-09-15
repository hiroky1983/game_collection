import SwiftUI
import Core

/// チェスの `GameModule` 登録口。
public struct ChessModule: GameModule {
    public let id = "chess"
    public let title = "チェス"
    public let description = "CPU と本格的なチェスで対決しよう"
    /// 市松模様。`crown.fill` は大富豪が使っているので避ける（ハブで同じ絵が2枚並ぶ）。
    public var icon: Image { Image(systemName: "checkerboard.rectangle") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(ChessView(services: services))
    }

    /// 将棋と同じく終局後の見返しも中断データに残る（`ChessGameModel.persist`）。検討に入った局には
    /// 続きが無い（#809）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        snapshots.load(ChessSnapshot.self, for: id)?.phase == .playing
    }
}
