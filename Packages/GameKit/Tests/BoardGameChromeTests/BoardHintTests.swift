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
        #expect(BoardHintBudget.engineLevel == 2)
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
        #expect(SourceScan.matchCount(of: #"BoardHintButton\(model: model\)"#, in: source) == 1,
                "\(path) が共通のヒントボタンを通っていない")
        // 文字・アイコン・色を各ゲームで持ち直していない（持つと「同じ見た目」が崩れる）。
        #expect(!source.contains("\"ヒント"), "\(path) がヒントの文言を持ち直している")
        #expect(!source.contains("lightbulb"), "\(path) がヒントのアイコンを持ち直している")
    }

    /// 将棋・チェスの操作列はカプセルが約 30pt の 1 行なので、44pt の枠はレイアウト上だけ詰める
    /// （詰めないと対局中の操作列だけが高くなり、決着の瞬間に盤が縮む・#139・#148）。
    /// 五目並べの操作列は元から 44pt で組んであるので詰めない（#711）。
    @Test(arguments: [
        ("GameShogi/ShogiView.swift", true),
        ("GameChess/ChessView.swift", true),
        ("GameGomoku/GomokuView.swift", false),
    ])
    func hintButtonKeepsTheControlRowHeight(path: String, needsInset: Bool) throws {
        let controls = SourceScan.strippingComments(
            SourceScan.functionSource(
                startingWith: "private var gameControls: some View {",
                in: try SourceScan.packageSource("Sources/\(path)")
            )
        )
        try #require(!controls.isEmpty, "走査の前提が壊れている: gameControls が見つからない")
        let inset = #"\.padding\(\.vertical, -BoardGameControlMetrics\.reviewNavLayoutInset\)"#
        #expect(SourceScan.matchCount(of: inset, in: controls) == (needsInset ? 1 : 0),
                "\(path) のヒントボタンの余白の詰め方が合っていない")
    }

    /// 共通のボタンの中身。黄色 + 電球はナンプレのヒントと同じで、押せない状態は `canUseHint` に結線する。
    @Test("共通のボタンは黄色のカプセルで、押せない状態を結線する")
    func sharedButtonWiresLookAndDisabledState() throws {
        let source = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/Core/BoardGameChrome.swift")
        )
        #expect(source.contains("Text(\"ヒント\\(model.hintsRemaining)\")"), "残り回数を文字に出していない")
        #expect(source.contains("Image(systemName: \"lightbulb.fill\")"))
        #expect(source.contains(".buttonStyle(BoardGameControlCapsuleStyle(fill: Theme.Fill.yellow))"))
        #expect(source.contains(".disabled(!model.canUseHint)"))
        #expect(source.contains(".accessibilityLabel(\"ヒント、残り\\(model.hintsRemaining)回\")"))
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
