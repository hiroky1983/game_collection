import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// ステージの今の位置の表示（#3240）。面番号→盤・位置・次の盤・鍵の面までの対応。
@Suite("おじさんちのねこさがしのステージの進み具合")
@MainActor
struct CatPuzzleStageProgressTests {

    @Test("盤の境目: 10→11（6×6→7×7）、25→26、140→141（11×11→12×12）")
    func boardBoundaries() {
        let ten = CatPuzzleStage(10).progress
        #expect(ten.size == .easy && ten.position == 10 && ten.count == 10 && ten.toNextBoard == 0 && ten.nextSize == .normal)
        let eleven = CatPuzzleStage(11).progress
        #expect(eleven.size == .normal && eleven.position == 1 && eleven.count == 15 && eleven.toNextBoard == 14)
        let last7 = CatPuzzleStage(25).progress
        #expect(last7.size == .normal && last7.position == 15 && last7.toNextBoard == 0 && last7.nextSize == .hard)
        #expect(CatPuzzleStage(26).progress.size == .hard && CatPuzzleStage(26).progress.position == 1)
        let last11 = CatPuzzleStage(140).progress
        #expect(last11.size == .size11 && last11.position == 40 && last11.nextSize == .size12)
        let first12 = CatPuzzleStage(141).progress
        #expect(first12.size == .size12 && first12.position == 1 && first12.count == nil)
        #expect(first12.nextSize == nil && first12.toNextBoard == nil && first12.fraction == nil)
        #expect(CatPuzzleStage(500).progress.position == 360)
    }

    @Test("文言: 7×7 の 3 面目は「7×7：3 / 15 面」「次の盤（8×8）まであと 12 面」")
    func texts() {
        let p = CatPuzzleStage(13).progress
        #expect(p.fraction == 3.0 / 15.0)
        #expect(CatPuzzleStageProgressText.position(p) == "7×7：3 / 15 面")
        #expect(CatPuzzleStageProgressText.nextBoard(p) == "次の盤（8×8）まであと 12 面")
        #expect(CatPuzzleStageProgressText.nextBoard(CatPuzzleStage(150).progress) == nil)
        #expect(CatPuzzleStageProgressText.position(CatPuzzleStage(150).progress) == "12×12：10 面目")
        #expect(CatPuzzleStageProgressText.nextBoard(CatPuzzleStage(25).progress) == "次の面から 8×8")
        #expect(CatPuzzleStageProgressText.advanced(to: .hard) == "8×8 に進んだ！")
    }

    @Test("鍵の面までの数: 前後と、鍵の面そのもの")
    func keyDistance() {
        #expect(CatPuzzleStage(9).progress.toKey == 0 && !CatPuzzleStage(9).progress.isKey)
        #expect(CatPuzzleStageProgressText.key(CatPuzzleStage(9).progress) == "次は鍵の面")
        #expect(CatPuzzleStage(10).progress.isKey)
        #expect(CatPuzzleStageProgressText.key(CatPuzzleStage(10).progress) == "鍵の面")
        #expect(CatPuzzleStage(11).progress.toKey == 8)
        #expect(CatPuzzleStageProgressText.key(CatPuzzleStage(11).progress) == "鍵の面まであと 8 面")
        #expect(CatPuzzleStage(1).progress.toKey == 8)
    }

    @Test("盤が切り替わる面（2 面目以降の盤の最初）だけ演出の対象")
    func entersNewBoard() {
        let entering = (1...500).filter { CatPuzzleStage($0).entersNewBoard }
        #expect(entering == [11, 26, 46, 71, 101, 141])
    }

    @Test("「次のステージへ」で盤が切り替わる面に入ったときだけ boardAdvance が立つ")
    func boardAdvanceFlag() async {
        let defaults = UserDefaults(suiteName: "asobiba.catpuzzle.progress.tests")!
        defaults.removePersistentDomain(forName: "asobiba.catpuzzle.progress.tests")
        let model = CatPuzzleModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()),
                                   stageDefaults: defaults)
        model.startStage(10)
        await model.stagePreparation?.value
        #expect(model.boardAdvance == nil, "開始シートや再開では立てない")
        if let key = model.keyCat { model.findCat(cell: key) }
        for cell in model.puzzle.solutionCells where model.marks[cell] != .cat { model.findCat(cell: cell) }
        #expect(model.isSolved)
        model.startStage(11)
        await model.stagePreparation?.value
        #expect(model.boardAdvance == .normal)
        model.clearBoardAdvance()
        #expect(model.boardAdvance == nil)
    }
}
