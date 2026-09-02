import Foundation
import SwiftUI
import Core

public struct SolitaireView: View {
    @State private var model: SolitaireModel
    @State private var showConfirmNewGame = false
    /// ドラッグ中の札（会長要望 2026-09-02: ドラッグ&ドロップで動かす）。
    /// タップ（選択→行き先）の従来操作はそのまま残し、ドラッグは同じモデル操作を
    /// 別の入力経路から呼ぶだけにする（合法判定・拒否・記録の経路を増やさない）。
    @State private var drag: SolitaireDragState?
    /// ドロップ先の当たり判定枠（盤スクロール座標系）。
    @State private var dropFrames: [SolitaireDropTarget: CGRect] = [:]

    /// 盤の座標空間名。ドラッグの指の位置・ドロップ枠・追従オーバーレイを同じ空間で扱う。
    private static let boardSpace = "solitaireBoard"
    /// 札の移動を補間するための名前空間（#421）。
    ///
    /// 場札・捨て札・組札は別々のビュー階層なので、そのままでは移動が「移動元のビューが消えて
    /// 移動先のビューが生まれる」扱いになり座標を補間できない（将棋 #200 と同じ問題）。
    /// **同じ札に同じ id を与える**ことで、盤のどこへ動いても 1 つの札として繋がる。
    @Namespace private var cardMotion
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: SolitaireModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            board.layoutPriority(1)
            HowToPlayHint(.solitaire, playLog: services.playLog)
            controlArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .popBackground()
        .reviewRequestPrompt(services.review)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        #endif
        .tint(Theme.coral)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Label("戻る", systemImage: "chevron.left") }
            }
            ToolbarItem(placement: .principal) {
                Text("ソリティア")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { startNewGame() } label: {
                    Label("新規ゲーム", systemImage: "plus.circle.fill")
                }
                .accessibilityLabel("新しい配札にする")
            }
        }
        .howToPlay(.solitaire) { SolitaireRuleSheet() }
        .confirmationDialog("新しい配札にしますか？", isPresented: $showConfirmNewGame, titleVisibility: .visible) {
            Button("終了して新規ゲーム", role: .destructive) { model.newGame() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると今の盤面が失われ、この配札は「クリアできなかった」として記録されます。")
        }
        .overlay {
            if model.isDeadEnd { deadEndOverlay }
        }
        .task {
            model.resumeTimerIfNeeded()
            #if DEBUG
            // 撮影用（#397）: 遊んでいる最中の盤面を機械的に作る。シミュレータは自動タップが
            // できないため、初期配置以外を撮る手段がこれしかない（囲碁の `-goMidgame` と同じ理由）。
            if ProcessInfo.processInfo.arguments.contains("-solitaireMidgame") {
                model.applyPreviewProgressForTesting()
            }
            #endif
        }
        .onDisappear { model.pauseTimer() }
    }

    /// 途中の盤面があるときだけ確認を挟んでから配り直す。
    private func startNewGame() {
        if model.phase == .playing, model.canUndo {
            showConfirmNewGame = true
        } else {
            model.newGame()
        }
    }

    // MARK: - ステータスバー

    private var statusBar: some View {
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

            Text(stateEmoji).font(.system(size: 28))

            Spacer()

            Label(RecordFormat.time(model.elapsedSeconds), systemImage: "clock")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.teal)
                .frame(minWidth: 78, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .popCard(corner: Theme.cornerSmall)
        // 3 つの数字が別々に読まれると意味が取りにくいので 1 要素にまとめる。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SolitaireAccessibility.statusLabel(
            phase: model.phase,
            elapsedSeconds: model.elapsedSeconds,
            moveCount: model.moveCount,
            isDeadEnd: model.isDeadEnd
        ))
    }

    private var stateEmoji: String {
        if model.phase == .won { return "🎉" }
        return model.isDeadEnd ? "😵" : "♠️"
    }

    // MARK: - 盤面

    private var board: some View {
        GeometryReader { geo in
            let width = SolitaireMetrics.cardWidth(availableWidth: geo.size.width)
            let metrics = SolitaireMetrics.faceMetrics(width: width)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    topRow(metrics: metrics)
                    tableau(metrics: metrics)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
            // ドラッグの指の位置・ドロップ枠・追従表示を全て同じ座標空間で扱う。
            .coordinateSpace(name: Self.boardSpace)
            .onPreferenceChange(SolitaireDropFramesKey.self) { dropFrames = $0 }
            .overlay(alignment: .topLeading) { dragOverlay(metrics: metrics) }
            .gameAnimation(SolitaireMotion.move, value: boardAnimationKey)
        }
    }

    // MARK: - ドラッグ&ドロップ（会長要望 2026-09-02）

    /// 指に追従する持ち上げた札の描画。当たり判定は持たない。
    @ViewBuilder private func dragOverlay(metrics: PlayingCardMetrics) -> some View {
        if let drag {
            let upStep = SolitaireMetrics.faceUpStep(cardHeight: metrics.height)
            ZStack(alignment: .top) {
                ForEach(Array(drag.cards.enumerated()), id: \.element.id) { index, card in
                    cardView(card, faceUp: true, isSelected: false,
                             isCovered: index < drag.cards.count - 1, metrics: metrics)
                        .offset(y: CGFloat(index) * upStep)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
            .offset(x: drag.location.x - drag.grab.width,
                    y: drag.location.y - drag.grab.height)
            .allowsHitTesting(false)
        }
    }

    /// 札のドラッグ。移動の成立・拒否は既存のタップ操作（選択→行き先）をそのまま呼び、
    /// 合法判定・拒否音・記録の経路を1本に保つ。
    private func dragGesture(source: SolitaireSelection, metrics: PlayingCardMetrics) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.boardSpace))
            .onChanged { value in
                if drag == nil {
                    guard model.phase == .playing,
                          let cards = draggableCards(from: source), !cards.isEmpty else { return }
                    model.deselect()
                    drag = SolitaireDragState(
                        source: source,
                        cards: cards,
                        location: value.location,
                        // つかんだ位置がだいたい札の中央上部に来るように合わせる。
                        grab: CGSize(width: metrics.width / 2, height: metrics.height / 3)
                    )
                    services.feedback.impact(.rigid)
                } else {
                    drag?.location = value.location
                }
            }
            .onEnded { value in
                guard let current = drag else { return }
                drag = nil
                resolveDrop(of: current, at: value.location)
            }
    }

    /// ドラッグで持ち上げられる札の並び。動かせない並びは持ち上げさせない（タップ選択と同じ規則）。
    private func draggableCards(from source: SolitaireSelection) -> [SolitaireCard]? {
        switch source {
        case .waste:
            return model.board.waste.last.map { [$0] }
        case .tableau(let pile, let cardIndex):
            guard model.board.tableau.indices.contains(pile),
                  model.board.tableau[pile].faceUp.indices.contains(cardIndex),
                  model.board.isMovableRun(pile: pile, from: cardIndex) else { return nil }
            return Array(model.board.tableau[pile].faceUp[cardIndex...])
        }
    }

    /// 指を離した位置のドロップ先を探し、既存のタップ操作を再現して移動を試みる。
    /// 何にも重なっていなければ何もしない（誤ドロップで拒否音を鳴らさない）。
    private func resolveDrop(of drag: SolitaireDragState, at point: CGPoint) {
        // 組札と場札の枠は重ならないが、辞書順は不定なので組札を先に探す。
        let target = dropFrames.first { key, frame in
            if case .foundation = key { return frame.contains(point) }
            return false
        }?.key ?? dropFrames.first { $0.value.contains(point) }?.key
        guard let target else { return }

        // 同じ列に戻しただけなら何もしない。
        if case .tableau(let from, _) = drag.source, case .pile(let to) = target, from == to { return }

        model.deselect()
        switch drag.source {
        case .waste:
            model.tapWaste()
        case .tableau(let pile, let cardIndex):
            model.tapPile(pile, cardIndex: cardIndex)
        }
        switch target {
        case .pile(let pile):
            model.tapPile(pile)
        case .foundation(let suit):
            model.tapFoundation(suit)
        }
        // 移動が成立しなかったとき（拒否音は既に鳴っている）に選択が残らないようにする。
        if model.selection != nil { model.deselect() }
    }

    /// この札がドラッグで持ち上げ中（元の位置は薄く見せる）か。
    private func isLifted(pile: Int, cardIndex: Int) -> Bool {
        guard let drag, case .tableau(let dragPile, let dragIndex) = drag.source else { return false }
        return dragPile == pile && cardIndex >= dragIndex
    }

    /// 盤面の演出を起こす値。札の増減と選択の両方をひとつにまとめ、`.gameAnimation` は
    /// 盤面に 1 つだけ掛ける（入れ子にすると内側が外側のトランザクションを打ち消す・#199）。
    private var boardAnimationKey: BoardKey {
        BoardKey(
            foundations: model.board.foundations,
            wasteCount: model.board.waste.count,
            stockCount: model.board.stock.count,
            pileCounts: model.board.tableau.map { $0.faceDown.count * 100 + $0.faceUp.count },
            selection: model.selection
        )
    }

    private struct BoardKey: Equatable {
        let foundations: [Int]
        let wasteCount: Int
        let stockCount: Int
        let pileCounts: [Int]
        let selection: SolitaireSelection?
    }

    // MARK: - 山札・捨て札・組札

    private func topRow(metrics: PlayingCardMetrics) -> some View {
        HStack(spacing: SolitaireMetrics.columnGap) {
            stockView(metrics: metrics)
            wasteView(metrics: metrics)
            Spacer(minLength: 0)
            ForEach(SolitaireSuit.allCases, id: \.rawValue) { suit in
                foundationView(suit: suit, metrics: metrics)
            }
        }
    }

    private func stockView(metrics: PlayingCardMetrics) -> some View {
        Group {
            if model.board.stock.isEmpty {
                emptySlot(metrics: metrics, symbol: "arrow.clockwise")
            } else {
                ZStack {
                    PlayingCardSurface(faceUp: false, cornerRadius: metrics.cornerRadius)
                    PlayingCardBack(metrics: metrics)
                }
                .frame(width: metrics.width, height: metrics.height)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.tapStock() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SolitaireAccessibility.stockLabel(remaining: model.board.stock.count))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapStock() }
    }

    private func wasteView(metrics: PlayingCardMetrics) -> some View {
        Group {
            if let card = model.board.waste.last {
                // 山札からめくった 1 枚だけが裏から返る。場に出して下から出てきた札は
                // もともと表なので、`flips` を false にして返さない（#421）。
                SolitaireRevealCardView(
                    card: card,
                    isSelected: model.selection == .waste,
                    isCovered: false,
                    metrics: metrics,
                    flips: model.lastMoveWasDraw
                )
                .matchedGeometryEffect(id: card.id, in: cardMotion)
                .opacity(drag?.source == .waste ? 0.35 : 1)
            } else {
                emptySlot(metrics: metrics, symbol: nil)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.tapWaste() }
        .highPriorityGesture(dragGesture(source: .waste, metrics: metrics))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SolitaireAccessibility.wasteLabel(
            card: model.board.waste.last, isSelected: model.selection == .waste))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapWaste() }
    }

    private func foundationView(suit: SolitaireSuit, metrics: PlayingCardMetrics) -> some View {
        let rank = model.board.foundations[suit.rawValue]
        return Group {
            if rank > 0 {
                // 送られてきた札と同じ id を与えて、場札・捨て札からここまで滑らせる（#421）。
                cardView(SolitaireCard(suit, rank), faceUp: true, isSelected: false, metrics: metrics)
                    .matchedGeometryEffect(id: SolitaireCard(suit, rank).id, in: cardMotion)
            } else {
                // 空の組札にはスート記号を薄く置く。どこに何を積むのかが最初から分かるようにする。
                emptySlot(metrics: metrics, symbol: nil, suit: suit)
            }
        }
        .background(GeometryReader { g in
            Color.clear.preference(
                key: SolitaireDropFramesKey.self,
                value: [.foundation(suit): g.frame(in: .named(Self.boardSpace))])
        })
        .contentShape(Rectangle())
        .onTapGesture { model.tapFoundation(suit) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SolitaireAccessibility.foundationLabel(suit: suit, rank: rank))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapFoundation(suit) }
    }

    // MARK: - 場札

    private func tableau(metrics: PlayingCardMetrics) -> some View {
        HStack(alignment: .top, spacing: SolitaireMetrics.columnGap) {
            ForEach(0..<SolitaireBoard.pileCount, id: \.self) { pile in
                pileView(pile: pile, metrics: metrics)
            }
        }
    }

    private func pileView(pile: Int, metrics: PlayingCardMetrics) -> some View {
        let column = model.board.tableau[pile]
        let downStep = SolitaireMetrics.faceDownStep(cardHeight: metrics.height)
        let upStep = SolitaireMetrics.faceUpStep(cardHeight: metrics.height)
        let height = SolitaireMetrics.pileHeight(
            faceDownCount: column.faceDown.count,
            faceUpCount: column.faceUp.count,
            cardHeight: metrics.height
        )

        return ZStack(alignment: .top) {
            // 列全体を「置く先」として受ける下敷き。札の無いところをタップしても列に置ける。
            if column.isEmpty {
                emptySlot(metrics: metrics, symbol: "crown")
                    // 空の列は「K だけ置ける」ことを読み上げないと、音声では置けない理由が分からない。
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SolitaireAccessibility.emptyPileLabel(pile: pile))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.tapPile(pile) }
            } else {
                Color.clear.frame(width: metrics.width, height: height)
            }

            // 札の同一性は**位置ではなく札そのもの**に持たせる（#421）。添字を id にすると
            // 動いた札が「消えて生まれた」扱いになり、移動も裏返りも補間できない。
            ForEach(Array(column.faceDown.enumerated()), id: \.element.id) { index, card in
                let restY = CGFloat(index) * downStep
                SolitaireDealtCardView(
                    pile: pile, depth: index, restY: restY,
                    metrics: metrics, dealing: model.isFreshDeal
                ) {
                    SolitaireCardBody(card: card, faceUp: false, isSelected: false,
                                      isCovered: false, metrics: metrics)
                }
                .matchedGeometryEffect(id: card.id, in: cardMotion)
                // 段差は `.offset` ではなく余白で作る。`.offset` はレイアウト上の位置を変えないため、
                // 移動の補間が「札の位置」ではなく「列の上端」どうしを結んでしまう。
                .padding(.top, restY)
                .accessibilityHidden(true)
            }

            ForEach(Array(column.faceUp.enumerated()), id: \.element.id) { index, card in
                let restY = CGFloat(column.faceDown.count) * downStep + CGFloat(index) * upStep
                faceUpCard(
                    pile: pile, index: index, card: card, column: column,
                    // いちばん上の 1 枚だけが札の全体を出す。下に重なった札は段差ぶんの帯しか
                    // 見えないため、中央寄せの面（`PlayingCardFace`）を出すと数字が隠れて
                    // 「何の札が並んでいるか」が読めなくなる（実測）。
                    isCovered: index < column.faceUp.count - 1,
                    restY: restY,
                    metrics: metrics
                )
                .padding(.top, restY)
            }
        }
        .frame(width: metrics.width, height: height, alignment: .top)
        // ドロップ先の枠を報告する（列全体。会長要望 2026-09-02 のドラッグ&ドロップ用）。
        .background(GeometryReader { g in
            Color.clear.preference(
                key: SolitaireDropFramesKey.self,
                value: [.pile(pile): g.frame(in: .named(Self.boardSpace))])
        })
        .contentShape(Rectangle())
        .onTapGesture { model.tapPile(pile) }
    }

    private func faceUpCard(
        pile: Int,
        index: Int,
        card: SolitaireCard,
        column: SolitairePile,
        isCovered: Bool,
        restY: CGFloat,
        metrics: PlayingCardMetrics
    ) -> some View {
        let isSelected = model.selection == .tableau(pile: pile, cardIndex: index)
        return SolitaireDealtCardView(
            pile: pile, depth: column.faceDown.count + index, restY: restY,
            metrics: metrics, dealing: model.isFreshDeal
        ) {
            // 伏せ札から出てきた 1 枚だけが裏から返る（#421）。
            SolitaireRevealCardView(
                card: card,
                isSelected: isSelected,
                isCovered: isCovered,
                metrics: metrics,
                flips: model.revealedCardIDs.contains(card.id)
            )
        }
            .matchedGeometryEffect(id: card.id, in: cardMotion)
            .opacity(isLifted(pile: pile, cardIndex: index) ? 0.35 : 1)
            .contentShape(Rectangle())
            .onTapGesture { model.tapPile(pile, cardIndex: index) }
            .highPriorityGesture(dragGesture(
                source: .tableau(pile: pile, cardIndex: index), metrics: metrics))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SolitaireAccessibility.tableauCardLabel(
                pile: pile,
                position: index,
                aboveCount: column.faceUp.count - index - 1,
                hiddenCount: column.faceDown.count,
                card: card,
                isSelected: isSelected,
                isMovable: model.board.isMovableRun(pile: pile, from: index)
            ))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.tapPile(pile, cardIndex: index) }
    }

    // MARK: - 札の見た目

    /// 演出を掛けない素の 1 枚（ドラッグ中の追従表示・組札の頂点）。
    private func cardView(
        _ card: SolitaireCard,
        faceUp: Bool,
        isSelected: Bool,
        isCovered: Bool = false,
        metrics: PlayingCardMetrics
    ) -> some View {
        SolitaireCardBody(card: card, faceUp: faceUp, isSelected: isSelected,
                          isCovered: isCovered, metrics: metrics)
    }

    private func emptySlot(
        metrics: PlayingCardMetrics,
        symbol: String?,
        suit: SolitaireSuit? = nil
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .strokeBorder(Theme.inkSub.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            if let suit {
                Text(suit.symbol)
                    .font(.system(size: metrics.suitFont))
                    .foregroundStyle(Theme.inkSub.opacity(0.45))
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: metrics.suitFont * 0.8, weight: .semibold))
                    .foregroundStyle(Theme.inkSub.opacity(0.45))
            }
        }
        .frame(width: metrics.width, height: metrics.height)
    }

    // MARK: - 盤の下の操作エリア

    /// プレイ中（戻す・自動で上がる）とクリア後（記録 + 次のゲーム + レコメンド）で中身が
    /// 入れ替わるが、**高さは常に後者の最大構成に揃える**（#148）。ここが伸び縮みすると
    /// 盤面（残りの高さいっぱいに札を敷く）が帳尻合わせに縮む。
    private var controlArea: some View {
        ZStack(alignment: .top) {
            finishedControls { RecommendationCard.heightPlaceholder }
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if model.phase == .won {
                finishedControls {
                    RecommendationSlot(services: services, isFinished: true)
                }
            } else {
                gameControls
            }
        }
    }

    private func finishedControls<Recommendation: View>(
        @ViewBuilder recommendation: () -> Recommendation
    ) -> some View {
        VStack(spacing: 8) {
            resultControls
            recommendation()
        }
    }

    private var resultControls: some View {
        HStack(spacing: 12) {
            RecordLabel(model.recordResult)
                .lineLimit(1).minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Button { model.newGame() } label: {
                Label("次のゲーム", systemImage: "arrow.clockwise")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.coral))
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private var gameControls: some View {
        HStack(spacing: 8) {
            controlButton("戻す", systemImage: "arrow.uturn.backward", tint: Theme.coral) {
                model.undo()
            }
            .disabled(!model.canUndo)
            // 押せない間も枠は残す（消えると「そんな機能は無い」と読まれる・#198 と同じ扱い）。
            .opacity(model.canUndo ? 1 : 0.4)
            .accessibilityLabel("1手戻す")
            .accessibilityHint(model.canUndo ? "何回でも戻せます" : "まだ戻せる手がありません")

            // 「あとは組札へ積むだけ」になった局面でだけ出す。終盤の 52 回タップを 1 回に畳む。
            if model.canAutoFinish {
                controlButton("自動で上がる", systemImage: "wand.and.stars", tint: Theme.teal) {
                    model.autoFinish()
                }
                .accessibilityHint("残りの札をまとめて組札へ送ります")
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
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                // 高さは 44pt（#199 で全ゲームの操作ボタンに揃えた下限）。
                .frame(minHeight: 44)
                .background(Capsule().fill(tint))
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }

    // MARK: - 詰み

    /// 山札を循環させるほかに進める手が無くなった局面（#397 の詰み検知）。
    ///
    /// **ジョーカーでの救済（広告）はここに出さない**。提示のしかたは #406 の決裁待ちで、
    /// 決まるまでは「戻す」と「新しい配札」だけを出口にする（undo は無料・無制限なので、
    /// 詰みは必ず巻き戻せる = 出口の無い行き止まりにはならない）。
    private var deadEndOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("😵").font(.system(size: 52))
                Text("進める手がありません")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("山札をめくるしか手が残っていません。手を戻してやり直すか、新しい配札にしてください。")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                    .multilineTextAlignment(.center)

                if model.canUndo {
                    Button { model.undo() } label: {
                        Label("1手戻す", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.coral, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                Button { model.newGame() } label: {
                    Text("新しい配札にする")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            .padding(.horizontal, 28)
        }
    }
}

// MARK: - 札 1 枚の見た目

/// 札 1 枚の外形と中身（表 / 裏）。
///
/// 反転の途中でも同じ外形を使うので、View のメソッドではなく型として切り出して
/// `SolitaireFlipCardView` と共有する（#421）。
struct SolitaireCardBody: View {
    let card: SolitaireCard
    let faceUp: Bool
    let isSelected: Bool
    let isCovered: Bool
    let metrics: PlayingCardMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 外形・面はトランプ共通基盤（#397。質感は CardStyle #366）。
            PlayingCardSurface(
                faceUp: faceUp,
                cornerRadius: metrics.cornerRadius,
                border: isSelected ? Theme.coral : Color.gray.opacity(0.2),
                borderWidth: isSelected ? 2.5 : 0.5,
                shadowColor: isSelected ? Theme.coral.opacity(0.6) : .black.opacity(0.15),
                shadowRadius: isSelected ? 6 : 3
            )
            if !faceUp {
                PlayingCardBack(metrics: metrics)
            } else if isCovered {
                SolitaireCardIndex(card: card, metrics: metrics)
            } else {
                PlayingCardFace(figure: card.figure, metrics: metrics)
                    .frame(width: metrics.width, height: metrics.height)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
    }
}

// MARK: - めくり（#421）

/// 裏から表へ返る 1 枚。
///
/// `faceUp` の切り替えに `.gameAnimation` を掛けただけでは表裏が瞬時に入れ替わるだけなので、
/// ポーカーの `FlipRevealCardView`・ブラックジャックの `BJFlipCardView` と同じく
/// **このビュー自身を `Animatable`** にして進捗を補間させ、進捗の翻訳は
/// `SolitaireMotion` の純関数に任せる。
struct SolitaireFlipCardView: View, Animatable {
    nonisolated let card: SolitaireCard
    nonisolated let isSelected: Bool
    nonisolated let isCovered: Bool
    nonisolated let metrics: PlayingCardMetrics
    /// 0 = 裏 / 1 = 表。掛かっているアニメーションがこの値を補間する。
    nonisolated var progress: Double

    // `View` への適合でこの型は MainActor 隔離になるが、`Animatable` の要求は nonisolated。
    // 保持しているのは値型（すべて Sendable）だけなので、格納プロパティごと nonisolated にする。
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let showsFace = SolitaireMotion.showsFace(progress: progress)
        SolitaireCardBody(card: card, faceUp: showsFace, isSelected: isSelected,
                          isCovered: isCovered, metrics: metrics)
            // 後半は札ごと 90 度を越えて回っているので、表の中身が鏡像にならないよう
            // ここで 180 度打ち消す（合計 360 度で元の向きに戻る）。
            .rotation3DEffect(.degrees(showsFace ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(
                .degrees(SolitaireMotion.flipDegrees(progress: progress)),
                axis: (x: 0, y: 1, z: 0)
            )
    }
}

/// 反転の起動役。`flips` が true のときだけ 0 → 1 を走らせる。
///
/// 返る必要のない札（もともと表で置かれていた札）は**進捗 1 の状態で作る**ので、
/// 1 フレームだけ裏が見えることがない。Reduce Motion が ON なら `withGameAnimation` が
/// 補間を落とすので、返る過程は出ずに即座に表になる。
struct SolitaireRevealCardView: View {
    let card: SolitaireCard
    let isSelected: Bool
    let isCovered: Bool
    let metrics: PlayingCardMetrics
    let flips: Bool

    @State private var progress: Double

    init(card: SolitaireCard, isSelected: Bool, isCovered: Bool,
         metrics: PlayingCardMetrics, flips: Bool) {
        self.card = card
        self.isSelected = isSelected
        self.isCovered = isCovered
        self.metrics = metrics
        self.flips = flips
        _progress = State(initialValue: flips ? 0 : 1)
    }

    var body: some View {
        SolitaireFlipCardView(card: card, isSelected: isSelected, isCovered: isCovered,
                              metrics: metrics, progress: progress)
            .onAppear {
                guard flips else { return }
                withGameAnimation(SolitaireMotion.flip) { progress = 1 }
            }
    }
}

// MARK: - 配札（#421）

/// 山札から飛んできて場札に収まる 1 枚。
///
/// 段差は「配られた順」で決まりビューの再生成では変わらないので、状態は**このビュー自身が持つ**
/// （ブラックジャックの `BJDealtCardView` と同じ設計）。`dealing` が false のときは何もしない。
///
/// `dealing` の判定は「まだ 1 手も指していないか」なので、**巻き戻して初手前まで戻したとき**に
/// 動いた札だけがもう一度飛んでくる。その盤面は配ったばかりの状態そのものなので、
/// 演出としても食い違わない。
struct SolitaireDealtCardView<Content: View>: View {
    let pile: Int
    let depth: Int
    /// 列の上端から測った、この札の落ち着き先。飛んでくる距離の計算に使う。
    let restY: CGFloat
    let metrics: PlayingCardMetrics

    let content: Content

    /// 置き終わったか。`false` の間だけ山札の位置に隠しておく。
    @State private var dealt: Bool

    init(pile: Int, depth: Int, restY: CGFloat, metrics: PlayingCardMetrics,
         dealing: Bool, @ViewBuilder content: () -> Content) {
        self.pile = pile
        self.depth = depth
        self.restY = restY
        self.metrics = metrics
        self.content = content()
        _dealt = State(initialValue: !dealing)
    }

    var body: some View {
        let start = SolitaireMotion.dealStartOffset(pile: pile, restY: restY, metrics: metrics)
        content
            .offset(x: dealt ? 0 : start.width, y: dealt ? 0 : start.height)
            .opacity(dealt ? 1 : 0)
            .onAppear {
                guard !dealt else { return }
                // Reduce Motion が ON なら `withGameAnimation` が補間を落とすので、
                // 遅れも動きも無く即座に置かれる（状態変更そのものは必ず走る）。
                withGameAnimation(SolitaireMotion.dealAppear(pile: pile, depth: depth)) {
                    dealt = true
                }
            }
    }
}

/// 重なって「上端の帯」しか見えない札に出す、隅の小さな見出し（ランク + スート）。
///
/// 実物のトランプが左上に数字を刷っているのと同じ役割で、**扇状に重ねた列でも
/// 何の札が並んでいるかを読めるようにする**ための表示。共通基盤の
/// `PlayingCardFace` は中央寄せなので、重なった札では隠れてしまう（実測で数字が読めなかった）。
struct SolitaireCardIndex: View {
    let card: SolitaireCard
    let metrics: PlayingCardMetrics

    private var color: Color {
        guard let suit = card.suit, !card.isJoker else { return PlayingCardInk.joker }
        return PlayingCardInk.color(for: suit.playingCardSuit)
    }

    var body: some View {
        HStack(spacing: 2) {
            if card.isJoker {
                JesterCapMark(color: PlayingCardInk.joker)
                    .frame(width: metrics.rankFont * 0.8, height: metrics.rankFont * 0.8)
            } else {
                Text(card.rankLabel)
                    .font(.system(size: metrics.rankFont * 0.72, weight: .black, design: .rounded))
                Text(card.suit?.symbol ?? "")
                    .font(.system(size: metrics.suitFont * 0.66))
            }
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .padding(.leading, 5)
        .padding(.top, 3)
        // 読み上げは呼び出し側（列の 1 枚）が束ねて出すので、ここは黙らせる。
        .accessibilityHidden(true)
    }
}

// MARK: - くわしいルール

/// 「遊び方」シートから開く詳細ページ。組み方は `MahjongSolitaireRuleSheet` と同じ。
struct SolitaireRuleSheet: View {
    /// 文言はテストから検証したいので型の外に出しておく。
    static let rules: [(String, String)] = [
        ("ゲームの流れ", "配られた52枚を、右上の組札（4か所）に ♠♥♦♣ ごとに A から K まで順に積み上げれば クリアです。クロンダイクと呼ばれる、いちばん標準的なソリティアです"),
        ("場札の並べ方", "場札（下の7列）には、ひとつ上の札より1つ小さくて色ちがいの札だけを置けます（黒の8 の上には 赤の7）。そろっている並びは何枚でもまとめて動かせます"),
        ("空いた列", "札が無くなった列に置けるのは K だけです。K を引くまで空けておくか、思い切って埋めるかがクロンダイクの読みどころです"),
        ("山札", "左上の山札はタップで1枚ずつめくれます。最後までめくったらもう一度タップすると、捨て札が山札に戻ります（何周でもできます）"),
        ("操作", "動かしたい札をタップして選び、置きたい列か組札をタップします。もう一度同じ札をタップすると選択を外せます"),
        ("戻す", "「戻す」は何回でも無料で使えます。行き止まりになっても、手を戻してやり直せます"),
        ("配られる札", "出題する配札は、すべて事前にコンピュータで解いてクリアできることを確かめてあります。行き止まりは配りのせいではなく、指し方で変わります"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Self.rules, id: \.0) { rule in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rule.0)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.coral)
                        Text(rule.1)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2))
                }
            }
            .padding(Theme.pad)
        }
        .popBackground()
        .navigationTitle("ルール")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - ドラッグ&ドロップ（会長要望 2026-09-02）

/// ドラッグ中の札の状態。
struct SolitaireDragState {
    var source: SolitaireSelection
    var cards: [SolitaireCard]
    /// 盤座標系での指の位置。
    var location: CGPoint
    /// つかんだ点から札の左上までのずれ（追従表示の位置合わせ用）。
    var grab: CGSize
}

/// ドロップ先の種類。
enum SolitaireDropTarget: Hashable {
    case pile(Int)
    case foundation(SolitaireSuit)
}

/// ドロップ先の枠を子ビューから集める。
struct SolitaireDropFramesKey: PreferenceKey {
    static var defaultValue: [SolitaireDropTarget: CGRect] { [:] }
    static func reduce(value: inout [SolitaireDropTarget: CGRect],
                       nextValue: () -> [SolitaireDropTarget: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
