import Testing
@testable import Core

/// 終局・クリアのカードの出現告知（#2232）。通知そのものはシミュレータ上の VoiceOver でしか確かめられないので、
/// 「1 回だけ・ラベルをそのまま渡す」判定を純関数で固定する。
@Suite("結果カードの出現告知")
struct ResultAppearanceAnnouncementTests {

    @Test("同じ表示のあいだは何度呼んでも 1 回だけ告げる")
    func postsOnlyOnce() {
        var announced = false
        var posted: [String] = []
        for _ in 0..<3 {
            ResultAppearanceAnnouncement.announceOnce(label: "あなたの勝ち", announced: &announced) { posted.append($0) }
        }
        #expect(posted == ["あなたの勝ち"])
    }

    @Test("出し直した（フラグが戻った）ときは改めて告げる")
    func postsAgainAfterReset() {
        var announced = false
        var posted: [String] = []
        ResultAppearanceAnnouncement.announceOnce(label: "A", announced: &announced) { posted.append($0) }
        announced = false
        ResultAppearanceAnnouncement.announceOnce(label: "B", announced: &announced) { posted.append($0) }
        #expect(posted == ["A", "B"])
    }
}
