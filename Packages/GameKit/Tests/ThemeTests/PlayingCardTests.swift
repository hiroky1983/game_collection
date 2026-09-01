import Testing
import Foundation
import SwiftUI
import Core

/// トランプ54枚の共通描画基盤（#397）を固定する。
///
/// ポーカー・ブラックジャック・大富豪（と、これから載るソリティア）が同じ定義を共有するため、
/// ここが崩れると複数のカードゲームの見た目が一度に変わる。**寸法の既存値**と
/// **ジョーカーの図案が札に収まること**を数値で残す。
struct PlayingCardTests {

    // MARK: - 表記

    @Test("ランクの表記は A / 数字 / J / Q / K")
    func rankLabels() {
        let expected: [Int: String] = [1: "A", 2: "2", 10: "10", 11: "J", 12: "Q", 13: "K"]
        for (rank, label) in expected {
            #expect(PlayingCardFigure.pip(suit: .spade, rank: rank).rankLabel == label)
        }
        #expect(PlayingCardFigure.joker.rankLabel == "JOKER")
    }

    @Test("短い表記はスート記号 + ランク")
    func shortLabels() {
        #expect(PlayingCardFigure.pip(suit: .spade, rank: 1).label == "♠A")
        #expect(PlayingCardFigure.pip(suit: .diamond, rank: 12).label == "♦Q")
        #expect(PlayingCardFigure.joker.label == "JOKER")
    }

    /// VoiceOver は記号をそのまま読ませると端末設定で読み方が変わるため、文字で持つ（#188 と同じ方針）。
    @Test("読み上げ文はスート名を日本語で持つ")
    func spokenLabels() {
        #expect(PlayingCardFigure.pip(suit: .heart, rank: 13).spokenLabel == "ハートのK")
        #expect(PlayingCardFigure.joker.spokenLabel == "ジョーカー")
        for suit in PlayingCardSuit.allCases {
            #expect(!suit.spokenName.isEmpty)
            #expect(suit.spokenName.rangeOfCharacter(from: .symbols) == nil)
        }
    }

    @Test("赤スートはハートとダイヤだけ")
    func redSuits() {
        #expect(PlayingCardSuit.allCases.filter(\.isRed) == [.heart, .diamond])
        #expect(PlayingCardSuit.allCases.map(\.symbol) == ["♠", "♥", "♦", "♣"])
    }

    // MARK: - 寸法

    /// 共通化にあたって各ゲームの札の大きさを変えていないことの証跡。
    /// ここを動かすと全カードゲームのレイアウトが同時に動く。
    @Test("寸法プリセットは各ゲームの既存値を保つ")
    func metricsPreserveExistingSizes() {
        // ポーカー・ブラックジャックの手札。
        #expect(PlayingCardMetrics.standard.width == 62)
        #expect(PlayingCardMetrics.standard.height == 90)
        #expect(PlayingCardMetrics.standard.rankFont == 22)
        #expect(PlayingCardMetrics.standard.suitFont == 24)
        #expect(PlayingCardMetrics.standard.backMotifFont == 26)
        // 大富豪の手札（`DaifugoCardView.Size.small`。タップ判定 #190 がこの幅を前提にしている）。
        #expect(PlayingCardMetrics.compact.width == 42)
        #expect(PlayingCardMetrics.compact.height == 60)
        #expect(PlayingCardMetrics.compact.rankFont == 16)
        #expect(PlayingCardMetrics.compact.suitFont == 15)
        // 大富豪の場札（`DaifugoCardView.Size.large`）。
        #expect(PlayingCardMetrics.medium.width == 56)
        #expect(PlayingCardMetrics.medium.height == 78)
        #expect(PlayingCardMetrics.medium.rankFont == 22)
        #expect(PlayingCardMetrics.medium.suitFont == 20)
    }

