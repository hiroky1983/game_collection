import Core
import Foundation
import Testing
@testable import GameHanafuda

@MainActor
@Suite("花札: 対局の進行")
struct HanafudaModelTests {

    /// 決着まで機械的に回す。人間の手番は「出せる先頭の札」を出し、
    /// 選択待ちになったら先頭の候補を選び、こいこいは聞かれたらあがる。
    /// - Returns: 打ち切りに達したら false。
    @discardableResult
    private func playOut(_ model: HanafudaModel, koiKoi: Bool = false, limit: Int = 400) -> Bool {
        for _ in 0..<limit {
            switch model.phase {
            case .playing:
                if let selection = model.selection {
                    model.chooseFieldCard(selection.candidates[0])
                } else if model.turn == .human {
                    guard let card = model.humanHand.first(where: { model.canPlay($0) }) else {
                        return false
                    }
                    model.play(card)
                } else {
                    model.stepCPU()
                }
            case .koiKoiPrompt:
                if koiKoi, model.deck.count > 0, model.humanHand.count >= 1 {
                    model.declareKoiKoi()
                } else if model.canStop {
                    model.declareStop()
                } else {
                    model.declareKoiKoi()
                }
            case .roundResult:
                model.advanceAfterRound()
            case .matchResult:
                return true
            case .idle:
                return false
            }
        }
        return false
    }

    private func started(seed: UInt64 = 1, options: HanafudaOptions = HanafudaOptions(),
                         services: GameServices? = nil) -> HanafudaModel {
        let model = HanafudaModel(services: services, cpuDelay: .zero, seed: seed)
        model.startMatch(options: options)
        return model
    }

    // MARK: 配り

    @Test("試合を始めると手札8枚ずつ・場8枚・山24枚から始まる")
    func startDealsCorrectly() {
        let model = started()
        #expect(model.humanHand.count == 8)
        #expect(model.cpuHand.count == 8)
        #expect(model.field.count == 8)
        #expect(model.deck.count == 24)
        #expect(model.phase == .playing)
        #expect(model.round == 1)
        #expect(model.turn == model.dealer)
    }

    @Test("48枚は常にどこかに1枚ずつある（局の途中でも）")
    func cardsAreConservedDuringPlay() {
        let model = started(seed: 42)
        for _ in 0..<12 {
            guard model.phase == .playing else { break }
            if let selection = model.selection {
                model.chooseFieldCard(selection.candidates[0])
            } else if model.turn == .human {
                guard let card = model.humanHand.first(where: { model.canPlay($0) }) else { break }
                model.play(card)
            } else {
                model.stepCPU()
            }
            var all = model.humanHand + model.cpuHand + model.field + model.deck
            all += model.humanCaptured + model.cpuCaptured
            if let drawn = model.drawnCard { all.append(drawn) }
            #expect(Set(all.map(\.id)).count == 48, "札が消えたか増えた")
        }
    }

    // MARK: 手番

    @Test("手札を1枚出すと手札が減り、続けて山札が1枚めくれる")
    func oneTurnConsumesAHandCardAndADeckCard() {
        let model = started(seed: 3)
        // 人間が親になる種を探す。
        var m = model
        var seed: UInt64 = 3
        while m.dealer != .human, seed < 30 {
            seed += 1
            m = started(seed: seed)
        }
        #expect(m.dealer == .human)
        let deckBefore = m.deck.count
        let card = m.humanHand.first { m.canPlay($0) }!
        m.play(card)
        if let selection = m.selection { m.chooseFieldCard(selection.candidates[0]) }
        #expect(m.humanHand.count == 7)
        #expect(m.deck.count == deckBefore - 1)
        #expect(!m.humanHand.contains(card))
    }

    @Test("選択待ちのあいだは別の手札を出せない")
    func cannotPlayWhileChoosing() {
        // 場に同月2枚がある局面を作って選択待ちに入れる。
        let model = started(seed: 5)
        var m = model
        var seed: UInt64 = 5
        while m.selection == nil, seed < 200 {
            seed += 1
            m = started(seed: seed)
            while m.phase == .playing, m.selection == nil {
                if m.turn == .human {
                    guard let card = m.humanHand.first(where: { m.canPlay($0) }) else { break }
                    m.play(card)
                } else {
                    m.stepCPU()
                }
            }
        }
        guard let selection = m.selection else { return }  // 200 種で作れなければ検証を飛ばす
        #expect(m.humanHand.allSatisfy { !m.canPlay($0) })
        m.chooseFieldCard(selection.candidates[0])
        #expect(m.selection == nil)
    }

