import Foundation
import SwiftUI
import Core

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
                    VStack(spacing: 8) {
                        matchResultCard
                        actionButton("もう一度", role: .primary) { model.restartMatch() }
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
        .gameChrome(title: "花札こいこい", review: services.review,
                    reference: GameChromeReference { showYakuSheet = true })
        .howToPlay(.hanafuda) { HanafudaRuleSheet() }
        .sheet(isPresented: $showYakuSheet) { HanafudaYakuSheet(options: model.options) }
        .sheet(isPresented: .constant(model.phase == .idle)) {
            HanafudaSetupSheet(draft: $draft, onStart: { model.startMatch(options: draft) }, onCancel: { dismiss() })
                .interactiveDismissDisabled()
        }
        .confirmationDialog("投了しますか？", isPresented: $showResignConfirm, titleVisibility: .visible) {
            Button("投了する", role: .destructive) { model.resign() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この試合を打ち切ります。負けとして記録されます。")
        }
        // 1 局延長の提示（#780 × #1049）。最終局で負けている局の結果でボタンが出ているあいだを 1 回の提示として数える。
        .rewardOffer(extendRescue, for: .continue, isPresented: model.canExtendMatch,
                     services: services, gameID: HanafudaModel.gameID)
        .rewardedRescueAlerts(
            extendRescue,
            notEarned: "延長できませんでした",
            unavailable: RewardUnavailableAlert(
                title: "延長できませんでした",
                message: "広告を見ているあいだに試合が終わったため、延長できませんでした。"
            )
        )
        .task(id: model.aiTurnKey) {
            await model.runCPUTurnIfNeeded()
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
                scoreChip(title: "あなた", value: model.humanTotal, fill: Theme.Fill.teal)
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
                    Text(model.round > model.options.rounds ? "延長戦" : "\(model.round) / \(model.options.rounds)局")
                        .themeCaption(13, weight: .bold, maxScale: 1.5)
                        .fitOneLine()
                        .foregroundStyle(Theme.inkSub)
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
            TurnBadge("開始待ち", kind: .finished)
        case .playing, .koiKoiPrompt:
            TurnBadge(isYourTurn: model.turn == .human)
        case .roundResult:
            TurnBadge("局の終わり", kind: .finished)
        case .matchResult:
            TurnBadge("決着", kind: .finished)
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
            Text("\(value)文")
                .themeBody(16, weight: .heavy, maxScale: 1.5)
                .fitOneLine()
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)文")
    }

    // MARK: - 相手

    private func opponentArea(_ fit: HanafudaFit.Metrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("CPUの取り札")
                    .themeCaption(12, weight: .bold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(model.turn == .cpu ? Theme.coral : Theme.inkSub)
                Text(yakuLine(for: .cpu))
                    .themeCaption(12, weight: .semibold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(Theme.inkSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text("手札\(model.cpuHand.count)枚")
                    .themeCaption(12, weight: .semibold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(Theme.inkSub)
            }
            capturedStrip(model.cpuCaptured, height: fit.stripHeight)
        }
        .padding(10)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CPUの取り札。\(HanafudaSpeech.capturedSummary(model.cpuCaptured))。\(HanafudaSpeech.yakuSummary(model.yaku(of: .cpu)))")
    }

    /// 取り札を小さく並べる帯。枚数が増えても高さが変わらないよう 1 行に収める。
    private func capturedStrip(_ cards: [HanafudaCard], height: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                if cards.isEmpty {
                    Text("なし")
                        .themeCaption(12, weight: .regular, maxScale: 1.5)
                        .fitOneLine()
                        .foregroundStyle(Theme.inkSub)
                        .frame(height: height)
                }
                ForEach(cards) { card in
                    HanafudaCardFace(card: card)
                        .frame(height: height)
                }
            }
        }
        .frame(height: height)
    }

    // MARK: - 場

    private func fieldArea(_ fit: HanafudaFit.Metrics) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("場")
                    .themeCaption(12, weight: .bold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(Theme.inkSub)
                Spacer()
                if let drawn = model.drawnCard {
                    HStack(spacing: 4) {
                        Text("めくり札")
                            .themeCaption(12, weight: .bold, maxScale: 1.5)
                            .fitOneLine()
                            .foregroundStyle(Theme.coral)
                        HanafudaCardFace(card: drawn, isHighlighted: true)
                            .frame(height: fit.stripHeight)
                    }
                }
                Text("山札\(model.deck.count)枚")
                    .themeCaption(12, weight: .semibold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(Theme.inkSub)
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
                Text("あなたの取り札")
                    .themeCaption(12, weight: .bold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(model.isPlayerTurn ? Theme.teal : Theme.inkSub)
                Text(yakuLine(for: .human))
                    .themeCaption(12, weight: .semibold, maxScale: 1.5)
                    .fitOneLine()
                    .foregroundStyle(Theme.inkSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
            }
            capturedStrip(model.humanCaptured, height: fit.stripHeight)
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
        guard !hits.isEmpty else { return "役なし" }
        let total = hits.reduce(0) { $0 + $1.points }
        return "\(hits.map(\.name).joined(separator: "・"))（\(total)文）"
    }

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .koiKoiPrompt:
            HStack(spacing: 10) {
                actionButton("こいこい", role: .declaration) { model.declareKoiKoi() }
                actionButton("あがり", role: .primary, disabled: !model.canStop) {
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
                    model.round >= model.totalRounds ? "試合の結果へ" : "次の局へ",
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
                    id: "resign", title: "投了", systemImage: "flag.fill",
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
            Label("広告を見て1局延長（1試合に1回）", systemImage: "play.rectangle.fill")
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
                Text(result.winner == nil ? "流局" : "\(result.winner!.label)のあがり")
                    .themeBody(18, weight: .heavy)
                    .fitOneLine()
                    .foregroundStyle(result.winner == .human ? Theme.teal : Theme.ink)
                if !result.hits.isEmpty {
                    Text(result.hits.map { "\($0.name) \($0.points)文" }.joined(separator: "・"))
                        .themeCaption(13, weight: .semibold, maxScale: 1.5)
                        .foregroundStyle(Theme.inkSub)
                        .multilineTextAlignment(.center)
                }
                if !result.reasons.isEmpty {
                    Text(result.reasons.joined(separator: "・"))
                        .themeCaption(12, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.Fill.yellow))
                }
                Text("\(result.score)文")
                    .themeBody(22, weight: .heavy)
                    .fitOneLine()
                    .foregroundStyle(Theme.coral)
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
            Text("あなた \(model.humanTotal)文 ・ CPU \(model.cpuTotal)文")
                .themeBody(15, weight: .semibold, maxScale: 1.5)
                .foregroundStyle(Theme.inkSub)
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
        if model.wasResigned { return "投了（CPUの勝ち）" }
        if model.humanTotal > model.cpuTotal { return "あなたの勝ち！" }
        if model.humanTotal < model.cpuTotal { return "CPUの勝ち" }
        return "引き分け"
    }

    private var matchTitleColor: Color {
        if model.wasResigned { return Theme.ink }
        return model.humanTotal > model.cpuTotal ? Theme.teal : Theme.ink
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
    /// 取り札の帯の、縮める前の高さ。
    static let baseStripHeight: CGFloat = 40
    /// 場・手札が並びうる最大枚数（配り直後の 8 枚）。これを超えたぶんだけ段を足す。
    static let baseCardCount = 8
    /// 縮小率の下限。これ以下には縮めない（札が読めなくなるため）。
    static let minScale: CGFloat = 0.4
    /// 札の並べ方の候補（列数）。広い画面は 6 列 2 段、狭い画面は 8 列 1 段のほうが大きく取れる。
    static let columnChoices = [6, 8]
    /// 札のすぐ下の「⋯」の行の上下の余白と、それを含めた行の高さ（44pt の「⋯」+ 上下の余白・#1485）。
    /// 行を札の外に置いていた頃（44pt + 上下 2pt）と同じ外寸にして、札の大きさを変えない。
    static let overflowRowPadding: CGFloat = 2
    static let overflowRowHeight: CGFloat = BoardGameControlMetrics.minTapTarget + 2 * overflowRowPadding
    /// 縮められない部分（見出しの文字・カードの内側の余白・段のあいだ以外）の高さ。
    /// 見出し 3 行（12pt の文字 ≈ 16pt。役名の行は lineLimit(1) で折り返さない）＋ 3 カードぶんの上下余白 60 ＋ カード内の縦の間隔 4 か所 ＋ カード間の間隔 2 か所。
    static let fixedHeight: CGFloat = 3 * 16 + 3 * 2 * cardPadding + 4 * gap + 2 * sectionSpacing

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
    ///   - fieldCount / handCount: いまの枚数。`baseCardCount` を超えたときだけ段が増える。
    static func metrics(availableWidth: CGFloat, availableHeight: CGFloat, stripHeight: CGFloat,
                        fieldCount: Int, handCount: Int) -> Metrics {
        let innerWidth = max(0, availableWidth - 2 * cardPadding)
        var best = Metrics(cardWidth: 0, stripHeight: stripHeight * minScale, columnCount: columnChoices[0])
        for columns in columnChoices {
            let naturalWidth = (innerWidth - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let fieldRows = rows(max(baseCardCount, fieldCount), columns: columns)
            let handRows = rows(max(baseCardCount, handCount), columns: columns)
            let rowGaps = CGFloat(fieldRows - 1 + handRows - 1) * gap
            let naturalHeight = 3 * stripHeight + CGFloat(fieldRows + handRows) * naturalWidth * HanafudaCardArt.aspectRatio
            let scale = naturalHeight > 0
                ? min(1, max(minScale, (availableHeight - fixedHeight - rowGaps) / naturalHeight))
                : 1
            // 同じ大きさなら列の少ない（＝これまでどおりの）並べ方を残す。
            if naturalWidth * scale > best.cardWidth {
                best = Metrics(cardWidth: naturalWidth * scale, stripHeight: stripHeight * scale, columnCount: columns)
            }
        }
        return best
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
