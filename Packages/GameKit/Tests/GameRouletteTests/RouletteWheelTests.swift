import Testing
import Foundation
@testable import GameRoulette

@Suite("ルーレットのホイール（#1318）")
struct RouletteWheelTests {

    @Test("ポケットは 37 個で 0〜36 を 1 つずつ持つ")
    func pocketsCoverEveryNumberOnce() {
        #expect(RouletteWheel.pocketOrder.count == RouletteWheel.pocketCount)
        #expect(Set(RouletteWheel.pocketOrder) == Set(RouletteWheel.numbers))
        #expect(RouletteWheel.pocketOrder.first == 0, "0 が先頭（回転 0 で 12 時）")
    }

    @Test("並びは実物のヨーロピアンホイールと同じ")
    func pocketOrderMatchesTheRealWheel() {
        // 「37 個・重複なし・赤黒交互」を満たす別の順列に差し替えても上のテストは通るので、並びそのものを固定する。
        #expect(RouletteWheel.pocketOrder == [
            0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
            5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
        ])
        #expect(RouletteWheel.redNumbers == [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36])
    }

    @Test("赤 18・黒 18・緑は 0 だけ")
    func colorsAreBalanced() {
        let colors = RouletteWheel.numbers.map(RouletteWheel.color(of:))
        #expect(colors.filter { $0 == .red }.count == 18)
        #expect(colors.filter { $0 == .black }.count == 18)
        #expect(colors.filter { $0 == .green }.count == 1)
        #expect(RouletteWheel.color(of: 0) == .green)
        // 実物と同じ配色の代表例。
        #expect(RouletteWheel.color(of: 1) == .red)
        #expect(RouletteWheel.color(of: 2) == .black)
        #expect(RouletteWheel.color(of: 10) == .black)
        #expect(RouletteWheel.color(of: 19) == .red)
        #expect(RouletteWheel.color(of: 36) == .red)
    }

    @Test("ホイール上の位置は数字から一意に引ける")
    func pocketIndexRoundTrips() {
        for number in RouletteWheel.numbers {
            let index = RouletteWheel.pocketIndex(of: number)
            #expect(RouletteWheel.pocketOrder[index] == number)
        }
        #expect(RouletteWheel.pocketIndex(of: 99) == 0, "範囲外は 0 に倒す")
    }

    @Test("隣り合うポケットは赤黒が交互になる（0 の両隣を除く）")
    func neighbouringPocketsAlternateColors() {
        let order = RouletteWheel.pocketOrder
        for i in 1..<(order.count - 1) {
            let here = RouletteWheel.color(of: order[i])
            let next = RouletteWheel.color(of: order[i + 1])
            #expect(here != next, "\(order[i]) と \(order[i + 1]) が同じ色で隣り合っている")
        }
    }
}

@Suite("賭けの種類と配当（#1318）")
struct RouletteBetKindTests {

    @Test("配当は数字 1 点 35 倍・12 個の区分 2 倍・その他 1 倍")
    func payouts() {
        #expect(RouletteBetKind.straight(7).payout == 35)
        #expect(RouletteBetKind.dozen(1).payout == 2)
        #expect(RouletteBetKind.dozen(3).payout == 2)
        for kind in RouletteBetKind.evenMoney {
            #expect(kind.payout == 1, "\(kind.label)")
        }
    }

    @Test("赤黒・奇数偶数・1〜18/19〜36 はそれぞれ 18 個を覆い、0 は覆わない")
    func evenMoneyBetsCoverEighteenNumbers() {
        for kind in RouletteBetKind.evenMoney {
            let covered = RouletteWheel.numbers.filter(kind.covers)
            #expect(covered.count == 18, "\(kind.label) が覆う数は \(covered.count)")
            #expect(!kind.covers(0), "\(kind.label) は 0 で外れ")
        }
        #expect(RouletteBetKind.red.covers(1) && !RouletteBetKind.red.covers(2))
        #expect(RouletteBetKind.odd.covers(1) && !RouletteBetKind.odd.covers(2))
        #expect(RouletteBetKind.low.covers(18) && !RouletteBetKind.low.covers(19))
        #expect(RouletteBetKind.high.covers(19) && !RouletteBetKind.high.covers(18))
    }

