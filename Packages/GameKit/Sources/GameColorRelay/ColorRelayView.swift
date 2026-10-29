import SwiftUI
import Core

public struct ColorRelayView: View {
    @State private var model: ColorRelayModel
    private let services: GameServices
    /// 引き札を広告で免除する救済（#1320）。
    @State private var waiveRescue = RewardedRescue()
    /// 操作の後に CPU の手番を回すタスク。画面を離れたらキャンセルする（CodeRabbit 指摘・PR #1339）。
    /// `.task` の側は View のライフサイクルで自動的にキャンセルされるが、ボタンから起こした
    /// 非構造化タスクはそのままでは生き残り、画面外で CPU が打ち続けて決着・記録まで進んでしまう。
    @State private var cpuTask: Task<Void, Never>?
    /// 進行中に右上の新規を押したときの確認（#2370）。
    @State private var showConfirmNewGame = false
    /// 右上の新規で開く開始シート（CPU の強さを選ぶ・#2604）。
    @State private var showNewGame = false
    /// 画面の広さ（#458）。幅で札の大きさを決め、広い画面では同じ倍率で拡大する。
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: ColorRelayModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            // 決着後は卓も手札も要らないので、代わりに順位のリザルトを出す。
            // 縦の余りは `Spacer` ではなく卓 / リザルトのカード自身に吸わせる（大富豪 #193 と同じ）。
            if model.phase == .result {
                resultCard
                    .transition(.opacity)
            } else {
                tableArea
                    .transition(.opacity)
                handArea
                    .transition(.opacity)
            }
            HowToPlayHint(.colorRelay, playLog: services.playLog)
            actionArea
            RecommendationSlot(services: services, isFinished: model.phase == .result, ladder: ladder)
        }
        // 局面 → リザルトの差し替えは、残り続ける親に置かないと `transition` が効かない（#195）。
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        // レイアウトパターン A（全画面・#2531）: 左右 8pt、上下はヘッダーの余白 4 とバナーの帯の余白 8 に 4 を足す。
        .padding(.horizontal, FullScreenGameLayoutMetrics.sideInset)
        .padding(.vertical, 4)
        // レイアウトパターン A（会長決裁 2026-10-19・#2432）: フェルトを画面全体に敷き、ヘッダーは 1 行
        // （戻る・いろリレー・何ゲーム目と回る向き・？・＋）、バナーは画面最下部。卓の見出しだった札はヘッダーへ移る。
        // 右上の新規（#2370）。視聴中に配り直すと、見終えた免除が局ガードで弾かれて見損になる（#911 と同型）。
        .gameChrome(title: tr("いろリレー"), review: services.review, fullScreen: .felt, ads: services.ads,
                    newGame: GameChromeNewGame(.match, isDisabled: waiveRescue.isWatching) {
                        if model.hasProgressToLose {
                            showConfirmNewGame = true
                        } else {
                            showNewGame = true
                        }
                    }) {
            tableHeader
        }
        // 図で見る遊び方（#2824）は「？」の中から開くので、開いているあいだは CPU の手番を止め、閉じたら続きを回す。
        .howToPlay(HowToPlayGuide.colorRelay.illustrated(ColorRelayHowToFigures.items).onboarding(ColorRelayOnboarding.guide),
                   onPresent: { cpuTask?.cancel() }, onDismiss: { runCPU() }) { ColorRelayRuleSheet() }
        // 開始シートにも図で見る遊び方の入口があるので、開いているあいだは手番を止める。
        .onChange(of: showNewGame) { _, isOpen in
            if isOpen { cpuTask?.cancel() } else { runCPU() }
        }
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規対局しますか？"), isPresented: $showConfirmNewGame, titleVisibility: .visible) {
                Button(tr("終了して新規対局"), role: .destructive) { showNewGame = true }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると対局データが失われます。"))
            }
        }
        .sheet(isPresented: $showNewGame) {
            ColorRelayNewGameSheet(aiLevel: model.aiLevel, opponentCount: model.opponentCount) { level, opponents in
                showNewGame = false
                startNewGame(aiLevel: level, opponentCount: opponents)
            } onCancel: { showNewGame = false }
        }
        // 免除の提示（#780）。自分の番で引き札を課され、免除ボタンが出ているあいだを 1 回の提示として数える。
        .rewardOffer(waiveRescue, for: .revival, isPresented: model.canWaivePenalty,
                     services: services, gameID: model.gameID)
        .rewardedRescueAlerts(
            waiveRescue,
            notEarned: tr("引き札を免除できませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("引き札を免除できませんでした"),
                message: tr("広告を見ているあいだに番が進んだため、免除できませんでした。")
            )
        )
        .onDisappear { cpuTask?.cancel() }
        .task {
            // 開幕のモーダルは置かず、盤を見せたまま配り始める（#192）。
            // 中断から戻ったときは init が `.playing` まで復元しているので配り直さない。
            if model.phase == .idle { model.startGame() }
            #if DEBUG
            // 撮影・動作確認用: `-colorRelayScenario penalty|wild|result` で局面を差し替える。
            // 中断データから復元した局面も差し替える（前回の撮影が残っていても狙った局面になるように）。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-colorRelayScenario"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
            }
            #endif
            // 中断から戻ったときに CPU の手番が止まったままにならないようにする。
            runCPU()
        }
    }

    /// 勝ちが続いたら一段上の強さを勧める（#722・#2806）。並びは開始シートの「CPUの強さ」と同じ。
    private var ladder: DifficultyLadderPrompt? {
        DifficultyLadderPrompt(result: model.recordResult,
                               currentLevel: CPUStrength.ladderIndex(forLevel: model.aiLevel),
                               levelLabels: CPUStrength.labels) { index in
            startNewGame(aiLevel: CPUStrength.level(atLadderIndex: index))
        }
    }

    /// 新しい 1 ゲームを配って、CPU が親なら手番を回す（右上の新規・#2370）。
    private func startNewGame(aiLevel: Int, opponentCount: Int? = nil) {
        model.startGame(aiLevel: aiLevel, opponentCount: opponentCount)
        runCPU()
    }

    /// 人間の操作の後に CPU の手番を回す。前のタスクは止めてから起こす（走者は `withAITurnRunner` が 1 本に保つ）。
    private func runCPU() {
        cpuTask?.cancel()
        cpuTask = Task { await model.runCPUTurnsIfNeeded() }
    }

    // MARK: - 卓（#2369 案 B: 上段に相手 3 人・中段に山札と場札）

    private var turnLabel: String {
        switch model.phase {
        case .idle:    return tr("開始待ち")
        case .result:  return tr("決着")
        case .playing: return model.isPlayerTurn ? tr("あなたの番") : tr("%@の番", model.playerName(model.currentPlayer))
        }
    }

    /// 画面の幅で決まる卓と手札の寸法。
    private var metrics: ColorRelayHandLayout.Metrics {
        ColorRelayHandLayout.metrics(screenWidth: layout.width, elementScale: layout.elementScale)
    }

    /// 卓はアプリ共通の卓（緑のフェルト）に載せる。茶色の独自の卓は作らない（会長決裁 2026-10-18）。
    /// フェルトは全画面の枠（`gameChrome(fullScreen: .felt)`・#2531）が画面全体に敷くので、ここでは敷かない
    /// （卓の上の色 `cardTableInk` も枠が配る）。
    private var tableArea: some View {
        VStack(spacing: 0) {
            // 相手の段は縦に縮めない（SE で引き札の 2 段ボタンが出ても文字が潰れないように）。
            // 縦の余りと不足は中段の山札・場札が受け持つ。
            seatsRow
                .fixedSize(horizontal: false, vertical: true)
            fieldArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 卓の見出し（何ゲーム目・回る向き）。全画面の枠のヘッダーの行に札として置く（文字色は枠が配る）。
    /// 幅が足りないとき（英語の iPhone SE: 「Game 1 ↻ Clockwise」）は向きの文字を落として矢印だけにする。
    private var tableHeader: some View {
        let turnIcon = Image(systemName: model.isClockwise ? "arrow.clockwise" : "arrow.counterclockwise")
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                Text(tr("%lldゲーム目", max(model.gameNumber, 1)))
                turnIcon
                Text(model.isClockwise ? tr("順回り") : tr("逆回り"))
            }
            HStack(spacing: 4) {
                Text(tr("%lldゲーム目", max(model.gameNumber, 1)))
                turnIcon
            }
        }
        .scaledFont(11, weight: .bold, design: .rounded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ColorRelayAccessibility.tableHeaderLabel(
            gameNumber: max(model.gameNumber, 1), isClockwise: model.isClockwise, turn: turnLabel
        ))
    }

    /// 相手（1〜3 人）を横並び。あいだの `»` / `«` が番の回る向き（左から CPU1 → CPU2 → CPU3 が順回り）。
    private var seatsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(1..<model.playerCount, id: \.self) { index in
                seat(index)
                if index < model.playerCount - 1 {
                    CardTableInkReader { ink in
                        Image(systemName: model.isClockwise ? "chevron.right.2" : "chevron.left.2")
                            .scaledFont(15, weight: .black)
                            .foregroundStyle(ink.labelSub)
                    }
                    .frame(height: metrics.seatDiameter)
                    .accessibilityHidden(true)
                }
            }
        }
        .gameAnimation(.easeInOut(duration: 0.18), value: model.isClockwise)
    }

    /// 相手 1 人の席。アイコン・束・残り枚数・吹き出しの組み方は共通部品（`OpponentSeat`・#2531。大富豪と同じ見た目）。
    private func seat(_ index: Int) -> some View {
        let isCurrent = model.currentPlayer == index && model.phase == .playing
        let count = model.hands[index].count
        let action = model.lastActions[index]
        let cardWidth = metrics.opponentCardWidth
        return OpponentSeat(
            index: index, diameter: metrics.seatDiameter, isCurrent: isCurrent, cardCount: count, lastAction: action,
            accessibilityLabel: ColorRelayAccessibility.seatLabel(
                name: model.playerName(index), cardCount: count, isCurrent: isCurrent, lastAction: action
            )
        ) {
            OpponentCardFan(count: count, cardWidth: cardWidth, cardHeight: ColorRelayCardSize(width: cardWidth).height) {
                ColorRelayCardBack(width: cardWidth)
            }
        }
    }

    /// 山札と場札。大きさは卓の残りの高さから決める（SE で引き札の 2 段ボタンが出ても卓に収まる）。
    private var fieldArea: some View {
        GeometryReader { proxy in
            // GeometryReader は最初に大きさ 0 を渡すことがあるので、寸法の側で 0 を守る。
            let field = ColorRelayHandLayout.field(size: proxy.size, maxTopWidth: metrics.maxTopCardWidth)
            HStack(alignment: .center, spacing: field.spacing) {
                drawPileView(width: field.pileWidth)
                discardView(width: field.topWidth)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// 山札。自分の番で引けるときはタップでも引ける（操作欄の「1枚引く」と同じ）。
    private func drawPileView(width: CGFloat) -> some View {
        VStack(spacing: 4) {
            Button {
                model.drawCard()
                runCPU()
            } label: {
                ZStack {
                    ColorRelayCardBack(width: width).offset(x: 4, y: 4).opacity(0.7)
                    ColorRelayCardBack(width: width).offset(x: 2, y: 2).opacity(0.85)
                    ColorRelayCardBack(width: width)
                }
                .padding(.trailing, 4).padding(.bottom, 4)
            }
            .buttonStyle(.pop)
            .disabled(!model.canDraw)
            .accessibilityLabel(tr("山から1枚引く"))
            .accessibilityValue(tr("山 %lld枚", model.drawPile.count))
            CardTableInkReader { ink in
                Text(tr("山 %lld枚", model.drawPile.count))
                    .scaledFont(11, weight: .bold, design: .rounded)
                    .foregroundStyle(ink.labelSub)
                    .lineLimit(1)
            }
            .accessibilityHidden(true)
        }
    }

    /// 場札。下の色の皿が「いまの色」（いろがえの直後は場の札に色が無いので、ここで示す）。
    private func discardView(width: CGFloat) -> some View {
        let plate = width * ColorRelayHandLayout.plateRatio
        let under = model.discardPile.count >= 2 ? model.discardPile[model.discardPile.count - 2] : nil
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(model.activeColor.color.opacity(0.35))
                    .overlay(Circle().strokeBorder(model.activeColor.color, lineWidth: max(3, width * 0.05)))
                    .frame(width: plate, height: plate)
                if let under {
                    ColorRelayCardView(card: under, width: width)
                        .rotationEffect(.degrees(8))
                        .opacity(0.85)
                }
                if let top = model.topCard {
                    ColorRelayCardView(card: top, width: width)
                        .rotationEffect(.degrees(-5))
                        .id(top.id)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: plate, height: plate)
            CardTableInkReader { ink in
                HStack(spacing: 4) {
                    Text(tr("いまの色"))
                    Text(model.activeColor.name)
                }
                .scaledFont(11, weight: .bold, design: .rounded)
                .foregroundStyle(ink.labelSub)
                .lineLimit(1)
            }
        }
        .gameAnimation(.easeInOut(duration: 0.18), value: model.topCard)
        .gameAnimation(.easeInOut(duration: 0.18), value: model.activeColor)
        // 場は「何が出ているか」「いまの色」「山の残り」が分かればよいので 1 要素にまとめる（#188）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ColorRelayAccessibility.fieldLabel(
            top: model.topCard, activeColor: model.activeColor, drawPileCount: model.drawPile.count
        ))
    }

    // MARK: - 手札

    private var handArea: some View {
        // 1 枚ごとに引くと合法手の探索が手札の枚数ぶん走るので、ここで 1 回だけ求める（#190）。
        let handHint = model.handHint
        let playable = model.playableCardIDs
        return VStack(alignment: .leading, spacing: 4) {
            youPill
            handStrip(handHint, playable: playable)
            hintLine(handHint, playable: playable)
        }
    }

    /// 自分の席の札（手札の見出し）。自分の番は黄色。
    private var youPill: some View {
        let isTurn = model.isPlayerTurn
        let action = model.lastActions[ColorRelayModel.humanIndex]
        return HStack(spacing: 6) {
            Text(isTurn ? tr("あなたの番") : tr("あなた"))
                .scaledFont(12, weight: .black, design: .rounded)
            // 残り 1 枚は相手の席（`OpponentSeat`）と同じ黄色の札で目立たせる（#2805）。自分の番の黄色い見出しの上でも
            // 埋もれないよう、墨の細い縁を付ける。
            let isLast = model.playerHand.count == 1
            Text(tr("残り%lld枚", model.playerHand.count))
                .scaledFont(11, weight: isLast ? .black : .bold, design: .rounded)
                .foregroundStyle(isLast ? Theme.onAccent : (isTurn ? Theme.onAccent : Theme.ink))
                .padding(.horizontal, isLast ? 8 : 0)
                .padding(.vertical, isLast ? 2 : 0)
                .background(Capsule().fill(isLast ? Theme.Fill.yellow : Color.clear))
                .overlay(Capsule().strokeBorder(Theme.onAccent.opacity(isLast && isTurn ? 0.6 : 0), lineWidth: 1))
            if !action.isEmpty {
                Text(action)
                    .scaledFont(11, weight: .bold, design: .rounded)
            }
        }
        .foregroundStyle(isTurn ? Theme.onAccent : Theme.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(isTurn ? Theme.Fill.yellow : Theme.surface))
        .shadow(color: Theme.cardShadow, radius: 3, y: 1)
        .accessibilityElement(children: .combine)
    }

    /// 手札をまっすぐ重ねて大きく並べる。1 枚あたりの見える幅は 44pt 以上に保ち、収まらない枚数は横にスクロールする。
    private func handStrip(_ handHint: RelayHandHint?, playable: Set<Int>) -> some View {
        let m = metrics
        let cardHeight = ColorRelayCardSize(width: m.handCardWidth).height
        return GeometryReader { proxy in
            let available = max(0, proxy.size.width)
            let exposure = ColorRelayHandLayout.exposure(
                count: model.playerHand.count, cardWidth: m.handCardWidth, available: available
            )
            let total = ColorRelayHandLayout.totalWidth(
                count: model.playerHand.count, cardWidth: m.handCardWidth, exposure: exposure
            )
            ScrollView(.horizontal, showsIndicators: false) {
                // 後ろの札ほど手前に重なる（HStack は後の子を上に描き、タップも上の子が受ける）。
                // 見えている帯（exposure）が、その札のタップ判定になる。
                HStack(alignment: .top, spacing: exposure - m.handCardWidth) {
                    ForEach(model.playerHand) { card in
                        handCard(card, hint: handHint?.state(for: card.id) ?? .none, glows: playable.contains(card.id), width: m.handCardWidth)
                    }
                }
                .padding(.top, ColorRelayHandLayout.lift)
                .frame(width: max(total, available), height: cardHeight + ColorRelayHandLayout.lift)
                // 出した札が消える / 引いた札が増える変化を演出する（#195）。
                .gameAnimation(.easeInOut(duration: 0.18), value: model.playerHand)
            }
            .scrollDisabled(total <= available)
        }
        .frame(height: cardHeight + ColorRelayHandLayout.lift)
    }

    private func handCard(_ card: RelayCard, hint: RelayCardHint, glows: Bool, width: CGFloat) -> some View {
        let isSelected = model.selectedID == card.id
        return ColorRelayCardView(card: card, width: width, selected: isSelected, hint: hint, glows: glows)
            .offset(y: isSelected ? -ColorRelayHandLayout.lift : 0)
            .gameAnimation(.spring(response: 0.2), value: isSelected)
            .contentShape(Rectangle())
            .onTapGesture { model.toggleSelection(card) }
            .transition(.scale.combined(with: .opacity))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ColorRelayAccessibility.handCardLabel(card, isSelected: isSelected, hint: hint))
            .accessibilityHint(tr("ダブルタップで選択を切り替えます"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.toggleSelection(card) }
            .disabled(!model.isPlayerTurn || model.isPlayerPenalized)
    }

    /// 手札の下に出す 1 行の案内（#190）。
    @ViewBuilder
    private func hintLine(_ handHint: RelayHandHint?, playable: Set<Int>) -> some View {
        let message: String? = {
            if model.isPlayerPenalized { return tr("%lld枚引いて、番は飛ばされます", model.pendingDraw) }
            if model.canEndTurn, !playable.isEmpty { return tr("引いた札は出せます。出さずに次へ回すこともできます") }
            if model.isPlayerTurn, handHint?.playable.isEmpty == true, model.canDraw { return tr("出せる札がありません。山から1枚引いてください") }
            return nil
        }()
        if let message {
            // フェルトの上なので赤系（`Theme.coralText`）ではなく卓の上の文字色（白系）で出す（#2531）。
            CardTableInkReader { ink in
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .scaledFont(11, weight: .bold)
                    Text(message)
                        .scaledFont(11, weight: .bold, design: .rounded)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(ink.label)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - 操作

    @ViewBuilder
    private var actionArea: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .playing where model.isPlayerPenalized:
            VStack(spacing: 8) {
                if model.canWaivePenalty {
                    waivePenaltyButton
                }
                // 視聴中に引くと番が進み、見終えた広告が局ガードで弾かれて見損になる（#911 と同型）。
                actionButton(tr("%lld枚引く", model.pendingDraw), role: .primary, disabled: waiveRescue.isWatching) {
                    model.takePenalty()
                    runCPU()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .playing where model.needsColorChoice:
            VStack(spacing: 6) {
                Text(tr("次の色を選ぶ"))
                    .scaledFont(12, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
                HStack(spacing: 8) {
                    ForEach(RelayColor.allCases, id: \.self) { color in
                        colorChoiceButton(color)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .playing:
            HStack(spacing: 12) {
                if model.canEndTurn {
                    actionButton(tr("出さずに次へ"), role: .skip) {
                        model.endTurn()
                        runCPU()
                    }
                } else {
                    // 出せる札が無いときは押してほしいボタンとして主役の色にする（#2693）。
                    actionButton(tr("1枚引く"), role: model.mustDraw ? .primary : .skip, disabled: !model.canDraw) {
                        model.drawCard()
                        runCPU()
                    }
                }
                actionButton(playButtonTitle, role: .primary, disabled: !model.canPlaySelection) {
                    model.playSelected()
                    runCPU()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .result:
            actionButton(tr("もう一回"), role: .primary) {
                model.startGame()
                runCPU()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        }
    }

    /// 引き札を課された自分の番にだけ出す「広告を見て免除」（#1320）。1 ゲーム 1 回。
    private var waivePenaltyButton: some View {
        Button {
            // 視聴完了（報酬獲得）したときだけ免除する。どの手番に対するものかを広告の前に控え、
            // 視聴中に番が進んでいたら乗せない（#729）。
            let turn = model.turnSerial
            waiveRescue.request(
                services, gameID: model.gameID, purpose: .revival,
                guardedBy: .checkedByGrant
            ) {
                let applied = model.waivePenaltyAfterAd(forTurn: turn)
                if applied { runCPU() }
                return applied
            }
        } label: {
            Label(tr("広告を見て%lld枚の引き札を免除", model.pendingDraw), systemImage: "play.rectangle.fill")
                .themeBody(14)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .buttonStyle(GameButtonStyle(role: .ad, shape: .block))
        .disabled(waiveRescue.isWatching)
    }

    private func colorChoiceButton(_ color: RelayColor) -> some View {
        Button {
            model.playSelected(color: color)
            runCPU()
        } label: {
            VStack(spacing: 4) {
                Capsule()
                    .fill(color.color)
                    .frame(height: 28)
                Text(color.name)
                    .scaledFont(11, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: ColorRelayHandLayout.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pop)
        .accessibilityLabel(tr("%@にして出す", color.name))
    }

    private var playButtonTitle: String {
        model.selectedID == nil ? tr("札を選ぶ") : tr("出す")
    }

    // MARK: - リザルト

    /// 結果の寸法（#2393）。広い画面で横に間延びしないよう幅に上限を置き、文字は盤の上の小さな札向けでなく読む前提の大きさにする。
    private enum ResultLayout {
        static let maxWidth: CGFloat = 520
        static let placeWidth: CGFloat = 56
    }

    /// 枠は中身の高さで止め、余りは枠の下に空ける（#2393）。文字サイズ特大で収まらないときだけ縦にスクロールする。
    private var resultCard: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                resultContent
                Spacer(minLength: 0)
            }
            ScrollView {
                resultContent
            }
        }
    }

    private var resultContent: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: model.playerPlace == 0 ? "crown.fill" : "flag.checkered")
                    .scaledFont(26)
                    .foregroundStyle(model.playerPlace == 0 ? Theme.yellowText : Theme.inkSubText)
                    .accessibilityHidden(true)
                Text(resultHeadline)
                    .scaledFont(22, weight: .black, design: .rounded)
                    .foregroundStyle(model.playerPlace == 0 ? Theme.tealText : Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            VStack(spacing: 8) {
                ForEach(Array(model.ranking.enumerated()), id: \.element) { place, player in
                    HStack(spacing: 10) {
                        Text(tr("%lld位", place + 1))
                            .scaledFont(15, weight: .black, design: .rounded)
                            // 1 位だけ差し色の面。他は濃いグレーの面なので文字色を分ける（#220）。
                            .foregroundStyle(place == 0 ? Theme.onAccent : .white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: ResultLayout.placeWidth)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(place == 0 ? Theme.Fill.yellow : Theme.fillMuted))
                        // 卓では名前を出さずアイコンで見分けているので、順位にも同じアイコンを添える（#2369）。
                        if player != ColorRelayModel.humanIndex {
                            OpponentSeatIcon(index: player, diameter: layout.scaled(28))
                        }
                        Text(model.playerName(player))
                            .scaledFont(17, weight: .bold, design: .rounded)
                            .foregroundStyle(player == ColorRelayModel.humanIndex ? Theme.coralText : Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        Text(place == 0 ? tr("あがり") : tr("残り%lld枚", model.hands[player].count))
                            .scaledFont(15, weight: .semibold, design: .rounded)
                            .foregroundStyle(Theme.inkSubText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            RecordLabel(model.recordResult)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .popCard(corner: Theme.cornerSmall)
        .frame(maxWidth: ResultLayout.maxWidth)
        .frame(maxWidth: .infinity)
    }

    private var resultHeadline: String {
        guard let winner = model.ranking.first else { return tr("決着") }
        return winner == ColorRelayModel.humanIndex ? tr("あなたの勝ち！") : tr("%@の勝ち", model.playerName(winner))
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

// MARK: - 卓と手札の寸法

/// 卓と手札の寸法（#2369 案 B）。View を組まずに 44pt の判定や SE での収まりをテストできるよう純関数にする。
///
/// 手札はまっすぐ重ねて並べ、**1 枚あたりの見える幅（＝タップ判定の幅）を 44pt 以上**に保つ。
/// 札の幅は画面の幅で 2 段に分ける: 390pt 以上（17 Pro など）は 72pt、それより狭い SE（375pt）は 50pt。
/// SE だけ札を小さくするのは、44pt の見える幅を守ったまま**配られた 7 枚 + 1 枚引いた 8 枚**までを
/// 横スクロール無しで並べるため（50 + 44 × 7 = 358 ≤ 359pt。56pt だと 8 枚目からスクロールになる）。
///
/// 画面はレイアウトパターン A（全画面・#2531）で、左右の余白は `FullScreenGameLayoutMetrics.sideInset`（8pt）。
/// 以前は余白 16pt の内側から帯だけ 8pt ずつはみ出させていたが、A では余白が 8pt なのではみ出させない（帯の幅は同じ）。
enum ColorRelayHandLayout {
    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44
    /// 札の幅を小さい段に切り替える画面の幅。
    static let compactBreakpoint: CGFloat = 390
    static let regularHandCardWidth: CGFloat = 72
    static let compactHandCardWidth: CGFloat = 50
    /// 画面の左右の余白（全画面の枠の値）。
    static let sideInset: CGFloat = FullScreenGameLayoutMetrics.sideInset
    /// 選んだ札を持ち上げる高さ（帯の上にこの分の余白を取る）。
    static let lift: CGFloat = 12
    /// 重ならないときの札どうしのすき間。
    static let looseGap: CGFloat = 4
    /// 場札の下の「いまの色」の皿の直径（場札の幅に対する比）。
    static let plateRatio: CGFloat = 1.5
    /// 場札の下の「いまの色」の文字の行（皿との間を含む）。
    static let fieldLabelHeight: CGFloat = 20

    struct Metrics: Equatable {
        let handCardWidth: CGFloat
        let seatDiameter: CGFloat
        let opponentCardWidth: CGFloat
        let maxTopCardWidth: CGFloat
    }

    /// 画面幅 `screenWidth` のときの寸法。幅が測れる前（0）は狭いほうに倒す。広い画面（iPad）は `elementScale` 倍。
    /// 場札の幅の上限。全画面（A）で増えた卓の高さが場札の大きさに出るよう、卓を囲っていた頃の 96 / 76 から上げた
    /// （#2432 のモックの読み取り「上限を外さないと全画面にした意味が画に出ない」。手札 72 / 50 に対して約 1.7〜1.8 倍。
    /// 実際の大きさは卓の中段の高さと幅で決まり、SE ではこの上限まで届かないことがある）。
    static let regularMaxTopCardWidth: CGFloat = 120
    static let compactMaxTopCardWidth: CGFloat = 90

    static func metrics(screenWidth: CGFloat, elementScale: CGFloat = 1) -> Metrics {
        let compact = screenWidth < compactBreakpoint
        return Metrics(
            handCardWidth: (compact ? compactHandCardWidth : regularHandCardWidth) * elementScale,
            seatDiameter: OpponentSeatStyle.iconDiameter(compact: compact) * elementScale,
            opponentCardWidth: OpponentSeatStyle.cardWidth(compact: compact) * elementScale,
            maxTopCardWidth: (compact ? compactMaxTopCardWidth : regularMaxTopCardWidth) * elementScale
        )
    }

    /// 手札の帯の幅（画面の左右の余白の内側いっぱい）。
    static func stripWidth(screenWidth: CGFloat) -> CGFloat {
        max(0, screenWidth - sideInset * 2)
    }

    /// 1 枚あたりの見える幅。帯に収まるなら詰めすぎず、収まらなくても 44pt を割らない（その分は横スクロール）。
    static func exposure(count: Int, cardWidth: CGFloat, available: CGFloat) -> CGFloat {
        guard count > 1 else { return cardWidth }
        let fit = (available - cardWidth) / CGFloat(count - 1)
        return min(cardWidth + looseGap, max(minimumTapTarget, fit))
    }

    /// 手札を並べた全体の幅。
    static func totalWidth(count: Int, cardWidth: CGFloat, exposure: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return cardWidth + exposure * CGFloat(count - 1)
    }

    /// 横スクロール無しで並べられる最大の枚数。
    static func maxCardsWithoutScroll(screenWidth: CGFloat) -> Int {
        let card = metrics(screenWidth: screenWidth).handCardWidth
        let strip = stripWidth(screenWidth: screenWidth)
        guard strip >= card else { return 0 }
        return 1 + Int(((strip - card) / minimumTapTarget).rounded(.down))
    }

    struct Field: Equatable {
        let topWidth: CGFloat
        let pileWidth: CGFloat
        let spacing: CGFloat
    }

    /// 卓の中段（大きさ `size`）に置く山札と場札の幅。皿 + 文字の行が高さに、山札 + 皿が幅に収まる大きさにする。
    static func field(size: CGSize, maxTopWidth: CGFloat) -> Field {
        let spacing: CGFloat = 28
        let byHeight = (max(0, size.height) - fieldLabelHeight) / plateRatio
        let byWidth = (max(0, size.width) - spacing) / (plateRatio + 0.8)
        let top = max(0, min(maxTopWidth, byHeight, byWidth))
        return Field(topWidth: top, pileWidth: top * 0.8, spacing: spacing)
    }
}

// MARK: - Rule Sheet

struct ColorRelayRuleSheet: View {
    static var rules: [(String, String)] { [
        (tr("ゲームの流れ"), tr("CPUと対戦します。7枚ずつ配り、場の札と同じ色か同じ数字・記号の札を順番に出します。手札を先になくした人が勝ちです")),
        (tr("引くとき"), tr("出せる札が無いとき（出したくないときも）は山から1枚引きます。引いた札が出せるならそのまま出せます（出さずに次へ回してもかまいません）。出せなければ自動で次の人の番になります")),
        (tr("とばし"), tr("次の人の番を飛ばします")),
        (tr("ぎゃく"), tr("番の回る向きが逆になります")),
        ("+2", tr("次の人は山から2枚引き、番を飛ばされます")),
        (tr("いろがえ"), tr("どの札の上にも出せて、次の色を自分で選べます")),
        (tr("いろがえ+4"), tr("いろがえに加えて、次の人は4枚引いて番を飛ばされます")),
        (tr("引き札の免除"), tr("+2 / いろがえ+4 を受けたとき、広告を見ると1ゲームに1回だけ引かずに済みます（番は飛ばされます）")),
        (tr("順位"), tr("上がった人が1位。残りは手札の少ない順です。次のゲームは親が1人ずつ回ります")),
    ] }

    var body: some View {
        RuleListSheet(rules: Self.rules)
    }
}

// MARK: - New Game Sheet

/// 右上の新規で開く開始シート（相手の人数 #2866・CPU の強さ #2604 を選ぶ）。
/// 強さは他の CPU 戦と同じ部品（`CPUStrengthPicker`）を使う。
struct ColorRelayNewGameSheet: View {
    @State private var level: Int
    @State private var opponents: Int
    let onStart: (Int, Int) -> Void
    let onCancel: () -> Void

    init(aiLevel: Int, opponentCount: Int, onStart: @escaping (Int, Int) -> Void, onCancel: @escaping () -> Void) {
        _level = State(initialValue: aiLevel)
        _opponents = State(initialValue: opponentCount)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        GameSetupSheet(
            kind: .versus,
            onboarding: ColorRelayOnboarding.guide,
            onStart: { onStart(level, opponents) }, onCancel: onCancel
        ) {
            GameSetupSection(tr("相手の人数")) {
                HStack(spacing: 12) {
                    ForEach(Array(ColorRelayModel.opponentCountRange), id: \.self) { count in
                        GameSetupChooser(title: tr("%lld人", count), subtitle: "",
                                          selected: opponents == count,
                                          accent: Theme.Fill.purple) { opponents = count }
                    }
                }
                Text(tr("人数ごとに記録（勝敗・連勝・平均順位）は別々に残ります。"))
                    .themeBody(12).foregroundStyle(Theme.inkSubText)
            }
            GameSetupSection(tr("CPUの強さ")) {
                // 説明は `ColorRelayRules.cpuPlay` の中身と一致させる（#416）。
                CPUStrengthPicker(level: $level, details: [
                    tr("出せる札からでたらめに選ぶ"), tr("ときどきでたらめに出し、攻撃を急がない"),
                    tr("相手の手札が2枚以下で攻撃する"), tr("相手の手札が3枚以下で攻撃する"),
                ])
            }
        }
    }
}
