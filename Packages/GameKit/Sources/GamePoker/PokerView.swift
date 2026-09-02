import SwiftUI
import Core

public struct PokerView: View {
    @State private var model: PokerModel
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss
    @State private var showStartSheet = true
    @State private var hasPlayedOnce = false
    @State private var revealCPU = false
    @State private var showRewardNotEarned = false
    @State private var isRecoveringChips = false

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
            HowToPlayHint(.poker, playLog: services.playLog)
            if model.sessionOver {
                sessionOverView
            } else {
                actionArea
            }
            RecommendationSlot(services: services, isFinished: model.phase == .result || model.sessionOver)
            Spacer(minLength: 4)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .popBackground()
        .reviewRequestPrompt(services.review)
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
        // 役一覧は3行に収まらないので、遊び方シートの「くわしいルール」へ送る（#118）。
        .howToPlay(.poker) { HandGuideSheet() }
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
        .task {
            #if DEBUG
            // 撮影用（#366）: 開始シートを飛ばして1ラウンド配る。手札5枚 + CPU の裏札が写る。
            if ProcessInfo.processInfo.arguments.contains("-pokerAutoStart") {
                showStartSheet = false
                hasPlayedOnce = true
                if model.phase == .idle { model.startGame() }
            }
            #endif
        }
        .alert("チップは回復しませんでした", isPresented: $showRewardNotEarned) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。")
        }
    }

    // MARK: - Chips Bar

    private var chipsBar: some View {
        HStack {
            Label("あなた: \(model.playerChips)枚", systemImage: "person.fill")
                .themeBody(14)
                .foregroundStyle(Theme.ink)
            Spacer()
            Label("CPU: \(model.cpuChips)枚", systemImage: "cpu")
                .themeBody(14)
                .foregroundStyle(Theme.inkSub)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    /// CPU の手札を表向きにしてよいか。`.result` に入った**次の**更新（`onChange`）で真になる。
    ///
    /// **`|| model.phase == .result` を足してはいけない**（#383）。それを足すと `.result` に
    /// 入ったその描画で既に真になり、同じ描画で新規に挿入される役名 `Text` とカードには
    /// 「変化前の値」が無いため `.gameAnimation(_:value:)` が一度も走らない。結果、
    /// 遅延フェードが効かず**カードが返る前に役名が見えて**しまう。`.result` と `.showdown` は
    /// `PokerModel.persist()` の保存対象外なので、この状態で復元されることもない。
    private var cpuRevealed: Bool { revealCPU }

    // MARK: - CPU Area

    private var cpuArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("CPU")
                    .themeBody(13)
                    .foregroundStyle(Theme.inkSub)
                if !model.cpuAction.isEmpty {
                    Text(model.cpuAction)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.Fill.purple))
                }
                Spacer()
                if model.phase == .result && !model.cpuFolded {
                    Text(model.cpuHandRank.description)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.purple)
                        // 役名が手札より先に出ると答えを見せてから返すことになるので、
                        // 5 枚が返り終わってから薄く現れる（#206）。
                        .opacity(cpuRevealed ? 1 : 0)
                        .gameAnimation(
                            .easeIn(duration: PokerMotion.potChangeDuration)
                                .delay(PokerMotion.showdownTotalDuration),
                            value: cpuRevealed
                        )
                }
            }

            HStack(spacing: 8) {
                // ショーダウンでは左から順に返す（#206）。index は段差の順番にだけ使う。
                ForEach(Array(model.cpuHand.enumerated()), id: \.element.id) { index, card in
                    FlipRevealCardView(card: card, progress: cpuRevealed ? 1 : 0)
                        .gameAnimation(PokerMotion.showdownFlip(index: index), value: cpuRevealed)
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
                        // ベット・コールで増え、決着で勝者に渡って 0 に戻る。数字が瞬時に
                        // 入れ替わると増減の向きが分からないので、転がして見せる（#206）。
                        .contentTransition(.numericText(value: Double(model.pot)))
                        .gameAnimation(PokerMotion.potChange, value: model.pot)
                        // 枚数が変わるのと同時に画面全体のレイアウトが動く場面（ゲーム画面へ
                        // 入りながらアンティが積まれるなど）では、この Text だけが古い位置から
                        // 滑ってきてポットの枠の外に文字が出る。実測で確認したため、
                        // 位置は親と一体で決まるようにして数字の入れ替えだけを演出に残す。
                        .geometryGroup()
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
                    .themeBody(13)
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
                        .gameAnimation(PokerMotion.handSelection, value: isSelected)
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
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.Fill.teal))
        case .cpu:
            Text("負け")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.Fill.coral))
        case .tie:
            Text("引き分け")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.fillMuted))
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
            actionButton("チェック", color: Theme.Fill.teal) {
                model.bet1Action(.check)
            }
            actionButton("ベット \(20)枚", color: Theme.Fill.coral, disabled: model.playerChips < 20) {
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
                    Text("CPUが交換中…").themeBody(14).foregroundStyle(Theme.inkSub)
                }
                .frame(maxWidth: .infinity)
            } else {
                let count = model.selectedForExchange.count
                actionButton(count == 0 ? "交換しない" : "\(count)枚を交換", color: Theme.Fill.coral) {
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
                    actionButton("フォールド", color: Theme.fillMuted) {
                        model.foldToCPUBet()
                    }
                    actionButton("コール \(model.currentBet)枚", color: Theme.Fill.coral,
                                 disabled: model.playerChips < model.currentBet) {
                        model.callCPUBet()
                    }
                }
            } else {
                HStack(spacing: 12) {
                    actionButton("フォールド", color: Theme.fillMuted) {
                        model.bet2Action(.fold)
                    }
                    actionButton("チェック", color: Theme.Fill.teal) {
                        model.bet2Action(.check)
                    }
                    actionButton("ベット \(20)枚", color: Theme.Fill.coral, disabled: model.playerChips < 20) {
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
        VStack(spacing: 8) {
            RecordLabel(model.recordResult)
            actionButton("次のゲーム", color: Theme.Fill.coral) {
                revealCPU = false
                if hasPlayedOnce {
                    model.startGame()
                } else {
                    showStartSheet = true
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    // セッション終了（チップ0）
    private var sessionOverView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                let winner = model.sessionWinner
                let icon = winner == .player ? "trophy.fill" : winner == .tie ? "equal.circle.fill" : "xmark.octagon.fill"
                let iconColor = winner == .player ? Theme.yellow : winner == .tie ? Theme.teal : Theme.coral
                let title = winner == .player ? "セッション勝利！" : winner == .tie ? "引き分け" : "セッション敗北"
                let titleColor = winner == .player ? Theme.teal : winner == .tie ? Theme.teal : Theme.coral
                let subtitle = winner == .player ? "CPUのチップが尽きました" : winner == .tie ? "お互いのチップが尽きました" : "あなたのチップが尽きました"
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(titleColor)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                Spacer()
            }

            // チップが尽きた回は resultView ではなくこちらが出るため、記録行もここに置く。
            RecordLabel(model.recordResult)

            if model.sessionWinner == .cpu {
                Button {
                    // 広告のロード〜表示中の連打で2本目が失敗し、誤ってアラートが出るのを防ぐ
                    guard !isRecoveringChips else { return }
                    isRecoveringChips = true
                    Task {
                        if await model.recoverChipsAfterAd() == false { showRewardNotEarned = true }
                        isRecoveringChips = false
                    }
                } label: {
                    Label("広告を見てチップ回復", systemImage: "play.rectangle.fill")
                        .themeBody(16).frame(maxWidth: .infinity)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.yellow)
                .disabled(isRecoveringChips)
            }

            Button {
                revealCPU = false
                hasPlayedOnce = false
                model.restartSession()
                showStartSheet = true
            } label: {
                Text("もう一度はじめる").themeBody(16).frame(maxWidth: .infinity)
                .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private func actionButton(_ title: String, color: Color, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeBody(14)
                // 文字を拡大すると「カードを選ぶ」「コール 20枚」等が折り返して
                // ボタンの高さが跳ねるため、折り返さずに縮めて収める（#189）。
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
                // 高さは上下の余白（10pt）任せだと実測 34〜37pt で Apple HIG の 44pt に届かない（#207）。
                // 見た目のトーン（角丸・色）は変えず、下限だけを与えて背景ごと 44pt にする。
                // 文字が大きくなって 44pt を超えるぶんには従来どおり伸びる。
                .frame(maxWidth: .infinity, minHeight: PokerMetrics.actionButtonMinHeight)
                .background(disabled ? Theme.inkSub.opacity(0.3) : color,
                            in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(disabled ? Theme.inkSub : Theme.onAccent)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Flip Reveal Card View

/// 裏から表へ返る CPU の手札（#206）。
///
/// `faceUp` の切り替えに `.gameAnimation` を掛けただけでは表裏が瞬時に入れ替わるだけなので、
/// オセロの盤（#204）と同じく**このビュー自身を `Animatable`** にして進捗を補間させ、
/// 進捗の翻訳は `PokerMotion` の純関数に任せる（`PokerMotionTests` で固定できる）。
struct FlipRevealCardView: View, Animatable {
    nonisolated let card: PokerCard
    /// 0 = 裏 / 1 = 表。`.gameAnimation` が掛かっていればこの値が補間される。
    nonisolated var progress: Double

    // `View` への適合でこの型は MainActor 隔離になるが、`Animatable` の要求は nonisolated。
    // 保持しているのは値型（すべて Sendable）だけなので、格納プロパティごと nonisolated にして
    // 適合を成立させる（オセロの `OthelloBoardCanvas` と同じ）。
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let showsFace = PokerMotion.showsFace(progress: progress)
        CardView(card: card, faceUp: showsFace)
            // 後半はカードごと 90 度を越えて回っているので、表の中身が鏡像にならないよう
            // ここで 180 度打ち消す（合計 360 度で元の向きに戻る）。
            .rotation3DEffect(.degrees(showsFace ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(
                .degrees(PokerMotion.flipDegrees(progress: progress)),
                axis: (x: 0, y: 1, z: 0)
            )
    }
}

// MARK: - Card View

struct CardView: View {
    let card: PokerCard
    var faceUp: Bool = true
    var selected: Bool = false

    private let metrics = PlayingCardMetrics.standard

    var body: some View {
        ZStack {
            // 外形・面・裏はトランプ共通基盤（#397。質感は CardStyle #366）。
            PlayingCardSurface(
                faceUp: faceUp,
                cornerRadius: metrics.cornerRadius,
                border: selected ? Theme.coral : Color.gray.opacity(0.2),
                borderWidth: selected ? 2 : 0.5,
                shadowColor: selected ? Theme.coral.opacity(0.6) : .black.opacity(0.15),
                shadowRadius: selected ? 6 : 3
            )

            if faceUp {
                PlayingCardFace(figure: card.figure, metrics: metrics)
            } else {
                PlayingCardBack(metrics: metrics)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
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
                        .themeBody(15).foregroundStyle(Theme.inkSub)
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
                    Text("ゲーム開始").themeBody(18).frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
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
