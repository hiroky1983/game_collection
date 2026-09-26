import SwiftUI
import Core

/// 将棋の対局画面（CPU 対戦）。人間の手番側を常に手前に表示する。
public struct ShogiView: View {
    @State private var model: ShogiGameModel
    private let services: GameServices
    @State private var showNewGame: Bool
    @State private var showConfirmNewGame = false
    /// 「待った」のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var undoRescue = RewardedRescue()
    /// 盤上の駒に「移動しても変わらない ID」を与えるための対応付け（#200）。
    /// 表示局面が変わるたびに更新し、駒の層はこれだけを見て描く。
    @State private var pieceLayout: ShogiPieceLayout
    /// 表示中の「王手」の合図の契機 ID（#377）。nil なら出していない。
    /// モデルの `checkEventID` をそのまま入れ、一定時間後に nil へ戻す。
    @State private var checkBannerID: Int?

    public init(services: GameServices) {
        self.services = services
        let model = ShogiGameModel(services: services)
        _model = State(initialValue: model)
        _pieceLayout = State(initialValue: ShogiPieceLayout(model.displayedPosition))
        var showSheet = !services.snapshots.exists(for: "shogi")
        #if DEBUG
        // 撮影用（#366系）: 開始シートを飛ばして初期局面を撮る。
        if ProcessInfo.processInfo.arguments.contains("-shogiSkipStartSheet") { showSheet = false }
        #endif
        _showNewGame = State(initialValue: showSheet)
    }

    /// 人間が後手なら盤を反転して表示する。
    private var flipped: Bool { model.humanSide == .white }