    /// どのプリセットもトランプの縦横比（おおよそ 1:1.4）から外れない。
    @Test("寸法プリセットは縦長のカード比率を保つ")
    func metricsStayCardShaped() {
        for metrics in [PlayingCardMetrics.standard, .compact, .medium] {
            let ratio = metrics.height / metrics.width
            #expect(ratio > 1.3)
            #expect(ratio < 1.5)
        }
    }

    // MARK: - 色

    @Test("面のインクは赤スートと黒スートで分かれる")
    func inkSplitsByColor() {
        #expect(PlayingCardInk.color(for: .heart) == PlayingCardInk.red)
        #expect(PlayingCardInk.color(for: .diamond) == PlayingCardInk.red)
        #expect(PlayingCardInk.color(for: .spade) == PlayingCardInk.black)
        #expect(PlayingCardInk.color(for: .club) == PlayingCardInk.black)
        // ジョーカーは赤黒どちらでもない差し色（一目で別物と分かること）。
        #expect(PlayingCardInk.joker != PlayingCardInk.red)
        #expect(PlayingCardInk.joker != PlayingCardInk.black)
    }

    // MARK: - ジョーカーの図案

    /// 図案が札からはみ出す（= 角丸で切れる）と、小さい札でシルエットが壊れる。
    /// 逆に小さすぎても駄目（枠の中でぽつんと点になっていないこと）。
    @Test("道化帽の図案は枠に収まりつつ枠の大半を使う")
    func jesterCapFitsAndFillsItsFrame() {
        let bounds = JesterCapGeometry.bounds
        #expect(bounds.minX >= 0)
        #expect(bounds.minY >= 0)
        #expect(bounds.maxX <= 1)
        #expect(bounds.maxY <= 1)
        #expect(bounds.width >= 0.8)
        #expect(bounds.height >= 0.8)
    }

    /// 鈴が左右対称に並んでいること（片方だけずれると帽子に見えない）。
    @Test("道化帽の鈴は左右対称に配置する")
    func jesterCapBellsAreSymmetric() {
        let bells = JesterCapGeometry.bells
        #expect(bells.count == 3)
        #expect(abs((bells[0].x + bells[2].x) / 2 - bells[1].x) < 0.001)
        #expect(abs(bells[0].y - bells[2].y) < 0.001)
        // 上の鈴がいちばん高く、左右はつばより下に垂れる（真上に3本立てると王冠に見える）。
        #expect(bells[1].y < bells[0].y)
        #expect(bells[0].y > JesterCapGeometry.band.maxY)
        #expect(bells[2].y > JesterCapGeometry.band.maxY)
    }

    /// とんがり帽の三角は、つばの帯の内側に収まる（帯からはみ出すと帽子に見えない）。
    @Test("とんがり帽の裾はつばの帯の内側に収まる")
    func capSitsOnTheBand() {
        #expect(JesterCapGeometry.brimLeft.x > JesterCapGeometry.band.minX)
        #expect(JesterCapGeometry.brimRight.x < JesterCapGeometry.band.maxX)
        #expect(JesterCapGeometry.apex.y < JesterCapGeometry.band.minY)
        // 頂点は左右の裾のちょうど中央。
        let mid = (JesterCapGeometry.brimLeft.x + JesterCapGeometry.brimRight.x) / 2
        #expect(abs(JesterCapGeometry.apex.x - mid) < 0.001)
    }

    /// 正規化座標で定義しているので、枠を動かしても形が変わらない。
    @Test("とんがり帽の三角は原点の平行移動に追従する")
    func capFollowsOrigin() {
        let a = JesterCapShape().path(in: CGRect(x: 0, y: 0, width: 60, height: 60)).boundingRect
        let b = JesterCapShape().path(in: CGRect(x: 20, y: 30, width: 60, height: 60)).boundingRect
        #expect(abs(b.minX - (a.minX + 20)) < 0.001)
        #expect(abs(b.minY - (a.minY + 30)) < 0.001)
        #expect(abs(b.width - a.width) < 0.001)
        #expect(abs(b.height - a.height) < 0.001)
    }
}