    // MARK: 局と試合の決着

    @Test("6局戦は6局で試合が終わる")
    func sixRoundMatchEndsAfterSixRounds() {
        let model = started(seed: 11, options: HanafudaOptions(rounds: 6))
        #expect(playOut(model))
        #expect(model.phase == .matchResult)
        #expect(model.round == 6)
    }

    @Test("12局戦は12局で試合が終わる")
    func twelveRoundMatchEndsAfterTwelveRounds() {
        let model = started(seed: 12, options: HanafudaOptions(rounds: 12))
        // 12局は 1 局あたり最大 41 手 ×12 で既定の 400 に収まらない。他の12局戦のループと
        // 揃えて明示的に上げる（種を変えたときに本題と関係なく打ち切られないため）。
        #expect(playOut(model, limit: 900))
        #expect(model.round == 12)
    }

    @Test("あがった側が次の局の親になる")
    func winnerBecomesTheNextDealer() {
        let model = started(seed: 21, options: HanafudaOptions(rounds: 6))
        var checked = 0
        for _ in 0..<400 {
            if model.phase == .roundResult {
                let winner = model.roundResult?.winner
                model.advanceAfterRound()
                if let winner, model.phase == .playing {
                    #expect(model.dealer == winner)
                    #expect(model.turn == winner)
                    checked += 1
                }
                continue
            }
            if model.phase == .matchResult { break }
            if model.phase == .koiKoiPrompt {
                if model.canStop { model.declareStop() } else { model.declareKoiKoi() }
                continue
            }
            if let selection = model.selection {
                model.chooseFieldCard(selection.candidates[0])
            } else if model.turn == .human {
                guard let card = model.humanHand.first(where: { model.canPlay($0) }) else { break }
                model.play(card)
            } else {
                model.stepCPU()
            }
        }
        #expect(checked >= 1, "1度もあがりが出ない種を引いた（テストの前提が壊れている）")
    }

    @Test("累計文数は各局の獲得文の合計になる")
    func totalsAccumulate() {
        let model = started(seed: 33, options: HanafudaOptions(rounds: 6))
        var expectedHuman = 0
        var expectedCPU = 0
        for _ in 0..<600 {
            if model.phase == .matchResult { break }
            if model.phase == .roundResult {
                if let result = model.roundResult, let winner = result.winner {
                    if winner == .human { expectedHuman += result.score } else { expectedCPU += result.score }
                }
                model.advanceAfterRound()
                continue
            }
            if model.phase == .koiKoiPrompt {
                if model.canStop { model.declareStop() } else { model.declareKoiKoi() }
                continue
            }
            if let selection = model.selection {
                model.chooseFieldCard(selection.candidates[0])
            } else if model.turn == .human {
                guard let card = model.humanHand.first(where: { model.canPlay($0) }) else { break }
                model.play(card)
            } else {
                model.stepCPU()
            }
        }
        #expect(model.humanTotal == expectedHuman)
        #expect(model.cpuTotal == expectedCPU)
    }

    @Test("だれもあがらずに手札が尽きたら流局で0文")
    func drawnRoundScoresNothing() {
        // 流局が出る種を探す。1 局でも流局が出れば十分。
        var sawDraw = false
        for seed in UInt64(1)..<40 where !sawDraw {
            let model = started(seed: seed, options: HanafudaOptions(rounds: 12))
            for _ in 0..<600 {
                if model.phase == .matchResult { break }
                if model.phase == .roundResult {
                    if let result = model.roundResult, result.winner == nil {
                        sawDraw = true
                        #expect(result.score == 0)
                        #expect(result.hits.isEmpty)
                        #expect(model.humanHand.isEmpty && model.cpuHand.isEmpty)
                    }
                    model.advanceAfterRound()
                    continue
                }
                if model.phase == .koiKoiPrompt {
                    if model.canStop { model.declareStop() } else { model.declareKoiKoi() }
                    continue
                }
                if let selection = model.selection {
                    model.chooseFieldCard(selection.candidates[0])
                } else if model.turn == .human {
                    guard let card = model.humanHand.first(where: { model.canPlay($0) }) else { break }
                    model.play(card)
                } else {
                    model.stepCPU()
                }
            }
        }
        #expect(sawDraw, "40種の配りで一度も流局が出なかった")
    }

