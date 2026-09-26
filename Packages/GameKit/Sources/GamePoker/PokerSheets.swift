import SwiftUI
import Core

// MARK: - Start Sheet

struct PokerStartSheet: View {
    @Binding var rules: PokerRuleSet
    let onStart: () -> Void
    /// キャンセル（ハブへ戻る）。これが無いと開いたら 1 局遊ぶしかなかった（#1371。麻雀は #352 で対応済み）。
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // ボーナスルールを選ぶと節が2つ増えるので、文字を大きくしても押し出されない
                // ようにスクロールさせる（開始ボタンは下に固定したまま・#189 と同じ考え方）。
                ScrollView {
                    VStack(spacing: 20) { sections }
                }
                Button {
                    onStart()
                } label: {
                    Text("ゲーム開始").themeBody(18).frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("5カードドロー")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var sections: some View {
        Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ルール")
                        .themeBody(15).foregroundStyle(Theme.inkSub)
                    // 他ゲームの開始シート（麻雀の対局の長さ・チャリおじのモードなど）と同じ
                    // 大きめのタイルに揃える（会長指摘・2026-09-23。`.pickerStyle(.segmented)` は
                    // 他より一回り小さく見えた）。
                    HStack(spacing: 12) {
                        ForEach(PokerRuleSet.allCases) { rule in
                            GameSetupChooser(
                                title: rule.title, subtitle: "",
                                selected: rules == rule, accent: Theme.Fill.coral
                            ) { rules = rule }
                        }
                    }
                    Text(rules.summary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3))

                VStack(alignment: .leading, spacing: 8) {
                    Text("ゲームの流れ")
                        .themeBody(15).foregroundStyle(Theme.inkSub)
                    ruleRow("1", "アンティ 10枚 → 手札5枚配布")
                    ruleRow("2", "ベット（チェック or 20枚ベット）")
                    ruleRow("3", "カード交換（0〜5枚）")
                    ruleRow("4", "最終ベット → 勝負")
                    if rules == .bonus {
                        ruleRow("5", "勝負に勝つと役ボーナス → ダブルアップに挑戦")
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3))

                NavigationLink {
                    HandGuideSheet()
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("役一覧を見る")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkSub)
                    }
                    .foregroundStyle(Theme.coral)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 3))
                }

                if rules == .bonus {
                    NavigationLink {
                        BonusTableSheet()
                    } label: {
                        HStack {
                            Image(systemName: "list.number")
                            Text("役ボーナス配当表を見る")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.inkSub)
                        }
                        .foregroundStyle(Theme.coral)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                            .shadow(color: .black.opacity(0.06), radius: 6, y: 3))
                    }
                }

        }
    }

    private func ruleRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.Fill.coral))
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
    }
}

// MARK: - Bonus Table Sheet

/// 役ボーナスの配当表（#496）。役を覚える教材を兼ねるので、金額だけでなく役の説明も添える。
struct BonusTableSheet: View {
    var body: some View {
        YakuTableSheet(title: "役ボーナス配当表") {
            YakuTableSection(
                footer: "勝って得たチップは、最大\(PokerModel.maxDoubleUpStreak)回まで「ダブルアップ」に賭けられます（1枚めくって見せ札より上か下かを当てる・同じ数字は引き直し）。"
            ) {
                Text("勝負（ショーダウン）で勝った側に、ポットとは別に配当されます。フォールド勝ちには付きません。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                ForEach(PokerBonusTable.payouts) { payout in
                    HStack(spacing: 8) {
                        Text(payout.rank.description)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.coral)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer()
                        Text("+\(payout.chips)枚")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.yellow)
                    }
                }
                HStack(spacing: 8) {
                    Text("ワンペア・ハイカード")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer()
                    Text("なし")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
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
            HandGuide("ロイヤルフラッシュ", "最強・同スーツ A K Q J 10",
                      [c(14,s), c(13,s), c(12,s), c(11,s), c(10,s)]),
            HandGuide("ストレートフラッシュ", "連続5枚の同スーツ",
                      [c(9,h), c(8,h), c(7,h), c(6,h), c(5,h)]),
            HandGuide("フォーカード", "同ランク4枚",
                      [c(14,s), c(14,h), c(14,d), c(14,cl), c(7,s)]),
            HandGuide("フルハウス", "3枚 ＋ 2枚",
                      [c(13,s), c(13,h), c(13,d), c(9,s), c(9,h)]),
            HandGuide("フラッシュ", "同スーツ5枚（順不同）",
                      [c(14,cl), c(10,cl), c(7,cl), c(4,cl), c(2,cl)]),
            HandGuide("ストレート", "連続5枚（スーツ混在）",
                      [c(9,s), c(8,h), c(7,d), c(6,cl), c(5,s)]),
            HandGuide("スリーカード", "同ランク3枚",
                      [c(8,s), c(8,h), c(8,d), c(4,cl), c(2,s)]),
            HandGuide("ツーペア", "ペア2組",
                      [c(13,s), c(13,h), c(9,d), c(9,cl), c(5,s)]),
            HandGuide("ワンペア", "ペア1組",
                      [c(11,s), c(11,h), c(8,d), c(4,cl), c(2,s)]),
            HandGuide("ハイカード", "役なし・最高位カードで比較",
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

struct MiniCardView: View {
    let card: PokerCard

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
            VStack(spacing: 0) {
                Text(card.rankLabel)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                Text(card.suit.symbol)
                    .font(.system(size: 14))
            }
            .foregroundStyle(card.suit.isRed ? Color(hex: 0xC0392B) : Color(hex: 0x1A1A1A))
        }
        .frame(width: 38, height: 54)
    }
}
