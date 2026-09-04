import SwiftUI
import Core

/// チェスの対局画面（CPU 対戦）。人間の手番側を常に手前に表示する。
public struct ChessView: View {
    @State private var model: ChessGameModel
    private let services: GameServices
    @State private var showNewGame: Bool
    @State private var showConfirmNewGame = false
    @State private var showUndoConfirm = false
    @State private var showResignConfirm = false
    @State private var showRewardNotEarned = false
    /// 盤上の駒に「移動しても変わらない ID」を与えるための対応付け（将棋 #200 と同じ）。
    @State private var pieceLayout: ChessPieceLayout
    /// 表示中の「チェック」の合図の契機 ID。nil なら出していない。
    @State private var checkBannerID: Int?
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        self.services = services
        let model = ChessGameModel(services: services)
        _model = State(initialValue: model)
        _pieceLayout = State(initialValue: ChessPieceLayout(model.displayedPosition))
        var showSheet = !services.snapshots.exists(for: "chess")
        #if DEBUG
        // 撮影用: 開始シートを飛ばして初期局面を撮る。
        if ProcessInfo.processInfo.arguments.contains("-chessSkipStartSheet") { showSheet = false }
        #endif
        _showNewGame = State(initialValue: showSheet)
    }

    /// 人間が黒なら盤を反転して表示する。
    private var flipped: Bool { model.humanSide == .black }

    public var body: some View {
        // 縦の構成・余白は将棋と揃える。対局中と終局後で高さが変わらない `controlArea` を
        // 置くことで、決着の瞬間に盤が縮まない（#139 の契約）。
        VStack(spacing: 4) {
            statusBar
            CapturedAreaView(model: model, owner: model.humanSide.opponent)
            board
                .layoutPriority(1)
            CapturedAreaView(model: model, owner: model.humanSide)
            HowToPlayHint(.chess, playLog: services.playLog)
            controlArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.none, value: model.gameOver)
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
                Text("チェス")
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
        .howToPlay(.chess) {
            ChessRuleDetail()
        }
        .sheet(isPresented: $showNewGame) {
            ChessNewGameSheet(initialSide: model.humanSide, initialLevel: model.aiLevel) { side, level in
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
        .overlay { checkOverlay }
        .overlay { promotionOverlay }
        .task(id: model.aiTurnKey) {
            await model.performAIMoveIfNeeded()
        }
        .task {
            #if DEBUG
            // 撮影用: 終局後レイアウト（検討ナビ・レコメンドのオーバーレイ）を即再現する。
            if ProcessInfo.processInfo.arguments.contains("-chessAutoResign") { model.resign() }
            // 撮影用: 成り先の選択札を出した状態を再現する。シミュレータは自動タップできないので、
            // 中断データの注入だけでは出せない画面（`pendingPromotion` は永続化しない）をここで作る。
            if ProcessInfo.processInfo.arguments.contains("-chessAutoPromotion"),
               let promotion = model.legalMovesCache.first(where: { $0.promotion != nil }) {
                model.tapSquare(promotion.from)
                model.tapSquare(promotion.to)
            }
            #endif
        }
        // チェックが掛かった瞬間だけ文字を出し、少し置いて引っ込める。
        .task(id: model.checkEventID) {
            guard model.checkEventID > 0 else { return }
            checkBannerID = model.checkEventID
            try? await Task.sleep(for: .seconds(ChessMotion.checkBannerHold))
            checkBannerID = nil
        }
        // 人間の着手・CPU の着手・待った・検討ナビのどれで局面が変わっても、
        // 経路を問わずここ 1 か所で駒の対応付けを進める（#200）。
        .onChange(of: model.displayedPosition) { _, position in
            pieceLayout.update(to: position)
        }
    }

    /// 「チェック」の合図。キングの赤枠が「いま王手されている」を常時示すのに対し、
    /// こちらは**王手が掛かった瞬間**だけ飛び出して消える。
    ///
    /// 分岐は**この層の中**に置く。呼び出し側の `.overlay { if … }` にすると、
    /// 出入りする枝と一緒に修飾子まで消えて `.transition` が効かない（将棋 #201/#195）。
    private var checkOverlay: some View {
        ZStack {
            if checkBannerID != nil {
                Text("チェック")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Capsule().fill(ChessBoardStyle.check))
                    .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        // 読み上げは盤のマス（`isCheckedKing`）に持たせてある。1 秒あまりで消える要素を
        // ここで読ませると、VoiceOver のフォーカスが消える要素に乗る。
        .accessibilityHidden(true)
        .gameAnimation(ChessMotion.checkBanner, value: checkBannerID)
    }

    /// プロモーション先を選ぶ札。出入りのアニメーションは**残り続ける親**（この `ZStack`）に置く。
    private var promotionOverlay: some View {
        ZStack {
            if model.pendingPromotion != nil {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { model.cancelPromotion() }
                VStack(spacing: 18) {
                    Text("何に成りますか？")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 12) {
                        // クイーンを先頭に置く。実戦のほぼ全てがクイーン成りなので、
                        // 駒種の定義順（ナイト → クイーン）のままだと一番使う選択肢が端に来る。
                        ForEach(ChessGameModel.promotionChoices, id: \.rawValue) { type in
                            Button { model.resolvePromotion(type) } label: {
                                VStack(spacing: 4) {
                                    ChessPieceView(
                                        piece: ChessPiece(type: type, color: model.humanSide),
                                        size: 44
                                    )
                                    Text(type.japaneseName)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.inkSub)
                                }
                                .frame(width: 66, height: 76)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(type.japaneseName)に成る")
                        }
                    }
                    Button("やめる") { model.cancelPromotion() }
                        .themeBody(14)
                        .foregroundStyle(Theme.inkSub)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        // 札を出していない間、この層は盤の上に常設される（分岐を中に入れたぶん）。
        // 触れないことを明示しておく — 空の `ZStack` は素通しだが、暗黙に頼ると
        // 中身を足したときに静かに盤のタップを塞ぐ。
        .allowsHitTesting(model.pendingPromotion != nil)
        .gameAnimation(ChessMotion.promotionPrompt, value: model.pendingPromotion != nil)
    }

    // MARK: - 盤

    private var board: some View {
        let pos = model.displayedPosition
        // 64 マスの読み上げ文それぞれから引くので、ここで 1 回だけ求める。
        let checkedKing = model.checkedKingSquare
        return GeometryReader { geo in
            let cell = (geo.size.width - 8) / 8
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { col in
                            let idx = squareIndex(row: row, col: col)
                            ChessCell(
                                size: cell,
                                isLight: ChessSquare.isLightSquare(idx),
                                isSelected: model.selectedSquare == idx,
                                isLastMove: model.highlightedSquares.contains(idx)
                            )
                            .onTapGesture { model.tapSquare(idx) }
                            // 盤は 64 個の図形の集まりでしかないため、マスごとに読み上げ要素を作る。
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(ChessAccessibility.squareLabel(
                                index: idx,
                                piece: pos.squares[idx],
                                isSelected: model.selectedSquare == idx,
                                isTarget: model.legalTargets.contains(idx),
                                isLastMove: model.highlightedSquares.contains(idx),
                                isCheckedKing: checkedKing == idx
                            ))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { model.tapSquare(idx) }
                        }
                    }
                }
            }
            // 駒はマスの中ではなく盤全体を覆う 1 枚の層に置く（#200）。
            .overlay { pieceLayer(cell: cell) }
            // 王手されているキングの印も駒より**上**。キングそのものを囲むので、下に潜ると見えない。
            .overlay { checkLayer(cell: cell) }
            // 着手先の印も駒より**上**（取れる駒に重ねる枠が駒の下に潜ると読めなくなる）。
            .overlay { targetLayer(cell: cell) }
            .overlay { coordinateLayer(cell: cell) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(LinearGradient(
                        colors: [ChessBoardStyle.frameTop, ChessBoardStyle.frameBottom],
                        startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
            )
        }
        .aspectRatio(1, contentMode: .fit)
        // 終局後のレコメンドは盤の下端に重ねる（将棋と同じ。高さの予約をせずに済ませる）。
        .overlay(alignment: .bottom) {
            if model.gameOver {
                RecommendationSlot(services: services, isFinished: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
    }

    /// 画面 (row,col) → 内部マス。人間が白なら白視点、黒なら反転。
    private func squareIndex(row: Int, col: Int) -> Int {
        ChessSquare.boardIndex(row: row, col: col, flipped: flipped)
    }

    /// 盤の上に重ねる駒の層。ここだけが駒を描き、マスの側は描かない（#200）。
    private func pieceLayer(cell: CGFloat) -> some View {
        GeometryReader { geo in
            let slot = geo.size.width / 8
            ZStack(alignment: .topLeading) {
                ForEach(pieceLayout.placements) { placement in
                    let spot = ChessSquare.displayPosition(of: placement.square, flipped: flipped)
                    ChessPieceView(piece: placement.piece, size: cell)
                        // `.transition` は `.position` より前に置く。あとに置くと拡大・縮小の
                        // 基準がマスではなく盤の原点になり、消える駒が左上へ吸い込まれる。
                        .transition(.opacity)
                        .position(x: slot * (CGFloat(spot.col) + 0.5),
                                  y: slot * (CGFloat(spot.row) + 0.5))
                }
            }
            // アニメーションの指定は**この 1 か所だけ**にする。入れ子にすると内側が
            // 外側のトランザクションを打ち消し、片方の演出が静かに効かなくなる。
            .gameAnimation(ChessMotion.pieceMove, value: pieceLayout)
        }
        // 当たり判定と読み上げはマス（`ChessCell` 側）が持ち続ける。
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 王手されているキングのマスの印。駒の層より上に重ねる。
    private func checkLayer(cell: CGFloat) -> some View {
        GeometryReader { geo in
            let slot = geo.size.width / 8
            ZStack(alignment: .topLeading) {
                if let square = model.checkedKingSquare {
                    let spot = ChessSquare.displayPosition(of: square, flipped: flipped)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ChessBoardStyle.check, lineWidth: 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(ChessBoardStyle.check.opacity(0.22)))
                        .frame(width: cell - 4, height: cell - 4)
                        .position(x: slot * (CGFloat(spot.col) + 0.5),
                                  y: slot * (CGFloat(spot.row) + 0.5))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 着手先の印。アニメーションは付けない — 選択の反映は即時にする。
    private func targetLayer(cell: CGFloat) -> some View {
        GeometryReader { geo in
            let slot = geo.size.width / 8
            let pos = model.displayedPosition
            ZStack(alignment: .topLeading) {
                ForEach(model.legalTargets.sorted(), id: \.self) { square in
                    let spot = ChessSquare.displayPosition(of: square, flipped: flipped)
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

    /// 筋（a〜h）と段（1〜8）の目印。棋譜表記と盤を突き合わせられるようにする。
    /// マスの色に応じて**反対色**で描くので、明暗どちらのマスに載っても読める。
    private func coordinateLayer(cell: CGFloat) -> some View {
        GeometryReader { geo in
            let slot = geo.size.width / 8
            ZStack(alignment: .topLeading) {
                ForEach(0..<8, id: \.self) { i in
                    // 段は左端の列、筋は下端の行に置く。
                    let rankSquare = squareIndex(row: i, col: 0)
                    let fileSquare = squareIndex(row: 7, col: i)
                    Text(ChessSquare.name(rankSquare).suffix(1))
                        .font(.system(size: max(7, cell * 0.20), weight: .bold, design: .rounded))
                        .foregroundStyle(ChessBoardStyle.coordinate(onLight: ChessSquare.isLightSquare(rankSquare)))
                        .position(x: slot * 0.18, y: slot * (CGFloat(i) + 0.18))
                    Text(ChessSquare.name(fileSquare).prefix(1))
                        .font(.system(size: max(7, cell * 0.20), weight: .bold, design: .rounded))
                        .foregroundStyle(ChessBoardStyle.coordinate(onLight: ChessSquare.isLightSquare(fileSquare)))
                        .position(x: slot * (CGFloat(i) + 0.84), y: slot * 7.84)
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
                Text(model.position.sideToMove == .white ? "白番" : "黒番")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    // 面色が白番＝差し色 / 黒番＝濃色と大きく違うので、文字色も面に合わせる（#220）。
                    .foregroundStyle(model.position.sideToMove == .white ? Theme.onAccent : .white)
                    .padding(.horizontal, 12).padding(.vertical, 2)
                    .background(Capsule().fill(
                        model.position.sideToMove == .white ? Theme.Fill.teal : Theme.fillStrong))
                    .gameAnimation(ChessMotion.turnChange, value: model.position.sideToMove)
                if model.isThinking {
                    ProgressView().controlSize(.small)
                    Text("CPU思考中…").themeBody(13).foregroundStyle(Theme.inkSub)
                } else if let last = model.highlightedMoveText {
                    Text("直前 \(last)").themeBody(14).foregroundStyle(Theme.ink)
                }
            }
            Spacer(minLength: 8)
            if model.gameOver {
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

    // MARK: - 盤の下の操作エリア

    /// 対局中（投了・待った）と終局後（検討ナビ・もう一度）で中身が入れ替わるが、
    /// どちらも**同じ余白の1行**なので高さは変わらない（#139 の「決着で盤が縮まない」契約）。
    private var controlArea: some View {
        ZStack(alignment: .top) {
            if model.gameOver {
                reviewControls
            } else {
                gameControls
            }
        }
    }

    private var gameControls: some View {
        HStack(spacing: 12) {
            Button { showResignConfirm = true } label: {
                Label("投了", systemImage: "flag.fill")
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Fill.coral))
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
                            // 視聴完了（報酬獲得）したときだけ待ったを許可する。
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
        .padding(.horizontal, 16).padding(.vertical, 5)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 検討ナビと「もう一度」は 1 段にまとめ、対局中の `gameControls` と同じ高さに収める（#139）。
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
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Fill.coral))
            }
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 5)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - 取られた駒の帯

/// 取られた駒の表示。将棋の持ち駒エリアと同じ位置・同じ高さに置く。
/// チェスでは取った駒を打てないので**選べない**（表示だけ）。
private struct CapturedAreaView: View {
    let model: ChessGameModel
    /// この帯が「失った駒」を並べる側。
    let owner: ChessColor
    /// 画面の広さ（#458）。盤は幅から作られるので勝手に広がるが、ここは固定 pt なので
    /// 一緒に拡大しないと iPad で盤との比率が崩れる。
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        let lost = model.capturedPieces(of: owner)
        let isYou = owner == model.humanSide

        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isYou ? "あなた" : "CPU")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isYou ? Theme.teal : Theme.inkSub)
                Text(owner.name)
                    .font(.system(size: 12)).foregroundStyle(Theme.inkSub)
            }
            .frame(width: 38, alignment: .leading)

            // ZStack で「取られていない / 取られた」を共通の高さに収め、ガタつきを防ぐ。
            ZStack(alignment: .leading) {
                if lost.isEmpty {
                    Text("取られた駒なし")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                } else {
                    // **少し重ねて並べる**。取られた駒は片側で最大 15 枚まで増えるので、
                    // 間隔を空けて並べると帯からはみ出す（15 × 22.9pt ≒ 344pt に対し、
                    // ラベルと余白を引いた帯の内寸は iPhone で約 310pt しかない）。
                    // 重ねる幅は駒の見た目の余白ぶんに留め、形が読めなくならないようにする。
                    HStack(spacing: -layout.scaled(4)) {
                        ForEach(Array(lost.enumerated()), id: \.offset) { _, type in
                            ChessPieceView(piece: ChessPiece(type: type, color: owner),
                                           size: layout.scaled(26))
                        }
                    }
                    .drawingGroup() // 図形とグラデーションを Metal で一括描画
                }
            }
            .frame(maxWidth: .infinity, minHeight: layout.scaled(40), alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ChessAccessibility.capturedLabel(owner: owner, lost: lost))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12).padding(.vertical, 2)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - 新規対局シート

/// 先後・難易度を大きなボタンで選ぶ。
struct ChessNewGameSheet: View {
    @State private var side: ChessColor
    @State private var level: Int
    let onStart: (ChessColor, Int) -> Void
    let onCancel: () -> Void

    init(initialSide: ChessColor, initialLevel: Int,
         onStart: @escaping (ChessColor, Int) -> Void, onCancel: @escaping () -> Void) {
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
                        chooser(title: "白", subtitle: "先に指す", selected: side == .white,
                                accent: Theme.Fill.teal) { side = .white }
                        chooser(title: "黒", subtitle: "後に指す", selected: side == .black,
                                accent: Theme.fillStrong, onAccent: .white) { side = .black }
                    }
                }
                section("CPUの強さ") {
                    HStack(spacing: 12) {
                        // 副題は探索の中身と一致させる（#416）。詳細は `SimpleChessEngine.init(level:)`。
                        chooser(title: "弱", subtitle: "駒の損得だけ", selected: level == 0,
                                accent: Theme.Fill.teal) { level = 0 }
                        chooser(title: "普通", subtitle: "駒の働きも見る", selected: level == 1,
                                accent: Theme.Fill.yellow) { level = 1 }
                        chooser(title: "強", subtitle: "定跡＋深読み", selected: level == 2,
                                accent: Theme.Fill.coral) { level = 2 }
                    }
                }
                Spacer()
                Button { onStart(side, level) } label: {
                    Text("対局開始").themeBody(18).frame(maxWidth: .infinity)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
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

    /// - Parameter onAccent: 選択中（＝面が `accent` で塗られている状態）の文字色。
    ///   差し色の面には `Theme.onAccent`、`fillStrong` のような濃い面には白を渡す（#220）。
    private func chooser(title: String, subtitle: String, selected: Bool, accent: Color,
                         onAccent: Color = Theme.onAccent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).themeTitle(22).foregroundStyle(selected ? onAccent : Theme.ink)
                Text(subtitle).font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? onAccent : Theme.inkSub)
                    .lineLimit(1).minimumScaleFactor(0.7)
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

// MARK: - くわしいルール

/// 「遊び方」シートの下に足す駒の動き・特別ルールの説明。
/// ミニガイドは 3 行までという決まり（`HowToPlayGuide`）なので、初心者に必要な残りはここに置く。
struct ChessRuleDetail: View {
    private let pieces: [(ChessPieceType, String)] = [
        (.king, "たて・よこ・ななめに1マス。取られたら負け"),
        (.queen, "たて・よこ・ななめに何マスでも"),
        (.rook, "たて・よこに何マスでも"),
        (.bishop, "ななめに何マスでも"),
        (.knight, "L字（2+1マス）。駒を飛び越えられる"),
        (.pawn, "前へ1マス（最初だけ2マス）。取るときだけ斜め前"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("駒の動き").themeBody(16).foregroundStyle(Theme.ink)
                ForEach(pieces, id: \.0.rawValue) { type, movement in
                    HStack(alignment: .center, spacing: 10) {
                        ChessPieceView(piece: ChessPiece(type: type, color: .white), size: 30)
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(type.japaneseName)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            Text(movement)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Theme.inkSub)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("特別なルール").themeBody(16).foregroundStyle(Theme.ink)
                ruleLine("プロモーション", "ポーンが一番奥に届くと、好きな駒（普通はクイーン）に変われます。")
                ruleLine("キャスリング", "キングとルークがまだ動いていなければ、キングを2マス動かして入れ替われます。")
                ruleLine("アンパッサン", "相手のポーンが2マス進んで真横に並んだ直後だけ、通り過ぎたマスへ斜めに取れます。")
                ruleLine("ステイルメイト", "王手されていないのに動かせる駒が1つも無いと、引き分けです。")
            }
        }
    }

    private func ruleLine(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(body).font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.inkSub)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 演出の長さ

/// チェスの演出の長さ。Reduce Motion への追従は `gameAnimation(_:value:)` 側が持つ（#210）。
///
/// 長さは秒の定数として持ち、`Animation` はそこから組む。`Animation` からは長さを読み出せないため、
/// 定数を経由しないと**長さの大小関係をテストで固定できない**。
enum ChessMotion {
    /// 駒の移動にかかる時間の目安（バネの `response`）。
    static let pieceMoveResponse: TimeInterval = 0.26
    /// プロモーション選択の札の出入り。`pieceMoveResponse` より短くする。
    static let promotionPromptDuration: TimeInterval = 0.18
    /// 手番バッジの色替え。
    static let turnChangeDuration: TimeInterval = 0.2
    /// 「チェック」の合図が飛び出す・引っ込むのにかかる時間（バネの `response`）。
    static let checkBannerResponse: TimeInterval = 0.24
    /// 「チェック」の合図を出しておく時間。**駒の移動より長く取る**。
    /// ここが短いと、王手を掛けた駒がまだ動いている最中に文字が消えて何が起きたか読めない。
    static let checkBannerHold: TimeInterval = 1.1

    /// 駒の移動。跳ね返り（`dampingFraction` < 1）は駒がマスから外れて見えるため、ほぼ入れない。
    static let pieceMove: Animation = .spring(response: pieceMoveResponse, dampingFraction: 0.9)
    /// プロモーション選択の札の出入り。**駒の移動より短く取る**。
    static let promotionPrompt: Animation = .easeOut(duration: promotionPromptDuration)
    /// 手番バッジの色替え。
    static let turnChange: Animation = .easeInOut(duration: turnChangeDuration)
    /// 「チェック」の合図の出入り。危急を伝えるので少し跳ねさせる。
    static let checkBanner: Animation = .spring(response: checkBannerResponse, dampingFraction: 0.65)
}

// MARK: - 盤の配色

/// 盤と駒の配色。あそびばの温かいアンバー系に寄せた明暗 2 色にする。
enum ChessBoardStyle {
    /// 盤枠（上→下のグラデーション）。
    static let frameTop = Color(hex: 0xE0B87C)
    static let frameBottom = Color(hex: 0xB98A50)
    /// 明るいマス・暗いマス。
    static let lightSquare = Color(hex: 0xF2DFBB)
    static let darkSquare = Color(hex: 0xB2884F)

    /// 白駒。明るいマスに載っても沈まないよう、濃い輪郭で締める。
    static let whitePieceTop = Color(hex: 0xFEFAF0)
    static let whitePieceBottom = Color(hex: 0xE4D3B2)
    static let whitePieceLine = Color(hex: 0x4A3524)
    /// 黒駒。暗いマスに載っても輪郭が読めるよう、**明るい線**で縁取る。
    static let blackPieceTop = Color(hex: 0x50443A)
    static let blackPieceBottom = Color(hex: 0x22190F)
    static let blackPieceLine = Color(hex: 0xEFE2C6)

    /// 王手の合図。キングのマスの枠と「チェック」の札に使う。
    ///
    /// 差し色（`Theme.coral` など）は**白文字を載せると WCAG AA 未達**で #220 の対象に
    /// なっているため、ここでは使わない。この緋色は白文字との対比が 6.5:1 あり、
    /// 盤の明暗どちらのマスに対しても十分に沈んで見える（将棋 `BoardStyle.check` と同じ値）。
    ///
    /// `Color` は生成後に成分を取り出せないため、コントラストを検証するテストが参照できるよう
    /// 数値のまま持つ。
    static let checkHex: UInt32 = 0xB3261E
    static let check = Color(hex: checkHex)

    /// マスに直接書く座標の文字色。**マスの反対色**で描くので明暗どちらでも読める。
    static func coordinate(onLight: Bool) -> Color {
        onLight ? Color(hex: 0x8A6A3C) : Color(hex: 0xF2DFBB).opacity(0.85)
    }
}

// MARK: - 1 マス

/// 1 マス。マスの色とハイライトだけを描く。
/// 駒と着手先の印は描かない（#200）— 移動を補間するため、駒は盤全体を覆う 1 枚の層が受け持つ。
struct ChessCell: View {
    let size: CGFloat
    let isLight: Bool
    let isSelected: Bool
    let isLastMove: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(isLight ? ChessBoardStyle.lightSquare : ChessBoardStyle.darkSquare)
            if isLastMove {
                Rectangle().fill(Theme.coral.opacity(0.26)) // 直前手のマス
            }
            if isSelected {
                Rectangle().fill(Theme.yellow.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
    }
}
