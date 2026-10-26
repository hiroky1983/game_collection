import Foundation
import SwiftUI
import Testing
@testable import Core
import GameKitTestSupport

/// 対戦相手の席の共通部品（#2531）。いろリレー（#2369）の見せ方を大富豪と共有する。
@Suite("対戦相手の席")
struct OpponentSeatTests {

    @Test("相手 3 人のアイコンは記号も丸の色も互いに違う")
    func iconsAreDistinct() {
        let seats = [1, 2, 3]
        #expect(Set(seats.map(OpponentSeatStyle.symbol(for:))).count == seats.count)
        #expect(Set(seats.map { OpponentSeatStyle.colors(for: $0).disc }).count == seats.count)
        // 記号は丸の上で読める（非テキストの 3:1）。
        for seat in seats {
            let c = OpponentSeatStyle.colors(for: seat)
            #expect(WCAG.contrast(c.mark, c.disc) >= 3, "CPU\(seat)")
        }
    }

    @Test("丸の色はトランプの札の色（赤・黒・紙の白）と取り違えない")
    func discColorsAvoidPlayingCardInks() {
        let discs = [1, 2, 3].map { OpponentSeatStyle.colors(for: $0).disc }
        // 紙（白系）・赤（ハート・ダイヤ）には使わない。墨（CPU2）は黒いスートに近いが、記号が白で乗るので丸として見分く。
        #expect(!discs.contains(0xFFFFFF))
        #expect(!discs.contains(Theme.Hex.coral))
    }

    @Test("寸法: 狭い画面は丸 44・札 20、それ以外は丸 56・札 24（いろリレーの値）")
    func metrics() {
        #expect(OpponentSeatStyle.iconDiameter(compact: true) == 44)
        #expect(OpponentSeatStyle.iconDiameter(compact: false) == 56)
        #expect(OpponentSeatStyle.cardWidth(compact: true) == 20)
        #expect(OpponentSeatStyle.cardWidth(compact: false) == 24)
        #expect(OpponentSeatStyle.maxFanCards == 5)
        #expect(OpponentSeatStyle.fanStepRatio == 0.42)
    }

    @Test("束の幅は札の幅 + ずれ × (見せる枚数 − 1)。6 枚以上は 5 枚で止まり、0 枚でも 1 枚ぶんの幅を残す")
    func fanWidth() {
        typealias Style = OpponentSeatStyle
        // 式は #expect の外で組む（CI の swiftc が `20 + 20 * 0.42 * 2` の型推論に時間切れを起こした）。
        let three: CGFloat = 20 + 20 * 0.42 * 2
        let one = Style.fanWidth(count: 1, cardWidth: 20)
        let threeShown = Style.fanWidth(count: 3, cardWidth: 20)
        let five = Style.fanWidth(count: 5, cardWidth: 24)
        let thirteen = Style.fanWidth(count: 13, cardWidth: 24)
        let zero = Style.fanWidth(count: 0, cardWidth: 24)
        #expect(one == 20)
        #expect(abs(threeShown - three) < 0.001)
        #expect(five == thirteen)
        #expect(zero == 24)
    }

    @Test("席は 1 まとまりで読み上げ、手番は輪（黄色）で示す")
    func seatSource() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/OpponentSeat.swift"))
        #expect(source.contains(".accessibilityElement(children: .ignore)"))
        #expect(source.contains(".accessibilityLabel(accessibilityLabel)"))
        #expect(source.contains("isCurrent ? Theme.Fill.yellow"))
        #expect(source.contains(#"Text(lastAction.isEmpty ? " " : lastAction)"#), "吹き出しの高さを空でも残していない")
        #expect(source.contains("cardCount == 1 ? Theme.Fill.yellow"), "残り 1 枚の札が目立たない")
        #expect(source.contains("ink.labelSub"), "文字色を卓の上の色（cardTableInk）から取っていない")
    }

    @Test("残り枚数の英訳は Core の表にある（単数・複数）")
    func countLabelEnglish() {
        #expect(tr("残り%lld枚", 1, language: .english) == "1 card left")
        #expect(tr("残り%lld枚", 4, language: .english) == "4 cards left")
    }

    @Test("席は描ける（アイコン・束・枚数・吹き出し）")
    @MainActor
    func renders() throws {
        let seat = OpponentSeat(index: 2, diameter: 56, isCurrent: true, cardCount: 1, lastAction: "パス",
                                accessibilityLabel: "CPU2") {
            OpponentCardFan(count: 1, cardWidth: 24, cardHeight: 34) {
                PlayingCardBack(metrics: PlayingCardMetrics.compact.scaled(by: 24 / 42))
            }
        }
        .frame(width: 120)
        let renderer = ImageRenderer(content: seat)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 120)
        #expect(image.height > 56 + 34)
    }
}
