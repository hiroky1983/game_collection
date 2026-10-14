import SwiftUI
import Core

public struct OldMaidView: View {
    @State private var model: OldMaidModel
    private let services: GameServices
    @State private var showNewGame = false
    /// 操作の後に CPU の手番を回すタスク。画面を離れたらキャンセルする（いろリレー #1339 と同じ）。
    /// `.task` の側は View のライフサイクルで自動的にキャンセルされるが、ボタンから起こした
    /// 非構造化タスクはそのままでは生き残り、画面外で CPU が引き続けて決着・記録まで進んでしまう。
    @State private var cpuTask: Task<Void, Never>?
    /// 画面の広さ（#458）。札と同じ倍率で枠を拡大するために読む。
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: OldMaidModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            cpuRow
            // 決着後は卓も手札も要らないので、代わりに順位のリザルトを出す。
            // 縦の余りは `Spacer` ではなく手札 / リザルトのカード自身に吸わせる（大富豪 #193 と同じ）。
            if model.phase == .result {
                resultCard
                    .transition(.opacity)
            } else {
                tableArea
                    .transition(.opacity)
                handArea
                    .transition(.opacity)
            }
            HowToPlayHint(.oldMaid, playLog: services.playLog)
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .result, ladder: ladder)
            BannerSlot(ads: services.ads)
        }
        // 局面 → リザルトの差し替えは、残り続ける親に置かないと `transition` が効かない（#195）。
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        .padding(Theme.pad)
        .gameChrome(title: tr("ババ抜き"), review: services.review,
                    newGame: GameChromeNewGame(.match) {
                        showNewGame = true
                    })
        .howToPlay(HowToPlayGuide.oldMaid.illustrated(OldMaidHowToFigures.items))
        .sheet(isPresented: $showNewGame) {
            OldMaidNewGameSheet(aiLevel: model.aiLevel) { level in
                showNewGame = false
                model.startGame(aiLevel: level)
                runCPU()
            } onCancel: { showNewGame = false }
        }
        .onDisappear { cpuTask?.cancel() }
        .task {
            // 開幕のモーダルは置かず、卓を見せたまま配り始める（#192）。強さは右上の「新規対局」で選び直す。
            // 中断から戻ったときは init が `.playing` まで復元しているので配り直さない。
            if model.phase == .idle { model.startGame() }
            #if DEBUG
            // 撮影・動作確認用: `-oldMaidScenario tell|watched|result` で局面を差し替える。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-oldMaidScenario"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
            }
            #endif
            // 中断から戻ったときに CPU の手番が止まったままにならないようにする。
            await model.runCPUTurnsIfNeeded()
        }
    }

    /// あなたの操作の後に CPU の手番を回す。前のタスクは止めてから起こす（走者は `withAITurnRunner` が 1 本に保つ）。
    private func runCPU() {
        cpuTask?.cancel()
        cpuTask = Task { await model.runCPUTurnsIfNeeded() }
    }

    /// 勝ちが続いたら一段上の強さを勧める（#722）。並びは開始シートの「CPUの強さ」と同じ。
    private var ladder: DifficultyLadderPrompt? {
        DifficultyLadderPrompt(result: model.recordResult,
                               currentLevel: CPUStrength.ladderIndex(forLevel: model.aiLevel),
                               levelLabels: CPUStrength.labels) { index in
            model.startGame(aiLevel: CPUStrength.level(atLadderIndex: index))
            runCPU()
        }
    }

    // MARK: - ステータス

    private var statusBar: some View {
        HStack(spacing: 8) {
            Label(tr("%lldゲーム目", max(model.gameNumber, 1)), systemImage: "number")
                .themeBody(13)
                .foregroundStyle(Theme.inkSub)
            Text(CPUStrength.strength(for: model.aiLevel).label)
                .scaledFont(11, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(CPUStrength.strength(for: model.aiLevel).accent))
                .accessibilityLabel(tr("CPUの強さ、%@", CPUStrength.strength(for: model.aiLevel).label))
            Spacer()
            Text(turnLabel)
                .scaledFont(12, weight: .bold, design: .rounded)
                .foregroundStyle(model.isPlayerTurn ? Theme.teal : Theme.inkSub)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var turnLabel: String {
        switch model.phase {
        case .idle:    return tr("開始待ち")
        case .result:  return tr("決着")
        case .playing:
            return model.isPlayerTurn ? tr("あなたの番") : tr("%@の番", model.playerName(model.currentPlayer))
        }
    }

    // MARK: - CPU

    private var cpuRow: some View {
        HStack(spacing: 8) {
            ForEach(1..<OldMaidModel.playerCount, id: \.self) { index in
                cpuCard(index)
            }
        }
    }

    private func cpuCard(_ index: Int) -> some View {
        let isCurrent = model.phase == .playing && model.currentPlayer == index
        let isTarget = model.humanTarget == index
        let count = model.hands[index].count
        let action = OldMaidAccessibility.actionText(model.game?.lastActions[index] ?? OldMaidAction.none)
        return VStack(spacing: 4) {
            OldMaidFaceView(face: model.face(of: index), isOut: count == 0 && model.phase != .idle)
                .frame(width: layout.scaled(34), height: layout.scaled(34))
            Text(model.playerName(index))
                .scaledFont(12, weight: .bold, design: .rounded)
                .foregroundStyle(isCurrent ? Theme.coral : Theme.ink)
            Text(cpuStatus(index, count: count))
                .scaledFont(11, weight: .semibold, design: .rounded)
                .foregroundStyle(Theme.inkSub)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(action.isEmpty ? " " : action)
                .scaledFont(10, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.onAccent)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(action.isEmpty ? Color.clear : Theme.Fill.purple))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 6)
        .popCard(corner: Theme.cornerSmall)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .strokeBorder(isTarget ? Theme.coral : Color.clear, lineWidth: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([model.playerName(index), cpuStatus(index, count: count), action]
            .filter { !$0.isEmpty }.joined(separator: tr("、")))
    }

    private func cpuStatus(_ index: Int, count: Int) -> String {
        if let place = model.game?.finishOrder.firstIndex(of: index) {
            return tr("%lld位であがり", place + 1)
        }
        return tr("残り%lld枚", count)
    }

    // MARK: - 卓（引く相手の伏せ札）

    private var tableArea: some View {
        VStack(spacing: 8) {
            if let target = model.humanTarget {
                targetPicker(target)
            } else {
                waitingPanel
            }
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .scaledFont(11, weight: .bold)
                Text(tr("捨てたペア %lld組", model.game?.discardedPairs.count ?? 0))
                    .scaledFont(11, weight: .semibold, design: .rounded)
                Spacer()
                if let joker = jokerNote {
                    Text(joker)
                        .scaledFont(11, weight: .bold, design: .rounded)
                        .foregroundStyle(Theme.purple)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(Theme.inkSub)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 誰がジョーカーを持っているかは、あなた自身が持っているときだけ分かる。
    private var jokerNote: String? {
        model.playerHand.contains(where: \.isJoker) ? tr("ジョーカーはあなたの手に") : nil
    }

    /// あなたの番: 相手の顔と伏せ札。札をタップすると指をかけ、顔に出ることがある。
    private func targetPicker(_ target: Int) -> some View {
        let cards = model.hands[target]
        let face = model.face(of: target)
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                OldMaidFaceView(face: face)
                    .frame(width: layout.scaled(52), height: layout.scaled(52))
                    .accessibilityLabel(tr("%1$@の顔、%2$@", model.playerName(target), OldMaidAccessibility.faceName(face)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("%@の札から1枚選んで引く", model.playerName(target)))
                        .scaledFont(13, weight: .bold, design: .rounded)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(faceCaption(face))
                        .scaledFont(12, weight: .bold, design: .rounded)
                        .foregroundStyle(face == .neutral ? Theme.inkSub : Theme.coral)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
            }
            .gameAnimation(.easeInOut(duration: 0.15), value: face)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: OldMaidHandLayout.columnSpacing),
                               count: OldMaidHandLayout.columns),
                spacing: OldMaidHandLayout.rowSpacing
            ) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { position, card in
                    let isSelected = model.selectedID == card.id
                    OldMaidCardBackView(selected: isSelected)
                        .offset(y: isSelected ? -8 : 0)
                        .gameAnimation(.spring(response: 0.2), value: isSelected)
                        // 見える札は 42pt のまま、タップ判定だけを列いっぱいに広げて 44pt 以上にする（#195）。
                        .frame(maxWidth: .infinity, minHeight: OldMaidHandLayout.minimumTapTarget)
                        .contentShape(Rectangle())
                        .onTapGesture { model.toggleSelection(card.id) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(OldMaidAccessibility.targetCardLabel(
                            position: position, count: cards.count, isSelected: isSelected))
                        .accessibilityHint(tr("ダブルタップで選択を切り替えます"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.toggleSelection(card.id) }
                }
            }
            .gameAnimation(.easeInOut(duration: 0.18), value: cards)
        }
    }

    private func faceCaption(_ face: OldMaidFace) -> String {
        switch face {
        case .neutral:
            return model.selectedID == nil ? tr("札をタップして、顔色をうかがおう") : tr("……（顔色は読めない）")
        case .smile:   return tr("にやり……？")
        case .worried: return tr("ひやり……？")
        }
    }

    /// CPU の番: 誰が誰から引いているか。直前に動いた札があなたの札なら、それも伝える。
    private var waitingPanel: some View {
        let drawer = model.currentPlayer
        let from = model.game?.currentTarget
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                OldMaidFaceView(face: .neutral)
                    .frame(width: layout.scaled(40), height: layout.scaled(40))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if model.phase == .playing, let from {
                        Text(tr("%1$@が%2$@から引いています", model.playerName(drawer), model.playerName(from)))
                            .scaledFont(13, weight: .bold, design: .rounded)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    if let note = lastTransferNote {
                        Text(note)
                            .scaledFont(12, weight: .semibold, design: .rounded)
                            .foregroundStyle(Theme.inkSub)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: layout.scaled(OldMaidHandLayout.tableMinHeight))
        .accessibilityElement(children: .combine)
    }

    /// 直前の「引く」のうち、あなたが関わったもの。あなたが引かれた札は見えるので名前を出す。
    private var lastTransferNote: String? {
        guard let transfer = model.game?.lastTransfer else { return nil }
        if transfer.from == OldMaidModel.humanIndex {
            return tr("%1$@があなたの%2$@を引いた", model.playerName(transfer.to),
                      OldMaidAccessibility.cardName(transfer.card))
        }
        if transfer.to == OldMaidModel.humanIndex {
            return transfer.paired
                ? tr("あなたは%@を引いてペアで捨てた", OldMaidAccessibility.cardName(transfer.card))
                : tr("あなたは%@を引いた", OldMaidAccessibility.cardName(transfer.card))
        }
        return nil
    }

    // MARK: - 手札

    private var handArea: some View {
        let lastDrawn = model.lastDrawnCardID
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(tr("あなた（残り%lld枚）", model.playerHand.count))
                    .themeBody(13)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    model.shuffleHand()
                } label: {
                    Label(tr("シャッフル"), systemImage: "shuffle")
                        .scaledFont(12, weight: .bold, design: .rounded)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 10)
                        .frame(minHeight: OldMaidHandLayout.minimumTapTarget)
                }
                .buttonStyle(.pop)
                .foregroundStyle(model.isJokerWatched ? Theme.coral : Theme.teal)
                .disabled(!model.canShuffle)
                .accessibilityHint(tr("手札の並びを混ぜます。ジョーカーの場所を覚えられなくなります"))
            }
            // 手札は最大 14 枚。7 列 × 2 段で収まるが、縦が足りない画面では枠の中でスクロールさせる。
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: OldMaidHandLayout.columnSpacing),
                                   count: OldMaidHandLayout.columns),
                    spacing: OldMaidHandLayout.rowSpacing
                ) {
                    ForEach(model.playerHand) { card in
                        let isLastDrawn = card.id == lastDrawn
                        OldMaidCardFaceView(card: card, highlighted: isLastDrawn)
                            .frame(maxWidth: .infinity)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(OldMaidAccessibility.handCardLabel(card, isLastDrawn: isLastDrawn))
                    }
                }
                // 縦の ScrollView は中身の理想幅を提案してくるので、幅を枠に固定する。
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                // 引いた札が増える・ペアで消える・混ぜて並びが変わる変化を演出する（#195）。
                .gameAnimation(.easeInOut(duration: 0.2), value: model.playerHand)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.isJokerWatched {
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .scaledFont(11, weight: .bold)
                    Text(tr("右端のジョーカーを見られています。シャッフルしよう"))
                        .scaledFont(11, weight: .bold, design: .rounded)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(Theme.coral)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, OldMaidHandLayout.horizontalPadding).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .playing:
            actionButton(drawButtonTitle, role: .primary, disabled: !model.canDraw) {
                model.drawSelected()
                runCPU()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .result:
            actionButton(tr("次のゲーム"), role: .primary) {
                model.startGame()
                runCPU()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        }
    }

    private var drawButtonTitle: String {
        guard model.isPlayerTurn else { return tr("CPUの番です") }
        return model.selectedID == nil ? tr("引く札を選ぶ") : tr("この札を引く")
    }

    // MARK: - リザルト

    private var resultCard: some View {
        let won = model.reviewOutcome == .win
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: won ? "crown.fill" : "theatermasks.fill")
                    .scaledFont(20)
                    .foregroundStyle(won ? Theme.yellow : Theme.purple)
                Text(won ? tr("あなたの勝ち！") : tr("ジョーカーが残った…あなたの負け"))
                    .scaledFont(17, weight: .black, design: .rounded)
                    .foregroundStyle(won ? Theme.teal : Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
            }
            VStack(spacing: 4) {
                ForEach(Array((model.game?.ranking ?? []).enumerated()), id: \.element) { place, player in
                    let isLoser = player == model.loser
                    HStack(spacing: 8) {
                        Text(isLoser ? tr("負け") : tr("%lld位", place + 1))
                            .scaledFont(12, weight: .black, design: .rounded)
                            // 1 位だけ差し色の面。他は濃いグレーの面なので文字色を分ける（#220）。
                            .foregroundStyle(place == 0 ? Theme.onAccent : .white)
                            .frame(width: 44)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(place == 0 ? Theme.Fill.yellow
                                                       : (isLoser ? Theme.Fill.purple : Theme.fillMuted)))
                        Text(model.playerName(player))
                            .scaledFont(13, weight: .bold, design: .rounded)
                            .foregroundStyle(player == OldMaidModel.humanIndex ? Theme.coral : Theme.ink)
                        Spacer()
                        if isLoser {
                            OldMaidCardFaceView(card: .joker, highlighted: false, size: .mini)
                                .accessibilityLabel(tr("ジョーカーが残った"))
                        } else {
                            Text(tr("あがり"))
                                .scaledFont(12, weight: .semibold, design: .rounded)
                                .foregroundStyle(Theme.inkSub)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            // 「今回の結果」を上、「通算」を下に置き、余りは 2 つの塊の**間**に集める（#193）。
            Spacer(minLength: 8)
            RecordLabel(model.recordResult)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 12)
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
        }
        .buttonStyle(GameButtonStyle(role: role, shape: .block))
        .disabled(disabled)
    }
}

