import Testing
import CoreEngine
@testable import GameHearts

/// 4 席それぞれの強さで 1 手（13 巡）を最後まで回す。CPU が合法手以外を選んだら記録して止める。
/// 戻り値は各席が取った点。
private func playHand(
    _ strengths: [CPUStrength], rng: inout SplitMix64, violations: inout [String]
) -> [Int] {
    var deck = HeartsCard.makeDeck()
    deck.shuffle(using: &rng)
    var hands = (0..<4).map { seat in Array(deck[(seat * 13)..<(seat * 13 + 13)]).sorted { $0.id < $1.id } }
    let cpus = strengths.map(HeartsCPU.init(strength:))
    let passes = (0..<4).map { cpus[$0].choosePass(hand: hands[$0], using: &rng) }
    for seat in 0..<4 {
        if passes[seat].count != 3 || Set(passes[seat]).count != 3 || !passes[seat].allSatisfy(hands[seat].contains) {
            violations.append("\(strengths[seat]) の渡す札が不正: \(passes[seat])")
        }
    }
    for seat in 0..<4 { hands[seat].removeAll { passes[seat].contains($0) } }
    for seat in 0..<4 { hands[HeartsRules.passTarget(from: seat)] += passes[seat] }

    var leader = HeartsRules.startingPlayer(hands: hands)
    var broken = false
    var played = Set<Int>()
    var taken = [0, 0, 0, 0]
    for trickIndex in 0..<13 {
        var trick: [HeartsPlay] = []
        for offset in 0..<4 {
            let seat = (leader + offset) % 4
            let view = HeartsCPU.Situation(hand: hands[seat], trick: trick, heartsBroken: broken,
                                      isFirstTrick: trickIndex == 0, playedIDs: played)
            let legal = HeartsRules.legalPlays(hand: hands[seat], trick: trick, heartsBroken: broken,
                                               isFirstTrick: trickIndex == 0)
            guard let card = cpus[seat].choosePlay(view, using: &rng), legal.contains(card) else {
                violations.append("\(strengths[seat]) が合法手以外を選んだ（巡 \(trickIndex)・手札 \(hands[seat])）")
                return taken
            }
            hands[seat].removeAll { $0 == card }
            trick.append(HeartsPlay(player: seat, card: card))
            if card.suit == .heart { broken = true }
        }
        let winner = HeartsRules.trickWinner(trick)!
        taken[winner] += HeartsRules.points(trick.map(\.card))
        played.formUnion(trick.map(\.card.id))
        leader = winner
    }
    if taken.reduce(0, +) != 26 { violations.append("点の合計が 26 でない: \(taken)") }
    return taken
}

@Suite("ハーツの CPU")
struct HeartsCPUTests {
    @Test("どの強さも渡す札は手札の 3 枚・出す札は必ず合法手（各段 400 手）", arguments: CPUStrength.allCases)
    func onlyLegalMoves(strength: CPUStrength) {
        var rng = SplitMix64(seed: UInt64(strength.rawValue + 10))
        var violations: [String] = []
        for _ in 0..<400 {
            _ = playHand([strength, strength, strength, strength], rng: &rng, violations: &violations)
            if !violations.isEmpty { break }
        }
        #expect(violations.isEmpty, "\(violations.prefix(3))")
    }

    @Test("強い段ほど点を取らない（入門 3 人を相手にした 1 手の平均点）")
    func strongerTakesFewerPoints() {
        var averages: [Double] = []
        for strength in CPUStrength.allCases {
            var rng = SplitMix64(seed: 2026)
            var violations: [String] = []
            var total = 0
            let hands = 600
            for _ in 0..<hands {
                total += playHand([strength, .novice, .novice, .novice], rng: &rng, violations: &violations)[0]
            }
            #expect(violations.isEmpty)
            averages.append(Double(total) / Double(hands))
        }
        // 入門 → かんたん → ふつう の順に平均点が下がる。ふつうとむずかしいは入門相手だとどちらも 1 点前後で
        // 差が揺れに埋もれるので、むずかしいは「かんたんより下」だけを見て、ふつうとの差は直接対決（下）で確かめる。
        #expect(averages[1] < averages[0] && averages[2] < averages[1], "平均点が下がっていない: \(averages)")
        #expect(averages[3] < averages[1], "\(averages)")
        // 入門どうしの期待値は 26 / 4 = 6.5 点。むずかしいは大きく下回る。
        #expect(averages.last! < 3, "\(averages)")
    }

