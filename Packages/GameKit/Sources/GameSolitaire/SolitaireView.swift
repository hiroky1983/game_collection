import Foundation
import SwiftUI
import Core

public struct SolitaireView: View {
    @State private var model: SolitaireModel
    @State private var showConfirmNewGame = false
    private let services: GameServices
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: SolitaireModel(services: services))
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            board
                // 7 列は横幅で大きさが決まるので、左右の余白ぶんまで使って札を大きくする
                // （麻雀ソリティアの盤面と同じ扱い）。
                .padding(.horizontal, -Theme.pad)
                .layoutPriority(1)
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
        .task { model.resumeTimerIfNeeded() }
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
        return model.isDeadEnd ? "😵" : "🃏"
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
            .gameAnimation(.easeOut(duration: 0.18), value: boardAnimationKey)
        }
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
                cardView(card, faceUp: true, isSelected: model.selection == .waste, metrics: metrics)
            } else {
                emptySlot(metrics: metrics, symbol: nil)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.tapWaste() }
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
                cardView(SolitaireCard(suit, rank), faceUp: true, isSelected: false, metrics: metrics)
            } else {
                // 空の組札にはスート記号を薄く置く。どこに何を積むのかが最初から分かるようにする。
                emptySlot(metrics: metrics, symbol: nil, suit: suit)
            }
        }
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
            } else {
                Color.clear.frame(width: metrics.width, height: height)
            }

            ForEach(Array(column.faceDown.enumerated()), id: \.offset) { index, _ in
                ZStack {
                    PlayingCardSurface(faceUp: false, cornerRadius: metrics.cornerRadius)
                    PlayingCardBack(metrics: metrics)
                }
                .frame(width: metrics.width, height: metrics.height)
                .offset(y: CGFloat(index) * downStep)
                .accessibilityHidden(true)
            }

            ForEach(Array(column.faceUp.enumerated()), id: \.offset) { index, card in
                faceUpCard(pile: pile, index: index, card: card, column: column, metrics: metrics)
                    .offset(y: CGFloat(column.faceDown.count) * downStep + CGFloat(index) * upStep)
            }
        }
        .frame(width: metrics.width, height: height, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { model.tapPile(pile) }
        // 空の列は「K だけ置ける」ことを読み上げないと、音声では置けない理由が分からない。
        .accessibilityLabel(column.isEmpty ? SolitaireAccessibility.emptyPileLabel(pile: pile) : "")
    }

    private func faceUpCard(
        pile: Int,
        index: Int,
        card: SolitaireCard,
        column: SolitairePile,
        metrics: PlayingCardMetrics
    ) -> some View {
        let isSelected = model.selection == .tableau(pile: pile, cardIndex: index)
        return cardView(card, faceUp: true, isSelected: isSelected, metrics: metrics)
            .contentShape(Rectangle())
            .onTapGesture { model.tapPile(pile, cardIndex: index) }
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

    private func cardView(
        _ card: SolitaireCard,
        faceUp: Bool,
        isSelected: Bool,
        metrics: PlayingCardMetrics
    ) -> some View {
        ZStack {
            // 外形・面はトランプ共通基盤（#397。質感は CardStyle #366）。
            PlayingCardSurface(
                faceUp: faceUp,
                cornerRadius: metrics.cornerRadius,
                border: isSelected ? Theme.coral : Color.gray.opacity(0.2),
                borderWidth: isSelected ? 2.5 : 0.5,
                shadowColor: isSelected ? Theme.coral.opacity(0.6) : .black.opacity(0.15),
                shadowRadius: isSelected ? 6 : 3
            )
            PlayingCardFace(figure: card.figure, metrics: metrics)
        }
        .frame(width: metrics.width, height: metrics.height)
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
