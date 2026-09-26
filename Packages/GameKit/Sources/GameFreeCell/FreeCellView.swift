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
    /// 拡大モード（#604）。既定は等倍で、**盤全体を一望できる性質を既定から取り上げない**。
    /// フリーセルは全札が表向きで、どこに何があるかを見渡せることが読みの前提になる。
    @State private var zoomMode = false

    /// 盤の座標空間名。ドラッグの指の位置・ドロップ枠・追従オーバーレイを同じ空間で扱う。
    private static let boardSpace = "freeCellBoard"
    /// 札の移動を補間するための名前空間（#421 の横展開）。
    @Namespace private var cardMotion
    private let services: GameServices
    /// 画面の広さ（#458）。札の幅の上限をここから受け取る。
    @Environment(\.adaptiveLayout) private var layout

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: FreeCellModel(services: services))
    }

    public var body: some View {
        // 左右の余白は部品ごとに付ける。盤だけは `boardSideInset`（4pt）まで詰めて札の幅に回し、
        // 帯・ヒント・ボタン・バナーは従来どおり `Theme.pad`（16pt）。
        VStack(spacing: 8) {
            statusBar
                .padding(.horizontal, Theme.pad)
            board
                .padding(.horizontal, FreeCellMetrics.boardSideInset)
                .layoutPriority(1)
            HowToPlayHint(.freecell, playLog: services.playLog)
                .padding(.horizontal, Theme.pad)
            Spacer(minLength: 0)
            controlArea
                .padding(.horizontal, Theme.pad)
            BannerSlot(ads: services.ads)
                .padding(.horizontal, Theme.pad)
        }
        .padding(.vertical, Theme.pad)
        .gameChrome(title: "フリーセル", review: services.review,
                    newGame: GameChromeNewGame(.solo) {
                        startNewGame()
                    })
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
            // 拡大モード（#604）はトグルを押さないと入れないが、シミュレータは自動タップが
            // できないため、起動引数から直接その状態にして撮る。
            if ProcessInfo.processInfo.arguments.contains("-freecellZoom") {
                zoomMode = true
            }
            #endif
        }
        .onDisappear { model.pauseTimer() }
        // 広告のロード〜視聴中は計時を止める（全画面広告は onDisappear を発火させない・#1382）。
        .pausesTimerWhileWatching([undoRescue], pause: { model.pauseTimer() }, resume: { model.resumeTimerIfNeeded() })
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

    /// 数字の並び。帯には表示だけを置く。拡大の切り替えは右下の「⋯」へ（#1468）。
    private var statusBar: some View {
        GameStatusBar {
            statusReadout
        } trailing: {
            EmptyView()
        }
        .accessibilityElement(children: .contain)
    }

    /// 読み上げの対象。数字は `children: .ignore` の 1 要素にまとめる。
    private var statusReadout: some View {
        HStack(spacing: 8) {
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

            VStack(spacing: 0) {
                Text(stateEmoji).font(.system(size: 24))
                // 番号付きディールはフリーセルの文化なので、どの配札を解いているかを常時出す（#492）。
                // `Text("...\(数値)")` は LocalizedStringKey 扱いになり **桁区切りが入る**
                // （実測: 配札 #1,126）。番号なので区切ってはいけない。文字列にしてから渡す。
                Text(verbatim: "配札 #" + String(model.dealNumber))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.inkSub)
            }

            Label(RecordFormat.time(model.elapsedSeconds), systemImage: "clock")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.teal)
        }
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
            let width = cardWidth(availableWidth: geo.size.width)
            let metrics = FreeCellMetrics.faceMetrics(width: width)
            // 段差は盤の縦の余りに合わせて広げ、全列で同じ値を使う。拡大中も同じ計算
            // （札が大きくなるぶん余りが減り、収まらなければ下限の段差で縦スクロールになる）。
            let stack = FreeCellMetrics.stackLayout(
                cardWidth: metrics.width, cardHeight: metrics.height,
                boardHeight: geo.size.height, pileCounts: model.board.tableau.map(\.count))
            ScrollView(zoomMode ? [.horizontal, .vertical] : [.vertical], showsIndicators: false) {
                VStack(spacing: FreeCellMotion.topRowSpacing) {
                    topRow(metrics: metrics)
                    tableau(metrics: metrics, stack: stack)
                }
                // 上段（4 セル + 4 組札）と下段（8 列）はどちらもちょうど 8 枠ぶんなので、
                // 同じ幅に揃えて中央に置けば iPad でも縦に揃う（#458）。
                .frame(width: FreeCellMetrics.boardWidth(cardWidth: width))
                .padding(.top, FreeCellMetrics.boardTopPadding)
                // 盤が画面より狭いとき（等倍・iPad の拡大）は従来どおり中央に置く。
                // 広いとき（拡大モード）は `minWidth` が効かず、はみ出した分が横スクロールになる。
                // **`maxWidth: .infinity` は使えない**: 横スクロール側では幅の提案が無限大になり、
                // 盤が画面ではなく無限に広がって中央寄せの基準が消える。
                //
                // `minHeight` と `.top` は**縦方向の浮き上がり止め**（#604 の実測）。2 軸の
                // `ScrollView` は、中身がビューポートより短い軸で中身を**中央に置く**ため、
                // 拡大した盤がステータスバーから 56pt 落ちた位置に浮いた。1 軸のときは上詰めなので
                // この指定は等倍の見た目を変えない。
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .top)
            }
            .coordinateSpace(name: Self.boardSpace)
            .onPreferenceChange(CardDropFramesKey<FreeCellDropTarget>.self) { dropFrames = $0 }
            .overlay(alignment: .topLeading) { dragOverlay(metrics: metrics, stack: stack) }
            .gameAnimation(FreeCellMotion.move, value: boardAnimationKey)
        }
    }

    /// 札の幅（#604）。**等倍と拡大の分岐はここ 1 か所だけ**にする。
    ///
    /// 盤はこの 1 つの値から `faceMetrics` を作り、それを場札・上段・ドロップ枠・追従表示の
    /// すべてへ同じものを配っている。分岐を各所に撒くと、拡大したのに当たり判定だけ等倍のまま、
    /// という形のズレが生まれる。
    private func cardWidth(availableWidth: CGFloat) -> CGFloat {
        // 広い画面では他の画面と同じ倍率で札の上限を引き上げる（#458）。
        // 狭い画面では `scaled` が恒等なので従来どおり。
        let maxWidth = layout.scaled(FreeCellMetrics.maxCardWidth)
        return zoomMode
            ? FreeCellMetrics.zoomedCardWidth(availableWidth: availableWidth, maxWidth: maxWidth)
            : FreeCellMetrics.cardWidth(availableWidth: availableWidth, maxWidth: maxWidth)
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
    @ViewBuilder private func dragOverlay(metrics: PlayingCardMetrics, stack: CardStackLayout) -> some View {
        if let drag {
            CardDragLayer(
                cards: drag.cards,
                grab: drag.grab,
                location: dragLocation,
                step: stack.faceUpStep
            ) { index, card in
                FreeCellCardBody(card: card, isSelected: false,
                                 coveredIndex: index < drag.cards.count - 1 ? stack.index : nil,
                                 metrics: metrics)
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
        // **`Spacer` は置かない**（会長QA #595-9）。上段はちょうど 8 枠で下段の 8 列と幅が
        // ぴったり揃う（`FreeCellMetrics.boardWidth` = 8 枠 + 隙間 7 つ）ため、`Spacer` を挟むと
        // 子が 9 個になり、`HStack` の隙間が **8 つ**ぶん（+4pt）取られて上段だけが盤の幅を
        // はみ出す。はみ出した分は中央寄せで左右 2pt ずつ切り落とされ、**左端の枠の左辺と
        // 右端の枠の右辺の破線が丸ごと消える**（実測: 角の円弧だけが端に残る）。
        // `Spacer(minLength: 0)` は幅 0 に潰れても、その両隣の隙間は消えない。
        HStack(spacing: FreeCellMetrics.columnGap) {
            ForEach(0..<FreeCellBoard.cellCount, id: \.self) { cell in
                cellView(cell, metrics: metrics)
            }
            ForEach(PlayingCardSuit.allCases, id: \.rawValue) { suit in
                foundationView(suit: suit, metrics: metrics)
            }
        }
        // 左 4 つ（フリーセル）と右 4 つ（組札）の境目。
        //
        // 上段は 8 枠が等間隔に並ぶので、**札が載ると 8 枚が 1 列に並んでいるようにしか
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
                FreeCellCardBody(card: card, isSelected: isSelected, coveredIndex: nil, metrics: metrics)
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
                                 coveredIndex: nil, metrics: metrics)
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

    private func tableau(metrics: PlayingCardMetrics, stack: CardStackLayout) -> some View {
        HStack(alignment: .top, spacing: FreeCellMetrics.columnGap) {
            ForEach(0..<FreeCellBoard.pileCount, id: \.self) { pile in
                pileView(pile: pile, metrics: metrics, stack: stack)
            }
        }
    }

    private func pileView(pile: Int, metrics: PlayingCardMetrics, stack: CardStackLayout) -> some View {
        let column = model.board.tableau[pile]
        let step = stack.faceUpStep
        let height = FreeCellMetrics.pileHeight(cardCount: column.count, cardHeight: metrics.height, step: step)

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
                            restY: restY, metrics: metrics, stack: stack)
                    // 段差は `.offset` ではなく余白で作る。`.offset` はレイアウト上の位置を
                    // 変えないため、移動の補間が「札の位置」ではなく「列の上端」どうしを結ぶ。
                    .padding(.top, restY)
            }
        }
        // 押せる範囲（ドロップ枠を含む）は**盤の下端まで**伸ばす。札の無い下の空きを押しても
        // この列を押したことになり、小さい札を狙わなくてよい。
        .frame(width: metrics.width, height: max(height, stack.reachHeight), alignment: .top)
        .cardDropTarget(FreeCellDropTarget.pile(pile), in: Self.boardSpace)
        .contentShape(Rectangle())
        .onTapGesture { tapBelowPile(pile) }
    }

    /// 列の下の空き（札の無いところ）を押したとき。**一番下の札を押したのと同じ**にする
    /// （空の列なら空の列を押したのと同じ）。ドラッグは札にだけ付いているので、ここからは始まらない。
    private func tapBelowPile(_ pile: Int) {
        let count = model.board.tableau[pile].count
        if count == 0 {
            model.tapPile(pile)
        } else {
            model.tapPile(pile, cardIndex: count - 1)
        }
    }

    private func tableauCard(
        pile: Int,
        index: Int,
        card: FreeCellCard,
        column: [FreeCellCard],
        restY: CGFloat,
        metrics: PlayingCardMetrics,
        stack: CardStackLayout
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
                coveredIndex: index < column.count - 1 ? stack.index : nil,
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
    /// 入れ替わるが、**高さは常に後者の最大構成に揃える**（#148。高さの担保は `GameControlArea`）。
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
        // 戻す・拡大・自動で上がるは右下の「⋯」にまとめる（#1422・#1468）。
        // 「動かせる枚数」の表示は操作行と一緒になくなる（会長決裁 2026-09-26。必要なら別の場所を相談）。
        GameOverflowBar(menuItems: [
            // 残り回数を文言に含める（#476 と同じ見せ方）。押せない間も項目は残す（#198）。
            GameControlMenuItem(
                id: "undo", title: "戻す（残り\(model.undosRemaining)）", systemImage: "arrow.uturn.backward",
                isEnabled: model.canUndo && !undoRescue.isWatching,
                accessibilityLabel: FreeCellAccessibility.undoButtonLabel(remaining: model.undosRemaining),
                accessibilityHint: FreeCellAccessibility.undoButtonHint(
                    canUndo: model.canUndo, remaining: model.undosRemaining)
            ) { requestUndo() },
            // 拡大（#604）。ヒントも状態で切り替える。ラベルだけ切り替えると、拡大中に
            // 「盤全体を表示」と読んだ直後に「札を大きくします」と案内することになる。
            GameControlMenuItem(
                id: "zoom", title: "拡大", systemImage: "plus.magnifyingglass", isChecked: zoomMode,
                accessibilityLabel: zoomMode ? "盤全体を表示" : "札を拡大",
                accessibilityHint: zoomMode
                    ? "等倍に戻して盤全体を画面に収めます"
                    : "札を大きくして指で押しやすくします。はみ出した列は横にスクロールします"
            ) { zoomMode.toggle() },
            // 「あとは組札へ積むだけ」になった局面でだけ押せる。終盤の連打を 1 回に畳む。
            GameControlMenuItem(
                id: "autoFinish", title: "自動で上がる", systemImage: "wand.and.stars",
                isEnabled: model.canAutoFinish,
                accessibilityHint: "残りの札をまとめて組札へ送ります"
            ) { model.autoFinish() },
        ])
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
        // 暗幕が背面のタップを塞ぐので、VoiceOver も告知の中だけを移動させる。
        .accessibilityAddTraits(.isModal)
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
