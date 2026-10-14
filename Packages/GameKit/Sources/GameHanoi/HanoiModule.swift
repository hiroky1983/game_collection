import SwiftUI
import Core

/// ハノイの塔の `GameModule` 登録口（#2003・企画倉庫。ハブの登録行はコメントアウトのまま）。
public struct HanoiModule: GameModule {
    public let id = "hanoi"
    public var title: String { tr("ハノイの塔") }
    public var description: String { tr("円盤を1枚ずつ動かして、右の柱へ全部移そう") }
    public var icon: Image { Image(systemName: "square.stack.3d.up.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(HanoiView(services: services))
    }

    /// 1 手でも動かした盤だけが「続き」（手つかずの盤はそもそも保存しない・#1847）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(HanoiSnapshot.self, for: id) else { return false }
        return snap.moves > 0
    }
}
