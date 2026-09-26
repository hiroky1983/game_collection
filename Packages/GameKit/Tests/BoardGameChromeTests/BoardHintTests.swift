import Foundation
import Testing
import GameKitTestSupport
@testable import Core

/// ヒントの回数制（#1118）。将棋・チェス・五目並べが同じ勘定で持つので、値の検証はここに 1 つだけ置く。
@Suite("ヒントの回数制")
struct BoardHintBudgetTests {

    @Test("1局あたり3回から始まる")
    func startsWithThree() {
        #expect(BoardHintBudget.perGame == 3)
        let budget = BoardHintBudget()
        #expect(budget.remaining == 3)
        #expect(!budget.isExhausted)
        #expect(!budget.wasUsed)
    }

    @Test("使うたびに1つ減り、3回で使い切る")
    func consumesUntilExhausted() {
        var budget = BoardHintBudget()
        for remaining in stride(from: 2, through: 0, by: -1) {
            let consumed = budget.consume()
            #expect(consumed)
            #expect(budget.remaining == remaining)
            #expect(budget.wasUsed)
        }
        #expect(budget.isExhausted)
        // 使い切ったあとは**何も変えずに** false を返す（広告での補充は持たない）。
        let extra = budget.consume()
        #expect(!extra)
        #expect(budget.used == BoardHintBudget.perGame)
    }

    @Test("新規対局で3回に戻る")
    func resetsForTheNextGame() {
        var budget = BoardHintBudget()
        let consumed = budget.consume()
        #expect(consumed)
        budget.reset()
        #expect(budget.remaining == BoardHintBudget.perGame)
        #expect(!budget.wasUsed)
    }

    /// 壊れた中断データ（負の数・上限超え）でも残り回数が破綻しないようにする。
    @Test("復元した使用回数は範囲に丸める")
    func clampsRestoredValue() {
        #expect(BoardHintBudget(used: -5).used == 0)
        #expect(BoardHintBudget(used: 99).used == BoardHintBudget.perGame)
        #expect(BoardHintBudget(used: 99).isExhausted)
    }

    @Test("ヒントを1回でも使った局は順位表へ送らない（自己ベストには影響しない）")
    func usedHintDropsLeaderboardEligibility() {
        var budget = BoardHintBudget()
        #expect(budget.winLossScore.isLeaderboardEligible)
        #expect(budget.winLossScore.metric == .winLoss)
        let consumed = budget.consume()
        #expect(consumed)
        #expect(!budget.winLossScore.isLeaderboardEligible)
        // 旗は指標を問わず `GameCenterLeaderboard` の入口で弾かれる（ソリティアのジョーカー #406 と同じ扱い）。
        let assisted = GameScore(metric: .points, points: 4096, isLeaderboardEligible: false)
        #expect(GameCenterLeaderboard.score(gameID: "2048", outcome: .win, score: assisted) == nil)
    }

    /// ヒントは対局中の CPU の強さに合わせない。五目並べの level 0（弱）は探索せず確率で見逃すため、
    /// 合わせると「最善手」を名乗れなくなる（#665）。
    @Test("読ませる強さは最強に固定")
    func readsWithTheStrongestEngine() {
        #expect(BoardHintBudget.engineLevel == CPUStrength.hard.rawValue)
    }
}

/// ヒントのボタンは 3 本とも同じ部品・同じ見た目（`feedback_same_widget_same_look` の方針・#1118）。
/// 見た目の選び方はソースで固定する（描画では「同じ組み方か」までは確かめられない）。
@Suite("ヒントのボタンの組み方")
struct BoardHintButtonSourceTests {

    /// 各ゲームが共通の部品を通っていること。手書きのカプセルを並べ直すと、片方だけ色や文字が変わる。
    @Test(arguments: [
        "GameShogi/ShogiView.swift",
        "GameChess/ChessView.swift",
        "GameGomoku/GomokuView.swift",
    ])
    func everyBoardGameUsesTheSharedButton(path: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/\(path)"))
        #expect(SourceScan.matchCount(of: #"BoardControlBarHint\(model\)"#, in: source) == 1,
                "\(path) が共通のヒントボタンを通っていない")
        // 文字・アイコン・色を各ゲームで持ち直していない（持つと「同じ見た目」が崩れる）。
        #expect(!source.contains("\"ヒント"), "\(path) がヒントの文言を持ち直している")
        #expect(!source.contains("lightbulb"), "\(path) がヒントのアイコンを持ち直している")
    }

    /// 共通の操作行の中身。ヒントは「⋯」メニューの中で電球 + 残り回数を出し、押せない状態は `canUseHint` に結線する（#1421）。
    /// 操作行の高さは 44pt 固定で、決着で入れ替わっても盤が縮まない（#139）。
    @Test("共通の操作行はヒントをメニューに入れ、押せない状態を結線し、高さを固定する")
    func controlBarWiresHintMenuAndFixedHeight() throws {
        let source = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/Core/BoardGameControlBar.swift")
        )
        #expect(source.contains("\"ヒント（残り\\(hint.remaining)回）\""), "残り回数を文字に出していない")
        #expect(source.contains("systemImage: \"lightbulb.fill\""))
        #expect(source.contains(".disabled(!hint.isEnabled)"))
        #expect(source.contains("isEnabled = model.canUseHint"))
        #expect(source.contains(".frame(height: BoardGameControlMetrics.minTapTarget)"), "操作行の高さが 44pt 固定でない")
        #expect(source.contains("Label(\"投了\", systemImage: \"flag.fill\")"))
        #expect(source.contains(".boardResignConfirmation(isPresented: $showResignConfirm, onResign: onResign)"),
                "投了に確認ダイアログが付いていない")
    }

    /// 盤の上の印は 3 本とも同じ色（`BoardGameHintColor`）。ゲームごとに色を決めると、
    /// 同じ意味の印がゲームによって違う色になる。
    @Test(arguments: [
        "GameShogi/ShogiView.swift",
        "GameChess/ChessView.swift",
        "GameGomoku/GomokuView.swift",
    ])
    func hintMarkUsesTheSharedColor(path: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/\(path)"))
        #expect(source.contains("BoardGameHintColor.color"), "\(path) がヒントの共通色を使っていない")
    }

    /// 3 本の Model が決着へ渡す成績は必ず `hints.winLossScore` を通す。
    /// 素の `GameScore(metric: .winLoss)` に戻すと、その 1 本だけヒントを使った局が順位表へ送られる。
    @Test(arguments: [
        "GameShogi/ShogiGameModel.swift",
        "GameChess/ChessGameModel.swift",
        "GameGomoku/GomokuModel.swift",
    ])
    func everyModelFeedsTheHintAwareScore(path: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/\(path)"))
        #expect(source.contains("hints.winLossScore"), "\(path) がヒントを見た成績を渡していない")
        #expect(SourceScan.matchCount(of: #"GameScore\(metric: \.winLoss\)"#, in: source) == 0,
                "\(path) に素の勝敗スコアが残っている（ヒントを使った局が順位表へ送られる）")
    }
}
