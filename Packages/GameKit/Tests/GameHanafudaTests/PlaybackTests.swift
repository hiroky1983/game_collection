import Core
import Foundation
import Testing
@testable import GameHanafuda

@MainActor
@Suite("花札: 札の動きの台本（#3138）")
struct HanafudaPlaybackTests {

    private func startedModel(seed: UInt64) -> HanafudaModel {
        let model = HanafudaModel(cpuDelay: .zero, seed: seed)
        model.playback.isEnabled = true
        model.startMatch(options: HanafudaOptions())
        return model
    }

    /// 台本の中身がモデルの確定状態と矛盾しないこと（手番を 1 つ進めるたびに調べる）。
    private func checkScript(_ model: HanafudaModel, sourceIsHand: Bool) {
        guard let script = model.playback.script else { return }
        #expect(script.finalFieldIDs == Set(model.field.map(\.id)))
        #expect((1...2).contains(script.moves.count))
        if sourceIsHand { #expect(script.moves[0].source == .hand) }
        for move in script.moves {
            #expect(model.playback.hidden.contains(move.card.id))
            for target in move.matched { #expect(model.playback.hidden.contains(target.id)) }
            #expect(move.matched.allSatisfy { $0.month == move.card.month })
        }
        // 山札の束に足す数は、台本の中のめくる回数と一致する。
        #expect(model.playback.deckBonus == script.moves.filter { $0.source == .deck }.count)
    }

    @Test("人間の 1 手も CPU の 1 手も、確定後の状態と合った台本になる", arguments: [1, 2, 3, 4, 5, 6, 7, 8] as [UInt64])
    func scriptsMatchModel(seed: UInt64) {
        let model = startedModel(seed: seed)
        for _ in 0..<60 {
            switch model.phase {
            case .playing:
                if let selection = model.selection {
                    model.playback.reset()
                    let fromDeck = selection.source == .deck
                    model.chooseFieldCard(selection.candidates[0])
                    if fromDeck {
                        // めくり札の合わせ先を選び終えた後に動くのは、見出しに出ていためくり札 1 枚だけ。
                        #expect(model.playback.script?.moves.map(\.source) == [.reveal])
                    } else {
                        checkScript(model, sourceIsHand: true)
                    }
                } else if model.turn == .human, let card = model.humanHand.first(where: { model.canPlay($0) }) {
                    model.playback.reset()
                    model.play(card)
                    checkScript(model, sourceIsHand: true)
                } else if model.turn == .cpu {
                    model.playback.reset()
                    model.stepCPU()
                    checkScript(model, sourceIsHand: true)
                }
            case .koiKoiPrompt:
                model.declareStop()
            case .roundResult:
                model.advanceAfterRound()
            default:
                return
            }
        }
    }

    @Test("画面に出ていないとき（isEnabled = false）は台本を作らない")
    func disabledPlaybackIgnoresScripts() {
        let model = HanafudaModel(cpuDelay: .zero, seed: 3)
        model.startMatch(options: HanafudaOptions())
        if model.turn == .cpu { model.stepCPU() }
        if let card = model.humanHand.first(where: { model.canPlay($0) }) { model.play(card) }
        #expect(model.playback.script == nil)
        #expect(!model.playback.isBusy)
    }

    @Test("動きの途中でも reset すると表示はモデルの状態に戻る")
    func resetRestoresModelView() {
        let model = startedModel(seed: 4)
        if model.turn == .cpu { model.stepCPU() }
        if let card = model.humanHand.first(where: { model.canPlay($0) }) { model.play(card) }
        model.playback.reset()
        #expect(model.playback.script == nil)
        #expect(model.playback.hidden.isEmpty)
        #expect(model.playback.extraField.isEmpty)
        #expect(model.playback.flying.isEmpty)
        #expect(model.playback.deckBonus == 0)
    }

    @Test("新しい局を配ると動きは捨てられる")
    func startRoundDiscardsPlayback() {
        let model = startedModel(seed: 5)
        if model.turn == .cpu { model.stepCPU() }
        if let card = model.humanHand.first(where: { model.canPlay($0) }) { model.play(card) }
        model.startRound()
        #expect(!model.playback.isBusy)
    }
}
