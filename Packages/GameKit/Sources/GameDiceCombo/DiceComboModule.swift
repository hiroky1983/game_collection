import SwiftUI
import Core

/// サイコロ役づくり（#1752）の `GameModule` 登録口。
///
/// 企画倉庫（`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」）の段階では
/// `AppEnvironment.registry` への登録行がコメントアウトされている。出荷する版が決まったら
/// そのコメントアウトを外すだけでハブに並ぶ。
///
/// 表示名は市販のダイスゲームの商品名（「ヨット」「ヤッツィー」「Yahtzee」「Yatzy」など）を使わず、
/// 一般的な言い方の「サイコロ役づくり」（英語は "Dice Combos"）にした。5 個そろいの役の名前も
/// 同じ理由で「ファイブダイス」にしている（Issue #1752 の権利チェック）。
public struct DiceComboModule: GameModule {
    // **文字列リテラルで書く**（`DiceComboModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため。
    public let id = "dicecombo"
    public var title: String { tr("サイコロ役づくり") }
    public var description: String { tr("サイコロ5個を3回まで振って、12の役に点を入れていこう") }
    public var icon: Image { Image(systemName: "dice.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(DiceComboView(services: services))
    }

    /// 開いただけで一度も振っていない局は「続き」ではない（#1847）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(DiceComboSnapshot.self, for: id) else { return false }
        return !snap.isUntouched
    }

    /// 保存はあるが一度も振っていない局（#2161）。
    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(DiceComboSnapshot.self, for: id) else { return false }
        return snap.isUntouched
    }
}
