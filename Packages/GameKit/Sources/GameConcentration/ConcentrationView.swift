import SwiftUI
import Core

public struct ConcentrationView: View {
    @State private var model: ConcentrationModel
    private let services: GameServices
    @State private var showNewGame = false
    @State private var showMattaConfirm = false
    @State private var showRewardNotEarned = false
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: ConcentrationModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 10) {
            statusBar
            cardGrid
            HowToPlayHint(.concentration, playLog: services.playLog)
            if !model.isGameOver {
                mattaControls
            }
            RecommendationSlot(services: services, isFinished: model.isGameOver)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .popBackground()
        .reviewRequestPrompt(services.review)
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
        .howToPlay(.concentration)
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
            // 終局はフェードで出す（#208）。オセロ（#205）と同じく `.gameAnimation` は
            // オーバーレイの ZStack にだけ置く。ここより外に置くと「待った」欄や
            // レコメンド枠の入れ替えまで animate され、決着の瞬間に盤が伸び縮みする。
            // 修飾子は1つのビューに1つだけ置くこと（入れ子にすると打ち消し合う・#199）。
            ZStack {
                if model.isGameOver {
                    resultOverlay
                        .transition(.opacity)
                }
            }
            .gameAnimation(ConcentrationMotion.resultOverlayFade, value: model.isGameOver)
        }
        .alert("待った確認", isPresented: $showMattaConfirm) {
            Button(model.mattaUsed ? "広告を見て戻す" : "戻す（無料）") {
                Task {
                    if model.mattaUsed {
                        // 視聴完了（報酬獲得）したときだけ待ったを許可する
                        guard await services.ads.showRewardedAd() else {
                            showRewardNotEarned = true
                            model.resumeAutoTurn()
                            return
                        }
                    }
                    model.useMatta()
                }
            }
            Button("キャンセル", role: .cancel) { model.resumeAutoTurn() }
        } message: {
            Text(model.mattaUsed
                 ? "無料の待ったは使い切りました。\n広告を視聴すると1手戻せます。"
                 : "ミスマッチを取り消してもう一度選べます。\n無料で使えるのは1回だけです。")
        }
        .alert("待ったは使えませんでした", isPresented: $showRewardNotEarned) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。")
        }
        .task(id: model.turnID) {
            await model.performCPUMoveIfNeeded()
        }
        // CPUのミスマッチは doCPUTurn が自前でクリアするため onChange 不要
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
        // 手番が移ったことを色の変化で見せる（#208）。文字色（白 ↔ inkSub）も同じ値で
        // 切り替わるため、この1つで chip 全体が一緒に馴染む。
        .gameAnimation(ConcentrationMotion.turnHighlight, value: isActive)
    }

    // MARK: - Matta Controls

    private var mattaControls: some View {
        HStack {
            // 確認ダイアログを開いている間に自動でターンが移ると「戻す」が空振りするため止める
            Button {
                model.pauseAutoTurn()
                showMattaConfirm = true
            } label: {
                Label("待った", systemImage: "arrow.uturn.backward")
                    .themeBody(14)
            }
            .disabled(!model.canMatta)

            Spacer()

            // ミスマッチは自動で裏返るため「次へ」ボタンは無い（#137）。
            // 待っている間だけ「待った」が押せることをここで知らせる。
            if model.canMatta {
                Text("ミスマッチ… 待ったは今だけ")
                    .themeBody(13)
                    .foregroundStyle(Theme.coral)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Card Grid

    private var cardGrid: some View {
        let cols = model.pairCount == .small ? 4 : 6
        let rows = Int((Double(model.cards.count) / Double(cols)).rounded(.up))

        // 幅だけでカードの大きさを決めると縦に大きな空白が残る。与えられた高さも見て、
        // 余っていればカードを縦に伸ばす（伸ばしすぎて不自然にならないよう上限を設ける）。
        return GeometryReader { geo in
            let spacing = Self.gridSpacing
            let widthLimit = (geo.size.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            let heightLimit = rows > 0
                ? (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
                : widthLimit / Self.cardAspect
            // 高さが足りないときは幅を削って収める。余っているときは幅いっぱいに使う。
            let cardWidth = max(1, min(widthLimit, heightLimit * Self.cardAspect / Self.maxStretch))
            let cardHeight = max(1, min(heightLimit, cardWidth / Self.cardAspect * Self.maxStretch))
            let columns = Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: cols)

            LazyVGrid(columns: columns, spacing: spacing) {
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
                    .frame(width: cardWidth, height: cardHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// カードの基準の幅 : 高さ
    private static let cardAspect: CGFloat = 0.75
    /// 縦に余ったときにカードを引き伸ばしてよい上限（基準比に対する倍率）
    private static let maxStretch: CGFloat = 1.3
    private static let gridSpacing: CGFloat = 6

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
                        Text("あなた").themeBody(13).foregroundStyle(Theme.inkSub)
                        Text("\(model.playerScore)").themeTitle(36).foregroundStyle(Theme.teal)
                    }
                    Text("–").themeTitle(24).foregroundStyle(Theme.inkSub)
                    VStack {
                        Text("CPU").themeBody(13).foregroundStyle(Theme.inkSub)
                        Text("\(model.cpuScore)").themeTitle(36).foregroundStyle(Theme.coral)
                    }
                }

                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))

                Button { showNewGame = true } label: {
                    Text("もう一度")
                        .themeBody(16)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.purple)
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
                // 表は紙の淡い縦グラデーション（CardStyle #366）。マッチ済みのティール地は維持。
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(card.isMatched ? AnyShapeStyle(Theme.teal.opacity(0.15))
                                         : AnyShapeStyle(CardStyle.faceFill))
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
                // 裏は神経衰弱の顔である紫を保ちつつ、白の内枠で「カードの裏」に寄せる（#366）。
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.purple, Theme.purple.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                CardStyle.backFrame(cornerRadius: 10)
                Image(systemName: "questionmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        // 大きさは呼び出し側（cardGrid）が画面の空きに合わせて決める
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .gameAnimation(ConcentrationMotion.cardFlip, value: isFaceUp)
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
                        .themeBody(18)
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
        .gameSheetDetents()
    }

    private func settingSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .themeBody(15)
                .foregroundStyle(Theme.inkSub)
            content()
        }
    }

    private func choiceButton(title: String, subtitle: String, selected: Bool,
                              accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .themeBody(16)
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
