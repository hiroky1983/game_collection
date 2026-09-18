import SwiftUI
import Core

public struct PokerView: View {
    @State private var model: PokerModel
    private let services: GameServices
    @State private var showStartSheet = true
    @State private var hasPlayedOnce = false
    @State private var revealCPU = false
    /// チップ切れ復活のリワード広告の段取り（連打ガード・失敗アラート。#526）。
    @State private var reviveRescue = RewardedRescue()
    /// 開始シートでの選択。**次の局に使う設定**であって、進行中の局はこれを見ない（#496）。
    @State private var selectedRules: PokerRuleSet
    @State private var showBonusTable = false
    /// 初回だけ出す遊び方ヒントを出すか（#118）。**この画面では判定を自前で持つ**（#650）。
    /// 下の `body` は `ViewThatFits` で同じ列を2回組み立てるため、init で「見せた」を消費する
    /// `HowToPlayHint(_:playLog:)` を使うと 2 つめが false を受け取り、あとから選ばれた枝で
    /// ヒントが消える。判定はここで 1 回だけ行い、結果を渡す。
    @State private var showsHowToPlayHint: Bool
    /// 画面の広さ（#458）。iPad で縦の余白をどう配るかにだけ使う（#485）。
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        self.services = services
        // Reduce Motion が ON なら手札は即座に表になるので、勝敗の触覚も待たせない（#667）。
        let restored = PokerModel(
            services: services,
            showdownRevealDelay: Motion.isReduceMotionEnabled ? .zero : PokerMotion.showdownRevealDelay
        )
        _model = State(initialValue: restored)
        let hasSnapshot = services.snapshots.exists(for: "poker")
        // 復活したのに次の局を始める前で離れた中断データ（#1104）は局を持たない（`.idle`）。
        // そのまま開くと操作欄が空のまま固まるので、開始シートから次の局に入ってもらう。
        let waitsForNextRound = restored.phase == .idle
        _showStartSheet = State(initialValue: !hasSnapshot || waitsForNextRound)
        _hasPlayedOnce  = State(initialValue: hasSnapshot)
        // 中断から戻ったときは、その局に焼き込まれていたルールを選択の初期値にする。
        _selectedRules  = State(initialValue: restored.rules)
        _showsHowToPlayHint = State(
            initialValue: services.playLog?.markGuideShown(for: "poker") ?? false
        )
    }

    public var body: some View {
        // 背の高い局面（ダブルアップ・チップ切れのセッション終了）は縦が足りず、`VStack` 1 枚では
        // 溢れたぶんが上下に切り落とされていた（#650。チップ帯がナビゲーションバーの裏へ隠れ、
        // いちばん下のボタンが画面の下端で切れる）。
        //
        // **収まるあいだは今までの縦並びをそのまま使い、収まらないときだけスクロールに落とす**。
        // `ViewThatFits` は選んだ側しか画面に置かないので、収まる局面の描画は従来と一致し、
        // #485 / #640 で決めた位置が 1pt も動かない（iPhone 17 Pro Max・iPad Pro の
        // 通常の対局でピクセル一致を実測）。
        //
        // 常にスクロールに載せる形は採らない。`ScrollView` を置くと iOS 26 のナビゲーションバーが
        // 確保する安全域が 49pt → 64pt に広がり（プローブビルドで実測）、収まっている端末まで
        // 15pt 下がるため。
        ViewThatFits(in: .vertical) {
            mainColumn
            GeometryReader { geo in
                ScrollView {
                    // **幅を枠に固定する**。`ScrollView` は中身の理想幅が枠より広いとそちらを
                    // 提案してくるため、指定しないと CPU の札5枚（固定 pt で枠に収まらない）が
                    // 基準になって列全体が広がり、右端が切れて左へ寄る（実測）。
                    mainColumn
                        .frame(width: geo.size.width)
                        // 高さの下限も枠に合わせる。入れないと `Spacer` が最小のまま畳まれ、
                        // 数 pt 溢れただけの局面でも並びが base と食い違う。
                        .frame(minHeight: geo.size.height, alignment: .top)
                }
            }
        }
        .padding(Theme.pad)
        .rewardOffer(reviveRescue, for: .revival, isPresented: model.canReviveAfterBust,
                     services: services, gameID: model.gameID)
        .gameChrome(title: "ポーカー", review: services.review) {
            // 配当表は「役を覚える教材」を兼ねるので、対局中に1タップで開ける場所に置く（#496）。
            if model.rules == .bonus {
                ToolbarItem(placement: .primaryAction) {
                    Button { showBonusTable = true } label: {
                        Image(systemName: "list.number")
                    }
                    .accessibilityLabel("役ボーナス配当表")
                }
            }
        }
        // 役一覧は3行に収まらないので、遊び方シートの「くわしいルール」へ送る（#118）。
        .howToPlay(.poker) { HandGuideSheet() }
        .sheet(isPresented: $showStartSheet) {
            PokerStartSheet(rules: $selectedRules) {
                showStartSheet = false
                hasPlayedOnce = true
                revealCPU = false
                model.startGame(rules: selectedRules)
            }
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showBonusTable) {
            NavigationStack {
                BonusTableSheet()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { showBonusTable = false }.fontWeight(.semibold)
                        }
                    }
            }
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
            // 撮影用（#496）: 開始シートをボーナスルールを選んだ状態で出す。
            if ProcessInfo.processInfo.arguments.contains("-pokerBonusPreview") {
                selectedRules = .bonus
                showStartSheet = true
            }
            // 撮影用（#496）: 配当表だけを出す。開始シートと同時には出せない
            // （同じビューから2枚のシートは presented にならない）ので排他にする。
            if ProcessInfo.processInfo.arguments.contains("-pokerBonusTable") {
                showStartSheet = false
                showBonusTable = true
            }
            // 撮影・動作確認用（#499）: チップ切れのセッション終了画面を出す。
            // 中断データで「手持ち0・2巡目」を注入したうえで、タップ起点のフォールドを
            // ここから起こす（`-simulateBlackjackAction` と同型。撮った画が実行結果であることを担保する）。
            if ProcessInfo.processInfo.arguments.contains("-pokerSessionOverPreview") {
                revealCPU = true
                model.bet2Action(.fold)
            }
            // 撮影用（#496）: ダブルアップの提示まで進めた局面を出す。
            if ProcessInfo.processInfo.arguments.contains("-pokerDoubleUpPreview") {
                showStartSheet = false
                hasPlayedOnce = true
                revealCPU = true
                model.debugPresentDoubleUp()
                // さらに挑戦を始めた状態（ハイ・ローを選ぶ画面）。
                if ProcessInfo.processInfo.arguments.contains("-pokerDoubleUpPlaying") {
                    model.startDoubleUp()
                }
            }
            #endif
        }
        .rewardedRescueAlerts(
            reviveRescue,
            notEarned: "チップは回復しませんでした",
            unavailable: RewardUnavailableAlert(
                title: "チップは回復しませんでした",
                message: "広告を見ているあいだにセッションが変わったため、復活は適用していません。復活の回数は減っていません。"
            )
        )
    }

    /// 画面の縦並び本体。`ViewThatFits` の2つの枝で同じものを使うために切り出しただけで、
    /// 並びは変えていない。
    private var mainColumn: some View {
        VStack(spacing: 10) {
            chipsBar
            verticalSlack
            cpuArea
            verticalSlack
            potArea
            verticalSlack
            playerArea
            verticalSlack
            actionSlack
            // 出すかどうかは `showsHowToPlayHint` が1回だけ決める（上の `body` のコメント）。
            HowToPlayHint(.poker, isVisible: showsHowToPlayHint)
            if model.sessionOver {
                sessionOverView
            } else {
                actionArea
            }
            RecommendationSlot(services: services, isFinished: model.phase == .result || model.sessionOver)
            // iPad の余りは上の `verticalSlack` が配るので、ここには可変の余白を置かない。
            // 置くと最後の 1 つぶんが下端に固まって残る（実測 14.2%・#485）。
            if layout.isWide {
                Color.clear.frame(height: 4)
            } else {
                Spacer(minLength: 4)
            }
            BannerSlot(ads: services.ads)
        }
    }

    /// iPad で余った高さを節の間に配るための可変余白（#485）。iPhone では何も置かないので
    /// `VStack` の子の並びが変わらず、見た目は 1pt も動かない。
    @ViewBuilder
    private var verticalSlack: some View {
        if layout.isWide { Spacer(minLength: 0) }
    }

    /// 操作の節（遊び方ヒント + チェック/ベット）の上に置く可変余白（#640）。
    ///
    /// iPhone では余りが下端の `Spacer` に全部たまり、操作の列が画面の中ほどに浮いて
    /// 下だけが大きく空いていた。ここに同じ可変余白をもう 1 つ置くと余りが上下で等分され、
    /// 列が半分ぶんだけ下がる（iPhone 17 Pro Max の実測で **+99pt**）。
    /// `playerArea` 側に `.frame(maxHeight: .infinity)` を付ける手も試したが、
    /// 余りを総取りして操作の列が広告に接してしまう（実測 +185pt）ため採らない。
    ///
    /// 余りが無い端末では `Spacer` 自体は 0pt だが、`VStack(spacing: 10)` の隙間が 1 つ増えるぶん
    /// 節全体が 10pt 伸びる（iPhone SE で実測。上に 5pt / 下に 5pt 広がるだけで、広告まで収まる）。
    ///
    /// iPad は `verticalSlack` がすでに余りを節の間に配っているので何も置かない（#485 の配分を崩さない）。
    @ViewBuilder
    private var actionSlack: some View {
        if !layout.isWide { Spacer(minLength: 0) }
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

    /// ポットの数値の入れ替え方。CPU の 5 枚を返す決着（ショーダウン・プレイヤーのフォールド）では、
    /// 返り終わるまで動かさない（#667）。先に 0 へ転がると、めくる前に勝敗が分かってしまう。
    /// CPU のフォールドは相手が降りた時点で勝ちが見えているので従来どおりすぐ動かす。
    private var potAnimation: Animation {
        model.phase == .result && !model.cpuFolded ? PokerMotion.potSettle : PokerMotion.potChange
    }

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
                        // ショーダウンの決着だけは 5 枚が返り終わってから転がす（#667）。
                        .gameAnimation(potAnimation, value: model.pot)
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
                        // カードは `onTapGesture` で組んでいるため、ボタン trait も読み上げ文も
                        // 自動では付かない（#710。大富豪の #188 と同じ形）。
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            PokerAccessibility.handCardLabel(card: card, isSelected: isSelected, phase: model.phase)
                        )
                        .accessibilityHint(PokerAccessibility.handCardHint(phase: model.phase))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.toggleCardSelection(card) }
                        // 交換フェーズ以外では `toggleCardSelection` が何もしないので、
                        // 操作可能として案内しない（描画は素の図形なので見た目は変わらない）。
                        .disabled(!PokerAccessibility.acceptsSelection(phase: model.phase))
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
                    actionButton("フォールド", color: Theme.fillMuted, foreground: .white) {
                        model.foldToCPUBet()
                    }
                    actionButton("コール \(model.currentBet)枚", color: Theme.Fill.coral,
                                 disabled: model.playerChips < model.currentBet) {
                        model.callCPUBet()
                    }
                }
            } else {
                HStack(spacing: 12) {
                    actionButton("フォールド", color: Theme.fillMuted, foreground: .white) {
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
            if model.playerBonus > 0 || model.cpuBonus > 0 { bonusLine }
            if model.awaitsDoubleUp || model.doubleUp != nil { doubleUpArea }
            // ダブルアップの決着待ちの間は記録がまだ確定していない（#496）。確定してから出す。
            if !model.awaitsDoubleUp {
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
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 役ボーナスの配当を1行で伝える。
    private var bonusLine: some View {
        let isPlayer = model.playerBonus > 0
        let chips = isPlayer ? model.playerBonus : model.cpuBonus
        let who = isPlayer ? "あなた" : "CPU"
        return HStack(spacing: 6) {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(Theme.yellow)
            Text("役ボーナス \(who) +\(chips)枚")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isPlayer ? Theme.teal : Theme.inkSub)
            Spacer()
        }
    }

    // MARK: - ダブルアップ

    @ViewBuilder
    private var doubleUpArea: some View {
        if let state = model.doubleUp {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(state.isSettled ? "ダブルアップ終了" : "ダブルアップ \(state.streak)/\(PokerModel.maxDoubleUpStreak)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                    Spacer()
                    Text(state.isSettled ? "獲得 \(state.payout)枚" : "賭け金 \(state.stake)枚")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(state.isSettled && state.payout == 0 ? Theme.coral : Theme.yellow)
                }
                HStack(spacing: 12) {
                    CardView(card: state.baseCard, faceUp: true)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(Theme.inkSub)
                    if let drawn = state.drawnCard {
                        CardView(card: drawn, faceUp: true)
                    } else {
                        CardView(card: state.baseCard, faceUp: false)
                    }
                    Spacer()
                    if let result = state.result { doubleUpResultBadge(result) }
                }
                doubleUpButtons(state)
            }
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .foregroundStyle(Theme.yellow)
                    Text("獲得 \(model.pendingWinnings)枚 をダブルアップに賭けますか？")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                }
                HStack(spacing: 12) {
                    actionButton("受け取る", color: Theme.Fill.teal) { model.declineDoubleUp() }
                    actionButton("ダブルアップ", color: Theme.Fill.yellow,
                                 disabled: !model.canStartDoubleUp) {
                        model.startDoubleUp()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func doubleUpButtons(_ state: PokerDoubleUp) -> some View {
        if state.isSettled {
            EmptyView()
        } else if state.isAwaitingGuess {
            HStack(spacing: 12) {
                actionButton("ロー ↓", color: Theme.Fill.purple) { model.guessDoubleUp(.low) }
                actionButton("ハイ ↑", color: Theme.Fill.coral) { model.guessDoubleUp(.high) }
            }
        } else {
            HStack(spacing: 12) {
                actionButton("受け取る \(state.stake)枚", color: Theme.Fill.teal) {
                    model.takeDoubleUpWinnings()
                }
                actionButton(state.result == .push ? "引き直す" : "続ける", color: Theme.Fill.yellow) {
                    model.continueDoubleUp()
                }
            }
        }
    }

    @ViewBuilder
    private func doubleUpResultBadge(_ result: PokerDoubleUpResult) -> some View {
        let (text, fill): (String, Color) = switch result {
        case .success: ("当たり！", Theme.Fill.teal)
        case .failure: ("はずれ", Theme.Fill.coral)
        case .push:    ("引き分け", Theme.fillMuted)
        }
        Text(text)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(result == .push ? .white : Theme.onAccent)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(fill))
    }

    /// 復活導線の文言。回数制限を見た目にも出す（#499）。
    private var reviveButtonTitle: String {
        "広告を見て\(PokerModel.reviveChips)枚で復活（1セッションに1回）"
    }

    /// やり直しの文言。復活の枚数と並べて読めるように、こちらにも枚数を出す（#523・ブラックジャックと揃える）。
    private var restartButtonTitle: String {
        "もう一度はじめる (\(PokerModel.initialChips)枚)"
    }

    /// セッション終了の見出し下の説明。**自分が負けた回だけ**、復活を使い切ったことを書き添える
    /// （#499・ブラックジャックの `sessionOverSubtitle` と揃える）。書かないとボタンが消えるだけになり、
    /// なぜ選べないのかが画面から読み取れない。
    private var sessionOverSubtitle: String {
        switch model.sessionWinner {
        case .player: return "CPUのチップが尽きました"
        case .tie:    return "お互いのチップが尽きました"
        default:
            // 復活のほうがチップは多い（#523）ぶん、順位表に載らないことも選ぶ前に読める場所へ書く。
            return model.canReviveAfterBust
                ? "あなたのチップが尽きました。\(PokerModel.reviveChips)枚で復活すると順位表に載りません"
                : "あなたのチップが尽きました。復活はこのセッションで使いました"
        }
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
                let subtitle = sessionOverSubtitle
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

            // チップ切れ復活（#499）。麻雀のトビ復活（#338）と同じ形
            // （リザルト内のボタン・視聴完了時のみ効果・失敗は #64 統一アラート）。
            // 使い切ったセッションではボタンごと消す。
            if model.canReviveAfterBust {
                Button {
                    // 連打ガードと失敗アラートは共通側が持つ（#526）。広告と回復は
                    // `reviveAfterAd()` が 1 本で受け持つのでモデル側の形のまま。見終えたのに
                    // 適用できなかったとき（#728）は「視聴しなかった」と別のアラートを出す。
                    reviveRescue.requestHandledByModel(withOutcome: { await model.reviveAfterAd() })
                } label: {
                    // 「1セッションに1回」は VoiceOver のヒントだけでなく見た目にも出す（#352 と同じ理由。
                    // 書かないと2回目を期待して押す人が出る）。数値は `Text` 補間の桁区切りを避けて
                    // 文字列を先に組む（#484）。
                    Label(reviveButtonTitle, systemImage: "play.rectangle.fill")
                        .themeBody(16).frame(maxWidth: .infinity)
                        // 0.8 では SE で末尾が切れる（#523。ブラックジャックの撮影で実測）。
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.yellow)
                .disabled(reviveRescue.isWatching)
            }

            Button {
                revealCPU = false
                hasPlayedOnce = false
                model.restartSession()
                showStartSheet = true
            } label: {
                Text(restartButtonTitle).themeBody(16).frame(maxWidth: .infinity)
                .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
            // 復活広告のロード〜視聴中にやり直すと、見終えた広告が新しいセッションに乗る（#728）。
            .disabled(reviveRescue.isWatching)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    /// - Parameter foreground: 面（`color`）の上に載せる文字色。差し色の面には `Theme.onAccent`、
    ///   `fillMuted` のような濃い面には白を渡す（#220）。
    private func actionButton(_ title: String, color: Color, foreground: Color = Theme.onAccent,
                              disabled: Bool = false, action: @escaping () -> Void) -> some View {
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
                .foregroundStyle(disabled ? Theme.inkSub : foreground)
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
