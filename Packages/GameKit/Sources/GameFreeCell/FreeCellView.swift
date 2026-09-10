import Foundation
import SwiftUI
import Core

public struct FreeCellView: View {
    @State private var model: FreeCellModel
    @State private var showConfirmNewGame = false
    /// ドラッグ中の札。タップ（選択→行き先）の従来操作はそのまま残し、ドラッグは同じモデル操作を
    /// 別の入力経路から呼ぶだけにする（合法判定・拒否・記録の経路を増やさない。ソリティアと同じ設計）。
    ///
    /// **指の位置はここに入れない**（#521 と同じ理由）。持ち上げ・置くの瞬間にしか変わらない値だけを置く。
    @State private var drag: FreeCellDragState?
    /// ドラッグ中の指の位置。**盤本体から切り離すために参照型に逃がす**（#521・#524）。
    ///
    /// `@State` の構造体に入れると 1 サンプルごとに `FreeCellView.body` 全体
    /// （ステータスバー・8 列の場札・操作エリア）が作り直される。参照型にして
    /// 追従表示の `CardDragLayer` だけが `point` を読むことで、盤本体は
    /// 持ち上げ・置くの 2 回しか作り直されない。
    @State private var dragLocation = CardDragLocation()
    /// ドロップ先の当たり判定枠（盤スクロール座標系）。
    @State private var dropFrames: [FreeCellDropTarget: CGRect] = [:]
    /// 無料の「戻す」を使い切った状態でボタンを押したときの提案。
    /// **自動再生はしない**。ここで「見る」を選んだときだけ広告を出す。
    @State private var showUndoRefillPrompt = false
    /// 「戻す」補充のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var undoRescue = RewardedRescue()

