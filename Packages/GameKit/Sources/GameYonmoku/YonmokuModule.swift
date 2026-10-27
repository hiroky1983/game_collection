import SwiftUI
import Core

/// 四目並べ（#1738・企画倉庫）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
///
/// 表示名は一般名称の「四目並べ」（英語はローマ字の "Yonmoku Narabe"）。他社の商品名は使わない（#1738 の権利チェック）。
public struct YonmokuModule: GameModule {
    // **文字列リテラルで書く**（`YonmokuModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `YonmokuModel.gameID` との一致は `YonmokuModuleTests` が機械的に確かめる。
    public let id = "yonmoku"
    public var title: String { tr("四目並べ") }
    public var description: String { tr("上から石を落として、4 つ並べよう！CPU と対戦") }
    public var icon: Image { Image(systemName: "circle.grid.3x3.circle.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(YonmokuView(services: services))
    }

    /// 人間が一手も打っていない盤は「続き」ではない。人間が白のときは CPU の初手（黒）が先に入るので、
    /// それだけでは数えない（#2934。五目並べ・オセロと同じ #2508 の判定）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(YonmokuSnapshot.self, for: id) else { return false }
        return CPUOpening.humanHasMoved(totalMoves: snap.moves.count, cpuMovesFirst: snap.humanSide == YonmokuDisc.white.rawValue)
    }

    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        snapshots.exists(for: id) && !hasResumableSnapshot(in: snapshots)
    }
}
