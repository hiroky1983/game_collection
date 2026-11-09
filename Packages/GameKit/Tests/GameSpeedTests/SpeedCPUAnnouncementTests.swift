import Testing
import Foundation
@testable import GameSpeed

/// CPU が札を出したときの読み上げ（#3424）。出し合いが速いので View 側で間引く設計（Core の throttle）。
@MainActor
@Suite("スピード: CPU の動きの読み上げ")
struct SpeedCPUAnnouncementTests {
    @Test("文面は札と左右の台札")
    func text() {
        let card = SpeedCard(id: 4, suit: .hearts, rank: 5)
        let name = SpeedAccessibility.cardName(card)
        #expect(SpeedAccessibility.cpuPlayAnnouncement(card: card, pileIndex: 0) == "CPUが\(name)を左の台札に出しました")
        #expect(SpeedAccessibility.cpuPlayAnnouncement(card: card, pileIndex: 1) == "CPUが\(name)を右の台札に出しました")
    }

    @Test("英語の訳がある")
    func english() {
        #expect(GameSpeed.tr("CPUが%1$@を%2$@に出しました", "5 of Hearts", "left pile", language: .english)
                == "The CPU played 5 of Hearts on the left pile")
    }
}