    /// 盤の座標空間名。ドラッグの指の位置・ドロップ枠・追従オーバーレイを同じ空間で扱う。
    private static let boardSpace = "freeCellBoard"
    /// 札の移動を補間するための名前空間（#421 の横展開）。
    @Namespace private var cardMotion
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss
    /// 画面の広さ（#458）。札の幅の上限をここから受け取る。
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: FreeCellModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            board.layoutPriority(1)
            HowToPlayHint(.freecell, playLog: services.playLog)
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
                Text("フリーセル")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { startNewGame() } label: {
                    Label("新規ゲーム", systemImage: "plus.circle.fill")
                }
                .accessibilityLabel("新しい配札にする")
            }
        }
        .howToPlay(.freecell) { FreeCellRuleSheet() }
        .confirmationDialog("新しい配札にしますか？", isPresented: $showConfirmNewGame, titleVisibility: .visible) {
            Button("終了して新規ゲーム", role: .destructive) { model.newGame() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると今の盤面が失われ、この配札は「クリアできなかった」として記録されます。")
        }
        .alert("無料の「戻す」を使い切りました", isPresented: $showUndoRefillPrompt) {
            Button("広告を見て\(FreeCellUndoBudget.refill)回補充する") { requestUndoRefill() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴すると「戻す」を\(FreeCellUndoBudget.refill)回ぶん補充します。\n盤面はそのままです。")
        }
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
        .task {
            model.resumeTimerIfNeeded()
            #if DEBUG
            // 撮影用（#492）: 遊んでいる最中・行き止まりの盤面を機械的に作る。
            // シミュレータは自動タップができないため、初期配置以外を撮る手段がこれしかない。
            if ProcessInfo.processInfo.arguments.contains("-freecellMidgame") {
                model.applyPreviewProgressForTesting()
            }
            if ProcessInfo.processInfo.arguments.contains("-freecellDeadEnd") {
                model.applyDeadEndPreviewForTesting()
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

            VStack(spacing: 0) {
                Text(stateEmoji).font(.system(size: 24))
                // 番号付きディールはフリーセルの文化なので、どの配札を解いているかを常時出す（#492）。
                // `Text("...\(数値)")` は LocalizedStringKey 扱いになり **桁区切りが入る**
                // （実測: 配札 #1,126）。番号なので区切ってはいけない。文字列にしてから渡す。
                Text(verbatim: "配札 #" + String(model.dealNumber))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.inkSub)
            }

            Spacer()

            Label(RecordFormat.time(model.elapsedSeconds), systemImage: "clock")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.teal)
                .frame(minWidth: 78, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .popCard(corner: Theme.cornerSmall)
        // 数字が別々に読まれると意味が取りにくいので 1 要素にまとめる。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FreeCellAccessibility.statusLabel(
            phase: model.phase,
            elapsedSeconds: model.elapsedSeconds,
            moveCount: model.moveCount,
            dealNumber: model.dealNumber,
            maxMovableCount: model.board.maxMovableCount(),
            isDeadEnd: model.isDeadEnd
        ))
    }

    private var stateEmoji: String {
        if model.phase == .won { return "🎉" }
        return model.isDeadEnd ? "😵" : "♦️"
    }

    // MARK: - 盤面

    private var board: some View {
        GeometryReader { geo in
            let width = FreeCellMetrics.cardWidth(
                availableWidth: geo.size.width,
                // 広い画面では他の画面と同じ倍率で札の上限を引き上げる（#458）。
                // 狭い画面では `scaled` が恒等なので従来どおり。
                maxWidth: layout.scaled(FreeCellMetrics.maxCardWidth)
            )
            let metrics = FreeCellMetrics.faceMetrics(width: width)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: FreeCellMotion.topRowSpacing) {
                    topRow(metrics: metrics)
                    tableau(metrics: metrics)
                }
                // 上段（4 セル + 4 組札）と下段（8 列）はどちらもちょうど 8 枠ぶんなので、
                // 同じ幅に揃えて中央に置けば iPad でも縦に揃う（#458）。
                .frame(width: FreeCellMetrics.boardWidth(cardWidth: width))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
            .coordinateSpace(name: Self.boardSpace)
            .onPreferenceChange(CardDropFramesKey<FreeCellDropTarget>.self) { dropFrames = $0 }
            .overlay(alignment: .topLeading) { dragOverlay(metrics: metrics) }
            .gameAnimation(FreeCellMotion.move, value: boardAnimationKey)
        }
    }

    /// 盤面の演出を起こす値。`.gameAnimation` は盤面に 1 つだけ掛ける
    /// （同じビューへ重ね掛けすると内側が外側のトランザクションを打ち消す・#199）。
    private var boardAnimationKey: BoardKey {
        BoardKey(
            foundations: model.board.foundations,
            cells: model.board.cells.map { $0?.id ?? -1 },
            pileCounts: model.board.tableau.map(\.count),
            selection: model.selection
        )
    }

    private struct BoardKey: Equatable {
        let foundations: [Int]
        let cells: [Int]
        let pileCounts: [Int]
        let selection: FreeCellSelection?
    }

    // MARK: - ドラッグ&ドロップ

    /// 指に追従する持ち上げた札の描画。当たり判定は持たない。
    ///
    /// **位置を読むのはここではなく `CardDragLayer` の中**（#521・#524）。この関数は
    /// `FreeCellView.body` の一部として評価されるので、ここで `dragLocation.point` を
    /// 読むと盤本体が指の動きを購読してしまい、逃がした意味が無くなる。
    @ViewBuilder private func dragOverlay(metrics: PlayingCardMetrics) -> some View {
        if let drag {
            CardDragLayer(
                cards: drag.cards,
                grab: drag.grab,
                location: dragLocation,
                step: FreeCellMetrics.step(cardHeight: metrics.height)
            ) { index, card in
                FreeCellCardBody(card: card, isSelected: false,
                                 isCovered: index < drag.cards.count - 1, metrics: metrics)
            }
        }
    }

    /// 札のドラッグ。移動の成立・拒否は既存のタップ操作（選択→行き先）をそのまま呼び、
    /// 合法判定・拒否音・記録の経路を1本に保つ。
    private func dragGesture(source: FreeCellSelection, metrics: PlayingCardMetrics) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.boardSpace))
            .onChanged { value in
                if drag == nil {
                    guard model.phase == .playing,
                          let cards = draggableCards(from: source), !cards.isEmpty else { return }
                    model.deselect()
                    // 位置を先に入れる。持ち上げた最初の 1 フレームから正しい場所に出す。
                    dragLocation.point = value.location
                    drag = FreeCellDragState(
                        source: source,
                        cards: cards,
                        // つかんだ位置がだいたい札の中央上部に来るように合わせる。
                        grab: CGSize(width: metrics.width / 2, height: metrics.height / 3)
                    )
                    services.feedback.impact(.rigid)
                } else {
                    // 盤本体の `@State` は触らない（#521）。読むのは追従表示だけ。
                    dragLocation.point = value.location
                }
            }
            .onEnded { value in
                guard let current = drag else { return }
                drag = nil
                resolveDrop(of: current, at: value.location)
            }
    }

    /// ドラッグで持ち上げられる札の並び。動かせない並びは持ち上げさせない（タップ選択と同じ規則）。
    ///
    /// **枚数の上限（`maxMovableCount`）はここでは見ない**。上限は置き先が決まって初めて決まる
    /// （空列へ置くときだけ 1 本減る）ので、持ち上げの時点で弾くと本当は通る手まで掴めなくなる。
    private func draggableCards(from source: FreeCellSelection) -> [FreeCellCard]? {
        switch source {
        case .cell(let cell):
            guard model.board.cells.indices.contains(cell) else { return nil }
            return model.board.cells[cell].map { [$0] }
        case .tableau(let pile, let cardIndex):
            guard model.board.tableau.indices.contains(pile),
                  model.board.tableau[pile].indices.contains(cardIndex),
                  model.board.isOrderedRun(pile: pile, from: cardIndex) else { return nil }
            return Array(model.board.tableau[pile][cardIndex...])
        }
    }

    /// 指を離した位置のドロップ先を探し、既存のタップ操作を再現して移動を試みる。
    /// 何にも重なっていなければ何もしない（誤ドロップで拒否音を鳴らさない）。
    private func resolveDrop(of drag: FreeCellDragState, at point: CGPoint) {
        // 上段（セル・組札）と場札の枠は重ならないが、辞書順は不定なので上段を先に探す。
        let target = dropFrames.first { key, frame in
            if case .pile = key { return false }
            return frame.contains(point)
        }?.key ?? dropFrames.first { $0.value.contains(point) }?.key
        guard let target else { return }

        // 同じ場所に戻しただけなら何もしない。
        if case .tableau(let from, _) = drag.source, case .pile(let to) = target, from == to { return }
        if case .cell(let from) = drag.source, case .cell(let to) = target, from == to { return }

        model.deselect()
        switch drag.source {
        case .cell(let cell):
            model.tapCell(cell)
        case .tableau(let pile, let cardIndex):
            model.tapPile(pile, cardIndex: cardIndex)
        }
        switch target {
        case .pile(let pile):
            model.tapPile(pile)
        case .cell(let cell):
            model.tapCell(cell)
        case .foundation(let suit):
            model.tapFoundation(suit)
        }
        // 移動が成立しなかったとき（拒否音は既に鳴っている）に選択が残らないようにする。
        if model.selection != nil { model.deselect() }
    }

    /// 移動の補間で札どうしを結ぶ鍵（#421）。配り直しをまたいでは結ばない。
    private func motionID(_ card: FreeCellCard) -> CardMotionID {
        CardMotionID(deal: model.dealSerial, card: card.id)
    }

    /// この札がドラッグで持ち上げ中（元の位置は薄く見せる）か。
    private func isLifted(pile: Int, cardIndex: Int) -> Bool {
        guard let drag, case .tableau(let dragPile, let dragIndex) = drag.source else { return false }
        return dragPile == pile && cardIndex >= dragIndex
    }

    // MARK: - フリーセル・組札

    private func topRow(metrics: PlayingCardMetrics) -> some View {
        HStack(spacing: FreeCellMetrics.columnGap) {
            ForEach(0..<FreeCellBoard.cellCount, id: \.self) { cell in
                cellView(cell, metrics: metrics)
            }
            Spacer(minLength: 0)
            ForEach(PlayingCardSuit.allCases, id: \.rawValue) { suit in
                foundationView(suit: suit, metrics: metrics)
            }
        }
        // 左 4 つ（フリーセル）と右 4 つ（組札）の境目。
        //
        // 上段はちょうど 8 枠で、下段の 8 列と幅がぴったり揃う（`FreeCellMetrics.boardWidth`）。
        // そのぶん `Spacer` が 0 に潰れるので、**札が載ると 8 枚が 1 列に並んでいるようにしか
        // 見えない**（実測。空のうちは受け皿の絵と ♠♥♦♣ で区別が付くが、埋まると消える）。
        // 列の幅を崩さずに境目だけ描くため、レイアウトを取らない overlay で中央に引く。
        .overlay {
            Capsule()
                .fill(Theme.inkSub.opacity(0.5))
                .frame(width: 2.5)
                .padding(.vertical, 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func cellView(_ cell: Int, metrics: PlayingCardMetrics) -> some View {
        let card = model.board.cells[cell]
        let isSelected = model.selection == .cell(cell)
        return Group {
            if let card {
                FreeCellCardBody(card: card, isSelected: isSelected, isCovered: false, metrics: metrics)
                    .matchedGeometryEffect(id: motionID(card), in: cardMotion)
                    .opacity(drag?.source == .cell(cell) ? 0.35 : 1)
            } else {
                CardSlot(metrics: metrics, systemImage: "tray")
            }
        }
        .cardDropTarget(FreeCellDropTarget.cell(cell), in: Self.boardSpace)
        .contentShape(Rectangle())
        .onTapGesture { model.tapCell(cell) }
        .highPriorityGesture(dragGesture(source: .cell(cell), metrics: metrics))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FreeCellAccessibility.cellLabel(
            index: cell, card: card, isSelected: isSelected))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapCell(cell) }
    }

    private func foundationView(suit: PlayingCardSuit, metrics: PlayingCardMetrics) -> some View {
        let rank = model.board.foundations[suit.rawValue]
        return Group {
            if rank > 0 {
                // 送られてきた札と同じ id を与えて、場札・セルからここまで滑らせる（#421）。
                FreeCellCardBody(card: FreeCellCard(suit, rank), isSelected: false,
                                 isCovered: false, metrics: metrics)
                    .matchedGeometryEffect(id: motionID(FreeCellCard(suit, rank)), in: cardMotion)
            } else {
                // 空の組札にはスート記号を薄く置く。どこに何を積むのかが最初から分かるようにする。
                CardSlot(metrics: metrics, suitSymbol: suit.symbol)
            }
        }
        .cardDropTarget(FreeCellDropTarget.foundation(suit), in: Self.boardSpace)
        .contentShape(Rectangle())
        .onTapGesture { model.tapFoundation(suit) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FreeCellAccessibility.foundationLabel(suit: suit, rank: rank))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapFoundation(suit) }
    }

    // MARK: - 場札

    private func tableau(metrics: PlayingCardMetrics) -> some View {
        HStack(alignment: .top, spacing: FreeCellMetrics.columnGap) {
            ForEach(0..<FreeCellBoard.pileCount, id: \.self) { pile in
                pileView(pile: pile, metrics: metrics)
            }
        }
    }

    private func pileView(pile: Int, metrics: PlayingCardMetrics) -> some View {
        let column = model.board.tableau[pile]
        let step = FreeCellMetrics.step(cardHeight: metrics.height)
        let height = FreeCellMetrics.pileHeight(cardCount: column.count, cardHeight: metrics.height)

        return ZStack(alignment: .top) {
            // 列全体を「置く先」として受ける下敷き。札の無いところをタップしても列に置ける。
            if column.isEmpty {
                CardSlot(metrics: metrics, systemImage: "square.dashed")
                    // 空列は「どの札でも置ける」ことを読み上げないと、音声では規則が分からない。
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(FreeCellAccessibility.emptyPileLabel(pile: pile))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.tapPile(pile) }
            } else {
                Color.clear.frame(width: metrics.width, height: height)
            }

            // 札の同一性は**位置ではなく札そのもの**に持たせる（#421）。添字を id にすると
            // 動いた札が「消えて生まれた」扱いになり、移動を補間できない。
            ForEach(Array(column.enumerated()), id: \.element.id) { index, card in
                let restY = CGFloat(index) * step
                tableauCard(pile: pile, index: index, card: card, column: column,
                            restY: restY, metrics: metrics)
                    // 段差は `.offset` ではなく余白で作る。`.offset` はレイアウト上の位置を
                    // 変えないため、移動の補間が「札の位置」ではなく「列の上端」どうしを結ぶ。
                    .padding(.top, restY)
            }
        }
        .frame(width: metrics.width, height: height, alignment: .top)
        .cardDropTarget(FreeCellDropTarget.pile(pile), in: Self.boardSpace)
        .contentShape(Rectangle())
        .onTapGesture { model.tapPile(pile) }
    }

    private func tableauCard(
        pile: Int,
        index: Int,
        card: FreeCellCard,
        column: [FreeCellCard],
        restY: CGFloat,
        metrics: PlayingCardMetrics
    ) -> some View {
        let isSelected = model.selection == .tableau(pile: pile, cardIndex: index)
        let isMovable = model.board.isOrderedRun(pile: pile, from: index)
        return FreeCellDealtCardView(
            pile: pile, depth: index, restY: restY,
            metrics: metrics, dealing: model.isFreshDeal
        ) {
            FreeCellCardBody(
                card: card,
                isSelected: isSelected,
                // いちばん上の 1 枚だけが札の全体を出す。下に重なった札は段差ぶんの帯しか
                // 見えないため、中央寄せの面を出すと数字が隠れて何の札か読めなくなる。
                isCovered: index < column.count - 1,
                metrics: metrics
            )
        }
        // 配り直しでは「もう配り終わった」状態のビューを使い回さない。
        .id(model.dealSerial)
        .matchedGeometryEffect(id: motionID(card), in: cardMotion)
        .opacity(isLifted(pile: pile, cardIndex: index) ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture { model.tapPile(pile, cardIndex: index) }
        .highPriorityGesture(dragGesture(
            source: .tableau(pile: pile, cardIndex: index), metrics: metrics))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FreeCellAccessibility.tableauCardLabel(
            pile: pile,
            position: index,
            aboveCount: column.count - index - 1,
            card: card,
            isSelected: isSelected,
            isMovable: isMovable
        ))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapPile(pile, cardIndex: index) }
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
            // 残り回数を常時見せる（#476 と同じ見せ方）。
            controlButton("戻す\(model.undosRemaining)",
                          systemImage: "arrow.uturn.backward",
                          tint: Theme.Fill.coral) {
                requestUndo()
            }
            .disabled(!model.canUndo || undoRescue.isWatching)
            // 押せない間も枠は残す（消えると「そんな機能は無い」と読まれる・#198 と同じ扱い）。
            .opacity(model.canUndo ? 1 : 0.4)
            .accessibilityLabel(FreeCellAccessibility.undoButtonLabel(remaining: model.undosRemaining))
            .accessibilityHint(FreeCellAccessibility.undoButtonHint(
                canUndo: model.canUndo, remaining: model.undosRemaining))

            // 一度に動かせる枚数は**フリーセルで手が通らない理由の大半**なので常時出す。
            movableBadge

            // 「あとは組札へ積むだけ」になった局面でだけ出す。終盤の連打を 1 回に畳む。
            if model.canAutoFinish {
                controlButton("自動で上がる", systemImage: "wand.and.stars", tint: Theme.Fill.teal) {
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

    /// 一度に動かせる枚数の表示。**ボタンではない**ので押せる見た目にはしない。
    private var movableBadge: some View {
        Label("\(model.board.maxMovableCount())枚", systemImage: "square.stack.3d.up.fill")
            .lineLimit(1)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Capsule().fill(Theme.Fill.purple))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("一度に\(model.board.maxMovableCount())枚まで動かせます")
            .accessibilityHint("空きのフリーセルと空いた列が増えるほど多く動かせます")
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
                // 高さは 44pt（#199 で全ゲームの操作ボタンに揃えた下限）。
                .frame(minHeight: 44)
                .background(Capsule().fill(tint))
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }

    // MARK: - 行き止まりの告知

    /// 指せる手が本当にゼロになったときだけ出す。
    ///
    /// クロンダイク（#491）と違い盤に触れる手が残っていないので、告知は「取り上げている」わけではない。
    /// それでも閉じられるようにするのは、**どこで間違えたかを盤で読み返してから戻したい**ため。
    private var deadEndOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("😵").font(.system(size: 52))
                Text("指せる手がありません")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("フリーセルが全部埋まり、どの札も置き先がありません。この配札は必ずクリアできるので、手を戻せばやり直せます。")
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
                    .accessibilityLabel(FreeCellAccessibility.undoButtonLabel(remaining: model.undosRemaining))
                    .accessibilityHint(FreeCellAccessibility.undoButtonHint(
                        canUndo: model.canUndo, remaining: model.undosRemaining))
                }

                Button { model.newGame() } label: {
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
        .accessibilityLabel(FreeCellAccessibility.deadEndPromptLabel(
            canUndo: model.canUndo, remaining: model.undosRemaining))
    }

    /// 「戻す」の入口を 1 本にまとめる（#476 と同じ契約）。
    ///
    /// 残り回数があればそのまま戻し、使い切っていたら**提案を出すだけ**にする。
    /// ここで広告を直接出さないのが要で、押した瞬間に再生が始まると
    /// 「戻すつもりが広告を見せられた」になる。
    private func requestUndo() {
        if model.needsUndoRefill {
            showUndoRefillPrompt = true
        } else {
            model.undo()
        }
    }

    /// リワード広告 → 「戻す」の補充。視聴しなかったときと補充できなかったときを読み分けて必ず知らせる。
    private func requestUndoRefill() {
        // どの局に対する補充かを、広告を出す前に控える。ボタンの `disabled` だけでは
        // ツールバーの「新規ゲーム」からの配り直しを止められない（PR #480 の敵対的検証）。
        let deal = model.dealSerial
        undoRescue.request(
            services, gameID: model.gameID, purpose: .undo,
            guardedBy: .checkedByGrant
        ) {
            model.grantUndos(forDeal: deal)
        }
    }
}