    // MARK: こいこい

    @Test("こいこいを宣言すると局が続き、宣言時の文数を超えるまであがれない")
    func koiKoiContinuesAndLocksStopping() {
        var found = false
        for seed in UInt64(1)..<60 where !found {
            let model = started(seed: seed, options: HanafudaOptions(rounds: 12))
            for _ in 0..<600 {
                if model.phase == .matchResult || model.phase == .idle { break }
                if model.phase == .koiKoiPrompt {
                    let points = model.points(of: .human)
                    guard model.deck.count > 0, model.humanHand.count >= 1 else {
                        model.declareStop(); continue
                    }
                    model.declareKoiKoi()
                    found = true
                    // 宣言した直後は同じ文数のままなので、次に役ができるまであがれない。
                    #expect(model.humanKoiKoiCount >= 1)
                    #expect(!HanafudaRules.canStop(currentPoints: points, claimedPoints: points))
                    break
                }
                if model.phase == .roundResult { model.advanceAfterRound(); continue }
                if let selection = model.selection {
                    model.chooseFieldCard(selection.candidates[0])
                } else if model.turn == .human {
                    guard let card = model.humanHand.first(where: { model.canPlay($0) }) else { break }
                    model.play(card)
                } else {
                    model.stepCPU()
                }
            }
        }
        #expect(found, "60種の配りで一度も人間に役ができなかった")
    }

    /// こいこい返し。**相手が宣言していたぶんだけ得点が倍になる**ことを、
    /// 局の結果に記録された理由文で確かめる。
    @Test("相手のこいこいのあとにあがると理由に『こいこい返し』が入る")
    func koiKoiReturnIsRecorded() {
        var sawReturn = false
        for seed in UInt64(1)..<80 where !sawReturn {
            let model = started(seed: seed, options: HanafudaOptions(rounds: 12, difficulty: .normal))
            for _ in 0..<600 {
                if model.phase == .matchResult { break }
                if model.phase == .roundResult {
                    if let result = model.roundResult, let winner = result.winner,
                       model.koiKoiCount(of: winner.other) > 0 {
                        sawReturn = true
                        #expect(result.reasons.contains("こいこい返しで2倍"))
                        #expect(result.score >= result.basePoints * 2)
                    }
                    model.advanceAfterRound()
                    continue
                }
                if model.phase == .koiKoiPrompt {
                    if model.canStop { model.declareStop() } else { model.declareKoiKoi() }
                    continue
                }
                if let selection = model.selection {
                    model.chooseFieldCard(selection.candidates[0])
                } else if model.turn == .human {
                    guard let card = model.humanHand.first(where: { model.canPlay($0) }) else { break }
                    model.play(card)
                } else {
                    model.stepCPU()
                }
            }
        }
        #expect(sawReturn, "80種の配りで一度もこいこい返しが起きなかった")
    }

    @Test("局の得点は役の合計に倍率をかけた値と一致する")
    func roundScoreMatchesScoringRules() {
        let model = started(seed: 51, options: HanafudaOptions(rounds: 12))
        for _ in 0..<800 {
            if model.phase == .matchResult { break }
            if model.phase == .roundResult {
                if let result = model.roundResult, let winner = result.winner {
                    let expected = HanafudaScoring.finalScore(
                        base: result.basePoints,
                        opponentDeclaredKoiKoi: model.koiKoiCount(of: winner.other) > 0
                    )
                    #expect(result.score == expected)
                    #expect(result.basePoints == result.hits.reduce(0) { $0 + $1.points })
                }
                model.advanceAfterRound()
                continue
            }
            if model.phase == .koiKoiPrompt {
                if model.canStop { model.declareStop() } else { model.declareKoiKoi() }
                continue
            }
            if let selection = model.selection {
                model.chooseFieldCard(selection.candidates[0])
            } else if model.turn == .human {
                guard let card = model.humanHand.first(where: { model.canPlay($0) }) else { break }
                model.play(card)
            } else {
                model.stepCPU()
            }
        }
    }

    // MARK: 記録・解析

