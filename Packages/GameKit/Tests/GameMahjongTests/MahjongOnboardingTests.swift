import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjong
import CoreTestSupport

/// 図で見る「はじめての遊び方」（#2825）の図が、実装のルールのとおりになっていること。
@MainActor
@Suite("麻雀: はじめての遊び方")
struct MahjongOnboardingTests {
    private func makeModel() -> MahjongModel {
        MahjongModel(
            services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()),
            cpuDelay: .zero,
            seed: 2026
        )
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている。gameID は対局の長さによらず同じ")
    func wellFormed() {
        for length in MahjongGameLength.allCases {
            let guide = MahjongOnboarding.guide(length: length)
            #expect(guide.isWellFormed, "\(length)")
            #expect(guide.gameID == makeModel().gameID)
        }
        #expect(MahjongOnboarding.guide(length: .tonpuu) != MahjongOnboarding.guide(length: .singleHand))
    }

    @Test("和了の形の図: 連番 2 組・同じ 3 枚 2 組・同じ 2 枚の 14 枚は和了")
    func winningShape() {
        let groups = MahjongHowToFigures.WinningShapeFigure().groups
        let hand = MahjongHand(tiles: groups.flatMap(\.tiles))
        #expect(hand.total == 14)
        #expect(MahjongShanten.isWinningHand(hand))
        #expect(groups.map(\.tiles.count) == [3, 3, 3, 3, 2])
    }

    @Test("役と立直: 形がそろっても役が無いと和了できず、立直を付けると和了できる")
    func yakuAndRiichi() {
        func context(riichi: Bool) -> MahjongWinContext {
            MahjongWinContext(
                winningTile: MahjongNotation.tile("7m"), isTsumo: false, isRiichi: riichi, isIppatsu: false,
                isLastTile: false, seatWind: 1, roundWind: 0, doraIndicators: [], uraIndicators: []
            )
        }
        let hand = MahjongNotation.hand("123m456m678m22p567s")
        #expect(MahjongShanten.isWinningHand(hand))
        #expect(MahjongScoring.score(hand: hand, context: context(riichi: false)) == nil)
        #expect(MahjongScoring.score(hand: hand, context: context(riichi: true)) != nil)
    }

    @Test("聴牌の図: 13 枚であと 1 枚で和了できる。持ち点は 25000 点から")
    func tenpai() {
        let hand = MahjongHand(tiles: MahjongHowToFigures.RiichiFigure().hand)
        #expect(hand.total == 13)
        #expect(MahjongShanten.isTenpai(hand))
        #expect(!MahjongShanten.waits(hand).isEmpty)
        #expect(MahjongModel.startingScore == 25_000)
    }

    @Test("鳴く: 同じ牌 2 枚で誰の捨て牌でもポンでき、チーは上家（捨てた人の下家）だけ")
    func calls() {
        let hand = MahjongNotation.hand("55p13m")
        let pon = MahjongCallFinder.claimOptions(hand: hand, tile: MahjongNotation.tile("5p"), from: 2, allowsChi: false)
        #expect(pon.map(\.kind) == [.pon])
        // 2m を 1m・3m ではさんでチーできるのは、チーを許された席からの捨て牌だけ。
        let chiSeat = MahjongCallFinder.claimOptions(hand: hand, tile: MahjongNotation.tile("2m"), from: 2, allowsChi: true)
        let otherSeat = MahjongCallFinder.claimOptions(hand: hand, tile: MahjongNotation.tile("2m"), from: 2, allowsChi: false)
        #expect(chiSeat.map(\.kind) == [.chi])
        #expect(otherSeat.isEmpty)
    }

    @Test("流局: 聴牌した人が 3000 点を分け合い、ノーテンの人が払う。持ち点の合計は変わらない")
    func exhaustiveDraw() {
        let model = makeModel()
        model.applyExhaustiveDrawPayments(tenpaiPlayers: [0, 1])
        #expect(model.scores[0] == MahjongModel.startingScore + 1500)
        #expect(model.scores[1] == MahjongModel.startingScore + 1500)
        #expect(model.scores[2] == MahjongModel.startingScore - 1500)
        #expect(model.scores.reduce(0, +) == MahjongModel.startingScore * 4)
    }

    @Test("連荘は東風戦だけ。順位の図の持ち点の合計は 4 人ぶんの持ち点")
    func dealerRepeatAndRanking() {
        #expect(MahjongGameLength.tonpuu.allowsDealerRepeat)
        #expect(!MahjongGameLength.singleHand.allowsDealerRepeat)
        #expect(MahjongGameLength.tonpuu.roundCount == 4)
        #expect(MahjongGameLength.singleHand.roundCount == 1)
        #expect(MahjongOnboarding.exampleScores.reduce(0, +) == MahjongModel.startingScore * 4)
        #expect(MahjongOnboarding.exampleScores == MahjongOnboarding.exampleScores.sorted(by: >))
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for length in MahjongGameLength.allCases {
            for text in MahjongOnboarding.guide(length: length).texts {
                #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
            }
        }
    }
}
