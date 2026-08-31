import SwiftUI
import Core

/// 将棋の対局画面（CPU 対戦）。人間の手番側を常に手前に表示する。
public struct ShogiView: View {
    @State private var model: ShogiGameModel
    private let services: GameServices
    @State private var showNewGame: Bool
    @State private var showConfirmNewGame = false
    @State private var showUndoConfirm = false
    @State private var showResignConfirm = false
    @State private var showRewardNotEarned = false
    /// 盤上の駒に「移動しても変わらない ID」を与えるための対応付け（#200）。
    /// 表示局面が変わるたびに更新し、駒の層はこれだけを見て描く。
    @State private var pieceLayout: ShogiPieceLayout
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        self.services = services
        let model = ShogiGameModel(services: services)
        _model = State(initialValue: model)
        _pieceLayout = State(initialValue: ShogiPieceLayout(model.displayedPosition))
        _showNewGame = State(initialValue: !services.snapshots.exists(for: "shogi"))
    }

    /// 人間が後手なら盤を反転して表示する。
    private var flipped: Bool { model.humanSide == .white }

    #if DEBUG
    /// 駒スタイルのコンペ（#366・会長レビュー用）。採用が決まったらピッカーごと畳む。
    @State private var komaVariant: KomaCompetitionVariant = .standard
    #endif

    public var body: some View {
        // 縦の余白は 8。対局中と終局後で高さが変わらない `controlArea` を置くぶん、
        // 盤に回せる高さを間隔から捻出している（#139）。
        VStack(spacing: 8) {
            statusBar
            #if DEBUG
            komaCompetitionPicker
            #endif
            HandAreaView(model: model, color: model.humanSide.opponent)
            board
                .layoutPriority(1)
            HandAreaView(model: model, color: model.humanSide)
            HowToPlayHint(.shogi, playLog: services.playLog)
            controlArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.none, value: model.gameOver)
        #if DEBUG
        .environment(\.komaStyle, komaVariant.spec)
        #endif
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
                Text("将棋")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.phase == .playing && !model.moves.isEmpty {
                        showConfirmNewGame = true
                    } else {
                        showNewGame = true
                    }
                } label: {
                    Label("新規対局", systemImage: "plus.circle.fill")
                }
            }
        }
        .howToPlay(.shogi)
        .sheet(isPresented: $showNewGame) {
            NewGameSheet(initialSide: model.humanSide, initialLevel: model.aiLevel) { side, level in
                model.newGame(humanSide: side, aiLevel: level)
                showNewGame = false
            } onCancel: {
                showNewGame = false
            }
        }
        .confirmationDialog("新規対局しますか？", isPresented: $showConfirmNewGame, titleVisibility: .visible) {
            Button("終了して新規対局", role: .destructive) { showNewGame = true }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると対局データが失われます。")
        }
        .overlay { promotionOverlay }
        .task(id: model.aiTurnKey) {
            await model.performAIMoveIfNeeded()
        }
        // 人間の着手・CPU の着手・待った・検討ナビのどれで局面が変わっても、
        // 経路を問わずここ 1 か所で駒の対応付けを進める（#200）。
        .onChange(of: model.displayedPosition) { _, position in
            pieceLayout.update(to: position)
        }
    }

    /// 成り確認の札。出入りのアニメーションは**残り続ける親**（この `ZStack`）に置く（#201）。
    /// 入れ替わる枝の中に置くと、消える側と一緒に修飾子も消えて効かない（#195）。
    private var promotionOverlay: some View {
        ZStack {
            if model.pendingPromotion != nil {
                // 暗幕と札で別のトランジションを使う。ひとまとめに縮小を掛けると
                // 画面いっぱいの暗幕まで拡縮して、幕の縁が動いて見える。
                Color.black.opacity(0.35).ignoresSafeArea()
                    .transition(.opacity)
                VStack(spacing: 20) {
                    Text("成りますか？")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 16) {
                        Button {
                            model.resolvePromotion(false)
                        } label: {
                            Text("不成")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(width: 80, height: 44)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Theme.ink)
                        }
                        Button {
                            model.resolvePromotion(true)
                        } label: {
                            Text("成る")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(width: 80, height: 44)
                                .background(Theme.coral, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                // 札は中央に置いてあり `offset` を持たないので、縮小の基準は札の中心になる。
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        // 札を出していない間、この層は盤の上に常設される（分岐を中に入れたぶん）。
        // 触れないことを明示しておく — 空の `ZStack` は素通しだが、暗黙に頼ると
        // 中身を足したときに静かに盤のタップを塞ぐ。
        .allowsHitTesting(model.pendingPromotion != nil)
        .gameAnimation(ShogiMotion.promotionPrompt, value: model.pendingPromotion != nil)
    }

    // MARK: - 盤

    private var board: some View {
        let pos = model.displayedPosition
        return GeometryReader { geo in
            let cell = (geo.size.width - 8) / 9
            VStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<9, id: \.self) { col in
                            let idx = squareIndex(row: row, col: col)
                            ShogiCell(
                                size: cell,
                                isSelected: model.selectedSquare == idx,
                                isLastMove: model.highlightedSquares.contains(idx)
                            )
                            .onTapGesture { model.tapSquare(idx) }
                            // 盤は 81 個の図形の集まりでしかないため、マスごとに
                            // 読み上げ要素を作る（#188）。`children: .ignore` にしないと
                            // 駒の漢字1文字がそのまま読まれる。
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(ShogiAccessibility.squareLabel(
                                index: idx,
                                piece: pos.squares[idx],
                                isSelected: model.selectedSquare == idx,
                                isTarget: model.legalTargets.contains(idx),
                                isLastMove: model.highlightedSquares.contains(idx)
                            ))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { model.tapSquare(idx) }
                        }
                    }
                }
            }
            .background(BoardStyle.line)
            // 盤の木の質感（#366）: 柾目の縦筋と星4つを薄く重ねる。描画のみでタップは素通し。
            .overlay { boardTexture }
            // 駒はマスの中ではなく盤全体を覆う 1 枚の層に置く（#200）。
            // マスに紐づけると駒の同一性がマスと一緒に変わり、移動が補間されない。
            .overlay { pieceLayer(cell: cell) }
            // 着手先の印は駒より**上**。マスの中に描いていた頃の重なり順をそのまま保つ
            // （取れる駒に重ねる枠が駒の下に潜ると、何が取れるのか読めなくなる）。
            .overlay { targetLayer(cell: cell) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(LinearGradient(
                        colors: [BoardStyle.frameTop, BoardStyle.frameBottom],
                        startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// 画面 (row,col) → 内部マス。人間が先手なら先手視点、後手なら反転。
    private func squareIndex(row: Int, col: Int) -> Int {
        Sq.boardIndex(row: row, col: col, flipped: flipped)
    }

    /// 盤の上に重ねる駒の層。ここだけが駒を描き、マスの側は描かない（#200）。
    ///
    /// マス 1 つぶんの間隔は **盤の実寸 ÷ 9** から取る。`ShogiCell` 側の余白の積み上げを
    /// 数式で再現しないので、マスの組み方を変えても駒の位置がずれない。
    /// 駒そのものの大きさは従来どおりマスの実寸（`cell`）から作り、見た目を変えない。
    private func pieceLayer(cell: CGFloat) -> some View {
        GeometryReader { geo in
            let slot = geo.size.width / 9
            ZStack(alignment: .topLeading) {
                ForEach(pieceLayout.placements) { placement in
                    let spot = Sq.displayPosition(of: placement.square, flipped: flipped)
                    KomaView(piece: placement.piece, size: cell,
                             pointsUp: placement.piece.color == model.humanSide)
                        // `.transition` は `.position` より前に置く。あとに置くと拡大・縮小の
                        // 基準がマスではなく盤の原点になり、消える駒が左上へ吸い込まれる。
                        .transition(.opacity)
                        .position(x: slot * (CGFloat(spot.col) + 0.5),
                                  y: slot * (CGFloat(spot.row) + 0.5))
                }
            }
            // アニメーションの指定は**この 1 か所だけ**にする。入れ子にすると内側が
            // 外側のトランザクションを打ち消し、片方の演出が静かに効かなくなる。
            .gameAnimation(ShogiMotion.pieceMove, value: pieceLayout)
        }
        // 当たり判定と読み上げはマス（`ShogiCell` 側）が持ち続ける。
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 盤の木の質感（#366）: 柾目の縦筋と星。決定的な固定パターンで、乱数は使わない。
    /// 星は 3三・3六・6三・6六 の線の交点（実物の盤と同じ位置）。
    private var boardTexture: some View {
        GeometryReader { geo in
            let slot = geo.size.width / 9
            Canvas { ctx, sz in
                for (i, x) in Array(stride(from: 0.04, through: 0.96, by: 0.08)).enumerated() {
                    let bend = (i % 2 == 0 ? 0.012 : -0.012) * sz.width
                    var p = Path()
                    p.move(to: CGPoint(x: sz.width * x, y: 0))
                    p.addQuadCurve(to: CGPoint(x: sz.width * x + 2, y: sz.height),
                                   control: CGPoint(x: sz.width * x + bend, y: sz.height * 0.5))
                    ctx.stroke(p, with: .color(BoardStyle.boardGrain.opacity(0.10)), lineWidth: 1.2)
                }
                for r in [3, 6] {
                    for c in [3, 6] {
                        let pt = CGPoint(x: slot * CGFloat(c), y: slot * CGFloat(r))
                        let dr: CGFloat = slot * 0.055
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - dr, y: pt.y - dr,
                                                        width: dr * 2, height: dr * 2)),
                                 with: .color(BoardStyle.boardGrain.opacity(0.7)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 着手先の印。駒の層より上に重ねる（#200）。
    /// アニメーションは付けない — 選択の反映は従来どおり即時にする。
    private func targetLayer(cell: CGFloat) -> some View {
        GeometryReader { geo in
            let slot = geo.size.width / 9
            let pos = model.displayedPosition
            ZStack(alignment: .topLeading) {
                ForEach(model.legalTargets.sorted(), id: \.self) { square in
                    let spot = Sq.displayPosition(of: square, flipped: flipped)
                    Group {
                        if pos.squares[square] == nil {
                            Circle().fill(Theme.coral.opacity(0.55))
                                .frame(width: cell * 0.28, height: cell * 0.28)
                        } else {
                            RoundedRectangle(cornerRadius: 4).stroke(Theme.coral, lineWidth: 3)
                                .frame(width: cell - 4, height: cell - 4)
                        }
                    }
                    .position(x: slot * (CGFloat(spot.col) + 0.5),
                              y: slot * (CGFloat(spot.row) + 0.5))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - ステータス

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let result = model.resultText {
                Label(result, systemImage: "flag.checkered")
                    .themeBody(16).foregroundStyle(Theme.coral)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(model.position.sideToMove == .black ? "先手番" : "後手番")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(model.position.sideToMove == .black ? Theme.fillStrong : Theme.teal))
                    // 手番が移ったことを色の移り変わりで見せる（#201）。文字は差し替わるだけなので、
                    // 目に留まるのは色の変化。着手そのものを待たせないよう短く取る。
                    .gameAnimation(ShogiMotion.turnChange, value: model.position.sideToMove)
                if model.isThinking {
                    ProgressView().controlSize(.small)
                    Text("CPU思考中…").themeBody(13).foregroundStyle(Theme.inkSub)
                } else if let last = model.highlightedMoveText {
                    Text("直前 \(last)").themeBody(14).foregroundStyle(Theme.ink)
                }
            }
            Spacer(minLength: 8)
            if model.gameOver {
                // 終局後の記録は行を増やさずここに同居させる（#139）。手数は検討ナビが
                // 「n/N手」で出しているため、入れ替えても情報は失われない。
                RecordLabel(model.recordResult)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("\(model.moves.count)手").themeBody(13).foregroundStyle(Theme.inkSub)
            }
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .popCard(corner: Theme.cornerSmall)
    }

    #if DEBUG
    /// #366 コンペ用の駒スタイル切り替え（DEBUG のみ）。盤・持ち駒の駒が即座に切り替わる。
    private var komaCompetitionPicker: some View {
        Picker("駒スタイル", selection: $komaVariant) {
            ForEach(KomaCompetitionVariant.allCases) { variant in
                Text(variant.rawValue).tag(variant)
            }
        }
        .pickerStyle(.segmented)
    }
    #endif

    // MARK: - 盤の下の操作エリア

    /// 対局中（投了・待った）と終局後（検討ナビ・もう一度・レコメンド）で中身が入れ替わるが、
    /// **高さは常に終局後の最大構成に揃える**（#139）。
    ///
    /// ここが伸び縮みすると `board`（`aspectRatio(1, .fit)` + `layoutPriority(1)`）が
    /// 帳尻合わせに縮み、決着した瞬間に盤が一段小さくなって見える。レコメンドは出るとは
    /// 限らず×でも閉じられるため、カードのぶんは常にひな形で高さを確保しておく。
    private var controlArea: some View {
        ZStack(alignment: .top) {
            finishedControls { RecommendationCard.heightPlaceholder }
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if model.gameOver {
                finishedControls {
                    RecommendationSlot(services: services, isFinished: true)
                }
            } else {
                gameControls
            }
        }
    }

    /// 終局後に出すもの。高さの基準（ひな形）と実物で同じ組み方を使う。
    private func finishedControls<Recommendation: View>(
        @ViewBuilder recommendation: () -> Recommendation
    ) -> some View {
        VStack(spacing: 8) {
            reviewControls
            recommendation()
        }
    }

    private var gameControls: some View {
        HStack(spacing: 12) {
            Button { showResignConfirm = true } label: {
                Label("投了", systemImage: "flag.fill")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.coral))
            }
            .confirmationDialog("投了しますか？", isPresented: $showResignConfirm, titleVisibility: .visible) {
                Button("投了する", role: .destructive) { model.resign() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("現在の対局を終了します。CPUの勝ちになります。")
            }

            Spacer()

            Button { showUndoConfirm = true } label: {
                Label("待った", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)
            .alert("待った確認", isPresented: $showUndoConfirm) {
                Button(model.undoUsed ? "広告を見て戻す" : "戻す（無料）") {
                    Task {
                        if model.undoUsed {
                            // 視聴完了（報酬獲得）したときだけ待ったを許可する
                            guard await services.ads.showRewardedAd() else {
                                showRewardNotEarned = true
                                return
                            }
                        }
                        model.undoLastExchange()
                    }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text(model.undoUsed
                     ? "無料の待ったは使い切りました。\n広告を視聴すると1手戻せます。"
                     : "直前の1手を取り消します。\n無料で使えるのは1回だけです。")
            }
            .alert("待ったは使えませんでした", isPresented: $showRewardNotEarned) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。")
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 検討ナビと「もう一度」は 1 段にまとめ、対局中の `gameControls` と同じ高さに収める（#139）。
    /// 2 段のままだと盤の下が伸び、決着の瞬間に盤が縮む。
    private var reviewControls: some View {
        HStack(spacing: 12) {
            Button { model.reviewStepBack() } label: { Image(systemName: "backward.frame.fill") }
                .disabled(model.reviewPly <= 0)
            Text("\(model.reviewPly)/\(model.moves.count)手")
                .themeBody(14).monospacedDigit().foregroundStyle(Theme.ink)
            Button { model.reviewStepForward() } label: { Image(systemName: "forward.frame.fill") }
                .disabled(model.reviewPly >= model.moves.count)

            Spacer(minLength: 8)

            Button { showNewGame = true } label: {
                Label("もう一度", systemImage: "arrow.clockwise")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.coral))
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - 新規対局シート

/// 先後・難易度を大きなボタンで選ぶ。
struct NewGameSheet: View {
    @State private var side: Side
    @State private var level: Int
    let onStart: (Side, Int) -> Void
    let onCancel: () -> Void

    init(initialSide: Side, initialLevel: Int,
         onStart: @escaping (Side, Int) -> Void, onCancel: @escaping () -> Void) {
        _side = State(initialValue: initialSide)
        _level = State(initialValue: initialLevel)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                section("あなたの手番") {
                    HStack(spacing: 12) {
                        chooser(title: "先手", subtitle: "▲ 先に指す", selected: side == .black, accent: Theme.fillStrong) { side = .black }
                        chooser(title: "後手", subtitle: "△ 後に指す", selected: side == .white, accent: Theme.teal) { side = .white }
                    }
                }
                section("CPUの強さ") {
                    HStack(spacing: 12) {
                        chooser(title: "弱", subtitle: "駒得だけ", selected: level == 0, accent: Theme.teal) { level = 0 }
                        chooser(title: "普通", subtitle: "囲いを作る", selected: level == 1, accent: Theme.yellow) { level = 1 }
                        chooser(title: "強", subtitle: "定跡＋深読み", selected: level == 2, accent: Theme.coral) { level = 2 }
                    }
                }
                Spacer()
                Button { onStart(side, level) } label: {
                    Text("対局開始").themeBody(18).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.coral)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("新規対局")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
            }
        }
        .gameSheetDetents()
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).themeBody(15).foregroundStyle(Theme.inkSub)
            content()
        }
    }

    private func chooser(title: String, subtitle: String, selected: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).themeTitle(22).foregroundStyle(selected ? .white : Theme.ink)
                Text(subtitle).font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? .white.opacity(0.9) : Theme.inkSub)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(selected ? accent : Theme.surface)
                    .shadow(color: .black.opacity(selected ? 0.15 : 0.06), radius: 6, y: 3)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 盤・駒

/// 将棋の演出の長さ（#200・#201）。Reduce Motion への追従は `gameAnimation(_:value:)` 側が持つ。
///
/// 長さは秒の定数として持ち、`Animation` はそこから組む。`Animation` からは長さを読み出せないため、
/// 定数を経由しないと「札は駒の移動より短い」のような**長さの大小関係をテストで固定できない**。
enum ShogiMotion {
    /// 駒の移動にかかる時間の目安（バネの `response`）。CPU が即指しする場面や早指しでも
    /// 次の着手に食い込まないよう短めに取る。
    static let pieceMoveResponse: TimeInterval = 0.26
    /// 成り確認の札の出入り。`pieceMoveResponse` より短くする。
    static let promotionPromptDuration: TimeInterval = 0.18
    /// 手番バッジの色替え。
    static let turnChangeDuration: TimeInterval = 0.2

    /// 駒の移動。跳ね返り（`dampingFraction` < 1）は駒がマスから外れて見えるため、ほぼ入れない。
    static let pieceMove: Animation = .spring(response: pieceMoveResponse, dampingFraction: 0.9)
    /// 成り確認の札の出入り（#201）。**駒の移動より短く取る**。
    /// 札が消えるのと同時に成った駒が動き出すため、ここが長いと札が駒に被ったまま残る。
    static let promotionPrompt: Animation = .easeOut(duration: promotionPromptDuration)
    /// 手番バッジの色替え（#201）。手番が移ったと分かる程度に留め、
    /// タップから盤が反応するまでの体感を遅くしない。
    static let turnChange: Animation = .easeInOut(duration: turnChangeDuration)
}

/// 盤の配色（明るい木目調）。
enum BoardStyle {
    static let frame = Color(hex: 0xE7B96A)
    /// 盤の枠は単色をやめて上→下の木のグラデーションにする（#366）。
    static let frameTop = Color(hex: 0xEDC178)
    static let frameBottom = Color(hex: 0xD3A04D)
    static let cell = Color(hex: 0xFBE6B6)
    static let line = Color(hex: 0xCDA15B)
    /// 盤面に薄く重ねる柾目と星の色（#366）。
    static let boardGrain = Color(hex: 0xA87B3C)
    /// 駒は実物と同じくツゲ材（黄楊）のような単色。先手・後手は色ではなく向き（180度回転）で見分ける。
    static let komaWoodLight = Color(hex: 0xF3DFAE)
    static let komaWoodDark = Color(hex: 0xD9B673)
    /// 駒の側面（#366）。本体を下へずらした同じ駒形をこの色で敷き、木駒の厚みを見せる。
    static let komaWoodSide = Color(hex: 0xA37C42)
    /// 木目の筋（#366）。木地の上に低い不透明度で重ねる。
    static let komaGrain = Color(hex: 0x8A6A32)
}

/// 1 マス。マスの色だけを描く。
///
/// 駒と着手先の印は描かない（#200）。移動を補間するため、駒は盤全体を覆う 1 枚の層
/// （`ShogiView.pieceLayer`）が、その上に重ねる印は `ShogiView.targetLayer` が受け持つ。
struct ShogiCell: View {
    let size: CGFloat
    let isSelected: Bool
    let isLastMove: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(BoardStyle.cell)
            if isLastMove {
                Rectangle().fill(Theme.coral.opacity(0.22)) // 直前手のマス
            }
            if isSelected {
                Rectangle().fill(Theme.yellow.opacity(0.65))
            }
        }
        .frame(width: size, height: size)
        .padding(0.5)
    }
}

/// 駒の見た目一式（#366）。色・側面・木目・面取りをデータとして持ち、`KomaView` が描画する。
///
/// 会長コンペ（DEBUG の `KomaCompetitionVariant`）で候補を実機比較するための構造で、
/// 本採用が決まったら `standard` に採用値を畳み、候補は削除する。
struct KomaStyleSpec: Equatable {
    let faceTop: UInt32
    let faceBottom: UInt32
    let sideTop: UInt32
    let sideBottom: UInt32
    /// 側面の見える高さ（駒サイズに対する比）。
    let sideOffset: CGFloat
    /// 側面を右下へもずらし、五角柱の2面に見せるか。
    let sideDiagonal: Bool
    /// true = 年輪の山形 + 縦筋の木目 v2。false = 従来の縦カーブ3本。
    let organicGrain: Bool
    let grain: UInt32
    let grainOpacity: Double
    /// 上辺の面取りの色（真っ白だと灰色に沈むため、木の明色を使う）。
    let chamferTint: UInt32
    let chamferOpacity: Double
    let chamferWidth: CGFloat
    let outline: UInt32
    let outlineOpacity: Double
    let text: UInt32

    /// 現行の見た目（v1.1.2 からの流れ + #371/#372）。
    static let standard = KomaStyleSpec(
        faceTop: 0xF3DFAE, faceBottom: 0xD9B673,
        sideTop: 0xA37C42, sideBottom: 0xA37C42,
        sideOffset: 0.045, sideDiagonal: false,
        organicGrain: false, grain: 0x8A6A32, grainOpacity: 0.16,
        chamferTint: 0xFFFFFF, chamferOpacity: 0.55, chamferWidth: 0.035,
        outline: 0x8A6A32, outlineOpacity: 0.6,
        text: 0x2A1B0E)
}

private struct KomaStyleKey: EnvironmentKey {
    static let defaultValue = KomaStyleSpec.standard
}

extension EnvironmentValues {
    /// 駒の見た目。DEBUG のコンペピッカーが差し替える。既定は `standard`。
    var komaStyle: KomaStyleSpec {
        get { self[KomaStyleKey.self] }
        set { self[KomaStyleKey.self] = newValue }
    }
}

#if DEBUG
/// 駒スタイルのコンペ候補（#366 会長レビュー用・DEBUG のみ）。
enum KomaCompetitionVariant: String, CaseIterable, Identifiable {
    case standard = "現"
    case warmWhite = "E"
    case amberSoft = "F"
    case candy = "G"
    case amberPrism = "H"

    var id: String { rawValue }

    var spec: KomaStyleSpec {
        switch self {
        case .standard: return .standard
        case .warmWhite: return KomaStyleSpec(
            faceTop: 0xF8ECC8, faceBottom: 0xE3C68C,
            sideTop: 0xA87F42, sideBottom: 0x7E5C2A,
            sideOffset: 0.10, sideDiagonal: false,
            organicGrain: true, grain: 0xA5793C, grainOpacity: 0.26,
            chamferTint: 0xFFF7DC, chamferOpacity: 0.95, chamferWidth: 0.05,
            outline: 0x7E5C2A, outlineOpacity: 0.7,
            text: 0x241708)
        case .amberSoft: return KomaStyleSpec(
            faceTop: 0xEDD3A0, faceBottom: 0xD3A662,
            sideTop: 0x8F6830, sideBottom: 0x6A4A1E,
            sideOffset: 0.10, sideDiagonal: false,
            organicGrain: true, grain: 0x8F6528, grainOpacity: 0.28,
            chamferTint: 0xFCEECB, chamferOpacity: 0.95, chamferWidth: 0.05,
            outline: 0x6A4A1E, outlineOpacity: 0.7,
            text: 0x201304)
        case .candy: return KomaStyleSpec(
            faceTop: 0xE7BE7C, faceBottom: 0xC08A45,
            sideTop: 0x7A5322, sideBottom: 0x543813,
            sideOffset: 0.095, sideDiagonal: true,
            organicGrain: true, grain: 0x7A5322, grainOpacity: 0.30,
            chamferTint: 0xF7DFAE, chamferOpacity: 0.95, chamferWidth: 0.05,
            outline: 0x543813, outlineOpacity: 0.7,
            text: 0x1F1204)
        case .amberPrism: return KomaStyleSpec(
            faceTop: 0xEDD3A0, faceBottom: 0xD3A662,
            sideTop: 0x8F6830, sideBottom: 0x63451B,
            sideOffset: 0.095, sideDiagonal: true,
            organicGrain: true, grain: 0x8F6528, grainOpacity: 0.28,
            chamferTint: 0xFFF3D4, chamferOpacity: 0.95, chamferWidth: 0.05,
            outline: 0x63451B, outlineOpacity: 0.7,
            text: 0x201304)
        }
    }
}
#endif

/// 将棋の駒（木製の実物に寄せた見た目・五角形）。先手・後手は色ではなく
/// 向き（pointsUp=false＝相手の駒は180度回転）だけで見分ける（実物と同じ規則）。
struct KomaView: View {
    let piece: Piece
    let size: CGFloat
    let pointsUp: Bool
    @Environment(\.komaStyle) private var style

    var body: some View {
        ZStack {
            // 側面（#366）: 本体を下へずらした同じ駒形を濃い木色で敷き、木駒の厚みを見せる。
            // 落ち影はいちばん下のこの層に掛ける（本体に掛けると影が自分の側面に落ちて濁る）。
            //
            // 向きの回転はこの層と本体に**別々に**掛ける。外側の ZStack ごと回すと
            // 下方向のオフセットまで回って、後手の駒だけ厚みが上端に出てしまう
            // （厚みと影は駒の向きに関係なく、机に置かれた実物として常に下端が正しい）。
            // 回転 → オフセットの順なので、ずれは常に画面座標の下向きになる。
            KomaShape()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: style.sideTop), Color(hex: style.sideBottom)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .rotationEffect(.degrees(pointsUp ? 0 : 180))
                .offset(x: style.sideDiagonal ? size * 0.03 : 0,
                        y: size * style.sideOffset)
                .shadow(color: .black.opacity(0.30), radius: 2.5, y: 2)
            // 木地: 上が明るく下がやや濃い縦グラデーションで、削り出した木の丸みを表現。
            ZStack {
                KomaShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: style.faceTop), Color(hex: style.faceBottom)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // 木目（#366）: 低い不透明度の筋。文字より下の層。
                    .overlay(grainOverlay)
                    .overlay(KomaShape().stroke(
                        Color(hex: style.outline).opacity(style.outlineOpacity), lineWidth: 1))
                    // ベゼル: 縁の内側に明→暗のグラデーション線を重ね、断面の厚みを疑似表現。
                    .overlay(
                        KomaShape()
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: style.chamferTint).opacity(style.chamferOpacity),
                                             .clear,
                                             Color.black.opacity(0.25)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: max(1, size * style.chamferWidth)
                            )
                    )
                    // 稜線: 面と側面の境目に1本のエッジを立て、五角柱の折り目に見せる（#366）。
                    .overlay(
                        KomaBaseEdgeShape()
                            .stroke(Color(hex: style.sideBottom).opacity(0.55),
                                    lineWidth: max(1, size * 0.02))
                    )
                Text(Glyph.kanji(for: piece))
                    .font(.system(size: size * 0.46, weight: .black, design: .serif))
                    .foregroundStyle(piece.promoted ? Theme.coral : Color(hex: style.text))
                    // 彫り込まれた文字に見えるよう、上に淡いハイライト・下に淡い影を重ねる。
                    .shadow(color: .white.opacity(0.4), radius: 0, x: 0, y: -0.5)
                    .shadow(color: .black.opacity(0.3), radius: 0.5, x: 0, y: 0.8)
            }
            .rotationEffect(.degrees(pointsUp ? 0 : 180))
        }
        .frame(width: size * 0.86, height: size * 0.86)
    }

    @ViewBuilder private var grainOverlay: some View {
        if style.organicGrain {
            ZStack {
                KomaGrainArcsShape()
                    .stroke(Color(hex: style.grain).opacity(style.grainOpacity),
                            lineWidth: max(0.7, size * 0.024))
                KomaGrainStreaksShape()
                    .stroke(Color(hex: style.grain).opacity(style.grainOpacity * 0.55),
                            lineWidth: max(0.5, size * 0.015))
            }
            .clipShape(KomaShape())
        } else {
            KomaGrainShape()
                .stroke(Color(hex: style.grain).opacity(style.grainOpacity),
                        lineWidth: max(0.5, size * 0.02))
                .clipShape(KomaShape())
        }
    }
}

/// 木目・主層（#366）: 緩く曲がる縦筋4本。会長レビューで「年輪の山形（v2）より
/// 縦筋（1巡目）が良い」となったため、縦筋を本数多めにしたものを主層にする。
struct KomaGrainArcsShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        for (x, bend) in [(0.24, -0.04), (0.40, 0.09), (0.56, -0.07), (0.72, 0.05)] {
            p.move(to: CGPoint(x: w * x, y: h * 0.10))
            p.addQuadCurve(to: CGPoint(x: w * (x + 0.02), y: h * 0.94),
                           control: CGPoint(x: w * (x + bend), y: h * 0.5))
        }
        return p
    }
}

/// 木目・副層（#366）: 主層の間を埋める細く薄い縦筋。
struct KomaGrainStreaksShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        for (x, bend) in [(0.31, 0.05), (0.48, -0.06), (0.64, 0.08), (0.80, -0.04)] {
            p.move(to: CGPoint(x: w * x, y: h * 0.14))
            p.addQuadCurve(to: CGPoint(x: w * (x - 0.015), y: h * 0.92),
                           control: CGPoint(x: w * (x + bend), y: h * 0.55))
        }
        return p
    }
}

/// 木目の筋（#366）。緩い縦カーブ3本の**固定パターン**で、どの駒も同じ木目にする
/// （駒ごとに乱数で変えると再描画のたびに柄が揺れて見えるため、決定的な形に留める）。
struct KomaGrainShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        for (i, x) in [0.34, 0.52, 0.68].enumerated() {
            // 中央の1本だけ逆へ曲げ、平行線に見えないようにする。
            let bend = (i == 1 ? 0.07 : -0.05) * w
            p.move(to: CGPoint(x: w * x, y: h * 0.16))
            p.addQuadCurve(
                to: CGPoint(x: w * x, y: h * 0.92),
                control: CGPoint(x: w * x + bend, y: h * 0.55)
            )
        }
        return p
    }
}

