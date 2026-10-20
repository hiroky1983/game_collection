import SwiftUI
import Core

// MARK: - Start Sheet

struct PokerStartSheet: View {
    let onStart: () -> Void
    /// キャンセル（ハブへ戻る）。これが無いと開いたら 1 勝負遊ぶしかなかった（#1371。麻雀は #352 で対応済み）。
    let onCancel: () -> Void

    /// 役一覧・点数表の詳細。共通枠は NavigationStack を持たないので、入れ子のシートで開く。
    private enum Detail: Identifiable {
        case handGuide, pointTable
        var id: Self { self }
    }
    @State private var detail: Detail?

    var body: some View {
        GameSetupSheet(kind: .versus, onStart: onStart, onCancel: onCancel) {
            // 遊び方を、図つきでそのまま並べる（#2044・#2268。荷物運びパズル #2132 と同じ型）。
            // カードは「？」の遊び方シートと同じ部品。
            GameSetupSection(tr("ルールの要点")) {
                let guide = PokerHowToFigures.guide
                VStack(spacing: 10) {
                    ForEach(Array(guide.items.enumerated()), id: \.offset) { _, item in
                        HowToPlayItemCard(item)
                    }
                    if !guide.notes.isEmpty { HowToPlayNotesCard(guide.notes) }
                }
            }

            detailButton(tr("役一覧を見る"), systemImage: "list.bullet.rectangle", showing: .handGuide)
            detailButton(tr("役の点数表を見る"), systemImage: "list.number", showing: .pointTable)
        }
        .sheet(item: $detail) { detail in
            NavigationStack {
                Group {
                    switch detail {
                    case .handGuide: HandGuideSheet()
                    case .pointTable: PointTableSheet()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("閉じる")) { self.detail = nil }
                    }
                }
            }
        }
    }

    private func detailButton(_ title: String, systemImage: String, showing target: Detail) -> some View {
        Button { detail = target } label: {
            HStack {
                Image(systemName: systemImage)
                Text(title)
                    .scaledFont(15, weight: .semibold, design: .rounded)
                Spacer()
                Image(systemName: "chevron.right")
                    .scaledFont(13, weight: .semibold)
                    .foregroundStyle(Theme.inkSub)
            }
            .foregroundStyle(Theme.coralText)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                .shadow(color: .black.opacity(0.06), radius: 6, y: 3))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Point Table Sheet

/// 役の点数表（#2551）。役を覚える教材を兼ねるので、点だけでなく勝負の決まり方も添える。
struct PointTableSheet: View {
    var body: some View {
        YakuTableSheet(title: tr("役の点数表")) {
            YakuTableSection(
                footer: tr("1 回の勝負は 10 回。10 回の合計点が記録になります。")
            ) {
                Text(tr("その回に勝ったとき、自分の役の点がもらえます。負け・引き分けは 0 点です。"))
                    .scaledFont(12, weight: .medium, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                ForEach(PokerPointTable.entries) { entry in
                    HStack(spacing: 8) {
                        Text(entry.rank.description)
                            .scaledFont(14, weight: .black, design: .rounded)
                            .foregroundStyle(Theme.coralText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer()
                        Text(tr("%lld点", entry.points))
                            .scaledFont(16, weight: .black, design: .rounded)
                            .foregroundStyle(Theme.yellowText)
                    }
                }
            }
        }
    }
}

// MARK: - Hand Guide Sheet

struct HandGuideSheet: View {
    var body: some View {
        RuleListSheet(rules: []) {
            ForEach(handGuides, id: \.name) { guide in
                RuleFigureCard(title: guide.name, detail: guide.desc) {
                    HStack(spacing: 4) {
                        ForEach(guide.cards) { card in
                            MiniCardView(card: card)
                        }
                    }
                    // 5 枚を 1 要素にまとめる（1 枚 2 要素 × 5 枚の読み上げを避ける）。
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(PokerAccessibility.handGuideCardsLabel(cards: guide.cards))
                }
            }
        }
    }

    private func c(_ rank: Int, _ suit: PokerSuit) -> PokerCard {
        PokerCard(id: rank * 10 + suit.rawValue, suit: suit, rank: rank)
    }

    private var handGuides: [HandGuide] {
        let s = PokerSuit.spades; let h = PokerSuit.hearts
        let d = PokerSuit.diamonds; let cl = PokerSuit.clubs
        return [
            HandGuide(tr("ロイヤルフラッシュ"), tr("最強・同スーツ A K Q J 10"),
                      [c(14,s), c(13,s), c(12,s), c(11,s), c(10,s)]),
            HandGuide(tr("ストレートフラッシュ"), tr("連続5枚の同スーツ"),
                      [c(9,h), c(8,h), c(7,h), c(6,h), c(5,h)]),
            HandGuide(tr("フォーカード"), tr("同ランク4枚"),
                      [c(14,s), c(14,h), c(14,d), c(14,cl), c(7,s)]),
            HandGuide(tr("フルハウス"), tr("3枚 ＋ 2枚"),
                      [c(13,s), c(13,h), c(13,d), c(9,s), c(9,h)]),
            HandGuide(tr("フラッシュ"), tr("同スーツ5枚（順不同）"),
                      [c(14,cl), c(10,cl), c(7,cl), c(4,cl), c(2,cl)]),
            HandGuide(tr("ストレート"), tr("連続5枚（スーツ混在）"),
                      [c(9,s), c(8,h), c(7,d), c(6,cl), c(5,s)]),
            HandGuide(tr("スリーカード"), tr("同ランク3枚"),
                      [c(8,s), c(8,h), c(8,d), c(4,cl), c(2,s)]),
            HandGuide(tr("ツーペア"), tr("ペア2組"),
                      [c(13,s), c(13,h), c(9,d), c(9,cl), c(5,s)]),
            HandGuide(tr("ワンペア"), tr("ペア1組"),
                      [c(11,s), c(11,h), c(8,d), c(4,cl), c(2,s)]),
            HandGuide(tr("ハイカード"), tr("役なし・最高位カードで比較"),
                      [c(14,s), c(10,h), c(7,d), c(4,cl), c(2,s)]),
        ]
    }

    struct HandGuide: Identifiable {
        let id = UUID()
        let name: String
        let desc: String
        let cards: [PokerCard]
        init(_ name: String, _ desc: String, _ cards: [PokerCard]) {
            self.name = name; self.desc = desc; self.cards = cards
        }
    }
}

// MARK: - Mini Card View

/// 役一覧の見本札。外形・面は手札と同じ共通部品（`PlayingCardSurface` / `PlayingCardFace`）で、
/// 寸法だけ小さい `PlayingCardMetrics` を `elementScale` で拡大する。読み上げは `HandGuideSheet` が 5 枚まとめて行う。
struct MiniCardView: View {
    let card: PokerCard

    @Environment(\.adaptiveLayout) private var layout

    private var metrics: PlayingCardMetrics {
        PlayingCardMetrics(width: 38, height: 54, cornerRadius: 5, rankFont: 13, suitFont: 14,
                           pipSpacing: 0, backMotifFont: 14)
            .scaled(by: layout.elementScale)
    }

    var body: some View {
        ZStack {
            PlayingCardSurface(
                faceUp: true,
                cornerRadius: metrics.cornerRadius,
                border: Color.gray.opacity(0.2),
                borderWidth: 0.5,
                shadowColor: .black.opacity(0.12),
                shadowRadius: 2
            )
            PlayingCardFace(figure: card.figure, metrics: metrics)
        }
        .frame(width: metrics.width, height: metrics.height)
    }
}
