import Testing
@testable import Core

/// CPU の着手の読み上げ（#2280）。投稿そのものは VoiceOver 上でしか確かめられないので、
/// 「CPU が動かした鍵のときだけ文を返す」判定を純関数で固定する。
@Suite("CPU の着手の読み上げ判定")
struct CPUMoveAnnouncementTests {
    private let key = AITurnKey(gameSerial: 1, ply: 4)

    @Test("CPU が着手した鍵と一致するときは文を返す")
    func matchingKeyReturnsText() {
        #expect(CPUMoveAnnouncement.text(key: key, cpuMoveKey: key) { "CPUは打ちました" } == "CPUは打ちました")
    }

    @Test("人間の着手・待ったなど、CPU が動かしていない鍵では文を作りもしない")
    func otherKeyReturnsNilWithoutBuildingText() {
        var built = false
        let other = AITurnKey(gameSerial: 1, ply: 5)
        #expect(CPUMoveAnnouncement.text(key: other, cpuMoveKey: key) { built = true; return "x" } == nil)
        #expect(built == false)
    }

    @Test("新規対局（通し番号違い）では手数が同じでも鳴らさない")
    func newGameDoesNotMatch() {
        let newGame = AITurnKey(gameSerial: 2, ply: 4)
        #expect(CPUMoveAnnouncement.text(key: newGame, cpuMoveKey: key) { "x" } == nil)
    }

    @Test("CPU の着手がまだ無いときは鳴らさない")
    func noCPUMoveYet() {
        #expect(CPUMoveAnnouncement.text(key: key, cpuMoveKey: nil) { "x" } == nil)
    }
}
