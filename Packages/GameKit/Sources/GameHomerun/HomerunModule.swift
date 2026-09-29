import SwiftUI
import Core

/// 柵越えおじさん（#1348）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
///
/// いまの画面は段 3（2D の仮絵で一回遊べる形）。3D（RealityKit）・広告/アンケートでの回数回復・
/// 解析・Game Center は後続の段で足す。
///
/// 表示名「柵越えおじさん」は文字商標 0 件・同名アプリ 0 本（`docs/design/homerun/README.md` §4.1・
/// 正式な権利チェックは #1348 の関所）。
public struct HomerunModule: GameModule {
    // **文字列リテラルで書く**（`HomerunModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `HomerunModel.gameID` との一致は `HomerunModuleTests` が機械的に確かめる。
    public let id = "homerun"
    public let title = "柵越えおじさん"
    public let description = "1日3回、10球勝負。押したまま狙って離して振り、柵の向こうへ"
    public var icon: Image { Image(systemName: "figure.baseball") }
    /// 1 挑戦は途中から戻せない（打席に立った時点で回数を使う）ので中断データを持たない。
    /// 「途中のままです」のお知らせ（#663）の対象から外す。
    public var resumesFromSnapshot: Bool { false }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(HomerunView(services: services))
    }
}
