import Testing
import Foundation
@testable import Core
@testable import GameBlackjack
import CoreTestSupport
import GameKitTestSupport

/// 負けた 1 回をリワード広告でやり直す（#2552）。purpose は既存の `undo`。
@Suite("ブラックジャック: 負けた 1 回のやり直し（リワード広告・#2552）")
@MainActor
struct BlackjackRetryAdTests {

    /// 16 対 ディーラー 17 でスタンドして負けた直後の局面。
    private func makeLostModel(
        rewardEarned: Bool = true, roundsPlayed: Int = 4, score: Int = 3, streak: Int = 2,
        retryUsed: Bool = false, store: MemorySnapshotStore = MemorySnapshotStore(),
        playLog: PlayLog? = nil, screenGeneration: GameScreenGeneration = GameScreenGeneration()
    ) -> (BlackjackModel, StubAdService, MemorySnapshotStore) {
        let (model, store, ads) = makeInjectedModel(
            player: [10, 6], dealer: [10, 7], deck: [], roundsPlayed: roundsPlayed, score: score, streak: streak,
            retryUsed: retryUsed, store: store, ads: StubAdService(rewardEarned: rewardEarned),
            playLog: playLog, screenGeneration: screenGeneration
        )
        model.stand()
        #expect(model.outcome == .lose)
        return (model, ads, store)
    }

    @Test("視聴完了なら、その回をなかったことにして配る前へ戻る（回数・点・連勝は負ける前）")
    func undoesTheLostRound() async {
        let (model, ads, _) = makeLostModel()
        #expect(model.canRetryLoss)
        #expect(model.roundsPlayed == 5)
        #expect(model.streak == 0)

        let outcome = await model.retryLossAfterAd()

        #expect(outcome == .granted)
        #expect(model.phase == .ready)
        #expect(model.roundsPlayed == 4)
        #expect(model.score == 3)
        #expect(model.streak == 2, "負けで切れた連勝を戻す")
        #expect(model.outcome == nil)
        #expect(model.hands.isEmpty)
        #expect(model.recordResult == nil)
        #expect(ads.rewardedCount == 1)
        #expect(!model.canRetryLoss, "1 回の勝負につき 1 回まで")
    }

    @Test("バストして負けた回もやり直せる")
    func bustCanBeRetried() async {
        let (model, _, _) = makeInjectedModel(player: [10, 10], dealer: [10, 7], deck: [10], roundsPlayed: 1)
        model.hit()
        #expect(model.outcome == .bust)
        #expect(model.canRetryLoss)
        #expect(await model.retryLossAfterAd() == .granted)
    }

    @Test("勝ち・引き分けの直後は出せず、広告も出さない")
    func notAvailableAfterWinOrPush() async {
        let (win, _, winAds) = makeInjectedModel(player: [10, 9], dealer: [10, 7], deck: [])
        win.stand()
        #expect(!win.canRetryLoss)
        #expect(await win.retryLossAfterAd() == .unavailable)
        #expect(winAds.rewardedCount == 0)

        let (push, _, pushAds) = makeInjectedModel(player: [10, 7], dealer: [10, 7], deck: [])
        push.stand()
        #expect(!push.canRetryLoss)
        #expect(await push.retryLossAfterAd() == .unavailable)
        #expect(pushAds.rewardedCount == 0)
    }

    @Test("10 回目の負けもやり直せ、取り消すと 9 回目の終わりへ戻る")
    func finalRoundLossCanBeRetried() async {
        let (model, _, store) = makeLostModel(roundsPlayed: 9, score: 4, streak: 0)
        #expect(model.isMatchOver)
        #expect(model.canRetryLoss)
        #expect(!store.exists(for: "blackjack"), "終わった勝負の中断データは無い")

        #expect(await model.retryLossAfterAd() == .granted)

        #expect(!model.isMatchOver)
        #expect(model.roundsPlayed == 9)
        #expect(model.phase == .ready)
        #expect(store.exists(for: "blackjack"), "配る前の進み具合を書き出す")
    }

