import SwiftUI
import Core

public struct HeartsView: View {
    @State private var model: HeartsModel
    private let services: GameServices
    @State private var showNewGame = false
    /// 操作の後に CPU の手番を回すタスク。画面を離れたらキャンセルする（いろリレー・CodeRabbit 指摘 PR #1339 と同じ）。
    /// ボタンから起こした非構造化タスクは View のライフサイクルで止まらないので、離れたら自分で止める。
    @State private var cpuTask: Task<Void, Never>?
    /// 画面の広さ（#458）。札と同じ倍率で場の枠を拡大するために読む。
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: HeartsModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            cpuRow
            // 手の終わり・決着では場も手札も要らないので、代わりに点の一覧を出す。
            // 縦の余りは `Spacer` ではなく手札 / 点の一覧のカード自身に吸わせる（大富豪 #193 と同じ）。
            switch model.phase {
            case .handResult, .result:
                scoreCard
                    .transition(.opacity)
            case .idle, .passing, .playing:
                trickArea
                    .transition(.opacity)
                handArea
                    .transition(.opacity)
            }
            HowToPlayHint(.hearts, playLog: services.playLog)
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .result)
            BannerSlot(ads: services.ads)
        }
        // 局面 → 点の一覧の差し替えは、残り続ける親に置かないと `transition` が効かない（#195）。
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        .padding(Theme.pad)
        .gameChrome(title: tr("ハーツ"), review: services.review,
                    newGame: GameChromeNewGame(.match) { showNewGame = true })
        .howToPlay(HowToPlayGuide.hearts.illustrated(HeartsHowToFigures.items)) { HeartsRuleSheet() }
        .sheet(isPresented: $showNewGame) {
            HeartsNewGameSheet(aiLevel: model.aiLevel) { level in
                cpuTask?.cancel()
                model.startMatch(aiLevel: level)
                showNewGame = false
            } onCancel: { showNewGame = false }
        }
        .onDisappear { cpuTask?.cancel() }
        .task {
            // 開幕のモーダルは置かず、卓を見せたまま配り始める（#192）。強さは「新規対局」から選び直せる。
            // 中断から戻ったときは init が局面まで復元しているので配り直さない。
            if model.phase == .idle { model.startMatch() }
            #if DEBUG
            // 撮影・動作確認用: `-heartsScenario queen|handResult|result` で局面を差し替える。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-heartsScenario"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
            }
            #endif
            // 中断から戻ったときに CPU の手番が止まったままにならないようにする。
            await model.runCPUTurnsIfNeeded()
        }
    }

    /// 人間の操作の後に CPU の手番を回す。前のタスクは止めてから起こす（走者は `withAITurnRunner` が 1 本に保つ）。
    private func runCPU() {
        cpuTask?.cancel()
        cpuTask = Task { await model.runCPUTurnsIfNeeded() }
    }

    // MARK: - ステータス

    private var statusBar: some View {
        HStack(spacing: 8) {
            Label(tr("%lld手目", max(model.handNumber, 1)), systemImage: "number")
                .themeBody(13)
                .foregroundStyle(Theme.inkSub)
            Text(tr("%lld点で終了", HeartsRules.targetScore))
                .scaledFont(11, weight: .semibold, design: .rounded)
                .foregroundStyle(Theme.inkSub)
            Spacer()
            Text(turnLabel)
                .scaledFont(12, weight: .bold, design: .rounded)
                .foregroundStyle(model.isPlayerTurn || model.phase == .passing ? Theme.tealText : Theme.inkSub)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var turnLabel: String {
        switch model.phase {
        case .idle:       return tr("開始待ち")
        case .passing:    return tr("渡す札を選ぶ")
        case .handResult: return tr("この手の結果")
        case .result:     return tr("決着")
        case .playing:
            if model.isTrickComplete, let winner = model.trickLeader {
                return tr("%@が取ります", model.playerName(winner))
            }
            return model.isPlayerTurn ? tr("あなたの番") : tr("%@の番", model.playerName(model.currentPlayer))
        }
    }

    // MARK: - CPU

    private var cpuRow: some View {
        HStack(spacing: 8) {
            ForEach(1..<HeartsModel.playerCount, id: \.self) { index in
                cpuCard(index)
            }
        }
    }

    private func cpuCard(_ index: Int) -> some View {
        let isCurrent = model.phase == .playing && !model.isTrickComplete && model.currentPlayer == index
        return VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .scaledFont(12, weight: .bold)
                    .foregroundStyle(isCurrent ? Theme.coralText : Theme.inkSub)
                Text(model.playerName(index))
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.ink)
                Text(seatLabel(index))
                    .scaledFont(10, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
            }
            Text(tr("この手 %lld点", model.takenPoints[index]))
                .scaledFont(11, weight: .bold, design: .rounded)
                .foregroundStyle(model.takenPoints[index] > 0 ? Theme.coralText : Theme.inkSub)
            Text(tr("合計 %lld点", model.totals[index]))
                .scaledFont(11, weight: .semibold, design: .rounded)
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 6)
        .popCard(corner: Theme.cornerSmall)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .strokeBorder(isCurrent ? Theme.coral : Color.clear, lineWidth: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HeartsAccessibility.scoreLabel(
            name: model.playerName(index), handPoints: model.takenPoints[index], total: model.totals[index]
        ))
    }

    /// 席の向き（1 = 左・2 = 向かい・3 = 右）。渡す相手（左）が分かるように出す。
    private func seatLabel(_ index: Int) -> String {
        switch index {
        case 1:  return tr("左")
        case 2:  return tr("向かい")
        default: return tr("右")
        }
    }

    // MARK: - 場

    /// 場。自分を下に、左（CPU1）・向かい（CPU2）・右（CPU3）が出した札を十字に並べる。
    private var trickArea: some View {
        let metrics = PlayingCardMetrics.compact.scaled(by: layout.elementScale)
        let complete = model.isTrickComplete
        let leader = model.trickLeader
        return ZStack {
            heartsChip
            trickSlot(2, metrics: metrics, highlighted: complete && leader == 2)
                .offset(y: -metrics.height * 0.62)
            trickSlot(1, metrics: metrics, highlighted: complete && leader == 1)
                .offset(x: -metrics.width * 1.6)
            trickSlot(3, metrics: metrics, highlighted: complete && leader == 3)
                .offset(x: metrics.width * 1.6)
            trickSlot(0, metrics: metrics, highlighted: complete && leader == 0)
                .offset(y: metrics.height * 0.62)
        }
        .frame(maxWidth: .infinity)
        .frame(height: metrics.height * 2.35)
        .padding(.vertical, 6)
        .popCard(corner: Theme.cornerSmall)
        .gameAnimation(.easeInOut(duration: 0.18), value: model.currentTrick)
        // 場は「誰が何を出したか」「いま誰が取りそうか」が分かればよいので 1 要素にまとめる（#188）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HeartsAccessibility.trickLabel(model.currentTrick))
    }

    @ViewBuilder
    private func trickSlot(_ player: Int, metrics: PlayingCardMetrics, highlighted: Bool) -> some View {
        if let card = model.trickCard(of: player) {
            HeartsCardView(card: card, metrics: metrics, selected: highlighted)
                .transition(.scale.combined(with: .opacity))
        } else {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .strokeBorder(Theme.inkSub.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: metrics.width, height: metrics.height)
        }
    }

    /// 場の真ん中。ハートが割れたかどうか（割れるまでハートを先頭に出せない）。
    private var heartsChip: some View {
        VStack(spacing: 2) {
            Image(systemName: model.heartsBroken ? "suit.heart.fill" : "suit.heart")
                .scaledFont(16, weight: .bold)
                .foregroundStyle(PlayingCardInk.red)
            Text(model.heartsBroken ? tr("ハート解禁") : tr("ハートまだ"))
                .scaledFont(10, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.inkSub)
        }
    }

    // MARK: - 手札

    private var handArea: some View {
        // 1 枚ごとに引くと合法手の探索が手札の枚数ぶん走るので、ここで 1 回だけ求める（#190）。
        let playable = model.playableCardIDs
        let isPassing = model.phase == .passing
        return VStack(spacing: 6) {
            HStack {
                Text(tr("あなた"))
                    .themeBody(13)
                    .foregroundStyle(Theme.ink)
                Text(tr("この手 %lld点", model.takenPoints[HeartsModel.humanIndex]))
                    .scaledFont(11, weight: .bold, design: .rounded)
                    .foregroundStyle(model.takenPoints[HeartsModel.humanIndex] > 0 ? Theme.coralText : Theme.inkSub)
                Spacer()
                Text(tr("合計 %lld点", model.totals[HeartsModel.humanIndex]))
                    .scaledFont(11, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HeartsAccessibility.scoreLabel(
                name: model.playerName(HeartsModel.humanIndex),
                handPoints: model.takenPoints[HeartsModel.humanIndex], total: model.totals[HeartsModel.humanIndex]
            ))
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: HeartsHandLayout.columnSpacing),
                    count: HeartsHandLayout.columns
                ),
                spacing: HeartsHandLayout.rowSpacing
            ) {
                ForEach(model.playerHand) { card in
                    let isSelected = isPassing ? model.passSelection.contains(card.id) : model.selectedID == card.id
                    let hint = model.hint(for: card, playable: playable)
                    let isReceived = model.receivedIDs.contains(card.id)
                    HeartsCardView(
                        card: card, metrics: PlayingCardMetrics.compact.scaled(by: layout.elementScale),
                        selected: isSelected, hint: hint, received: isReceived
                    )
                    .offset(y: isSelected ? -6 : 0)
                    .gameAnimation(.spring(response: 0.2), value: isSelected)
                    // 見える札は 42pt のまま、タップ判定だけを列いっぱいに広げて 44pt 以上にする（#195）。
                    .frame(maxWidth: .infinity, minHeight: HeartsHandLayout.minimumTapTarget)
                    .contentShape(Rectangle())
                    .onTapGesture { tap(card) }
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(HeartsAccessibility.handCardLabel(
                        card, isSelected: isSelected, isReceived: isReceived, hint: hint
                    ))
                    .accessibilityHint(tr("ダブルタップで選択を切り替えます"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { tap(card) }
                    .disabled(!(isPassing || model.isPlayerTurn))
                }
            }
            .frame(maxWidth: .infinity)
            // 出した札が消える / 受け取った札が増える変化を演出する（#195）。
            .gameAnimation(.easeInOut(duration: 0.18), value: model.playerHand)
            Spacer(minLength: 0)
            hintLine(playable: playable)
        }
        .padding(.horizontal, HeartsHandLayout.horizontalPadding).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .popCard(corner: Theme.cornerSmall)
    }

    private func tap(_ card: HeartsCard) {
        if model.phase == .passing {
            model.togglePass(card)
        } else {
            model.toggleSelection(card)
        }
    }

    /// 手札の下に出す 1 行の案内（#190）。
    @ViewBuilder
    private func hintLine(playable: Set<Int>) -> some View {
        let message: String? = {
            switch model.phase {
            case .passing:
                return tr("左のCPU1へ渡す札を3枚選んでください（%lld/3）", model.passSelection.count)
            case .playing where model.isPlayerTurn:
                if model.trickNumber == 0, model.currentTrick.isEmpty { return tr("最初はクラブの2から出します") }
                if model.currentTrick.isEmpty, !model.heartsBroken, playable.count < model.playerHand.count {
                    return tr("ハートは、場に出るまで先頭に出せません")
                }
                if let lead = model.currentTrick.first?.card.suit, model.playerHand.contains(where: { $0.suit == lead }) {
                    return tr("出された札と同じスートを出します")
                }
                if !model.currentTrick.isEmpty { return tr("同じスートが無いので、どの札でも出せます") }
                return nil
            default:
                return nil
            }
        }()
        if let message {
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .scaledFont(11, weight: .bold)
                Text(message)
                    .scaledFont(11, weight: .bold, design: .rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Theme.coralText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .passing:
            actionButton(tr("CPU1へ3枚渡す"), role: .primary, disabled: !model.canConfirmPass) {
                model.confirmPass()
                runCPU()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .playing:
            actionButton(model.selectedID == nil ? tr("札を選ぶ") : tr("出す"), role: .primary,
                         disabled: !model.canPlaySelection) {
                model.playSelected()
                runCPU()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .handResult:
            actionButton(tr("次の手へ"), role: .primary) {
                model.nextHand()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .result:
            actionButton(tr("もう一回"), role: .primary) {
                model.startMatch()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        }
    }

    // MARK: - 点の一覧（手の終わり・決着）

    private var scoreCard: some View {
        let isFinal = model.phase == .result
        let order = isFinal ? model.ranking : Array(0..<HeartsModel.playerCount)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isFinal ? (model.playerPlace == 0 ? "crown.fill" : "flag.checkered") : "suit.heart.fill")
                    .scaledFont(20)
                    .foregroundStyle(isFinal && model.playerPlace == 0 ? Theme.yellowText : PlayingCardInk.red)
                Text(scoreHeadline)
                    .scaledFont(17, weight: .black, design: .rounded)
                    .foregroundStyle(isFinal && model.playerPlace == 0 ? Theme.tealText : Theme.ink)
                Spacer()
            }
            HStack {
                Spacer()
                Text(tr("この手"))
                    .frame(width: 64, alignment: .trailing)
                Text(tr("合計"))
                    .frame(width: 64, alignment: .trailing)
            }
            .scaledFont(11, weight: .semibold, design: .rounded)
            .foregroundStyle(Theme.inkSub)
            .accessibilityHidden(true)
            VStack(spacing: 6) {
                ForEach(order, id: \.self) { player in
                    scoreRow(player, isFinal: isFinal)
                }
            }
            // 「今回の結果」を上、「通算」を下に置き、余りは 2 つの塊の**間**に集める（#193）。
            Spacer(minLength: 8)
            if isFinal {
                RecordLabel(model.recordResult)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(tr("だれかが%lld点に届いたら終了。合計の少ない人が勝ちです", HeartsRules.targetScore))
                    .scaledFont(11, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    private func scoreRow(_ player: Int, isFinal: Bool) -> some View {
        let place = HeartsRules.place(of: player, totals: model.totals)
        return HStack(spacing: 8) {
            if isFinal {
                Text(tr("%lld位", place + 1))
                    .scaledFont(12, weight: .black, design: .rounded)
                    // 1 位だけ差し色の面。他は濃いグレーの面なので文字色を分ける（#220）。
                    .foregroundStyle(place == 0 ? Theme.onAccent : .white)
                    .frame(width: 44)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(place == 0 ? Theme.Fill.yellow : Theme.fillMuted))
            }
            Text(model.playerName(player))
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(player == HeartsModel.humanIndex ? Theme.coralText : Theme.ink)
            Spacer()
            Text(tr("%lld点", model.takenPoints[player]))
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(model.takenPoints[player] > 0 ? Theme.coralText : Theme.inkSub)
                .frame(width: 64, alignment: .trailing)
            Text(tr("%lld点", model.totals[player]))
                .scaledFont(13, weight: .black, design: .rounded)
                .foregroundStyle(Theme.ink)
                .frame(width: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HeartsAccessibility.scoreLabel(
            name: model.playerName(player), handPoints: model.takenPoints[player], total: model.totals[player]
        ))
    }

    private var scoreHeadline: String {
        guard model.phase == .result else { return tr("%lld手目の結果", model.handNumber) }
        guard let winner = model.ranking.first else { return tr("決着") }
        if model.playerPlace == 0 { return tr("あなたの勝ち！") }
        return tr("%@の勝ち", model.playerName(winner))
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

/// 手札グリッドの寸法（大富豪 #195・いろリレーと同じ考え方）。13 枚を 7 列 × 2 段に並べる。
/// 見た目の札は 42pt のまま、タップ判定だけを列いっぱいに広げる。
enum HeartsHandLayout {
    static let columns = 7
    static let columnSpacing: CGFloat = 0
    static let rowSpacing: CGFloat = 8
    /// 手札カード（`popCard`）の内側の左右余白。
    static let horizontalPadding: CGFloat = 12
    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 画面幅 `screenWidth` のときの、手札 1 枚あたりのタップ判定の幅。
    static func tapWidth(screenWidth: CGFloat) -> CGFloat {
        let available = screenWidth - Theme.pad * 2 - horizontalPadding * 2
        return (available - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns)
    }
}

// MARK: - 札

extension HeartsCard {
    /// トランプ共通基盤（#397）に渡す描画の値。ハーツの A（14）は面の表記では 1。
    public var figure: PlayingCardFigure {
        let suit: PlayingCardSuit
        switch self.suit {
        case .club:    suit = .club
        case .diamond: suit = .diamond
        case .spade:   suit = .spade
        case .heart:   suit = .heart
        }
        return .pip(suit: suit, rank: rank == 14 ? 1 : rank)
    }
}

/// 札 1 枚。外形・面はトランプ共通基盤（`PlayingCardSurface`・`PlayingCardFace`・#397）で描き、
/// ハーツ独自の印（点の札の小さな点数・受け取った札の印）だけを上に重ねる。
struct HeartsCardView: View {
    let card: HeartsCard
    let metrics: PlayingCardMetrics
    var selected: Bool = false
    var hint: HeartsCardHint = .none
    var received: Bool = false

    /// 出せない札は色に頼らず**明度**でも落として区別する。
    private var isDimmed: Bool { hint == .unplayable && !selected }

    private var borderColor: Color {
        if selected { return Theme.coral }
        if hint == .playable { return Theme.teal }
        return Color.gray.opacity(0.2)
    }

    private var borderWidth: CGFloat {
        if selected { return 2.5 }
        return hint == .playable ? 2 : 0.5
    }

    var body: some View {
        ZStack {
            PlayingCardSurface(
                cornerRadius: metrics.cornerRadius,
                border: borderColor,
                borderWidth: borderWidth,
                shadowColor: selected ? Theme.coral.opacity(0.6) : .black.opacity(0.15),
                shadowRadius: selected ? 6 : 3
            )
            PlayingCardFace(figure: card.figure, metrics: metrics)
            if card.isQueenOfSpades {
                // 13 点の札は小さな点数で目立たせる（取ってはいけない札がひと目で分かる）。
                Text(verbatim: "13")
                    .scaledFont(8, weight: .black, design: .rounded, maxScale: 1.1)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.Fill.coral))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(2)
                    .accessibilityHidden(true)
            }
            if received {
                Image(systemName: "arrow.down.circle.fill")
                    .scaledFont(10, weight: .bold, maxScale: 1.1)
                    .foregroundStyle(Theme.tealText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(2)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
        .opacity(isDimmed ? 0.4 : 1)
    }
}

// MARK: - New Game Sheet

struct HeartsNewGameSheet: View {
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
            discardsProgress: true,
            onStart: { onStart(level) }, onCancel: onCancel
        ) {
            GameSetupSection(tr("CPUの強さ")) {
                // 説明は `HeartsCPU` の中身と一致させる（#416）。
                CPUStrengthPicker(level: $level, details: [
                    tr("でたらめに出す"), tr("小さい札から出す"), tr("取らないように出し、点を押し付ける"), tr("出た札を覚えてクイーンを追い出す"),
                ])
            }
        }
    }
}

// MARK: - Rule Sheet

struct HeartsRuleSheet: View {
    static var rules: [(String, String)] { [
        (tr("ゲームの流れ"), tr("CPU3人と対戦します。52枚を13枚ずつ配り、1人1枚ずつ順に出して、いちばん強い札を出した人が4枚を取ります。取った人から次を出します")),
        (tr("渡す"), tr("配られたら、左どなりへ3枚渡し、右どなりから3枚受け取ります（毎回左へ）")),
        (tr("最初の1枚"), tr("クラブの2を持っている人が、クラブの2から出します。1巡目はハートとスペードのQを出せません（それしか無いときは出せます）")),
        (tr("同じスート"), tr("最初に出された札と同じスートを持っていれば、必ずそれを出します。無ければどの札でも出せます")),
        (tr("強さ"), tr("最初に出されたスートの中で、数字の大きい札が強い（Aがいちばん強い）。ほかのスートの札は勝てません")),
        (tr("点"), tr("取った札のハートは1枚1点、スペードのQは13点。点は少ないほど良い")),
        (tr("ハートを先に出す"), tr("ハートは、誰かが場にハートを出すまで先頭に出せません（手札がハートだけなら出せます）")),
        (tr("終わり"), tr("13巡で1手が終わり、点を合計します。だれかが50点に届いた手で終了し、合計の少ない人が勝ちです")),
        (tr("全部取り"), tr("ハートを全部とスペードのQを1人で取っても、特別な扱いはありません（26点のまま）")),
    ] }

    var body: some View {
        RuleListSheet(rules: Self.rules)
    }
}
