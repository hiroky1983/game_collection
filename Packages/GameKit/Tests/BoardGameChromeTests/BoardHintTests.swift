import Foundation
import Testing
import GameKitTestSupport
@testable import Core

/// ヒントの回数制（#1118・#1500）。将棋・チェス・五目並べが同じ勘定で持つので、値の検証はここに 1 つだけ置く。
@Suite("ヒントの回数制")
struct BoardHintBudgetTests {

    @Test("無料3回・広告5回の合計8回から始まる")
    func startsWithEight() {
        #expect(BoardHintBudget.perGame == 3)
        #expect(BoardHintBudget.adRefillMax == 5)
        #expect(BoardHintBudget.total == 8)
        let budget = BoardHintBudget()
        #expect(budget.remaining == 8)
        #expect(!budget.isExhausted)
        #expect(!budget.wasUsed)
        #expect(budget.hasFreeRemaining)
    }

    @Test("無料の consume() は3回で使い切り、4回目は何も変えずに false")
    func consumeStopsAtTheFreeLimit() {
        var budget = BoardHintBudget()
        for remaining in stride(from: 7, through: 5, by: -1) {
            let consumed = budget.consume()
            #expect(consumed)
            #expect(budget.remaining == remaining)
            #expect(budget.wasUsed)
        }
        #expect(!budget.hasFreeRemaining)
        #expect(!budget.isExhausted, "無料枠は尽きたが広告枠が残っている")
        // 無料枠を使い切ったあとは consume() は**何も変えずに** false を返す（広告は consumeAd() の担当）。
        let extra = budget.consume()
        #expect(!extra)
        #expect(budget.used == BoardHintBudget.perGame)
    }

    @Test("無料枠が残っているあいだ consumeAd() は何も変えずに false")
    func consumeAdRequiresFreeToBeExhaustedFirst() {
        var budget = BoardHintBudget()
        let consumed = budget.consumeAd()
        #expect(!consumed)
        #expect(budget.used == 0)
    }

    @Test("無料枠を使い切った後、consumeAd() を5回で合計8回を使い切る")
    func consumeAdFillsTheRemainingFive() {
        var budget = BoardHintBudget()
        for _ in 0..<BoardHintBudget.perGame {
            let consumed = budget.consume()
            #expect(consumed)
        }

        for remaining in stride(from: 4, through: 0, by: -1) {
            let consumed = budget.consumeAd()
            #expect(consumed)
            #expect(budget.remaining == remaining)
        }
        #expect(budget.isExhausted)
        #expect(budget.used == BoardHintBudget.total)
        // 使い切ったあとは consumeAd() も**何も変えずに** false を返す。
        let extra = budget.consumeAd()
        #expect(!extra)
        #expect(budget.used == BoardHintBudget.total)
    }

    @Test("新規対局で無料・広告とも8回に戻る")
    func resetsForTheNextGame() {
        var budget = BoardHintBudget()
        for _ in 0..<BoardHintBudget.perGame {
            let consumed = budget.consume()
            #expect(consumed)
        }
        let consumedAd = budget.consumeAd()
        #expect(consumedAd)
        budget.reset()
        #expect(budget.remaining == BoardHintBudget.total)
        #expect(!budget.wasUsed)
        #expect(budget.hasFreeRemaining)
    }