    public var body: some View {
        // 縦の余白は 5。対局中と終局後で高さが変わらない `controlArea` を置くぶん、
        // 盤に回せる高さを間隔から捻出している（#139）。盤の横幅をカード類と同じ内寸まで
        // 届かせるため、間隔・各カードの縦余白から高さを捻出している（会長指示 2026-09-01）。
        VStack(spacing: 4) {
            statusBar
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
        .padding(Theme.pad)
        .gameChrome(title: "将棋", review: services.review,
                    newGame: GameChromeNewGame(.match) {
                        if model.phase == .playing && !model.moves.isEmpty {
                            showConfirmNewGame = true
                        } else {
                            showNewGame = true
                        }
                    })
        .howToPlay(.shogi)
        .sheet(isPresented: $showNewGame, onDismiss: { model.startPlayIfPending() }) {
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
        .overlay { checkOverlay }
        .overlay { promotionOverlay }
        .task(id: model.aiTurnKey) {
            await model.performAIMoveIfNeeded()
        }
        .task {
            #if DEBUG
            // 撮影用: 終局後レイアウト（検討ナビ・レコメンドのオーバーレイ）を即再現する。
            if ProcessInfo.processInfo.arguments.contains("-shogiAutoResign") { model.resign() }
            #endif
        }
        // 王手が掛かった瞬間だけ文字を出し、少し置いて引っ込める（#377）。
        //
        // 引っ込めるのは**自分が出した合図がまだ出ているときだけ**にする。`.task(id:)` は
        // 契機が変わると古いタスクを取り消すが、`Task.sleep` の `CancellationError` は
        // `try?` が飲み込むので、古いタスクはそのまま最後の行まで走る。素朴に nil を書くと、
        // 続けて王手が掛かったときに**古い後始末が新しい合図を消す**（チェス側で先に判明。#519）。
        .task(id: model.checkEventID) {
            let id = model.checkEventID
            guard id > 0 else { return }
            checkBannerID = id
            try? await Task.sleep(for: .seconds(ShogiMotion.checkBannerHold))
            if checkBannerID == id { checkBannerID = nil }
        }
        // 待った・新規対局・投了で盤の意味が変わったら、上の固定待ちを待たずに札を畳む（#519）。
        // `checkEventID` は着手でしか増えないので、局面を戻しても上の `.task` は走り直さず、
        // 王手でない盤の上に最大 1.1 秒ぶん札が残っていた。
        .onChange(of: model.checkBannerDismissID) { _, _ in
            checkBannerID = nil
        }
        // 人間の着手・CPU の着手・待った・検討ナビのどれで局面が変わっても、
        // 経路を問わずここ 1 か所で駒の対応付けを進める（#200）。
        .onChange(of: model.displayedPosition) { _, position in
            pieceLayout.update(to: position)
        }
    }

    /// 「王手」の合図（#377）。玉の赤枠が「いま王手されている」を常時示すのに対し、
    /// こちらは**王手が掛かった瞬間**だけ飛び出して消える。
    ///
    /// 成り確認の札（#201）と同じく、分岐は**この層の中**に置く。呼び出し側の
    /// `.overlay { if … }` にすると、出入りする枝と一緒に修飾子まで消えて `.transition` が効かない。
    private var checkOverlay: some View {
        ZStack {
            if checkBannerID != nil {
                BoardGameCheckBanner("王手")
                    // 札は中央にあり `offset` を持たないので、拡大の基準は札の中心になる。
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        // 読み上げは盤のマス（`ShogiCell` の `isCheckedKing`）に持たせてある。1 秒あまりで
        // 消える要素をここで読ませると、VoiceOver のフォーカスが消える要素に乗る。
        .accessibilityHidden(true)
        .gameAnimation(ShogiMotion.checkBanner, value: checkBannerID)
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
                    .onTapGesture { model.cancelPromotion() }
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
                                .background(Theme.Fill.coral, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Theme.onAccent)
                        }
                    }
                    Button("やめる") { model.cancelPromotion() }
                        .themeBody(14)
                        .foregroundStyle(Theme.inkSub)
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
        // 81 マスの読み上げ文それぞれから引くので、ここで 1 回だけ求める。
        // `checkedKingSquare` は表示局面を組み直す（検討中は指し手の全再生）ため、
        // ループの中で呼ぶと 1 回の描画で 81 回それをやることになる。
        let checkedKing = model.checkedKingSquare
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
                                isLastMove: model.highlightedSquares.contains(idx),
                                isCheckedKing: checkedKing == idx,
                                isHint: model.hintSquares.contains(idx)
                            ))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { model.tapSquare(idx) }
                        }
                    }
                }
            }
            // 盤の木地（#366）: 無地アンバーの縦グラデーション + 格子線と星。
            // 木目テクスチャも試したが会長レビューで無地が採用になった（コンペ経緯は #366）。
            .background {
                boardGrid
                    .background(
                        LinearGradient(
                            colors: [BoardStyle.frameTop, BoardStyle.frameBottom],
                            startPoint: .top, endPoint: .bottom)
                    )
            }
            // 角丸 → 駒 → 王手 → 着手先 の重なり順はチェスと共通（#530）。
            // 順番そのものが不具合の有無を決めるため、理由ごと `boardLayers` に置いてある。
            .boardLayers(
                corner: Theme.cornerSmall,
                pieces: { pieceLayer(cell: cell) },
                check: { checkLayer(cell: cell) },
                targets: { targetLayer(cell: cell) }
            )
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
        // 終局後のレコメンドは盤の下端に重ねる（#139 の高さ予約の代替。会長指示 2026-09-01:
        // 予約をやめて盤の横幅をカード類と同じ内寸まで届かせる）。×で閉じられ、
        // 検討ナビで盤を見たいときに邪魔なら閉じればよい。
        .overlay(alignment: .bottom) {
            if model.gameOver {
                RecommendationSlot(services: services, isFinished: true, ladder: ladder)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
    }

    /// 勝ちが続いたら一段上の強さを勧める（#722）。並びは開始シートの「CPUの強さ」と同じ。
    private var ladder: DifficultyLadderPrompt? {
        DifficultyLadderPrompt(result: model.recordResult,
                               currentLevel: CPUStrength.ladderIndex(forLevel: model.aiLevel),
                               levelLabels: CPUStrength.labels) { index in
            model.newGame(humanSide: model.humanSide,
                          aiLevel: CPUStrength.level(atLadderIndex: index))
        }
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
                    // 選択した駒は少し持ち上げる（拡大 + 浮かせ + 落ち影）。
                    // 「浮いている」ことは駒の下に落ちる影で伝わるので、影を先に描く。
                    let isLifted = model.selectedSquare == placement.square
                    KomaView(piece: placement.piece, size: cell,
                             pointsUp: placement.piece.color == model.humanSide)
                        // 拡大 + 浮かせ + 落ち影はチェスと共通（#530）。
                        .pieceLift(isLifted: isLifted, cell: cell)
                        // 持ち上げのアニメーションは**駒単位**でここに置く（層全体に置くと、
                        // 着手確定で配置と選択が同時に変わったとき pieceMove 側の指定に
                        // 上書きされて、戻りの速さが意図とずれる — verifier 検証 2026-09-06）。
                        // この指定より下（scale/shadow/offset）だけに効き、`.position` は層の
                        // pieceMove が受け持つ。
                        .gameAnimation(ShogiMotion.pieceLift, value: isLifted)
                        // `.transition` は `.position` より前に置く。あとに置くと拡大・縮小の
                        // 基準がマスではなく盤の原点になり、消える駒が左上へ吸い込まれる。
                        .transition(.opacity)
                        .position(x: slot * (CGFloat(spot.col) + 0.5),
                                  y: slot * (CGFloat(spot.row) + 0.5))
                }
            }
            // 駒の移動（`.position`）のアニメーションは**この層に 1 つだけ**置く。
            // 同じ値を監視する指定を入れ子にすると内側が外側を打ち消して片方が静かに消える。
            // 持ち上げ（別の値 `isLifted` を監視）は上の駒単位の指定が受け持つ。
            .gameAnimation(ShogiMotion.pieceMove, value: pieceLayout)
        }
        // 当たり判定と読み上げはマス（`ShogiCell` 側）が持ち続ける。
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 盤の格子線と星（#366）。木地テクスチャの上に引く。
    /// 星は 3三・3六・6三・6六 の線の交点（実物の盤と同じ位置）。
    private var boardGrid: some View {
        GeometryReader { geo in
            let slot = geo.size.width / 9
            Canvas { ctx, sz in
                let line = GraphicsContext.Shading.color(Color(hex: 0x8B6432).opacity(0.7))
                for i in 0...9 {
                    let p = CGFloat(i) * slot
                    let w: CGFloat = (i == 0 || i == 9) ? 2 : 1
                    var vp = Path()
                    vp.move(to: CGPoint(x: p, y: 0)); vp.addLine(to: CGPoint(x: p, y: sz.height))
                    ctx.stroke(vp, with: line, lineWidth: w)
                    var hp = Path()
                    hp.move(to: CGPoint(x: 0, y: p)); hp.addLine(to: CGPoint(x: sz.width, y: p))
                    ctx.stroke(hp, with: line, lineWidth: w)
                }
                for r in [3, 6] {
                    for c in [3, 6] {
                        let pt = CGPoint(x: slot * CGFloat(c), y: slot * CGFloat(r))
                        let dr: CGFloat = slot * 0.05
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - dr, y: pt.y - dr,
                                                        width: dr * 2, height: dr * 2)),
                                 with: .color(Color(hex: 0x5F4118).opacity(0.85)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 王手されている玉のマスの印（#377）。駒の層より上に重ねる。
    ///
    /// 出す条件は `model.checkedKingSquare`（表示局面から毎回導く）だけなので、検討ナビで
    /// 王手局面へ戻ったときも中断から復元したときも、別の復元処理なしにそのまま正しく出る。
    /// アニメーションは付けない — 王手は「いま起きている事実」であって、遷移の演出は
    /// `checkOverlay` の文字が受け持つ。
    private func checkLayer(cell: CGFloat) -> some View {
        GeometryReader { geo in
            let slot = geo.size.width / 9
            ZStack(alignment: .topLeading) {
                if let square = model.checkedKingSquare {
                    let spot = Sq.displayPosition(of: square, flipped: flipped)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(BoardStyle.check, lineWidth: 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(BoardStyle.check.opacity(0.22)))
                        .frame(width: cell - 4, height: cell - 4)
                        .position(x: slot * (CGFloat(spot.col) + 0.5),
                                  y: slot * (CGFloat(spot.row) + 0.5))
                }
            }
        }
        .allowsHitTesting(false)
        // 読み上げはマス（`ShogiCell` の `isCheckedKing`）が持つ。
        .accessibilityHidden(true)
    }

    /// 着手先の印と、ヒントが示す手の印（#200・#1118）。駒の層より上に重ねる。
    /// アニメーションは付けない — 選択の反映は従来どおり即時にする。
    ///
    /// **ヒントの印もこの層で描く**。共通の重ね順（`boardLayers`・#530）に 4 つ目の層を足したり、
    /// 盤へ自前の `.overlay` を重ねたりすると、将棋だけ共通の順番の外に出る（`PieceLayoutTests`）。
    /// ヒントは着手先の印より後に描くので、両方が出るマスでも紫の枠が読める。
    /// 出す条件は `model.hintSquares` だけで、盤が動けば Model 側が印を落とす。
    /// 色は 3 本共通（`BoardGameHintColor`）。読み上げはマス（`ShogiCell` の `isHint`）が持つ。
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
                ForEach(model.hintSquares.sorted(), id: \.self) { square in
                    let spot = Sq.displayPosition(of: square, flipped: flipped)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(BoardGameHintColor.color, lineWidth: 3)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(BoardGameHintColor.color.opacity(0.22)))
                        .frame(width: cell - 4, height: cell - 4)
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
        GameStatusBar {
            if let result = model.resultText {
                Label(result, systemImage: "flag.checkered")
                    .themeBody(16).foregroundStyle(Theme.coral)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                TurnBadge(isYourTurn: model.position.sideToMove == model.humanSide)
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
        } trailing: {
            if model.gameOver {
                // 終局後の記録は行を増やさずここに同居させる（#139）。手数は検討ナビが
                // 「n/N手」で出しているため、入れ替えても情報は失われない。
                RecordLabel(model.recordResult)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("\(model.moves.count)手").themeBody(13).foregroundStyle(Theme.inkSub)
            }
        }
    }

    // MARK: - 盤の下の操作エリア

    /// 対局中（投了・待った）と終局後（検討ナビ・もう一度）で中身が入れ替わるが、
    /// どちらも**同じ余白の1行**なので高さは変わらない（#139 の「決着で盤が縮まない」契約）。
    ///
    /// かつてはレコメンドカードのぶんまで常時ひな形で高さを予約していたが、その予約（約55pt）が
    /// 盤の幅をカード類より狭くしていた（会長指示 2026-09-01「盤の横幅をカードに揃える」）。
    /// レコメンドは盤の下端へのオーバーレイ（`board` 側の `.overlay`）に移し、予約を撤廃した。
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
        // 待った・「⋯」（投了・ヒント）の並びは盤ゲーム 5 本で共通（#1421）。
        BoardGameControlBar(
            model: model, services: services, rescue: undoRescue, hint: BoardControlBarHint(model, game: model.gameSerial, activity: [model.moves.count, model.selectedSquare ?? -1, model.selectedHand?.hashValue ?? -1]),
            onResign: { model.resign() }
        )
    }

    /// 検討ナビと「もう一度」の帯。実体はチェスと共通の `ReviewNavBar`（#139・#530）。
    private var reviewControls: some View {
        ReviewNavBar(
            ply: model.reviewPly,
            total: model.moves.count,
            onBack: { model.reviewStepBack() },
            onForward: { model.reviewStepForward() },
            onNewGame: { showNewGame = true }
        )
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
        GameSetupSheet(
            kind: .versus,
            onStart: { onStart(side, level) }, onCancel: onCancel
        ) {
            GameSetupSection("あなたの手番") {
                HStack(spacing: 12) {
                    GameSetupChooser(title: "先手", subtitle: "▲ 先に指す", selected: side == .black,
                                     accent: Theme.fillStrong, onAccent: .white) { side = .black }
                    GameSetupChooser(title: "後手", subtitle: "△ 後に指す", selected: side == .white,
                                     accent: Theme.Fill.teal) { side = .white }
                }
            }
            GameSetupSection("CPUの強さ") {
                // 説明は探索の中身と一致させる（#416）。詳細は `SimpleMinimaxEngine.init(level:)`。
                CPUStrengthPicker(level: $level, details: [
                    "手なりで指す", "駒得だけ", "囲いを作る", "定跡＋深読み",
                ])
            }
        }
    }
}

// MARK: - 盤・駒

/// 将棋の演出の長さ（#200・#201）。Reduce Motion への追従は `gameAnimation(_:value:)` 側が持つ。
///
/// 実体は盤ゲーム共通の `BoardGameMotion`（#530）。チェス（`ChessMotion`）とは値も理由も
/// 同じで、片方だけ調整すると盤ゲーム間で手触りがずれるため 1 か所に置いてある。
/// 呼び出し側の読み口は将棋の名前のまま残す（どのゲームの演出を触っているかを見失わないため）。
typealias ShogiMotion = BoardGameMotion

/// 1 マス。マスの色だけを描く。
///
/// 駒と着手先の印は描かない（#200）。移動を補間するため、駒は盤全体を覆う 1 枚の層
/// （`ShogiView.pieceLayer`）が、その上に重ねる印は `ShogiView.targetLayer` が受け持つ。
struct ShogiCell: View {
    let size: CGFloat
    let isSelected: Bool
    let isLastMove: Bool

    var body: some View {
        // 盤の木地は盤全体に敷いたテクスチャ（#366）が担うため、マスは
        // ハイライトだけを描く透明な当たり判定になった。格子線は `boardGrid` が引く。
        ZStack {
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

// MARK: - 持ち駒エリア（独立 View で再描画スコープを分離）

/// 持ち駒の表示・打ち駒選択。ShogiView.body から切り出すことで、
/// isThinking など持ち駒に無関係なプロパティ変化では再描画されない。
private struct HandAreaView: View {
    let model: ShogiGameModel
    let color: Side
    /// 画面の広さ（#458）。盤は幅から作られるので勝手に広がるが、持ち駒だけは固定 pt なので
    /// ここで一緒に拡大しないと iPad で盤との比率が崩れる。
    @Environment(\.adaptiveLayout) private var layout

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
                                             size: layout.scaled(32), pointsUp: isYou)
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
            .frame(maxWidth: .infinity, minHeight: layout.scaled(48), alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        // 縦の余白は 3。終局後に出るもののぶんの高さを確保しても盤が小さくならないよう、
        // 駒の大きさ（＝タップ目標）は変えずに余白から捻出している（#139・会長指示 2026-09-01）。
        .padding(.horizontal, 12).padding(.vertical, 2)
        .popCard(corner: Theme.cornerSmall)
    }
}