/// 将棋の駒形（五角形）。上が尖り、下が平ら。
///
/// 会長フィードバック（#366）: 尖りすぎ → 実物の駒と同じく**天（てっぺん）に短い平らな辺**を
/// 持たせ、肩も少し上げて先端の角度を鈍くした。
struct KomaShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let shoulder = h * 0.30
        var p = Path()
        p.move(to: CGPoint(x: w * 0.455, y: h * 0.045))
        p.addLine(to: CGPoint(x: w * 0.545, y: h * 0.045))
        p.addLine(to: CGPoint(x: w * 0.845, y: shoulder))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.96))
        p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.96))
        p.addLine(to: CGPoint(x: w * 0.155, y: shoulder))
        p.closeSubpath()
        return p
    }
}

/// 面と側面の境目（駒の底辺）。エッジを1本立てて五角柱の稜線に見せる（#366）。
struct KomaBaseEdgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.10, y: h * 0.96))
        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.96))
        return p
    }
}

// MARK: - 持ち駒エリア（独立 View で再描画スコープを分離）

/// 持ち駒の表示・打ち駒選択。ShogiView.body から切り出すことで、
/// isThinking など持ち駒に無関係なプロパティ変化では再描画されない。
private struct HandAreaView: View {
    let model: ShogiGameModel
    let color: Side

