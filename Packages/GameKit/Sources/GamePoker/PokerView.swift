import SwiftUI
import Core

public struct PokerView: View {
    @State private var model: PokerModel
    private let services: GameServices
    @State private var showStartSheet = true
    /// 開始シートで最後に選んだ勝負の形。「もう一度」で同じ形を始め直す（#2860）。
    @State private var lastFormat: PokerSessionFormat = .tenRounds
    @Environment(\.dismiss) private var dismiss
    @State private var revealCPU = false
    /// 広告の「もう 1 回交換」の段取り（連打ガード・失敗アラート。#526・#2551）。
    @State private var exchangeRescue = RewardedRescue()
    @State private var showPointsTable = false
    /// 結果の演出（めくり・役名）が終わるまで「次の勝負へ」を押せなくする（#2701）。
    @State private var nextLocked = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 初回だけ出す遊び方ヒントを出すか（#118）。**この画面では判定を自前で持つ**（#650）。
    /// 下の `body` は `ViewThatFits` で同じ列を2回組み立てるため、init で「見せた」を消費する
    /// `HowToPlayHint(_:playLog:)` を使うと 2 つめが false を受け取り、あとから選ばれた枝で
    /// ヒントが消える。判定はここで 1 回だけ行い、結果を渡す。
    @State private var showsHowToPlayHint: Bool
    /// 画面の広さ（#458）。iPad で縦の余白をどう配るかにだけ使う（#485）。
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        // Reduce Motion が ON なら手札は即座に表になるので、勝敗の触覚も待たせない（#667）。
        self.init(services: services, model: PokerModel(
            services: services,
            showdownRevealDelay: Motion.isReduceMotionEnabled ? .zero : PokerMotion.showdownRevealDelay
        ))
    }

    /// 局面を作ってから画面に渡す口（静止画・プレビュー用。決着の画は中断データからは戻せないため）。
    init(services: GameServices, model restored: PokerModel) {
        self.services = services
        _model = State(initialValue: restored)
        // 10 回勝負の途中から戻ったときだけ開始シートを飛ばす。旧ルールの頃の中断データは
        // モデルが読み飛ばして消しているので、ここでは `.idle` になる（#2551）。
        _showStartSheet = State(initialValue: restored.phase == .idle)
        _lastFormat = State(initialValue: restored.format)
        // 回の決着の画から戻ったときは、CPU の手札を表のまま出す（返す演出はその場で見たときだけ）。
        _revealCPU = State(initialValue: restored.phase == .result)
        _showsHowToPlayHint = State(
            initialValue: services.playLog?.markGuideShown(for: "poker") ?? false
        )
    }

    public var body: some View {
        // 背の高い局面（10 回勝負の決着）は縦が足りず、`VStack` 1 枚では溢れたぶんが上下に
        // 切り落とされていた（#650）。**収まるあいだは縦並びをそのまま使い、収まらないときだけ
        // スクロールに落とす**。`ViewThatFits` は選んだ側しか画面に置かない。
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
        .rewardOffer(exchangeRescue, for: .undo, isPresented: model.canUseExtraExchange,
                     services: services, gameID: model.gameID)
        // 点数表は「役を覚える教材」を兼ねるので、対局中に1タップで開ける場所に置く（#496）。
        // レイアウトパターン A（全画面・会長 QA 2026-10-23・#2531）: ブラックジャックと同じく、フェルトを画面全体に敷き、
        // ヘッダーは 1 行（戻る・ポーカー・点数表・？）、バナーは画面最下部。CPU・役・あなた・操作欄の白い札はやめて
        // フェルトに直に置く。勝負の帯（何回目・連勝・合計点）はブラックジャックと同じくヘッダーの下に 1 行の札で残す。
        .gameChrome(title: tr("ポーカー"), review: services.review, fullScreen: .felt, ads: services.ads,
                    reference: GameChromeReference(tr("役の点数表")) { showPointsTable = true })
        // 役一覧は3行に収まらないので、遊び方シートの「くわしいルール」へ送る（#118）。
        .howToPlay(PokerHowToFigures.guide) { HandGuideSheet() }
        .sheet(isPresented: $showStartSheet) {
            PokerStartSheet(format: lastFormat) { format in
                showStartSheet = false
                revealCPU = false
                lastFormat = format
                model.startGame(format: format)
            } onCancel: {
                // 「覗いてみたけど今はやめる」の退路（#1371）。勝負は始まっていないので記録・解析の
                // イベントは何も発生しない（それらは `startGame()` だけが送る）。
                // 決着後に「遊び方を選ぶ」から開いたときは、シートを閉じるだけで決着の画に戻る（#2860）。
                showStartSheet = false
                if model.phase == .idle { dismiss() }
            }
            // スワイプで閉じると「シートだけ消えて空の卓が残る」ため引き続き無効。
            // 閉じる操作はキャンセル（ハブへ戻る）に一本化する。
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showPointsTable) {
            NavigationStack {
                PointsTableSheet()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("閉じる")) { showPointsTable = false }.fontWeight(.semibold)
                        }
                    }
            }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .result { revealCPU = true }
        }
        .task {
            #if DEBUG
            // 撮影用（#366）: 開始シートを飛ばして1回目を配る。手札5枚 + CPU の裏札が写る。
            if ProcessInfo.processInfo.arguments.contains("-pokerAutoStart") {
                showStartSheet = false
                if model.phase == .idle { model.startGame() }
            }
            // 撮影用（#2531）: `-pokerSelectExchange <枚数>` で左から n 枚を捨てる札に選ぶ（交換を選ぶところ）。
            // `-pokerAutoPlay` と併せると、その札を替えて決着する（替えた札の印 #2738 が写る）。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-pokerSelectExchange"), i + 1 < args.count, let n = Int(args[i + 1]) {
                showStartSheet = false
                if model.phase == .idle { model.startGame() }
                for card in model.playerHand.prefix(n) { model.toggleCardSelection(card) }
            }
            // 撮影用（#1754）: 開始シートを飛ばし、交換なしで勝負して 1 回目の決着の画を出す。
            if ProcessInfo.processInfo.arguments.contains("-pokerAutoPlay") {
                showStartSheet = false
                if model.phase == .idle { model.startGame() }
                model.confirmExchange()
                model.showdown()
            }
            // 撮影用（#2551）: 10 回勝負の決着の画を出す。
            if ProcessInfo.processInfo.arguments.contains("-pokerSessionOverPreview") {
                showStartSheet = false
                model.debugPlayToEnd()
            }
            // 撮影用（#2551）: 点数表だけを出す（開始シートと同時には出せないので排他にする）。
            if ProcessInfo.processInfo.arguments.contains("-pokerPointsTable") {
                showStartSheet = false
                showPointsTable = true
            }
            #endif
        }
        .rewardedRescueAlerts(
            exchangeRescue,
            notEarned: tr("もう1回の交換はできませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("もう1回の交換はできませんでした"),
                message: tr("広告を見ているあいだに次の回へ進んだため、交換は追加していません。")
            )
        )
    }

    /// 画面の縦並び本体。`ViewThatFits` の2つの枝で同じものを使うために切り出しただけ。
    private var mainColumn: some View {
        VStack(spacing: 8) {
            scoreBar
            // CPU・役・あなた・操作欄を 1 つのまとまりにして、帯の下の残りの真ん中に置く（ブラックジャック #2671 と同じ）。
            // 全画面にして縦が伸びた分を札のあいだで吸うと、真ん中が大きく空く。
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    cpuArea
                    // 1 回の勝敗を卓の中央（CPU とあなたの境目）に大きく出す（#1754）。画面全体の中央に
                    // 重ねるとあなたの手札を覆ってしまうので、中央の帯に重ねる。13pt のバッジ（`resultBadge`）は残す
                    // ——バナーは数秒で消えるので、消えたあとも手札の横で勝敗が読める。
                    // CPU の 5 枚は返り終わってから出す（先に出すと勝敗の答えを見せてから返すことになる・#667）。
                    handArea
                        .handResultOverlay(
                            model.handResult,
                            appearDelay: Motion.isReduceMotionEnabled ? .zero : PokerMotion.showdownRevealDelay
                        )
                        // 後ろに並ぶ手札より手前に描く（兄弟は並び順に重なるため、無いとバナーの下半分が隠れる）。
                        .zIndex(1)
                    playerArea
                    // 出すかどうかは `showsHowToPlayHint` が1回だけ決める（上の `body` のコメント）。
                    HowToPlayHint(.poker, isVisible: showsHowToPlayHint)
                    if model.sessionOver {
                        sessionOverView
                    } else {
                        // ボタン 1 段ぶんを取っておき上詰め（配る前・広告の交換ボタンの出入りでまとまりが動かない）。
                        actionArea
                            .frame(minHeight: PokerMetrics.actionButtonMinHeight, alignment: .top)
                    }
                }
                Spacer(minLength: 0)
            }
            RecommendationSlot(services: services, isFinished: model.sessionOver)
        }
        // 左右は全画面の枠の値（8pt）。上下はヘッダーの余白 4 とバナーの帯の余白 8 に足す分。
        .padding(.horizontal, FullScreenGameLayoutMetrics.sideInset)
        .padding(.vertical, 4)
    }

    // MARK: - Score Bar（#2551）

    /// 合計点の数値の入れ替え方。CPU の 5 枚を返す決着では、返り終わるまで動かさない（#667）。
    /// 先に転がると、めくる前に勝敗が分かってしまう。
    private var pointsAnimation: Animation {
        model.phase == .result ? PokerMotion.pointsSettle : PokerMotion.pointsChange
    }

    private var scoreBar: some View {
        HStack(spacing: 8) {
            Label(model.format == .single
                    ? tr("単発戦")
                    : tr("%1$lld回目 / %2$lld", max(model.round, 1), PokerModel.roundsPerSession),
                  systemImage: "flag.checkered")
                .themeBody(14)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Theme.ink)
            if model.showsFinalRoundMark { FinalRoundBadge() }
            Spacer()
            Label(tr("連勝 %lld", model.streak), systemImage: "flame.fill")
                .themeBody(14)
                .foregroundStyle(Theme.coralText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(tr("合計 %lld点", model.playerPoints))
                .themeBody(16, weight: .black, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.tealText)
                // 勝った回に増える。数字が瞬時に入れ替わると増えたことが分からないので転がして見せる（#206）。
                .contentTransition(.numericText(value: Double(model.playerPoints)))
                .gameAnimation(pointsAnimation, value: model.playerPoints)
                // 位置まで animate されると、画面が動く場面で数字だけが帯の外へ滑る（実測・#206）。
                .geometryGroup()
            Text(tr("CPU %lld点", model.cpuPoints))
                .themeCaption(12, weight: .semibold, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.inkSubText)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
        .finalRoundBar(model.showsFinalRoundMark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FinalRoundBar.accessibilityLabel(
            PokerAccessibility.scoreboardLabel(
                round: max(model.round, 1), playerPoints: model.playerPoints, cpuPoints: model.cpuPoints,
                streak: model.streak, format: model.format
            ),
            isFinal: model.showsFinalRoundMark
        ))
    }

    /// CPU の手札を表向きにしてよいか。`.result` に入った**次の**更新（`onChange`）で真になる。
    ///
    /// **`|| model.phase == .result` を足してはいけない**（#383）。それを足すと `.result` に
    /// 入ったその描画で既に真になり、同じ描画で新規に挿入される役名 `Text` とカードには
    /// 「変化前の値」が無いため `.gameAnimation(_:value:)` が一度も走らない。結果、
    /// 遅延フェードが効かず**カードが返る前に役名が見えて**しまう。
    private var cpuRevealed: Bool { revealCPU }

    // MARK: - CPU Area

    private var cpuArea: some View {
        VStack(spacing: 8) {
            // フェルトの上の見出し・役名は卓の上の文字色（白系）。
            CardTableInkReader { ink in
                HStack(spacing: 8) {
                    Text("CPU")
                        .themeBody(13)
                        .foregroundStyle(ink.labelSub)
                        // 役名の行が「CPU、…」と主体まで読むので、見出しは重ねて読まない（#2589）。
                        .accessibilityHidden(model.phase == .result)
                    if !model.cpuAction.isEmpty {
                        Text(model.cpuActionLabel)
                            .themeCaption(12, weight: .bold, maxScale: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.Fill.purple))
                            // 役名と同じく、5 枚が返り終わってから現れる（バッジだけ先に出ない）。
                            .opacity(cpuRevealed ? 1 : 0)
                            .gameAnimation(
                                .easeIn(duration: PokerMotion.pointsChangeDuration)
                                    .delay(PokerMotion.showdownTotalDuration),
                                value: cpuRevealed
                            )
                    }
                    Spacer()
                    if model.phase == .result {
                        Text(model.cpuHandRank.description)
                            // 主体と勝敗の印を畳んだ 1 要素で読む（#2589）。見た目は変えない。
                            .accessibilityLabel(PokerAccessibility.handRankLabel(
                                subject: tr("CPU"), rank: model.cpuHandRank, side: .cpu,
                                winner: model.winner))
                            .themeCaption(12, weight: .bold, maxScale: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(ink.label)
                            // 役名が手札より先に出ると答えを見せてから返すことになるので、
                            // 5 枚が返り終わってから薄く現れる（#206）。
                            .opacity(cpuRevealed ? 1 : 0)
                            .gameAnimation(
                                .easeIn(duration: PokerMotion.pointsChangeDuration)
                                    .delay(PokerMotion.showdownTotalDuration),
                                value: cpuRevealed
                            )
                    }
                }
                // 決着で出る「n枚交換」の札の高さを先に取っておく（出入りで札の列が動かない）。
                .frame(minHeight: Self.handHeaderMinHeight)
            }

            HStack(spacing: 8) {
                // ショーダウンでは左から順に返す（#206）。index は段差の順番にだけ使う。
                ForEach(Array(model.cpuHand.enumerated()), id: \.element.id) { index, card in
                    cpuCard(card, index: index)
                }
            }
            .shrinkToFitWidth(naturalWidth: PlayingCardMetrics.standard.scaled(by: layout.elementScale)
                .rowWidth(count: model.cpuHand.count, spacing: 8))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
    }

    /// CPU の札 1 枚。決着で替えた札には、プレイヤーの「捨てる札」と対になる枠を、返り終わってから薄く重ねる（#2594）。
    /// 枠は返る札の外に置く（回転に巻き込まない）。Reduce Motion では補間が起きず、静止した枠だけが出る。
    @ViewBuilder
    private func cpuCard(_ card: PokerCard, index: Int) -> some View {
        let exchanged = model.cpuExchangedIndices.contains(index)
        let showsMark = exchanged && model.phase == .result
        let metrics = PlayingCardMetrics.standard.scaled(by: layout.elementScale)
        ZStack {
            FlipRevealCardView(card: card, progress: cpuRevealed ? 1 : 0)
                .gameAnimation(PokerMotion.showdownFlip(index: index), value: cpuRevealed)
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .strokeBorder(Theme.purple, lineWidth: 2)
                .frame(width: metrics.width, height: metrics.height)
                .shadow(color: Theme.purple.opacity(0.6), radius: 6)
                .opacity(showsMark && cpuRevealed ? 1 : 0)
                .gameAnimation(PokerMotion.exchangedMarkAppear, value: cpuRevealed)
                .allowsHitTesting(false)
        }
        .modifier(CPUCardAccessibility(isResult: model.phase == .result, card: card, exchanged: exchanged))
    }

    // MARK: - Hand Area（#2551）

    /// 卓の中央の帯。勝負の前は「いまの役」と勝ったときの点、決着したらその回に入った点を出す。
    private var handArea: some View {
        let current = HandEvaluator.evaluate(model.playerHand).rank
        let (caption, value): (String, String) = {
            guard model.phase == .result, let winner = model.winner else {
                return (tr("いまの役・勝てば +%lld点", PokerScoreTable.points(for: current)), current.description)
            }
            switch winner {
            case .player: return (tr("あなたの勝ち"), tr("+%lld点", model.roundPoints))
            case .cpu:    return (tr("CPUの勝ち"), tr("CPUに +%lld点", model.roundPoints))
            case .tie:    return (tr("引き分け"), tr("0点"))
            }
        }()
        // 白い札はやめてフェルトに直に置く。役・点は卓の上で目立つ黄色、見出しは卓の上の文字色。
        return CardTableInkReader { ink in
            HStack {
                Spacer()
                VStack(spacing: 2) {
                    Text(caption)
                        .themeCaption(11, weight: .semibold, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(ink.labelSub)
                    Text(value)
                        .themeBody(22, weight: .black, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.Fill.yellow)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("%1$@、%2$@", caption, value))
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Player Area

    /// CPU・あなたの見出しの行の高さの下限。勝敗のバッジ（13pt + 上下 4pt）が収まる高さ。
    private static let handHeaderMinHeight: CGFloat = 26

    private var playerArea: some View {
        VStack(spacing: 8) {
            CardTableInkReader { ink in
                HStack {
                    Text(tr("あなた"))
                        .themeBody(13)
                        .foregroundStyle(ink.label)
                        .accessibilityHidden(model.phase == .result)
                    Spacer()
                    if model.phase == .exchange {
                        Text(tr("捨てるカードを選んでください"))
                            .themeCaption(11, weight: .semibold, maxScale: 1.5)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(ink.label)
                    }
                    if model.phase == .result {
                        if let w = model.winner {
                            resultBadge(w)
                                .accessibilityHidden(true)  // 役名の行が勝敗まで読む（#2589）
                        }
                        Text(model.playerHandRank.description)
                            .accessibilityLabel(PokerAccessibility.handRankLabel(
                                subject: tr("あなた"), rank: model.playerHandRank, side: .player,
                                winner: model.winner))
                            .themeCaption(12, weight: .bold, maxScale: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(ink.label)
                    }
                }
                // 決着で出る勝敗のバッジの高さを先に取っておく（出入りで札の列と操作欄が動かない）。
                .frame(minHeight: Self.handHeaderMinHeight)
            }
            HStack(spacing: 8) {
                ForEach(Array(model.playerHand.enumerated()), id: \.element.id) { index, card in
                    let isSelected = model.selectedForExchange.contains(card.id)
                    let exchanged = model.playerExchangedIndices.contains(index)
                        && (model.phase == .drawn || model.phase == .result)
                    CardView(card: card, faceUp: true, selected: isSelected)
                        .overlay { if exchanged { exchangedMark } }
                        .onTapGesture {
                            if model.phase == .exchange {
                                model.toggleCardSelection(card)
                            }
                        }
                        // カードは `onTapGesture` で組んでいるため、ボタン trait も読み上げ文も
                        // 自動では付かない（#710。大富豪の #188 と同じ形）。
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            PokerAccessibility.handCardLabel(
                                card: card, isSelected: isSelected, phase: model.phase, wasExchanged: exchanged)
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
            .shrinkToFitWidth(naturalWidth: PlayingCardMetrics.standard.scaled(by: layout.elementScale)
                .rowWidth(count: model.playerHand.count, spacing: 8))
            // 選んだ札は 10pt 下がる（`offset`）。下がったぶんを取っておき、操作欄に重ならないようにする。
            // 10 回勝負の決着は選べないうえ縦が足りない（iPhone SE）ので取らない。
            .padding(.bottom, model.sessionOver ? 0 : 10)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
    }

    /// 自分が替えた札の枠（#2704）。CPU の札（`cpuCard`）と同じ紫の枠。
    private var exchangedMark: some View {
        let metrics = PlayingCardMetrics.standard.scaled(by: layout.elementScale)
        return RoundedRectangle(cornerRadius: metrics.cornerRadius)
            .strokeBorder(Theme.purple, lineWidth: 2)
            .frame(width: metrics.width, height: metrics.height)
            .shadow(color: Theme.purple.opacity(0.6), radius: 6)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func resultBadge(_ winner: PokerWinner) -> some View {
        switch winner {
        case .player:
            Text(tr("勝ち！"))
                .themeCaption(13, weight: .black, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.Fill.teal))
        case .cpu:
            Text(tr("負け"))
                .themeCaption(13, weight: .black, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.Fill.coral))
        case .tie:
            Text(tr("引き分け"))
                .themeCaption(13, weight: .black, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
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
        case .exchange:
            exchangeView
        case .drawn:
            drawnView
        case .result:
            resultView
        }
    }

    // カード交換
    private var exchangeView: some View {
        let count = model.selectedForExchange.count
        return actionButton(count == 0 ? tr("交換しない") : tr("%lld枚を交換", count), role: .primary) {
            model.confirmExchange()
        }
    }

    // 交換のあと: そのまま勝負するか、広告を見てもう 1 回交換するか（#2551）
    private var drawnView: some View {
        HStack(spacing: 12) {
            if model.canUseExtraExchange {
                Button {
                    // 連打ガードと失敗アラートは共通側が持つ（#526）。広告と適用は
                    // `extraExchangeAfterAd()` が 1 本で受け持つ。見終えたのに回が進んでいて
                    // 適用できなかったとき（#728）は「視聴しなかった」と別のアラートを出す。
                    exchangeRescue.requestHandledByModel(withOutcome: { await model.extraExchangeAfterAd() })
                } label: {
                    Label(tr("広告でもう1回交換"), systemImage: "play.rectangle.fill")
                        .themeBody(14)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(GameButtonStyle(role: .ad, shape: .block))
                .disabled(exchangeRescue.isWatching)
                .accessibilityHint(model.format == .single
                    ? tr("1度だけ、広告を見るともう1回カードを交換できます")
                    : tr("10回のうち1度だけ、広告を見るともう1回カードを交換できます"))
            }
            actionButton(tr("勝負する"), role: .primary, disabled: exchangeRescue.isWatching) {
                model.showdown()
            }
        }
    }

    // リザルト（回の終わり）
    private var resultView: some View {
        actionButton(model.round + 1 >= PokerModel.roundsPerSession
                        ? tr("最後の勝負へ")
                        : tr("次の勝負へ（%lld回目）", model.round + 1),
                     role: .primary, disabled: nextLocked) {
            revealCPU = false
            model.nextRound()
        }
        .task {
            nextLocked = !reduceMotion
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(PokerMotion.nextButtonLockDuration))
            if !Task.isCancelled { nextLocked = false }
        }
        .onDisappear { nextLocked = true }
    }

    // 10 回勝負の決着
    private var sessionOverView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                let winner = model.sessionWinner
                let icon = winner == .player ? "trophy.fill" : winner == .tie ? "equal.circle.fill" : "xmark.octagon.fill"
                let iconColor = winner == .player ? Theme.yellowText : winner == .tie ? Theme.tealText : Theme.coralText
                let title: String = switch (model.format, winner) {
                case (.single, .player): tr("単発戦に勝ち！")
                case (.single, .tie):    tr("単発戦は引き分け")
                case (.single, _):       tr("単発戦に負け")
                case (_, .player):       tr("10回勝負に勝ち！")
                case (_, .tie):          tr("10回勝負は引き分け")
                default:                 tr("10回勝負に負け")
                }
                let titleColor = winner == .cpu ? Theme.coralText : Theme.tealText
                Image(systemName: icon)
                    .scaledFont(24)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .themeBody(16, weight: .bold, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(titleColor)
                    Text(tr("あなた %1$lld点・CPU %2$lld点", model.playerPoints, model.cpuPoints))
                        .themeCaption(12, weight: .semibold, maxScale: 1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Theme.inkSubText)
                    if model.format == .single {
                        Text(tr("あなたの役 %@", model.playerHandRank.description))
                            .themeCaption(12, weight: .semibold, maxScale: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(Theme.inkSubText)
                    } else {
                        Text(tr("この勝負の最高連勝 %lld", model.bestStreak))
                            .themeCaption(12, weight: .semibold, maxScale: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(Theme.inkSubText)
                        Text(tr("勝ち %1$lld回・いちばん強い役 %2$@",
                                model.playerWins, (model.bestRank ?? .highCard).description))
                            .themeCaption(12, weight: .semibold, maxScale: 1.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(Theme.inkSubText)
                    }
                }
                Spacer()
            }

            RecordLabel(model.recordResult)

            HStack(spacing: 12) {
                // 「遊び方を選ぶ」は開始シートを開き直す（10 回勝負と単発戦を切り替えられる・#2860）。
                actionButton(tr("遊び方を選ぶ"), role: .skip) {
                    showStartSheet = true
                }
                actionButton(model.format == .single ? tr("もう一度 単発戦") : tr("もう一度 10回勝負"), role: .primary) {
                    revealCPU = false
                    model.startGame(format: model.format)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 役割（`GameButtonRole`）で色を決める横いっぱいのボタン（#1423）。色・角丸・44pt は `GameButtonStyle` が持つ。
    private func actionButton(_ title: String, role: GameButtonRole, disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeBody(14)
                // 文字を拡大すると折り返してボタンの高さが跳ねるため、折り返さずに縮めて収める（#189）。
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
        }
        .buttonStyle(GameButtonStyle(role: role, shape: .block))
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

/// 決着で表になった CPU の札の読み上げ（#2594）。決着前は伏せた札で読むものが無いので、何も足さない。
private struct CPUCardAccessibility: ViewModifier {
    let isResult: Bool
    let card: PokerCard
    let exchanged: Bool

    func body(content: Content) -> some View {
        if isResult {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(PokerAccessibility.cpuCardLabel(card: card, wasExchanged: exchanged))
        } else {
            content
        }
    }
}
