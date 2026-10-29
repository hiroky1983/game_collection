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
    /// ヒント（無料 3 回を使い切った後の広告）の段取り（#2025）。読みと広告はモデルが 1 本の非同期メソッドで持つ。
    @State private var hintRescue = RewardedRescue()
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
        #if DEBUG
        // 確認用（#1755）: クリアカードを遊ばずに出す。記録・中断データ・解析に触れない局で開く。
        if ProcessInfo.processInfo.arguments.contains("-spiderWon") {
            _model = State(initialValue: SpiderModel.clearPreviewForTesting(remainingMoves: 0))
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-spiderAlmostWon") {
            _model = State(initialValue: SpiderModel.clearPreviewForTesting(remainingMoves: 1))
            return
        }
        #endif
        var rules: SpiderRuleSet?
        #if DEBUG
        // 撮影用: `-spiderSuits 2` のように起動引数でスート数を指定できる（中断データが無いときだけ効く）。
        if let suits = SpiderSuitCount(rawValue: UserDefaults.standard.integer(forKey: "spiderSuits")) {
            rules = SpiderRuleSet(suitCount: suits)
        }
        #endif
        _model = State(initialValue: SpiderModel(services: services, rules: rules))
    }

    public var body: some View {
        // 左右の余白は部品ごとに付ける。盤だけは `boardSideInset`（4pt）まで詰めて札の幅に回し、
        // 帯・ヒント・ボタンは全画面の枠の左右の余白（8pt）。ソリティア・フリーセルと同じ。
        VStack(spacing: 8) {
            statusBar
                .padding(.horizontal, FullScreenGameLayoutMetrics.sideInset)
            // レイアウトパターン A（全画面・#2531）: 卓のフェルトは全画面の枠が画面全体に敷くので、盤に `.cardTable()`
            // （木枠付きの卓）は付けない。札の大きさは盤の幅から決まるので、木枠の分だけ大きくなる。
            // 札が帯に張り付いて見えないよう、卓の中の上の余白（`cardTopInset`・ソリティア系で共通）は残す。
            board
                .padding(.top, CardTableStyle.cardTopInset)
                // クリアは盤に重ねる共通のカードで示す（#1755）。
                .gameClearCard(isPresented: model.phase == .won,
                               details: [tr("%1$lld手 / タイム %2$@", model.moveCount, RecordFormat.time(model.elapsedSeconds))])
                .padding(.horizontal, SpiderMetrics.boardSideInset)
                .layoutPriority(1)
            controlArea
                .padding(.horizontal, FullScreenGameLayoutMetrics.sideInset)
            HowToPlayHint(.spider, playLog: services.playLog)
                .padding(.horizontal, FullScreenGameLayoutMetrics.sideInset)
            // 余りの高さは「⋯」の行とバナーの帯のあいだに置く（盤→「⋯」→余白→広告・#1485）。
            Spacer(minLength: 0)
        }
        // 上下はヘッダーの余白 4 とバナーの帯の余白 8 に足す分。
        .padding(.vertical, 4)
        // レイアウトパターン A（全画面・会長決裁 2026-10-22・#2111 → #2531）: フェルトを画面全体に敷き、ヘッダーは 1 行
        // （戻る・スパイダーソリティア・？・＋）、バナーは画面最下部。手数・スート・配札・時計はソリティア・フリーセルと
        // 同じくヘッダーの下に低い 1 行の札で残す。
        .gameChrome(title: tr("スパイダーソリティア"), review: services.review, fullScreen: .felt, ads: services.ads,
                    newGame: GameChromeNewGame(.solo) {
                        openSetup()
                    })
        .howToPlay(HowToPlayGuide.spider.illustrated(SpiderHowToFigures.items).onboarding(SpiderOnboarding.guide)) { SpiderRuleSheet() }
        .sheet(isPresented: $showSetup) {
            SpiderSetupSheet(draft: $draft, discardsProgress: model.canUndo) {
                showSetup = false
                model.newGame(rules: draft)
            } onCancel: {
                showSetup = false
            }
        }
        .dialogs { anchor in
            anchor.alert(tr("この盤からは勝てません"), isPresented: hopelessBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(tr("「戻す」で戻れます。ヒントの回数は減っていません。"))
            }
            .alert(tr("無料の「戻す」を使い切りました"), isPresented: $showUndoRefillPrompt) {
                Button(tr("広告を見て%lld回補充する", SpiderUndoBudget.refill)) { requestUndoRefill() }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("広告を最後まで視聴すると「戻す」を%lld回ぶん補充します。\n盤面はそのままです。", SpiderUndoBudget.refill))
            }
        }
        .rewardOffer(undoRescue, for: .undo, isPresented: showUndoRefillPrompt,
                     services: services, gameID: model.gameID)
        .rewardedRescueAlerts(
            undoRescue,
            notEarned: tr("「戻す」を補充できませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("「戻す」を補充できませんでした"),
                message: tr("広告を見ているあいだに配り直されたか、局が終わったため、補充できませんでした。\n新しい配札の「戻す」は無料の回数まで戻っています。")
            )
        )
        .rewardedRescueAlerts(
            hintRescue,
            notEarned: tr("ヒントを表示できませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("ヒントを出せませんでした"),
                message: tr("広告を見ているあいだに盤が変わったか、画面を離れたため、ヒントを出せませんでした。")
            )
        )
        .overlay {
            if model.showsDeadEndPrompt { deadEndOverlay }
        }
        // 示した手を VoiceOver にも一言で伝える（印は目で見る手がかりなので）。
        .onChange(of: model.hintMove) { _, move in
            guard let move else { return }
            AccessibilityNotification.Announcement(
                SpiderAccessibility.hintLabel(move: move, board: model.board)
            ).post()
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
            // ヒントの印（#2025）。シミュレータは自動タップができないため、起動引数から無料の 1 回を押した状態にする。
            if ProcessInfo.processInfo.arguments.contains("-spiderHint") {
                await model.requestHint()
            }
            if ProcessInfo.processInfo.arguments.contains("-spiderZoom") {
                zoomMode = true
            }
            if ProcessInfo.processInfo.arguments.contains("-spiderSetup") {
                openSetup()
            }
            #endif
        }
        // 画面を離れたら・背面に回ったら・広告の視聴中は計時を止め、戻ったら再開する
        // （#375・#1734・#1382。止め方・動かし方は `GameStopwatch` / `gameTimerLifecycle` に共通化・#1857）。
        .gameTimerLifecycle(
            rescues: [undoRescue, hintRescue],
            isHeld: showSetup,
            pause: { model.pauseTimer() },
            resume: { model.resumeTimerIfNeeded() }
        )
    }

    private var hopelessBinding: Binding<Bool> {
        Binding(get: { model.showsHintHopeless }, set: { if !$0 { model.dismissHintHopeless() } })
    }

    /// 開始シートを開く。**いま遊んでいるルールを初期選択にする**（#498 と同じ）。
    private func openSetup() {
        draft = model.rules
        showSetup = true
    }

    // MARK: - ステータスバー

    /// 帯には表示だけを置く。拡大の切り替えは右下の「⋯」へ（#1468）。
    /// 全画面（A・#2531）ではモックどおり 44pt の帯より低い 1 行の札にする（`GameStatusBarStyle.compactMinHeight`）。
    private var statusBar: some View {
        GameStatusBar(verticalPadding: GameStatusBarStyle.compactVerticalPadding,
                      minHeight: GameStatusBarStyle.compactMinHeight) {
            statusReadout
        } trailing: {
            EmptyView()
        }
        .accessibilityElement(children: .contain)
    }

    private var statusReadout: some View {
        HStack(spacing: 8) {
            Group {
                if model.phase == .won {
                    Label(tr("クリア！"), systemImage: "flag.checkered")
                        .themeBody(15)
                        .foregroundStyle(Theme.tealText)
                } else {
                    Label(tr("%lld手", model.moveCount), systemImage: "hand.tap.fill")
                        .scaledFont(15, weight: .bold, design: .monospaced)
                        .foregroundStyle(Theme.coralText)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            // 数値の桁区切りを避けるため文字列にしてから渡す（フリーセル #492 の実測）。
            Text(verbatim: model.rules.suitCount.label + " #" + String(model.dealNumber))
                .scaledFont(10, weight: .bold, design: .monospaced)
                .foregroundStyle(Theme.inkSubText)

            GameClockLabel(RecordFormat.time(model.elapsedSeconds), elapsedSeconds: model.elapsedSeconds)
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

    // MARK: - 盤面

    private var board: some View {
        GeometryReader { geo in
            let width = cardWidth(availableWidth: geo.size.width)
            let metrics = SpiderMetrics.faceMetrics(width: width)
            // 段差は盤の縦の余りに合わせて広げ、全列で同じ値を使う（フリーセルと同じ計算）。
            let stack = SpiderMetrics.stackLayout(
                cardWidth: metrics.width, cardHeight: metrics.height,
                boardHeight: geo.size.height, piles: model.board.piles)
            ScrollView(zoomMode ? [.horizontal, .vertical] : [.vertical], showsIndicators: false) {
                VStack(spacing: SpiderMotion.topRowSpacing) {
                    topRow(metrics: metrics)
                    tableau(metrics: metrics, stack: stack)
                }
                .frame(width: SpiderMetrics.boardWidth(cardWidth: width))
                .padding(.top, SpiderMetrics.boardTopPadding)
                // 盤が画面より狭いときは中央、広いとき（拡大）は横スクロール。縦の浮き上がり止めは #604 の実測。
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .top)
            }
            .coordinateSpace(name: Self.boardSpace)
            .onPreferenceChange(CardDropFramesKey<SpiderDropTarget>.self) { dropFrames = $0 }
            .overlay(alignment: .topLeading) { dragOverlay(metrics: metrics, stack: stack) }
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

    @ViewBuilder private func dragOverlay(metrics: PlayingCardMetrics, stack: CardStackLayout) -> some View {
        if let drag {
            CardDragLayer(
                cards: drag.cards,
                grab: drag.grab,
                location: dragLocation,
                step: stack.faceUpStep
            ) { index, card in
                SpiderCardBody(card: card, faceUp: true, isSelected: false,
                               coveredIndex: index < drag.cards.count - 1 ? stack.index : nil,
                               metrics: metrics)
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
                // 置けなかったとき、指の下の札が消えて元の札が「パッ」と濃くなるのを避け、
                // 薄さが戻る様子を見せる（#2707）。成功時の移動（0.2 秒）より少し短く。
                withGameAnimation(.easeOut(duration: 0.15)) { drag = nil }
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
                    .font(.system(size: max(9, metrics.rankFont * 0.55), weight: .black, design: .rounded)) // fixed-size: カード・セットアップ部品の寸法（metrics）に比例させる文字
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.Fill.coral))
                    .offset(x: 4, y: 4)
            } else {
                CardSlot(metrics: metrics, systemImage: "tray")
            }
        }
        .frame(width: metrics.width, height: metrics.height)
        // 手が「配る」のときは山札に点線を重ねて示す（#2025）。
        .overlay { hintFrame(model.hintsDeal, metrics: metrics) }
        .contentShape(Rectangle())
        .onTapGesture { model.tapStock() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpiderAccessibility.stockLabel(
            dealsRemaining: remaining,
            isBlockedByEmptyPile: model.board.isDealBlockedByEmptyPile))
        .accessibilityHint(remaining > 0 ? tr("各列に1枚ずつ配ります") : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapStock() }
    }

    private func foundationView(slot: Int, metrics: PlayingCardMetrics) -> some View {
        let completed = model.board.completed
        return Group {
            if slot < completed.count {
                let suit = completed[slot]
                let kingID = model.board.completedKingIDs.indices.contains(slot)
                    ? model.board.completedKingIDs[slot] : nil
                // 取り除いた組は K の面で示す。
                foundationKing(suit: suit, kingID: kingID, metrics: metrics)
            } else {
                CardSlot(metrics: metrics, systemImage: "checkmark")
            }
        }
        .accessibilityHidden(slot != 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpiderAccessibility.completedLabel(count: completed.count))
    }

    /// 完成枠の K。場の K と同じ ID で補間を付け、組がそろった瞬間に場から枠へ滑らせる（#2708）。
    @ViewBuilder private func foundationKing(suit: SpiderSuit, kingID: Int?, metrics: PlayingCardMetrics) -> some View {
        let face = ZStack {
            PlayingCardSurface(cornerRadius: metrics.cornerRadius)
            PlayingCardFace(figure: .pip(suit: suit.playingCardSuit, rank: 13), metrics: metrics)
                .frame(width: metrics.width, height: metrics.height)
        }
        .frame(width: metrics.width, height: metrics.height)
        if let kingID {
            face.matchedGeometryEffect(id: CardMotionID(deal: model.dealSerial, card: kingID), in: cardMotion)
        } else {
            face
        }
    }

    // MARK: - 場札

    private func tableau(metrics: PlayingCardMetrics, stack: CardStackLayout) -> some View {
        HStack(alignment: .top, spacing: SpiderMetrics.columnGap) {
            ForEach(0..<SpiderBoard.pileCount, id: \.self) { pile in
                pileView(pile: pile, metrics: metrics, stack: stack)
            }
        }
    }

    private func pileView(pile: Int, metrics: PlayingCardMetrics, stack: CardStackLayout) -> some View {
        let column = model.board.piles[pile]
        let downStep = stack.faceDownStep
        let upStep = stack.faceUpStep
        let height = SpiderMetrics.pileHeight(
            faceDownCount: column.faceDownCount, faceUpCount: column.faceUpCount, cardHeight: metrics.height,
            faceDownStep: downStep, faceUpStep: upStep)

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
                                   restY: restY, metrics: metrics, stack: stack)
                    } else {
                        faceDownCard(pile: pile, index: index, card: card, column: column,
                                     restY: restY, metrics: metrics)
                    }
                }
                // 段差は `.offset` ではなく余白で作る（移動の補間が札の位置どうしを結ぶように）。
                .padding(.top, restY)
            }
        }
        // 行き先の列は、いちばん上の札（空列なら枠）に点線を重ねて示す（#2025）。
        .overlay(alignment: .top) {
            hintFrame(model.hintDestinationPile == pile, metrics: metrics)
                .padding(.top, column.isEmpty ? 0 : max(height - metrics.height, 0))
        }
        // 押せる範囲（ドロップ枠を含む）は**盤の下端まで**伸ばす（フリーセルと同じ）。
        .frame(width: metrics.width, height: max(height, stack.reachHeight), alignment: .top)
        .cardDropTarget(SpiderDropTarget.pile(pile), in: Self.boardSpace)
        .contentShape(Rectangle())
        .onTapGesture { tapBelowPile(pile) }
    }

    /// 列の下の空き（札の無いところ）を押したとき。**一番下の札を押したのと同じ**にする
    /// （空の列なら空の列を押したのと同じ）。ドラッグは札にだけ付いているので、ここからは始まらない。
    private func tapBelowPile(_ pile: Int) {
        let count = model.board.piles[pile].cards.count
        if count == 0 {
            model.tapPile(pile)
        } else {
            model.tapPile(pile, cardIndex: count - 1)
        }
    }

    private func faceDownCard(
        pile: Int, index: Int, card: SpiderCard, column: SpiderPile,
        restY: CGFloat, metrics: PlayingCardMetrics
    ) -> some View {
        SpiderDealtCardView(
            pile: pile, depth: index, restY: restY, metrics: metrics,
            dealing: model.isFreshDeal, fromStock: false
        ) {
            SpiderCardBody(card: card, faceUp: false, isSelected: false, coveredIndex: nil, metrics: metrics)
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
        restY: CGFloat, metrics: PlayingCardMetrics, stack: CardStackLayout
    ) -> some View {
        let isSelected = model.selection == SpiderSelection(pile: pile, cardIndex: index)
        let isMovable = model.board.isMovableRun(pile: pile, from: index)
        let isHinted = model.hintSource.map { $0.pile == pile && index >= $0.cardIndex } ?? false
        let fromStock = model.lastDealtCardIDs.contains(card.id)
        return SpiderDealtCardView(
            pile: pile, depth: index, restY: restY, metrics: metrics,
            dealing: model.isFreshDeal || fromStock, fromStock: fromStock
        ) {
            SpiderCardBody(
                card: card, faceUp: true, isSelected: isSelected, isHinted: isHinted,
                // いちばん上の 1 枚だけが札の全体を出す（下に重なった札は左上の見出しだけ）。
                coveredIndex: index < column.cards.count - 1 ? stack.index : nil,
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

    /// クリアが続いたら一段上のスート数を勧める（#2599）。始め直しは開始シートの「配る」と同じ経路。
    private var ladder: DifficultyLadderPrompt? {
        let counts = SpiderSuitCount.allCases
        return DifficultyLadderPrompt(result: model.recordResult, currentLevel: counts.firstIndex(of: model.rules.suitCount),
                                      levelLabels: counts.map(\.label)) { level in
            model.newGame(rules: SpiderRuleSet(suitCount: counts[level]))
        }
    }

    private var controlArea: some View {
        GameControlArea(isFinished: model.phase == .won, services: services, ladder: ladder) {
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
                Label(tr("もう一回"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.game(.primary))

            Button { model.restartSameDeal() } label: {
                Text(tr("同じ配札で"))
            }
            .buttonStyle(.game(.skip))
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var gameControls: some View {
        // 戻す（無料 3 回のあと広告）は盤の下の段のカプセルに出し、配る・拡大（広告なし）は右下の「⋯」に残す
        // （#1468・#1856・会長決裁 2026-10-06「段に出すのは広告が絡む操作だけ」）。
        GameOverflowBar(
            menuItems: [
                GameControlMenuItem(
                    id: "deal", title: tr("配る（残り%lld）", model.board.dealsRemaining),
                    systemImage: "rectangle.stack.badge.plus",
                    isEnabled: model.board.dealsRemaining > 0,
                    accessibilityLabel: SpiderAccessibility.stockLabel(
                        dealsRemaining: model.board.dealsRemaining,
                        isBlockedByEmptyPile: model.board.isDealBlockedByEmptyPile)
                ) { model.tapStock() },
                GameControlMenuItem(
                    id: "zoom", title: tr("拡大"), systemImage: "plus.magnifyingglass", isChecked: zoomMode,
                    accessibilityLabel: zoomMode ? tr("盤全体を表示") : tr("札を拡大"),
                    accessibilityHint: zoomMode
                        ? tr("等倍に戻して盤全体を画面に収めます")
                        : tr("札を大きくして指で押しやすくします。はみ出した列は横にスクロールします")
                ) { zoomMode.toggle() },
            ],
            actions: [
                // 残り回数は 2 行目に出し、無料枠を使い切ったら「▶ 広告を見て」。押せない間も項目は残す。
                GameActionItem(
                    id: "undo", title: tr("戻す"), systemImage: "arrow.uturn.backward", role: .undo,
                    badge: model.undosRemaining > 0 ? .count(model.undosRemaining) : .ad(gain: RewardedUndoBudget.refill),
                    isEnabled: model.canUndo && !undoRescue.isWatching,
                    accessibilityLabel: SpiderAccessibility.undoButtonLabel(remaining: model.undosRemaining),
                    accessibilityHint: SpiderAccessibility.undoButtonHint(
                        canUndo: model.canUndo, remaining: model.undosRemaining)
                ) { requestUndo() },
                hintAction,
            ],
            nudge: hintNudge,
            // 「配る」が拒否された理由。段と「⋯」のあいだに出て、空の列が埋まると自動で消える。
            caption: showDealBlockedHint && model.board.isDealBlockedByEmptyPile
                ? GameOverflowCaption(tr("空の列を埋めると配れます"), color: Theme.coralText)
                : nil
        )
    }

    /// 盤の下の「操作の段」のヒント（#2025・#1856）。数字は「いま使える回数」で、無料を使い切ったら「▶ 広告を見て」（#1897）。
    private var hintAction: GameActionItem {
        let free = model.hints.freeRemaining
        return GameActionItem(
            id: "hint", title: tr("ヒント"), systemImage: "lightbulb.fill", role: .hint,
            badge: model.needsAdForHint ? .ad() : .count(free),
            isEnabled: model.canUseHint && !hintRescue.isWatching,
            accessibilityLabel: SpiderAccessibility.hintButtonLabel(
                freeRemaining: free, needsAd: model.needsAdForHint, isThinking: model.isHintThinking),
            accessibilityHint: tr("次に指す1手を、動かす札と行き先の列に紫の枠で示します。動かすのはあなたです")
        ) { requestHint() }
    }

    private var hintNudge: HintNudge {
        HintNudge(
            isEligible: HintNudgePolicy.isEligible(
                canUseHint: model.canUseHint, isWatchingAd: hintRescue.isWatching, showsBlockingPanel: model.showsDeadEndPrompt),
            game: model.dealSerial,
            activity: [model.moveCount, model.hints.used]
        )
    }

    /// ヒントの入口。無料の残りがあればそのまま読み、使い切っていたら読んでから広告を出す（#2025）。
    /// 読みは画面を離れたら取り消す（離脱後に確定すると回数・解析・中断データが動く・#1903）。
    private func requestHint() {
        guard !hintRescue.isWatching, model.canUseHint else { return }
        if model.needsAdForHint {
            hintRescue.requestHandledByModel(withOutcome: { readDidFinish in await model.requestAdHint(readDidFinish: readDidFinish) }, until: services.screenGeneration)
        } else {
            services.screenGeneration.runUntilLeave { await model.requestHint() }
        }
    }

    /// ヒントの行き先を示す点線の枠（#2025）。札 1 枚ぶんの大きさ。
    @ViewBuilder private func hintFrame(_ isOn: Bool, metrics: PlayingCardMetrics) -> some View {
        if isOn {
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .inset(by: 1.5)
                .stroke(BoardGameHintColor.color, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                .frame(width: metrics.width, height: metrics.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - 行き止まりの告知

    private var deadEndOverlay: some View {
        GameDeadEndPanel(
            emoji: "😵",
            title: tr("指せる手がありません"),
            message: tr("どの札も置き先がなく、山札も配れません。この配札には勝ち筋があるので、手を戻せばやり直せます。")
        ) {
            if model.canUndo {
                GameDeadEndActionButton(
                    tr("1手戻す（残り%lld）", model.undosRemaining), systemImage: "arrow.uturn.backward",
                    tint: Theme.Fill.coral, isDisabled: undoRescue.isWatching
                ) {
                    requestUndo()
                }
                .accessibilityLabel(SpiderAccessibility.undoButtonLabel(remaining: model.undosRemaining))
                .accessibilityHint(SpiderAccessibility.undoButtonHint(
                    canUndo: model.canUndo, remaining: model.undosRemaining))
            }

            // ソリティア・フリーセルと同じく今のスート数のまま即配り直す。変えたいときはナビバーの「新規ゲーム」から（#2600）。
            GameDeadEndDismissButton(tr("新しい配札にする"), isDisabled: undoRescue.isWatching) {
                model.newGame()
            }

            GameDeadEndDismissButton(tr("同じ配札でやり直す"), isDisabled: undoRescue.isWatching) {
                model.restartSameDeal()
            }

            GameDeadEndDismissButton(tr("盤面を見る"), isDisabled: undoRescue.isWatching) {
                model.dismissDeadEndPrompt()
            }
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

    var body: some View {
        GameSetupSheet(
            kind: .solo, discardsProgress: discardsProgress,
            onboarding: SpiderOnboarding.guide,
            onStart: onStart, onCancel: onCancel
        ) {
            GameSetupSection(tr("スートの数")) {
                HStack(spacing: 6) {
                    tile(.one, accent: DifficultyTile.accent(step: 0, of: 3))
                    tile(.two, accent: DifficultyTile.accent(step: 1, of: 3))
                    tile(.four, accent: DifficultyTile.accent(step: 2, of: 3))
                }
                Text(Self.footer(for: draft.suitCount))
                    .scaledFont(12, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.inkSubText)
            }
            if discardsProgress {
                Label(tr("途中で終了すると今の盤面が失われ、この配札は「クリアできなかった」として記録されます。"),
                      systemImage: "exclamationmark.triangle.fill")
                    .scaledFont(13, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.coralText)
            }
        }
    }

    private func tile(_ value: SpiderSuitCount, accent: Color) -> some View {
        GameSetupChooser(title: value.label, subtitle: value.subtitle,
                         selected: draft.suitCount == value, accent: accent,
                         metrics: DifficultyTile.metrics) {
            draft.suitCount = value
        }
    }

    /// スート数の説明。**記録の扱いまで書く**（自己ベストと順位表がスート数ごとに別枠であること）。
    static func footer(for suits: SpiderSuitCount) -> String {
        switch suits {
        case .one:
            return tr("♠だけの 104 枚。どの札もつなげられるので、並べ替えの練習に向いています。自己ベストと Game Center の順位表はスート数ごとに別々です。")
        case .two:
            return tr("♠と♥の 104 枚。まとめて動かせるのは同じスートの並びだけなので、色を揃える読みが要ります。")
        case .four:
            return tr("4 種すべての 104 枚。もっとも難しく、配られる配札はすべて勝ち筋を確認済みです。")
        }
    }
}

// MARK: - くわしいルール

/// 「遊び方」シートから開く詳細ページ。組み方は `FreeCellRuleSheet` と同じ。
struct SpiderRuleSheet: View {
    /// 文言はテストから検証したいので型の外に出しておく。
    static var rules: [(String, String)] { [
        (tr("ゲームの流れ"), tr("2組104枚を使います。場札（10列）で同じスートの札を K から A まで順に並べると、その13枚は自動的に場から取り除かれます。8組すべて取り除いたらクリアです")),
        (tr("札の置き方"), tr("場札には、ひとつ上の札より1つ小さい札なら**スートを問わず**置けます（♠8 の上に ♥7）。空いた列にはどの札でも置けます")),
        (tr("まとめて動かす"), tr("まとめて動かせるのは、同じスートで降順に揃った並びだけです（♠9♠8♠7 は動かせますが ♠9♥8 は 1 枚ずつ）。枚数の上限はありません")),
        (tr("山札を配る"), tr("左上の山札をタップするか「配る」を押すと、各列に1枚ずつ配られます（5回ぶん）。**空いた列があると配れません**。先に何かを置いて埋めてください")),
        (tr("スートの数"), tr("「新規ゲーム」で 1・2・4 スートを選べます。1スートは ♠ だけ、2スートは ♠♥、4スートは4種すべてです。自己ベストと Game Center の順位表はスート数ごとに別々です")),
        (tr("操作"), tr("動かしたい札をタップして選び、置きたい列をタップします。ドラッグでも動かせます。もう一度同じ札をタップすると選択を外せます")),
        (tr("戻す"), tr("「戻す」は1局につき%1$lld回まで無料です。残り回数はボタンに出ています。使い切ったあとは、広告を見ると%2$lld回ぶん補充できます", SpiderUndoBudget.free, SpiderUndoBudget.refill)),
        (tr("配られる札"), tr("出題する配札は、すべて事前にコンピュータで解いてクリアできることを確かめてあります。行き止まりは配りのせいではなく、指し方で変わります。配札の番号は画面の上に出ています")),
    ] }

    var body: some View {
        RuleListSheet(rules: Self.rules)
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
