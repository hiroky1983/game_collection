import Foundation
import Observation
import SwiftUI
import Core

public struct SolitaireView: View {
    @State private var model: SolitaireModel
    /// 配り直しの開始シート（#498）。**初回の配札では出さない**（既定で即座に配る）。
    ///
    /// #498 以前は「新しい配札にしますか？」の確認ダイアログを出していたが、
    /// このシートが同じ警告と最終確認（キャンセルできる「配る」）を兼ねるので置き換えた。
    /// ダイアログのあとにさらにシートを出すと、確認を 2 枚重ねることになる。
    @State private var showSetup = false
    /// 開始シートで選んでいる最中のルール。「配る」を押すまで局には効かない（1局=1RuleSet）。
    @State private var draft = SolitaireRuleSet.standard
    /// ドラッグ中の札（会長要望 2026-09-02: ドラッグ&ドロップで動かす）。
    /// タップ（選択→行き先）の従来操作はそのまま残し、ドラッグは同じモデル操作を
    /// 別の入力経路から呼ぶだけにする（合法判定・拒否・記録の経路を増やさない）。
    ///
    /// **指の位置はここに入れない**（#521）。持ち上げ・置くの瞬間にしか変わらない値だけを置く。
    @State private var drag: SolitaireDragState?
    /// ドラッグ中の指の位置。**盤本体から切り離すために参照型に逃がす**（#521）。
    ///
    /// `@State` の構造体に入れると 1 サンプルごとに `SolitaireView.body` 全体
    /// （ステータスバー・7 列の場札・操作エリア）が作り直される。参照型にして
    /// 追従表示の `SolitaireDragLayer` だけが `point` を読むことで、盤本体は
    /// 持ち上げ・置くの 2 回しか作り直されない。
    @State private var dragLocation = SolitaireDragLocation()
    /// ドロップ先の当たり判定枠（盤スクロール座標系）。
    @State private var dropFrames: [SolitaireDropTarget: CGRect] = [:]
    /// ジョーカー補充のリワード広告を出している最中（連打で 2 本目が失敗するのを防ぐ・#406）。
    @State private var isWatchingJokerAd = false
    @State private var showJokerNotEarned = false
    @State private var showJokerUnavailable = false
    /// 無料の「戻す」を使い切った状態でボタンを押したときの提案（#476）。
    /// **自動再生はしない**。ここで「見る」を選んだときだけ広告を出す。
    @State private var showUndoRefillPrompt = false
    @State private var isWatchingUndoAd = false
    @State private var showUndoNotEarned = false
    @State private var showUndoUnavailable = false

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
    /// 画面の広さ（#458）。札の幅の上限をここから受け取る。
    @Environment(\.adaptiveLayout) private var layout

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
                Button { openSetup() } label: {
                    Label("新規ゲーム", systemImage: "plus.circle.fill")
                }
                .accessibilityLabel("新しい配札にする")
            }
        }
        .howToPlay(.solitaire) { SolitaireRuleSheet() }
        // めくり方を選んでから配る（#498）。局に焼き込むのは「配る」を押した瞬間だけ。
        .sheet(isPresented: $showSetup) {
            SolitaireSetupSheet(draft: $draft, discardsProgress: model.canUndo) {
                showSetup = false
                model.newGame(rules: draft)
            }
        }
        .alert("ジョーカーをもらえませんでした", isPresented: $showJokerNotEarned) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。")
        }
        .alert("ジョーカーを受け取れませんでした", isPresented: $showJokerUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を見ているあいだに局面が変わったため、ジョーカーを追加できませんでした。\n手持ちのジョーカーはそのまま残っています。")
        }
        .alert("無料の「戻す」を使い切りました", isPresented: $showUndoRefillPrompt) {
            Button("広告を見て\(SolitaireUndoBudget.refill)回補充する") { requestUndoRefill() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴すると「戻す」を\(SolitaireUndoBudget.refill)回ぶん補充します。\n盤面はそのままです。")
        }
        .alert("「戻す」を補充できませんでした", isPresented: $showUndoNotEarned) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。")
        }
        .alert("「戻す」を補充できませんでした", isPresented: $showUndoUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を見ているあいだに配り直されたか、局が終わったため、補充できませんでした。\n新しい配札の「戻す」は無料の回数まで戻っています。")
        }
        .overlay {
            if model.showsRescuePrompt { rescueOverlay }
        }
        .task {
            model.resumeTimerIfNeeded()
            #if DEBUG
            // 撮影用（#397）: 遊んでいる最中の盤面を機械的に作る。シミュレータは自動タップが
            // できないため、初期配置以外を撮る手段がこれしかない（囲碁の `-goMidgame` と同じ理由）。
            if ProcessInfo.processInfo.arguments.contains("-solitaireMidgame") {
                model.applyPreviewProgressForTesting()
            }
            // 救済の面（#406）は自然に到達させられないので、撮影用に直接その状態を作る。
            if ProcessInfo.processInfo.arguments.contains("-solitaireRescue") {
                model.applyPreviewProgressForTesting()
                model.applyRescuePreviewForTesting(spendJoker: false)
            }
            if ProcessInfo.processInfo.arguments.contains("-solitaireRescueAd") {
                model.applyPreviewProgressForTesting()
                model.applyRescuePreviewForTesting(spendJoker: true)
            }
            if ProcessInfo.processInfo.arguments.contains("-solitaireJokerPlacing") {
                model.applyPreviewProgressForTesting()
                model.applyPlacingJokerPreviewForTesting()
            }
            // 3 枚めくり（#498）は開始シートで選ぶので、自動タップのできないシミュレータでは
            // この 2 つの口からしか撮れない。
            if ProcessInfo.processInfo.arguments.contains("-solitaireDraw3") {
                model.applyDrawThreePreviewForTesting()
            }
            if ProcessInfo.processInfo.arguments.contains("-solitaireSetup") {
                openSetup()
            }
            #endif
        }
        .onDisappear { model.pauseTimer() }
    }

    /// 開始シートを開く。**いま遊んでいるルールを初期選択にする**（#498）。
    /// 前に開いたときの選択が残っていると、続けて配り直したときに勝手にルールが変わる。
    private func openSetup() {
        draft = model.rules
        showSetup = true
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
            isDeadEnd: model.isDeadEnd,
            isLost: model.isLost
        ))
    }

    private var stateEmoji: String {
        if model.phase == .won { return "🎉" }
        if model.isDeadEnd { return "😵" }
        // 敗北確定（#406）。告知を閉じたあとも、ここだけは状態を出し続ける。
        return model.isLost ? "🤔" : "♠️"
    }

    // MARK: - 盤面

    private var board: some View {
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
            .onPreferenceChange(SolitaireDropFramesKey.self) { dropFrames = $0 }
            .overlay(alignment: .topLeading) { dragOverlay(metrics: metrics) }
            .gameAnimation(SolitaireMotion.move, value: boardAnimationKey)
        }
    }

    // MARK: - ドラッグ&ドロップ（会長要望 2026-09-02）

    /// 指に追従する持ち上げた札の描画。当たり判定は持たない。
    ///
    /// **位置を読むのはここではなく `SolitaireDragLayer` の中**（#521）。この関数は
    /// `SolitaireView.body` の一部として評価されるので、ここで `dragLocation.point` を
    /// 読むと盤本体が指の動きを購読してしまい、逃がした意味が無くなる。
    @ViewBuilder private func dragOverlay(metrics: PlayingCardMetrics) -> some View {
        if let drag {
            SolitaireDragLayer(
                cards: drag.cards, grab: drag.grab, location: dragLocation, metrics: metrics)
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
    private func motionID(_ card: SolitaireCard) -> SolitaireCardMotionID {
        SolitaireCardMotionID(deal: model.dealSerial, card: card.id)
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
                emptySlot(metrics: metrics, symbol: nil)
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
                cardView(SolitaireCard(suit, rank), faceUp: true, isSelected: false, metrics: metrics)
                    .matchedGeometryEffect(id: motionID(SolitaireCard(suit, rank)), in: cardMotion)
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
            // 残り回数を常時見せる（#476 仕様3）。ナンプレの「ヒント3」と同じ見せ方に揃えてある。
            controlButton(
                "戻す\(model.undosRemaining)",
                systemImage: "arrow.uturn.backward",
                tint: Theme.Fill.coral
            ) {
                requestUndo()
            }
            .disabled(!model.canUndo || isWatchingUndoAd)
            // 押せない間も枠は残す（消えると「そんな機能は無い」と読まれる・#198 と同じ扱い）。
            .opacity(model.canUndo ? 1 : 0.4)
            .accessibilityLabel(SolitaireAccessibility.undoButtonLabel(remaining: model.undosRemaining))
            .accessibilityHint(SolitaireAccessibility.undoButtonHint(
                canUndo: model.canUndo,
                remaining: model.undosRemaining
            ))

            // ジョーカーの所持を**常時**見せる（#406 の決裁1）。持っていない間も枠を残すのは
            // 「戻す」と同じ理由で、消すと「そんな機能は無い」と読まれるため（#198）。
            jokerButton

            // 「あとは組札へ積むだけ」になった局面でだけ出す。終盤の 52 回タップを 1 回に畳む。
            if model.canAutoFinish {
                controlButton("自動で上がる", systemImage: "wand.and.stars", tint: Theme.Fill.teal) {
                    model.autoFinish()
                }
                .accessibilityHint("残りの札をまとめて組札へ送ります")
            }

            Spacer(minLength: 0)

            // 標準以外のルールで遊んでいるときだけ出す（#498）。既定の1枚めくりは
            // 「標準」そのものなので札は出さず、操作列の見た目を従来のまま保つ。
            if model.rules.drawMode != .one {
                Text(model.rules.drawMode.label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("このゲームのルールは\(model.rules.drawMode.label)")
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
        .overlay(alignment: .top) {
            if model.isPlacingJoker { jokerPlacingBanner }
        }
    }

    /// ジョーカーの所持ボタン。押すと「置く列を選ぶ」モードに入り、もう一度押すと抜ける。
    private var jokerButton: some View {
        controlButton(
            model.isPlacingJoker ? "やめる" : "ジョーカー",
            systemImage: model.isPlacingJoker ? "xmark.circle.fill" : "questionmark.app.fill",
            tint: model.isPlacingJoker ? Theme.Fill.teal : Theme.Fill.purple
        ) {
            if model.isPlacingJoker { model.cancelPlacingJoker() } else { model.beginPlacingJoker() }
        }
        .disabled(!model.hasJoker && !model.isPlacingJoker)
        .opacity(model.hasJoker || model.isPlacingJoker ? 1 : 0.4)
        .accessibilityLabel(SolitaireAccessibility.jokerButtonLabel(
            hasJoker: model.hasJoker,
            isPlacing: model.isPlacingJoker
        ))
        .accessibilityHint(SolitaireAccessibility.jokerButtonHint(
            hasJoker: model.hasJoker,
            isPlacing: model.isPlacingJoker
        ))
    }

    /// 置き先を選んでいる最中の案内。盤に被せず操作列の上に出す（列をタップさせる必要があるため）。
    private var jokerPlacingBanner: some View {
        Text("ジョーカーを置く列をタップしてください（空の列と、すでにジョーカーがある列には置けません）")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.onAccent)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(Theme.Fill.purple))
            .padding(.horizontal, 8)
            .offset(y: -34)
            .allowsHitTesting(false)
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

    // MARK: - 詰み・敗北確定の救済（#406）

    /// 2 種類の「もう届かない」を1つの面で受ける（#406 の決裁）。
    ///
    /// - **有効手ゼロ**（`isDeadEnd`）: 盤面が進む手が無い。ただし K → 空列の入れ替えは残るので、
    ///   「何もできない」わけではない（#475 の実測）。
    /// - **敗北確定**（`isLost`）: 指せる手は残っているがソルバーが勝ち筋の不在を確定させた。
    ///
    /// **どちらも閉じられる**（#491 の決裁 C）。まだ触れる盤を告知で取り上げない。
    /// 閉じたら配り直すまで出さない。
    ///
    /// ジョーカーは**持っていれば広告なしで使える**（決裁1）。持っていないときだけ広告で補充する
    /// （決裁2）。ここで二重に対価を取らないよう、文言もボタンも所持で切り替える。
    private var rescueOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 20) {
                Text(model.isDeadEnd ? "😵" : "🤔").font(.system(size: 52))
                Text(model.isDeadEnd ? "進める手がありません" : "このままではクリアできません")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(rescueMessage)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                    .multilineTextAlignment(.center)

                jokerRescueButton

                if model.canUndo {
                    Button { requestUndo() } label: {
                        // ここでも残り回数を見せる（#476 仕様3）。押した先で初めて
                        // 「使い切っていた」と分かるのでは、救済の面で二度手間になる。
                        Label("1手戻す（残り\(model.undosRemaining)）", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.Fill.coral, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(Theme.onAccent)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWatchingJokerAd || isWatchingUndoAd)
                    .accessibilityLabel(SolitaireAccessibility.undoButtonLabel(remaining: model.undosRemaining))
                    .accessibilityHint(SolitaireAccessibility.undoButtonHint(
                        canUndo: model.canUndo,
                        remaining: model.undosRemaining
                    ))
                }

                Button { model.newGame() } label: {
                    Text("新しい配札にする")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                .buttonStyle(.plain)
                .disabled(isWatchingJokerAd || isWatchingUndoAd)

                // どちらの告知でも盤には触れる手が残っている。宣告で操作を奪わない（#491）。
                Button { model.dismissRescuePrompt() } label: {
                    Text("このまま続ける")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                .buttonStyle(.plain)
                .disabled(isWatchingJokerAd || isWatchingUndoAd)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SolitaireAccessibility.rescuePromptLabel(
            isDeadEnd: model.isDeadEnd,
            hasJoker: model.hasJoker
        ))
    }

    private var rescueMessage: String {
        // 行き止まりでも K → 空列の入れ替えは残る。「めくるしかない」と書くと、
        // 盤に手が見えている人には事実に反して見える（#475 の会長QA → #491）。
        let head = model.isDeadEnd
            ? "山札をめくるか、盤面が進まない入れ替えしか残っていません。"
            : "指せる手はありますが、ここからは組札を揃えきれません。"
        let tail = model.hasJoker
            ? "ジョーカーを場札に置くと、その上へどんな札でも1枚だけ重ねられます。"
            : "広告を見るとジョーカーを1枚受け取れます。手を戻すか、新しい配札にすることもできます。"
        return head + tail
    }

    /// 所持していれば広告なしで使い、持っていなければリワード広告で補充する。
    private var jokerRescueButton: some View {
        Button {
            if model.hasJoker {
                model.beginPlacingJoker()
            } else {
                requestJoker()
            }
        } label: {
            Label(
                model.hasJoker ? "ジョーカーを使う" : "広告を見てジョーカーをもらう",
                systemImage: model.hasJoker ? "questionmark.app.fill" : "play.rectangle.fill"
            )
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.Fill.purple, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.plain)
        // 「戻す」の補充広告を出している最中もここは押させない（2 本の広告が並走する）。
        .disabled(isWatchingJokerAd || isWatchingUndoAd)
        .opacity(isWatchingJokerAd || isWatchingUndoAd ? 0.5 : 1)
    }

    /// リワード広告 → ジョーカー補充 → 置き先の選択、までを 1 本に繋ぐ。
    ///
    /// 「広告を見たのに何も起きない」経路を作らないのが要（既存の広告契約・ナンプレのヒントと同型）。
    /// 視聴しなかったときと、視聴したのに補充できなかったとき（待っている間に自力で局面が
    /// 変わって所持に戻った等）を読み分けて必ず知らせる。
    private func requestJoker() {
        // 広告のロード〜表示中の連打で 2 本目が失敗し、誤ってアラートが出るのを防ぐ。
        guard !isWatchingJokerAd else { return }
        isWatchingJokerAd = true
        // どの局に対する補充かを、広告を出す前に控える（`requestUndoRefill` と同型。#511）。
        let deal = model.dealSerial
        Task {
            if await services.showRewardedAd(gameID: model.gameID, purpose: .joker) {
                if model.grantJoker(forDeal: deal) {
                    model.beginPlacingJoker()
                } else {
                    showJokerUnavailable = true
                }
            } else {
                showJokerNotEarned = true
            }
            isWatchingJokerAd = false
        }
    }

    /// 「戻す」の入口を 1 本にまとめる（#476）。
    ///
    /// 残り回数があればそのまま戻し、使い切っていたら**提案を出すだけ**にする。
    /// ここで広告を直接出さないのが要で、押した瞬間に再生が始まると
    /// 「戻すつもりが広告を見せられた」になる（決裁の「自動再生禁止」）。
    private func requestUndo() {
        if model.needsUndoRefill {
            showUndoRefillPrompt = true
        } else {
            model.undo()
        }
    }

    /// リワード広告 → 「戻す」の補充。視聴しなかったときと補充できなかったときを読み分けて必ず知らせる。
    private func requestUndoRefill() {
        // 広告のロード〜表示中の連打で 2 本目が失敗し、誤ってアラートが出るのを防ぐ（ジョーカーと同型）。
        guard !isWatchingUndoAd else { return }
        isWatchingUndoAd = true
        // どの局に対する補充かを、広告を出す前に控える。ボタンの `disabled` だけでは
        // ツールバーの「新規ゲーム」からの配り直しを止められない（PR #480 の敵対的検証）。
        let deal = model.dealSerial
        Task {
            if await services.showRewardedAd(gameID: model.gameID, purpose: .undo) {
                if !model.grantUndos(forDeal: deal) { showUndoUnavailable = true }
            } else {
                showUndoNotEarned = true
            }
            isWatchingUndoAd = false
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
        ("山札", "左上の山札はタップでめくれます。最後までめくったらもう一度タップすると、捨て札が山札に戻ります（何周でもできます）"),
        ("めくり方を選ぶ", "「新規ゲーム」を押すと、山札を1枚ずつめくるか3枚ずつめくるかを選べます。3枚めくりでは使えるのがいちばん上の1枚だけになるぶん歯ごたえがあり、自己ベストは1枚めくりとは別に記録されます（Game Center の順位表に載るのは1枚めくりだけです）。選んだめくり方はその配札のあいだ変わりません"),
        ("操作", "動かしたい札をタップして選び、置きたい列か組札をタップします。もう一度同じ札をタップすると選択を外せます"),
        ("戻す", "「戻す」は1局につき\(SolitaireUndoBudget.free)回まで無料です。残り回数はボタンに出ています。使い切ったあとは、広告を見ると\(SolitaireUndoBudget.refill)回ぶん補充できます"),
        ("ジョーカー", "1局につき1枚持っています。場札の列の上に置くと、その上にはどんな札でも1枚だけ重ねられます（空の列と、すでにジョーカーがある列には置けません）。上の札が全部はけると自動で消えて、下の札がまた使えるようになります"),
        ("ジョーカーの補充", "使い切ったあと、手詰まりになったときや、指せる手はあってもクリアできなくなったときに、広告を見て1枚受け取れます。「戻す」でジョーカーを置いた手を巻き戻せば、手持ちに戻ります。ジョーカーを使ってクリアした記録は、自己ベストには残りますが Game Center の順位表には送りません"),
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

/// ドラッグ中の札の状態。**持ち上げた瞬間から置くまで変わらない値だけを持つ**（#521）。
/// 毎サンプル変わる指の位置は `SolitaireDragLocation` にある。
struct SolitaireDragState {
    var source: SolitaireSelection
    var cards: [SolitaireCard]
    /// つかんだ点から札の左上までのずれ（追従表示の位置合わせ用）。
    var grab: CGSize
}

/// 盤座標系での指の位置だけを持つ入れ物（#521）。
///
/// 参照型にして「盤本体は持たず、追従表示だけが読む」形にするためのもの。値型で
/// `@State` に置くと、指を 1 サンプル動かすたびにビュー全体が無効化される。
/// `@Observable` なので、`point` を body で読んだビューだけが作り直される。
@MainActor @Observable final class SolitaireDragLocation {
    var point: CGPoint = .zero

    init(point: CGPoint = .zero) {
        self.point = point
    }
}

/// 指に追従する持ち上げた札。**位置を読むのはこの body の中だけ**（#521）。
///
/// 盤本体（`SolitaireView.body`）から独立したビューにすることで、指の動きによる
/// 無効化がこのビューで止まる。当たり判定は持たない（ドロップ先は下の盤が報告する）。
private struct SolitaireDragLayer: View {
    let cards: [SolitaireCard]
    let grab: CGSize
    let location: SolitaireDragLocation
    let metrics: PlayingCardMetrics

    var body: some View {
        let upStep = SolitaireMetrics.faceUpStep(cardHeight: metrics.height)
        let origin = SolitaireDragLayout.origin(location: location.point, grab: grab)
        ZStack(alignment: .top) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                SolitaireCardBody(card: card, faceUp: true, isSelected: false,
                                  isCovered: index < cards.count - 1, metrics: metrics)
                    .offset(y: CGFloat(index) * upStep)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
        .offset(x: origin.x, y: origin.y)
        .allowsHitTesting(false)
    }
}

/// 追従表示の位置合わせ。
enum SolitaireDragLayout {
    /// 指の位置とつかんだ点のずれから、持ち上げた札の左上を出す。
    static func origin(location: CGPoint, grab: CGSize) -> CGPoint {
        CGPoint(x: location.x - grab.width, y: location.y - grab.height)
    }
}

/// 移動の補間で札どうしを結ぶ鍵（#421）。配り直しの世代を含めるので、世代が変わると結ばれない。
struct SolitaireCardMotionID: Hashable {
    let deal: Int
    let card: Int
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
