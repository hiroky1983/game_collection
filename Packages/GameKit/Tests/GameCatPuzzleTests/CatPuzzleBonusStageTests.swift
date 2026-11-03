import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// 141 面目以降の盤の回し（12×12・11×11・ボーナスステージ）。面番号→盤の対応を固定する（#3260）。
@Suite("おじさんちのねこさがしの 141 面目以降の盤の回し")
@MainActor
struct CatPuzzleBonusStageTests {

    @Test("141〜160 面の盤: 1 の位 3・8 は 11×11、5 は 6×6 / 7×7 のボーナス、ほかは 12×12")
    func boardsInTwoCycles() {
        let sizes = (141...160).map { CatPuzzleStage($0).size }
        let expected: [CatPuzzleSize] = [
            .size12, .size12, .size11, .size12, .easy, .size12, .size12, .size11, .size12, .size12,   // 141〜150
            .size12, .size12, .size11, .size12, .normal, .size12, .size12, .size11, .size12, .size12,  // 151〜160
        ]
        #expect(sizes == expected)
    }

    @Test("ボーナスは 1 周りごとに 6×6 と 7×7 が交互")
    func bonusAlternates() {
        let bonus = stride(from: 145, through: 205, by: 10).map { CatPuzzleStage($0).size }
        #expect(bonus == [.easy, .normal, .easy, .normal, .easy, .normal, .easy])
        #expect((141...1200).filter { CatPuzzleStage($0).isBonus } == (14...119).map { $0 * 10 + 5 })
    }

    @Test("140 面目までの盤の表は変わらない（ボーナスなし）")
    func tableUnchanged() {
        let sizes = [1, 10, 11, 25, 26, 45, 46, 70, 71, 100, 101, 140].map { CatPuzzleStage($0).size }
        #expect(sizes == [.easy, .easy, .normal, .normal, .hard, .hard, .expert, .expert, .size10, .size10, .size11, .size11])
        #expect((1...140).allSatisfy { !CatPuzzleStage($0).isBonus && CatPuzzleStage($0).progress.toBonus == nil })
        // 145 は 6×6 だが、5 の付く 25・45・65・85・105・125 面目はボーナスではない。
        #expect(CatPuzzleStage(125).size == .size11)
    }

    @Test("鍵の面（1 の位が 0）は 12×12 のまま、ボーナス・11×11 と重ならない")
    func keyStagesStayLarge() {
        for number in stride(from: 150, through: 1000, by: 10) {
            #expect(CatPuzzleStage(number).isKey)
            #expect(CatPuzzleStage(number).size == .size12, "\(number) 面目")
            #expect(!CatPuzzleStage(number).isBonus)
        }
    }

    @Test("ボーナスと 11×11 の問題の段・入り組み: ボーナスは段 3 まで・入り組み 0、11×11 は前半（3）が段 3 まで、後半（8）が段 4")
    func tiersAndWinding() {
        #expect(CatPuzzleStage(145).tiers == 1...3 && CatPuzzleStage(145).winding == 0)
        #expect(CatPuzzleStage(155).tiers == 1...3 && CatPuzzleStage(155).winding == 0)
        #expect(CatPuzzleStage(143).tiers == 1...3 && CatPuzzleStage(143).winding == 1)
        #expect(CatPuzzleStage(148).tiers == 4...4 && CatPuzzleStage(148).winding == 2)
        // 12×12 の前半・後半は従来どおり（141 面目から数えた 10 面ごと）。
        #expect([141, 142, 144, 146, 147, 149, 150].map { CatPuzzleStage($0).tiers } == [1...4, 1...4, 1...4, 4...4, 4...4, 4...4, 4...4])
    }

    @Test("進み具合: 次のボーナスまでの面数。ボーナスそのものは 0、1 つ前も 0、141 面目より前は nil")
    func bonusDistance() {
        let at = { (n: Int) in CatPuzzleStage(n).progress }
        #expect(at(141).toBonus == 3 && at(144).toBonus == 0 && at(145).toBonus == 0 && at(145).isBonus)
        #expect(at(146).toBonus == 8 && at(150).toBonus == 4 && !at(146).isBonus)
        #expect(at(140).toBonus == nil)
        #expect(CatPuzzleStageProgressText.bonus(at(141)) == "次のボーナスまであと 3 面")
        #expect(CatPuzzleStageProgressText.bonus(at(144)) == "次はボーナスステージ")
        #expect(CatPuzzleStageProgressText.bonus(at(145)) == "ボーナスステージ")
        #expect(CatPuzzleStageProgressText.bonus(at(140)) == nil)
        #expect(CatPuzzleStageProgressText.position(at(145)) == "ボーナスステージ（6×6）")
        #expect(CatPuzzleStageProgressText.position(at(155)) == "ボーナスステージ（7×7）")
        #expect(CatPuzzleStageProgressText.position(at(143)) == "11×11：3 面目")
    }

    @Test("141 面目以降は次の盤の行を出さず、盤の切り替えの演出は 141 面目だけ")
    func noNextBoardAfterTable() {
        for number in 141...200 {
            let progress = CatPuzzleStage(number).progress
            #expect(progress.count == nil && progress.nextSize == nil && progress.toNextBoard == nil)
            #expect(CatPuzzleStageProgressText.nextBoard(progress) == nil)
        }
        #expect((141...1100).filter { CatPuzzleStage($0).entersNewBoard } == [141])
    }

    @Test("同梱の問題の盤の大きさは、46〜1,000 面すべてで面の盤と同じ")
    func bankMatchesBoards() {
        for number in 46...1000 {
            #expect(CatPuzzleStageBank.puzzle(for: number)?.side == CatPuzzleStage(number).size.side, "\(number) 面目")
        }
    }

    @Test("1,001 面目以降の繰り返しも同じ回し方を保つ（盤・ボーナス・鍵の面が写し元と一致）")
    func repeatKeepsCycle() {
        #expect(CatPuzzleStageBank.sourceNumber(for: 1001) == 141)
        for number in 1001...2200 {
            let source = CatPuzzleStageBank.sourceNumber(for: number)
            #expect(CatPuzzleStage(source).size == CatPuzzleStage(number).size, "\(number) 面目")
            #expect(CatPuzzleStage(source).isBonus == CatPuzzleStage(number).isBonus, "\(number) 面目")
            #expect(CatPuzzleStage(source).isKey == CatPuzzleStage(number).isKey, "\(number) 面目")
        }
        // ボーナスの 6×6 / 7×7 の交互も繰り返しの前後でそろう（1,005 面目は 145 面目＝6×6、1,015 面目は 155 面目＝7×7）。
        #expect([1005, 1015, 1025].map { CatPuzzleStage($0).size } == [.easy, .normal, .easy])
        // 繰り返しの長さは 20 面の倍数（盤の回しの周期）。
        #expect((CatPuzzleStageBank.lastStage - 141 + 1) % 20 == 0)
    }

    @Test("ボーナスステージを始めた直後だけ bonusIntro が立つ")
    func bonusIntroFlag() async {
        let defaults = UserDefaults(suiteName: "asobiba.catpuzzle.bonus.tests")!
        defaults.removePersistentDomain(forName: "asobiba.catpuzzle.bonus.tests")
        let model = CatPuzzleModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()),
                                   stageDefaults: defaults)
        #expect(model.bonusIntro == nil)
        model.startStage(145)
        await model.stagePreparation?.value
        #expect(model.bonusIntro == .easy)
        model.clearBonusIntro()
        #expect(model.bonusIntro == nil)
        model.startStage(146)
        await model.stagePreparation?.value
        #expect(model.bonusIntro == nil)
    }
}
