import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// ねこさがしの効果音（#3239）。再生の入口は触覚と同じ `FeedbackService`（スパイで差し替える）。
@Suite("おじさんちのねこさがしの効果音")
@MainActor
struct CatPuzzleSoundTests {

    private let sample = CatPuzzle(
        side: 4,
        rooms: [0, 0, 1, 1, 0, 0, 1, 1, 2, 2, 3, 1, 2, 2, 3, 3],
        solution: [1, 3, 0, 2]
    )

    private func makeModel(_ feedback: SpyFeedbackService) -> CatPuzzleModel {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: feedback)
        return CatPuzzleModel(services: services, puzzle: sample, size: .easy)
    }

    @Test("猫を見つけると鳴き声。続けて見つけたときは違う鳴き声を順に鳴らす")
    func foundCatsRotateMeows() {
        let feedback = SpyFeedbackService()
        let model = makeModel(feedback)
        model.findCat(cell: 1)
        model.findCat(cell: 7)
        model.findCat(cell: 8)
        #expect(feedback.impacts == [.cat(.meowA), .cat(.meowB), .cat(.meowC)])
    }

    @Test("間違えると（まだ続けられるミスは）ミスの音")
    func missPlaysMissSound() {
        let feedback = SpyFeedbackService()
        let model = makeModel(feedback)
        model.findCat(cell: 0)
        #expect(feedback.impacts == [.cat(.miss)])
        #expect(feedback.notices.isEmpty)
    }

    @Test("最後の猫を見つけるとクリアの音（鳴き声は重ねない）")
    func clearPlaysClearSound() {
        let feedback = SpyFeedbackService()
        let model = makeModel(feedback)
        for cell in [1, 7, 8, 14] { model.findCat(cell: cell) }
        #expect(model.isSolved)
        #expect(feedback.impacts == [.cat(.meowA), .cat(.meowB), .cat(.meowC), .cat(.clear)])
    }

    @Test("× を付ける・外すは今までどおりの軽い触覚で、ねこさがし専用の音は鳴らさない")
    func crossStaysLight() {
        let feedback = SpyFeedbackService()
        let model = makeModel(feedback)
        #expect(model.toggleCross(cell: 0))
        #expect(model.toggleCross(cell: 0))
        #expect(feedback.impacts == [.light, .light])
    }

    @Test("設定がオフなら、ねこさがしの音は下位サービスへ届かない")
    func disabledSettingSilences() {
        let spy = SpyFeedbackService()
        var enabled = false
        let gated = GatedFeedbackService(base: spy, isEnabled: { enabled })
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: gated)
        let model = CatPuzzleModel(services: services, puzzle: sample, size: .easy)
        model.findCat(cell: 1)
        #expect(spy.impacts.isEmpty)
        enabled = true
        model.findCat(cell: 7)
        #expect(spy.impacts == [.cat(.meowB)], "オフの間も鳴き声の順番は進む（オンに戻したら続きから）")
    }

    @Test("音は 0.5 秒以内（クリアだけ鳴き声つきで 1 秒前後）、ピークは割れない範囲", arguments: CatSound.allCases)
    func shape(sound: CatSound) {
        let limit: Double = sound == .clear ? 1.1 : 0.5
        #expect(sound.duration > 0.1 && sound.duration <= limit, "\(sound) の長さ \(sound.duration)")
        let peak = sound.samples.map { abs($0) }.max() ?? 0
        #expect(peak > 0.3 && peak < 1.0, "\(sound) のピーク \(peak)")
    }

    @Test("合成は毎回同じ波形で、WAV として読める大きさ")
    func deterministic() {
        for sound in CatSound.allCases {
            #expect(sound.samples == sound.samples)
            #expect(sound.wavData.count > 44)
        }
    }
}
