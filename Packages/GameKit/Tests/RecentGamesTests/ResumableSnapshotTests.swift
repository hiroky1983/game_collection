import Foundation
import Testing
import Core
import CoreTestSupport
import Game2048
import GameChess
import GameRunner
import GameShogi

/// 「続きから」の判定（#809）。中断データが在るだけでは途中の局と言えない 2 種類
/// （局を復元しないチャリンコおじさん・終局後も見返しを残す将棋とチェス）を、本物の Module と Model で確かめる。
@MainActor
@Suite("続きからの判定（#809）")
struct ResumableSnapshotTests {
    private static let registry = GameRegistry([
        Game2048Module(), ShogiModule(), ChessModule(), RunnerModule(),
    ])

    /// ハブ（`HubView.recentCandidates`）と同じ組み立て。
    private static func candidates(
        store: SnapshotStore, lastPlayedAt: [String: Date] = [:]
    ) -> [RecentGames.Candidate] {
        let visible = registry.modules.map(\.id)
        let resuming = visible.filter { registry.hasResumableSnapshot(gameID: $0, in: store) }
        return RecentGames.candidates(
            visibleGameIDs: visible,
            resumingGameIDs: Set(resuming),
            lastPlayedAt: lastPlayedAt
        )
    }

    @Test("既定のゲームは中断データの有無がそのまま答えになる")
    func defaultFollowsSnapshotExistence() {
        let store = MemorySnapshotStore()
        #expect(!Self.registry.hasResumableSnapshot(gameID: "2048", in: store))
        _ = Game2048Model(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(store.exists(for: "2048"), "前提が崩れた: 2048 は開いた時点で中断データを書くはず")
        #expect(Self.registry.hasResumableSnapshot(gameID: "2048", in: store))
    }

    @Test("resumesFromSnapshot == false のゲームは中断データがあっても「つづきから」に出ない")
    func unresumableGameIsNotResuming() throws {
        let store = MemorySnapshotStore()
        try store.save(["stage": 3], for: "runner")
        #expect(store.exists(for: "runner"))
        #expect(!Self.registry.hasResumableSnapshot(gameID: "runner", in: store))

        let result = Self.candidates(store: store, lastPlayedAt: ["runner": Date()])
        #expect(result == [RecentGames.Candidate(gameID: "runner", hasResume: false)],
                "チャリンコおじさんが「つづきから」として並んだ")
    }

    @Test("将棋・チェスは対局中なら「つづきから」、終局すると記録由来の候補になる")
    func finishedBoardGameFallsBackToRecord() {
        for gameID in ["shogi", "chess"] {
            let store = MemorySnapshotStore()
            let services = GameServices(snapshots: store, ads: NoopAdService())
            if gameID == "shogi" {
                let model = ShogiGameModel(services: services)
                model.newGame()
                #expect(Self.registry.hasResumableSnapshot(gameID: gameID, in: store), "\(gameID): 対局中の局が途中扱いにならない")
                model.resign()
            } else {
                let model = ChessGameModel(services: services)
                model.newGame()
                #expect(Self.registry.hasResumableSnapshot(gameID: gameID, in: store), "\(gameID): 対局中の局が途中扱いにならない")
                model.resign()
            }
            #expect(store.exists(for: gameID), "前提が崩れた: \(gameID) は終局後も見返しの中断データを残すはず")
            #expect(!Self.registry.hasResumableSnapshot(gameID: gameID, in: store), "\(gameID): 終局した局を途中扱いした")

            let result = Self.candidates(store: store, lastPlayedAt: [gameID: Date()])
            #expect(result == [RecentGames.Candidate(gameID: gameID, hasResume: false)],
                    "\(gameID): 終局後にハブへ戻ると記録由来の候補として並ぶはず")

            // アプリを起動し直して見返しを開いた（Model が作り直され、同じ中断データを書き直す）。
            let reopened = GameServices(snapshots: store, ads: NoopAdService())
            if gameID == "shogi" {
                ShogiGameModel(services: reopened).reviewStepBack()
            } else {
                ChessGameModel(services: reopened).reviewStepBack()
            }
            #expect(!Self.registry.hasResumableSnapshot(gameID: gameID, in: store), "\(gameID): 見返しを開き直したら途中扱いに戻った")
        }
    }

    @Test("読めない中断データは途中扱いにしない（Model も新規対局として始める）")
    func undecodableSnapshotIsNotResumable() {
        let store = MemorySnapshotStore()
        store.inject(Data("broken".utf8), for: "shogi")
        store.inject(Data("broken".utf8), for: "chess")
        #expect(!Self.registry.hasResumableSnapshot(gameID: "shogi", in: store))
        #expect(!Self.registry.hasResumableSnapshot(gameID: "chess", in: store))
    }

    @Test("登録外の ID は途中扱いにしない")
    func unknownGameIsNotResumable() throws {
        let store = MemorySnapshotStore()
        try store.save(["x": 1], for: "unknown")
        #expect(!Self.registry.hasResumableSnapshot(gameID: "unknown", in: store))
    }
}
