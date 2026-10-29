import SwiftUI
import Core

public struct HeartsView: View {
    @State private var model: HeartsModel
    private let services: GameServices
    @State private var showNewGame = false
    /// 対局中に開ける札の強さ・点数の早見表（#2788）。
    @State private var showReference = false
    /// 遊び方（図で見る遊び方を含む）を開いているか。開いているあいだ CPU の手番を止める（#2827）。
    @State private var isHowToPlayOpen = false
    /// 操作の後に CPU の手番を回すタスク。画面を離れたらキャンセルする（いろリレー・CodeRabbit 指摘 PR #1339 と同じ）。
    /// ボタンから起こした非構造化タスクは View のライフサイクルで止まらないので、離れたら自分で止める。
    @State private var cpuTask: Task<Void, Never>?
    /// 渡す場面のヒントの広告（無料 3 回を使い切ったあと 1 本につき 1 回・#3003）。
    @State private var hintRescue = RewardedRescue()
    /// 画面の広さ（#458）。広い画面（iPad）では札の拡大に上限を掛けるのに読む。
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: HeartsModel(services: services))
    }

    public var body: some View {
        // レイアウトパターン A（全画面・会長 QA 2026-10-23・#2531）: 大富豪・いろリレーと同じく、フェルトを画面全体に敷き、
        // ヘッダーは 1 行（戻る・ハーツ・手数と終了点と手番の札・？・＋）、バナーは画面最下部。
        // 白い札（ステータスの帯・CPU・場・手札・操作欄）はやめてフェルトに直に置き、CPU の席は共通部品（`OpponentSeat`）。
        GeometryReader { geometry in
            let metrics = HeartsLayoutA.metrics(screenWidth: geometry.size.width, elementScale: layout.elementScale)
            VStack(spacing: HeartsLayoutA.spacing) {
                cpuRow(metrics)
                // 手の終わり・決着では場も手札も要らないので、代わりに点の一覧を出す。
                // 縦の余りは `Spacer` ではなく場 / 点の一覧自身に吸わせる（大富豪 #193 と同じ）。
                switch model.phase {
                case .handResult, .result:
                    scoreCard
                        .transition(.opacity)
                case .idle, .passing, .playing:
                    trickArea(metrics)
                        .transition(.opacity)
                    handArea(metrics)
                        .transition(.opacity)
                }
                HowToPlayHint(.hearts, playLog: services.playLog)
                actionArea
                RecommendationSlot(services: services, isFinished: model.phase == .result)
            }
            // 局面 → 点の一覧の差し替えは、残り続ける親に置かないと `transition` が効かない（#195）。
            .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
            // 左右 8pt（全画面の枠の値）。上下はヘッダーの余白 4 とバナーの帯の余白 8 に足す分。
            .padding(.horizontal, HeartsLayoutA.sideInset)
            .padding(.vertical, HeartsLayoutA.verticalInset)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        // 手数・終了点・手番は、ヘッダー下の帯ではなくヘッダーの行の札に置く（A の「1 行のヘッダー」）。
        .gameChrome(title: tr("ハーツ"), review: services.review, fullScreen: .felt, ads: services.ads,
                    reference: GameChromeReference(tr("札の強さと点数")) { showReference = true },
                    newGame: GameChromeNewGame(.match) { showNewGame = true }) {
            statusChips
        }
        .howToPlay(HowToPlayGuide.hearts.illustrated(HeartsHowToFigures.items).onboarding(HeartsOnboarding.guide),
                   onPresent: { isHowToPlayOpen = true; cpuTask?.cancel() },
                   onDismiss: { isHowToPlayOpen = false; runCPU() }) { HeartsRuleSheet() }
        // 早見表を開いているあいだは CPU の手番を止め、閉じたら続きを回す（読んでいるあいだに場が進まないように）。
        .sheet(isPresented: $showReference) {
            NavigationStack {
                HeartsReferenceSheet()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(tr("閉じる")) { showReference = false }.fontWeight(.semibold)
                        }
                    }
            }
        }
        .onChange(of: showReference) { _, isOpen in
            if isOpen { cpuTask?.cancel() } else { runCPU() }
        }
        // 新規対局シートにも図で見る遊び方の入口があるので、開いているあいだは手番を止める（#2827）。
        .onChange(of: showNewGame) { _, isOpen in
            if isOpen { cpuTask?.cancel() } else { runCPU() }
        }
        .sheet(isPresented: $showNewGame) {
            HeartsNewGameSheet(aiLevel: model.aiLevel) { level in
                cpuTask?.cancel()
                model.startMatch(aiLevel: level)
                showNewGame = false
            } onCancel: { showNewGame = false }
        }
        .rewardedRescueAlerts(
            hintRescue,
            notEarned: tr("ヒントを使えませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("ヒントを出せませんでした"),
                message: tr("広告を見ているあいだに次の手が始まったため、ヒントを出せませんでした。\nヒントの残り回数は減っていません。")
            )
        )
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
            // 撮影用（#2788）: 早見表だけを開く。
            if args.contains("-heartsReference") { showReference = true }
            #endif
            // 中断から戻ったときに CPU の手番が止まったままにならないようにする。
            // 早見表で止められるよう、操作の後と同じ cpuTask で回す（#2788）。
            runCPU()
        }
    }

    /// 人間の操作の後に CPU の手番を回す。前のタスクは止めてから起こす（走者は `withAITurnRunner` が 1 本に保つ）。
    private func runCPU() {
        cpuTask?.cancel()
        cpuTask = Task { await model.runCPUTurnsIfNeeded() }
    }

    // MARK: - ステータス（ヘッダーの行の札）

    /// 手数・終了点・手番。ヘッダーの残りの幅に収まらないとき（英語の iPhone SE など）は終了点、次に手数を落とす。
    /// 文字色（白）は全画面の枠が配る。手番の札（`TurnBadge`）は対戦ゲーム共通の色（#1419）。
    private var statusChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                handNumberLabel
                targetLabel
                turnChip
            }
            HStack(spacing: 8) {
                handNumberLabel
                turnChip
            }
            turnChip
        }
    }

    private var handNumberLabel: some View {
        Label(tr("%lld手目", max(model.handNumber, 1)), systemImage: "number")
            .themeBody(13, maxScale: Self.seatTextMaxScale)
    }

    private var targetLabel: some View {
        Text(tr("%lld点で終了", HeartsRules.targetScore))
            .scaledFont(11, weight: .semibold, design: .rounded)
    }

    /// いま動いている（または場を取る）CPU。手番の札にその席のアイコンを添える（席に名前を出さないため）。
    private var activeCPU: Int? {
        guard model.phase == .playing else { return nil }
        let player = model.isTrickComplete ? model.trickLeader : model.currentPlayer
        guard let player, player != HeartsModel.humanIndex else { return nil }
        return player
    }

    private var turnChip: some View {
        HStack(spacing: 4) {
            if let cpu = activeCPU {
                OpponentSeatIcon(index: cpu, diameter: layout.scaled(22))
            }
            TurnBadge(turnLabel, kind: turnKind)
        }
    }

    private var turnKind: TurnBadge.Kind {
        switch model.phase {
        case .idle, .handResult, .result: return .finished
        case .passing: return .you
        case .playing: return activeCPU == nil ? .you : .cpu
        }
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

    /// CPU の席・手札の見出しが文字サイズ設定で拡大する上限倍率（大富豪 #1782 と同じ）。
    private static let seatTextMaxScale: CGFloat = 1.6

    /// CPU 3 人の席（左から 左どなり・向かい・右どなり。場の十字の並びと同じ向き）。見せ方は大富豪・いろリレーと同じ
    /// 共通部品（`OpponentSeat`・#2531）: 色と記号の丸いアイコン・手番の黄色い輪・裏向きのトランプの束・残り枚数・吹き出し。
    private func cpuRow(_ metrics: HeartsLayoutA.Metrics) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(1..<HeartsModel.playerCount, id: \.self) { index in
                cpuSeat(index, metrics)
            }
        }
    }

    private func cpuSeat(_ index: Int, _ metrics: HeartsLayoutA.Metrics) -> some View {
        let isCurrent = model.phase == .playing && !model.isTrickComplete && model.currentPlayer == index
        let count = model.hands[index].count
        // ハーツは場の札が直前の手を見せるので、吹き出しにはこの手の点と合計点を出す（以前の白い札の 2・3 行目）。
        let handPoints = tr("この手 %lld点", model.takenPoints[index])
        let totalPoints = tr("合計 %lld点", model.totals[index])
        let points = "\(handPoints) / \(totalPoints)"
        var spoken = [HeartsAccessibility.scoreLabel(
            name: model.playerName(index), handPoints: model.takenPoints[index], total: model.totals[index]
        ), seatLabel(index)]
        // 手番は輪の色でしか示さないので、読み上げに「〜の番」まで入れる（大富豪 #2495 と同じ）。
        if isCurrent { spoken.append(tr("%@の番", model.playerName(index))) }
        let back = metrics.seatCardMetrics
        return OpponentSeat(
            index: index, diameter: metrics.seatDiameter, isCurrent: isCurrent, cardCount: count, lastAction: points,
            accessibilityLabel: spoken.joined(separator: " ")
        ) {
            OpponentCardFan(count: count, cardWidth: back.width, cardHeight: back.height) {
                // トランプの裏（藍の面 + 白い内枠 + スート印）。外形と面は共通基盤（#397）。
                ZStack {
                    PlayingCardSurface(faceUp: false, cornerRadius: back.cornerRadius, shadowRadius: 1)
                    PlayingCardBack(metrics: back)
                }
            }
        }
    }

    /// 席の向き（1 = 左・2 = 向かい・3 = 右）。渡す相手（左）が分かるように、場の十字の札に添える。
    private func seatLabel(_ index: Int) -> String {
        switch index {
        case 1:  return tr("左")
        case 2:  return tr("向かい")
        default: return tr("右")
        }
    }

    // MARK: - 場

    /// 場。自分を下に、左（CPU1）・向かい（CPU2）・右（CPU3）が出した札を十字に並べる。白い札は使わずフェルトに直に置く。
    /// 縦の余りはここが吸い、十字はその真ん中に置く（大富豪の場と同じ）。札は手札と同じ大きさまでで、
    /// 縦の短い画面（iPhone SE）では残りの高さに収まるよう小さくする。
    private func trickArea(_ metrics: HeartsLayoutA.Metrics) -> some View {
        // 札が 1 枚でも出ていれば、その時点で最も強い人を強調する（4 枚そろう前は暫定）。
        let leader = model.trickLeader
        return GeometryReader { proxy in
            let card = HeartsLayoutA.trickCard(hand: metrics.handCard, height: proxy.size.height)
            ZStack {
                heartsChip
                trickSlot(2, metrics: card, highlighted: leader == 2)
                    .offset(y: -card.height * HeartsLayoutA.trickVerticalOffset)
                trickSlot(1, metrics: card, highlighted: leader == 1)
                    .offset(x: -card.width * HeartsLayoutA.trickHorizontalOffset)
                trickSlot(3, metrics: card, highlighted: leader == 3)
                    .offset(x: card.width * HeartsLayoutA.trickHorizontalOffset)
                trickSlot(0, metrics: card, highlighted: leader == 0)
                    .offset(y: card.height * HeartsLayoutA.trickVerticalOffset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, minHeight: HeartsLayoutA.trickMinHeight, maxHeight: .infinity)
        .gameAnimation(.easeInOut(duration: 0.18), value: model.currentTrick)
        // 場は「誰が何を出したか」「いま誰が取りそうか」が分かればよいので 1 要素にまとめる（#188）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HeartsAccessibility.trickLabel(model.currentTrick))
    }

    @ViewBuilder
    private func trickSlot(_ player: Int, metrics: PlayingCardMetrics, highlighted: Bool) -> some View {
        Group {
            if let card = model.trickCard(of: player) {
                HeartsCardView(card: card, metrics: metrics, selected: highlighted)
                    .transition(.scale.combined(with: .opacity))
            } else {
                // 空き枠（破線の色は卓の上の色・`cardTableInk`）。
                CardSlot(metrics: metrics)
            }
        }
        // 席に名前を出さないので、CPU の札には席と同じアイコンを添えて、誰の札かを席と結ぶ（以前の「左・向かい・右」の代わり）。
        .overlay(alignment: .topLeading) {
            if player != HeartsModel.humanIndex {
                OpponentSeatIcon(index: player, diameter: HeartsLayoutA.trickIconDiameter)
                    .offset(x: -HeartsLayoutA.trickIconDiameter / 3, y: -HeartsLayoutA.trickIconDiameter / 3)
            }
        }
    }

    /// 場の真ん中。ハートが割れたかどうか（割れるまでハートを先頭に出せない）。
    private var heartsChip: some View {
        VStack(spacing: 2) {
            Image(systemName: model.heartsBroken ? "suit.heart.fill" : "suit.heart")
                .scaledFont(16, weight: .bold)
                .foregroundStyle(PlayingCardInk.red)
            CardTableInkReader { ink in
                Text(model.heartsBroken ? tr("ハート解禁") : tr("ハートまだ"))
                    .scaledFont(10, weight: .bold, design: .rounded)
                    .foregroundStyle(ink.label)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
    }

    // MARK: - 手札

    private func handArea(_ metrics: HeartsLayoutA.Metrics) -> some View {
        // 1 枚ごとに引くと合法手の探索が手札の枚数ぶん走るので、ここで 1 回だけ求める（#190）。
        let playable = model.playableCardIDs
        let isPassing = model.phase == .passing
        let human = HeartsModel.humanIndex
        return VStack(spacing: 6) {
            CardTableInkReader { ink in
                HStack {
                    Text(tr("あなた"))
                        .themeBody(13, maxScale: Self.seatTextMaxScale)
                        .foregroundStyle(ink.label)
                    Text(tr("この手 %lld点", model.takenPoints[human]))
                        .scaledFont(11, weight: .bold, design: .rounded)
                        .foregroundStyle(model.takenPoints[human] > 0 ? ink.label : ink.labelSub)
                    Spacer()
                    Text(tr("合計 %lld点", model.totals[human]))
                        .scaledFont(11, weight: .semibold, design: .rounded)
                        .foregroundStyle(ink.label)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HeartsAccessibility.scoreLabel(
                name: model.playerName(human), handPoints: model.takenPoints[human], total: model.totals[human]
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
                    HeartsCardView(card: card, metrics: metrics.handCard,
                                   selected: isSelected, hint: hint, received: isReceived)
                    .offset(y: isSelected ? -6 : 0)
                    .gameAnimation(.spring(response: 0.2), value: isSelected)
                    // 札は列幅 − 4pt。タップ判定は列いっぱい（44pt 以上・#195）。
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
            // 出した札が消える / 受け取った札が増える変化を演出する（#195）。
            .gameAnimation(.easeInOut(duration: 0.18), value: model.playerHand)
            hintLine(playable: playable)
        }
    }

    private func tap(_ card: HeartsCard) {
        if model.phase == .passing {
            model.togglePass(card)
        } else {
            model.toggleSelection(card)
        }
    }

    /// 手札の下に出す 1 行の案内（#190）。フェルトの上なので赤系ではなく卓の上の文字色（白系）で出す（大富豪と同じ）。
    /// CPU の番は案内が無くなるが、行の高さは取っておく（出すたびに手札が上下に跳ねないように）。
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
                if !model.currentTrick.isEmpty {
                    // 1 巡目だけは点の札（ハート・スペードの Q）を避ける（HeartsRules.legalPlays）。
                    return model.trickNumber == 0
                        ? tr("1巡目はハート・スペードのQを出せません（それしか無ければ出せます）")
                        : tr("同じスートが無いので、どの札でも出せます")
                }
                return nil
            default:
                return nil
            }
        }()
        return CardTableInkReader { ink in
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .scaledFont(11, weight: .bold)
                Text(message ?? " ")
                    .scaledFont(11, weight: .bold, design: .rounded)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(ink.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(message == nil ? 0 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHidden(message == nil)
    }

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .passing:
            HStack(spacing: 8) {
                passHintButton
                    .frame(maxWidth: 150)
                actionButton(tr("CPU1へ3枚渡す"), role: .primary, disabled: !model.canConfirmPass || hintRescue.isWatching) {
                    model.confirmPass()
                    runCPU()
                }
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

    // MARK: - 渡す場面のヒント（#3003）

    /// 「ヒント」ボタン。押すと渡すとよい 3 枚を光らせる（選ぶのはあなた）。
    /// 2 行目は他のゲームと同じ `GameActionBadge.hint`（無料の残り回数 / 0 回 ▶ 広告を見て +1）。
    private var passHintButton: some View {
        let badge = GameActionBadge.hint(totalRemaining: model.passHints.remaining, needsAd: model.needsAdForHint)
        return Button { requestPassHint() } label: {
            VStack(spacing: 0) {
                Label(tr("ヒント"), systemImage: "lightbulb.fill")
                    .themeBody(14)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let text = badge.text {
                    Text(badge.countText.map { "\($0) ▶ \(text)" } ?? text)
                        .scaledFont(10, weight: .bold, design: .rounded)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .buttonStyle(GameButtonStyle(role: .hint, shape: .block))
        .disabled(!model.canUseHint || hintRescue.isWatching)
        .accessibilityLabel(HeartsAccessibility.passHintLabel(
            remaining: model.passHints.freeRemaining, needsAd: model.needsAdForHint))
        .accessibilityHint(tr("渡すのにおすすめの3枚を光らせます。渡す札はあなたが選びます"))
    }

    /// 無料が残っていればそのまま示し、使い切っていれば広告を見たあとに示す（広告は押下起点・自動再生しない）。
    private func requestPassHint() {
        guard !hintRescue.isWatching, model.canUseHint else { return }
        guard model.needsAdForHint else {
            withGameAnimation { model.requestHint() }
            return
        }
        // どの手に対する広告かを出す前に控え、ロード中に始まった新しい手へは乗せない（15パズル・ナンプレのヒントと同じ）。
        let turn = model.turnSerial
        hintRescue.request(
            services, gameID: model.gameID, purpose: .hint,
            guardedBy: .checkedByGrant
        ) {
            withGameAnimation { model.grantAdHint(forTurn: turn) }
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
                    .accessibilityHidden(true)
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
            .foregroundStyle(Theme.inkSubText)
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
                    .foregroundStyle(Theme.inkSubText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // 縦の余りをここで吸い、点の一覧の下にフェルトの空白を残さない（大富豪 #193 と同じ）。
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
            // 卓では席をアイコンで見分けているので、点の一覧にも同じアイコンを添える（大富豪・いろリレーと同じ）。
            if player != HeartsModel.humanIndex {
                OpponentSeatIcon(index: player, diameter: layout.scaled(24))
            }
            Text(model.playerName(player))
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(player == HeartsModel.humanIndex ? Theme.coralText : Theme.ink)
            Spacer()
            Text(tr("%lld点", model.takenPoints[player]))
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(model.takenPoints[player] > 0 ? Theme.coralText : Theme.inkSubText)
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

// MARK: - 全画面（A）の寸法

/// レイアウトパターン A でのハーツの寸法（#2531。大富豪の `DaifugoLayoutA` と同じ考え方）。
/// View を組まずに札の大きさ・SE での収まりをテストできるよう純関数にする（`HeartsModuleTests`）。
///
/// 手札は 7 列のまま、**札を列幅いっぱい（列幅 − 4pt）まで大きくする**（`PlayingCardMetrics.compact` の相似拡大）。
/// 広い画面（iPad）では倍率に上限（`maxCardScale` × `elementScale`）を掛ける。場の十字の札は手札と同じ大きさまでで、
/// 場に使える高さが足りないとき（iPhone SE）は高さに合わせて小さくする（`trickCard`）。
enum HeartsLayoutA {
    /// 画面の左右の余白（全画面の枠の値）。
    static let sideInset: CGFloat = FullScreenGameLayoutMetrics.sideInset
    /// 中身の上下の余白（ヘッダーの余白 4 / バナーの帯の余白 8 に足す分）。
    static let verticalInset: CGFloat = 2
    /// 段のあいだの間隔（大富豪と同じ）。
    static let spacing: CGFloat = 6
    /// 手札の列のあいだに残す隙間（札の幅 = 列幅 − これ）。
    static let handGap: CGFloat = 4
    /// 札の拡大率の上限（狭い画面の倍率。iPad ではさらに `elementScale` 倍）。
    static let maxCardScale: CGFloat = 1.5
    /// 席のアイコンを小さい段に切り替える画面の幅（大富豪・いろリレーと同じ）。
    static let compactBreakpoint: CGFloat = 390
    /// 場の十字: 上下の札を真ん中からずらす量（札の高さに対する比）と、左右の札をずらす量（札の幅に対する比）。
    static let trickVerticalOffset: CGFloat = 0.72
    static let trickHorizontalOffset: CGFloat = 1.6
    /// 場の十字に要る高さ（札の高さに対する比。上下の札 + あいだ + 余白）。
    static let trickHeightRatio: CGFloat = 2.55
    /// 場の札の高さの下限（SE で初回のミニガイドが出ていても収まる大きさ）。
    static let minTrickCardHeight: CGFloat = 42
    /// 場の高さの下限。
    static var trickMinHeight: CGFloat { minTrickCardHeight * trickHeightRatio }
    /// 場の CPU の札に添える席のアイコンの直径。
    static let trickIconDiameter: CGFloat = 18

    struct Metrics: Equatable {
        /// 手札の札。
        let handCard: PlayingCardMetrics
        /// CPU の席のアイコンの直径。
        let seatDiameter: CGFloat
        /// CPU の席の裏向きの札。
        let seatCardMetrics: PlayingCardMetrics
    }

    /// 手札 1 列の幅（＝タップ判定の幅）。
    static func columnWidth(screenWidth: CGFloat) -> CGFloat {
        max(0, screenWidth - sideInset * 2) / CGFloat(HeartsHandLayout.columns)
    }

    /// 手札の札の拡大率（`PlayingCardMetrics.compact` に掛ける）。
    static func cardScale(screenWidth: CGFloat, elementScale: CGFloat = 1) -> CGFloat {
        let fit = (columnWidth(screenWidth: screenWidth) - handGap) / PlayingCardMetrics.compact.width
        return max(0, min(fit, maxCardScale * elementScale))
    }

    static func metrics(screenWidth: CGFloat, elementScale: CGFloat = 1) -> Metrics {
        let compact = screenWidth < compactBreakpoint
        let seatCardWidth = OpponentSeatStyle.cardWidth(compact: compact) * elementScale
        return Metrics(
            handCard: PlayingCardMetrics.compact.scaled(by: cardScale(screenWidth: screenWidth, elementScale: elementScale)),
            seatDiameter: OpponentSeatStyle.iconDiameter(compact: compact) * elementScale,
            seatCardMetrics: PlayingCardMetrics.compact.scaled(by: seatCardWidth / PlayingCardMetrics.compact.width)
        )
    }

    /// 場の十字の札。手札と同じ大きさまでで、場の高さ `height` に十字が収まらなければ小さくする（下限 `minTrickCardHeight`）。
    static func trickCard(hand: PlayingCardMetrics, height: CGFloat) -> PlayingCardMetrics {
        let fitHeight = max(minTrickCardHeight, height / trickHeightRatio)
        guard fitHeight < hand.height, hand.height > 0 else { return hand }
        return hand.scaled(by: fitHeight / hand.height)
    }

    /// 手札の段の高さ（13 枚 = 2 段ぶん。タップ判定の 44pt を下回らない）。
    static func handGridHeight(_ metrics: Metrics) -> CGFloat {
        let row = max(metrics.handCard.height, HeartsHandLayout.minimumTapTarget)
        return row * 2 + HeartsHandLayout.rowSpacing
    }

    /// 初回のミニガイドが出ているときの、中身に要る高さの見積もり（場は下限の高さ）。
    /// 席（アイコン + 束 + 枚数の札 18 + 吹き出し 20）+ 場の下限 + 手札（見出し 16 + 6 + 2 段 + 6 + 案内 14）+
    /// ミニガイド 22 + 操作欄 60 + 間隔 + 上下の余白。`HeartsModuleTests` が SE の使える高さと突き合わせる。
    static func estimatedMinimumHeight(screenWidth: CGFloat) -> CGFloat {
        let m = metrics(screenWidth: screenWidth)
        let seat = m.seatDiameter + OpponentSeatStyle.spacing * 3 + m.seatCardMetrics.height + 18 + 20
        let hand = 16 + 6 + handGridHeight(m) + 6 + 14
        let rows: [CGFloat] = [seat, trickMinHeight, hand, 22, 60]
        return rows.reduce(0, +) + spacing * CGFloat(rows.count - 1) + verticalInset * 2
    }
}

// MARK: - 手札グリッドの寸法

/// 手札グリッドの寸法（大富豪 #195・いろリレーと同じ考え方）。13 枚を 7 列 × 2 段に並べる。
/// 札は列幅 − 4pt（`HeartsLayoutA`）、タップ判定は列いっぱい。
enum HeartsHandLayout {
    static let columns = 7
    static let columnSpacing: CGFloat = 0
    static let rowSpacing: CGFloat = 8
    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 画面幅 `screenWidth` のときの、手札 1 枚あたりのタップ判定の幅（= 列幅）。
    static func tapWidth(screenWidth: CGFloat) -> CGFloat {
        HeartsLayoutA.columnWidth(screenWidth: screenWidth)
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
        if hint == .recommendedPass { return BoardGameHintColor.color }
        return Color.gray.opacity(0.2)
    }

    private var borderWidth: CGFloat {
        if selected { return 2.5 }
        if hint == .recommendedPass { return 3 }
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
            if hint == .recommendedPass {
                // 色だけに頼らず、電球の印も添える。
                Image(systemName: "lightbulb.fill")
                    .scaledFont(10, weight: .bold, maxScale: 1.1)
                    .foregroundStyle(BoardGameHintColor.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        // フェルトの上なので、不透明度を落とす（緑に濁る）のではなく白を重ねて沈める（大富豪 #2531 と同じ）。
        .tableDimmed(isDimmed, cornerRadius: metrics.cornerRadius)
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
            onboarding: HeartsOnboarding.guide,
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
