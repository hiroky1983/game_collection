import SwiftUI

// MARK: - 幅に収まらない固定 pt の行を縮める（#2496）

enum ShrinkToFitMath {
    /// 幅 0 の最初のフレームや理想幅が不明のときは縮めない（0 倍で消えるのを避ける）。
    static func scale(natural: CGFloat, available: CGFloat) -> CGFloat {
        guard natural > 0, available > 0, natural > available else { return 1 }
        return available / natural
    }
}

extension PlayingCardMetrics {
    /// 札を `count` 枚、間隔 `spacing` で横に並べたときの理想幅。
    public func rowWidth(count: Int, spacing: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return width * CGFloat(count) + spacing * CGFloat(count - 1)
    }
}

extension View {
    /// 使える幅より `naturalWidth` が広いときだけ、この行を相似に縮める。
    ///
    /// 札は固定 pt（62pt）で、手札が 5 枚を超える / iPhone SE の狭い幅では枠から横にはみ出す。
    /// 収まるときの倍率は 1（恒等）なので、収まる端末の見た目は変わらない。
    /// 行は理想幅で組んだまま中央に置いて見た目だけ縮めるので、行の高さは変わらない
    /// （縮める局面でも縦の収まりを動かさない）。
    public func shrinkToFitWidth(naturalWidth: CGFloat) -> some View {
        self
            .fixedSize()
            // 幅 0 の枠に置いて、親へは理想幅を要求しない（要求すると親の VStack ごと広がる）。
            .frame(width: 0)
            .frame(maxWidth: .infinity)
            .visualEffect { content, proxy in
                content.scaleEffect(ShrinkToFitMath.scale(natural: naturalWidth, available: proxy.size.width))
            }
    }
}
