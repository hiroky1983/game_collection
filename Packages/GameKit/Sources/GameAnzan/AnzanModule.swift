import SwiftUI
import Core

/// ぱっと暗算（#1321）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
///
/// 表示名は「フラッシュ暗算」にしない。日本で現存する登録商標（登録第4801121号・株式会社
/// グリーン・フィールド・第9類/第41類）のため、規程「日本で商標なら採用しない」に従って言い換えた
/// （Issue #1321 の権利チェック）。
public struct AnzanModule: GameModule {
    // **文字列リテラルで書く**（`AnzanModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    // `AnzanModel.gameID` との一致は `ModuleTests` が機械的に確かめる。
    public let id = "anzan"
    public let title = "ぱっと暗算"
    public let description = "パッと出て消える数を足していこう。桁数・個数・速さを選べる"
    public var icon: Image { Image(systemName: "sum") }
    /// 中断データは最後に選んだ難易度の控えで、問題そのものは復元しない（表示のタイミングで成り立つ
    /// ゲームなので途中から戻せない）。「途中のままです」のお知らせ（#663）の対象から外す。
    public var resumesFromSnapshot: Bool { false }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(AnzanView(services: services))
    }
}