    @Test("試合が終わると勝敗が記録され、合計文数がリーダーボードへ送られる")
    func matchFinishRecordsAndSubmits() {
        let defaults = UserDefaults(suiteName: "asobiba.hanafuda.tests.record")!
        defaults.removePersistentDomain(forName: "asobiba.hanafuda.tests.record")
        let log = PlayLog(defaults: defaults)
        let spy = SpyGameCenterService()
        let model = HanafudaModel(
            services: makeServices(log: log, gameCenter: spy), cpuDelay: .zero, seed: 61
        )
        model.startMatch(options: HanafudaOptions(rounds: 6))
        #expect(playOut(model))
        #expect(model.recordResult != nil)
        #expect(log.record(gameID: HanafudaModel.gameID)?.plays == 1)
        #expect(spy.scores.count == 1)
        #expect(spy.scores.first?.leaderboardID == GameCenterLeaderboard.hanafudaPoints)
        #expect(spy.scores.first?.value == model.humanTotal)
    }

    @Test("投了は負けとして記録され、中断データが消える")
    func resignRecordsALoss() {
        let defaults = UserDefaults(suiteName: "asobiba.hanafuda.tests.resign")!
        defaults.removePersistentDomain(forName: "asobiba.hanafuda.tests.resign")
        let log = PlayLog(defaults: defaults)
        let store = MemorySnapshotStore()
        let model = HanafudaModel(
            services: makeServices(store: store, log: log), cpuDelay: .zero, seed: 71
        )
        model.startMatch(options: HanafudaOptions(rounds: 6))
        #expect(store.exists(for: HanafudaModel.gameID))
        model.resign()
        #expect(model.phase == .matchResult)
        #expect(log.record(gameID: HanafudaModel.gameID)?.losses == 1)
        #expect(!store.exists(for: HanafudaModel.gameID))
    }

    // MARK: 中断と復元

