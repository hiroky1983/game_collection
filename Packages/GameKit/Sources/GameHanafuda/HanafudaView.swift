import Foundation
import SwiftUI
import Core

/// `.task(id:)` の鍵。手番の鍵に「止めているか」を足し、止めた・再開したの両方でタスクを起こし直す（#2827）。
private struct PausableTurn: Equatable {
    let key: AITurnKey
    let paused: Bool
}

public struct HanafudaView: View {
    @State private var model: HanafudaModel
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveLayout) private var layout
    @State private var showResignConfirm = false
    @State private var showYakuSheet = false
    /// 最終局で負けているときに広告で 1 局延長する救済（#1049）。
    @State private var extendRescue = RewardedRescue()
    /// 開始前の設定（局数・酒の役・強さ）。局が始まったら焼き込まれる（1 局 = 1 RuleSet）。
    @State private var draft = HanafudaOptions()
    /// 試合の後に「設定を変える」で設定シートを開き直しているか（#2612）。初回は `.idle` で開く。
    @State private var showChangeSettings = false
    /// 「？」（図で見る遊び方を含む）を開いているあいだ CPU の手番を止める（#2827）。
    @State private var isHowToPlayOpen = false

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: HanafudaModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            scoreBar
            // 場・手札は局の進み方で行数が変わり（最大 8 枚ずつ）、小さい画面（iPhone SE 等）では
            // 他の要素ごと画面下にはみ出ていた（会長指摘）。かといってスクロールにすると「スクロール
            // しないと見えない」に変わっただけなので、残った高さを測って札の大きさを縮め、
            // 1 画面に収める（#1254。麻雀・将棋・オセロの盤と同じ考え方）。
            GeometryReader { geo in
                if model.phase == .matchResult {
                    // 「もう一度」は結果カードのすぐ下に置き、余りの高さは広告との間に残す（#1519）。
                    // 下の操作エリアに置くと、この枠が残り高さを取るぶんボタンが広告の直上へ押し下げられて誤タップを招く。
                    // 他のゲームと同じ共通部品（同じ条件でもう一回／設定を変える・#2612）。ヘッダーの新規は付けない（投了せずに記録を抜ける経路を作らない）。
                    VStack(spacing: 8) {
                        matchResultCard
                        GameReplayBar(
                            onReplay: { model.restartMatch() },
                            onChangeSettings: {
                                draft = model.options
                                showChangeSettings = true
                            }
                        )
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                    .transition(.opacity)
                } else {
                    // 「⋯」の行は札のすぐ下に置き、余りの高さは「⋯」の行と広告のあいだに残す（#1485）。
                    // 行のぶんを先に引いてから札の大きさを決める（行を外に置いていた従来と同じ高さの配分）。
                    let showsOverflow = showsOverflowBar
                    let fit = HanafudaFit.metrics(
                        availableWidth: geo.size.width,
                        availableHeight: geo.size.height - (showsOverflow ? HanafudaFit.overflowRowHeight + HanafudaFit.sectionSpacing : 0),
                        stripHeight: layout.scaled(HanafudaFit.baseStripHeight),
                        fieldCount: model.field.count, handCount: model.humanHand.count
                    )
                    VStack(spacing: HanafudaFit.sectionSpacing) {
                        opponentArea(fit)
                        fieldArea(fit).transition(.opacity)
                        handArea(fit)
                        if showsOverflow {
                            overflowBar
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
            }
            HowToPlayHint(.hanafuda, playLog: services.playLog)
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .matchResult, ladder: ladder)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        .padding(Theme.pad)
        // 役は 12 種あり、覚えていないと打つ手が決められない。対局中 1 タップで開ける
        // 早見表を置く（#495 の仕様）。
        .gameChrome(title: tr("花札こいこい"), review: services.review,
                    reference: GameChromeReference { showYakuSheet = true })
        .howToPlay(HowToPlayGuide.hanafuda.illustrated(HanafudaHowToFigures.items).onboarding(HanafudaOnboarding.guide),
                   onPresent: { isHowToPlayOpen = true }, onDismiss: { isHowToPlayOpen = false }) { HanafudaRuleSheet() }
        .sheet(isPresented: $showYakuSheet) { HanafudaYakuSheet(options: model.options) }
        .sheet(isPresented: .constant(model.phase == .idle)) {
            HanafudaSetupSheet(draft: $draft, onStart: { model.startMatch(options: draft) }, onCancel: { dismiss() })
                .interactiveDismissDisabled()
        }
        // 試合の後の選び直し。閉じても結果カードに戻るだけ。
        .sheet(isPresented: $showChangeSettings) {
            HanafudaSetupSheet(
                draft: $draft,
                onStart: {
                    showChangeSettings = false
                    model.restartMatch(options: draft)
                },
                onCancel: { showChangeSettings = false }
            )
        }
        .dialogs { anchor in
            anchor.confirmationDialog(tr("投了しますか？"), isPresented: $showResignConfirm, titleVisibility: .visible) {
                Button(tr("投了する"), role: .destructive) { model.resign() }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("この試合を打ち切ります。負けとして記録されます。"))
            }
        }
        // 1 局延長の提示（#780 × #1049）。最終局で負けている局の結果でボタンが出ているあいだを 1 回の提示として数える。
        .rewardOffer(extendRescue, for: .continue, isPresented: model.canExtendMatch,
                     services: services, gameID: HanafudaModel.gameID)
        .rewardedRescueAlerts(
            extendRescue,
            notEarned: tr("延長できませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("延長できませんでした"),
                message: tr("広告を見ているあいだに試合が終わったため、延長できませんでした。")
            )
        )
        // 閉じたら鍵（paused）が変わって再起動し、止めていた手番の続きを回す。
        .task(id: PausableTurn(key: model.aiTurnKey, paused: isHowToPlayOpen)) {
            guard !isHowToPlayOpen else { return }
            await model.runCPUTurnIfNeeded()
        }
        // CPU の手番の締めに 1 回だけ読み上げる（#2280）。
        .cpuMoveAnnouncement(key: model.aiTurnKey, cpuMoveKey: model.lastCPUMoveKey) {
            model.lastCPUTurn.map(HanafudaSpeech.cpuTurnAnnouncement)
        }
        #if DEBUG
        // 撮影用。シミュレータはタップを自動化できないため、役の早見表はこの経路でしか撮れない
        // （中断データの注入では「シートが開いている」状態を作れない）。
        // `#if DEBUG` で囲ってあるので Release のバイナリには入らない。
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-hanafudaShowYaku") else { return }
            if model.phase == .idle { model.startMatch(options: draft) }
            showYakuSheet = true
        }
        // 試合の結果画面（#1496）。同じくタップ無しでは辿り着けない画面。
        .task {
            if ProcessInfo.processInfo.arguments.contains("-hanafudaMatchResult") {
                model.debugForceMatchResult(resigned: false)
            } else if ProcessInfo.processInfo.arguments.contains("-hanafudaMatchResultResigned") {
                model.debugForceMatchResult(resigned: true)
            }
        }
        #endif
    }

    // MARK: - 得点表示

    private var scoreBar: some View {
        VStack(spacing: 6) {
            // 手番はほかの対戦ゲームと同じく状態の帯の左に出す（#1485。以前は盤の下の行に「あなたの番」だけが残っていた）。
            GameStatusBar {
                turnBadge
            } trailing: {
                scoreChip(title: tr("あなた"), value: model.humanTotal, fill: Theme.Fill.teal)
                scoreChip(title: "CPU", value: model.cpuTotal, fill: Theme.Fill.coral)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.message)
                    .themeCaption(13, weight: .semibold, maxScale: 1.5)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                // 局数は帯から手番に場所を譲り、この行の右端へ（小さい画面で帯に収めるため）。
                if model.phase != .matchResult {
                    Text(model.round > model.options.rounds ? tr("延長戦") : tr("%1$lld / %2$lld局", model.round, model.options.rounds))
                        .themeCaption(13, weight: .bold, maxScale: 1.5)
                        .fitOneLine()
                        .foregroundStyle(Theme.inkSubText)
                }
            }
            .padding(.horizontal, GameStatusBarStyle.horizontalPadding)
        }
    }

    /// 状態の帯の手番表示。局・試合の決着のあいだは終局色で出す。
    @ViewBuilder
    private var turnBadge: some View {
        switch model.phase {
        case .idle:
            TurnBadge(tr("開始待ち"), kind: .finished)
        case .playing, .koiKoiPrompt:
            TurnBadge(isYourTurn: model.turn == .human)
        case .roundResult:
            TurnBadge(tr("局の終わり"), kind: .finished)
        case .matchResult:
            TurnBadge(tr("決着"), kind: .finished)
        }
    }

    private func scoreChip(title: String, value: Int, fill: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .themeCaption(12, weight: .bold, maxScale: 1.5)
                .fitOneLine()
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(fill))
            Text(tr("%lld文", value))
                .themeBody(16, weight: .heavy, maxScale: 1.5)
                .fitOneLine()
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("%@ %lld文", title, value))
    }

    // MARK: - 相手

    private func opponentArea(_ fit: HanafudaFit.Metrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(tr("CPUの取り札"))
                    .themeCaption(13, weight: .bold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(model.turn == .cpu ? Theme.coralText : Theme.inkSubText)
                Text(yakuLine(for: .cpu))
                    .themeCaption(13, weight: .semibold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(Theme.inkSubText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text(tr("手札%lld枚", model.cpuHand.count))
                    .themeCaption(13, weight: .semibold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(Theme.inkSubText)
            }
            capturedGroups(model.cpuCaptured, height: fit.stripHeight)
        }
        .padding(10)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("CPUの取り札。%1$@。%2$@", HanafudaSpeech.capturedSummary(model.cpuCaptured),
                                HanafudaSpeech.yakuSummary(model.yaku(of: .cpu))))
    }

    /// 取り札を 光・タネ・短・カス の 4 つの列に束ねて見せる（#2336）。
    /// 札は列の中で横に重ね、重なりの端に出る月の数字が読める間隔を保つ。見出しの「n/m」は枚数と、
    /// 基本の役（三光・タネ・タン・カス）が成り立つ枚数。高さは枚数によらず一定。
    private func capturedGroups(_ cards: [HanafudaCard], height: CGFloat) -> some View {
        let groups = HanafudaCapturedGroup.groups(of: cards)
        return GeometryReader { geo in
            let cardWidth = height / HanafudaCardArt.aspectRatio
            let widths = HanafudaFit.groupWidths(
                total: geo.size.width, cardWidth: cardWidth, counts: groups.map(\.cards.count)
            )
            HStack(alignment: .top, spacing: HanafudaFit.groupSpacing) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    capturedGroupColumn(group, width: widths[index], cardWidth: cardWidth, height: height)
                }
            }
        }
        .frame(height: HanafudaFit.groupHeaderHeight + HanafudaFit.groupHeaderSpacing + height)
    }

    private func capturedGroupColumn(_ group: HanafudaCapturedGroup, width: CGFloat,
                                     cardWidth: CGFloat, height: CGFloat) -> some View {
        let hex = HanafudaCardArt.kindHex(for: group.kind)
        let step = HanafudaFit.overlapStep(groupWidth: width, cardWidth: cardWidth, count: group.cards.count)
        return VStack(alignment: .leading, spacing: HanafudaFit.groupHeaderSpacing) {
            Text(verbatim: "\(group.kind.label) \(group.cards.count)/\(group.goal)")
                .themeCaption(11, weight: .heavy, maxScale: 1.3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Color(hex: HanafudaCardArt.bandLabelHex(on: hex)))
                .padding(.horizontal, 5)
                .frame(height: HanafudaFit.groupHeaderHeight)
                .background(Capsule().fill(Color(hex: hex).opacity(group.isComplete ? 1 : 0.8)))
            ZStack(alignment: .leading) {
                if group.cards.isEmpty {
                    RoundedRectangle(cornerRadius: cardWidth * 0.12, style: .continuous)
                        .strokeBorder(Theme.inkSub.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: cardWidth, height: height)
                }
                ForEach(Array(group.cards.enumerated()), id: \.element.id) { index, card in
                    HanafudaCardFace(card: card, showsKindLabel: index == group.cards.count - 1)
                        .frame(width: cardWidth, height: height)
                        .offset(x: CGFloat(index) * step)
                }
            }
            .frame(width: width, height: height, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
    }

    // MARK: - 場

    private func fieldArea(_ fit: HanafudaFit.Metrics) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(tr("場"))
                    .themeCaption(13, weight: .bold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(Theme.inkSubText)
                Spacer()
                if let drawn = model.drawnCard {
                    HStack(spacing: 4) {
                        Text(tr("めくり札"))
                            .themeCaption(13, weight: .bold, maxScale: 1.5)
                            .fitOneLine()
                            .foregroundStyle(Theme.coralText)
                        HanafudaCardFace(card: drawn, isHighlighted: true)
                            .frame(height: HanafudaFit.drawnCardHeight)
                    }
                }
                Text(tr("山札%lld枚", model.deck.count))
                    .themeCaption(14, weight: .heavy, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(Theme.inkSubText)
            }
            LazyVGrid(columns: fit.columns, spacing: HanafudaFit.gap) {
                ForEach(model.field) { card in
                    Button { model.chooseFieldCard(card) } label: {
                        HanafudaCardFace(
                            card: card,
                            isDimmed: isFieldDimmed(card),
                            isHighlighted: isCandidate(card)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isCandidate(card))
                    .accessibilityLabel(HanafudaSpeech.fieldLabel(
                        for: card, isSelecting: model.selection != nil, isCandidate: isCandidate(card)
                    ))
                }
            }
        }
        .padding(HanafudaFit.cardPadding)
        .frame(maxWidth: .infinity)
        .popCard(corner: Theme.cornerSmall)
    }

    private func isCandidate(_ card: HanafudaCard) -> Bool {
        model.selection?.candidates.contains(card) ?? false
    }

    /// 選択待ちのあいだは候補以外を落として、どれを押せばよいかを迷わせない。
    private func isFieldDimmed(_ card: HanafudaCard) -> Bool {
        model.selection != nil && !isCandidate(card)
    }

    // MARK: - 手札

    private func handArea(_ fit: HanafudaFit.Metrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(tr("あなたの取り札"))
                    .themeCaption(13, weight: .bold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(model.isPlayerTurn ? Theme.tealText : Theme.inkSubText)
                Text(yakuLine(for: .human))
                    .themeCaption(13, weight: .semibold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(Theme.inkSubText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
            }
            capturedGroups(model.humanCaptured, height: fit.stripHeight)
            LazyVGrid(columns: fit.columns, spacing: HanafudaFit.gap) {
                ForEach(model.humanHand) { card in
                    Button { model.play(card) } label: {
                        HanafudaCardFace(
                            card: card,
                            isDimmed: model.selection != nil,
                            isHighlighted: hintedHandCards.contains(card.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canPlay(card))
                    .accessibilityLabel(HanafudaSpeech.handLabel(
                        for: card, matches: HanafudaRules.matches(for: card, in: model.field)
                    ))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(10)
        .popCard(corner: Theme.cornerSmall)
    }

    /// ヒントがオンで自分の手番のときだけ「取れる札」を強調する（#190 の流儀）。
    private var hintedHandCards: Set<Int> {
        guard FeedbackPreference.hints.isEnabled, model.isPlayerTurn else { return [] }
        return model.capturableHandCards()
    }

    private func yakuLine(for player: HanafudaPlayer) -> String {
        let hits = model.yaku(of: player)
        guard !hits.isEmpty else { return tr("役なし") }
        let total = hits.reduce(0) { $0 + $1.points }
        // 1 行に収める行なので短い役名（英語はローマ字だけ・#2166）。
        return tr("%@（%lld文）", hits.map(\.yaku.shortName).joined(separator: tr("・")), total)
    }

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .koiKoiPrompt:
            HStack(spacing: 10) {
                actionButton(tr("こいこい"), role: .declaration) { model.declareKoiKoi() }
                actionButton(tr("あがり"), role: .primary, disabled: !model.canStop) {
                    model.declareStop()
                }
            }
        case .roundResult:
            VStack(spacing: 8) {
                roundResultCard
                if model.canExtendMatch {
                    extendMatchButton
                }
                // 視聴中に試合の結果へ進むと、見終えた広告が局ガードで弾かれて見損になる（#911 と同型）。
                actionButton(
                    model.round >= model.totalRounds ? tr("試合の結果へ") : tr("次の局へ"),
                    role: .primary,
                    disabled: extendRescue.isWatching
                ) { model.advanceAfterRound() }
            }
        case .matchResult:
            // 試合の結果の「もう一度」は結果カードの下（body の GeometryReader 内）に出す（#1519）。
            EmptyView()
        default:
            // 対局中は操作の行を出さない。投了は札のすぐ下の「⋯」（`overflowBar`）、手番は状態の帯（#1485）。
            EmptyView()
        }
    }

    /// 「⋯」の行を札のすぐ下に出す局面（こいこい・局の結果・試合の結果はその場の操作ボタンを出す）。
    private var showsOverflowBar: Bool {
        model.phase == .idle || model.phase == .playing
    }

    /// 札のすぐ下の「⋯」の行。投了は「⋯」へ（#1468）。
    private var overflowBar: some View {
        GameOverflowBar(
            menuItems: [
                GameControlMenuItem(
                    id: "resign", title: tr("投了"), systemImage: "flag.fill",
                    isDestructive: true, isEnabled: model.canResign
                ) { showResignConfirm = true },
            ],
            verticalPadding: HanafudaFit.overflowRowPadding
        )
    }

    /// 最終局で負けているときにだけ出す「広告を見て1局延長」（#1049）。
    private var extendMatchButton: some View {
        Button {
            // 視聴完了（報酬獲得）したときだけ延長する。どの局の決着に対するものかを広告の前に控え、
            // 視聴中に試合が決着・入れ替わっていたら乗せない（#729）。
            let serial = model.gameSerial
            extendRescue.request(
                services, gameID: HanafudaModel.gameID, purpose: .continue,
                guardedBy: .checkedByGrant
            ) {
                model.extendMatchAfterAd(forGame: serial)
            }
        } label: {
            Label(tr("広告を見て1局延長（1試合に1回）"), systemImage: "play.rectangle.fill")
                .themeBody(14, weight: .bold, maxScale: 1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .buttonStyle(GameButtonStyle(role: .ad, shape: .block))
        .disabled(extendRescue.isWatching)
    }

    private var roundResultCard: some View {
        VStack(spacing: 6) {
            if let result = model.roundResult {
                HanafudaRoundTitle(
                    text: roundResultTitle(result.winner),
                    color: result.winner == .human ? Theme.tealText : Theme.ink,
                    isBig: result.isBigHumanWin
                )
                if !result.hits.isEmpty {
                    Text(result.hits.map { tr("%@ %lld文", $0.name, $0.points) }.joined(separator: tr("・")))
                        .themeCaption(13, weight: .semibold, maxScale: 1.5)
                        .foregroundStyle(Theme.inkSubText)
                        .multilineTextAlignment(.center)
                }
                if !result.reasons.isEmpty {
                    Text(result.reasons.map(HanafudaScoring.reasonLabel).joined(separator: tr("・")))
                        .themeCaption(12, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.Fill.yellow))
                }
                Text(tr("%lld文", result.score))
                    .themeBody(22, weight: .heavy)
                    .fitOneLine()
                    .foregroundStyle(Theme.coralText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.roundResult.map(HanafudaSpeech.roundResultSummary) ?? "")
    }

    private var matchResultCard: some View {
        VStack(spacing: 10) {
            Text(matchTitle)
                .themeBody(26, weight: .heavy)
                .fitOneLine()
                .foregroundStyle(matchTitleColor)
            Text(tr("あなた %1$lld文 ・ CPU %2$lld文", model.humanTotal, model.cpuTotal))
                .themeBody(15, weight: .semibold, maxScale: 1.5)
                .foregroundStyle(Theme.inkSubText)
            Text(tr("こいこい あなた %1$lld回 ・ CPU %2$lld回", model.humanMatchKoiKoiCount, model.cpuMatchKoiKoiCount))
                .themeBody(13, maxScale: 1.5)
                .foregroundStyle(Theme.inkSubText)
            RecordLabel(model.recordResult)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 勝ちが続いたら一段上の強さを勧める（#722）。局数と酒役は今の試合のものを引き継ぐ。
    private var ladder: DifficultyLadderPrompt? {
        let levels = HanafudaDifficulty.allCases
        return DifficultyLadderPrompt(result: model.recordResult, currentLevel: levels.firstIndex(of: model.options.difficulty),
                                      levelLabels: levels.map(\.label)) { level in
            model.restartMatch(difficulty: levels[level])
        }
    }

    private var matchTitle: String {
        if model.wasResigned { return tr("投了（CPUの勝ち）") }
        if model.humanTotal > model.cpuTotal { return tr("あなたの勝ち！") }
        if model.humanTotal < model.cpuTotal { return tr("CPUの勝ち") }
        return tr("引き分け")
    }

    /// 局の結果カードの見出し。英語で語順が変わるので勝者ごとに文を分ける（#2166）。
    private func roundResultTitle(_ winner: HanafudaPlayer?) -> String {
        switch winner {
        case nil: return tr("流局")
        case .human?: return tr("あなたのあがり")
        case .cpu?: return tr("CPUのあがり")
        }
    }

    private var matchTitleColor: Color {
        if model.wasResigned { return Theme.ink }
        return model.humanTotal > model.cpuTotal ? Theme.tealText : Theme.ink
    }

    /// 役割（`GameButtonRole`）で色を決める横いっぱいのボタン（#1423）。色・角丸・44pt は `GameButtonStyle` が持つ。
    private func actionButton(_ title: String, role: GameButtonRole, disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .themeBody(16, weight: .bold, maxScale: 1.5)
                .fitOneLine()
        }
        .buttonStyle(GameButtonStyle(role: role, shape: .block))
        .disabled(disabled)
    }
}

// MARK: - 画面の高さへの収め方（#1254）

/// 場・手札・取り札の帯を、残った高さに収めるための寸法。
///
/// `View` の static 定数は MainActor に隔離されるため、テストから読めるよう別の enum に置く。
enum HanafudaFit {
    /// 札のあいだ・段のあいだ。
    static let gap: CGFloat = 6
    /// 3 つのカード（相手・場・手札）のあいだ。
    static let sectionSpacing: CGFloat = 8
    /// 各カードの内側の余白。
    static let cardPadding: CGFloat = 10
    /// 取り札の札の、縮める前の高さ（#2336。40pt では帯の月・種別が読めなかったので 52pt に）。
    static let baseStripHeight: CGFloat = 52
    /// 取り札の見出し（「光 2/3」）の高さと、見出しと札のあいだ。列どうしのあいだ。
    static let groupHeaderHeight: CGFloat = 16
    static let groupHeaderSpacing: CGFloat = 2
    static let groupSpacing: CGFloat = 6
    /// 見出しの文字（13pt）の行の高さ。役名の行は lineLimit(1) で折り返さない。
    static let headingHeight: CGFloat = 16
    /// 縮小率の下限。これ以下には縮めない（札が読めなくなるため）。
    static let minScale: CGFloat = 0.4
    /// 取り札（と めくり札）の縮小率の下限。月の数字が読めなくならないよう、場・手札より縮めない（#2336）。
    static let minStripScale: CGFloat = 0.85
    /// 低い画面（iPhone SE など）での取り札の縮小率の下限。押せる場・手札の札を優先して、取り札はここまで縮める（#2452）。
    /// 残りの高さが `shortScreenHeight` 以下で下限になり、`tallScreenHeight` 以上では `minStripScale` のまま
    /// （iPhone 17 の取り札は変わらない）。そのあいだは線形に移るので、高さが減るほど札が大きくなるような逆転は起きない。
    static let shortScreenMinStripScale: CGFloat = 0.6
    static let shortScreenHeight: CGFloat = 380
    static let tallScreenHeight: CGFloat = 480
    /// 札の並べ方の候補（列数）。空いた高さがある局は 4・5 列で大きく、広い画面は 6 列 2 段、
    /// 狭い画面は 8 列 1 段のほうが大きく取れる（#2336）。
    static let columnChoices = [4, 5, 6, 8]
    /// 札のすぐ下の「⋯」の行の上下の余白と、それを含めた行の高さ（44pt の「⋯」+ 上下の余白・#1485）。
    /// 行を札の外に置いていた頃（44pt + 上下 2pt）と同じ外寸にして、札の大きさを変えない。
    static let overflowRowPadding: CGFloat = 2
    static let overflowRowHeight: CGFloat = BoardGameControlMetrics.minTapTarget + 2 * overflowRowPadding
    /// めくり札（場の見出しの行に出る）の高さ。取り札の縮小とは別に固定し、出た瞬間に行が伸びる分だけを
    /// `fixedHeight` に見込んでおく（以前は取り札と同じ高さをもう 1 本ぶん確保していて、実寸より 70pt ほど多かった・#2336）。
    static let drawnCardHeight: CGFloat = 40
    /// 縮められない部分（見出しの文字・カードの内側の余白・段のあいだ以外）の高さ。
    /// 見出し 3 行 ＋ 取り札の見出し 2 つ ＋ めくり札で行が伸びる分 ＋ 3 カードぶんの上下余白 60 ＋ カード内の縦の間隔 4 か所 ＋ カード間の間隔 2 か所。
    static let fixedHeight: CGFloat = 3 * headingHeight + 2 * (groupHeaderHeight + groupHeaderSpacing)
        + (drawnCardHeight - headingHeight) + 3 * 2 * cardPadding + 4 * gap + 2 * sectionSpacing

    struct Metrics: Equatable {
        var cardWidth: CGFloat
        var stripHeight: CGFloat
        var columnCount: Int

        var columns: [GridItem] {
            Array(repeating: GridItem(.fixed(cardWidth), spacing: HanafudaFit.gap), count: columnCount)
        }
    }

    /// - Parameters:
    ///   - availableWidth / availableHeight: 場・手札を置ける領域（得点・操作・広告を除いた残り）。
    ///   - stripHeight: 縮める前の取り札の帯の高さ。
    ///   - fieldCount / handCount: いまの枚数。段数はこの枚数と列数から数える。
    static func metrics(availableWidth: CGFloat, availableHeight: CGFloat, stripHeight: CGFloat,
                        fieldCount: Int, handCount: Int) -> Metrics {
        let innerWidth = max(0, availableWidth - 2 * cardPadding)
        var best = Metrics(cardWidth: 0, stripHeight: stripHeight * minScale, columnCount: columnChoices[0])
        var bestUsedHeight = CGFloat.infinity
        // 縮小の下限は札の幅で揃える（6 列の自然な幅の `minScale` 倍）。列ごとの比率で下限を持つと、
        // 列が少ないほど下限の札が大きくなり、高さに収まらない並べ方が選ばれてしまう（#2336）。
        let floorWidth = minScale * (innerWidth - 5 * gap) / 6
        let stripFloor = stripFloor(availableHeight: availableHeight)
        for columns in columnChoices {
            let naturalWidth = (innerWidth - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let floorScale = naturalWidth > 0 ? min(1, floorWidth / naturalWidth) : minScale
            // 段数は実際の枚数で数える。配り直後の 8 枚ぶんを取りっぱなしにすると、手札が減った局の後半に
            // 下が空いたままになる（#2336）。段が 1 つ減る枚数のとき札が大きくなる。
            let fieldRows = rows(max(1, fieldCount), columns: columns)
            let handRows = rows(max(1, handCount), columns: columns)
            let rowGaps = CGFloat(fieldRows - 1 + handRows - 1) * gap
            let naturalHeight = 2 * stripHeight + CGFloat(fieldRows + handRows) * naturalWidth * HanafudaCardArt.aspectRatio
            let cardsNaturalHeight = CGFloat(fieldRows + handRows) * naturalWidth * HanafudaCardArt.aspectRatio
            let scale = naturalHeight > 0
                ? min(1, max(floorScale, (availableHeight - fixedHeight - rowGaps) / naturalHeight))
                : 1
            var cardScale = scale
            var stripScale = scale
            // 取り札は月の数字が読める大きさを下限にして、足りない高さは場・手札の札で受ける（#2336）。
            if scale < stripFloor, cardsNaturalHeight > 0 {
                stripScale = stripFloor
                cardScale = min(1, max(floorScale, (availableHeight - fixedHeight - rowGaps - 2 * stripHeight * stripScale)
                                       / cardsNaturalHeight))
            }
            // 同じ大きさなら、段が少なく背の低い並べ方を残す（下限に張り付いた低い画面で、段の多い
            // 4 列が先頭だからと選ばれて高さを溢れさせない）。
            let width = naturalWidth * cardScale
            let usedHeight = CGFloat(fieldRows + handRows) * width * HanafudaCardArt.aspectRatio + rowGaps
            if width > best.cardWidth + 0.001 || (abs(width - best.cardWidth) <= 0.001 && usedHeight < bestUsedHeight) {
                best = Metrics(cardWidth: width, stripHeight: stripHeight * stripScale, columnCount: columns)
                bestUsedHeight = usedHeight
            }
        }
        return best
    }

    /// 残りの高さに応じた取り札の縮小率の下限（#2452）。
    static func stripFloor(availableHeight: CGFloat) -> CGFloat {
        let t = min(1, max(0, (availableHeight - shortScreenHeight) / (tallScreenHeight - shortScreenHeight)))
        return shortScreenMinStripScale + (minStripScale - shortScreenMinStripScale) * t
    }

    /// 取り札の 4 列の幅。札の重なりが多い列（カス）ほど広く取り、どの列も札 1 枚ぶんは確保する。
    /// 下限で持ち上げた列の分は、残りの列から重みに応じて差し引くので、合計は `total` を超えない。
    static func groupWidths(total: CGFloat, cardWidth: CGFloat, counts: [Int]) -> [CGFloat] {
        guard !counts.isEmpty else { return [] }
        let usable = max(0, total - CGFloat(counts.count - 1) * groupSpacing)
        let weights = counts.map { cardWidth + CGFloat(max(0, $0 - 1)) * cardWidth * 0.45 }
        var widths = [CGFloat](repeating: cardWidth, count: counts.count)
        var pinned = Set<Int>()
        while true {
            let free = counts.indices.filter { !pinned.contains($0) }
            let freeWeight = free.reduce(0) { $0 + weights[$1] }
            let room = usable - CGFloat(pinned.count) * cardWidth
            guard !free.isEmpty, freeWeight > 0 else { break }
            let newlyPinned = free.filter { room * weights[$0] / freeWeight < cardWidth }
            if newlyPinned.isEmpty {
                for i in free { widths[i] = room * weights[i] / freeWeight }
                break
            }
            pinned.formUnion(newlyPinned)
        }
        return widths
    }

    /// 列の中で札を重ねる間隔。月の数字（札の左端に出る）が読めるよう、広い列でも札の幅の 0.9 倍までに抑える。
    /// 列が狭ければ間隔も詰まる（列の外へはみ出さない）。
    static func overlapStep(groupWidth: CGFloat, cardWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        return max(0, min(cardWidth * 0.9, (groupWidth - cardWidth) / CGFloat(count - 1)))
    }

    private static func rows(_ count: Int, columns: Int) -> Int {
        (count + columns - 1) / columns
    }
}

private extension View {
    /// 文字サイズ設定で拡大しても、帯・見出しを折り返さず 1 行に縮めて収める（#1469）。
    func fitOneLine() -> some View {
        lineLimit(1).minimumScaleFactor(0.5)
    }
}


/// 局結果の見出し。大きなあがり（#2804）のときだけ一回り大きくし、出た瞬間に弾ませる。
/// Reduce Motion のときは弾ませず、大きさだけで強調する。
private struct HanafudaRoundTitle: View {
    let text: String
    let color: Color
    let isBig: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    var body: some View {
        Text(text)
            .themeBody(isBig ? 26 : 18, weight: .heavy)
            .fitOneLine()
            .foregroundStyle(color)
            .scaleEffect(isBig && !reduceMotion && !popped ? 0.6 : 1)
            .onAppear {
                guard isBig, !reduceMotion else { return }
                withGameAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { popped = true }
            }
    }
}
