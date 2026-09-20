import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameBaccarat

/// モデルの進行とチップ経済（#1197）。
@Suite("バカラのモデル")
@MainActor
struct BaccaratModelTests {

    private func makeModel(seed: UInt64 = 20260921) -> BaccaratModel {
        BaccaratModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()),
                      seed: seed)
    }

    @Test("初期状態は 1000 枚・プレイヤーに賭ける・賭け待ち")
    func initialState() {
        let model = makeModel()
        #expect(model.chips == BaccaratModel.initialChips)
        #expect(model.chips == 1000)
        #expect(model.selectedBet == .player)
        #expect(model.phase == .betting)
        #expect(model.playerHand.isEmpty)
        #expect(model.bankerHand.isEmpty)
        #expect(!model.sessionOver)
    }

    @Test("ベットすると両者に 2〜3 枚配られ、その場で決着する")
    func betDealsAndResolves() {
        let model = makeModel()
        model.placeBet(100)

        #expect(model.phase == .result)
        #expect(model.outcome != nil)
        #expect((2...3).contains(model.playerHand.count))
        #expect((2...3).contains(model.bankerHand.count))
        #expect(model.bet == 0, "決着したら場のベットは戻す")
    }

    /// 配りは乱数なので、種を変えながら回して**どの局も公式ルールどおりに配られている**ことを見る。
    /// 1 局だけ見ると引き足しの分岐をほとんど踏まない。
    @Test("100 局とも、枚数と引き足しが公式ルールに一致する")
    func everyDealFollowsTheOfficialRules() {
        for seed in UInt64(1)...100 {
            let model = makeModel(seed: seed)
            model.placeBet(100)
            let player = model.playerHand
            let banker = model.bankerHand

            let playerNatural = isNatural(Array(player.prefix(2)))
            let bankerNatural = isNatural(Array(banker.prefix(2)))
            if playerNatural || bankerNatural {
                #expect(player.count == 2 && banker.count == 2,
                        "種 \(seed): ナチュラルなのに 3 枚目を引いている")
                continue
            }

            let playerTwo = baccaratTotal(Array(player.prefix(2)))
            #expect((player.count == 3) == playerDrawsThird(total: playerTwo),
                    "種 \(seed): プレイヤーの引き足しが表と違う（2 枚合計 \(playerTwo)）")

            let bankerTwo = baccaratTotal(Array(banker.prefix(2)))
            let playerThird = player.count == 3 ? player[2].points : nil
            #expect((banker.count == 3) == bankerDrawsThird(total: bankerTwo, playerThird: playerThird),
                    "種 \(seed): バンカーの引き足しが表と違う（2 枚合計 \(bankerTwo)・3 枚目 \(String(describing: playerThird))）")
        }
    }

    @Test("チップの増減は配当表どおり（賭け先を変えて同じ局を精算する）")
    func chipsFollowThePayoutTable() {
        for bet in BaccaratBet.allCases {
            for seed in UInt64(1)...30 {
                let model = makeModel(seed: seed)
                model.select(bet)
                model.placeBet(100)
                let expected = baccaratChipDelta(
                    bet: bet,
                    outcome: baccaratOutcome(player: model.playerHand, banker: model.bankerHand),
                    amount: 100
                )
                #expect(model.lastChipDelta == expected, "\(bet) / 種 \(seed)")
                #expect(model.chips == 1000 + expected)
            }
        }
    }

    @Test("タイに賭けずにタイが出たら、チップは減らない（引き分け）")
    func tiePushesSideBets() {
        // タイが出る種を探す。3 択のうち 1 つに賭けていてもチップが動かないのがタイの証。
        for seed in UInt64(1)...500 {
            let model = makeModel(seed: seed)
            model.placeBet(100)
            guard model.outcome == .tie else { continue }
            #expect(model.chips == 1000, "賭け金はそのまま戻る")
            #expect(model.lastChipDelta == 0)
            #expect(model.reviewOutcome == .draw)
            return
        }
        Issue.record("タイの出る種が 500 件の中に無かった")
    }

    @Test("賭け先は 3 種類から選べ、選び直しは賭け待ちのあいだだけ")
    func betTargetIsChosenBeforeDealing() {
        #expect(BaccaratBet.allCases.count == 3)
        let model = makeModel()
        model.select(.banker)
        #expect(model.selectedBet == .banker)
        model.placeBet(100)
        // 決着の表示中に賭け先を変えられると、リザルトの文言と精算が食い違う。
        model.select(.tie)
        #expect(model.selectedBet == .banker, "決着後は選び直せない")
        model.nextRound()
        model.select(.tie)
        #expect(model.selectedBet == .tie)
    }

    @Test("残高より多くは賭けられない・最小ベット未満も受け付けない")
    func betsAreBounded() {
        let model = makeModel()
        model.placeBet(2000)
        #expect(model.phase == .betting, "残高を超える賭けは通らない")
        model.placeBet(BaccaratModel.minimumBet - 1)
        #expect(model.phase == .betting, "最小ベット未満は通らない")
        #expect(model.chips == 1000)
    }

    @Test("最小ベットに届かない残高になったらセッション終了")
    func sessionEndsWhenChipsCannotCoverTheMinimumBet() {
        let model = makeModel()
        // 全額を外しやすいタイに賭け続ければ、いずれ最小ベットを割る。
        model.select(.tie)
        for _ in 0..<200 {
            if model.sessionOver { break }
            if model.phase == .result { model.nextRound() }
            guard model.phase == .betting, model.chips >= BaccaratModel.minimumBet else { break }
            model.placeBet(model.chips)
        }
        #expect(model.sessionOver)
        #expect(model.chips < BaccaratModel.minimumBet)
        #expect(model.chips >= 0, "残高を負にしない")

        // 終わったセッションでは賭けられない（残高が最小ベットに足りていても受け付けない）。
        let chipsAtSessionOver = model.chips
        let handAtSessionOver = model.playerHand
        model.placeBet(BaccaratModel.minimumBet)
        #expect(model.chips == chipsAtSessionOver, "賭けが通っていない")
        #expect(model.playerHand == handAtSessionOver, "新しい局が配られていない")
    }

    @Test("最初からやり直すと 1000 枚に戻り、賭け先も既定へ戻る")
    func restartResetsTheSession() {
        let model = makeModel()
        model.select(.tie)
        model.placeBet(100)
        model.restartSession()
        #expect(model.chips == BaccaratModel.initialChips)
        #expect(model.selectedBet == .player)
        #expect(model.phase == .betting)
        #expect(model.outcome == nil)
        #expect(model.playerHand.isEmpty)
        #expect(!model.sessionOver)
    }

    @Test("次のゲームで手札と結果が消える")
    func nextRoundClearsTheTable() {
        let model = makeModel()
        model.placeBet(100)
        model.nextRound()
        #expect(model.phase == .betting)
        #expect(model.outcome == nil)
        #expect(model.playerHand.isEmpty)
        #expect(model.bankerHand.isEmpty)
        #expect(model.lastChipDelta == 0)
    }

    /// 勝敗は「手がどちらが強かったか」ではなく**賭けが当たったか**で決まる（#53 の評価判定）。
    @Test("バンカーの手が勝っても、プレイヤーに賭けていれば負け扱い")
    func reviewOutcomeFollowsTheBetNotTheHand() {
        for seed in UInt64(1)...200 {
            let model = makeModel(seed: seed)
            model.select(.player)
            model.placeBet(100)
            guard model.outcome == .banker else { continue }
            #expect(model.reviewOutcome == .loss)
            #expect(model.lastChipDelta == -100)
            return
        }
        Issue.record("バンカー勝ちの種が 200 件の中に無かった")
    }

    // MARK: - 中断データ

    @Test("復活を使っていないセッションは中断データを残さない")
    func noSnapshotWithoutRevival() {
        let store = MemorySnapshotStore()
        let model = BaccaratModel(services: GameServices(snapshots: store, ads: NoopAdService()),
                                  seed: 20260921)
        model.placeBet(100)
        #expect(!store.exists(for: "baccarat"), "持ち回る途中の局が無いので保存しない")
        #expect(BaccaratModule().hasResumableSnapshot(in: store) == false)
    }
}