    @Test("むずかしいは、ふつう 3 人を相手にしても平均で下回る")
    func hardBeatsNormal() {
        var rng = SplitMix64(seed: 77)
        var violations: [String] = []
        var hard = 0, normal = 0
        for _ in 0..<800 {
            let taken = playHand([.hard, .normal, .normal, .normal], rng: &rng, violations: &violations)
            hard += taken[0]
            normal += taken[1] + taken[2] + taken[3]
        }
        #expect(violations.isEmpty)
        #expect(Double(hard) < Double(normal) / 3, "むずかしい \(hard) / ふつう平均 \(Double(normal) / 3)")
    }

    @Test("ふつう以上は、出だしのスートが無ければスペードのQを押し付ける")
    func dumpsQueenWhenVoid() {
        var rng = SplitMix64(seed: 1)
        for strength in [CPUStrength.normal, .hard] {
            let view = HeartsCPU.Situation(
                hand: [c(.spade, 12), c(.heart, 13), c(.club, 5)],
                trick: [p(1, c(.diamond, 9))], heartsBroken: true, isFirstTrick: false, playedIDs: []
            )
            #expect(HeartsCPU(strength: strength).choosePlay(view, using: &rng) == c(.spade, 12), "\(strength)")
        }
    }

    @Test("ふつう以上は、勝たない範囲で最大の札を出す（スペードのKの下にQを捨てる）")
    func ducksUnderWinningCard() {
        var rng = SplitMix64(seed: 1)
        for strength in [CPUStrength.normal, .hard] {
            let view = HeartsCPU.Situation(
                hand: [c(.spade, 3), c(.spade, 12), c(.spade, 14), c(.club, 5)],
                trick: [p(1, c(.spade, 9)), p(2, c(.spade, 13))], heartsBroken: true, isFirstTrick: false, playedIDs: []
            )
            #expect(HeartsCPU(strength: strength).choosePlay(view, using: &rng) == c(.spade, 12), "\(strength)")
        }
    }

    @Test("むずかしいはスペードのQを低いスペード 3 枚で守れるなら渡さない。守れなければ渡す")
    func hardKeepsGuardedQueen() {
        var rng = SplitMix64(seed: 1)
        let guarded = [c(.spade, 12), c(.spade, 2), c(.spade, 5), c(.spade, 9), c(.club, 14), c(.diamond, 13),
                       c(.heart, 14), c(.heart, 4), c(.club, 3), c(.club, 6), c(.diamond, 2), c(.diamond, 7), c(.heart, 8)]
        let passGuarded = HeartsCPU(strength: .hard).choosePass(hand: guarded, using: &rng)
        #expect(!passGuarded.contains(c(.spade, 12)))
        #expect(passGuarded.count == 3)
        let bare = [c(.spade, 12), c(.spade, 2), c(.club, 14), c(.club, 13), c(.diamond, 13), c(.diamond, 3),
                    c(.heart, 14), c(.heart, 4), c(.club, 3), c(.club, 6), c(.diamond, 2), c(.diamond, 7), c(.heart, 8)]
        #expect(HeartsCPU(strength: .hard).choosePass(hand: bare, using: &rng).contains(c(.spade, 12)))
        #expect(HeartsCPU(strength: .normal).choosePass(hand: guarded, using: &rng).contains(c(.spade, 12)))
    }

    @Test("出せる札が 1 枚ならその札・手札が空なら nil")
    func trivialChoices() {
        var rng = SplitMix64(seed: 1)
        for strength in CPUStrength.allCases {
            let cpu = HeartsCPU(strength: strength)
            let first = HeartsCPU.Situation(hand: [c(.club, 2), c(.heart, 9)], trick: [], heartsBroken: false,
                                       isFirstTrick: true, playedIDs: [])
            #expect(cpu.choosePlay(first, using: &rng) == c(.club, 2))
            let empty = HeartsCPU.Situation(hand: [], trick: [], heartsBroken: false, isFirstTrick: false, playedIDs: [])
            #expect(cpu.choosePlay(empty, using: &rng) == nil)
        }
    }
}