// MARK: - 札 1 枚の見た目

/// 札 1 枚の外形と中身。フリーセルは**全札が表向き**なので裏面は持たない。
struct FreeCellCardBody: View {
    let card: FreeCellCard
    let isSelected: Bool
    let isCovered: Bool
    let metrics: PlayingCardMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 外形・面はトランプ共通基盤（#397。質感は CardStyle #366）。
            PlayingCardSurface(
                faceUp: true,
                cornerRadius: metrics.cornerRadius,
                border: isSelected ? Theme.coral : Color.gray.opacity(0.2),
                borderWidth: isSelected ? 2.5 : 0.5
            )
            if isCovered {
                // 下に重なった札は段差ぶんの帯しか見えないので、左上に小さく出す。
                FreeCellCardIndex(card: card, metrics: metrics)
            } else {
                PlayingCardFace(figure: card.figure, metrics: metrics)
                    .frame(width: metrics.width, height: metrics.height)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
    }
}

/// 重なって隠れた札の見出し（ランク + スートを左上に小さく）。
struct FreeCellCardIndex: View {
    let card: FreeCellCard
    let metrics: PlayingCardMetrics

    var body: some View {
        HStack(spacing: 2) {
            Text(card.rankLabel)
                .font(.system(size: metrics.rankFont * 0.72, weight: .black, design: .rounded))
            Text(card.suit.symbol)
                .font(.system(size: metrics.suitFont * 0.72))
        }
        .foregroundStyle(PlayingCardInk.color(for: card.suit))
        .padding(.leading, metrics.cornerRadius * 0.7)
        .padding(.top, metrics.cornerRadius * 0.4)
    }
}