    /// 壊れた中断データ（負の数・上限超え）でも残り回数が破綻しないようにする。
    @Test("復元した使用回数は範囲に丸める")
    func clampsRestoredValue() {
        #expect(BoardHintBudget(used: -5).used == 0)
        #expect(BoardHintBudget(used: 99).used == BoardHintBudget.total)
        #expect(BoardHintBudget(used: 99).isExhausted)
        // v1.1.5 までの中断データ（無料3回のみ）はそのまま「無料を使い切った」として読める。
        #expect(!BoardHintBudget(used: BoardHintBudget.perGame).hasFreeRemaining)
        #expect(!BoardHintBudget(used: BoardHintBudget.perGame).isExhausted)
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
        #expect(SourceScan.matchCount(of: #"BoardControlBarHint\(model, rescue: hintRescue, game:"#, in: source) == 1,
                "\(path) が共通のヒントボタンを通っていない")
        // 文字・アイコン・色を各ゲームで持ち直していない（持つと「同じ見た目」が崩れる）。
        #expect(!source.contains("\"ヒント"), "\(path) がヒントの文言を持ち直している")
        #expect(!source.contains("\"広告を見てヒント"), "\(path) が広告ヒントの文言を持ち直している")
        #expect(!source.contains("lightbulb"), "\(path) がヒントのアイコンを持ち直している")
    }

    /// 共通の操作行の中身。ヒントは盤の下の段のカプセル（電球 + 2 行目に残り回数）で、押せない状態は `canUseHint` に結線する（#1421・#1856）。
    /// 無料枠を使い切ったあとは 2 行目が「▶ あと n 回」（広告ぶんの残り）に変わる（#1500 と同じ数）。操作行の高さは 44pt 固定で、
    /// 決着で入れ替わっても盤が縮まない（#139）。
    @Test("共通の操作行はヒントを段に出し、押せない状態を結線し、高さを固定する")
    func controlBarWiresHintMenuAndFixedHeight() throws {
        let source = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/Core/BoardGameControlBar.swift")
        )
        #expect(source.contains("badge: hint.needsAd ? .ad(remaining: hint.remaining) : .count(hint.remaining)"),
                "残り回数と広告の有無を 2 行目に出していない")
        #expect(source.contains("role: .hint"), "ヒントのカプセルが役割の色（黄）になっていない")
        #expect(source.contains("systemImage: \"lightbulb.fill\""))
        #expect(source.contains("isEnabled: hint.isEnabled"))
        #expect(source.contains("isEnabled = model.canUseHint"))
        // 操作行の高さ（44pt 固定）は共通の `GameOverflowBar` が持つ（`GameOverflowBarTests`）。
        #expect(source.contains("GameOverflowBar("), "操作行が共通の「⋯」の行を通っていない")
        #expect(source.contains(#"GameControlMenuItem(id: "resign", title: "投了", systemImage: "flag.fill", isDestructive: true)"#))
        #expect(source.contains(".boardResignConfirmation(isPresented: $showResignConfirm, onResign: onResign)"),
                "投了に確認ダイアログが付いていない")
    }

    /// 待った・ヒントは別々の広告救済を持つ（`undoRescue` / `hint.rescue`）。同じメニューに同居する以上、
    /// 片方の視聴中はもう片方も塞ぐ（麻雀ソリティア PR #577 と同型の穴を作らない・#1500）。
    @Test("待ったとヒントの広告は互いの視聴中を塞ぐ")
    func undoAndHintRewardsAreMutuallyExclusive() throws {
        let source = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/Core/BoardGameControlBar.swift")
        )
        #expect(source.contains("isEnabled: model.canUndo && !hintIsWatching"),
                "待ったの項目がヒントの視聴中を塞いでいない")
        #expect(source.contains("isEnabled: hint.isEnabled && !undoRescue.isWatching"),
                "ヒントの項目が待ったの視聴中を塞いでいない")
    }

    /// ヒントの広告は「常設のボタンを押すと確認を挟まずに広告へ進む」形（ナンプレのヒントと同じ）なので、
    /// `reward_offer`（提示の計測）は数えない。`RewardOfferWiringTests` の除外リストにも載せておく。
    @Test("ヒントの広告は確認ダイアログを挟まず、視聴完了後に読みへ進む")
    func adHintSkipsConfirmationAndSearchesAfterTheAd() throws {
        let source = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/Core/BoardGameControlBar.swift")
        )
        #expect(source.contains("rescue.requestHandledByModel(withOutcome: { await model.requestAdHint() })"),
                "共通のリワード API（モデルが1本の非同期メソッドで持つ形）を経ていない")
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
