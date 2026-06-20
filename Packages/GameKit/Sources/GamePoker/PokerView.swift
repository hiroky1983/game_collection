import SwiftUI
import Core

public struct PokerView: View {
    @State private var model: PokerModel
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss
    @State private var showStartSheet = true
    @State private var hasPlayedOnce = false
    @State private var revealCPU = false
    @State private var showHandGuide = false

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: PokerModel(services: services))
        let hasSnapshot = services.snapshots.exists(for: "poker")
        _showStartSheet = State(initialValue: !hasSnapshot)
        _hasPlayedOnce  = State(initialValue: hasSnapshot)
    }

    public var body: some View {
        VStack(spacing: 10) {
            chipsBar
            cpuArea
            potArea
            playerArea
            if model.sessionOver {
                sessionOverView
            } else {
                actionArea
            }
            Spacer(minLength: 4)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .popBackground()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        #endif
        .tint(Theme.coral)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Label("戻る", systemImage: "chevron.left") }
            }
            ToolbarItem(placement: .principal) {
                Text("ポーカー")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHandGuide = true } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
            }
        }
        .sheet(isPresented: $showHandGuide) {
            HandGuideSheet()
        }
        .sheet(isPresented: $showStartSheet) {
            PokerStartSheet {
                showStartSheet = false
                hasPlayedOnce = true
                revealCPU = false
                model.startGame()
            }
            .interactiveDismissDisabled(true)
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .result { revealCPU = true }
        }
    }

    // MARK: - Chips Bar

    private var chipsBar: some View {
        HStack {
            Label("あなた: \(model.playerChips)枚", systemImage: "person.fill")
                .font(Theme.body(14))
                .foregroundStyle(Theme.ink)
            Spacer()
            Label("CPU: \(model.cpuChips)枚", systemImage: "cpu")
                .font(Theme.body(14))
                .foregroundStyle(Theme.inkSub)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - CPU Area

    private var cpuArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("CPU")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkSub)
                if !model.cpuAction.isEmpty {
                    Text(model.cpuAction)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.purple))
                }
                Spacer()
                if model.phase == .result && !model.cpuFolded {
                    Text(model.cpuHandRank.description)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.purple)
                }
            }

            HStack(spacing: 8) {
                ForEach(model.cpuHand) { card in
                    CardView(card: card, faceUp: revealCPU || model.phase == .result)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 18).padding(.vertical, 20)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Pot Area

    private var potArea: some View {
        HStack {
            Spacer()
            HStack(spacing: 10) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color(hex: 0xF5C842).gradient)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color(hex: 0xC8980A), lineWidth: 1))
                            .offset(y: CGFloat(i) * -4)
                    }
                }
                .frame(width: 22, height: 30)

                VStack(spacing: 2) {
                    Text("ポット")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                    Text("\(model.pot)枚")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.yellow)
                }
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Pot Area

    // MARK: - Player Area

    private var playerArea: some View {
        VStack(spacing: 6) {
            HStack {
                Text("あなた")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if model.phase == .exchange {
                    Text("捨てるカードを選んでください")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.teal)
                }
                if model.phase == .result {
                    if let w = model.winner {
                        resultBadge(w)
                    }
                }
                if model.phase == .result || model.phase == .showdown {
                    Text(model.playerHandRank.description)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.teal)
                }
            }
            HStack(spacing: 8) {
                ForEach(model.playerHand) { card in
                    let isSelected = model.selectedForExchange.contains(card.id)
                    CardView(card: card, faceUp: true, selected: isSelected)
                        .onTapGesture {
                            if model.phase == .exchange {
                                model.toggleCardSelection(card)
                            }
                        }
                        .offset(y: isSelected ? 10 : 0)
                        .animation(.spring(response: 0.25), value: isSelected)
                }
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    @ViewBuilder
    private func resultBadge(_ winner: PokerWinner) -> some View {
        switch winner {
        case .player:
            Text("勝ち！")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.teal))
        case .cpu:
            Text("負け")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.coral))
        case .tie:
            Text("引き分け")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.inkSub))
        }
    }

    // MARK: - Action Area

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .dealing:
            EmptyView()
        case .betting1:
            betting1View
        case .exchange, .cpuExchange:
            exchangeView
        case .betting2:
            betting2View
        case .showdown:
            EmptyView()
        case .result:
            resultView
        }
    }

    // ベットラウンド1
    private var betting1View: some View {
        HStack(spacing: 12) {
            actionButton("チェック", color: Theme.teal) {
                model.bet1Action(.check)
            }
            actionButton("ベット \(20)枚", color: Theme.coral, disabled: model.playerChips < 20) {
                model.bet1Action(.bet(20))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // カード交換
    private var exchangeView: some View {
        HStack(spacing: 12) {
            if model.phase == .cpuExchange {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("CPUが交換中…").font(Theme.body(14)).foregroundStyle(Theme.inkSub)
                }
                .frame(maxWidth: .infinity)
            } else {
                let count = model.selectedForExchange.count
                actionButton(count == 0 ? "交換しない" : "\(count)枚を交換", color: Theme.coral) {
                    model.confirmExchange()
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // ベットラウンド2
    private var betting2View: some View {
        Group {
            if model.currentBet > 0 {
                // CPUがベット済み → コールかフォールド
                HStack(spacing: 12) {
                    actionButton("フォールド", color: Theme.inkSub) {
                        model.foldToCPUBet()
                    }
                    actionButton("コール \(model.currentBet)枚", color: Theme.coral,
                                 disabled: model.playerChips < model.currentBet) {
                        model.callCPUBet()
                    }
                }
            } else {
                HStack(spacing: 12) {
                    actionButton("フォールド", color: Theme.inkSub) {
                        model.bet2Action(.fold)
                    }
                    actionButton("チェック", color: Theme.teal) {
                        model.bet2Action(.check)
                    }
                    actionButton("ベット \(20)枚", color: Theme.coral, disabled: model.playerChips < 20) {
                        model.bet2Action(.bet(20))
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // リザルト（ラウンド終了）
    private var resultView: some View {
        actionButton("次のゲーム", color: Theme.coral) {
            revealCPU = false
            if hasPlayedOnce {
                model.startGame()
            } else {
                showStartSheet = true
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // セッション終了（チップ0）
    private var sessionOverView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                let playerWon = model.sessionWinner == .player
                Image(systemName: playerWon ? "trophy.fill" : "xmark.octagon.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(playerWon ? Theme.yellow : Theme.coral)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playerWon ? "セッション勝利！" : "セッション敗北")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(playerWon ? Theme.teal : Theme.coral)
                    Text(playerWon ? "CPUのチップが尽きました" : "あなたのチップが尽きました")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                Spacer()
            }

            if model.sessionWinner == .cpu {
                Button { model.recoverChipsAfterAd() } label: {
                    Label("広告を見てチップ回復", systemImage: "play.rectangle.fill")
                        .font(Theme.body(16)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.yellow)
            }

            Button {
                revealCPU = false
                hasPlayedOnce = false
                model.restartSession()
                showStartSheet = true
            } label: {
                Text("もう一度はじめる").font(Theme.body(16)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.coral)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private func actionButton(_ title: String, color: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(14))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(disabled ? Theme.inkSub.opacity(0.3) : color,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(disabled ? Theme.inkSub : .white)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Card View

struct CardView: View {
    let card: PokerCard
    var faceUp: Bool = true
    var selected: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(faceUp ? Color.white : Color(hex: 0x2A5298))
                .shadow(color: selected ? Theme.coral.opacity(0.6) : .black.opacity(0.15),
                        radius: selected ? 6 : 3, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? Theme.coral : Color.gray.opacity(0.2), lineWidth: selected ? 2 : 0.5)
                )

            if faceUp {
                VStack(spacing: 2) {
                    Text(card.rankLabel)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                    Text(card.suit.symbol)
                        .font(.system(size: 24))
                }
                .foregroundStyle(card.suit.isRed ? Color(hex: 0xC0392B) : Color(hex: 0x1A1A1A))
            } else {
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(width: 62, height: 90)
    }
}

// MARK: - Start Sheet

struct PokerStartSheet: View {
    let onStart: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ゲームの流れ")
                        .font(Theme.body(15)).foregroundStyle(Theme.inkSub)
                    ruleRow("1", "アンティ 10枚 → 手札5枚配布")
                    ruleRow("2", "ベット（チェック or 20枚ベット）")
                    ruleRow("3", "カード交換（0〜5枚）")
                    ruleRow("4", "最終ベット → 勝負")
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

                Spacer()
                Button {
                    onStart()
                } label: {
                    Text("ゲーム開始").font(Theme.body(18)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.coral)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("5カードドロー")
        }
        .presentationDetents([.large])
    }

    private func ruleRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.coral))
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
    }
}

// MARK: - Hand Guide Sheet

struct HandGuideSheet: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(handGuides, id: \.name) { guide in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(guide.name)
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(Theme.coral)
                            Text(guide.desc)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.inkSub)
                        }
                        HStack(spacing: 4) {
                            ForEach(guide.cards) { card in
                                MiniCardView(card: card)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2))
                }
            }
            .padding(Theme.pad)
        }
        .popBackground()
        .navigationTitle("役一覧")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
