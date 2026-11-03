import Testing
import Foundation
import CoreEngine
@testable import GameCatPuzzle

/// ねこさがしの今日のランキング画面（#3236）の読み込みの各状態。
@Suite("おじさんちのねこさがしのランキング画面")
@MainActor
struct CatPuzzleRankingTests {

    private func jst(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }


    private var inEvent: Date { jst(2026, 11, 20) }

    private func row(_ rank: Int, _ name: String, _ score: Int, me: Bool = false) -> GameCenterBoardRow {
        GameCenterBoardRow(id: "p\(rank)", name: name, score: score, rank: rank, isMe: me)
    }

    private func board(rows: [GameCenterBoardRow], myRank: Int?, myScore: Int?, participants: Int = 50,
                       end: Date? = nil, yesterday: Int? = nil) -> GameCenterBoard {
        GameCenterBoard(rows: rows, myRank: myRank, myScore: myScore, participants: participants,
                        start: nil, end: end, lastWeekRank: yesterday)
    }

    private func model(signedIn: Bool = true, board: GameCenterBoard?, friends: [GameCenterBoardRow] = [],
                       now: Date? = nil, calls: Calls = Calls()) -> CatPuzzleRankingModel {
        CatPuzzleRankingModel(
            isSignedIn: { signedIn },
            loadBoard: { calls.board += 1; return board },
            loadFriends: { calls.friends += 1; return friends },
            now: { now ?? self.inEvent })
    }

    @MainActor final class Calls { var board = 0; var friends = 0 }

    @Test("成功: 上位と自分の順位・pt・昨日の最終順位・友だちが入る")
    func ready() async {
        let rows = [row(1, "A", 30), row(2, "B", 20, me: true)]
        let m = model(board: board(rows: rows, myRank: 2, myScore: 20, yesterday: 5),
                      friends: [row(2, "B", 20, me: true), row(7, "C", 9)])
        await m.load()
        guard case .ready(let c) = m.state else { Issue.record("ready ではない: \(m.state)"); return }
        #expect(c.rows == rows)
        #expect(c.myRank == 2 && c.myScore == 20 && c.yesterdayRank == 5)
        #expect(c.friends.count == 2)
    }

    @Test("自分が上位の外なら末尾に自分の行を足す")
    func appendsMeOutsideTop() async {
        let m = model(board: board(rows: [row(1, "A", 30)], myRank: 77, myScore: 3))
        await m.load()
        guard case .ready(let c) = m.state else { Issue.record("ready ではない"); return }
        #expect(c.rows.count == 2)
        #expect(c.rows.last?.isMe == true && c.rows.last?.rank == 77 && c.rows.last?.score == 3)
    }

    @Test("友だちが自分ひとりだけなら友だちの欄は空")
    func friendsOnlyMeIsHidden() async {
        let m = model(board: board(rows: [row(1, "A", 3, me: true)], myRank: 1, myScore: 3),
                      friends: [row(1, "A", 3, me: true)])
        await m.load()
        guard case .ready(let c) = m.state else { Issue.record("ready ではない"); return }
        #expect(c.friends.isEmpty)
    }

    @Test("未サインイン: 問い合わせずに signedOut")
    func signedOut() async {
        let calls = Calls()
        let m = model(signedIn: false, board: nil, calls: calls)
        await m.load()
        #expect(m.state == .signedOut)
        #expect(calls.board == 0 && calls.friends == 0)
    }

    @Test("失敗: 順位表が読めなければ failed")
    func failed() async {
        let m = model(board: nil)
        await m.load()
        #expect(m.state == .failed)
    }

    @Test("常設: イベントの期間の前後でも順位表を問い合わせる（#3298）")
    func loadsOutsideEventPeriod() async {
        for now in [jst(2026, 11, 4, 12), jst(2026, 12, 10, 0)] {
            let calls = Calls()
            let m = model(board: board(rows: [row(1, "A", 30)], myRank: 1, myScore: 30), now: now, calls: calls)
            await m.load()
            #expect(calls.board == 1)
            if case .ready = m.state {} else { Issue.record("ready になっていない: \(m.state)") }
        }
    }

    @Test("前の回の表が返ったら、今日はまだ記録なしにして、その順位を昨日の最終順位に回す")
    func staleBoardBecomesYesterday() async {
        let stale = board(rows: [row(1, "A", 30)], myRank: 4, myScore: 12, end: jst(2026, 11, 20, 0))
        let m = model(board: stale, friends: [row(1, "A", 30), row(4, "B", 12, me: true)])
        await m.load()
        guard case .ready(let c) = m.state else { Issue.record("ready ではない"); return }
        #expect(c.rows.isEmpty && c.myRank == nil)
        #expect(c.yesterdayRank == 4)
        #expect(c.friends.isEmpty)
    }

    @Test("表示名と順位の文言")
    func texts() {
        #expect(CatPuzzleRankingBoard.displayName(row(1, "", 1, me: true)) == "あなた")
        #expect(CatPuzzleRankingBoard.displayName(row(1, "", 1)) == "プレイヤー")
        #expect(CatPuzzleRankingBoard.rankText(3, of: 120) == "3位 / 120人")
        #expect(CatPuzzleRankingBoard.rankText(3, of: 0) == "3位")
    }
}
