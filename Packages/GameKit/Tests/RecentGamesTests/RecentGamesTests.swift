import Foundation
import Testing
@testable import Core

/// ハブ最上部の「つづき・最近」行（#660）。行そのものは App ターゲットにあるので、
/// 並び順と打ち切りの規則だけをここで固定する。
@Suite("つづき・最近の候補選び")
struct RecentGamesCandidateTests {
    /// ハブの並び。順序の基準にも同着の決着にも使われるため、テスト側でも 1 か所に置く。
    private static let visible = ["shogi", "poker", "2048", "othello", "sudoku", "mahjong"]

    private static func date(_ minutesAgo: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 - Double(minutesAgo) * 60)
    }

    @Test("中断も記録も無ければ候補ゼロ（= 行を描かない）")
    func emptyWhenNothingToShow() {
        let result = RecentGames.candidates(
            visibleGameIDs: Self.visible,
            resumingGameIDs: []
        )
        #expect(result.isEmpty)
    }

    @Test("中断ありは、記録だけのものより必ず先に来る")
    func resumingComesBeforePlayed() {
        // 記録のほうが新しくても、中断の側が先。「戻る理由が既にある人」を優先する規則。
        let result = RecentGames.candidates(
            visibleGameIDs: Self.visible,
            resumingGameIDs: ["mahjong"],
            resumeUpdatedAt: ["mahjong": Self.date(600)],
            lastPlayedAt: ["shogi": Self.date(1)]
        )
        #expect(result.map(\.gameID) == ["mahjong", "shogi"])
        #expect(result.map(\.hasResume) == [true, false])
    }

    @Test("中断ありは更新時刻の新しい順に並ぶ")
    func resumingSortedByNewest() {
        let result = RecentGames.candidates(
            visibleGameIDs: Self.visible,
            resumingGameIDs: ["shogi", "poker", "2048"],
            resumeUpdatedAt: [
                "shogi": Self.date(300),
                "poker": Self.date(10),
                "2048": Self.date(60),
            ]
        )
        #expect(result.map(\.gameID) == ["poker", "2048", "shogi"])
    }

    @Test("記録だけのものは最終プレイの新しい順に並ぶ")
    func playedSortedByNewest() {
        let result = RecentGames.candidates(
            visibleGameIDs: Self.visible,
            resumingGameIDs: [],
            lastPlayedAt: [
                "othello": Self.date(500),
                "sudoku": Self.date(5),
                "shogi": Self.date(50),
            ]
        )
        #expect(result.map(\.gameID) == ["sudoku", "shogi", "othello"])
        #expect(result.allSatisfy { !$0.hasResume })
    }

    @Test("候補が多くても最大4枚で打ち切る")
    func capsAtMaxCount() {
        let result = RecentGames.candidates(
            visibleGameIDs: Self.visible,
            resumingGameIDs: ["shogi", "poker"],
            resumeUpdatedAt: ["shogi": Self.date(2), "poker": Self.date(1)],
            lastPlayedAt: [
                "2048": Self.date(3), "othello": Self.date(4),
                "sudoku": Self.date(5), "mahjong": Self.date(6),
            ]
        )
        #expect(RecentGames.maxCount == 4)
        #expect(result.count == 4)
        // 打ち切られるのは古い側から。中断の2枚は残る。
        #expect(result.map(\.gameID) == ["poker", "shogi", "2048", "othello"])
    }

    @Test("設定で非表示にしたゲームは、中断や記録があっても行に出ない")
    func hiddenGamesAreExcluded() {
        // 非表示 = `visibleModules` から落ちる = この関数に渡らない、という形で担保する。
        let result = RecentGames.candidates(
            visibleGameIDs: ["shogi", "poker"],
            resumingGameIDs: ["shogi", "mahjong"],
            resumeUpdatedAt: ["mahjong": Self.date(1), "shogi": Self.date(100)],
            lastPlayedAt: ["sudoku": Self.date(2)]
        )
        #expect(result.map(\.gameID) == ["shogi"])
    }

    @Test("更新時刻の取れない中断は後ろへ回り、そのなかではハブの並びを保つ")
    func undatedResumingGoesLast() {
        // 時刻を持たない `SnapshotStore` 実装（`modifiedAt` の既定 nil）でも順序が決まること。
        let result = RecentGames.candidates(
            visibleGameIDs: Self.visible,
            resumingGameIDs: ["poker", "othello", "2048"],
            resumeUpdatedAt: ["othello": Self.date(999)]
        )
        #expect(result.map(\.gameID) == ["othello", "poker", "2048"])
    }

    @Test("同じ時刻の同着はハブの並びで決まる（呼ぶたびに順序が変わらない）")
    func tiesAreBrokenByHubOrderDeterministically() {
        // `sorted(by:)` は安定性が保証されないため、同着に決着を付けていないと同じ入力から
        // 違う並びが出て、ハブを開くたびに行がちらつく。
        let same = Self.date(7)
        let expected = ["poker", "2048", "othello"]
        for _ in 0..<20 {
            let result = RecentGames.candidates(
                visibleGameIDs: Self.visible,
                resumingGameIDs: ["othello", "poker", "2048"],
                resumeUpdatedAt: ["poker": same, "2048": same, "othello": same]
            )
            #expect(result.map(\.gameID) == expected)
        }
    }

    @Test("プレイ記録を消去すると記録由来の候補だけが消え、中断は残る")
    func clearingPlayLogRemovesOnlyPlayedCandidates() {
        // 「消去」は `PlayLog.clear()` = `lastPlayedAtByGame` が空になること。中断データは
        // プレイ記録ではないので消えない（消えると再開できなくなる）。
        let resuming: Set<String> = ["mahjong"]
        let before = RecentGames.candidates(
            visibleGameIDs: Self.visible,
            resumingGameIDs: resuming,
            resumeUpdatedAt: ["mahjong": Self.date(30)],
            lastPlayedAt: ["shogi": Self.date(10), "poker": Self.date(20)]
        )
        #expect(before.map(\.gameID) == ["mahjong", "shogi", "poker"])

        let after = RecentGames.candidates(
            visibleGameIDs: Self.visible,
            resumingGameIDs: resuming,
            resumeUpdatedAt: ["mahjong": Self.date(30)],
            lastPlayedAt: [:]
        )
        #expect(after.map(\.gameID) == ["mahjong"])
    }

    @Test("上限0なら何も返さない（打ち切りの境界）")
    func zeroLimitReturnsNothing() {
        let result = RecentGames.candidates(
            visibleGameIDs: Self.visible,
            resumingGameIDs: ["shogi"],
            limit: 0
        )
        #expect(result.isEmpty)
    }
}

