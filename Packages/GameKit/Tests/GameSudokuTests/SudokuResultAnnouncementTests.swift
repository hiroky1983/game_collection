import Testing
import Core
import GameKitTestSupport
@testable import GameSudoku
import CoreTestSupport

/// #2687: 入力の結果（正解・誤答・書き換え拒否）が連番付きの結果値としてモデルに残る。
@MainActor
@Suite("ナンプレ: 入力結果の読み上げ（#2687）")
struct SudokuResultAnnouncementTests {
    private func playing() async -> SudokuModel {
        let model = SudokuModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()), seed: 2026)
        await model.newGame(difficulty: .easy)
        return model
    }

    @Test("正解は「N を入れました」")
    func correct() async {
        let model = await playing()
        let blank = (0..<81).first { model.board[$0] == 0 }!
        model.select(index: blank)
        model.enter(digit: model.solution[blank])
        #expect(model.lastResult?.text == tr("%lld を入れました", model.solution[blank]))
        #expect(model.lastResult?.seq == 1)
    }

    @Test("誤答は何回目のミスかを読み、同じ誤答の入れ直しはミスに数えず「違います」")
    func wrong() async {
        let model = await playing()
        let blank = (0..<81).first { model.board[$0] == 0 }!
        let wrong = (1...9).first { $0 != model.solution[blank] }!
        model.select(index: blank)
        model.enter(digit: wrong)
        #expect(model.lastResult?.text == tr("違います。ミス%lld回目", 1))
        model.enter(digit: wrong)
        #expect(model.lastResult?.text == tr("違います"))
        #expect(model.lastResult?.seq == 2)
        #expect(model.mistakes == 1)
    }

    @Test("出題のマスへの入力は「出題のマスです」。マス未選択では読まない")
    func givenCell() async {
        let model = await playing()
        model.enter(digit: 1)
        #expect(model.lastResult == nil)
        let givenIndex = (0..<81).first { model.given[$0] }!
        model.select(index: givenIndex)
        model.enter(digit: 1)
        model.enter(digit: 1)
        #expect(model.lastResult?.text == tr("出題のマスです"))
        #expect(model.lastResult?.seq == 2)  // 同じ文言でも連番が進む
    }
}