// MARK: - 配札（#421 の横展開）

/// 配られてくる 1 枚。配り終わったあとは素通しなので、移動の補間には干渉しない。
///
/// 動きの器は共通基盤（`CardDealtView`・#524）が持ち、ここは**フリーセル固有の
/// 「どこから」「どの順で」飛んでくるか**を `FreeCellMotion` から渡す口になる
/// （配り元は上段のいちばん左・8 列へ 1 枚ずつ順に配る）。
struct FreeCellDealtCardView<Content: View>: View {
    let pile: Int
    let depth: Int
    /// 列の上端から測った、この札の落ち着き先。飛んでくる距離の計算に使う。
    let restY: CGFloat
    let metrics: PlayingCardMetrics
    let dealing: Bool

    let content: Content

    init(pile: Int, depth: Int, restY: CGFloat, metrics: PlayingCardMetrics,
         dealing: Bool, @ViewBuilder content: () -> Content) {
        self.pile = pile
        self.depth = depth
        self.restY = restY
        self.metrics = metrics
        self.dealing = dealing
        self.content = content()
    }

    var body: some View {
        CardDealtView(
            startOffset: FreeCellMotion.dealStartOffset(pile: pile, restY: restY, metrics: metrics),
            animation: FreeCellMotion.dealAppear(pile: pile, depth: depth),
            dealing: dealing
        ) {
            content
        }
    }
}