    @Test("中断した局面がそのまま復元される")
    func snapshotRoundTrips() {
        let store = MemorySnapshotStore()
        let model = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 81)
        model.startMatch(options: HanafudaOptions(rounds: 12, difficulty: .hard))
        for _ in 0..<6 where model.phase == .playing {
            if let selection = model.selection {
                model.chooseFieldCard(selection.candidates[0])
            } else if model.turn == .human {
                guard let card = model.humanHand.first(where: { model.canPlay($0) }) else { break }
                model.play(card)
            } else {
                model.stepCPU()
            }
        }
        let restored = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 999)
        #expect(restored.humanHand == model.humanHand)
        #expect(restored.cpuHand == model.cpuHand)
        #expect(restored.field == model.field)
        #expect(restored.deck == model.deck)
        #expect(restored.humanCaptured == model.humanCaptured)
        #expect(restored.cpuCaptured == model.cpuCaptured)
        #expect(restored.turn == model.turn)
        #expect(restored.dealer == model.dealer)
        #expect(restored.round == model.round)
        #expect(restored.phase == model.phase)
        #expect(restored.options == model.options)
        #expect(restored.selection == model.selection)
    }

    @Test("札が欠けた中断データは復元せず、新規対局から始められる")
    func corruptSnapshotIsRejected() {
        let store = MemorySnapshotStore()
        let model = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 91)
        model.startMatch(options: HanafudaOptions())
        // 1 枚抜いた JSON を流し込む。
        var snap = store.load(HanafudaSnapshot.self, for: HanafudaModel.gameID)!
        snap = HanafudaSnapshot(
            options: snap.options, round: snap.round, dealer: snap.dealer, turn: snap.turn,
            hands: [Array(snap.hands[0].dropLast()), snap.hands[1]],
            captured: snap.captured, field: snap.field, deck: snap.deck,
            claimed: snap.claimed, koiKoiCounts: snap.koiKoiCounts, totals: snap.totals,
            phase: snap.phase, selection: snap.selection, drawnCard: snap.drawnCard,
            roundResult: snap.roundResult, message: snap.message
        )
        #expect(HanafudaModel.validate(snap) == nil)
        store.inject(try! JSONEncoder().encode(snap), for: HanafudaModel.gameID)
        let restored = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 5)
        #expect(restored.phase == .idle, "壊れたデータからは復元しない")
    }

    @Test("同じ札が2枚ある中断データも弾く")
    func duplicateCardsAreRejected() {
        let store = MemorySnapshotStore()
        let model = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 92)
        model.startMatch(options: HanafudaOptions())
        let snap = store.load(HanafudaSnapshot.self, for: HanafudaModel.gameID)!
        // 手札の 1 枚を場札の 1 枚で置き換える（枚数は 48 のまま、重複が生まれる）。
        var hand = snap.hands[0]
        hand[0] = snap.field[0]
        let broken = HanafudaSnapshot(
            options: snap.options, round: snap.round, dealer: snap.dealer, turn: snap.turn,
            hands: [hand, snap.hands[1]], captured: snap.captured, field: snap.field,
            deck: snap.deck, claimed: snap.claimed, koiKoiCounts: snap.koiKoiCounts,
            totals: snap.totals, phase: snap.phase, selection: snap.selection,
            drawnCard: snap.drawnCard, roundResult: snap.roundResult, message: snap.message
        )
        #expect(HanafudaModel.validate(broken) == nil)
    }

    @Test("選択待ちの出どころと札の在り処が食い違う中断データを弾く")
    func selectionSourceMismatchIsRejected() {
        let store = MemorySnapshotStore()
        let model = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 93)
        model.startMatch(options: HanafudaOptions())
        let snap = store.load(HanafudaSnapshot.self, for: HanafudaModel.gameID)!

        func rebuilt(selection: HanafudaSelection, drawnCard: HanafudaCard?) -> HanafudaSnapshot {
            HanafudaSnapshot(
                options: snap.options, round: snap.round, dealer: snap.dealer, turn: snap.turn,
                hands: snap.hands, captured: snap.captured, field: snap.field, deck: snap.deck,
                claimed: snap.claimed, koiKoiCounts: snap.koiKoiCounts, totals: snap.totals,
                phase: snap.phase, selection: selection, drawnCard: drawnCard,
                roundResult: snap.roundResult, message: snap.message
            )
        }

        // 山からめくった扱いなのに、その札が手札に在る（復元後に取り札へ足されて 2 枚になる）。
        let fromDeck = rebuilt(
            selection: HanafudaSelection(
                source: .deck, card: snap.hands[0][0], candidates: [snap.field[0]]
            ),
            drawnCard: nil
        )
        #expect(HanafudaModel.validate(fromDeck) == nil)

        // 手札から出した扱いなのに、その札が手札に無い（同じく重複する）。
        let fromHand = rebuilt(
            selection: HanafudaSelection(
                source: .hand, card: snap.deck[0], candidates: [snap.field[0]]
            ),
            drawnCard: nil
        )
        #expect(HanafudaModel.validate(fromHand) == nil)
    }

    @Test("局数の範囲外は既定の6局へ倒れる")
    func invalidRoundCountFallsBack() {
        #expect(HanafudaOptions(rounds: 7).rounds == 6)
        #expect(HanafudaOptions(rounds: 0).rounds == 6)
        #expect(HanafudaOptions(rounds: 12).rounds == 12)
    }

    // MARK: CPU の駆動

    @Test("CPUの手番は非同期の駆動でも1手だけ進む")
    func cpuTurnRunsOnce() async {
        var model = started(seed: 101)
        var seed: UInt64 = 101
        while model.dealer != .cpu, seed < 140 {
            seed += 1
            model = started(seed: seed)
        }
        #expect(model.dealer == .cpu)
        let handBefore = model.cpuHand.count
        await model.runCPUTurnIfNeeded()
        #expect(model.cpuHand.count < handBefore)
        // CPU が打ち終われば人間の番か、局の決着になっている。
        #expect(model.turn == .human || model.phase != .playing)
    }

    @Test("CPU起動キーは手番ごとに必ず変わる")
    func aiTurnKeyAdvances() {
        let model = started(seed: 111)
        var keys: Set<AITurnKey> = [model.aiTurnKey]
        for _ in 0..<8 {
            guard model.phase == .playing else { break }
            if let selection = model.selection {
                model.chooseFieldCard(selection.candidates[0])
            } else if model.turn == .human {
                guard let card = model.humanHand.first(where: { model.canPlay($0) }) else { break }
                model.play(card)
            } else {
                model.stepCPU()
            }
            #expect(!keys.contains(model.aiTurnKey), "同じキーに戻ると CPU が起動しなくなる")
            keys.insert(model.aiTurnKey)
        }
    }

    @Test("ヒントは取れる手札だけを指す")
    func hintsPointAtCapturableCards() {
        let model = started(seed: 121)
        let hinted = model.capturableHandCards()
        for card in model.humanHand {
            let canTake = !HanafudaRules.matches(for: card, in: model.field).isEmpty
            #expect(hinted.contains(card.id) == canTake, "\(card.name) のヒント判定が違う")
        }
    }
}
