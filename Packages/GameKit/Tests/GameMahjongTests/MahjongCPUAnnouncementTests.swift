import Testing
import Foundation
import Core
import CoreTestSupport
import MahjongTiles
@testable import GameMahjong

/// CPU の打牌の読み上げ（#3424）。打牌は続けて来るので View 側で間引く設計（Core の throttle）。
@MainActor
@Suite("麻雀: CPU の動きの読み上げ")
struct MahjongCPUAnnouncementTests {
    @Test("文面は「誰が何を切ったか」")
    func text() {
        let tile = MahjongTile.characters(3)
        #expect(MahjongAccessibility.cpuDiscardAnnouncement(player: "CPU1", tile: tile) == "CPU1が\(tile.displayName)を切りました")
    }

    @Test("英語の訳がある")
    func english() {
        #expect(GameMahjong.tr("%1$@が%2$@を切りました", "CPU1", "3 Characters", language: .english) == "CPU1 discarded 3 Characters")
    }
}