// MARK: - くわしいルール

/// 「遊び方」シートから開く詳細ページ。組み方は `SolitaireRuleSheet` と同じ。
struct FreeCellRuleSheet: View {
    /// 文言はテストから検証したいので型の外に出しておく。
    static let rules: [(String, String)] = [
        ("ゲームの流れ", "配られた52枚を、右上の組札（4か所）に ♠♥♦♣ ごとに A から K まで順に積み上げればクリアです。最初から全部の札が見えているので、運ではなく読みで決まります"),
        ("フリーセル", "左上の4つの枠が「フリーセル」です。札を1枚ずつ一時的に置けます。ここに入れた札は、場札か組札へいつでも戻せます"),
        ("場札の並べ方", "場札（下の8列）には、ひとつ上の札より1つ小さくて色ちがいの札だけを置けます（黒の8 の上には 赤の7）"),
        ("空いた列", "札が無くなった列には、どの札でも置けます（クロンダイクのように K だけ、ではありません）。空列はフリーセル以上に強い資源です"),
        ("何枚まとめて動かせるか", "そろっている並びは「（空きフリーセル + 1）×（2の空き列数乗）」枚までまとめて動かせます。いま何枚動かせるかは盤の下に出ています。置き先が空列のときは、その列は数えません"),
        ("操作", "動かしたい札をタップして選び、置きたい列・フリーセル・組札をタップします。ドラッグでも動かせます。もう一度同じ札をタップすると選択を外せます"),
        ("戻す", "「戻す」は1局につき\(FreeCellUndoBudget.free)回まで無料です。残り回数はボタンに出ています。使い切ったあとは、広告を見ると\(FreeCellUndoBudget.refill)回ぶん補充できます"),
        ("配られる札", "出題する配札は、すべて事前にコンピュータで解いてクリアできることを確かめてあります。行き止まりは配りのせいではなく、指し方で変わります。配札の番号は画面の上に出ています"),
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

// MARK: - ドラッグ&ドロップ

/// ドラッグ中の札の状態。**持ち上げた瞬間から置くまで変わらない値だけを持つ**（#521・#524）。
/// 毎サンプル変わる指の位置は共通基盤の `CardDragLocation` にある。
struct FreeCellDragState {
    var source: FreeCellSelection
    var cards: [FreeCellCard]
    /// つかんだ点から札の左上までのずれ（追従表示の位置合わせ用）。
    var grab: CGSize
}

/// ドロップ先の種類。枠を集める仕組みそのものは共通基盤（`CardDropFramesKey`・#524）にある。
enum FreeCellDropTarget: Hashable {
    case pile(Int)
    case cell(Int)
    case foundation(PlayingCardSuit)
}
