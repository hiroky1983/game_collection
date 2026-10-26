import Testing
import Foundation
import SwiftUI
import Core
import CoreTestSupport
@testable import GameShogi

/// ヒントの詰み対応（#2779）。局面集は「自分に詰みがある」「相手に詰みがあり防げる」「受けが無い」。
/// 直す前は、詰みがあっても探索の最善手をそのまま出し（考える時間をまるまる使う）、
/// 受けが無い局面でも適当な手を出して回数を減らしていた。
@MainActor
@Suite("将棋 ヒントの詰み対応（#2779）")
struct ShogiHintMateTests {

    /// 先手に 1 手詰（頭金）がある。
    static let mateIn1 = "4k4/9/4G4/9/9/9/9/9/4K4 b G 1"
    /// 先手に 3 手詰（飛の打ち込み → 横から王手）がある。
    static let mateIn3 = "9/4k4/R8/9/9/9/9/9/4K4 b R 1"
    /// 先手に 5 手詰（飛 2 枚の追い詰め）がある。
    static let mateIn5 = "9/9/4k4/R8/9/9/9/9/4K4 b R 1"
    /// 後手に 1 手詰（5八金）があるが、先手は飛で 5七の金を取って防げる。
    static let defendable = "4k4/9/9/9/9/9/R3g4/9/4K4 b g 1"
    /// 後手に 1 手詰があり、先手はどの手を指しても詰まされる（玉は 4九・6九にしか動けず、どちらも金打ちで詰む）。
    static let hopeless = "4k4/9/9/9/9/9/4g4/9/4K4 b g 1"

    private func position(_ sfen: String) throws -> Position {
        try #require(Position.fromSFEN(sfen), "前提: 局面が読める")
    }

    /// エンジンに頼らない検算: `move` を指したあと、相手が 1 手で詰ませられるか（全合法手を総当たり）。
    private func opponentMatesInOne(_ pos: Position, after move: Move) -> Bool {
        var p = pos
        p.make(move)
        for reply in p.legalMoves() {
            var q = p
            q.make(reply)
            if q.isKingInCheck(q.sideToMove) && q.legalMoves().isEmpty { return true }
        }
        return false
    }

    /// 検算: 詰ます手を指すと、相手のどの返答にも自分の詰みが続く（`plies` 手以内・全合法手を総当たり）。
    private func mates(_ pos: Position, plies: Int) -> Bool {
        if plies < 1 { return false }
        for move in pos.legalMoves() {
            var p = pos
            p.make(move)
            let replies = p.legalMoves()
            if replies.isEmpty { if p.isKingInCheck(p.sideToMove) { return true }; continue }
            if plies >= 3, replies.allSatisfy({ reply in
                var q = p
                q.make(reply)
                return mates(q, plies: plies - 2)
            }) { return true }
        }
        return false
    }

    private func engine() -> SimpleMinimaxEngine { SimpleMinimaxEngine.hint() }

    // MARK: 自分に詰みがある

    @Test("1 手詰は詰ます手を出す（総当たりでも詰む）")
    func mateInOne() throws {
        let pos = try position(Self.mateIn1)
        let answer = try #require(engine().hintAnswer(sfen: Self.mateIn1))
        guard case let .mate(move) = answer else { Issue.record("詰ます手になっていない: \(answer)"); return }
        var after = pos
        after.make(move)
        #expect(after.isKingInCheck(after.sideToMove) && after.legalMoves().isEmpty)
    }

