import Testing
import Foundation
import CoreGraphics
import Core
import CoreTestSupport
import GameKitTestSupport
@testable import GameSpeed

private func card(_ suit: SpeedSuit, _ rank: Int) -> SpeedCard {
    SpeedCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
}

/// iPhone 17 の卓（盤に使える大きさ 402×668）で、寸法の関数から組んだ札・台札の枠。
/// 画面と同じ並び（手札 4 枚 + 山札を左詰めで 1 列、台札 2 山を真ん中に、その上に手札）を数字で再現する。
struct SpeedSwipeTable {
    let hand: [CGRect]
    let piles: [Int: CGRect]

    init(width: CGFloat = 402, height: CGFloat = 668) {
        let metrics = SpeedTableLayout.metrics(contentSize: CGSize(width: width, height: height))
        let inset = FullScreenGameLayoutMetrics.sideInset
        let hw = metrics.handCard.width, hh = metrics.handCard.height
        let pw = metrics.pileCard.width, ph = metrics.pileCard.height
        let handTop: CGFloat = 450
        let rowWidth = hw * 5 + SpeedHandLayout.spacing * 4
        let rowLeft = inset + (width - inset * 2 - rowWidth) / 2
        hand = (0..<4).map { CGRect(x: rowLeft + CGFloat($0) * (hw + SpeedHandLayout.spacing), y: handTop, width: hw, height: hh) }
        let pileTop = handTop - SpeedTableLayout.handGap - SpeedTableLayout.pileVerticalPadding - ph
        let pairWidth = pw * 2 + 20 * 2 + metrics.pileSpacing
        let pairLeft = (width - pairWidth) / 2 + 10
        piles = [
            0: CGRect(x: pairLeft, y: pileTop, width: pw, height: ph),
            1: CGRect(x: pairLeft + pw + 20 + metrics.pileSpacing, y: pileTop, width: pw, height: ph),
        ]
    }

    func center(_ slot: Int) -> CGPoint { CGPoint(x: hand[slot].midX, y: hand[slot].midY) }

    /// 札 `slot` から台札 `pile` の中心へ向かう向きに、`speed` pt/秒で払ったときの速さ。
    func velocity(from slot: Int, toward pile: Int, speed: CGFloat = 1200) -> CGSize {
        let from = center(slot), to = CGPoint(x: piles[pile]!.midX, y: piles[pile]!.midY)
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        return CGSize(width: dx / length * speed, height: dy / length * speed)
    }
}

@Suite("スピード: 払いの判定")
struct SpeedSwipeTests {
    let table = SpeedSwipeTable()

    private func resolve(_ slot: Int, moved: CGSize, velocity: CGSize, playable: Set<Int>) -> SpeedSwipe.Outcome {
        SpeedSwipe.resolve(cardCenter: table.center(slot), translation: moved, velocity: velocity,
                           pileFrames: table.piles, playable: playable)
    }

    @Test("ほとんど動かさずに離したらタップ（今までのタップの操作に渡す）")
    func tap() {
        #expect(resolve(0, moved: CGSize(width: 3, height: -2), velocity: .zero, playable: [0]) == .tap)
        #expect(resolve(0, moved: .zero, velocity: CGSize(width: 0, height: -40), playable: [0, 1]) == .tap)
    }

