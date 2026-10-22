import SwiftUI
import Core

/// おじさんちのねこさがし（#2250）の `GameModule` 登録口。
///
/// 企画倉庫から v1.1.14 でハブに公開（会長決裁 2026-10-22。名前・英語名 "Ojisan's Hidden Cats" も同日決定）。
///
/// 他社の名前（Nekodoku・Catdoku・Meowdoku・Petdoku 等）・絵・問題は使わない（Issue #2250 の権利の整理）。
public struct CatPuzzleModule: GameModule {
    // **文字列リテラルで書く**（`CatPuzzleModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `CatPuzzleModel.gameID` との一致は `CatPuzzleModuleTests` が機械的に確かめる。
    public let id = "catpuzzle"
    public var title: String { tr("おじさんちのねこさがし") }
    public var description: String { tr("家のどこかに隠れた飼い猫を、部屋ごとに1匹ずつ見つけよう") }
    public var icon: Image { Image(systemName: "cat.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(CatPuzzleView(services: services))
    }

    /// 印を 1 つでも付けた盤だけが「続き」（手つかずの盤はそもそも保存しない・#1847）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(CatPuzzleSnapshot.self, for: id) else { return false }
        return CatPuzzleSnapshot.isResumable(snap)
    }
}
