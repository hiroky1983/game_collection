import SwiftUI
import Core

public struct PokerView: View {
    @State private var model: PokerModel
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss
    @State private var showStartSheet = true
    @State private var revealCPU = false

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: PokerModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 10) {
            chipsBar
            cpuArea
            potArea
            playerArea
            actionArea
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
        }
        .sheet(isPresented: $showStartSheet) {
            PokerStartSheet {
                showStartSheet = false
                revealCPU = false
                model.startGame()
            }
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
        VStack(spacing: 6) {
            HStack {
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
            HStack(spacing: 6) {
                ForEach(model.cpuHand) { card in
                    CardView(card: card, faceUp: revealCPU || model.phase == .result)
                }
            }
        }
        .padding(10)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Pot Area

    private var potArea: some View {
        HStack {
            Spacer()
            VStack(spacing: 2) {
                Text("ポット")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.pot)枚")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.yellow)
            }
            Spacer()
        }
    }

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
            HStack(spacing: 6) {
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
        }
        .padding(10)
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

    // リザルト
    private var resultView: some View {
        VStack(spacing: 8) {
            if model.playerChips == 0 {
                // チップ切れ
                Button {
                    model.recoverChipsAfterAd()
                } label: {
                    Label("広告を見て500枚回復", systemImage: "play.rectangle.fill")
                        .font(Theme.body(14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.yellow, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
            Button {
                revealCPU = false
                showStartSheet = true
            } label: {
                Text("次のゲーム").font(Theme.body(16)).frame(maxWidth: .infinity)
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
                VStack(spacing: 1) {
                    Text(card.rankLabel)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                    Text(card.suit.symbol)
                        .font(.system(size: 13))
                }
                .foregroundStyle(card.suit.isRed ? Color(hex: 0xC0392B) : Color(hex: 0x1A1A1A))
            } else {
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(width: 52, height: 74)
    }
}

// MARK: - Start Sheet

struct PokerStartSheet: View {
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

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

                VStack(alignment: .leading, spacing: 8) {
                    Text("役")
                        .font(Theme.body(15)).foregroundStyle(Theme.inkSub)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(handRules, id: \.0) { name, desc in
                            HStack {
                                Text(name).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.coral)
                                Text(desc).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSub)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 3))

                Spacer()
                Button {
                    onStart()
                    dismiss()
                } label: {
                    Text("ゲーム開始").font(Theme.body(18)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.coral)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("5カードドロー")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
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

    private let handRules: [(String, String)] = [
        ("ロイヤルフラッシュ", "最強の役"),
        ("ストレートフラッシュ", "同スーツ連続"),
        ("フォーカード", "同ランク4枚"),
        ("フルハウス", "3枚＋2枚"),
        ("フラッシュ", "同スーツ5枚"),
        ("ストレート", "連続5枚"),
        ("スリーカード", "同ランク3枚"),
        ("ツーペア", "ペア2組"),
        ("ワンペア", "ペア1組"),
        ("ハイカード", "役なし"),
    ]
}
