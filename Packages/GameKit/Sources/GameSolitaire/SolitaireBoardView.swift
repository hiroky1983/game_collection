import Foundation
import SwiftUI
import Core

/// 盤面（山札・捨て札・組札・7 列の場札）と、そこへのドラッグ&ドロップ。
///
/// **ドラッグの状態はこの型が丸ごと抱える**（#521 / #525）。指の位置だけでなく
/// 「持ち上げている札」「ドロップ枠」もここに閉じるので、札を持ち上げた瞬間・置いた瞬間の
/// 作り直しも盤の中で止まり、ステータスバーや操作エリアまでは波及しない。
struct SolitaireBoardView: View {
    let model: SolitaireModel
    let services: GameServices

    /// ドラッグ中の札（会長要望 2026-09-02: ドラッグ&ドロップで動かす）。
    /// タップ（選択→行き先）の従来操作はそのまま残し、ドラッグは同じモデル操作を
    /// 別の入力経路から呼ぶだけにする（合法判定・拒否・記録の経路を増やさない）。
    ///
    /// **指の位置はここに入れない**（#521）。持ち上げ・置くの瞬間にしか変わらない値だけを置く。
    @State private var drag: SolitaireDragState?
    /// ドラッグ中の指の位置。**盤本体から切り離すために参照型に逃がす**（#521）。
    ///
    /// `@State` の構造体に入れると 1 サンプルごとに盤の `body`
    /// （7 列の場札・上段の山札と組札）が作り直される。参照型にして
    /// 追従表示の `CardDragLayer` だけが `point` を読むことで、盤本体は
    /// 持ち上げ・置くの 2 回しか作り直されない。
    @State private var dragLocation = CardDragLocation()
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
    /// 画面の広さ（#458）。札の幅の上限をここから受け取る。
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        GeometryReader { geo in
            let width = SolitaireMetrics.cardWidth(
                availableWidth: geo.size.width,
                // 広い画面では他の画面と同じ倍率で札の上限を引き上げる（#458）。
                // 狭い画面では `scaled` が恒等なので従来の 76pt のまま。
                maxWidth: layout.scaled(SolitaireMetrics.maxCardWidth)
            )
            let metrics = SolitaireMetrics.faceMetrics(width: width)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    topRow(metrics: metrics)
                    tableau(metrics: metrics)
                }
                // 上段（`Spacer` で伸びる）と下段（7 列で頭打ち）の幅を揃えて中央に置く。
                // これが無いと iPad で組札だけが右端へ逃げ、7 列目と縦に揃わない（#458）。
                .frame(width: SolitaireMetrics.boardWidth(cardWidth: width))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
            // ドラッグの指の位置・ドロップ枠・追従表示を全て同じ座標空間で扱う。
            .coordinateSpace(name: Self.boardSpace)
            .onPreferenceChange(CardDropFramesKey<SolitaireDropTarget>.self) { dropFrames = $0 }
            .overlay(alignment: .topLeading) { dragOverlay(metrics: metrics) }
            .gameAnimation(SolitaireMotion.move, value: boardAnimationKey)
        }
    }

    // MARK: - ドラッグ&ドロップ（会長要望 2026-09-02）

    /// 指に追従する持ち上げた札の描画。当たり判定は持たない。
    ///
    /// **位置を読むのはここではなく `CardDragLayer` の中**（#521）。この関数は
    /// 盤の `body` の一部として評価されるので、ここで `dragLocation.point` を
    /// 読むと盤本体が指の動きを購読してしまい、逃がした意味が無くなる。
    @ViewBuilder private func dragOverlay(metrics: PlayingCardMetrics) -> some View {
        if let drag {
            CardDragLayer(
                cards: drag.cards,
                grab: drag.grab,
                location: dragLocation,
                step: SolitaireMetrics.faceUpStep(cardHeight: metrics.height)
            ) { index, card in
                SolitaireCardBody(card: card, faceUp: true, isSelected: false,
                                  isCovered: index < drag.cards.count - 1, metrics: metrics)
            }
        }
    }

    /// 札のドラッグ。移動の成立・拒否は既存のタップ操作（選択→行き先）をそのまま呼び、
    /// 合法判定・拒否音・記録の経路を1本に保つ。
    private func dragGesture(source: SolitaireSelection, metrics: PlayingCardMetrics) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.boardSpace))
            .onChanged { value in
                if drag == nil {
                    // ジョーカーの置き先を選んでいる間は札を動かさない（タップだけを受ける）。
                    guard model.phase == .playing, !model.isPlacingJoker,
                          let cards = draggableCards(from: source), !cards.isEmpty else { return }
                    model.deselect()
                    // 位置を先に入れる。持ち上げた最初の 1 フレームから正しい場所に出す。
                    dragLocation.point = value.location
                    drag = SolitaireDragState(
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

    /// 移動の補間で札どうしを結ぶ鍵（#421）。
    ///
    /// 配り直しをまたいでは結ばない。またいで結ぶと、新しい配札の札が
    /// **前の配札での居場所から飛んでくる**ことになり、山札から配る演出と食い違う。
    private func motionID(_ card: SolitaireCard) -> CardMotionID {
        CardMotionID(deal: model.dealSerial, card: card.id)
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
                CardSlot(metrics: metrics, systemImage: "arrow.clockwise")
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

    /// 捨て札。**めくった枚数ぶんを横にずらして重ねる**（#498）。
    ///
    /// 使えるのは一番上の 1 枚だけだが、3 枚めくりでは次に何が控えているかが見えないと
    /// 「3 枚に 1 枚しか使えない」制約の下で山札を回す計画が立てられない。
    /// 1 枚めくりでは常に 1 枚しか出さないので、描画も当たり判定も従来と変わらない。
    private func wasteView(metrics: PlayingCardMetrics) -> some View {
        let visible = Array(model.board.waste.suffix(model.rules.drawCount))
        let step = SolitaireMetrics.wasteFanStep(cardWidth: metrics.width)
        return Group {
            if visible.isEmpty {
                CardSlot(metrics: metrics)
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, card in
                        let isTop = index == visible.count - 1
                        // 山札からめくった札だけが裏から返る。場に出して下から出てきた札は
                        // もともと表なので返さない（#421）。3 枚めくりでは 1〜3 枚が同時に返る。
                        SolitaireRevealCardView(
                            card: card,
                            isSelected: isTop && model.selection == .waste,
                            // 隠れている札は左上の帯しか見えないので、中央寄せの面ではなく
                            // 隅の見出し（ランク + スート）を出す（場札の重なりと同じ扱い）。
                            isCovered: !isTop,
                            metrics: metrics,
                            flips: model.drawnCardIDs.contains(card.id)
                        )
                        // 捨て札の枠は「札がある」状態が続くので、**札が入れ替わっても
                        // SwiftUI から見れば同じビュー**になり `@State` が作り直されない。
                        // 札ごとに identity を切って、2 回目以降のめくりも必ず返るようにする。
                        .id(card.id)
                        .matchedGeometryEffect(id: motionID(card), in: cardMotion)
                        .offset(x: CGFloat(index) * step)
                        .zIndex(Double(index))
                        // 持ち上げているのは一番上の 1 枚だけ。下の 2 枚まで薄くしない。
                        .opacity(isTop && drag?.source == .waste ? 0.35 : 1)
                    }
                }
            }
        }
        // 枠は**めくり枚数ぶんの幅で固定**する。見えている枚数に合わせて縮めると、
        // 捨て札を 1 枚使うたびに右の組札が横へ動く。
        .frame(
            width: SolitaireMetrics.wasteWidth(
                cardWidth: metrics.width, visibleCount: model.rules.drawCount),
            height: metrics.height,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .onTapGesture { model.tapWaste() }
        .highPriorityGesture(dragGesture(source: .waste, metrics: metrics))
        .accessibilityElement(children: .ignore)
        // 子要素は読み上げないので、重なって見えている札もここで束ねて読む（#498）。
        .accessibilityLabel(SolitaireAccessibility.wasteLabel(
            card: model.board.waste.last,
            isSelected: model.selection == .waste,
            covered: Array(visible.dropLast())))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.tapWaste() }
    }

    private func foundationView(suit: SolitaireSuit, metrics: PlayingCardMetrics) -> some View {
        let rank = model.board.foundations[suit.rawValue]
        return Group {
            if rank > 0 {
                // 送られてきた札と同じ id を与えて、場札・捨て札からここまで滑らせる（#421）。
                SolitaireCardBody(card: SolitaireCard(suit, rank), faceUp: true,
                                  isSelected: false, isCovered: false, metrics: metrics)
                    .matchedGeometryEffect(id: motionID(SolitaireCard(suit, rank)), in: cardMotion)
            } else {
                // 空の組札にはスート記号を薄く置く。どこに何を積むのかが最初から分かるようにする。
                CardSlot(metrics: metrics, suitSymbol: suit.symbol)
            }
        }
        .cardDropTarget(SolitaireDropTarget.foundation(suit), in: Self.boardSpace)
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
                CardSlot(metrics: metrics, systemImage: "crown")
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
                // 配り直しでは「もう配り終わった」状態のビューを使い回さない（下記 faceUpCard も同じ）。
                .id(model.dealSerial)
                .matchedGeometryEffect(id: motionID(card), in: cardMotion)
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
        .cardDropTarget(SolitaireDropTarget.pile(pile), in: Self.boardSpace)
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
            .id(model.dealSerial)
            .matchedGeometryEffect(id: motionID(card), in: cardMotion)
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
/// 動きの器は共通基盤（`CardDealtView`・#524）が持ち、ここは**クロンダイク固有の
/// 「どこから」「どの順で」飛んでくるか**を `SolitaireMotion` から渡す口になる
/// （山札は上段のいちばん左・列ごとにまとめて配る）。
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
            startOffset: SolitaireMotion.dealStartOffset(pile: pile, restY: restY, metrics: metrics),
            animation: SolitaireMotion.dealAppear(pile: pile, depth: depth),
            dealing: dealing
        ) {
            content
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

// MARK: - ドラッグ&ドロップ（会長要望 2026-09-02）

/// ドラッグ中の札の状態。**持ち上げた瞬間から置くまで変わらない値だけを持つ**（#521）。
/// 毎サンプル変わる指の位置は共通基盤の `CardDragLocation` にある。
struct SolitaireDragState {
    var source: SolitaireSelection
    var cards: [SolitaireCard]
    /// つかんだ点から札の左上までのずれ（追従表示の位置合わせ用）。
    var grab: CGSize
}

/// ドロップ先の種類。枠を集める仕組みそのものは共通基盤（`CardDropFramesKey`・#524）にある。
enum SolitaireDropTarget: Hashable {
    case pile(Int)
    case foundation(SolitaireSuit)
}
