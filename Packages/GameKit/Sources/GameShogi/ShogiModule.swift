import SwiftUI
import Core

/// 将棋の `GameModule` 登録口。
public struct ShogiModule: GameModule {
    public let id = "shogi"
    public var title: String { tr("将棋") }
    public var description: String { tr("CPU と本格的な将棋で対決しよう") }
    public var icon: Image { Image(systemName: "square.grid.3x3.fill") }

    public init() {}

    @MainActor public func makeView(services: GameServices) -> AnyView {
        AnyView(ShogiView(services: services))
    }

    /// 終局後の見返しも中断データに残る（`ShogiGameModel.persist`）。`.review` から対局へ戻る経路は
    /// `newGame` だけなので、検討に入った局には続きが無い（#809）。読めない中断データは Model も
    /// 新規対局として扱うので false。人間が一手も指していない局は「続き」ではない（#1572・#1599）。
    /// 人間が後手（駒落ちなら下手）のときは CPU の初手が先に入るので、それだけでは数えない（#2508）。
    public func hasResumableSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(ShogiSnapshot.self, for: id) else { return false }
        return snap.phase == .playing && humanHasMoved(snap)
    }

    /// 対局中で人間が一手も指していない局（#2161）。終局後の見返しは手つかずではない。
    public func hasUntouchedSnapshot(in snapshots: SnapshotStore) -> Bool {
        guard let snap = snapshots.load(ShogiSnapshot.self, for: id) else { return false }
        return snap.phase == .playing && !humanHasMoved(snap)
    }

    /// 駒落ちの開始局面は後手番（`w`）から始まるので、手番欄を見て先に指す側を決める。
    private func humanHasMoved(_ snap: ShogiSnapshot) -> Bool {
        let goteFirst = CPUOpening.startsWithSecondPlayer(fen: snap.initialSfen, secondPlayerToken: "w")
        let cpuFirst = (goteFirst ? snap.gote : snap.sente) == .ai
        return CPUOpening.humanHasMoved(totalMoves: snap.moves.count, cpuMovesFirst: cpuFirst)
    }
}
