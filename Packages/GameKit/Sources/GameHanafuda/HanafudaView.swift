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
    /// 開始前の設定（局数・酒の役・強さ）。局が始まったら焼き込まれる（1 局 = 1 RuleSet）。
    @State private var draft = HanafudaOptions()

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: HanafudaModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            scoreBar
            if model.phase == .matchResult {
                matchResultCard.transition(.opacity)
            } else {
                opponentArea
                fieldArea.transition(.opacity)
                handArea
            }
            HowToPlayHint(.hanafuda, playLog: services.playLog)
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .matchResult)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        .padding(Theme.pad)
        .gameChrome(title: "花札こいこい", review: services.review) {
            // 役は 12 種あり、覚えていないと打つ手が決められない。対局中 1 タップで開ける
            // 早見表をここに置く（#495 の仕様）。ツールバーは `Label` をアイコンだけに畳むので
            // 文字を出すために `Text` を直接渡す。
            ToolbarItem(placement: .primaryAction) {
                Button { showYakuSheet = true } label: {
                    Text("役")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
        }
        .howToPlay(.hanafuda) { HanafudaRuleSheet() }
        .sheet(isPresented: $showYakuSheet) { HanafudaYakuSheet(options: model.options) }
        .sheet(isPresented: .constant(model.phase == .idle)) {
            HanafudaSetupSheet(draft: $draft) { model.startMatch(options: draft) }
                .interactiveDismissDisabled()
        }
        .confirmationDialog("投了しますか？", isPresented: $showResignConfirm, titleVisibility: .visible) {
            Button("投了する", role: .destructive) { model.resign() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この試合を打ち切ります。負けとして記録されます。")
        }
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
                    Text("\(model.round) / \(model.options.rounds)局")
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

    private var opponentArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("CPUの取り札")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(model.turn == .cpu ? Theme.coral : Theme.inkSub)
                Text(yakuLine(for: .cpu))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Spacer()
                Text("手札\(model.cpuHand.count)枚")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
            }
            capturedStrip(model.cpuCaptured)
        }
        .padding(10)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CPUの取り札。\(HanafudaSpeech.capturedSummary(model.cpuCaptured))。\(HanafudaSpeech.yakuSummary(model.yaku(of: .cpu)))")
    }

    /// 取り札を小さく並べる帯。枚数が増えても高さが変わらないよう 1 行に収める。
    private func capturedStrip(_ cards: [HanafudaCard]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                if cards.isEmpty {
                    Text("なし")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                        .frame(height: capturedHeight)
                }
                ForEach(cards) { card in
                    HanafudaCardFace(card: card)
                        .frame(height: capturedHeight)
                }
            }
        }
        .frame(height: capturedHeight)
    }

    private var capturedHeight: CGFloat { layout.scaled(40) }

    // MARK: - 場

    private var fieldArea: some View {
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
                            .frame(height: capturedHeight)
                    }
                }
                Text("山札\(model.deck.count)枚")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
            }
            LazyVGrid(columns: fieldColumns, spacing: 6) {
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
            // 縦の余りは**場のカード自身**に吸わせ、札は中央に置く（#193 と同じ考え方）。
            // 上寄せにすると、場が 1 行しか無いときに札の下へ大きな空白が残って
            // 「描き損ねた」ように見える。
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .popCard(corner: Theme.cornerSmall)
    }

    private var fieldColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
    }

    private func isCandidate(_ card: HanafudaCard) -> Bool {
        model.selection?.candidates.contains(card) ?? false
    }

    /// 選択待ちのあいだは候補以外を落として、どれを押せばよいかを迷わせない。
    private func isFieldDimmed(_ card: HanafudaCard) -> Bool {
        model.selection != nil && !isCandidate(card)
    }

    // MARK: - 手札

    private var handArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("あなたの取り札")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(model.isPlayerTurn ? Theme.teal : Theme.inkSub)
                Text(yakuLine(for: .human))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Spacer()
            }
            capturedStrip(model.humanCaptured)
            LazyVGrid(columns: fieldColumns, spacing: 6) {
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
                actionButton(
                    model.round >= model.options.rounds ? "試合の結果へ" : "次の局へ",
                    color: Theme.Fill.coral
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
