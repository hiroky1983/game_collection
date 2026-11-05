import Core
import SwiftUI

/// 図入りの遊び方（#2044）でトランプ系ゲームが共通で使う小さな札。
///
/// 本番の札（各ゲームのビュー）は盤の寸法に縛られるため、図には固定寸法の簡素な札を使う。
/// 数字とスートを文字で描くだけの札で、絵札の図案までは持たない（ルールの図には要らない）。
public struct RuleMiniCard: View {
    public enum Suit: String, Sendable {
        case spade = "♠", heart = "♥", diamond = "♦", club = "♣"

        var isRed: Bool { self == .heart || self == .diamond }
    }

    private let rank: String
    private let suit: Suit?
    private let isFaceDown: Bool
    private let isHighlighted: Bool
    private let isDimmed: Bool

    /// - Parameters:
    ///   - rank: 札の数字（"A" "10" "K" "JK" など）。
    ///   - suit: スート。nil なら数字だけ（絵柄を問わない図・神経衰弱の絵柄）。
    ///   - isFaceDown: 伏せた札（裏面）にする。
    ///   - isHighlighted: 選んだ札・注目してほしい札。コーラルの枠で囲む。
    ///   - isDimmed: 使わない札・引き直す札。薄くする。
    public init(
        _ rank: String, suit: Suit? = nil, isFaceDown: Bool = false,
        isHighlighted: Bool = false, isDimmed: Bool = false
    ) {
        self.rank = rank
        self.suit = suit
        self.isFaceDown = isFaceDown
        self.isHighlighted = isHighlighted
        self.isDimmed = isDimmed
    }

    public static let width: CGFloat = 34
    public static let height: CGFloat = 48

    public var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isFaceDown ? Theme.coral : Color.white)
            if isFaceDown {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                    .padding(4)
            } else {
                VStack(spacing: -1) {
                    Text(rank)
                        .scaledFont(rank.count > 1 ? 12 : 15, weight: .black, design: .rounded, maxScale: 1.15)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let suit {
                        Text(suit.rawValue).scaledFont(15, maxScale: 1.15)
                    }
                }
                .foregroundStyle(suit?.isRed == true ? Color(hex: 0xC0392B) : Color(hex: 0x1A1A1A))
                .padding(.top, 3)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(isHighlighted ? Theme.coral : Color.gray.opacity(0.35), lineWidth: isHighlighted ? 2.5 : 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
        .opacity(isDimmed ? 0.35 : 1)
        .offset(y: isHighlighted ? -4 : 0)
    }
}

/// 札を重ねて並べた列（場札・手札）。`overlap` が大きいほど深く重なる。
public struct RuleMiniCardRow<Content: View>: View {
    private let overlap: CGFloat
    private let content: Content

    public init(overlap: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.overlap = overlap
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: -overlap) { content }
    }
}

/// 札を縦に重ねた列（場札の列）。`step` は 1 枚ぶんずらす高さで、先頭（上）の札が奥になる。
public struct RuleMiniCardColumn<Content: View>: View {
    private let step: CGFloat
    private let content: Content

    public init(step: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.step = step
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: step - RuleMiniCard.height) { content }
    }
}

/// 空いた置き場（空の列・フリーセル・組札の枠）。点線で札 1 枚ぶんの大きさ。
public struct RuleMiniSlot: View {
    private let label: String?

    public init(_ label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(Theme.inkSub.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            .frame(width: RuleMiniCard.width, height: RuleMiniCard.height)
            .overlay {
                if let label {
                    Text(label)
                        .scaledFont(11, weight: .black, design: .rounded, maxScale: 1.15)
                        .foregroundStyle(Theme.inkSubText)
                        // 英語（Empty 等）は札 1 枚の幅に収まらないことがあるので縮める（#2165）。
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, 2)
                }
            }
    }
}

/// 札を重ねずに `perRow` 枚ずつ折り返して並べる列。13 枚以上の強さの順など、重ねると数字が隠れる図に使う（#2788）。
/// 並びは左から右、上から下。
public struct RuleMiniCardWrap<Content: View>: View {
    private let count: Int
    private let perRow: Int
    private let content: (Int) -> Content

    public init(count: Int, perRow: Int, @ViewBuilder content: @escaping (Int) -> Content) {
        self.count = count
        self.perRow = max(perRow, 1)
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<((count + perRow - 1) / perRow), id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row * perRow..<min(count, (row + 1) * perRow), id: \.self) { index in
                        content(index)
                    }
                }
            }
        }
    }
}