    @Test("左上へ払えば左、右上へ払えば右の台札に出す（短い払いでも速さで決まる）")
    func flickByDirection() {
        let short = CGSize(width: 0, height: -30)
        for slot in 0..<4 {
            #expect(resolve(slot, moved: short, velocity: table.velocity(from: slot, toward: 0), playable: [0, 1]) == .play(0),
                    "札 \(slot) を左の台札へ")
            #expect(resolve(slot, moved: short, velocity: table.velocity(from: slot, toward: 1), playable: [0, 1]) == .play(1),
                    "札 \(slot) を右の台札へ")
        }
    }

    @Test("狙った台札に出せなければ外れ（跳ね返す）。もう片方に出せても勝手に回さない")
    func flickAtWrongPileMisses() {
        // 右端の札から左上へ大きく払う（真上ではない）。左には出せず、右には出せる。
        let v = table.velocity(from: 3, toward: 0)
        #expect(abs(SpeedSwipe.angleFromUp(v)) > SpeedSwipe.straightUpTolerance)
        #expect(resolve(3, moved: CGSize(width: -20, height: -20), velocity: v, playable: [1]) == .miss(0))
        #expect(resolve(3, moved: CGSize(width: -20, height: -20), velocity: v, playable: []) == .miss(0))
    }

    @Test("上へまっすぐ払ったら、出せる台札が 1 つならそこ、2 つなら角度の近いほう")
    func straightUp() {
        let up = CGSize(width: 0, height: -1200)
        // 左端の札の真上はほぼ左の台札だが、右にしか出せなければ右へ。
        #expect(resolve(0, moved: CGSize(width: 0, height: -40), velocity: up, playable: [1]) == .play(1))
        #expect(resolve(3, moved: CGSize(width: 0, height: -40), velocity: up, playable: [0]) == .play(0))
        // 両方に出せるなら近いほう。
        #expect(resolve(0, moved: CGSize(width: 0, height: -40), velocity: up, playable: [0, 1]) == .play(0))
        #expect(resolve(3, moved: CGSize(width: 0, height: -40), velocity: up, playable: [0, 1]) == .play(1))
        // どちらにも出せなければ外れ。
        if case .miss = resolve(1, moved: CGSize(width: 0, height: -40), velocity: up, playable: []) {} else {
            Issue.record("どちらにも出せないのに外れにならない")
        }
    }

    @Test("真横に払っても向きで決まる。下へ払ったら取り消し")
    func sidewaysAndDown() {
        #expect(resolve(3, moved: CGSize(width: -30, height: 0), velocity: CGSize(width: -1200, height: 0), playable: [0, 1]) == .play(0))
        #expect(resolve(0, moved: CGSize(width: 30, height: 0), velocity: CGSize(width: 1200, height: 0), playable: [0, 1]) == .play(1))
        #expect(resolve(1, moved: CGSize(width: 0, height: 40), velocity: CGSize(width: 0, height: 1200), playable: [0, 1]) == .cancel)
    }

    @Test("速さが足りなくても、台札の上で離せば置く。出せない台札の上なら外れ")
    func slowDropOnPile() {
        let pile0 = table.piles[0]!
        let from = table.center(2)
        let moved = CGSize(width: pile0.midX - from.x, height: pile0.midY - from.y)
        #expect(resolve(2, moved: moved, velocity: CGSize(width: 0, height: -20), playable: [0]) == .play(0))
        #expect(resolve(2, moved: moved, velocity: .zero, playable: [1]) == .miss(0))
        // 台札の縁から少し外れていても置ける（`dropMargin` の余裕）。
        let nearEdge = CGSize(width: pile0.minX - SpeedSwipe.dropMargin / 2 - from.x, height: pile0.midY - from.y)
        #expect(resolve(2, moved: nearEdge, velocity: .zero, playable: [0]) == .play(0))
    }

    /// iPhone 17 のシミュレータで XCUITest の払い（press → drag・速さ .fast）を実際に入れたときの
    /// `DragGesture` の値（2026-10-23 実測）。右上へ速く払った ♥9 が、左の台札の縁の余裕（20pt）に入って
    /// 外れにされていた。速く払ったら縁の余裕より向きを先に見る。
    @Test("実測: 右上へ速く払った札が左の台札の縁をかすめても、右に出す")
    func measuredFlickGrazingOtherPile() {
        let piles: [Int: CGRect] = [
            0: CGRect(x: 69, y: 193.27, width: 98, height: 142.26),
            1: CGRect(x: 219, y: 193.27, width: 98, height: 142.26),
        ]
        let nine = CGRect(x: 80, y: 351.67, width: 70, height: 101.33)
        #expect(SpeedSwipe.resolve(cardCenter: CGPoint(x: nine.midX, y: nine.midY), translation: CGSize(width: 52, height: -47),
                                   velocity: CGSize(width: 460, height: -415), pileFrames: piles, playable: [1]) == .play(1))
        let five = CGRect(x: 2, y: 351.67, width: 70, height: 101.33)
        #expect(SpeedSwipe.resolve(cardCenter: CGPoint(x: five.midX, y: five.midY), translation: CGSize(width: 35.3, height: -60.3),
                                   velocity: CGSize(width: 320, height: -530), pileFrames: piles, playable: [0]) == .play(0))
    }

    @Test("ゆっくり動かして台札の外で離したら取り消し（警告は鳴らさない）")
    func slowDropElsewhere() {
        #expect(resolve(1, moved: CGSize(width: 0, height: -30), velocity: CGSize(width: 0, height: -100), playable: [0, 1]) == .cancel)
        #expect(resolve(1, moved: CGSize(width: 0, height: -35), velocity: .zero, playable: [0, 1]) == .cancel)
    }

    @Test("実測: 短い払いで離す瞬間に速さが落ちても、36pt 以上動かした向きで出す。下へ戻せば取り消し")
    func slowButCommitted() {
        // XCUITest の 40pt の払い（2026-10-23 実測）: 動いた量 (20, -34)・速さ (31, -46)。
        let v = CGSize(width: 31, height: -46)
        #expect(resolve(1, moved: CGSize(width: 20, height: -34), velocity: v, playable: [1]) == .play(1))
        #expect(resolve(1, moved: CGSize(width: 15, height: -25), velocity: v, playable: [1]) == .cancel, "36pt 未満は取り消し")
        #expect(resolve(0, moved: CGSize(width: 0, height: -40), velocity: .zero, playable: [0, 1]) == .play(0))
        #expect(resolve(1, moved: CGSize(width: 0, height: 60), velocity: .zero, playable: [0, 1]) == .cancel)
    }

    @Test("しきい値: 速さ 300pt/秒・タップ 10pt・台札の余裕 20pt・まっすぐ ±15 度")
    func thresholds() {
        #expect(SpeedSwipe.commitDistance == 36)
        #expect(SpeedSwipe.flickSpeed == 300)
        #expect(SpeedSwipe.tapSlop == 10)
        #expect(SpeedSwipe.dropMargin == 20)
        #expect(SpeedSwipe.straightUpTolerance == 15)
        #expect(SpeedSwipe.maxFlickAngle == 100)
        #expect(SpeedSwipe.angleFromUp(CGSize(width: 0, height: -1)) == 0)
        #expect(abs(SpeedSwipe.angleFromUp(CGSize(width: 1, height: -1)) - 45) < 0.001)
        #expect(abs(SpeedSwipe.angleFromUp(CGSize(width: -1, height: 0)) + 90) < 0.001)
    }
}

