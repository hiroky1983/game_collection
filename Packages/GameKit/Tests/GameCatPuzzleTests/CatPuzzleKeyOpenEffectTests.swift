import Testing
@testable import GameCatPuzzle

@Suite("鍵が開いた演出の進み具合（#3330）")
struct CatPuzzleKeyOpenEffectTests {
    @Test("覆いは鍵の猫に近いマスから順に消え、始まりは濃く終わりは消えている")
    func veilRipples() {
        typealias E = CatPuzzleKeyOpenEffect
        #expect(E.veilAmount(distance: 0.5, t: 0, reduceMotion: false) == 1)
        #expect(E.veilAmount(distance: 0, t: 0.3, reduceMotion: false) == 0)
        #expect(E.veilAmount(distance: 0.8, t: 0.3, reduceMotion: false) > E.veilAmount(distance: 0.1, t: 0.3, reduceMotion: false))
        #expect(E.veilAmount(distance: 1, t: 1, reduceMotion: false) == 0)
    }

    @Test("Reduce Motion では距離に依らず一様に薄れる")
    func veilFadesUniformlyWithReduceMotion() {
        typealias E = CatPuzzleKeyOpenEffect
        #expect(E.veilAmount(distance: 0.1, t: 0.3, reduceMotion: true) == E.veilAmount(distance: 0.9, t: 0.3, reduceMotion: true))
        #expect(E.veilAmount(distance: 0.5, t: 1, reduceMotion: true) == 0)
    }

    @Test("光は途中だけ膨らみ、始めと終わりでは出ない。輪は波の間だけ")
    func sparkleAndRing() {
        typealias E = CatPuzzleKeyOpenEffect
        #expect(E.sparkleAmount(t: 0) == 0 && E.sparkleAmount(t: 1) == 0)
        #expect(E.sparkleAmount(t: 0.35) > 0.9)
        #expect(E.ringProgress(t: 0.35) != nil)
        #expect(E.ringProgress(t: 0.9) == nil)
    }
}
