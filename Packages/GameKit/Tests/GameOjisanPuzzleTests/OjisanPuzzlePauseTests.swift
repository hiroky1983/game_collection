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
}