/// 払いの判定 → Model の経路（判定の結果をそのまま `swipeCard` に渡したときに場がどう動くか）。
@Suite("スピード: 払いから台札へ")
@MainActor
struct SpeedSwipeModelPathTests {
    let table = SpeedSwipeTable()

    private func model(feedback: SpyFeedbackService = SpyFeedbackService()) -> SpeedModel {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: feedback)
        let model = SpeedModel(services: services, seed: 1)
        model.start(SpeedSettings(level: .normal))
        // ♥5 は左（♠6）、♥9 は右（♥10）に出せる。♦Q・♥2 はどちらにも出せない。
        model.configureForTesting(
            humanHand: [card(.hearts, 5), card(.hearts, 9), card(.diamonds, 12), card(.hearts, 2)],
            humanStock: [card(.diamonds, 7)],
            cpuHand: [card(.spades, 3)], cpuStock: [card(.clubs, 3)],
            piles: [[card(.spades, 6)], [card(.hearts, 10)]]
        )
        return model
    }

    /// View の `onEnded` と同じ手順: 判定 → 出す。
    private func swipe(_ model: SpeedModel, slot: Int, moved: CGSize, velocity: CGSize) -> SpeedSwipe.Outcome {
        let card = model.humanHand[slot]
        let outcome = SpeedSwipe.resolve(cardCenter: table.center(slot), translation: moved, velocity: velocity,
                                         pileFrames: table.piles, playable: Set(model.playableTargets(for: card)))
        switch outcome {
        case .play(let pile), .miss(let pile): model.swipeCard(card, onto: pile)
        case .tap: model.tapHandCard(card)
        case .cancel: break
        }
        return outcome
    }

    @Test("上へ払うと、出せるただ 1 つの台札に出て、同じ枠に山札から補充される")
    func flickPlays() {
        let m = model()
        #expect(swipe(m, slot: 0, moved: CGSize(width: 0, height: -40), velocity: CGSize(width: 0, height: -900)) == .play(0))
        #expect(m.tops[0] == card(.hearts, 5))
        #expect(m.humanHand[0] == card(.diamonds, 7), "出した枠に補充（4 枚の位置は動かない）")
    }

    @Test("出せない札を払うと警告だけで場は動かない（ペナルティなし）")
    func flickMisses() {
        let feedback = SpyFeedbackService()
        let m = model(feedback: feedback)
        let before = m.piles
        feedback.reset()
        if case .miss = swipe(m, slot: 2, moved: CGSize(width: 0, height: -40), velocity: CGSize(width: 0, height: -900)) {} else {
            Issue.record("出せない札が外れにならない")
        }
        #expect(m.piles == before)
        #expect(m.humanHand.count == 4)
        #expect(feedback.notices(of: .warning) == 1)
        #expect(m.phase == .playing)
    }

    @Test("右の台札の上まで動かして離すと、速さが無くても置ける")
    func dropOnPile() {
        let m = model()
        let pile1 = table.piles[1]!, from = table.center(1)
        let moved = CGSize(width: pile1.midX - from.x, height: pile1.midY - from.y)
        #expect(swipe(m, slot: 1, moved: moved, velocity: .zero) == .play(1))
        #expect(m.tops[1] == card(.hearts, 9))
    }
}