// MARK: - 手札グリッドの寸法

/// 手札・伏せ札グリッドの寸法（大富豪 #195・いろリレーと同じ考え方）。見た目の札は 42pt のまま、
/// タップ判定だけを列いっぱいに広げる。
enum OldMaidHandLayout {
    static let columns = 7
    static let columnSpacing: CGFloat = 0
    static let rowSpacing: CGFloat = 6
    /// 手札カード（`popCard`）の内側の左右余白。
    static let horizontalPadding: CGFloat = 12
    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44
    /// CPU の番の卓の高さ（伏せ札 2 段ぶん）。番が替わるたびに卓の高さが跳ねないようにする。
    static let tableMinHeight: CGFloat = 132

    /// 画面幅 `screenWidth` のときの、伏せ札 1 枚あたりのタップ判定の幅。
    static func tapWidth(screenWidth: CGFloat) -> CGFloat {
        let available = screenWidth - Theme.pad * 2 - horizontalPadding * 2
        return (available - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns)
    }
}

// MARK: - 札（トランプ共通基盤）

/// 表向きの札。面・紙・ジョーカーの図案はトランプ共通基盤（`PlayingCardSurface` / `PlayingCardFace`・#397）。
struct OldMaidCardFaceView: View {
    enum Size {
        case small, mini
        /// small = 大富豪の手札と同じ 42×60。mini はリザルトの行に添える大きさ。
        var metrics: PlayingCardMetrics {
            switch self {
            case .small: return .compact
            case .mini:
                return PlayingCardMetrics(width: 24, height: 34, cornerRadius: Theme.cornerSmall / 3,
                                          rankFont: 9, suitFont: 9, pipSpacing: 0, backMotifFont: 10)
            }
        }
    }

