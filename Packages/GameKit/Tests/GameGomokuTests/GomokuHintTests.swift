import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameGomoku

/// 五目並べのヒント（#1118・確定仕様 A: 無料 3 回のみ・広告連携なし・1 局ごとにリセット）。
@MainActor
@Suite("五目並べ ヒント（#1118）")
struct GomokuHintTests {

    private func makeModel(store: SnapshotStore = MemorySnapshotStore()) -> GomokuModel {
        GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
    }

    /// 人間の 1 手を打ち、CPU の応手まで進める。
    private func playExchange(_ model: GomokuModel, row: Int, col: Int) async throws {
        let before = model.moveCount
        model.tap(row: row, col: col)
        await model.performAIMoveIfNeeded()
        try #require(model.moveCount == before + 2, "前提: (\(row),\(col)) と CPU の応手が打てている")
    }

    @Test("残り回数は 3 から始まり、押すたびに 1 ずつ減って 3 回で打ち止めになる")
    func hintIsLimitedToThreePerGame() async {
        let model = makeModel()
        #expect(model.hintsRemaining == BoardHintRules.perGame)
        #expect(model.canUseHint)

        for expected in stride(from: 2, through: 0, by: -1) {
            await model.requestHint()
            #expect(model.hintsRemaining == expected)
            #expect(model.hintMove != nil)
        }

        #expect(!model.canUseHint, "使い切ったら押せない")
        await model.requestHint()
        #expect(model.hintsUsed == BoardHintRules.perGame, "4 回目は数えない")
    }

    @Test("示された推奨手は、いま空いている交点である")
    func hintPointsToAnEmptyIntersection() async throws {
        let model = makeModel()
        await model.requestHint()
        let hint = try #require(model.hintMove)
        #expect(model.board[hint.row, hint.col] == nil)
        #expect((0..<gomokuBoardSize).contains(hint.row))
        #expect((0..<gomokuBoardSize).contains(hint.col))
    }

    @Test("新規対局で残り回数が 3 に戻り、盤の印も消える")
    func newGameResetsHints() async throws {
        let model = makeModel()
        await model.requestHint()
        try #require(model.hintsUsed == 1)

        model.newGame()
        #expect(model.hintsUsed == 0)
        #expect(model.hintsRemaining == BoardHintRules.perGame)
        #expect(model.hintMove == nil)
    }

    @Test("打つと盤の印は消えるが、使った回数は減らない")
    func placingClearsTheMarkButNotTheCount() async throws {
        let model = makeModel()
        await model.requestHint()
        try #require(model.hintMove != nil)

        try await playExchange(model, row: 7, col: 7)
        #expect(model.hintMove == nil)
        #expect(model.hintsUsed == 1, "打ち直しで回数が回復してはいけない")
    }

    @Test("待ったで盤を戻しても印は消え、回数は戻らない")
    func undoClearsTheMarkButNotTheCount() async throws {
        let model = makeModel()
        try await playExchange(model, row: 7, col: 7)
        await model.requestHint()
        try #require(model.hintMove != nil)
        try #require(model.canUndo)

        model.undoLastExchange()
        #expect(model.hintMove == nil)
        #expect(model.hintsUsed == 1)
    }

    @Test("CPU の手番では押せない")
    func cannotHintOnAITurn() async throws {
        let model = makeModel()
        model.tap(row: 7, col: 7)
        try #require(model.isAITurn, "前提: CPU の手番になっている")

        #expect(!model.canUseHint)
        await model.requestHint()
        #expect(model.hintsUsed == 0, "CPU の手番で数えている")
        #expect(model.hintMove == nil)
    }

    @Test("終局後（投了）は押せない")
    func cannotHintAfterGameOver() async {
        let model = makeModel()
        model.resign()
        #expect(model.gameOver)
        #expect(!model.canUseHint)
        await model.requestHint()
        #expect(model.hintsUsed == 0)
    }

    @Test("中断データに使った回数が書かれ、再開しても残り回数が引き継がれる")
    func hintCountSurvivesSnapshot() async throws {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        await model.requestHint()
        await model.requestHint()
        try #require(model.hintsUsed == 2)

        let snap = try #require(store.load(GomokuSnapshot.self, for: "gomoku"))
        #expect(snap.hintsUsed == 2, "スナップショットに書かれていない")

        let restored = GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(restored.hintsUsed == 2)
        #expect(restored.hintsRemaining == 1, "再開後に残り回数が 3 へ戻ってはいけない")
    }

    @Test("ヒントが無かった頃の中断データ（hintsUsed 無し）も読めて、未使用の局になる")
    func oldSnapshotWithoutHintsUsedStillLoads() throws {
        let store = MemorySnapshotStore()
        // `hintsUsed` を持たない v1.1.5 までの形。非 optional で足すとここで
        // デコードが丸ごと失敗し、中断が黙って消える。
        let cells = String(repeating: "null,", count: gomokuBoardSize * gomokuBoardSize).dropLast()
        let json = """
        {"cells":[\(cells)],"currentStone":0,"humanSide":0,"aiLevel":1,"startedAt":0}
        """
        let snap = try JSONDecoder().decode(GomokuSnapshot.self, from: Data(json.utf8))
        #expect(snap.hintsUsed == nil)
        try store.save(snap, for: "gomoku")

        let model = GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.hintsUsed == 0)
        #expect(model.hintsRemaining == BoardHintRules.perGame)
    }

    @Test("ヒントを使った局の成績は isLeaderboardEligible が false になる")
    func hintMakesScoreIneligible() async {
        let model = makeModel()
        #expect(model.finishScore.isLeaderboardEligible, "使っていない局は対象のまま")

        await model.requestHint()
        #expect(!model.finishScore.isLeaderboardEligible)
        #expect(model.finishScore.variant == nil, "ローカルの自己ベストは区分を分けない（#406）")
    }

    @Test("読み上げ文にヒントの手が入る")
    func accessibilityLabelMentionsHint() {
        let label = GomokuAccessibility.pointLabel(row: 7, col: 7, stone: nil, isLastMove: false, isHint: true)
        #expect(label.contains("ヒントの手"))

        let plain = GomokuAccessibility.pointLabel(row: 7, col: 7, stone: nil, isLastMove: false)
        #expect(!plain.contains("ヒントの手"), "ヒントでない交点に付いている")
    }
}