    var body: some View {
        let pos     = model.displayedPosition
        let hand    = pos.hands[color.rawValue]
        let owned   = PieceType.allCases.filter { $0.isDroppable && hand[$0.rawValue] > 0 }
        let isYou   = color == model.humanSide

        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isYou ? "あなた" : "CPU")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isYou ? Theme.teal : Theme.inkSub)
                Text(color == .black ? "☗" : "☖")
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSub)
            }
            .frame(width: 38, alignment: .leading)

            // ZStack で空/持ち駒あり共通サイズを確保し高さ変化によるガタつきを防ぐ
            ZStack(alignment: .leading) {
                if owned.isEmpty {
                    Text("持ち駒なし")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                } else {
                    HStack(spacing: 6) {
                        ForEach(owned, id: \.rawValue) { type in
                            let selected = model.selectedHand == type && color == pos.sideToMove
                            let count    = hand[type.rawValue]
                            Button { model.tapHand(type, color: color) } label: {
                                VStack(spacing: 2) {
                                    KomaView(piece: Piece(type: type, color: color),
                                             size: 32, pointsUp: isYou)
                                        .padding(.horizontal, 5).padding(.vertical, 3)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(selected ? Theme.yellow : BoardStyle.komaWoodLight)
                                        )
                                    Text("×\(count)")
                                        .font(.system(size: 10, weight: .black, design: .rounded))
                                        .foregroundStyle(selected ? Theme.coral : Theme.inkSub)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(ShogiAccessibility.handLabel(
                                type: type, color: color, count: count, isSelected: selected
                            ))
                        }
                    }
                    .drawingGroup() // 駒形状・グラデーションを Metal で一括描画
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        // 縦の余白は 4。終局後に出るもののぶんの高さを確保しても盤が小さくならないよう、
        // 駒の大きさ（＝タップ目標）は変えずに余白から捻出している（#139）。
        .padding(.horizontal, 12).padding(.vertical, 4)
        .popCard(corner: Theme.cornerSmall)
    }
}

/// 駒の漢字表記。
enum Glyph {
    static func kanji(for p: Piece) -> String {
        if p.promoted {
            switch p.type {
            case .pawn: return "と"
            case .lance: return "杏"
            case .knight: return "圭"
            case .silver: return "全"
            case .bishop: return "馬"
            case .rook: return "龍"
            default: break
            }
        }
        switch p.type {
        case .pawn: return "歩"
        case .lance: return "香"
        case .knight: return "桂"
        case .silver: return "銀"
        case .gold: return "金"
        case .bishop: return "角"
        case .rook: return "飛"
        case .king: return p.color == .black ? "玉" : "王"
        }
    }
}