    @Test("視聴未完了・ロード失敗なら何も変わらず、もう一度試せる")
    func notEarnedChangesNothing() async {
        let (model, ads, _) = makeLostModel(rewardEarned: false)

        let outcome = await model.retryLossAfterAd()

        #expect(outcome == .notEarned)
        #expect(model.phase == .result)
        #expect(model.roundsPlayed == 5)
        #expect(model.canRetryLoss, "権利は減らない")
        #expect(ads.rewardedCount == 1)
        #expect(ads.interstitialCount == 0, "報酬付きにインタースティシャルは使わない")
    }

    @Test("やり直しは 1 回の勝負につき 1 回。中断を挟んでも戻らない")
    func onlyOncePerMatchEvenAcrossRelaunch() async {
        let store = MemorySnapshotStore()
        let (model, _, _) = makeLostModel(store: store)
        #expect(await model.retryLossAfterAd() == .granted)

        // 配る前で離れて開き直す。使用済みの印が残っている。
        let reopened = BlackjackModel(
            services: GameServices(snapshots: store, ads: StubAdService()), seed: 5
        )
        #expect(reopened.phase == .ready)
        #expect(reopened.roundsPlayed == 4)
        reopened.deal()
        // 負けるまで進める（勝ち・引き分けなら次の回へ）。
        var guardCount = 0
        while reopened.outcome != .lose && reopened.outcome != .bust && !reopened.isMatchOver && guardCount < 6 {
            while reopened.phase == .playerTurn { reopened.stand() }
            if reopened.outcome == .lose || reopened.outcome == .bust { break }
            reopened.nextRound()
            reopened.deal()
            guardCount += 1
        }
        if reopened.outcome == .lose || reopened.outcome == .bust {
            #expect(!reopened.canRetryLoss, "開き直しても使用済み")
        }
    }

    @Test("新しい勝負を始めると権利が戻る")
    func restartRestoresTheRetry() async {
        let (model, _, _) = makeLostModel()
        #expect(await model.retryLossAfterAd() == .granted)
        #expect(!model.canRetryLoss)

        model.restartSession()
        // 新しい勝負で負けるまで配る。
        for seed in 0..<50 {
            _ = seed
            model.deal()
            while model.phase == .playerTurn { model.stand() }
            if model.outcome == .lose || model.outcome == .bust { break }
            model.nextRound()
        }
        if model.outcome == .lose || model.outcome == .bust {
            #expect(model.canRetryLoss)
        }
    }

    @Test("記録に積んだ負けは取り消す（広告を見るほど通算成績が増えない）")
    func cancelsTheRecordedLoss() async {
        let defaults = UserDefaults(suiteName: "bj-retry-\(UUID().uuidString)")!
        let log = PlayLog(defaults: defaults)
        let (model, _, _) = makeLostModel(playLog: log)
        #expect(log.record(gameID: "blackjack", variant: "match10")?.losses == 1)

        #expect(await model.retryLossAfterAd() == .granted)

        let record = log.record(gameID: "blackjack", variant: "match10")
        #expect(record?.losses == 0)
        #expect(record?.plays == 0)
    }

    /// 広告のロード中はハブへ戻れる。戻ると Model は捨てられ、次に開くと別の Model が動くが、
    /// 広告の完了を待つ `Task` は古い Model を強参照したまま生き残る（#653）。
    @Test("広告を見ているあいだにハブへ戻ったら、捨てられたモデルにやり直しを適用しない")
    func doesNotApplyAfterLeavingTheScreen() async {
        let generation = GameScreenGeneration()
        let (model, ads, _) = makeLostModel(screenGeneration: generation)
        ads.duringAd = { generation.advance() }

        let outcome = await model.retryLossAfterAd()

        #expect(outcome == .unavailable)
        #expect(model.phase == .result)
        #expect(model.roundsPlayed == 5)
        #expect(ads.rewardedCount == 1, "広告そのものは出ている（計測は従来どおり付く）")
    }

