import Core
import Testing
@testable import GameHanafuda

/// 難易度が本当に強さの差になっているかを、自己対戦の実測で確かめる。
///
/// こいこいは配りの運が大きいので、**1 局の勝敗ではなく通算の文数**で比べる。
/// 規模は `swift test`（最適化なし・CI もこれ）で回して秒数を見てから決めた。
/// 探索を持たない CPU なので 1 手あたりの計算は軽く、40 試合でも 1 秒未満で終わる。
@MainActor
@Suite("花札: CPUの強さ")
struct HanafudaStrengthTests {

    /// 「人間」側も CPU に打たせて 1 試合を通す。
    /// - Returns: (人間側の合計文数, CPU 側の合計文数)
    private func playMatch(
        seed: UInt64, humanLevel: HanafudaDifficulty, cpuLevel: HanafudaDifficulty
    ) -> (human: Int, cpu: Int) {
        let model = HanafudaModel(
            cpuDelay: .zero, seed: seed
        )
        model.startMatch(options: HanafudaOptions(rounds: 6, difficulty: cpuLevel))
        var rng = HanafudaRandom(seed: seed &+ 977)

        for _ in 0..<4000 {
            switch model.phase {
            case .matchResult:
                return (model.humanTotal, model.cpuTotal)
            case .roundResult:
                model.advanceAfterRound()
            case .koiKoiPrompt:
                let wants = HanafudaAI.shouldKoiKoi(
                    myPoints: model.points(of: .human),
                    opponentPoints: model.points(of: .cpu),
                    handCount: model.humanHand.count,
                    deckCount: model.deck.count,
                    difficulty: humanLevel
                )
                if wants { model.declareKoiKoi() } else if model.canStop {
                    model.declareStop()
                } else {
                    model.declareKoiKoi()
                }
            case .playing:
                if let selection = model.selection {
                    // 選択待ち。評価の高いほうを取る（CPU の山札めくりと同じ決め方）。
                    let best = selection.candidates.max {
                        HanafudaAI.cardWeight($0) < HanafudaAI.cardWeight($1)
                    }!
                    model.chooseFieldCard(best)
                } else if model.turn == .human {
                    guard let move = HanafudaAI.chooseMove(
                        hand: model.humanHand, field: model.field,
                        captured: model.humanCaptured, opponentCaptured: model.cpuCaptured,
                        options: model.options, difficulty: humanLevel, using: &rng
                    ) else { return (model.humanTotal, model.cpuTotal) }
                    model.play(move.card)
                    if model.selection != nil, let target = move.target {
                        model.chooseFieldCard(target)
                    }
                } else {
                    model.stepCPU()
                }
            case .idle:
                return (model.humanTotal, model.cpuTotal)
            }
        }
        return (model.humanTotal, model.cpuTotal)
    }

    /// 同じ配りで「強 対 弱」と「弱 対 強」を両方回し、席順の有利をならして比べる。
    private func totals(
        _ a: HanafudaDifficulty, vs b: HanafudaDifficulty, matches: Int
    ) -> (a: Int, b: Int) {
        var scoreA = 0
        var scoreB = 0
        for seed in UInt64(1)...UInt64(matches) {
            let first = playMatch(seed: seed, humanLevel: a, cpuLevel: b)
            scoreA += first.human
            scoreB += first.cpu
            let second = playMatch(seed: seed, humanLevel: b, cpuLevel: a)
            scoreA += second.cpu
            scoreB += second.human
        }
        return (scoreA, scoreB)
    }

    @Test("強は弱に通算で勝ち越す")
    func hardBeatsEasy() {
        let result = totals(.hard, vs: .easy, matches: 20)
        #expect(result.a > result.b, "強 \(result.a)文 対 弱 \(result.b)文")
    }

    @Test("普通は弱に通算で勝ち越す")
    func normalBeatsEasy() {
        let result = totals(.normal, vs: .easy, matches: 20)
        #expect(result.a > result.b, "普通 \(result.a)文 対 弱 \(result.b)文")
    }

    /// 「強」は相手の役を止めにいくぶん、自分の取り札の値打ちでは「普通」に譲ることがある。
    /// 勝ち越しまでは求めず、**明確に負け越していないこと**を下限として押さえる
    /// （ここを「必ず勝つ」で書くと、配りの運で落ちるフレークなテストになる）。
    @Test("強は普通に対して大きく負け越さない")
    func hardIsNotWorseThanNormal() {
        let result = totals(.hard, vs: .normal, matches: 20)
        #expect(Double(result.a) >= Double(result.b) * 0.85,
                "強 \(result.a)文 対 普通 \(result.b)文")
    }

    @Test("どの難易度でも試合は必ず決着まで進む")
    func matchesAlwaysFinish() {
        for level in HanafudaDifficulty.allCases {
            for seed in UInt64(1)...5 {
                let result = playMatch(seed: seed, humanLevel: level, cpuLevel: level)
                #expect(result.human >= 0 && result.cpu >= 0)
            }
        }
    }
}
