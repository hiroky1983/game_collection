import SwiftUI
import Core

public struct MahjongModule: GameModule {
    /// 麻雀ソリティア（#90）が既に `"mahjong"` を使っているので別の ID にする。
    /// この ID は中断スナップショットのファイル名・自己ベスト・解析イベントのキーを兼ねるため、
    /// 一度出したら変えられない（変えると過去の記録と結びつかなくなる）。
    public let id = "mahjong4"
    public var title: String { tr("麻雀") }
    public var description: String { tr("CPU3人と東風戦。立直・鳴きあり！") }
    /// 並んだ牌に見える記号。将棋が `square.grid.3x3.fill` を使っているので同じ形は避ける
    /// （ハブのカードはアイコンで見分けるため、被ると別のゲームに見える）。
    public var icon: Image { Image(systemName: "rectangle.3.group.fill") }

    public init() {}

    public func makeView(services: GameServices) -> AnyView {
        AnyView(MahjongView(services: services))
    }

    /// 配牌のまま 1 枚も切っていない 1 局目は「続き」ではない（#2542）。開始シートで東風戦・一局戦を選んだ
    /// 直後に配牌を保存するので、そのままハブへ戻ると手つかずの盤が続きになってしまう。
    /// 1 局目は必ず自分が親（`dealer == 0`）で、CPU も自分が切るまで河に何も出さない。
    /// 親が回った 2 局目以降は前の局の結果があるので続きとして扱う。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(MahjongSnapshot.self, for: id) else { return false }
        return !Self.isUntouched(snap)
    }

    /// 保存はあるが 1 枚も切っていない 1 局目（#2542）。
    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(MahjongSnapshot.self, for: id) else { return false }
        return Self.isUntouched(snap)
    }

    private static func isUntouched(_ snap: MahjongSnapshot) -> Bool {
        snap.roundNumber == 1 && snap.honba == 0 && snap.dealer == 0
            && snap.handResult == nil
            && snap.discards.allSatisfy(\.isEmpty)
            && (snap.melds ?? []).allSatisfy(\.isEmpty)
    }

    /// 局の名前（「東2局」「南3局」）。リザルト中の中断は決着した局を出す（`MahjongModel.displayedRoundNumber` と同じ）。
    /// 一局戦は進み具合が意味を持たないので出さない。
    public func resumeProgress(in snapshots: SnapshotStore) -> String? {
        guard let snap = snapshots.load(MahjongSnapshot.self, for: id) else { return nil }
        let length = snap.gameLength ?? .tonpuu
        guard length != .singleHand else { return nil }
        return length.roundName(forRound: snap.handResult?.roundNumber ?? snap.roundNumber)
    }
}
