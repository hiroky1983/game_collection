import SwiftUI
import Core

public struct ConcentrationView: View {
    @State private var model: ConcentrationModel
    private let services: GameServices
    @State private var showNewGame = false
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: ConcentrationModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 10) {
            statusBar
            cardGrid
            Spacer(minLength: 4)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .popBackground()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        #endif
        .tint(Theme.purple)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Label("戻る", systemImage: "chevron.left") }
            }
            ToolbarItem(placement: .principal) {
                Text("神経衰弱")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showNewGame = true } label: {
                    Label("新規", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showNewGame) {
            ConcentrationNewGameSheet(
                pairCount: model.pairCount,
                cpuLevel: model.cpuLevel
            ) { pairs, level in
                model.newGame(pairCount: pairs, cpuLevel: level)
                showNewGame = false
            } onCancel: { showNewGame = false }
        }
        .overlay {
            if model.isGameOver {
                resultOverlay
            }
        }
        .task(id: model.turnID) {
            await model.performCPUMoveIfNeeded()
        }
        .onChange(of: model.mismatchedIndices) { _, new in
            guard !new.isEmpty, model.isHumanTurn else { return }
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                model.clearMismatch()
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            scoreChip(label: "あなた", score: model.playerScore,
                      color: Theme.teal, isActive: model.isHumanTurn && !model.isGameOver)
            Spacer()
            if model.isThinking {
                ProgressView().controlSize(.small)
            }
            Spacer()
            scoreChip(label: "CPU", score: model.cpuScore,
                      color: Theme.coral, isActive: !model.isHumanTurn && !model.isGameOver)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private func scoreChip(label: String, score: Int, color: Color, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? .white : Theme.inkSub)
            Text("\(score)")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(isActive ? .white : Theme.ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(isActive ? color : Theme.surface))
    }

    // MARK: - Card Grid

    private var cardGrid: some View {
        let cols = model.pairCount == .small ? 4 : 6
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: cols)

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(model.cards) { card in
                    CardView(
                        card: card,
                        isLastMatched: model.lastMatchedIndices.contains(card.id),
                        isMismatched: model.mismatchedIndices.contains(card.id)
                    )
                    .onTapGesture {
                        guard model.isHumanTurn, model.mismatchedIndices.isEmpty else { return }
                        model.tap(index: card.id)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Result Overlay

    private var resultOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 16) {
                Group {
                    if let winner = model.winner {
                        let isWin = winner == .human
                        Image(systemName: isWin ? "trophy.fill" : "flag.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(isWin ? Theme.yellow : Theme.coral)
                        Text(isWin ? "あなたの勝ち！" : "CPUの勝ち")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(isWin ? Theme.teal : Theme.coral)
                    } else {
                        Image(systemName: "equal.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(Theme.inkSub)
                        Text("引き分け")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.inkSub)
                    }
                }

                HStack(spacing: 20) {
                    VStack {
                        Text("あなた").font(Theme.body(13)).foregroundStyle(Theme.inkSub)
                        Text("\(model.playerScore)").font(Theme.title(36)).foregroundStyle(Theme.teal)
                    }
                    Text("–").font(Theme.title(24)).foregroundStyle(Theme.inkSub)
                    VStack {
                        Text("CPU").font(Theme.body(13)).foregroundStyle(Theme.inkSub)
                        Text("\(model.cpuScore)").font(Theme.title(36)).foregroundStyle(Theme.coral)
                    }
                }

                VStack(spacing: 10) {
                    Button { showNewGame = true } label: {
                        Text("もう一度")
                            .font(Theme.body(16))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.purple)

                    Button {
                        Task {
                            await services.ads.showInterstitial()
                            model.newGame(pairCount: model.pairCount, cpuLevel: model.cpuLevel)
                        }
                    } label: {
                        Label("広告を見てもう1回", systemImage: "play.rectangle.fill")
                            .font(Theme.body(14))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.yellow)
                }
                .padding(.horizontal, 24)
            }
            .padding(28)
            .popCard()
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Card View

private struct CardView: View {
    let card: ConcentrationCard
    let isLastMatched: Bool
    let isMismatched: Bool

    private var isFaceUp: Bool { card.isFaceUp || card.isMatched }

    var body: some View {
        ZStack {
            if isFaceUp {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(card.isMatched ? Theme.teal.opacity(0.15) : Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isLastMatched ? Theme.teal :
                                isMismatched ? Theme.coral :
                                Color.clear,
                                lineWidth: 2
                            )
                    )
                Text(card.symbol)
                    .font(.system(size: 28))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.purple, Theme.purple.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "questionmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .aspectRatio(0.75, contentMode: .fit)
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isFaceUp)
        .opacity(card.isMatched ? 0.6 : 1.0)
    }
}

// MARK: - New Game Sheet

struct ConcentrationNewGameSheet: View {
    @State private var selectedPairCount: ConcentrationPairCount
    @State private var selectedCPULevel: ConcentrationCPULevel
    let onStart: (ConcentrationPairCount, ConcentrationCPULevel) -> Void
    let onCancel: () -> Void

    init(pairCount: ConcentrationPairCount,
         cpuLevel: ConcentrationCPULevel,
         onStart: @escaping (ConcentrationPairCount, ConcentrationCPULevel) -> Void,
         onCancel: @escaping () -> Void) {
        _selectedPairCount = State(initialValue: pairCount)
        _selectedCPULevel = State(initialValue: cpuLevel)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                settingSection("盤面サイズ") {
                    HStack(spacing: 12) {
                        ForEach(ConcentrationPairCount.allCases, id: \.rawValue) { p in
                            choiceButton(
                                title: p.displayName,
                                subtitle: p.subtitle,
                                selected: selectedPairCount == p,
                                accent: Theme.teal
                            ) { selectedPairCount = p }
                        }
                    }
                }

                settingSection("CPUの強さ") {
                    HStack(spacing: 12) {
                        ForEach(ConcentrationCPULevel.allCases, id: \.rawValue) { l in
                            choiceButton(
                                title: l.displayName,
                                subtitle: l.subtitle,
                                selected: selectedCPULevel == l,
                                accent: Theme.coral
                            ) { selectedCPULevel = l }
                        }
                    }
                }

                Spacer()

                Button { onStart(selectedPairCount, selectedCPULevel) } label: {
                    Text("ゲーム開始")
                        .font(Theme.body(18))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.purple)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("新規ゲーム")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func settingSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkSub)
            content()
        }
    }

    private func choiceButton(title: String, subtitle: String, selected: Bool,
                              accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(Theme.body(16))
                    .foregroundStyle(selected ? .white : Theme.ink)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? .white.opacity(0.85) : Theme.inkSub)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(selected ? accent : Theme.surface)
                    .shadow(color: .black.opacity(selected ? 0.15 : 0.06), radius: 6, y: 3)
            )
        }
        .buttonStyle(.plain)
    }
}
