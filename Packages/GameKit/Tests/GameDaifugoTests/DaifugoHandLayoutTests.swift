import Testing
import SwiftUI
import Core
@testable import GameDaifugo

/// 手札のタップ標的が 44pt（Apple HIG の最小）を割らないことを固定する（#195）。
///
/// 手札は `GridItem(.flexible())` の7列なので、実効幅は端末の画面幅で決まる。
/// 「シミュレータで見たら足りていた」では**最小構成の端末で割る**ことを防げないため、
/// 寸法の計算そのものをテストで押さえる。
@Suite("大富豪: 手札のタップ標的")
struct DaifugoHandLayoutTests {

    /// 検証する画面幅。iOS 17 の対応端末で最も狭いのは 375pt（iPhone SE 第2/第3世代・iPhone 8）。
    private static let screenWidths: [(name: String, width: CGFloat)] = [
        ("iPhone SE (375pt)", 375),
        ("iPhone 15 (393pt)", 393),
        ("iPhone 15 Pro Max (430pt)", 430),
    ]

    @Test("対応する最小の端末幅でもタップ判定が 44pt 以上ある")
    func tapTargetMeetsMinimumOnAllWidths() {
        for (name, width) in Self.screenWidths {
            let tap = DaifugoHandLayout.tapWidth(screenWidth: width)
            #expect(
                tap >= DaifugoHandLayout.minimumTapTarget,
                "\(name) でタップ判定が \(tap)pt しかなく 44pt を下回る"
            )
        }
    }

    @Test("タップ判定は見た目のカード幅以上（カードがはみ出して切れない）")
    func tapTargetIsWiderThanCard() {
        let cardWidth = DaifugoCardView.Size.small.width
        for (name, width) in Self.screenWidths {
            let tap = DaifugoHandLayout.tapWidth(screenWidth: width)
            #expect(tap >= cardWidth, "\(name) で列幅 \(tap)pt がカード幅 \(cardWidth)pt より狭い")
        }
    }

    @Test("カードの高さが縦方向の最小タップ標的を満たす")
    func cardHeightMeetsMinimum() {
        #expect(DaifugoCardView.Size.small.height >= DaifugoHandLayout.minimumTapTarget)
    }

    @Test("寸法の前提（7列・カード幅42pt）が変わったら気付けるようにする")
    func layoutConstants() {
        #expect(DaifugoHandLayout.columns == 7)
        #expect(DaifugoCardView.Size.small.width == 42)
        #expect(DaifugoHandLayout.minimumTapTarget == 44)
    }
}