    let card: OldMaidCard
    var highlighted: Bool
    var size: Size = .small
    // 別ファイル（遊び方の図）からも memberwise init で作るので private にしない。
    @Environment(\.adaptiveLayout) var layout

    private var metrics: PlayingCardMetrics { size.metrics.scaled(by: layout.elementScale) }

    var body: some View {
        ZStack {
            PlayingCardSurface(
                faceUp: true,
                cornerRadius: metrics.cornerRadius,
                border: highlighted ? Theme.coral : Color.gray.opacity(0.2),
                borderWidth: highlighted ? 2.5 : 0.5,
                shadowColor: highlighted ? Theme.coral.opacity(0.5) : .black.opacity(0.15),
                shadowRadius: highlighted ? 5 : 3
            )
            PlayingCardFace(figure: card.figure, metrics: metrics)
        }
        .frame(width: metrics.width, height: metrics.height)
    }
}

/// 伏せた札（相手の手札）。裏はトランプ共通基盤（`PlayingCardBack`）。
struct OldMaidCardBackView: View {
    var selected: Bool
    // 別ファイル（遊び方の図）からも memberwise init で作るので private にしない。
    @Environment(\.adaptiveLayout) var layout

    private var metrics: PlayingCardMetrics { PlayingCardMetrics.compact.scaled(by: layout.elementScale) }

