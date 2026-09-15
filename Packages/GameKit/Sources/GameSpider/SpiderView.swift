import Foundation
import SwiftUI
import Core

/// スパイダーソリティアの画面（#717）。組み立てはフリーセル `FreeCellView` と同じ。
public struct SpiderView: View {
    @State private var model: SpiderModel
    /// 配り直しの開始シート（スート数を選ぶ）。**初回の配札では出さない**（既定の 1 スートで即座に配る）。
    /// ソリティア（#498）と同じく、途中の盤面があるときの警告と最終確認（キャンセルできる「配る」）を兼ねる。
    @State private var showSetup = false
    /// 開始シートで選んでいる最中のルール。「配る」を押すまで局には効かない（1局=1RuleSet）。
    @State private var draft = SpiderRuleSet.standard
    /// ドラッグ中の札（指の位置は入れない・#521）。
    @State private var drag: SpiderDragState?
    /// ドラッグ中の指の位置。盤本体から切り離すために参照型に逃がす（#521・#524）。
    @State private var dragLocation = CardDragLocation()
    /// ドロップ先の当たり判定枠（盤スクロール座標系）。
    @State private var dropFrames: [SpiderDropTarget: CGRect] = [:]
    /// 無料の「戻す」を使い切った状態でボタンを押したときの提案。**自動再生はしない**。
    @State private var showUndoRefillPrompt = false
    /// 「戻す」補充のリワード広告の段取り（#526）。
    @State private var undoRescue = RewardedRescue()
    /// 拡大モード（#604）。既定は等倍。
    @State private var zoomMode = false
    /// 「空いた列があるので配れません」の案内を出しているか。
    @State private var showDealBlockedHint = false

    private static let boardSpace = "spiderBoard"
    @Namespace private var cardMotion
    private let services: GameServices
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        self.services = services
        var rules = SpiderRuleSet.standard
        #if DEBUG
        // 撮影用: `-spiderSuits 2` のように起動引数でスート数を指定できる（中断データが無いときだけ効く）。
        if let suits = SpiderSuitCount(rawValue: UserDefaults.standard.integer(forKey: "spiderSuits")) {
            rules = SpiderRuleSet(suitCount: suits)
        }
        #endif
        _model = State(initialValue: SpiderModel(services: services, rules: rules))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            board.layoutPriority(1)
            HowToPlayHint(.spider, playLog: services.playLog)
            controlArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .gameChrome(title: "スパイダーソリティア", review: services.review) {
            ToolbarItem(placement: .primaryAction) {
                Button { openSetup() } label: {
                    Label("新規ゲーム", systemImage: "plus.circle.fill")
                }
                .accessibilityLabel("新しい配札にする")
            }
        }
        .howToPlay(.spider) { SpiderRuleSheet() }
        .sheet(isPresented: $showSetup) {
            SpiderSetupSheet(draft: $draft, discardsProgress: model.canUndo) {
                showSetup = false
                model.newGame(rules: draft)
            } onCancel: {
                showSetup = false
            }
        }
        .alert("無料の「戻す」を使い切りました", isPresented: $showUndoRefillPrompt) {
            Button("広告を見て\(SpiderUndoBudget.refill)回補充する") { requestUndoRefill() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴すると「戻す」を\(SpiderUndoBudget.refill)回ぶん補充します。\n盤面はそのままです。")
        }
        .rewardOffer(undoRescue, for: .undo, isPresented: showUndoRefillPrompt,
                     services: services, gameID: model.gameID)
        .rewardedRescueAlerts(
            undoRescue,
            notEarned: "「戻す」を補充できませんでした",
            unavailable: RewardUnavailableAlert(
                title: "「戻す」を補充できませんでした",
                message: "広告を見ているあいだに配り直されたか、局が終わったため、補充できませんでした。\n新しい配札の「戻す」は無料の回数まで戻っています。"
            )
        )
        .overlay {
            if model.showsDeadEndPrompt { deadEndOverlay }
        }
        .onChange(of: model.dealBlockedCount) { _, _ in
            showDealBlockedHint = true
        }
        .onChange(of: model.board.isDealBlockedByEmptyPile) { _, blocked in
            if !blocked { showDealBlockedHint = false }
        }
        .task {
            model.resumeTimerIfNeeded()
            #if DEBUG
            // 撮影用（#717）: 遊んでいる最中・行き止まり・開始シート・拡大の面を機械的に作る。
            if ProcessInfo.processInfo.arguments.contains("-spiderMidgame") {
                model.applyPreviewProgressForTesting()
            }
            if ProcessInfo.processInfo.arguments.contains("-spiderDeadEnd") {
                model.applyDeadEndPreviewForTesting()
            }
            if ProcessInfo.processInfo.arguments.contains("-spiderZoom") {
                zoomMode = true
            }
            if ProcessInfo.processInfo.arguments.contains("-spiderSetup") {
                openSetup()
            }
            #endif
        }
        .onDisappear { model.pauseTimer() }
    }

