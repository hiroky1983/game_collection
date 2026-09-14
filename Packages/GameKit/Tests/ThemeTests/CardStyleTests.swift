import Testing
import Foundation
import Core
import GameKitTestSupport

/// カード面の共通質感（#366）を数値で固定する。
///
/// 4ゲーム（ポーカー・ブラックジャック・大富豪・神経衰弱）が同じ定数を使うため、
/// ここが崩れると全カードゲームの見た目が一度に変わる。#366 の描き分けの原則
/// 「平面の駒は明度差の控えめな縦グラデーション」をテストとして残す。
struct CardStyleTests {

    /// 表は「真っ白 → わずかに沈む」方向のみ。逆転すると面が上向きに反って見える。
    /// 明度差そのものも小さく留める（大きいと紙ではなく曲面に見える）。
    @Test("表面のグラデーションは下端がわずかに暗い")
    func faceGradientDarkensSlightly() {
        let top = WCAG.relativeLuminance(CardStyle.faceTop)
        let bottom = WCAG.relativeLuminance(CardStyle.faceBottom)
        #expect(bottom < top)
        // 平面に見える範囲の差に収める（輝度比 1.25 倍以内）。
        #expect(top / bottom < 1.25)
    }

    /// 裏も上端 → 下端へ暗くする方向のみ（オセロの盤 #366 と同じ規則）。
    @Test("裏面のグラデーションは下端が暗い")
    func backGradientDarkens() {
        let top = WCAG.relativeLuminance(CardStyle.backTop)
        let bottom = WCAG.relativeLuminance(CardStyle.backBottom)
        #expect(bottom < top)
    }

    /// 裏面の内枠とモチーフは「見えるが主張しない」帯に収める。
    @Test("裏面の内枠とモチーフの不透明度は控えめな可視域にある")
    func backOrnamentsStaySubtle() {
        for opacity in [CardStyle.backFrameOpacity, CardStyle.backMotifOpacity] {
            #expect(opacity > 0.2)  // 薄すぎて見えない
            #expect(opacity < 0.6)  // 濃すぎて表より目立つ
        }
    }
}
