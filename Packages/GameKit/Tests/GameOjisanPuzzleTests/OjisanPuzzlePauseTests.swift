import Testing
import Foundation
import Core
import GameKitTestSupport
@testable import GameOjisanPuzzle

/// 一時停止ボタン（#2135）。止めているあいだは落下・せり上がり・経過時間が進まず、盤の操作も受けない。
@Suite("おじさんの荷物運びパズルの一時停止")
@MainActor
struct OjisanPuzzlePauseTests {
    private func makeModel() -> OjisanPuzzleModel {
        OjisanPuzzleModel(services: nil, mode: .backpain, seed: 42)
    }

    @Test("一時停止中は resume() を呼んでも落下・せり上がり・時間が進まない")
    func pausedByUserDoesNotAdvance() async throws {
        let model = makeModel()
        model.resume()
        model.pauseByUser()
        #expect(model.isUserPaused)
        let before = (model.elapsedMilliseconds, model.millisecondsUntilRise, model.current)
        // 遊び方・確認ダイアログ・前面復帰が閉じたときの再開を模す。
        model.resume()
        try await Task.sleep(for: .milliseconds(model.dropInterval + 400))
        #expect(model.elapsedMilliseconds == before.0)
        #expect(model.millisecondsUntilRise == before.1)
        #expect(model.current == before.2)
    }

    @Test("再開すると続きから進む")
    func resumeFromUserPauseAdvances() async throws {
        let model = makeModel()
        model.pauseByUser()
        model.resumeFromUserPause()
        #expect(!model.isUserPaused)
        try await Task.sleep(for: .milliseconds(model.dropInterval + 400))
        model.pause()
        #expect(model.elapsedMilliseconds > 0)
    }

    @Test("一時停止中は操作を受けない")
    func pausedIgnoresInput() {
        let model = makeModel()
        model.pauseByUser()
        let before = model.current
        #expect(!model.move(by: 1))
        #expect(!model.rotate(clockwise: true))
        #expect(!model.softDrop())
        #expect(!model.hardDrop())
        #expect(model.current == before)
    }

    @Test("はじめから（newGame）で一時停止は解ける")
    func newGameClearsUserPause() {
        let model = makeModel()
        model.pauseByUser()
        model.newGame()
        #expect(!model.isUserPaused)
    }

    @Test("画面は一時停止ボタンと覆いを持ち、一時停止中はドラッグを受けない")
    func viewWiring() throws {
        let code = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameOjisanPuzzle/OjisanPuzzleView.swift"))
        #expect(code.contains("BoardGameControlMetrics.minTapTarget"), "押せる領域は 44pt（#1887）")
        #expect(code.contains("model.pauseByUser()") && code.contains("model.resumeFromUserPause()"))
        #expect(code.contains("!model.isUserPaused"), "一時停止中は盤のジェスチャを受けない")
        #expect(code.contains("pausedOverlay"))
    }

    @Test("一時停止中は盤と「つぎ」の荷物を描かない（会長指示 2026-10-12）")
    func pausedHidesLuggage() {
        let model = makeModel()
        // 盤に荷物がある状態を作る（組を 1 つ固定する）。
        model.hardDrop()
        #expect(model.displayBoard.joined().contains { $0 != 0 })
        #expect(!OjisanPuzzleView.hidesLuggage(isUserPaused: model.isUserPaused, outcome: model.outcome))
        model.pauseByUser()
        let hides = OjisanPuzzleView.hidesLuggage(isUserPaused: model.isUserPaused, outcome: model.outcome)
        #expect(hides)
        let board = OjisanPuzzleView.visibleBoard(model.displayBoard, hidesLuggage: hides)
        #expect(board == OjisanPuzzleBoard.emptyBoard(), "盤は空のマスだけ（大きさはそのまま）")
        let next = OjisanPuzzleView.visibleNextKinds(child: model.next.childKind, axis: model.next.axisKind,
                                                     hidesLuggage: hides)
        #expect(OjisanPuzzleLuggage.kind(next.child) == nil && OjisanPuzzleLuggage.kind(next.axis) == nil)
        // 再開すれば元どおり見える。
        model.resumeFromUserPause()
        model.pause()
        let shown = OjisanPuzzleView.hidesLuggage(isUserPaused: model.isUserPaused, outcome: model.outcome)
        #expect(!shown)
        #expect(OjisanPuzzleView.visibleBoard(model.displayBoard, hidesLuggage: shown) == model.displayBoard)
        // 決着後は隠さない（結果を見せる）。
        #expect(!OjisanPuzzleView.hidesLuggage(isUserPaused: true, outcome: .buried))
    }

    @Test("画面は盤と「つぎ」の両方を隠す分岐を通して描く")
    func viewDrawsThroughHidingBranch() throws {
        let code = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameOjisanPuzzle/OjisanPuzzleView.swift"))
        #expect(code.contains("Self.visibleBoard(model.displayBoard, hidesLuggage: hidesLuggage)"))
        #expect(code.contains("Self.visibleNextKinds(child: model.next.childKind"))
        // 隠す分岐を通らずに荷物を直接描いていない。
        #expect(code.components(separatedBy: "model.displayBoard").count == 2, "盤の中身は隠す分岐を通す 1 か所だけで読む")
        #expect(!code.contains("Self.luggage(model.next."), "「つぎ」を直接描かない")
    }
}