    /// 開始シートを開く。**いま遊んでいるルールを初期選択にする**（#498 と同じ）。
    private func openSetup() {
        draft = model.rules
        showSetup = true
    }

    // MARK: - ステータスバー

    private var statusBar: some View {
        HStack(spacing: 8) {
            statusReadout

            BoardToggleButton(
                isOn: zoomMode,
                systemImage: zoomMode ? "minus.magnifyingglass" : "plus.magnifyingglass",
                title: zoomMode ? "全体" : "拡大",
                fill: Theme.Fill.teal,
                accent: Theme.teal,
                label: zoomMode ? "盤全体を表示" : "札を拡大"
            ) {
                zoomMode.toggle()
            }
            .accessibilityHint(zoomMode
                ? "等倍に戻して盤全体を画面に収めます"
                : "札を大きくして指で押しやすくします。はみ出した列は横にスクロールします")
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .contain)
    }

    private var statusReadout: some View {
        HStack(spacing: 0) {
            Group {
                if model.phase == .won {
                    Label("クリア！", systemImage: "flag.checkered")
                        .themeBody(15)
                        .foregroundStyle(Theme.teal)
                } else {
                    Label("\(model.moveCount)手", systemImage: "hand.tap.fill")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.coral)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 78, alignment: .leading)

            Spacer()

            VStack(spacing: 0) {
                Text(stateEmoji).font(.system(size: 24))
                // 数値の桁区切りを避けるため文字列にしてから渡す（フリーセル #492 の実測）。
                Text(verbatim: model.rules.suitCount.label + " #" + String(model.dealNumber))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.inkSub)
            }

            Spacer()

            Label(RecordFormat.time(model.elapsedSeconds), systemImage: "clock")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.teal)
                .frame(minWidth: 78, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpiderAccessibility.statusLabel(
            phase: model.phase,
            suitCount: model.rules.suitCount,
            elapsedSeconds: model.elapsedSeconds,
            moveCount: model.moveCount,
            dealNumber: model.dealNumber,
            dealsRemaining: model.board.dealsRemaining,
            completedCount: model.board.completed.count,
            isDeadEnd: model.isDeadEnd
        ))
    }

    private var stateEmoji: String {
        if model.phase == .won { return "🎉" }
        return model.isDeadEnd ? "😵" : "🕷️"
    }

    // MARK: - 盤面

    private var board: some View {
        GeometryReader { geo in
            let width = cardWidth(availableWidth: geo.size.width)
            let metrics = SpiderMetrics.faceMetrics(width: width)
            ScrollView(zoomMode ? [.horizontal, .vertical] : [.vertical], showsIndicators: false) {
                VStack(spacing: SpiderMotion.topRowSpacing) {
                    topRow(metrics: metrics)
                    tableau(metrics: metrics)
                }
                .frame(width: SpiderMetrics.boardWidth(cardWidth: width))
                .padding(.top, 2)
                // 盤が画面より狭いときは中央、広いとき（拡大）は横スクロール。縦の浮き上がり止めは #604 の実測。
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .top)
            }
            .coordinateSpace(name: Self.boardSpace)
            .onPreferenceChange(CardDropFramesKey<SpiderDropTarget>.self) { dropFrames = $0 }
            .overlay(alignment: .topLeading) { dragOverlay(metrics: metrics) }
            .gameAnimation(SpiderMotion.move, value: boardAnimationKey)
        }
    }

    /// 札の幅（#604）。**等倍と拡大の分岐はここ 1 か所だけ**にする。
    private func cardWidth(availableWidth: CGFloat) -> CGFloat {
        let maxWidth = layout.scaled(SpiderMetrics.maxCardWidth)
        return zoomMode
            ? SpiderMetrics.zoomedCardWidth(availableWidth: availableWidth, maxWidth: maxWidth)
            : SpiderMetrics.cardWidth(availableWidth: availableWidth, maxWidth: maxWidth)
    }

    /// 盤面の演出を起こす値。`.gameAnimation` は盤面に 1 つだけ掛ける（#199）。
    private var boardAnimationKey: BoardKey {
        BoardKey(
            completed: model.board.completed.count,
            dealsRemaining: model.board.dealsRemaining,
            pileCounts: model.board.piles.map { $0.faceDownCount * 100 + $0.faceUpCount },
            selection: model.selection
        )
    }

    private struct BoardKey: Equatable {
        let completed: Int
        let dealsRemaining: Int
        let pileCounts: [Int]
        let selection: SpiderSelection?
    }

    // MARK: - ドラッグ&ドロップ

    @ViewBuilder private func dragOverlay(metrics: PlayingCardMetrics) -> some View {
        if let drag {
            CardDragLayer(
                cards: drag.cards,
                grab: drag.grab,
                location: dragLocation,
                step: SpiderMetrics.faceUpStep(cardHeight: metrics.height)
            ) { index, card in
                SpiderCardBody(card: card, faceUp: true, isSelected: false,
                               isCovered: index < drag.cards.count - 1, metrics: metrics)
            }
        }
    }

    /// 札のドラッグ。移動の成立・拒否は既存のタップ操作（選択→行き先）をそのまま呼ぶ。
    private func dragGesture(source: SpiderSelection, metrics: PlayingCardMetrics) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.boardSpace))
            .onChanged { value in
                if drag == nil {
                    guard model.phase == .playing,
                          let cards = draggableCards(from: source), !cards.isEmpty else { return }
                    model.deselect()
                    dragLocation.point = value.location
                    drag = SpiderDragState(
                        source: source,
                        cards: cards,
                        grab: CGSize(width: metrics.width / 2, height: metrics.height / 3)
                    )
                    services.feedback.impact(.rigid)
                } else {
                    dragLocation.point = value.location
                }
            }
            .onEnded { value in
                guard let current = drag else { return }
                drag = nil
                resolveDrop(of: current, at: value.location)
            }
    }

    /// ドラッグで持ち上げられる札の並び（同じスートで降順に揃った並びだけ）。
    private func draggableCards(from source: SpiderSelection) -> [SpiderCard]? {
        guard model.board.piles.indices.contains(source.pile),
              model.board.piles[source.pile].cards.indices.contains(source.cardIndex),
              model.board.isMovableRun(pile: source.pile, from: source.cardIndex) else { return nil }
        return Array(model.board.piles[source.pile].cards[source.cardIndex...])
    }

    /// 指を離した位置のドロップ先を探し、既存のタップ操作を再現して移動を試みる。
    private func resolveDrop(of drag: SpiderDragState, at point: CGPoint) {
        guard let target = dropFrames.first(where: { $0.value.contains(point) })?.key else { return }
        guard case .pile(let to) = target, to != drag.source.pile else { return }

        model.deselect()
        model.tapPile(drag.source.pile, cardIndex: drag.source.cardIndex)
        model.tapPile(to)
        if model.selection != nil { model.deselect() }
    }

    private func motionID(_ card: SpiderCard) -> CardMotionID {
        CardMotionID(deal: model.dealSerial, card: card.id)
    }

    private func isLifted(pile: Int, cardIndex: Int) -> Bool {
        guard let drag else { return false }
        return drag.source.pile == pile && cardIndex >= drag.source.cardIndex
    }

    // MARK: - 上段（山札・完成した組）

    /// 左端が山札、右側に完成した組の置き場が 8 つ。合わせて 9 枠なので 10 列の盤幅に収まる。
    private func topRow(metrics: PlayingCardMetrics) -> some View {
        HStack(spacing: SpiderMetrics.columnGap) {
            stockView(metrics: metrics)
            Spacer(minLength: 0)
            ForEach(0..<SpiderBoard.sequenceGoal, id: \.self) { slot in
                foundationView(slot: slot, metrics: metrics)
            }
        }
    }

    private func stockView(metrics: PlayingCardMetrics) -> some View {
        let remaining = model.board.dealsRemaining
        return ZStack(alignment: .bottomTrailing) {
            if remaining > 0 {
                // 残りの配りの枚数ぶん、わずかにずらして重ねる（残り回数が見た目でも分かる）。
                ForEach(0..<remaining, id: \.self) { index in
                    ZStack {
                        PlayingCardSurface(faceUp: false, cornerRadius: metrics.cornerRadius)
                        PlayingCardBack(metrics: metrics)
                    }
                    .frame(width: metrics.width, height: metrics.height)
                    .offset(x: CGFloat(index) * 1.5, y: -CGFloat(index) * 1.5)
                }
                Text(verbatim: "×\(remaining)")
                    .font(.system(size: max(9, metrics.rankFont * 0.55), weight: .black, design: .rounded))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.Fill.coral))
                    .offset(x: 4, y: 4)
            } else {
                CardSlot(metrics: metrics, systemImage: "tray")
            }
        }
        .frame(width: metrics.width, height: metrics.height)
        .contentShape(Rectangle())
        .onTapGesture { model.tapStock() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpiderAccessibility.stockLabel(
            dealsRemaining: remaining,
            isBlockedByEmptyPile: model.board.isDealBlockedByEmptyPile))
        .accessibilityHint(remaining > 0 ? "各列に1枚ずつ配ります" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapStock() }
    }

    private func foundationView(slot: Int, metrics: PlayingCardMetrics) -> some View {
        let completed = model.board.completed
        return Group {
            if slot < completed.count {
                let suit = completed[slot]
                // 取り除いた組は K の面で示す。
                ZStack {
                    PlayingCardSurface(cornerRadius: metrics.cornerRadius)
                    PlayingCardFace(figure: .pip(suit: suit.playingCardSuit, rank: 13), metrics: metrics)
                        .frame(width: metrics.width, height: metrics.height)
                }
                .frame(width: metrics.width, height: metrics.height)
            } else {
                CardSlot(metrics: metrics, systemImage: "checkmark")
            }
        }
        .accessibilityHidden(slot != 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpiderAccessibility.completedLabel(count: completed.count))
    }

    // MARK: - 場札

    private func tableau(metrics: PlayingCardMetrics) -> some View {
        HStack(alignment: .top, spacing: SpiderMetrics.columnGap) {
            ForEach(0..<SpiderBoard.pileCount, id: \.self) { pile in
                pileView(pile: pile, metrics: metrics)
            }
        }
    }

    private func pileView(pile: Int, metrics: PlayingCardMetrics) -> some View {
        let column = model.board.piles[pile]
        let downStep = SpiderMetrics.faceDownStep(cardHeight: metrics.height)
        let upStep = SpiderMetrics.faceUpStep(cardHeight: metrics.height)
        let height = SpiderMetrics.pileHeight(
            faceDownCount: column.faceDownCount, faceUpCount: column.faceUpCount, cardHeight: metrics.height)

        return ZStack(alignment: .top) {
            if column.isEmpty {
                CardSlot(metrics: metrics, systemImage: "square.dashed")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SpiderAccessibility.emptyPileLabel(pile: pile))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.tapPile(pile) }
            } else {
                Color.clear.frame(width: metrics.width, height: height)
            }

            // 札の同一性は**位置ではなく札そのもの**に持たせる（#421）。
            ForEach(Array(column.cards.enumerated()), id: \.element.id) { index, card in
                let faceUp = column.isFaceUp(index)
                let restY = CGFloat(min(index, column.faceDownCount)) * downStep
                    + CGFloat(max(0, index - column.faceDownCount)) * upStep
                Group {
                    if faceUp {
                        faceUpCard(pile: pile, index: index, card: card, column: column,
                                   restY: restY, metrics: metrics)
                    } else {
                        faceDownCard(pile: pile, index: index, card: card, column: column,
                                     restY: restY, metrics: metrics)
                    }
                }
                // 段差は `.offset` ではなく余白で作る（移動の補間が札の位置どうしを結ぶように）。
                .padding(.top, restY)
            }
        }
        .frame(width: metrics.width, height: height, alignment: .top)
        .cardDropTarget(SpiderDropTarget.pile(pile), in: Self.boardSpace)
        .contentShape(Rectangle())
        .onTapGesture { model.tapPile(pile) }
    }

    private func faceDownCard(
        pile: Int, index: Int, card: SpiderCard, column: SpiderPile,
        restY: CGFloat, metrics: PlayingCardMetrics
    ) -> some View {
        SpiderDealtCardView(
            pile: pile, depth: index, restY: restY, metrics: metrics,
            dealing: model.isFreshDeal, fromStock: false
        ) {
            SpiderCardBody(card: card, faceUp: false, isSelected: false, isCovered: false, metrics: metrics)
        }
        .id(model.dealSerial)
        .matchedGeometryEffect(id: motionID(card), in: cardMotion)
        // 伏せ札は 1 列ぶんをまとめて 1 要素で読む（枚数だけが情報）。
        .accessibilityHidden(index != 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpiderAccessibility.faceDownLabel(pile: pile, count: column.faceDownCount))
    }

    private func faceUpCard(
        pile: Int, index: Int, card: SpiderCard, column: SpiderPile,
        restY: CGFloat, metrics: PlayingCardMetrics
    ) -> some View {
        let isSelected = model.selection == SpiderSelection(pile: pile, cardIndex: index)
        let isMovable = model.board.isMovableRun(pile: pile, from: index)
        let fromStock = model.lastDealtCardIDs.contains(card.id)
        return SpiderDealtCardView(
            pile: pile, depth: index, restY: restY, metrics: metrics,
            dealing: model.isFreshDeal || fromStock, fromStock: fromStock
        ) {
            SpiderCardBody(
                card: card, faceUp: true, isSelected: isSelected,
                // いちばん上の 1 枚だけが札の全体を出す（下に重なった札は左上の見出しだけ）。
                isCovered: index < column.cards.count - 1,
                metrics: metrics
            )
        }
        .id(model.dealSerial)
        .matchedGeometryEffect(id: motionID(card), in: cardMotion)
        .opacity(isLifted(pile: pile, cardIndex: index) ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture { model.tapPile(pile, cardIndex: index) }
        .highPriorityGesture(dragGesture(
            source: SpiderSelection(pile: pile, cardIndex: index), metrics: metrics))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpiderAccessibility.tableauCardLabel(
            pile: pile,
            position: index,
            aboveCount: column.cards.count - index - 1,
            card: card,
            isSelected: isSelected,
            isMovable: isMovable
        ))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapPile(pile, cardIndex: index) }
    }

    // MARK: - 盤の下の操作エリア

    private var controlArea: some View {
        GameControlArea(isFinished: model.phase == .won, services: services) {
            resultControls
        } playing: {
            gameControls
        }
    }

    private var resultControls: some View {
        HStack(spacing: 12) {
            RecordLabel(model.recordResult)
                .lineLimit(1).minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Button { model.newGame() } label: {
                Label("次のゲーム", systemImage: "arrow.clockwise")
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Fill.coral))
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var gameControls: some View {
        HStack(spacing: 8) {
            controlButton("戻す\(model.undosRemaining)",
                          systemImage: "arrow.uturn.backward",
                          tint: Theme.Fill.coral) {
                requestUndo()
            }
            .disabled(!model.canUndo || undoRescue.isWatching)
            .opacity(model.canUndo ? 1 : 0.4)
            .accessibilityLabel(SpiderAccessibility.undoButtonLabel(remaining: model.undosRemaining))
            .accessibilityHint(SpiderAccessibility.undoButtonHint(
                canUndo: model.canUndo, remaining: model.undosRemaining))

            controlButton("配る\(model.board.dealsRemaining)",
                          systemImage: "rectangle.stack.badge.plus",
                          tint: Theme.Fill.teal) {
                model.tapStock()
            }
            .disabled(model.board.dealsRemaining == 0)
            .opacity(model.board.dealsRemaining == 0 ? 0.4 : 1)
            .accessibilityLabel(SpiderAccessibility.stockLabel(
                dealsRemaining: model.board.dealsRemaining,
                isBlockedByEmptyPile: model.board.isDealBlockedByEmptyPile))

            if showDealBlockedHint && model.board.isDealBlockedByEmptyPile {
                // 「配る」が拒否された理由。空の列が埋まると自動で消える。
                Text("空の列を埋めると配れます")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.coral)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private func controlButton(
        _ title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Capsule().fill(tint))
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }

    // MARK: - 行き止まりの告知

    private var deadEndOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("😵").font(.system(size: 52))
                Text("指せる手がありません")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("どの札も置き先がなく、山札も配れません。この配札には勝ち筋があるので、手を戻せばやり直せます。")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                    .multilineTextAlignment(.center)

                if model.canUndo {
                    Button { requestUndo() } label: {
                        Label("1手戻す（残り\(model.undosRemaining)）", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.Fill.coral, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(Theme.onAccent)
                    }
                    .buttonStyle(.plain)
                    .disabled(undoRescue.isWatching)
                    .accessibilityLabel(SpiderAccessibility.undoButtonLabel(remaining: model.undosRemaining))
                    .accessibilityHint(SpiderAccessibility.undoButtonHint(
                        canUndo: model.canUndo, remaining: model.undosRemaining))
                }

                Button { openSetup() } label: {
                    Text("新しい配札にする")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                .buttonStyle(.plain)
                .disabled(undoRescue.isWatching)

                Button { model.dismissDeadEndPrompt() } label: {
                    Text("盤面を見る")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                .buttonStyle(.plain)
                .disabled(undoRescue.isWatching)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .contain)
        // 暗幕が背面のタップを塞ぐので、VoiceOver も告知の中だけを移動させる。
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(SpiderAccessibility.deadEndPromptLabel(
            canUndo: model.canUndo, remaining: model.undosRemaining))
    }

    /// 「戻す」の入口を 1 本にまとめる（#476 と同じ契約）。
    private func requestUndo() {
        if model.needsUndoRefill {
            showUndoRefillPrompt = true
        } else {
            model.undo()
        }
    }

    /// リワード広告 → 「戻す」の補充。
    private func requestUndoRefill() {
        let deal = model.dealSerial
        undoRescue.request(
            services, gameID: model.gameID, purpose: .undo,
            guardedBy: .checkedByGrant
        ) {
            model.grantUndos(forDeal: deal)
        }
    }
}

// 札 1 枚の見た目と配札の 1 枚は `SpiderCardViews.swift`（#916 で切り出し。`FreeCellCardViews.swift` と同じ形）。

// MARK: - 開始シート

/// 配り直すときにスート数を選ぶ開始シート（#717）。
///
/// **ここで選んだ値は配札と同時に焼き込まれ、その局の途中では変えられない**（1局=1RuleSet）。
/// 初回の配札では出さない（既定の 1 スートで即座に配る）。出るのはツールバーの「新規ゲーム」を
/// 押したときだけ。途中の盤面があるときは同じ警告をここに出し、確定のボタンを「終了して配る」にする。
struct SpiderSetupSheet: View {
    @Binding var draft: SpiderRuleSet
    let discardsProgress: Bool
    let onStart: () -> Void
    let onCancel: () -> Void

    private static let metrics = GameSetupChooser.Metrics(
        title: .title(20), subtitleSize: 11, titleMinimumScale: 0.6, subtitleMinimumScale: 0.7
    )

    var body: some View {
        GameSetupSheet(
            title: "新しい配札",
            startTitle: discardsProgress ? "終了して配る" : "配る",
            onStart: onStart, onCancel: onCancel
        ) {
            GameSetupSection("スートの数") {
                HStack(spacing: 12) {
                    tile(.one, accent: Theme.Fill.teal)
                    tile(.two, accent: Theme.Fill.yellow)
                    tile(.four, accent: Theme.Fill.coral)
                }
                Text(Self.footer(for: draft.suitCount))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
            }
            if discardsProgress {
                Label("途中で終了すると今の盤面が失われ、この配札は「クリアできなかった」として記録されます。",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.coral)
            }
        }
    }

    private func tile(_ value: SpiderSuitCount, accent: Color) -> some View {
        GameSetupChooser(title: value.label, subtitle: value.subtitle,
                         selected: draft.suitCount == value, accent: accent,
                         metrics: Self.metrics) {
            draft.suitCount = value
        }
    }

    /// スート数の説明。**記録の扱いまで書く**（自己ベストと順位表がスート数ごとに別枠であること）。
    static func footer(for suits: SpiderSuitCount) -> String {
        switch suits {
        case .one:
            return "♠だけの 104 枚。どの札もつなげられるので、並べ替えの練習に向いています。"
                + "自己ベストと Game Center の順位表はスート数ごとに別々です。"
        case .two:
            return "♠と♥の 104 枚。まとめて動かせるのは同じスートの並びだけなので、色を揃える読みが要ります。"
        case .four:
            return "4 種すべての 104 枚。もっとも難しく、配られる配札はすべて勝ち筋を確認済みです。"
        }
    }
}

// MARK: - くわしいルール

/// 「遊び方」シートから開く詳細ページ。組み方は `FreeCellRuleSheet` と同じ。
struct SpiderRuleSheet: View {
    /// 文言はテストから検証したいので型の外に出しておく。
    static let rules: [(String, String)] = [
        ("ゲームの流れ", "2組104枚を使います。場札（10列）で同じスートの札を K から A まで順に並べると、その13枚は自動的に場から取り除かれます。8組すべて取り除いたらクリアです"),
        ("札の置き方", "場札には、ひとつ上の札より1つ小さい札なら**スートを問わず**置けます（♠8 の上に ♥7）。空いた列にはどの札でも置けます"),
        ("まとめて動かす", "まとめて動かせるのは、同じスートで降順に揃った並びだけです（♠9♠8♠7 は動かせますが ♠9♥8 は 1 枚ずつ）。枚数の上限はありません"),
        ("山札を配る", "左上の山札をタップするか「配る」を押すと、各列に1枚ずつ配られます（5回ぶん）。**空いた列があると配れません**。先に何かを置いて埋めてください"),
        ("スートの数", "「新規ゲーム」で 1・2・4 スートを選べます。1スートは ♠ だけ、2スートは ♠♥、4スートは4種すべてです。自己ベストと Game Center の順位表はスート数ごとに別々です"),
        ("操作", "動かしたい札をタップして選び、置きたい列をタップします。ドラッグでも動かせます。もう一度同じ札をタップすると選択を外せます"),
        ("戻す", "「戻す」は1局につき\(SpiderUndoBudget.free)回まで無料です。残り回数はボタンに出ています。使い切ったあとは、広告を見ると\(SpiderUndoBudget.refill)回ぶん補充できます"),
        ("配られる札", "出題する配札は、すべて事前にコンピュータで解いてクリアできることを確かめてあります。行き止まりは配りのせいではなく、指し方で変わります。配札の番号は画面の上に出ています"),
    ]

    var body: some View {
        RuleListSheet(title: "ルール", rules: Self.rules)
    }
}

// MARK: - ドラッグ&ドロップ

/// ドラッグ中の札の状態。**持ち上げた瞬間から置くまで変わらない値だけを持つ**（#521・#524）。
struct SpiderDragState {
    var source: SpiderSelection
    var cards: [SpiderCard]
    var grab: CGSize
}

/// ドロップ先の種類。スパイダーは場札の列にしか置けない。
enum SpiderDropTarget: Hashable {
    case pile(Int)
}