/// 中断データの更新時刻（#660）。**新しい永続化を増やさない**のが設計の要なので、
/// ファイル属性から取れていることと、既定が nil であることの両方を固定する。
@Suite("中断データの更新時刻")
struct SnapshotModifiedAtTests {
    private struct Payload: Codable { let value: Int }

    /// `modifiedAt` を実装しない最小の準拠型。既定実装に落ちることを確かめるためだけのもの。
    private struct DatelessStore: SnapshotStore {
        func save<T: Codable>(_ snapshot: T, for gameID: String) throws {}
        func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? { nil }
        func clear(for gameID: String) {}
        func exists(for gameID: String) -> Bool { true }
    }

    @Test("時刻を持たない実装の既定は nil")
    func defaultImplementationReturnsNil() {
        #expect(DatelessStore().modifiedAt(for: "shogi") == nil)
    }

    @Test("保存したら更新時刻が取れ、消したら nil に戻る")
    func fileStoreReportsModificationDate() throws {
        let store = FileSnapshotStore(subdirectory: Self.uniqueSubdirectory())
        let gameID = "recent-games-probe"
        #expect(store.modifiedAt(for: gameID) == nil, "保存前から時刻が取れている")

        try store.save(Payload(value: 1), for: gameID)
        // 現在時刻との差は見ない（実行が止まると正しい実装でも落ちる）。時刻が並び順に
        // 効いていることは下の `olderSnapshotSortsAfterNewer` で確かめる。
        #expect(store.modifiedAt(for: gameID) != nil, "保存したのに更新時刻が取れない")

        store.clear(for: gameID)
        #expect(store.modifiedAt(for: gameID) == nil, "消したのに時刻が残っている")
    }

    @Test("古い中断と新しい中断が更新時刻で区別でき、並び順の根拠になる")
    func olderSnapshotSortsAfterNewer() throws {
        // 実時間を待つ形にするとフレークするため、片方の更新時刻をファイル属性で
        // 1 時間前へ動かして差を作る（sleep で秒を稼ぐ形にはしない）。
        let subdirectory = Self.uniqueSubdirectory()
        let store = FileSnapshotStore(subdirectory: subdirectory)
        try store.save(Payload(value: 1), for: "older")
        try store.save(Payload(value: 2), for: "newer")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)],
            ofItemAtPath: Self.path(subdirectory: subdirectory, gameID: "older")
        )

        guard let older = store.modifiedAt(for: "older"),
              let newer = store.modifiedAt(for: "newer")
        else {
            Issue.record("更新時刻が取れない")
            return
        }
        #expect(newer > older)

        // 実際の並びまで通して確かめる（時刻が取れても順序に効いていなければ意味がない）。
        let visible = ["older", "newer"]
        let candidates = RecentGames.candidates(
            visibleGameIDs: visible,
            resumingGameIDs: Set(visible),
            resumeUpdatedAt: visible.reduce(into: [:]) { result, id in
                if let date = store.modifiedAt(for: id) { result[id] = date }
            }
        )
        #expect(candidates.map(\.gameID) == ["newer", "older"])
    }

    private static func uniqueSubdirectory() -> String {
        "SnapshotModifiedAtTests-\(UUID().uuidString)"
    }

    /// `FileSnapshotStore` の保存先は公開されていないので、同じ規則（Application Support /
    /// subdirectory / `<gameID>.json`）で組み立て直す。ここが実装とずれたら、上の
    /// `setAttributes` がファイル不在で throw して気付ける。
    private static func path(subdirectory: String, gameID: String) -> String {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(subdirectory, isDirectory: true)
            .appendingPathComponent("\(gameID).json", isDirectory: false)
            .path
    }
}
