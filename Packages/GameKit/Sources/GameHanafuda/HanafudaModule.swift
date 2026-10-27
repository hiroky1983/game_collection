import Core
import SwiftUI

/// 花札こいこいの `GameModule` 登録口（#495）。
///
/// 表示名・ID は権利チェック（Issue #495 の記録）の結論に従う。`花札` `こいこい` とも
/// ゲーム区分の商標は確認できなかったため通称をそのまま採るが、**「花札オンライン」型の
/// 名称だけは避ける**（そらいろ㈱ 登録5903259 が「花札 ONLINE」の組合せ商標を第9類で保有）。
public struct HanafudaModule: GameModule {
    // **文字列リテラルで書く**（`HanafudaModel.gameID` を参照しない）。LP の顔ぶれ照合
    // （`Scripts/check-lp-game-list.sh`）が `public let id = "..."` を静的に読み取るため、
    // 定数参照にすると slug を突き合わせられずに CI が落ちる。
    // `HanafudaModel.gameID` との一致は `ModuleTests` が機械的に確かめる。
    public let id = "hanafuda"
    // 表示名・説明は表示言語で引く（#2166）。英語も「Online」の組合せと酒の役名は載せない。
    public var title: String { tr("花札こいこい") }
    public var description: String { tr("CPUと役を競う。こいこいで倍を狙おう") }
    // 和風の看板。ハブに並ぶ他ゲームに草花のアイコンは無く、ひと目で見分けられる。
    public var icon: Image { Image(systemName: "leaf.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(HanafudaView(services: services))
    }


    /// 配っただけで一枚も出していない 1 局目は「続き」ではない（#1912）。開始シートで確定した直後に保存される。
    /// 親が CPU のときは CPU の初手が先に入るが、人間は何も出していないので続きではない（#3000）。
    /// 人間の手札が 8 枚のまま・取り札なし・選択待ちでないことで見分ける。
    /// 2 局目以降の配り直しは前の局の結果があるので続きとして扱う。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(HanafudaSnapshot.self, for: id) else { return false }
        return !Self.isUntouched(snap)
    }

    /// 保存はあるが配っただけで一枚も出していない 1 局目（#2301）。
    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(HanafudaSnapshot.self, for: id) else { return false }
        return Self.isUntouched(snap)
    }

    private static func isUntouched(_ snap: HanafudaSnapshot) -> Bool {
        snap.round <= 1
            && snap.phase == .playing
            && snap.selection == nil
            && snap.hands.first?.count == 8
            && snap.captured.first?.isEmpty == true
    }
}