    /// 広告のロード中は同じ画面の「もう一度」も押せる（#727）。画面の世代は進まないので、
    /// 勝負の通し番号と回数で照合する。
    @Test("広告中に新しい勝負を始めたら、やり直しを適用せず新しい勝負の権利も消さない")
    func doesNotApplyToRestartedMatch() async {
        let (model, ads, _) = makeLostModel()
        ads.duringAd = { model.restartSession() }

        let outcome = await model.retryLossAfterAd()

        #expect(outcome == .unavailable, "見終えたのに適用できなかったことを、視聴しなかったことと分けて返す")
        #expect(model.phase == .ready)
        #expect(model.roundsPlayed == 0)
        #expect(model.score == 0)
        #expect(ads.rewardedCount == 1)
    }

    /// 画面の状態はテストから操作できないので、書き方そのものを見る（#727）。
    @Test("視聴中は「もう一度」を押せない")
    func restartButtonIsDisabledWhileWatching() throws {
        let source = try SourceScan.packageSource("Sources/GameBlackjack/BlackjackView.swift")
        let start = try #require(source.range(of: "Button { model.restartSession() } label: {"),
                                 "もう一度ボタンの定義が見つからない（走査が空振りしている）")
        let end = try #require(source.range(of: "// MARK: - Helper", range: start.upperBound..<source.endIndex))
        let restartButton = source[start.upperBound..<end.lowerBound]
        #expect(restartButton.contains("\n            .disabled(retryRescue.isWatching)"),
                "広告のロード〜視聴中に「もう一度」が押せる")
    }

    @Test("広告の目的は既存の undo（新しい purpose は足さない）")
    func usesTheUndoPurpose() throws {
        let model = try SourceScan.packageSource("Sources/GameBlackjack/BlackjackModel.swift")
        let view = try SourceScan.packageSource("Sources/GameBlackjack/BlackjackView.swift")
        #expect(model.contains("purpose: .undo"))
        #expect(view.contains("for: .undo"))
    }
}

/// 画面・読み上げ・ストアの文言から賭けの語を消す（#2552。審査の疑似ギャンブル対応）。
@Suite("ブラックジャック: 賭けの語が画面に残っていない（#2552）")
struct BlackjackNoGamblingWordsTests {
    /// 画面に出る語。`ブラックジャック` の語や「ヒット」「スタンド」「スプリット」は残してよい。
    private static let banned = ["チップ", "ベット", "賭け", "賭ける", "配当", "ダブルダウン", "インシュアランス",
                                 "chip", "Chip", "bet ", "Bet ", "wager", "payout", "Double Down", "insurance"]

    @Test("モジュールの文言表（日本語のキーと英語の訳）に賭けの語が無い")
    func catalogHasNoBettingWords() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/GameBlackjack/Resources/Localization/Localizable.xcstrings")
        let text = try String(contentsOf: url, encoding: .utf8)
        for word in Self.banned {
            #expect(!text.contains(word), "文言表に「\(word)」が残っている")
        }
    }

    @Test("モジュールのソースの tr(\"…\") に賭けの語が無い")
    func sourcesHaveNoBettingWords() throws {
        let sources = try SourceScan.moduleSources("GameBlackjack")
        let literals = SourceScan.strippingComments(sources)
            .components(separatedBy: "tr(\"").dropFirst()
            .compactMap { $0.components(separatedBy: "\"").first }
        #expect(!literals.isEmpty)
        for literal in literals {
            for word in Self.banned {
                #expect(!literal.contains(word), "「\(literal)」に「\(word)」が残っている")
            }
        }
    }

    @Test("モジュール説明と遊び方に賭けの語が無い")
    func moduleAndHowToHaveNoBettingWords() {
        let guide = HowToPlayGuide.blackjack
        let texts = [BlackjackModule().title, BlackjackModule().description, guide.title, guide.hint]
            + guide.lines + guide.items.map(\.text) + guide.notes
        for text in texts {
            for word in Self.banned {
                #expect(!text.contains(word), "「\(text)」に「\(word)」が残っている")
            }
        }
    }
}