    @Test("3 手詰は詰ます手を出す（総当たりでも 3 手で詰む）")
    func mateInThree() throws {
        let pos = try position(Self.mateIn3)
        #expect(!mates(pos, plies: 1))
        let answer = try #require(engine().hintAnswer(sfen: Self.mateIn3))
        guard case let .mate(move) = answer else { Issue.record("詰ます手になっていない: \(answer)"); return }
        var after = pos
        after.make(move)
        #expect(after.isKingInCheck(after.sideToMove), "最初の手は王手")
        #expect(after.legalMoves().allSatisfy { reply in
            var q = after
            q.make(reply)
            return mates(q, plies: 1)
        }, "相手のどの返答にも 1 手詰が続く")
    }

    @Test("5 手詰は詰ます手を出す")
    func mateInFive() throws {
        // Debug ビルドの 5 手詰の探索は 1 秒近くかかる（出荷の Release では桁違いに速い）ので、
        // 打ち切りで揺れないよう考える時間を十分に取る。
        let relaxed = SimpleMinimaxEngine(level: BoardHintBudget.engineLevel, seed: nil, timeLimit: 60)
        let answer = try #require(relaxed.hintAnswer(sfen: Self.mateIn5))
        guard case .mate = answer else { Issue.record("詰ます手になっていない: \(answer)"); return }
    }

    @Test("詰みがあれば考える時間をまるまる使わずに答える")
    func mateAnswersQuickly() throws {
        let started = Date()
        _ = engine().hintAnswer(sfen: Self.mateIn3)
        #expect(Date().timeIntervalSince(started) < 1.0)
    }

    // MARK: 相手に詰みがある

    @Test("相手に 1 手詰がある局面では、詰まされない手を出す（総当たりで確かめる）")
    func defendsAgainstMateInOne() throws {
        let pos = try position(Self.defendable)
        #expect(pos.legalMoves().contains { opponentMatesInOne(pos, after: $0) }, "前提: 詰まされる手が混じっている")
        let answer = try #require(engine().hintAnswer(sfen: Self.defendable))
        let move = try #require(answer.move)
        #expect(!opponentMatesInOne(pos, after: move), "ヒントの手のあとに詰まされる")
    }

    @Test("受けが無い局面は .hopeless（どの手も詰まされることを総当たりで確かめる）")
    func hopelessWhenEveryMoveIsMated() throws {
        let pos = try position(Self.hopeless)
        #expect(pos.legalMoves().allSatisfy { opponentMatesInOne(pos, after: $0) }, "前提: どの手も詰まされる")
        #expect(engine().hintAnswer(sfen: Self.hopeless) == .hopeless)
        #expect(engine().hasNoDefense(sfen: Self.hopeless))
    }

    @Test("ふつうの局面（初形）は .move を返し、断らない")
    func normalPositionStaysNormal() throws {
        let answer = try #require(engine().hintAnswer(sfen: Position.startSFEN))
        guard case let .move(move) = answer else { Issue.record("ふつうの手になっていない: \(answer)"); return }
        #expect(try position(Position.startSFEN).legalMoves().contains(move))
        #expect(!engine().hasNoDefense(sfen: Position.startSFEN))
    }

    @Test("詰み探索が時間内に終わらなければ、今の探索の答えに戻る（断らない）")
    func timedOutMateSearchFallsBack() throws {
        var pos = try position(Self.hopeless)
        var search = ShogiMateSearch(deadline: .distantPast)
        let moves = pos.legalMoves()
        _ = SimpleMinimaxEngine.movesAvoidingMate(&pos, moves: moves, using: &search)
        #expect(search.timedOut)
    }

    // MARK: モデルの結線

    private func makeModel(sfen: String, hintsUsed: Int = 0, rewardEarned: Bool = true) -> (ShogiGameModel, MateAdStub) {
        let store = MemorySnapshotStore()
        try? store.save(
            ShogiSnapshot(initialSfen: sfen, moves: [], phase: .playing, reviewPly: nil, sente: .human,
                          gote: .ai, aiLevel: 1, startedAt: Date(timeIntervalSince1970: 0), undoUsed: false,
                          hintsUsed: hintsUsed),
            for: "shogi")
        let ads = MateAdStub(rewardEarned: rewardEarned)
        return (ShogiGameModel(services: GameServices(snapshots: store, ads: ads)), ads)
    }

    @Test("受けが無い局面で押すと、知らせるだけで回数を減らさず印も出さない")
    func hopelessDoesNotSpendAHint() async throws {
        let (model, _) = makeModel(sfen: Self.hopeless)
        await model.requestHint()
        #expect(model.showsHintHopeless)
        #expect(model.hintMove == nil)
        #expect(model.hintsRemaining == BoardHintBudget.total)
        model.dismissHintHopeless()
        #expect(!model.showsHintHopeless)
    }

    @Test("受けが無い局面では広告を流さず、広告で補充した回数も減らさない")
    func hopelessDoesNotShowAdOrSpendRefill() async throws {
        // 無料枠だけを使い切った状態（広告枠が残っている）。
        let (model, ads) = makeModel(sfen: Self.hopeless, hintsUsed: BoardHintBudget.perGame)
        try #require(model.needsAdForHint)
        let before = model.hintsRemaining

        let outcome = await model.requestAdHint()

        #expect(outcome == .granted)
        #expect(ads.shownCount == 0, "受けが無いのに広告を流している")
        #expect(model.showsHintHopeless)
        #expect(model.hintMove == nil)
        #expect(model.hintsRemaining == before, "広告枠が減っている")
    }

    @Test("詰ます手のヒントは hintIsMate が立ち、回数を 1 つ使う。着手で下りる")
    func mateHintIsFlagged() async throws {
        let (model, _) = makeModel(sfen: Self.mateIn1)
        await model.requestHint()
        #expect(model.hintIsMate)
        #expect(model.hintMove != nil)
        #expect(model.hintsRemaining == BoardHintBudget.total - 1)
        #expect(!model.showsHintHopeless)
    }
}

private final class MateAdStub: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var shownCount = 0
    init(rewardEarned: Bool) { self.rewardEarned = rewardEarned }
    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool { shownCount += 1; return rewardEarned }
}