@Suite("スピード: 卓の寸法")
struct SpeedTableLayoutTests {
    @Test("手札 4 枚 + 山札は iPhone SE・iPhone 17 の幅に収まり、札は 44pt 以上")
    func handFits() {
        for width: CGFloat in [375, 402, 440] {
            #expect(SpeedHandLayout.fits(screenWidth: width), "\(width)")
            let w = SpeedHandLayout.cardWidth(contentWidth: width - FullScreenGameLayoutMetrics.sideInset * 2)
            #expect(w >= 44)
        }
        #expect(SpeedHandLayout.cardWidth(contentWidth: 0) == SpeedHandLayout.minCardWidth, "大きさ 0 でも負にならない")
    }

    @Test("台札は手札より大きく、上限は手札の 1.4 倍。SE でも中身が使える高さに収まる")
    func pileSize() {
        // 盤に使える高さ（FullScreenGameChromeTests の値）: iPhone 17 は 668pt・SE は 537pt。
        for (width, height) in [(CGFloat(402), CGFloat(668)), (375, 537)] {
            let m = SpeedTableLayout.metrics(contentSize: CGSize(width: width, height: height))
            #expect(m.pileCard.width >= m.handCard.width)
            #expect(m.pileCard.width <= m.handCard.width * SpeedTableLayout.maxPileRatio + 0.001)
            let used = SpeedTableLayout.verticalInset * 2 + SpeedTableLayout.statsHeight + SpeedTableLayout.spacing * 2
                + SpeedTableLayout.actionMinHeight + m.cpuCard.height + SpeedTableLayout.cpuGap
                + SpeedTableLayout.pileVerticalPadding * 2 + m.pileCard.height + SpeedTableLayout.handGap + m.handCard.height
            #expect(used <= height, "\(width)×\(height) で \(used)pt 使う")
        }
        let zero = SpeedTableLayout.metrics(contentSize: .zero)
        #expect(zero.pileCard.width > 0)
    }

    @Test("手札の枠: 出した札の枠に補充が入り、山札が尽きたら空けたまま（ほかの札を寄せない）")
    func arrange() {
        #expect(SpeedHandLayout.arrange(previous: [], hand: [1, 2, 3, 4]) == [1, 2, 3, 4])
        // 2 を出して 9 を補充（Model は同じ位置に入れる）。
        #expect(SpeedHandLayout.arrange(previous: [1, 2, 3, 4], hand: [1, 9, 3, 4]) == [1, 9, 3, 4])
        // 山札が尽きて 1 を出した → 1 の枠は空いたまま。
        #expect(SpeedHandLayout.arrange(previous: [1, 9, 3, 4], hand: [9, 3, 4]) == [nil, 9, 3, 4])
        #expect(SpeedHandLayout.arrange(previous: [nil, 9, 3, 4], hand: [9, 4]) == [nil, 9, nil, 4])
        // 新しいゲーム（全部入れ替わり）は前から詰める。
        #expect(SpeedHandLayout.arrange(previous: [nil, 9, nil, 4], hand: [11, 12, 13, 14]) == [11, 12, 13, 14])
    }
}
