import SwiftUI
import Core

public struct DaifugoView: View {
    @State private var model: DaifugoModel
    private let services: GameServices
    @State private var showResignConfirm = false
    /// 右上の新規で開く開始シート（CPU の強さ・しばりを選ぶ・#2604・#2605）。
    @State private var showNewGame = false
    /// 対局中に開ける強さの順・特別ルールの早見表（#2788）。
    @State private var showReference = false
    /// 大貧民の献上を広告で免除する救済（#1048）。
    @State private var waiveRescue = RewardedRescue()
    /// ボタンから起こす CPU の手番。画面を離れたら止める（#1380。`.task` と違いボタンの Task は自動で止まらない）。
    @State private var cpuTask: Task<Void, Never>?
    /// 画面の広さ（#458）。広い画面（iPad）では札の拡大に上限を掛けるのに読む。
    @Environment(\.adaptiveLayout) private var layout
    /// Reduce Motion のときは革命・8切りの弾みを出さない（#2713）。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: DaifugoModel(services: services))
    }

    public var body: some View {
        // レイアウトパターン A（全画面・会長決裁 2026-10-19・#2431 → #2531）: フェルトを画面全体に敷き、ヘッダーは 1 行
        // （戻る・大富豪・ゲーム数と手番の札・？）、バナーは画面最下部。場と手札は白い札をやめてフェルトに直に置き、
        // 手札は 7 列のまま列幅いっぱいまで札を大きくする（SE で 47pt・iPhone 17 で 51pt。札そのものが初めて 44pt を超える）。
        // 以前の「ヘッダー下の帯 + 白い札の積み重ね」は SE で使える高さを 17〜30pt 超えていた（#2455）が、A では収まる
        // （`DaifugoLayoutA.estimatedMinimumHeight` を `DaifugoLayoutTests` が SE の高さと突き合わせる）。
        GeometryReader { geometry in
            let metrics = DaifugoLayoutA.metrics(screenWidth: geometry.size.width, elementScale: layout.elementScale)
            VStack(spacing: DaifugoLayoutA.spacing) {
                cpuRow(metrics)
                // 決着後は場も手札も空になるので、代わりに階級のリザルトを出す。
                //
                // 縦の余りは `Spacer` ではなく**場 / リザルトのカード自身**に吸わせる（#193）。
                // `Spacer` に吸わせると、その分がまるごとフェルトの空白として残る。
                if model.phase == .result {
                    resultCard
                        .transition(.opacity)
                } else {
                    fieldArea(metrics)
                        .transition(.opacity)
                    handArea(metrics)
                        .transition(.opacity)
                }
                HowToPlayHint(.daifugo, playLog: services.playLog)
                actionArea
                RecommendationSlot(services: services, isFinished: model.phase == .result)
            }
            // 局面 → リザルトの差し替えは、上の `transition` を効かせるために**入れ替わる側ではなく
            // 残り続ける親**へ置く（枝の中に置くと消える側と一緒に修飾子も消えて効かない）（#195）。
            .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
            // 左右 8pt（全画面の枠の値）。上下はヘッダーの余白 4 とバナーの帯の余白 8 に 4 を足す。
            .padding(.horizontal, DaifugoLayoutA.sideInset)
            .padding(.vertical, DaifugoLayoutA.verticalInset)
            // 縦の余りを場だけが吸うと手札・操作欄が下端に張り付いて見えるので、下に少し余白を足して全体を上へ寄せる。
            .padding(.bottom, DaifugoLayoutA.bottomLift(contentHeight: geometry.size.height,
                                                        screenWidth: geometry.size.width))
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            // 交換の帯は盤の高さを変えないよう重ねで出す（#2607・#2493 の再発防止）。
            .overlay { exchangeBanner }
        }
        // ゲーム数・革命中・手番は、ヘッダー下の帯（`GameStatusBar`）ではなくヘッダーの行の札に置く（A の「1 行のヘッダー」）。
        .gameChrome(title: daifugoGameName(), review: services.review, fullScreen: .felt, ads: services.ads,
                    reference: GameChromeReference(tr("カードの強さとルール")) { showReference = true },
                    newGame: GameChromeNewGame(.match, isDisabled: waiveRescue.isWatching) {
                        showNewGame = true
                    }) {
            statusChips
        }
        // 早見表を開いているあいだは CPU の手番を止め、閉じたら続きを回す（読んでいるあいだに場が進まないように）。
        .sheet(isPresented: $showReference) {
            NavigationStack {
                DaifugoReferenceSheet(ruleSet: model.ruleSet)
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
        // 開始シートにも図で見る遊び方の入口があるので、開いているあいだは手番を止める（#2824）。
        .onChange(of: showNewGame) { _, isOpen in
            if isOpen { cpuTask?.cancel() } else { runCPU() }
        }
        // 右上の新規で開く開始シート（CPU の強さを選ぶ・#2604）。途中の局を捨てる確認はシートの開始ボタンが兼ねる。
        .sheet(isPresented: $showNewGame) {
            DaifugoNewGameSheet(
                aiLevel: model.aiLevel, ruleSet: model.preferredRuleSet, discardsProgress: model.hasProgressToLose
            ) { level, ruleSet in
                showNewGame = false
                model.choosePreferredRuleSet(ruleSet)
                model.startGame(aiLevel: level)
                runCPU()
            } onCancel: { showNewGame = false }
        }
        // 革命・8切り・階級まで含む細かいルールは3行に収まらないので「くわしいルール」へ送る（#118）。
        // 図で見る遊び方（#2824）は「？」の中から開くので、開いているあいだは CPU の手番を止め、閉じたら続きを回す。
        .howToPlay(HowToPlayGuide.daifugo.illustrated(DaifugoHowToFigures.items).onboarding(DaifugoOnboarding.guide),
                   onPresent: { cpuTask?.cancel() }, onDismiss: { runCPU() }) { DaifugoRuleSheet() }
        .dialogs { anchor in
            anchor.confirmationDialog(tr("投了しますか？"), isPresented: $showResignConfirm, titleVisibility: .visible) {
                Button(tr("投了する"), role: .destructive) { model.resign() }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("今のゲームを打ち切ります。あなたは大貧民になり、負けとして記録されます。"))
            }
        }
        // 献上免除の提示（#780 × #1048）。大貧民のリザルトでボタンが出ているあいだを 1 回の提示として数える。
        .rewardOffer(waiveRescue, for: .revival, isPresented: model.canWaiveExchange,
                     services: services, gameID: model.gameID)
        .rewardedRescueAlerts(
            waiveRescue,
            notEarned: tr("カード交換を免除できませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("カード交換を免除できませんでした"),
                message: tr("広告を見ているあいだに次のゲームが始まったため、免除できませんでした。")
            )
        )
        .task {
            // 開幕の全画面モーダルは廃止したので、盤を見せたまま既定値で配り始める（#192）。
            // 中断から戻ったときは init が `.playing` まで復元しているので配り直さない。
            if model.phase == .idle { model.startGame() }
            #if DEBUG
            // 撮影用（#2788）: 早見表だけを開く。
            if ProcessInfo.processInfo.arguments.contains("-daifugoReference") { showReference = true }
            #endif
            // 中断から戻ったときに CPU の手番が止まったままにならないようにする。
            // 早見表で止められるよう、操作の後と同じ cpuTask で回す（#2788）。
            runCPU()
        }
        .onDisappear { cpuTask?.cancel() }
    }

    /// 配った直後の交換の帯（#2607）。数秒で消える・タップで閉じる。VoiceOver には出た時点で読み上げる。
    @ViewBuilder
    private var exchangeBanner: some View {
        Group {
            if let notice = model.exchangeNotice {
                let lines = DaifugoAccessibility.exchangeLines(
                    notice, partnerName: model.playerName(notice.partner), spoken: false)
                Button { model.dismissExchangeNotice() } label: {
                    VStack(spacing: 2) {
                        ForEach(lines, id: \.self) { line in
                            Text(verbatim: line)
                                .themeCaption(13, weight: .bold, maxScale: 1.5)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.Fill.teal))
                    .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .strokeBorder(Theme.ink.opacity(0.85), lineWidth: 2))
                }
                .buttonStyle(.pop)
                .padding(.horizontal, 24)
                .accessibilityLabel(DaifugoAccessibility.exchangeLines(
                    notice, partnerName: model.playerName(notice.partner), spoken: true).joined(separator: tr("。")))
                .accessibilityHint(tr("タップで閉じます"))
                .transition(.opacity)
            }
        }
        .gameAnimation(.easeInOut(duration: 0.2), value: model.exchangeNotice)
        .task(id: model.exchangeNoticeRun) {
            guard let notice = model.exchangeNotice else { return }
            AccessibilityNotification.Announcement(DaifugoAccessibility.exchangeLines(
                notice, partnerName: model.playerName(notice.partner), spoken: true).joined(separator: tr("。"))).post()
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { model.dismissExchangeNotice() }
        }
    }

    private func runCPU() {
        cpuTask?.cancel()
        cpuTask = Task { await model.runCPUTurnsIfNeeded() }
    }

    // MARK: - ステータス（ヘッダーの行の札）

    /// ゲーム数・革命中・手番。ヘッダーの残りの幅に収まらないとき（英語の iPhone SE など）はゲーム数を落とす。
    /// 文字色（白）は全画面の枠が配る。手番の札（`TurnBadge`）は対戦ゲーム共通の色（#1419）。
    private var statusChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                gameCountLabel
                bindBadge
                revolutionBadge
                turnChip
            }
            HStack(spacing: 8) {
                bindBadge
                revolutionBadge
                turnChip
            }
        }
    }

    private var gameCountLabel: some View {
        Label(tr("%lldゲーム目", max(model.gameNumber, 1)), systemImage: "number")
            .themeBody(13, maxScale: Self.seatTextMaxScale)
    }

    /// 手番の札。席に名前を出さない（アイコンで見分ける）ので、CPU の番ならその席のアイコンを添えてどの席か分かるようにする。
    private var turnChip: some View {
        HStack(spacing: 4) {
            if model.phase == .playing, !model.isPlayerTurn {
                OpponentSeatIcon(index: model.currentPlayer, diameter: layout.scaled(22))
            }
            TurnBadge(turnLabel, kind: turnKind)
        }
    }

    /// しばり中の札（#2605）。スートの印を添え、VoiceOver には「しばり中、♠のカードだけ出せます」を読ませる。
    @ViewBuilder private var bindBadge: some View {
        if !model.bindSuits.isEmpty {
            Text(tr("しばり %@", DaifugoRules.bindLabel(model.bindSuits)))
                .scaledFont(12, weight: .black, design: .rounded)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Fill.coral))
                .accessibilityLabel(DaifugoAccessibility.bindLabel(model.bindSuits))
        }
    }

    @ViewBuilder private var revolutionBadge: some View {
        if model.isRevolution {
            Text(tr("革命中"))
                .scaledFont(12, weight: .black, design: .rounded)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Fill.coral))
        }
    }

    private var turnKind: TurnBadge.Kind {
        switch model.phase {
        case .idle, .result: return .finished
        case .playing: return model.isPlayerTurn ? .you : .cpu
        }
    }

    private var turnLabel: String {
        switch model.phase {
        case .idle:    return tr("開始待ち")
        case .result:  return tr("決着")
        case .playing: return model.isPlayerTurn ? tr("あなたの番") : tr("%@の番", model.playerName(model.currentPlayer))
        }
    }

    // MARK: - CPU

    /// CPU 3 人の席。見せ方はいろリレーと同じ共通部品（`OpponentSeat`・#2531。会長「CPU のディテールとかいろリレーの感じに寄せれない？」）:
    /// 色と記号の丸いアイコン・手番の黄色い輪・裏向きのトランプの束・残り枚数・直前の手の吹き出し。
    private func cpuRow(_ metrics: DaifugoLayoutA.Metrics) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(1..<DaifugoModel.playerCount, id: \.self) { index in
                cpuSeat(index, metrics)
            }
        }
    }

    /// CPU の席・場のラベルが文字サイズ設定で拡大する上限倍率（#1782）。3 人を横に並べる密な帯なので、
    /// 際限なく拡大すると席が押し合う。上限を超える分は `minimumScaleFactor` で縮めて 1 行に収める。
    private static let seatTextMaxScale: CGFloat = 1.6

    private func cpuSeat(_ index: Int, _ metrics: DaifugoLayoutA.Metrics) -> some View {
        let isTurn = model.currentPlayer == index && model.phase == .playing
        let remaining = model.hands[index].count
        let action = model.lastActions[index].isEmpty ? "" : model.actionLabel(index)
        let back = metrics.seatCardMetrics
        return OpponentSeat(
            index: index, diameter: metrics.seatDiameter, isCurrent: isTurn, cardCount: remaining, lastAction: action,
            // 手番は輪の色でしか示さないので、席を 1 まとまりにして「〜の番」まで読ませる（#2495）。
            accessibilityLabel: DaifugoAccessibility.seatLabel(
                name: model.playerName(index), remaining: remaining, action: action, isTurn: isTurn)
        ) {
            OpponentCardFan(count: remaining, cardWidth: back.width, cardHeight: back.height) {
                // トランプの裏（藍の面 + 白い内枠 + スート印）。外形と面は共通基盤（#397）。
                ZStack {
                    PlayingCardSurface(faceUp: false, cornerRadius: back.cornerRadius, shadowRadius: 1)
                    PlayingCardBack(metrics: back)
                }
            }
        }
    }

    // MARK: - 場

    /// 場。白い札は使わずフェルトに直に置く。縦の余りはここが吸う（#193）。
    private func fieldArea(_ metrics: DaifugoLayoutA.Metrics) -> some View {
        VStack(spacing: 6) {
            fieldHeader
            HStack(spacing: 6) {
                if model.field.isEmpty {
                    // 場の札と同じ枠の空き枠（破線の色は卓の上の色・`cardTableInk`）。札が出た瞬間に場の高さが跳ねないよう同じ寸法。
                    CardSlot(metrics: metrics.fieldCard)
                        .transition(.opacity)
                } else {
                    ForEach(model.field) { card in
                        DaifugoCardView(card: card, metrics: metrics.fieldCard)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        // 革命の切り替わり・8切りの瞬間だけ場を 1.15 倍→1.0 倍に弾ませる。自分が起こしたときは一段大きく（#2713）。
        // Reduce Motion ではトリガーを止めて弾ませない。
        .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? nil : model.fieldImpact) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            let peak = model.fieldImpact?.byHuman == true ? 1.25 : 1.15
            CubicKeyframe(peak, duration: 0.12)
            SpringKeyframe(1.0, duration: 0.25, spring: .bouncy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 誰が出しても場は同じ経路（`field` の差し替え）で更新されるので、CPU の手も人間の手も
        // ここ1箇所で演出できる。見出しの「場は流れています」も同じ変化で切り替わる（#195）。
        .gameAnimation(.easeInOut(duration: 0.18), value: model.field)
        // 場は「何が出ているか」が分かればよいので 1 要素にまとめる（#188）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DaifugoAccessibility.fieldLabel(model.field, ownerName: fieldOwnerName))
        // 8切り・革命・しばり・反則上がりが起きた瞬間の一言説明（#2721）。盤の高さを変えないよう重ねで出す。
        .overlay(alignment: .top) { ruleNoticeBanner }
    }

    /// ルールの一言説明（#2721）。数秒で消える。VoiceOver には出た時点で読み上げる。
    @ViewBuilder
    private var ruleNoticeBanner: some View {
        Group {
            if let notice = model.ruleNotice {
                VStack(spacing: 2) {
                    ForEach(Array(notice.events.enumerated()), id: \.offset) { _, event in
                        Text(verbatim: DaifugoAccessibility.ruleEventText(event))
                            .themeCaption(12, weight: .bold, maxScale: Self.seatTextMaxScale)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .multilineTextAlignment(.center)
                    }
                }
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).fill(Theme.Fill.teal))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .strokeBorder(Theme.ink.opacity(0.85), lineWidth: 1.5))
                .padding(.horizontal, 8)
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(notice.events.map(DaifugoAccessibility.ruleEventText).joined(separator: tr("。")))
            }
        }
        .gameAnimation(.easeInOut(duration: 0.2), value: model.ruleNotice)
        .task(id: model.ruleNotice?.serial) {
            guard let notice = model.ruleNotice else { return }
            AccessibilityNotification.Announcement(
                notice.events.map(DaifugoAccessibility.ruleEventText).joined(separator: tr("。"))).post()
            try? await Task.sleep(for: .seconds(3.5))
            if !Task.isCancelled { model.dismissRuleNotice(serial: notice.serial) }
        }
    }

    /// 場の出し手（`fieldOwner`）の名前。場が空 / 出し手が不明なら nil。
    private var fieldOwnerName: String? {
        guard !model.field.isEmpty, let owner = model.fieldOwner else { return nil }
        return model.playerName(owner)
    }

    /// 場の見出し。組が出ているときは**誰が出したか**をバッジで添える（#193）。
    /// 出し手が分からないと、パスして流れたときに親が誰になるか・自分が越えるべき相手が誰かを読めない。
    @ViewBuilder
    private var fieldHeader: some View {
        if let ownerName = fieldOwnerName {
            let isHuman = model.fieldOwner == DaifugoModel.humanIndex
            HStack(spacing: 4) {
                // 席に名前を出さないので、出し手は席と同じアイコンで示す（どの相手を越えるべきか読める・#193）。
                if isHuman {
                    Image(systemName: "person.fill")
                        .themeCaption(10, maxScale: Self.seatTextMaxScale)
                } else if let owner = model.fieldOwner {
                    OpponentSeatIcon(index: owner, diameter: layout.scaled(16))
                }
                Text(isHuman ? tr("あなたが出した") : tr("%@が出した", ownerName))
                    .themeCaption(11, maxScale: Self.seatTextMaxScale)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(isHuman ? Theme.Fill.teal : Theme.Fill.purple))
        } else {
            // フェルトの上の地の文は卓の上の文字色（白系）で出す。
            CardTableInkReader { ink in
                Text(model.field.isEmpty ? tr("場は流れています（好きな組を出せます）") : tr("場"))
                    .themeCaption(11, weight: .semibold, maxScale: Self.seatTextMaxScale)
                    .foregroundStyle(ink.labelSub)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }

    // MARK: - 手札

    private func handArea(_ metrics: DaifugoLayoutA.Metrics) -> some View {
        // 1枚ごとに引くと合法手の探索が手札の枚数ぶん走るので、ここで1回だけ求める（#190）。
        let handHint = model.handHint
        return VStack(spacing: 6) {
            CardTableInkReader { ink in
                HStack {
                    Text(tr("あなた（残り%lld枚）", model.playerHand.count))
                        .themeBody(13, maxScale: Self.seatTextMaxScale)
                        .foregroundStyle(ink.label)
                    Spacer()
                    if !model.lastActions[DaifugoModel.humanIndex].isEmpty {
                        Text(model.actionLabel(DaifugoModel.humanIndex))
                            .scaledFont(11, weight: .bold, design: .rounded)
                            .foregroundStyle(ink.label)
                    }
                }
            }
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: DaifugoHandLayout.columnSpacing),
                    count: DaifugoHandLayout.columns
                ),
                spacing: DaifugoHandLayout.rowSpacing
            ) {
                ForEach(model.displayHand) { card in
                    let isSelected = model.selected.contains(card.id)
                    let hint = handHint?.state(for: card.id) ?? .none
                    DaifugoCardView(card: card, metrics: metrics.handCard, selected: isSelected, hint: hint)
                        .offset(y: isSelected ? -6 : 0)
                        .gameAnimation(.spring(response: 0.2), value: isSelected)
                        // 札は列幅 − 4pt。タップ判定は列いっぱい（44pt 以上・#195）。`offset` は判定の位置に影響しない。
                        .frame(maxWidth: .infinity, minHeight: DaifugoHandLayout.minimumTapTarget)
                        .contentShape(Rectangle())
                        .onTapGesture { model.toggleSelection(card) }
                        .transition(.scale.combined(with: .opacity))
                        // カードは `onTapGesture` で組んでいるため、Button と違って
                        // ボタン trait も読み上げ文も自動では付かない（#188）。
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            DaifugoAccessibility.handCardLabel(card, isSelected: isSelected, hint: hint)
                        )
                        .accessibilityHint(tr("ダブルタップで選択を切り替えます"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.toggleSelection(card) }
                        // CPU の手番では `toggleSelection` が何もしないので、
                        // 操作可能として案内しない（描画は素の図形なので見た目は変わらない）。
                        .disabled(!model.isPlayerTurn)
                }
            }
            // 出した札が手札から消える／交換で増える変化を演出する（#195）。
            .gameAnimation(.easeInOut(duration: 0.18), value: model.displayHand)
            hintLine(handHint)
        }
    }

    /// 手札の下に出す1行の案内（#190）。フェルトの上なので赤系ではなく卓の上の文字色（白系）で出す。
    /// 出せない組を選んでいればその理由を、選んでいなければ「1枚も出せない」ときだけ助言を出す。
    @ViewBuilder
    private func hintLine(_ handHint: DaifugoHandHint?) -> some View {
        let message = model.selectionIssue
            ?? (handHint?.playable.isEmpty == true ? tr("出せる組がありません。パスしてください") : nil)
        if let message {
            CardTableInkReader { ink in
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .scaledFont(11, weight: .bold)
                    Text(message)
                        // 受け入れ条件どおり1行に収める。文字を拡大しても高さが跳ねないよう縮めて入れる（#189）。
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
        case .playing where model.isPlayerFinished:
            // 自分が上がった後は操作が無くなるので、無効なパス／出すではなく早送りを出す（#191）。
            actionButton(tr("結果まで進める"), role: .primary, disabled: model.isSkippingToResult) {
                model.skipToResult()
                runCPU()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .playing:
            HStack(spacing: 12) {
                // 出せる手が無いときは押してほしいボタンとして主役の色にする（#2693）。
                actionButton(tr("パス"), role: model.mustPass ? .primary : .skip, disabled: !model.canPass) {
                    model.pass()
                    runCPU()
                }
                actionButton(playButtonTitle, role: .primary, disabled: !model.canPlaySelection) {
                    model.playSelected()
                    runCPU()
                }
                // 投了は盤下の「⋯」メニューに入れる（#1418・会長決裁 #1011 D1）。ヘッダー右は
                // 役・？・新規の並びに固定するため文字の「投了」は置けない。中断すると次回は必ず
                // 「続きから」に戻るので、局面を降りる導線としてここに残す（#194）。
                // 行の高さを増やさないよう、行ごと置く `GameOverflowBar` ではなく中身の `GameControlMenu`
                // （丸 44×44pt・全ゲーム共通の見た目）を並びの中に置く（#2494・#2455 の SE の高さを保つ）。
                GameControlMenu(items: [
                    GameControlMenuItem(
                        id: "resign", title: tr("投了"), systemImage: "flag.fill",
                        isDestructive: true, isEnabled: model.canResign
                    ) { showResignConfirm = true }
                ])
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .result:
            VStack(spacing: 8) {
                if model.canWaiveExchange {
                    waiveExchangeButton
                }
                // 視聴中に次のゲームを始めると、見終えた広告が局ガードで弾かれて見損になる（#911 と同型）。
                actionButton(tr("もう一回"), role: .primary, disabled: waiveRescue.isWatching) {
                    model.startGame()
                    runCPU()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        }
    }

    /// 大貧民のリザルトにだけ出す「広告を見て献上を免除」（#1048）。
    private var waiveExchangeButton: some View {
        Button {
            // 視聴完了（報酬獲得）したときだけ免除する。どのゲームの決着に対するものかを広告の前に控え、
            // 視聴中に次のゲームが始まっていたら乗せない（#729）。
            let game = model.gameNumber
            waiveRescue.request(
                services, gameID: model.gameID, purpose: .revival,
                guardedBy: .checkedByGrant
            ) {
                model.waiveExchangeAfterAd(forGame: game)
            }
        } label: {
            Label(tr("広告を見て次のカード交換を免除"), systemImage: "play.rectangle.fill")
                .themeBody(14)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .buttonStyle(GameButtonStyle(role: .ad, shape: .block))
        .disabled(waiveRescue.isWatching)
    }

    private var playButtonTitle: String {
        model.selected.isEmpty ? tr("カードを選ぶ") : tr("%lld枚出す", model.selected.count)
    }

    // MARK: - リザルト

    /// リザルト見出しに添える但し書き。投了は反則上がりより下の扱いなので先に見る（#194）。
    private var humanResultNote: String? {
        if model.resigned.contains(DaifugoModel.humanIndex) { return tr("投了") }
        if model.downfallPlayer == DaifugoModel.humanIndex { return tr("都落ち") }
        if model.fouls.contains(DaifugoModel.humanIndex) { return tr("反則上がり") }
        return nil
    }

    /// 順位表の各行に添える但し書き（見出しより短く詰める）。
    private func rankRowNote(_ player: Int) -> String? {
        if model.resigned.contains(player) { return tr("投了") }
        if model.downfallPlayer == player { return tr("都落ち") }
        if model.fouls.contains(player) { return tr("反則") }
        return nil
    }

    private var resultCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.playerPlace == 0 ? "crown.fill" : "flag.checkered")
                    .scaledFont(20)
                    .foregroundStyle(model.playerPlace == 0 ? Theme.yellowText : Theme.inkSubText)
                Text(tr("あなたは %@", model.playerTitle))
                    .scaledFont(17, weight: .black, design: .rounded)
                    .foregroundStyle(model.playerPlace == 0 ? Theme.tealText : Theme.ink)
                if let note = humanResultNote {
                    Text(note)
                        .scaledFont(11, weight: .bold, design: .rounded)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.Fill.coral))
                }
                Spacer()
            }
            VStack(spacing: 4) {
                ForEach(Array(model.ranking.enumerated()), id: \.element) { place, player in
                    HStack(spacing: 8) {
                        Text(DaifugoRules.title(forPlace: place))
                            .scaledFont(12, weight: .black, design: .rounded)
                            // 1位だけ差し色の面。他は濃いグレーの面なので文字色を分ける（#220）。
                            .foregroundStyle(place == 0 ? Theme.onAccent : .white)
                            // 幅が固定の札なので、英語の階級名（Tycoon など）が長くても 1 行に縮めて収める（#2166）。
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 58)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(place == 0 ? Theme.Fill.yellow : Theme.fillMuted))
                        // 卓では席をアイコンで見分けているので、順位にも同じアイコンを添える（いろリレー #2369 と同じ）。
                        if player != DaifugoModel.humanIndex {
                            OpponentSeatIcon(index: player, diameter: layout.scaled(24))
                        }
                        Text(model.playerName(player))
                            .scaledFont(13, weight: .bold, design: .rounded)
                            .foregroundStyle(player == DaifugoModel.humanIndex ? Theme.coralText : Theme.ink)
                        if let note = rankRowNote(player) {
                            Text(note)
                                .scaledFont(10, weight: .bold, design: .rounded)
                                .foregroundStyle(Theme.coralText)
                        }
                        Spacer()
                    }
                }
            }
            if let fallen = model.downfallPlayer {
                Text(tr("都落ち：前のゲームの大富豪（%@）が1位になれなかったので、大貧民に落ちました", model.playerName(fallen)))
                    .scaledFont(11, weight: .medium, design: .rounded)
                    .foregroundStyle(Theme.coralText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 「今回の結果」（見出し・順位表）を上、「この先」（通算成績・次ゲームの案内）を下に置き、
            // 伸びた分の余りは2つの塊の**間**に集める（#193）。カード全体を中央寄せにすると
            // 見出しが画面の真ん中まで降りてきてしまうので、間に寄せる。
            Spacer(minLength: 8)
            RecordLabel(model.recordResult)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(exchangeNote)
                .scaledFont(11, weight: .medium, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 縦の余りをここで吸い、リザルトの下にフェルトの空白を残さない（#193）。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 次のゲームのカード交換の案内。広告で献上を免除したら、免除したことを伝える（#1048）。
    private var exchangeNote: String {
        model.isExchangeWaived
            ? tr("次のゲームは大富豪⇔大貧民のカード交換を免除します（富豪⇔貧民は1枚ずつ交換します）")
            : tr("次のゲームは階級に応じてカードを交換します（大富豪⇔大貧民 2枚 / 富豪⇔貧民 1枚）")
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

/// レイアウトパターン A での大富豪の寸法（#2531・モック `docs/design/layout-patterns-2111/daifugo/`）。
/// View を組まずに札の大きさ・SE での収まりをテストできるよう純関数にする（`DaifugoLayoutTests`）。
///
/// 手札は 7 列のまま、**札を列幅いっぱい（列幅 − 4pt）まで大きくする**。札の寸法は `PlayingCardMetrics.compact`（42×60）を
/// 相似拡大したもので、場の札（`.medium` 56×78）も同じ倍率。広い画面（iPad）では列幅がそのまま札になると大きすぎるので、
/// 倍率に上限（`maxCardScale` × `elementScale`）を掛ける。
enum DaifugoLayoutA {
    /// 画面の左右の余白（全画面の枠の値）。
    static let sideInset: CGFloat = FullScreenGameLayoutMetrics.sideInset
    /// 中身の上下の余白（ヘッダーの余白 4 / バナーの帯の余白 8 に足す分）。SE で初回のミニガイド・案内・出し手の
    /// カプセルが同時に出ても収まるよう詰めてある（`estimatedMinimumHeight`）。
    static let verticalInset: CGFloat = 2
    /// 段のあいだの間隔。SE で出し手のカプセル・ミニガイド・案内が同時に出ても収まる値（8 だと 1.5pt 超える）。
    static let spacing: CGFloat = 6
    /// 手札の列のあいだに残す隙間（札の幅 = 列幅 − これ）。
    static let handGap: CGFloat = 4
    /// 札の拡大率の上限（狭い画面の倍率。iPad ではさらに `elementScale` 倍）。iPhone 17 Pro Max（440pt）で約 1.33 なので届かない。
    static let maxCardScale: CGFloat = 1.5
    /// 席のアイコンを小さい段に切り替える画面の幅（いろリレーと同じ）。
    static let compactBreakpoint: CGFloat = 390

    struct Metrics: Equatable {
        /// 手札の札。
        let handCard: PlayingCardMetrics
        /// 場の札。
        let fieldCard: PlayingCardMetrics
        /// CPU の席のアイコンの直径。
        let seatDiameter: CGFloat
        /// CPU の席の裏向きの札。
        let seatCardMetrics: PlayingCardMetrics
    }

    /// 手札 1 列の幅（＝タップ判定の幅）。
    static func columnWidth(screenWidth: CGFloat) -> CGFloat {
        max(0, screenWidth - sideInset * 2) / CGFloat(DaifugoHandLayout.columns)
    }

    /// 手札の札の拡大率（`PlayingCardMetrics.compact` に掛ける）。
    static func cardScale(screenWidth: CGFloat, elementScale: CGFloat = 1) -> CGFloat {
        let fit = (columnWidth(screenWidth: screenWidth) - handGap) / PlayingCardMetrics.compact.width
        return max(0, min(fit, maxCardScale * elementScale))
    }

    static func metrics(screenWidth: CGFloat, elementScale: CGFloat = 1) -> Metrics {
        let scale = cardScale(screenWidth: screenWidth, elementScale: elementScale)
        let compact = screenWidth < compactBreakpoint
        let seatCardWidth = OpponentSeatStyle.cardWidth(compact: compact) * elementScale
        return Metrics(
            handCard: PlayingCardMetrics.compact.scaled(by: scale),
            fieldCard: PlayingCardMetrics.medium.scaled(by: scale),
            seatDiameter: OpponentSeatStyle.iconDiameter(compact: compact) * elementScale,
            seatCardMetrics: PlayingCardMetrics.compact.scaled(by: seatCardWidth / PlayingCardMetrics.compact.width)
        )
    }

    /// 初回のミニガイドと手札の下の案内が両方出ているときの、中身に要る高さの見積もり（手札 14 枚 = 2 段・場に出し手のカプセル）。
    /// 席（アイコン + 束 + 枚数の札 18 + 吹き出し 20）+ 場（出し手のカプセル 21 + 6 + 札）+ 手札（見出し 16 + 6 + 2 段 + 6 + 案内 14）+
    /// ミニガイド 22 + 操作の段 60 + 間隔 + 上下の余白。`DaifugoLayoutTests` が SE の使える高さと突き合わせる（#2455 の再発防止）。
    static func estimatedMinimumHeight(screenWidth: CGFloat) -> CGFloat {
        let m = metrics(screenWidth: screenWidth)
        let seat = m.seatDiameter + OpponentSeatStyle.spacing * 3 + m.seatCardMetrics.height + 18 + 20
        let field = 21 + 6 + m.fieldCard.height
        let hand = 16 + 6 + m.handCard.height * 2 + DaifugoHandLayout.rowSpacing + 6 + 14
        let rows: [CGFloat] = [seat, field, hand, 22, 60]
        return rows.reduce(0, +) + spacing * CGFloat(rows.count - 1) + verticalInset * 2
    }

    /// 手札・操作欄を下端から持ち上げる量の上限（会長 QA 2026-10-22「気持ち要素を上に」・#2531）。
    static let maxBottomLift: CGFloat = 24

    /// 手札・操作欄を下端から持ち上げる量。中身の下に足す余白で、縦の余りを吸う場が同じだけ縮むので、
    /// 場・手札・操作欄がそろって少し上へ寄る。控えめな量（上限 `maxBottomLift`）にとどめ、
    /// 縦の余り（使える高さ − 最低限の高さ）の半分を超えない（SE で手札や操作欄が下にはみ出さない）。
    static func bottomLift(contentHeight: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let slack = contentHeight - estimatedMinimumHeight(screenWidth: screenWidth)
        return min(maxBottomLift, max(0, slack / 2))
    }
}

// MARK: - 手札グリッドの寸法

/// 手札グリッドの寸法（#195 → #2531）。
///
/// 列は `GridItem(.flexible())` の 7 列で、実効幅は画面幅で決まる。札は列幅 − 4pt（`DaifugoLayoutA`）、
/// タップ判定は列いっぱい。間隔を 0 にして幅を列へ回し、見た目の隙間は「列幅 − カード幅」= 4pt。
///
/// 実効幅の計算をここに置いてビュー側からも参照するのは、寸法を変えたときに
/// `DaifugoHandLayoutTests` の検証と実装がずれないようにするため。
enum DaifugoHandLayout {
    static let columns = 7
    static let columnSpacing: CGFloat = 0
    static let rowSpacing: CGFloat = 6
    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 画面幅 `screenWidth` のときの、手札1枚あたりのタップ判定の幅（= 列幅）。
    static func tapWidth(screenWidth: CGFloat) -> CGFloat {
        DaifugoLayoutA.columnWidth(screenWidth: screenWidth)
    }

    /// 画面幅 `screenWidth` のときの、手札の札の見た目の幅。
    static func cardWidth(screenWidth: CGFloat) -> CGFloat {
        DaifugoLayoutA.metrics(screenWidth: screenWidth).handCard.width
    }
}

// MARK: - Card View

struct DaifugoCardView: View {
    let card: DaifugoCard
    /// 寸法。手札・場ともに `DaifugoLayoutA.metrics` が画面幅から決める（#2531。以前は 42×60 / 56×78 の固定）。
    let metrics: PlayingCardMetrics
    var selected: Bool = false
    /// 出せる / 出せないの区別（#190）。`.none` なら素の見た目のまま。
    var hint: DaifugoCardHint = .none

    /// 出せない札は色に頼らず**明度**でも落として区別する（色覚特性の影響を受けないため）。
    private var isDimmed: Bool { hint == .unplayable && !selected }

    private var borderColor: Color {
        if selected { return Theme.coral }
        if hint == .playable { return Theme.teal }
        return Color.gray.opacity(0.2)
    }

    private var borderWidth: CGFloat {
        if selected { return 2 }
        return hint == .playable ? 1.5 : 0.5
    }

    var body: some View {
        ZStack {
            // 外形・面はトランプ共通基盤（#397。質感は CardStyle #366）。大富豪は常に表向き。
            PlayingCardSurface(
                cornerRadius: metrics.cornerRadius,
                border: borderColor,
                borderWidth: borderWidth,
                shadowColor: selected ? Theme.coral.opacity(0.6) : .black.opacity(0.15),
                shadowRadius: selected ? 6 : 3
            )

            // ジョーカーの図案は共通基盤の道化帽（#397 で新調。従来は star.fill だった）。
            PlayingCardFace(figure: card.figure, metrics: metrics)
        }
        .frame(width: metrics.width, height: metrics.height)
        // フェルトの上なので、不透明度を落とす（緑に濁る）のではなく白を重ねて沈める（#2531）。
        .tableDimmed(isDimmed, cornerRadius: metrics.cornerRadius)
    }
}

// MARK: - Rule Sheet

struct DaifugoRuleSheet: View {
    /// 表示用なので、その時点の言語で引く（#2166）。
    private var rules: [(String, String)] {
        [
            // 廃止した開幕モーダル（#192）が持っていた「誰と何人で戦うのか」をここへ移した。
            // 残りの3項目（出し方・パス・カード交換）は下の項目と `HowToPlayGuide.daifugo` に既にある。
            (tr("ゲームの流れ"), tr("CPU3人と対戦します。手札を早く出し切るほど上の階級になり、決着すると階級に応じてカードを交換して次のゲームへ進みます")),
            (tr("カードの強さ"), tr("弱い ← 3 4 5 6 7 8 9 10 J Q K A 2 → 強い。ジョーカーが最強で、どのカードの代わりにもなります")),
            (tr("出し方"), tr("場が空なら好きな組（1枚・ペア・3枚…）を出せます。場に組があるときは同じ枚数で、より強い組だけ出せます")),
            (tr("革命"), tr("同じ数字を4枚以上まとめて出すと革命。カードの強さが上下逆になります（もう一度出すと元に戻ります）")),
            (tr("ローカルルール"), tr("新規ゲームの開始シートで、8切り・しばり・階段・都落ち・反則上がりのあり／なしを選べます。ルールは局の始めに決まり、途中では変わりません（選んだ組み合わせは次のゲームにも引き継ぎます）")),
            (tr("8切り"), tr("8 を含む組を出すと場が流れ、出した人がそのまま続けて出せます（初期設定はあり）")),
            (tr("しばり"), tr("同じスートが2回続くと、場が流れるまでそのスートの札（とジョーカー）しか出せません（初期設定はなし）")),
            (tr("階段"), tr("同じスートで数が連なる3枚以上（例: ♠5-6-7）を1つの組として出せます。強さは一番強い札で比べ、場と同じ枚数の階段だけで受けます。ジョーカーは欠けた数の代わりになります（初期設定はなし）")),
            (tr("都落ち"), tr("前のゲームの大富豪が1位で上がれなかったら、その場で大貧民に落ちます（初期設定はなし）")),
            (tr("反則上がり"), tr("最後の1手が 2・ジョーカー・8（8切りありのとき）だと反則。上がっても大貧民に落ちます（初期設定はあり）")),
            (tr("階級とカード交換"), tr("上がった順に 大富豪・富豪・貧民・大貧民。次のゲームは 大貧民→大富豪 に強い2枚、大富豪→大貧民 に弱い2枚（富豪と貧民は1枚ずつ）を渡します")),
        ]
    }

    var body: some View {
        RuleListSheet(rules: rules)
    }
}

// MARK: - New Game Sheet

/// 右上の新規で開く開始シート（CPU の強さ・#2604、ローカルルール・#2605・#2721）。強さは他の CPU 戦と同じ部品（`CPUStrengthPicker`）を使う。
/// ローカルルールの初期値は従来の採用ルール（8切り・反則上がりあり）で、選んだ値は次のゲームにも引き継ぐ。
struct DaifugoNewGameSheet: View {
    @State private var level: Int
    @State private var ruleSet: DaifugoRuleSet
    let discardsProgress: Bool
    let onStart: (Int, DaifugoRuleSet) -> Void
    let onCancel: () -> Void

    init(aiLevel: Int, ruleSet: DaifugoRuleSet, discardsProgress: Bool,
         onStart: @escaping (Int, DaifugoRuleSet) -> Void, onCancel: @escaping () -> Void) {
        _level = State(initialValue: aiLevel)
        _ruleSet = State(initialValue: ruleSet)
        self.discardsProgress = discardsProgress
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        GameSetupSheet(
            kind: .versus,
            discardsProgress: discardsProgress,
            onboarding: DaifugoOnboarding.guide,
            onStart: { onStart(level, ruleSet) }, onCancel: onCancel
        ) {
            GameSetupSection(tr("CPUの強さ")) {
                // 説明は `DaifugoRules.cpuPlay` の中身と一致させる（#416）。
                CPUStrengthPicker(level: $level, details: [
                    tr("出せる手からでたらめに選ぶ"), tr("ときどき最善でない手を選ぶ"),
                    tr("出せる最弱の手を選ぶ"), tr("強い札を温存し、革命も狙う"),
                ])
            }
            GameSetupSection(tr("ローカルルール")) {
                VStack(spacing: 8) {
                    ruleToggle(tr("8切り"), tr("8を出すと場が流れ、出した人から"), $ruleSet.isEightCutEnabled)
                    ruleToggle(tr("しばり"), tr("同じ柄が2回続くとその柄だけ"), $ruleSet.isBindEnabled)
                    ruleToggle(tr("階段"), tr("同じ柄の連番3枚以上を出せる"), $ruleSet.isSequenceEnabled)
                    ruleToggle(tr("都落ち"), tr("前の大富豪が1位でないと大貧民へ"), $ruleSet.isDownfallEnabled)
                    ruleToggle(tr("反則上がり"), tr("最後が 2・ジョーカー・8 だと最下位"), $ruleSet.isFoulFinishEnabled)
                }
            }
        }
    }

    /// ローカルルール 1 つぶんのあり／なしの行。行ぜんたいが 44pt 以上のスイッチ。
    private func ruleToggle(_ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).themeBody(16, weight: .bold).foregroundStyle(Theme.ink)
                Text(detail).themeCaption(12).foregroundStyle(Theme.inkSubText)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
        }
        .tint(Theme.fillStrong)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).fill(Theme.fillMuted.opacity(0.12)))
    }
}
