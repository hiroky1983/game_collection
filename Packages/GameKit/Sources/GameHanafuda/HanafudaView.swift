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
                    matchResultCard.transition(.opacity)
                } else {
                    let fit = HanafudaFit.metrics(
                        availableWidth: geo.size.width, availableHeight: geo.size.height,
                        stripHeight: layout.scaled(HanafudaFit.baseStripHeight),
                        fieldCount: model.field.count, handCount: model.humanHand.count
                    )
                    VStack(spacing: HanafudaFit.sectionSpacing) {
                        opponentArea(fit)
                        fieldArea(fit).transition(.opacity)
                        handArea(fit)
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
        .gameChrome(title: "花札こいこい", review: services.review) {
            // 役は 12 種あり、覚えていないと打つ手が決められない。対局中 1 タップで開ける
            // 早見表をここに置く（#495 の仕様）。タイトル＋「?」（遊び方）とアイコンで並べる
            // （文字ラベルにすると幅を取り、狭い画面でヘッダーが崩れていた・会長指摘）。
            ToolbarItem(placement: .primaryAction) {
                Button { showYakuSheet = true } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .accessibilityLabel("役の早見表")
            }
        }
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
        #endif
    }

    // MARK: - 得点表示

    private var scoreBar: some View {
        VStack(spacing: 6) {
            HStack {
                scoreChip(title: "あなた", value: model.humanTotal, fill: Theme.Fill.teal)
                Spacer(minLength: 8)
                if model.phase != .matchResult {
                    Text(model.round > model.options.rounds ? "延長戦" : "\(model.round) / \(model.options.rounds)局")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                    Spacer(minLength: 8)
                }
                scoreChip(title: "CPU", value: model.cpuTotal, fill: Theme.Fill.purple)
            }
            Text(model.message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
        .padding(10)
        .popCard(corner: Theme.cornerSmall)
    }

    private func scoreChip(title: String, value: Int, fill: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(fill))
            Text("\(value)文")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
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
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(model.turn == .cpu ? Theme.coral : Theme.inkSub)
                Text(yakuLine(for: .cpu))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text("手札\(model.cpuHand.count)枚")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 12, design: .rounded))
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
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Spacer()
                if let drawn = model.drawnCard {
                    HStack(spacing: 4) {
                        Text("めくり札")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.coral)
                        HanafudaCardFace(card: drawn, isHighlighted: true)
                            .frame(height: fit.stripHeight)
                    }
                }
                Text("山札\(model.deck.count)枚")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(model.isPlayerTurn ? Theme.teal : Theme.inkSub)
                Text(yakuLine(for: .human))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                actionButton("こいこい", color: Theme.Fill.purple) { model.declareKoiKoi() }
                actionButton("あがり", color: Theme.Fill.coral, disabled: !model.canStop) {
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
                    color: Theme.Fill.coral,
                    disabled: extendRescue.isWatching
                ) { model.advanceAfterRound() }
            }
        case .matchResult:
            HStack(spacing: 10) {
                actionButton("もう一度", color: Theme.Fill.coral) { model.restartMatch() }
                actionButton("ハブへ戻る", color: Theme.fillMuted, foreground: .white) { dismiss() }
            }
        default:
            HStack(spacing: 10) {
                Text(model.isPlayerTurn ? "あなたの番です" : "CPUが考えています…")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button { showResignConfirm = true } label: {
                    Text("投了")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                .disabled(!model.canResign)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .popCard(corner: Theme.cornerSmall)
        }
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
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(extendRescue.isWatching ? Theme.inkSub.opacity(0.3) : Theme.Fill.teal,
                            in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                .foregroundStyle(extendRescue.isWatching ? Theme.inkSub : Theme.onAccent)
        }
        .buttonStyle(.plain)
        .disabled(extendRescue.isWatching)
    }

    private var roundResultCard: some View {
        VStack(spacing: 6) {
            if let result = model.roundResult {
                Text(result.winner == nil ? "流局" : "\(result.winner!.label)のあがり")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(result.winner == .human ? Theme.teal : Theme.ink)
                if !result.hits.isEmpty {
                    Text(result.hits.map { "\($0.name) \($0.points)文" }.joined(separator: "・"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                        .multilineTextAlignment(.center)
                }
                if !result.reasons.isEmpty {
                    Text(result.reasons.joined(separator: "・"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.Fill.yellow))
                }
                Text("\(result.score)文")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
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
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(model.humanTotal > model.cpuTotal ? Theme.teal : Theme.ink)
            Text("あなた \(model.humanTotal)文 ・ CPU \(model.cpuTotal)文")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            RecordLabel(model.recordResult)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        if model.humanTotal > model.cpuTotal { return "あなたの勝ち！" }
        if model.humanTotal < model.cpuTotal { return "CPUの勝ち" }
        return "引き分け"
    }

    /// - Parameter foreground: 面（`color`）の上に載せる文字色。差し色の面には `Theme.onAccent`、
    ///   濃色の面（`Theme.fillMuted`）には `.white` を渡す（#220）。
    private func actionButton(_ title: String, color: Color, foreground: Color = Theme.onAccent,
                              disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(disabled ? Theme.inkSub.opacity(0.3) : color,
                            in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                .foregroundStyle(disabled ? Theme.inkSub : foreground)
        }
        .buttonStyle(.plain)
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
