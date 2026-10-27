import Core
import CoreObjectArt
import SwiftUI

/// 図入りの遊び方（#2044）のカードしりとりの図。文言は `HowToPlayGuide.shiritori.items` /
/// `.shiritoriEndless.items`（Core）と同じ順で、先頭（勝ち方）だけが遊び方で変わる。札は本番の `ShiritoriCardTile`。
@MainActor
enum ShiritoriHowToFigures {
    /// ノルマの版。
    static let items: [@MainActor @Sendable () -> AnyView] = [{ AnyView(QuotaFigure()) }] + common

    /// とことんの版。
    static let endlessItems: [@MainActor @Sendable () -> AnyView] = [{ AnyView(EndlessFigure()) }] + common

    private static let common: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(ChainFigure()) },
        { AnyView(TurnFigure()) },
        { AnyView(TimerFigure()) },
        { AnyView(WinLoseFigure()) },
    ]

    private static func card(_ kind: ObjectCardKind) -> ShiritoriCard {
        ShiritoriCard.deck.first { $0.kind == kind } ?? ShiritoriCard.deck[0]
    }

    /// 札 1 枚（幅を固定）。
    private struct Tile: View {
        let kind: ObjectCardKind
        var style: ShiritoriCardTile.Style = .board(owner: nil, selectable: true, isCPUCursor: false)
        var width: CGFloat = 54

        var body: some View {
            let card = ShiritoriHowToFigures.card(kind)
            ShiritoriCardTile(card: card, reading: card.primaryReading, style: style)
                .frame(width: width)
        }
    }

    /// ノルマ: 取った札が決まった枚数に届けば勝ち。
    struct QuotaFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { i in
                        Image(systemName: i < 4 ? "rectangle.portrait.fill" : "rectangle.portrait")
                            .scaledFont(20, weight: .bold, maxScale: 1.15)
                            .foregroundStyle(i < 4 ? Theme.tealText : Theme.inkSubText.opacity(0.5))
                    }
                    Image(systemName: "flag.checkered")
                        .scaledFont(20, weight: .bold, maxScale: 1.15)
                        .foregroundStyle(Theme.ink)
                }
                RuleFigureLabel(tr("取った札がノルマに届けば勝ち"), color: Theme.coralText)
            }
        }
    }

    /// とことん: 札が尽きるまで。
    struct EndlessFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(0..<8, id: \.self) { _ in
                        Image(systemName: "rectangle.portrait.fill")
                            .scaledFont(20, weight: .bold, maxScale: 1.15)
                            .foregroundStyle(Theme.tealText)
                    }
                    Image(systemName: "infinity")
                        .scaledFont(20, weight: .black, maxScale: 1.15)
                        .foregroundStyle(Theme.coralText)
                }
                RuleFigureLabel(tr("全部取りきればパーフェクト"), color: Theme.coralText)
            }
        }
    }

    /// りんご → ご で始まる ごりら を取る（らっこ は合わない）。
    struct ChainFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 4) {
                    Tile(kind: .apple, style: .current, width: 64)
                    RuleFigureLabel(tr("場の札"))
                }
                Image(systemName: "arrow.right")
                    .scaledFont(12, weight: .black, maxScale: 1.2)
                    .foregroundStyle(Theme.inkSubText)
                    .padding(.top, 30)
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Tile(kind: .gorilla, style: .board(owner: nil, selectable: true, isCPUCursor: false))
                            .overlay(alignment: .bottom) { RuleVerdictMark(true).offset(y: 12) }
                        Tile(kind: .seaOtter)
                            .overlay(alignment: .bottom) { RuleVerdictMark(false).offset(y: 12) }
                    }
                    .padding(.bottom, 12)
                    RuleFigureLabel(tr("「ご」で始まる札を取る"), color: Theme.coralText)
                }
            }
        }
    }

    /// 取った札が新しい場の札になり、CPU の番。
    struct TurnFigure: View {
        var body: some View {
            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Tile(kind: .gorilla, style: .current, width: 64)
                    RuleFigureLabel(tr("新しい場の札"))
                }
                Image(systemName: "arrow.right")
                    .scaledFont(12, weight: .black, maxScale: 1.2)
                    .foregroundStyle(Theme.inkSubText)
                VStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .scaledFont(26, weight: .bold, maxScale: 1.15)
                        .foregroundStyle(Theme.coralText)
                    RuleFigureLabel(tr("CPU の番"))
                }
            }
        }
    }

    /// 制限時間 60 秒・成立で +10 秒・おてつきで -5 秒。
    struct TimerFigure: View {
        var body: some View {
            HStack(spacing: 10) {
                chip("timer", "60", Theme.ink)
                chip("checkmark.circle.fill", "+10", Color(hex: 0x2E9D6B))
                chip("xmark.circle.fill", "-5", Theme.coralText)
            }
        }

        private func chip(_ symbol: String, _ value: String, _ color: Color) -> some View {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(verbatim: value)
            }
            .scaledFont(15, weight: .black, design: .rounded, maxScale: 1.15)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.12)))
        }
    }

    /// 続けられなくなった側の負け。
    struct WinLoseFigure: View {
        var body: some View {
            HStack(spacing: 18) {
                side(symbol: "person.fill", label: tr("あなた"), win: true)
                Text(verbatim: "vs")
                    .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.inkSubText)
                side(symbol: "cpu", label: tr("CPU が続けられない"), win: false)
            }
        }

        private func side(symbol: String, label: String, win: Bool) -> some View {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .scaledFont(24, weight: .bold, maxScale: 1.15)
                    .foregroundStyle(win ? Theme.tealText : Theme.inkSubText)
                    .overlay(alignment: .topTrailing) {
                        if win {
                            Image(systemName: "crown.fill")
                                .scaledFont(12, weight: .bold, maxScale: 1.15)
                                .foregroundStyle(Theme.yellowText)
                                .offset(x: 8, y: -8)
                        }
                    }
                RuleFigureLabel(win ? tr("勝ち") : label, color: win ? Theme.coralText : Theme.inkSubText)
            }
        }
    }
}

extension ShiritoriMode {
    /// この遊び方の図入りの遊び方。ゲーム画面ヘッダーの「？」と開始シートで同じものを使う。
    @MainActor
    var howToPlayGuide: HowToPlayGuide {
        switch self {
        case .quota: .shiritori.illustrated(ShiritoriHowToFigures.items)
        case .endless: .shiritoriEndless.illustrated(ShiritoriHowToFigures.endlessItems)
        }
    }

    /// 開始シートで常に見せる項目の位置: 勝ち方・札の取り方。
    static let setupKeyItemIndices = [0, 1]

    @MainActor
    var setupKeyItems: [HowToPlayItem] {
        let items = howToPlayGuide.items
        return Self.setupKeyItemIndices.map { items[$0] }
    }

    /// 開始シートで折りたたむ項目（番の交代・制限時間・勝ち負け）。
    @MainActor
    var setupDetailItems: [HowToPlayItem] {
        let keys = Set(Self.setupKeyItemIndices)
        return howToPlayGuide.items.enumerated().filter { !keys.contains($0.offset) }.map(\.element)
    }
}
