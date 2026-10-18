import SwiftUI

/// 盤のマスの強調を色以外でも伝える印（#2486）。OS の「色なしで区別」がオンのときだけ、
/// 塗りの上に重ねる。オフのときは何も描かない（呼び出し側で出し分ける）。
///
/// 直前手は内枠、選択中は太い内枠と四隅の角印。両方が同じマスに乗ったときも
/// 選択中の印が上に来て区別できる。
public struct BoardCellMarks: View {
    let size: CGFloat
    let isSelected: Bool
    let isLastMove: Bool

    public init(size: CGFloat, isSelected: Bool, isLastMove: Bool) {
        self.size = size
        self.isSelected = isSelected
        self.isLastMove = isLastMove
    }

    public var body: some View {
        ZStack {
            if isLastMove {
                Rectangle().strokeBorder(Theme.coralText, lineWidth: max(2, size * 0.06))
            }
            if isSelected {
                Rectangle().strokeBorder(Theme.ink, lineWidth: max(3, size * 0.08))
                ForEach(0..<4, id: \.self) { corner in
                    Rectangle()
                        .fill(Theme.ink)
                        .frame(width: size * 0.18, height: size * 0.18)
                        .frame(width: size, height: size,
                               alignment: Self.alignments[corner])
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let alignments: [Alignment] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
}