    var body: some View {
        ZStack {
            PlayingCardSurface(
                faceUp: false,
                cornerRadius: metrics.cornerRadius,
                border: selected ? Theme.coral : Color.gray.opacity(0.2),
                borderWidth: selected ? 2.5 : 0.5,
                shadowColor: selected ? Theme.coral.opacity(0.6) : .black.opacity(0.15),
                shadowRadius: selected ? 6 : 3
            )
            PlayingCardBack(metrics: metrics)
        }
        .frame(width: metrics.width, height: metrics.height)
    }
}

// MARK: - CPU の顔（コード描画）

/// CPU の顔。丸い顔に目と口だけを描く（外部の画像は使わない）。
///
/// - neutral: 口は真一文字（ポーカーフェイス）
/// - smile: 目を細めて口角を上げる（にやり）
/// - worried: 眉を八の字にして口をゆがめ、汗を 1 滴（ひやり）
struct OldMaidFaceView: View {
    let face: OldMaidFace
    /// 抜けた CPU は顔を薄くする。
    var isOut = false

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - s) / 2, y: (size.height - s) / 2)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * s, y: origin.y + y * s) }
            let line = StrokeStyle(lineWidth: max(1.5, s * 0.06), lineCap: .round, lineJoin: .round)

            let head = Path(ellipseIn: CGRect(x: origin.x + s * 0.04, y: origin.y + s * 0.04, width: s * 0.92, height: s * 0.92))
            ctx.fill(head, with: .color(Theme.Fill.yellow))
            ctx.stroke(head, with: .color(Theme.Fill.yellow.opacity(0.6)), lineWidth: 1)
            let ink = GraphicsContext.Shading.color(Theme.onAccent)

            switch face {
            case .smile:
                // 細めた目（上に弧）。
                for x in [0.33, 0.67] {
                    var eye = Path()
                    eye.move(to: p(x - 0.09, 0.42))
                    eye.addQuadCurve(to: p(x + 0.09, 0.42), control: p(x, 0.32))
                    ctx.stroke(eye, with: ink, style: line)
                }
                var mouth = Path()
                mouth.move(to: p(0.3, 0.62))
                mouth.addQuadCurve(to: p(0.72, 0.58), control: p(0.52, 0.8))
                ctx.stroke(mouth, with: ink, style: line)
            case .worried:
                // 八の字の眉と、ゆがんだ口。右上に汗。
                var brows = Path()
                brows.move(to: p(0.22, 0.32)); brows.addLine(to: p(0.4, 0.27))
                brows.move(to: p(0.78, 0.32)); brows.addLine(to: p(0.6, 0.27))
                ctx.stroke(brows, with: ink, style: line)
                for x in [0.33, 0.67] {
                    ctx.fill(Path(ellipseIn: CGRect(x: origin.x + (x - 0.05) * s, y: origin.y + 0.38 * s,
                                                    width: s * 0.1, height: s * 0.12)), with: ink)
                }
                var mouth = Path()
                mouth.move(to: p(0.32, 0.7))
                mouth.addQuadCurve(to: p(0.5, 0.66), control: p(0.41, 0.62))
                mouth.addQuadCurve(to: p(0.68, 0.7), control: p(0.59, 0.74))
                ctx.stroke(mouth, with: ink, style: line)
                var drop = Path()
                drop.move(to: p(0.86, 0.12))
                drop.addQuadCurve(to: p(0.86, 0.34), control: p(0.98, 0.3))
                drop.addQuadCurve(to: p(0.86, 0.12), control: p(0.74, 0.3))
                ctx.fill(drop, with: .color(Theme.teal))
            case .neutral:
                for x in [0.33, 0.67] {
                    ctx.fill(Path(ellipseIn: CGRect(x: origin.x + (x - 0.05) * s, y: origin.y + 0.36 * s,
                                                    width: s * 0.1, height: s * 0.12)), with: ink)
                }
                var mouth = Path()
                mouth.move(to: p(0.34, 0.68)); mouth.addLine(to: p(0.66, 0.68))
                ctx.stroke(mouth, with: ink, style: line)
            }
        }
        .opacity(isOut ? 0.35 : 1)
    }
}

// MARK: - 新規対局のシート

struct OldMaidNewGameSheet: View {
    @State private var level: Int
    let onStart: (Int) -> Void
    let onCancel: () -> Void

    init(aiLevel: Int, onStart: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        _level = State(initialValue: aiLevel)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        GameSetupSheet(
            kind: .versus,
            onStart: { onStart(level) }, onCancel: onCancel
        ) {
            GameSetupSection(tr("CPUの強さ")) {
                // 説明は `OldMaidTuning` の中身と一致させる（#416）。
                CPUStrengthPicker(level: $level, details: [
                    tr("顔に出やすく、置き場所は見ていない"), tr("ときどき顔に出て、置き場所を少し覚える"),
                    tr("あまり顔に出ず、置き場所をよく覚える"), tr("顔に出ず、置き場所をほぼ覚える"),
                ])
            }
        }
    }
}