    @Test("12 個の区分は互いに重ならず、1〜36 を覆い尽くす")
    func dozensPartitionTheBoard() {
        var covered: [Int] = []
        for kind in RouletteBetKind.dozens {
            let numbers = RouletteWheel.numbers.filter(kind.covers)
            #expect(numbers.count == 12, "\(kind.label)")
            covered += numbers
        }
        #expect(Set(covered) == Set(1...36))
        #expect(covered.count == 36, "重なりが無い")
        #expect(!RouletteBetKind.dozen(1).covers(0))
        #expect(!RouletteBetKind.dozen(4).covers(37), "存在しない区分は何も覆わない")
    }

    @Test("数字 1 点はその数字だけを覆う")
    func straightCoversOnlyItself() {
        for number in RouletteWheel.numbers {
            let kind = RouletteBetKind.straight(number)
            #expect(RouletteWheel.numbers.filter(kind.covers) == [number])
        }
    }

    @Test("盤面に出す名前は区分の範囲を含む")
    func labels() {
        #expect(RouletteBetKind.straight(0).label == "0")
        #expect(RouletteBetKind.dozen(1).label == "1〜12")
        #expect(RouletteBetKind.dozen(2).label == "13〜24")
        #expect(RouletteBetKind.dozen(3).label == "25〜36")
        #expect(RouletteBetKind.low.label == "1〜18")
        #expect(RouletteBetKind.high.label == "19〜36")
    }

    @Test("Codable で往復できる（中断データに書く）")
    func codableRoundTrip() throws {
        let kinds: [RouletteBetKind] = [.straight(0), .straight(36), .red, .black, .odd, .even, .low, .high, .dozen(2)]
        let bets = kinds.enumerated().map { RouletteBet(id: $0.offset, kind: $0.element, amount: 10 * ($0.offset + 1)) }
        let data = try JSONEncoder().encode(bets)
        let decoded = try JSONDecoder().decode([RouletteBet].self, from: data)
        #expect(decoded == bets)
    }
}

@Suite("精算（#1318）")
struct RouletteSettlementTests {

    @Test("数字 1 点に 10 枚で当たると 360 枚戻り、収支は +350")
    func straightWin() {
        let settlement = rouletteSettlement(bets: [RouletteBet(id: 0, kind: .straight(7), amount: 10)], winningNumber: 7)
        #expect(settlement.staked == 10)
        #expect(settlement.returned == 360)
        #expect(settlement.net == 350)
        #expect(settlement.winningBets == 1)
    }

    @Test("外れた口は元金ごと失う")
    func loss() {
        let settlement = rouletteSettlement(bets: [RouletteBet(id: 0, kind: .straight(7), amount: 10)], winningNumber: 8)
        #expect(settlement.returned == 0)
        #expect(settlement.net == -10)
        #expect(settlement.winningBets == 0)
    }

    @Test("赤と黒に同額を置くと、0 以外なら収支ゼロ・0 なら両方失う")
    func hedgedBets() {
        let bets = [RouletteBet(id: 0, kind: .red, amount: 10), RouletteBet(id: 1, kind: .black, amount: 10)]
        let red = rouletteSettlement(bets: bets, winningNumber: 1)
        #expect(red.returned == 20)
        #expect(red.net == 0)
        let zero = rouletteSettlement(bets: bets, winningNumber: 0)
        #expect(zero.returned == 0)
        #expect(zero.net == -20)
    }

    @Test("複数の口が同時に当たると合算される")
    func multipleWinners() {
        let bets = [
            RouletteBet(id: 0, kind: .straight(17), amount: 10),   // 360
            RouletteBet(id: 1, kind: .dozen(2), amount: 50),       // 150
            RouletteBet(id: 2, kind: .black, amount: 100),         // 200（17 は黒）
            RouletteBet(id: 3, kind: .even, amount: 100),          // 外れ
        ]
        let settlement = rouletteSettlement(bets: bets, winningNumber: 17)
        #expect(settlement.staked == 260)
        #expect(settlement.returned == 710)
        #expect(settlement.net == 450)
        #expect(settlement.winningBets == 3)
    }

    @Test("口が無ければ何も動かない")
    func noBets() {
        let settlement = rouletteSettlement(bets: [], winningNumber: 0)
        #expect(settlement == RouletteSettlement(staked: 0, returned: 0, winningBets: 0))
    }
}
