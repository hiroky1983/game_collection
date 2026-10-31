import SwiftUI
import Core

public struct OldMaidView: View {
    @State private var model: OldMaidModel
    private let services: GameServices
    @State private var showNewGame = false
    /// 遊び方（図で見る遊び方を含む）を開いているか。開いているあいだ CPU の手番を止める（#2824）。
    @State private var isHowToPlayOpen = false
    /// 画面の広さ（#458）。札と同じ倍率で枠を拡大するために読む。
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: OldMaidModel(services: services))
    }

    public var body: some View {
        // レイアウトパターン A（全画面・会長 QA 2026-10-23・#2531）: 大富豪・いろリレーと同じく、フェルトを画面全体に敷き、
        // ヘッダーは 1 行（戻る・ババ抜き・ゲーム数と強さと手番の札・？・＋）、バナーは画面最下部。
        // 白い札（ステータスの帯・CPU・卓・手札・操作欄）はやめてフェルトに直に置き、CPU の席は共通部品（`OpponentSeat`）。
        GeometryReader { geometry in
            let metrics = OldMaidLayoutA.metrics(screenWidth: geometry.size.width, contentHeight: geometry.size.height,
                                                 elementScale: layout.elementScale)
            VStack(spacing: OldMaidLayoutA.spacing) {
                cpuRow(metrics)
                // 決着後は卓も手札も要らないので、代わりに順位のリザルトを出す。
                if model.phase == .result {
                    resultCard
                        .transition(.opacity)
                } else {
                    // 縦の余りは卓（引く相手の伏せ札）の上下に分けて置き、卓を席と手札のあいだの真ん中に置く
                    // （大富豪の場と同じ見た目）。手札・操作欄は下にそろえるので、番が替わって卓の高さが変わっても動かない。
                    Spacer(minLength: 0)
                    tableArea(metrics)
                        // 伏せ札は縮められる（枠の中でスクロール）が、余白があるうちは手札より先に全段を見せる（#2685）。
                        // 手札の最小の高さ（札 1 段）は優先度が低くても先に確保される。
                        .layoutPriority(2)
                        .transition(.opacity)
                    Spacer(minLength: 0)
                    handArea(metrics)
                        // 余りを分ける上下の Spacer より先に、手札の全段ぶんを取る。
                        .layoutPriority(1)
                        .transition(.opacity)
                }
                HowToPlayHint(.oldMaid, playLog: services.playLog)
                actionArea
                RecommendationSlot(services: services, isFinished: model.phase == .result, ladder: ladder)
            }
            // 局面 → リザルトの差し替えは、残り続ける親に置かないと `transition` が効かない（#195）。
            .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
            // 左右 8pt（全画面の枠の値）。上下はヘッダーの余白 4 とバナーの帯の余白 8 に足す分。
            .padding(.horizontal, OldMaidLayoutA.sideInset)
            .padding(.vertical, OldMaidLayoutA.verticalInset)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        // ゲーム数・CPU の強さ・手番は、ヘッダー下の帯ではなくヘッダーの行の札に置く（A の「1 行のヘッダー」）。
        .gameChrome(title: tr("ババ抜き"), review: services.review, fullScreen: .felt, ads: services.ads,
                    newGame: GameChromeNewGame(.match) {
                        showNewGame = true
                    }) {
            statusChips
        }
        // 図で見る遊び方（#2824）は「？」の中から開くので、開いているあいだは CPU の手番を止め、閉じたら続きを回す。
        .howToPlay(HowToPlayGuide.oldMaid.illustrated(OldMaidHowToFigures.items).onboarding(OldMaidOnboarding.guide),
                   onPresent: { isHowToPlayOpen = true }, onDismiss: { isHowToPlayOpen = false })
        // 開始シートにも図で見る遊び方の入口があるので、開いているあいだは手番を止める。
        // 止める・続けるは下の `.task(id:)` が `isCPUPaused` の変化で受ける。
        .sheet(isPresented: $showNewGame) {
            OldMaidNewGameSheet(aiLevel: model.aiLevel, discardsProgress: model.phase == .playing) { level in
                showNewGame = false
                model.startGame(aiLevel: level)
            } onCancel: { showNewGame = false }
        }
        // CPU の手番はここ 1 か所で動かす（麻雀と同じ作り・#3146）。手番キーが変わる（あなたの操作・CPU の着手・新しいゲーム）か、
        // 止める画面（遊び方・新規対局）の開閉が変わると作り直され、画面を離れれば止まる。
        // 操作のたびに手で起こす形だと、新しい操作を足したとき 1 か所呼び忘れて CPU 番のまま止まる。
        .task(id: CPUDriveKey(turn: model.cpuTurnKey, isPaused: isCPUPaused)) {
            guard !isCPUPaused else { return }
            await model.runCPUTurnsIfNeeded()
        }
        .task {
            // 開幕のモーダルは置かず、卓を見せたまま配り始める（#192）。強さは右上の「新規対局」で選び直す。
            // 中断から戻ったときは init が `.playing` まで復元しているので配り直さない。
            if model.phase == .idle { model.startGame() }
            #if DEBUG
            // 撮影・動作確認用: `-oldMaidScenario tell|watched|result|crowded` で局面を差し替える。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-oldMaidScenario"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
            }
            #endif
        }
    }

    /// CPU の手番を止めておく画面（遊び方・新規対局）を開いているか（#2824）。
    private var isCPUPaused: Bool { isHowToPlayOpen || showNewGame }

    /// `.task(id:)` の識別子。手番の進行と、止める画面の開閉のどちらが変わっても CPU のタスクを作り直す。
    private struct CPUDriveKey: Hashable {
        let turn: AITurnKey
        let isPaused: Bool
    }

    /// 勝ちが続いたら一段上の強さを勧める（#722）。並びは開始シートの「CPUの強さ」と同じ。
    private var ladder: DifficultyLadderPrompt? {
        DifficultyLadderPrompt(result: model.recordResult,
                               currentLevel: CPUStrength.ladderIndex(forLevel: model.aiLevel),
                               levelLabels: CPUStrength.labels) { index in
            model.startGame(aiLevel: CPUStrength.level(atLadderIndex: index))
        }
    }

    // MARK: - ステータス（ヘッダーの行の札）

    /// ゲーム数・CPU の強さ・手番。ヘッダーの残りの幅に収まらないとき（英語の iPhone SE など）はゲーム数、
    /// 次に強さを落とす。文字色（白）は全画面の枠が配る。手番の札（`TurnBadge`）は対戦ゲーム共通の色（#1419）。
    private var statusChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                gameCountLabel
                strengthBadge
                turnChip
            }
            HStack(spacing: 8) {
                strengthBadge
                turnChip
            }
            turnChip
        }
    }

    private var gameCountLabel: some View {
        Label(tr("%lldゲーム目", max(model.gameNumber, 1)), systemImage: "number")
            .themeBody(13, maxScale: Self.seatTextMaxScale)
    }

    private var strengthBadge: some View {
        let strength = CPUStrength.strength(for: model.aiLevel)
        return Text(strength.label)
            .scaledFont(11, weight: .bold, design: .rounded)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(strength.accent))
            .accessibilityLabel(tr("CPUの強さ、%@", strength.label))
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
        case .playing:
            return model.isPlayerTurn ? tr("あなたの番") : tr("%@の番", model.playerName(model.currentPlayer))
        }
    }

    // MARK: - CPU

    /// CPU の席・卓のラベルが文字サイズ設定で拡大する上限倍率（大富豪 #1782 と同じ）。
    private static let seatTextMaxScale: CGFloat = 1.6
    /// 直前の「引く」に関わらない席の吹き出しの濃さ。
    private static let staleBubbleOpacity: Double = 0.35

    /// CPU 3 人の席。見せ方は大富豪・いろリレーと同じ共通部品（`OpponentSeat`・#2531）:
    /// 色と記号の丸いアイコン・手番の黄色い輪・裏向きのトランプの束・残り枚数・直前の手の吹き出し。
    private func cpuRow(_ metrics: OldMaidLayoutA.Metrics) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(1..<OldMaidModel.playerCount, id: \.self) { index in
                cpuSeat(index, metrics)
            }
        }
    }

    private func cpuSeat(_ index: Int, _ metrics: OldMaidLayoutA.Metrics) -> some View {
        let isCurrent = model.phase == .playing && model.currentPlayer == index
        let count = model.hands[index].count
        let action = OldMaidAccessibility.actionText(model.game?.lastActions[index] ?? OldMaidAction.none)
        // あがった人は札が無いので、吹き出しに「n位であがり」を出す（以前の白い札の 2 行目）。
        let finished = finishedLabel(index)
        let bubble = finished ?? action
        // 直前の「引く」に関わらない人の吹き出しは何手も前の出来事なので薄くする（配った直後は直前の「引く」が無いので全員そのまま）。
        let isStale = model.game?.lastTransfer.map { $0.from != index && $0.to != index } ?? false
        let back = metrics.seatCardMetrics
        var spoken = [model.playerName(index), finished ?? tr("残り%lld枚", count)]
        if finished == nil, !action.isEmpty { spoken.append(action) }
        // 手番は輪の色でしか示さないので、席を 1 まとまりにして「〜の番」まで読ませる（大富豪 #2495 と同じ）。
        if isCurrent { spoken.append(tr("%@の番", model.playerName(index))) }
        return OpponentSeat(
            index: index, diameter: metrics.seatDiameter, isCurrent: isCurrent, cardCount: count, lastAction: bubble,
            lastActionOpacity: isStale ? Self.staleBubbleOpacity : 1,
            accessibilityLabel: spoken.joined(separator: tr("、"))
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

    /// あがった CPU の順位（「n位であがり」）。まだ残っていれば nil。
    private func finishedLabel(_ index: Int) -> String? {
        guard let place = model.game?.finishOrder.firstIndex(of: index) else { return nil }
        return tr("%lld位であがり", place + 1)
    }

    // MARK: - 卓（引く相手の伏せ札）

    /// 卓。白い札は使わずフェルトに直に置く（文字は卓の上の色・`cardTableInk`）。
    private func tableArea(_ metrics: OldMaidLayoutA.Metrics) -> some View {
        VStack(spacing: 8) {
            if let target = model.humanTarget {
                targetPicker(target, metrics)
            } else {
                waitingPanel(metrics)
            }
            CardTableInkReader { ink in
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.fill")
                        .scaledFont(11, weight: .bold)
                    Text(tr("捨てたペア %lld組", model.game?.discardedPairs.count ?? 0))
                        .scaledFont(11, weight: .semibold, design: .rounded)
                    Spacer()
                    if let joker = jokerNote {
                        // フェルトの上で紫の文字は沈むので、紫の札に白い文字で出す。
                        Text(joker)
                            .scaledFont(11, weight: .bold, design: .rounded)
                            .foregroundStyle(Theme.onAccent)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.Fill.purple))
                    }
                }
                .foregroundStyle(ink.labelSub)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
    }

    /// 誰がジョーカーを持っているかは、あなた自身が持っているときだけ分かる。
    private var jokerNote: String? {
        model.playerHand.contains(where: \.isJoker) ? tr("ジョーカーはあなたの手に") : nil
    }

    /// あなたの番: 相手の顔と伏せ札。札をタップすると指をかけ、顔に出ることがある。
    private func targetPicker(_ target: Int, _ metrics: OldMaidLayoutA.Metrics) -> some View {
        let cards = model.hands[target]
        let face = model.face(of: target)
        return VStack(spacing: 8) {
            CardTableInkReader { ink in
                HStack(spacing: 10) {
                    OldMaidFaceView(face: face)
                        .frame(width: metrics.faceDiameter, height: metrics.faceDiameter)
                        .accessibilityLabel(tr("%1$@の顔、%2$@", model.playerName(target), OldMaidAccessibility.faceName(face)))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            // 席に名前を出さないので、引く相手は席と同じアイコンで示す（大富豪の「〜が出した」と同じ）。
                            OpponentSeatIcon(index: target, diameter: layout.scaled(16))
                            Text(tr("%@の札から1枚選んで引く", model.playerName(target)))
                                .scaledFont(13, weight: .bold, design: .rounded)
                                .foregroundStyle(ink.label)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        faceCaptionView(face, ink: ink)
                    }
                    Spacer(minLength: 0)
                }
            }
            .gameAnimation(.easeInOut(duration: 0.15), value: face)
            // 伏せ札が 2 段になると、縦の短い画面（iPhone SE）では下の手札の枠が潰れて札が 1 枚も見えなく
            // なっていた（v1.1.14 の公開前 QA・#2685）。伏せ札も枠の中でスクロールできるようにし、縮むのは 1 段ぶんまで。
            // 余裕のある画面では 2 段とも見える高さ（上限）まで広がる。選んだ札が 8pt 浮くぶん上に余白を取る。
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: OldMaidHandLayout.columnSpacing),
                                   count: OldMaidHandLayout.columns),
                    spacing: OldMaidHandLayout.rowSpacing
                ) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { position, card in
                        let isSelected = model.selectedID == card.id
                        OldMaidCardBackView(selected: isSelected, metrics: metrics.card)
                            .offset(y: isSelected ? -Self.selectedLift : 0)
                            .gameAnimation(.spring(response: 0.2), value: isSelected)
                            // 札は列幅 − 4pt。タップ判定は列いっぱい（44pt 以上・#195）。
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
                .frame(maxWidth: .infinity)
                .padding(.top, Self.selectedLift)
            }
            .frame(maxWidth: .infinity,
                   minHeight: targetGridHeight(rows: 1, metrics),
                   maxHeight: targetGridHeight(rows: OldMaidHandLayout.rows(cards.count), metrics))
        }
    }

    /// 顔色の一言。顔に出たとき（にやり / ひやり）は、フェルトの上でも目立つよう珊瑚色の札に白い文字で出す。
    @ViewBuilder
    private func faceCaptionView(_ face: OldMaidFace, ink: CardTableInk) -> some View {
        let caption = Text(faceCaption(face))
            .scaledFont(12, weight: .bold, design: .rounded)
            .lineLimit(1).minimumScaleFactor(0.6)
        if face == .neutral {
            caption.foregroundStyle(ink.labelSub)
        } else {
            caption
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Theme.Fill.coral))
        }
    }

    /// 選んだ伏せ札が浮き上がる高さ。
    private static let selectedLift: CGFloat = 8

    /// 伏せ札 `rows` 段ぶんの高さ（浮き上がりの余白を含む）。
    private func targetGridHeight(rows: Int, _ metrics: OldMaidLayoutA.Metrics) -> CGFloat {
        let card = max(metrics.card.height, OldMaidHandLayout.minimumTapTarget)
        return Self.selectedLift + card * CGFloat(rows) + OldMaidHandLayout.rowSpacing * CGFloat(rows - 1)
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
    private func waitingPanel(_ metrics: OldMaidLayoutA.Metrics) -> some View {
        let drawer = model.currentPlayer
        let from = model.game?.currentTarget
        return CardTableInkReader { ink in
            HStack(spacing: 10) {
                OldMaidFaceView(face: .neutral)
                    .frame(width: layout.scaled(40), height: layout.scaled(40))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if model.phase == .playing, let from {
                        Text(tr("%1$@が%2$@から引いています", model.playerName(drawer), model.playerName(from)))
                            .scaledFont(13, weight: .bold, design: .rounded)
                            .foregroundStyle(ink.label)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    if let note = lastTransferNote {
                        Text(note)
                            .scaledFont(12, weight: .semibold, design: .rounded)
                            .foregroundStyle(ink.labelSub)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 0)
            }
        }
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

    /// 手札 `rows` 段ぶんの高さ（グリッドの上の余白 4pt を含む）。
    private func handGridHeight(rows: Int, _ metrics: OldMaidLayoutA.Metrics) -> CGFloat {
        4 + metrics.card.height * CGFloat(rows) + OldMaidHandLayout.rowSpacing * CGFloat(rows - 1)
    }

    private func handArea(_ metrics: OldMaidLayoutA.Metrics) -> some View {
        let lastDrawn = model.lastDrawnCardID
        return VStack(spacing: 6) {
            CardTableInkReader { ink in
                HStack(spacing: 8) {
                    Text(tr("あなた（残り%lld枚）", model.playerHand.count))
                        .themeBody(13, maxScale: Self.seatTextMaxScale)
                        .foregroundStyle(ink.label)
                    Spacer()
                    Button {
                        model.shuffleHand()
                    } label: {
                        Label(tr("シャッフル"), systemImage: "shuffle")
                            .scaledFont(12, weight: .bold, design: .rounded)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            // フェルトの上では青緑・珊瑚色の文字が沈むので、白い札に載せる。押せる範囲は 44pt のまま。
                            .background(Capsule().fill(Theme.surface))
                            .frame(minHeight: OldMaidHandLayout.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pop)
                    .foregroundStyle(model.isJokerWatched ? Theme.coralText : Theme.tealText)
                    .disabled(!model.canShuffle)
                    .accessibilityHint(tr("手札の並びを混ぜます。ジョーカーの場所を覚えられなくなります"))
                }
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
                        OldMaidCardFaceView(card: card, highlighted: isLastDrawn, size: .table(metrics.card))
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
            // 縦の短い画面（iPhone SE）では手札の枠が札 1 段ぶんより低く潰れ、数字だけ見えてマークが
            // 切れていた（v1.1.14 の公開前 QA・#2685）。少なくとも 1 段は札が丸ごと見える高さを確保する。
            // 上限は全段ぶん（それより下に余りを溜めず、余りは卓の上下へ回す）。
            .frame(maxWidth: .infinity,
                   minHeight: handGridHeight(rows: 1, metrics),
                   maxHeight: handGridHeight(rows: OldMaidHandLayout.rows(model.playerHand.count), metrics))
            if model.isJokerWatched {
                // フェルトの上でも目立つよう、珊瑚色の札に白い文字で出す。
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .scaledFont(11, weight: .bold)
                    Text(tr("右端のジョーカーを見られています。シャッフルしよう"))
                        .scaledFont(11, weight: .bold, design: .rounded)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(Theme.Fill.coral))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
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
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .popCard(corner: Theme.cornerSmall)
        case .result:
            actionButton(tr("もう一回"), role: .primary) {
                model.startGame()
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
                    .foregroundStyle(won ? Theme.yellowText : Theme.purple)
                    .accessibilityHidden(true)
                Text(won ? tr("あなたの勝ち！") : tr("ジョーカーが残った…あなたの負け"))
                    .scaledFont(17, weight: .black, design: .rounded)
                    .foregroundStyle(won ? Theme.tealText : Theme.ink)
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
                        // 卓では席をアイコンで見分けているので、順位にも同じアイコンを添える（大富豪・いろリレーと同じ）。
                        if player != OldMaidModel.humanIndex {
                            OpponentSeatIcon(index: player, diameter: layout.scaled(24))
                        }
                        Text(model.playerName(player))
                            .scaledFont(13, weight: .bold, design: .rounded)
                            .foregroundStyle(player == OldMaidModel.humanIndex ? Theme.coralText : Theme.ink)
                        Spacer()
                        if isLoser {
                            OldMaidCardFaceView(card: .joker, highlighted: false, size: .mini)
                                .accessibilityLabel(tr("ジョーカーが残った"))
                        } else {
                            Text(tr("あがり"))
                                .scaledFont(12, weight: .semibold, design: .rounded)
                                .foregroundStyle(Theme.inkSubText)
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
        // 縦の余りをここで吸い、リザルトの下にフェルトの空白を残さない（大富豪 #193 と同じ）。
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

// MARK: - 全画面（A）の寸法

/// レイアウトパターン A でのババ抜きの寸法（#2531。大富豪の `DaifugoLayoutA` と同じ考え方）。
/// View を組まずに札の大きさ・SE での収まりをテストできるよう純関数にする（`OldMaidLayoutTests`）。
///
/// 手札・伏せ札は 7 列のまま、**札を列幅いっぱい（列幅 − 4pt）まで大きくする**（`PlayingCardMetrics.compact` の相似拡大）。
/// 広い画面（iPad）では倍率に上限（`maxCardScale` × `elementScale`）を掛ける。
enum OldMaidLayoutA {
    /// 画面の左右の余白（全画面の枠の値）。
    static let sideInset: CGFloat = FullScreenGameLayoutMetrics.sideInset
    /// 中身の上下の余白（ヘッダーの余白 4 / バナーの帯の余白 8 に足す分）。
    static let verticalInset: CGFloat = 2
    /// 段のあいだの間隔（大富豪と同じ）。
    static let spacing: CGFloat = 6
    /// 列のあいだに残す隙間（札の幅 = 列幅 − これ）。
    static let handGap: CGFloat = 4
    /// 札の拡大率の上限（狭い画面の倍率。iPad ではさらに `elementScale` 倍）。
    static let maxCardScale: CGFloat = 1.5
    /// 席のアイコンを小さい段に切り替える画面の幅（大富豪・いろリレーと同じ）。
    static let compactBreakpoint: CGFloat = 390

    struct Metrics: Equatable {
        /// 手札・伏せ札の札。
        let card: PlayingCardMetrics
        /// CPU の席のアイコンの直径。
        let seatDiameter: CGFloat
        /// CPU の席の裏向きの札。
        let seatCardMetrics: PlayingCardMetrics
        /// 引く相手の顔の直径（狭い画面は 44・それ以外は 52）。
        let faceDiameter: CGFloat
    }

    /// 1 列の幅（＝タップ判定の幅）。
    static func columnWidth(screenWidth: CGFloat) -> CGFloat {
        max(0, screenWidth - sideInset * 2) / CGFloat(OldMaidHandLayout.columns)
    }

    /// 札の拡大率（`PlayingCardMetrics.compact` に掛ける）。
    static func cardScale(screenWidth: CGFloat, elementScale: CGFloat = 1) -> CGFloat {
        let fit = (columnWidth(screenWidth: screenWidth) - handGap) / PlayingCardMetrics.compact.width
        return max(0, min(fit, maxCardScale * elementScale))
    }

    /// - Parameter contentHeight: 中身に使える高さ（全画面の枠のヘッダーの下からバナーの帯の上まで）。札は幅いっぱいまで
    ///   大きくするが、伏せ札・手札を 1 段ずつに縮めても収まらない高さ（iPhone SE）では、収まる大きさまでに抑える。
    static func metrics(screenWidth: CGFloat, contentHeight: CGFloat = .infinity, elementScale: CGFloat = 1) -> Metrics {
        let compact = screenWidth < compactBreakpoint
        let seatCardWidth = OpponentSeatStyle.cardWidth(compact: compact) * elementScale
        let seatDiameter = OpponentSeatStyle.iconDiameter(compact: compact) * elementScale
        let seatCard = PlayingCardMetrics.compact.scaled(by: seatCardWidth / PlayingCardMetrics.compact.width)
        let face = (compact ? 44 : 52) * elementScale
        // 札 2 段（伏せ札 1 段 + 手札 1 段）に回せる高さで抑える。下限は以前の札（42×60）の大きさ。
        let fixed = fixedMinimumHeight(seatDiameter: seatDiameter, seatCardHeight: seatCard.height, faceDiameter: face)
        let heightFit = (contentHeight - fixed) / 2 / PlayingCardMetrics.compact.height
        let scale = min(cardScale(screenWidth: screenWidth, elementScale: elementScale), max(1, heightFit))
        return Metrics(
            card: PlayingCardMetrics.compact.scaled(by: scale),
            seatDiameter: seatDiameter,
            seatCardMetrics: seatCard,
            faceDiameter: face
        )
    }

    /// 伏せ札・手札がどちらも 2 段（`-oldMaidScenario crowded`）で、ミニガイドとジョーカーの注意が出ているときに、
    /// 卓・手札を 1 段まで縮めて要る高さのうち、札 2 段ぶん以外の高さ（#2685 の「縮むのは 1 段ぶんまで」の下限）。
    /// 席（アイコン + 束 + 枚数の札 18 + 吹き出し 20）+ 卓（顔 + 8 + 浮き 8 + 8 + ペアの行 14）+
    /// 手札（見出し 44 + 6 + 4 + 6 + 注意 20）+ ミニガイド 22 + 操作欄 60 + 間隔（Spacer 2 つを含む 6 か所）+ 上下の余白。
    static func fixedMinimumHeight(seatDiameter: CGFloat, seatCardHeight: CGFloat, faceDiameter: CGFloat) -> CGFloat {
        let seat = seatDiameter + OpponentSeatStyle.spacing * 3 + seatCardHeight + 18 + 20
        let table = faceDiameter + 8 + 8 + 8 + 14
        let hand: CGFloat = 44 + 6 + 4 + 6 + 20
        let rows: [CGFloat] = [seat, 0, table, 0, hand, 22, 60]
        return rows.reduce(0, +) + spacing * CGFloat(rows.count - 1) + verticalInset * 2
    }

    /// 上の下限の高さ（札 2 段を含む）。`OldMaidLayoutTests` が SE の使える高さと突き合わせる。
    static func estimatedMinimumHeight(screenWidth: CGFloat, contentHeight: CGFloat = .infinity) -> CGFloat {
        let m = metrics(screenWidth: screenWidth, contentHeight: contentHeight)
        let card = max(m.card.height, OldMaidHandLayout.minimumTapTarget)
        return fixedMinimumHeight(seatDiameter: m.seatDiameter, seatCardHeight: m.seatCardMetrics.height,
                                  faceDiameter: m.faceDiameter) + card + m.card.height
    }
}

// MARK: - 手札グリッドの寸法

/// 手札・伏せ札グリッドの寸法（大富豪 #195・いろリレーと同じ考え方）。札は列幅 − 4pt（`OldMaidLayoutA`）、
/// タップ判定は列いっぱい。
enum OldMaidHandLayout {
    static let columns = 7
    static let columnSpacing: CGFloat = 0
    static let rowSpacing: CGFloat = 6
    /// Apple HIG の最小タップ標的。
    static let minimumTapTarget: CGFloat = 44

    /// 画面幅 `screenWidth` のときの、伏せ札 1 枚あたりのタップ判定の幅（= 列幅）。
    static func tapWidth(screenWidth: CGFloat) -> CGFloat {
        OldMaidLayoutA.columnWidth(screenWidth: screenWidth)
    }

    /// `count` 枚を並べる段数（0 枚でも 1 段ぶんの高さは取る）。
    static func rows(_ count: Int) -> Int {
        max(1, (count + columns - 1) / columns)
    }
}


// MARK: - 札（トランプ共通基盤）

/// 表向きの札。面・紙・ジョーカーの図案はトランプ共通基盤（`PlayingCardSurface` / `PlayingCardFace`・#397）。
struct OldMaidCardFaceView: View {
    enum Size {
        /// small = 42×60（遊び方の図）。mini はリザルトの行に添える大きさ。table は卓の手札（画面幅から決めた寸法をそのまま使う・#2531）。
        case small, mini, table(PlayingCardMetrics)
        var metrics: PlayingCardMetrics {
            switch self {
            case .small: return .compact
            case .mini:
                return PlayingCardMetrics(width: 24, height: 34, cornerRadius: Theme.cornerSmall / 3,
                                          rankFont: 9, suitFont: 9, pipSpacing: 0, backMotifFont: 10)
            case .table(let metrics): return metrics
            }
        }
    }

    let card: OldMaidCard
    var highlighted: Bool
    var size: Size = .small
    // 別ファイル（遊び方の図）からも memberwise init で作るので private にしない。
    @Environment(\.adaptiveLayout) var layout

    /// 卓の寸法（`.table`）は `OldMaidLayoutA` が倍率まで含めて決めているので、ここでは掛けない。
    private var metrics: PlayingCardMetrics {
        if case .table(let metrics) = size { return metrics }
        return size.metrics.scaled(by: layout.elementScale)
    }

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
    /// 卓の寸法（`OldMaidLayoutA` が画面幅から決める・#2531）。nil なら 42×60（遊び方の図）。
    var tableMetrics: PlayingCardMetrics? = nil
    // 別ファイル（遊び方の図）からも memberwise init で作るので private にしない。
    @Environment(\.adaptiveLayout) var layout

    init(selected: Bool, metrics: PlayingCardMetrics? = nil) {
        self.selected = selected
        self.tableMetrics = metrics
    }

    private var metrics: PlayingCardMetrics {
        tableMetrics ?? PlayingCardMetrics.compact.scaled(by: layout.elementScale)
    }

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
    /// 対局中に開いたとき true（開始ボタンが「終了してスタート」になる）。決着後・開始待ちは通常の「スタート」。
    let discardsProgress: Bool
    let onStart: (Int) -> Void
    let onCancel: () -> Void

    init(aiLevel: Int, discardsProgress: Bool = false, onStart: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        _level = State(initialValue: aiLevel)
        self.discardsProgress = discardsProgress
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        GameSetupSheet(
            kind: .versus,
            discardsProgress: discardsProgress,
            onboarding: OldMaidOnboarding.guide,
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
