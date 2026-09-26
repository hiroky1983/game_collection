import SwiftUI
import Core

public struct OthelloView: View {
    @State private var model: OthelloModel
    private let services: GameServices
    @State private var showNewGame = false
    @State private var showConfirmNewGame = false
    @State private var showPassAlert = false
    @State private var showResignConfirm = false
    /// 「待った」のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var undoRescue = RewardedRescue()

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: OthelloModel(services: services))
    }

    public var body: some View {
        // 縦の余白は 8。対局中と終局後で高さが変わらない `controlArea` を置くぶん、
        // 盤に回せる高さを間隔から捻出している（#148）。
        VStack(spacing: 8) {
            statusBar
            // 盤は正方形で幅が上限になるため、左右の余白を削って盤そのものを広げる。
            // 縦に残る空きは盤の上下へ均等に振り、下だけが大きく空く見た目をなくす。
            Spacer(minLength: 0)
            board
                .padding(.horizontal, -Theme.pad)
                .layoutPriority(1)
                .overlay {
                    // 勝敗はフェードで出す（#205）。`.gameAnimation` はこの ZStack に置く。
                    // 外側の `.gameAnimation(.none, value: model.gameOver)`（下の VStack）は
                    // 決着時に操作エリアが入れ替わって盤が伸び縮みするのを止めるためのもので、
                    // ここで内側に置き直すことでオーバーレイの出現だけを演出に戻している。
                    // 修飾子は 1 つのビューに 1 つだけ置くこと（入れ子にすると打ち消し合う・#199）。
                    ZStack {
                        if model.gameOver {
                            resultOverlay
                                .transition(.opacity)
                        }
                    }
                    .gameAnimation(
                        .easeOut(duration: OthelloBoardStyle.resultOverlayFadeDuration),
                        value: model.gameOver
                    )
                }
            Spacer(minLength: 0)
            HowToPlayHint(.othello, playLog: services.playLog)
            controlArea
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.none, value: model.gameOver)
        .padding(Theme.pad)
        .gameChrome(title: "オセロ", review: services.review,
                    newGame: GameChromeNewGame(.match) {
                        if model.hasProgressToLose {
                            showConfirmNewGame = true
                        } else {
                            showNewGame = true
                        }
                    })
        .howToPlay(.othello)
        .sheet(isPresented: $showNewGame) {
            OthelloNewGameSheet(humanSide: model.humanSide, aiLevel: model.aiLevel) { side, level in
                model.newGame(humanSide: side, aiLevel: level)
                showNewGame = false
            } onCancel: { showNewGame = false }
        }
        .confirmationDialog("新規対局しますか？", isPresented: $showConfirmNewGame, titleVisibility: .visible) {
            Button("終了して新規対局", role: .destructive) { showNewGame = true }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると対局データが失われます。")
        }
        .alert("パス", isPresented: $showPassAlert) {
            Button("OK") { model.confirmPass() }
        } message: {
            Text("打てるマスがありません。パスします。")
        }
        .boardResignConfirmation(isPresented: $showResignConfirm) { model.resign() }
        // `initial: true` が要る（#414）。パスの案内を閉じる前に中断すると `mustPass = true` のまま
        // 保存され、復元後は値が変化しないので 2 引数版 `onChange` は既定では発火しない。
        // パスの手段はこの案内の「OK」だけなので、出ないと着手も「待った」も塞がったまま詰む。
        .onChange(of: model.mustPass, initial: true) { _, newValue in
            if newValue && !model.isAITurn { showPassAlert = true }
        }
        .task(id: model.aiTurnKey) {
            await model.performAIMoveIfNeeded()
        }
        .task {
            #if DEBUG
            // 撮影用（#366）: 中盤の盤面を機械的に作る。人間の手番で止まるので CPU は動かない。
            if ProcessInfo.processInfo.arguments.contains("-othelloMidgame") {
                model.applyPreviewMidgameForTesting()
            }
            #endif
        }
    }

    // MARK: - Status Bar (スコアも一行に統合)

    private var statusBar: some View {
        GameStatusBar {
            // 手番 / 結果
            if model.gameOver {
                TurnBadge("終局", kind: .finished)
            } else {
                TurnBadge(isYourTurn: !model.isAITurn)
                if model.isThinking {
                    ProgressView().controlSize(.small)
                }
            }
        } trailing: {
            // コンパクトスコア（終局後はリザルトと同じ「残りマス加算」後の数字。#440）
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: 0x1A1A1A))
                    .frame(width: 13, height: 13)
                Text("\(model.blackScore)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("–")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.whiteScore)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Circle()
                    .fill(Color(hex: 0xF0ECD8))
                    .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
                    .frame(width: 13, height: 13)
            }
        }
    }

    // MARK: - Board

    private var board: some View {
        GeometryReader { geo in
            let size = geo.size.width
            let cell = size / CGFloat(othelloBoardSize)
            let validSet = (model.gameOver || model.isAITurn || model.mustPass)
                ? Set<Int>()
                : Set(model.board.validMoves(for: model.currentStone).map { $0.0 * othelloBoardSize + $0.1 })

            ZStack {
                // 盤は上端 `boardGreen` → 下端 `boardGreenDeep` へ暗くする（#366）。
                // 合法手ドットのコントラストは明るい側（上端）で測っているので、
                // 暗くする方向のグラデーションなら保証はどこでも崩れない。
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: OthelloBoardStyle.boardGreen),
                                 Color(hex: OthelloBoardStyle.boardGreenDeep)],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(
                        // 上辺にだけ細い照りを乗せ、盤の面が起きている感じを出す。
                        RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                            .strokeBorder(LinearGradient(
                                colors: [.white.opacity(0.22), .white.opacity(0)],
                                startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                OthelloBoardCanvas(
                    board: model.board,
                    validSet: validSet,
                    lastMove: model.lastMove,
                    flippedCells: model.flippedCells,
                    placementCount: model.placementCount,
                    revealedPlacements: Double(model.placementCount)
                )
                // 石が裏返る演出（#204）。`Canvas` は View が再評価されないと描き直されない
                // ため、`OthelloBoardCanvas` を `Animatable` にして着手数を補間させている。
                // 段差（`OthelloFlip.stagger`）は進捗の割合として持たせているので、
                // ここは全体を等速で進める `.linear` にする。
                .gameAnimation(.linear(duration: OthelloFlip.duration), value: model.placementCount)
                // `Canvas` は下地の `RoundedRectangle` と兄弟で、自身の矩形いっぱいに描くため、
                // 盤の四隅では角丸の外側へ**直角の角がはみ出す**（グリッド線・端のマスの石・
                // #366 で足した落ち影が角丸の外に出て、盤の輪郭が角ばって見える）。
                // 実測: 四隅だけで 740px の差が出ており、盤の内側の見た目は変わらない。
                // クリップはヒットテスト領域も狭めるので、角のマスを取りこぼさないよう
                // タップ判定は矩形のまま保つ。
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { val in
                            guard !model.isAITurn, !model.gameOver, !model.mustPass else { return }
                            let col = Int(val.location.x / cell)
                            let row = Int(val.location.y / cell)
                            guard row >= 0, row < othelloBoardSize,
                                  col >= 0, col < othelloBoardSize else { return }
                            model.tap(row: row, col: col)
                        }
                )
                .accessibilityRepresentation {
                    accessibilityGrid(cell: cell, validSet: validSet)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// VoiceOver 用のマス目グリッド（#188）。
    ///
    /// 盤は `Canvas` 1 つで描いているため、そのままでは 64 マスが 1 要素にしか見えず、
    /// 石の色も置ける場所も音声で分からない。`accessibilityRepresentation` は
    /// **描画も当たり判定もされず、支援技術に見せる姿としてだけ使われる**ので、
    /// 見た目と指でのタップ挙動（下の `Canvas` の `SpatialTapGesture`）は一切変わらない。
    private func accessibilityGrid(cell: CGFloat, validSet: Set<Int>) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<othelloBoardSize, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<othelloBoardSize, id: \.self) { col in
                        Button {
                            model.tap(row: row, col: col)
                        } label: {
                            Color.clear.frame(width: cell, height: cell)
                        }
                        // 置けない局面では「利用不可」として案内されるようにする。
                        // ここは支援技術にだけ見せる Button なので、見た目には影響しない。
                        .disabled(model.gameOver || model.isAITurn || model.mustPass)
                        .accessibilityLabel(OthelloAccessibility.squareLabel(
                            row: row,
                            col: col,
                            stone: model.board[row, col],
                            isValidMove: validSet.contains(row * othelloBoardSize + col),
                            isLastMove: model.lastMove.map { $0.row == row && $0.col == col } ?? false
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Controls

    private var gameControls: some View {
        HStack(spacing: 12) {
            // 2 つとも同じカプセルに揃え、当たり判定を 44pt にする（#711）。中身は盤ゲーム 5 本で共通（#828）。
            // 投了の確認ダイアログだけは画面全体に付けている（body の `boardResignConfirmation`）。
            BoardResignButton(look: .tapTargetCapsule) { showResignConfirm = true }

            Spacer()

            BoardUndoButton(model: model, services: services, rescue: undoRescue, usesTapTargetCapsule: true)
        }
        .themeBody(14)
        // ボタンの枠が 44pt になったぶん上下の余白を詰め、操作列の外寸を据え置く（#711・#148）。
        .padding(.horizontal, 16).padding(.vertical, BoardGameControlMetrics.rowVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }

    private var resultOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 12) {
                if let w = model.winner {
                    let isWin = w == model.humanSide
                    Image(systemName: isWin ? "trophy.fill" : "flag.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(isWin ? Theme.yellow : Theme.coral)
                    Text(isWin ? "あなたの勝ち！" : "CPUの勝ち")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(isWin ? Theme.teal : Theme.coral)
                } else {
                    Image(systemName: "equal.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.inkSub)
                    Text("引き分け")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                }
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: 0x1A1A1A))
                        .frame(width: 22, height: 22)
                    Text("\(model.blackScore)")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("–")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                    Text("\(model.whiteScore)")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Circle()
                        .fill(Color(hex: 0xF0ECD8))
                        .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
                        .frame(width: 22, height: 22)
                }
                RecordLabel(model.recordResult)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }

    // MARK: - 盤の下の操作エリア

    /// 対局中（投了・待った）と終局後（もう一度・レコメンド）で中身が入れ替わるが、
    /// **高さは常に終局後の最大構成に揃える**（#148。高さの担保は `GameControlArea`）。
    private var controlArea: some View {
        GameControlArea(isFinished: model.gameOver, services: services, ladder: ladder) {
            newGameButton
        } playing: {
            gameControls
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

    /// 「もう一度」は対局中の `gameControls` と同じ高さの 1 段に収める（#148）。
    /// 全幅の大ボタンのままだと盤の下が伸び、決着の瞬間に盤が縮む。
    private var newGameButton: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Button { showNewGame = true } label: {
                Label("もう一度", systemImage: "arrow.clockwise")
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Fill.coral))
            }
            Spacer(minLength: 0)
        }
        .themeBody(14)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - Board Canvas

/// 盤（格子・合法手ドット・石）の描画（#204）。
///
/// `revealedPlacements` は「何手目まで返り終わっているか」を実数で持つ。`placementCount` が
/// n-1 → n へ変わるとき SwiftUI がこの値を補間するので、`revealedPlacements - Double(n - 1)` が
/// そのまま「直前の着手で返る石がどこまで返ったか（0→1）」になる。
///
/// `Canvas` はビュー本体が作り直されない限り描き直されないため、外から `.gameAnimation` を
/// 掛けただけでは色が瞬間で入れ替わるだけになる。`Animatable` に適合させて毎フレーム `body` を
/// 評価させるのがここでの肝（五目並べ #202 と同じ）。Reduce Motion が ON のときは
/// `.gameAnimation` がアニメーションを落とし、補間が起きない = 従来どおりの即時反映になる。
private struct OthelloBoardCanvas: View, Animatable {
    nonisolated let board: OthelloBoard
    nonisolated let validSet: Set<Int>
    nonisolated let lastMove: (row: Int, col: Int)?
    nonisolated let flippedCells: Set<Int>
    nonisolated let placementCount: Int
    nonisolated var revealedPlacements: Double

    // `View` への適合でこの型は MainActor 隔離になるが、`Animatable` の要求は nonisolated。
    // 保持しているのは値型（すべて Sendable）だけなので、格納プロパティごと nonisolated にして
    // 適合を成立させる。
    nonisolated var animatableData: Double {
        get { revealedPlacements }
        set { revealedPlacements = newValue }
    }

    /// 直前の着手の反転が全体としてどこまで進んだか（0→1）。
    ///
    /// 「待った」で着手数が変わらないまま盤だけ戻る場合に備えてクランプする
    /// （はみ出した値のまま描くと、返り終わった石が反転中の姿で残る）。
    private var flipProgress: Double {
        guard placementCount > 0 else { return 1 }
        return min(max(revealedPlacements - Double(placementCount - 1), 0), 1)
    }

    var body: some View {
        let progress = flipProgress
        Canvas { ctx, sz in
            let c = sz.width / CGFloat(othelloBoardSize)
            let lineShading = GraphicsContext.Shading.color(Color(hex: 0x145028).opacity(0.9))

            // グリッド線
            for i in 0...othelloBoardSize {
                let p = CGFloat(i) * c
                var vp = Path(); vp.move(to: CGPoint(x: p, y: 0)); vp.addLine(to: CGPoint(x: p, y: sz.height))
                ctx.stroke(vp, with: lineShading, lineWidth: 1)
                var hp = Path(); hp.move(to: CGPoint(x: 0, y: p)); hp.addLine(to: CGPoint(x: sz.width, y: p))
                ctx.stroke(hp, with: lineShading, lineWidth: 1)
            }

            // 星（盤の目印・#366）。グリッド線の交点に打つので石より先に描く。
            for star in OthelloBoardStyle.starPoints {
                let px = CGFloat(star.col) * c, py = CGFloat(star.row) * c
                let r = c * OthelloBoardStyle.starPointRadiusRatio
                ctx.fill(Path(ellipseIn: CGRect(x: px-r, y: py-r, width: r*2, height: r*2)),
                         with: lineShading)
            }

            // 合法手ドット
            for idx in validSet {
                let row = idx / othelloBoardSize, col = idx % othelloBoardSize
                let cx = (CGFloat(col) + 0.5) * c, cy = (CGFloat(row) + 0.5) * c
                let r  = c * OthelloBoardStyle.legalMoveDotRadiusRatio
                ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                         with: .color(Color(hex: OthelloBoardStyle.legalMoveDot)
                                          .opacity(OthelloBoardStyle.legalMoveDotOpacity)))
            }

            // 石は「上面 + 下にのぞく側面」の 2 枚のだ円で**上面が平らな円柱**に見せる（#366）。
            // 1 枚のだ円にラジアルの照りを乗せるとドーム（碁石）に見えるので使わない。
            // 石ごとの姿（色・幅・大きさ）をここで確定し、描画は 2 パスで行う。
            struct StoneShape {
                let faceRect: CGRect
                let sideRect: CGRect
                let shown: OthelloStone
                let edgeShade: Double
                let centerX: CGFloat
            }
            var shapes: [StoneShape] = []
            for row in 0..<othelloBoardSize {
                for col in 0..<othelloBoardSize {
                    guard let stone = board[row, col] else { continue }
                    let cx = (CGFloat(col) + 0.5) * c, cy = (CGFloat(row) + 0.5) * c
                    var r  = c * OthelloBoardStyle.stoneRadiusRatio

                    // 置いた瞬間の石は大きめに出して実寸へ落とす（ドロップ感・#366）。
                    if let last = lastMove, last.row == row, last.col == col {
                        r *= CGFloat(OthelloFlip.popScale(progress: progress))
                    }

                    // 返っている最中の石は、縦軸まわりに回っているように横幅だけ縮める。
                    // 真横を向く折り返しで色が入れ替わるので、盤の色が変わる瞬間が目で追える。
                    var shown = stone
                    var rx = r
                    if let last = lastMove, flippedCells.contains(row * othelloBoardSize + col) {
                        let distance = max(abs(row - last.row), abs(col - last.col))
                        let p = OthelloFlip.progress(distance: distance, overall: progress)
                        shown = OthelloFlip.shownStone(target: stone, progress: p)
                        rx = r * CGFloat(OthelloFlip.widthScale(progress: p))
                    }

                    // 側面の高さぶんを上下に振り分け、石全体をマスの中央に収める。
                    let rimH = r * OthelloBoardStyle.stoneRimHeightRatio
                    let faceRect = CGRect(x: cx - rx, y: cy - rimH / 2 - r, width: rx * 2, height: r * 2)
                    shapes.append(StoneShape(
                        faceRect: faceRect,
                        sideRect: faceRect.offsetBy(dx: 0, dy: rimH),
                        shown: shown,
                        // 反転中は細くなった幅のぶんだけ暗く沈め、回転中の陰影に見せる。
                        edgeShade: OthelloBoardStyle.flipEdgeShadeMaxOpacity
                            * (1 - Double(rx / max(r, 0.0001))),
                        centerX: cx))
                }
            }

            // パス1: 側面（最下層）。落ち影はここにだけ掛ける（フィルタは以後の描画
            // それぞれに適用されるので石 1 枚ごとに影が付く）。上面まで同じレイヤーに
            // 入れると上面の影が自分の側面に落ちて縁が濁る。
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(
                    color: .black.opacity(OthelloBoardStyle.stoneShadowOpacity),
                    radius: c * OthelloBoardStyle.stoneShadowRadiusRatio,
                    x: 0, y: c * OthelloBoardStyle.stoneShadowOffsetRatio))
                for shape in shapes {
                    layer.fill(Path(ellipseIn: shape.sideRect),
                               with: .color(Color(hex: shape.shown == .black
                                                  ? OthelloBoardStyle.stoneBlackSide
                                                  : OthelloBoardStyle.stoneWhiteSide)))
                }
            }

            // パス2: 上面。平らな面に見えるよう明度差の小さい縦グラデーションに留める。
            for shape in shapes {
                let colors = shape.shown == .black
                    ? [Color(hex: OthelloBoardStyle.stoneBlackFaceTop),
                       Color(hex: OthelloBoardStyle.stoneBlackFaceBottom)]
                    : [Color(hex: OthelloBoardStyle.stoneWhiteFaceTop),
                       Color(hex: OthelloBoardStyle.stoneWhiteFaceBottom)]
                let facePath = Path(ellipseIn: shape.faceRect)
                ctx.fill(facePath, with: .linearGradient(
                    Gradient(colors: colors),
                    startPoint: CGPoint(x: shape.centerX, y: shape.faceRect.minY),
                    endPoint: CGPoint(x: shape.centerX, y: shape.faceRect.maxY)))
                if shape.shown == .white {
                    ctx.stroke(facePath, with: .color(Color.gray.opacity(0.3)), lineWidth: 1)
                }
                if shape.edgeShade > 0.01 {
                    ctx.fill(facePath, with: .color(.black.opacity(shape.edgeShade)))
                    ctx.fill(Path(ellipseIn: shape.sideRect),
                             with: .color(.black.opacity(shape.edgeShade)))
                }
            }

            // 直前手マーカー。置いた石にだけ出るので、反転中の石には掛からない。
            // 反転の進みに合わせてフェードインさせ、着地前の石に印が乗らないようにする。
            if let last = lastMove, let stone = board[last.row, last.col] {
                let cx = (CGFloat(last.col) + 0.5) * c, cy = (CGFloat(last.row) + 0.5) * c
                let r = c * OthelloBoardStyle.stoneRadiusRatio
                // 上面の中心（側面ぶん上にずれている）へ合わせる。
                let faceCY = cy - r * OthelloBoardStyle.stoneRimHeightRatio / 2
                let mr = r * 0.3
                let mRect = CGRect(x: cx-mr, y: faceCY-mr, width: mr*2, height: mr*2)
                ctx.fill(Path(ellipseIn: mRect),
                         with: .color((stone == .black
                                       ? Color.white.opacity(0.5)
                                       : Color(hex: OthelloBoardStyle.boardGreen).opacity(0.5))
                                          .opacity(progress)))
            }
        }
    }
}

// MARK: - New Game Sheet

struct OthelloNewGameSheet: View {
    @State private var side: OthelloStone
    @State private var level: Int
    let onStart: (OthelloStone, Int) -> Void
    let onCancel: () -> Void

    init(humanSide: OthelloStone, aiLevel: Int,
         onStart: @escaping (OthelloStone, Int) -> Void,
         onCancel: @escaping () -> Void) {
        _side  = State(initialValue: humanSide)
        _level = State(initialValue: aiLevel)
        self.onStart  = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        GameSetupSheet(
            kind: .versus,
            onStart: { onStart(side, level) }, onCancel: onCancel
        ) {
            GameSetupSection("あなたの石") {
                HStack(spacing: 12) {
                    GameSetupChooser(title: "●黒", subtitle: "先手",
                                     selected: side == .black, accent: Theme.fillStrong,
                                     onAccent: .white) { side = .black }
                    GameSetupChooser(title: "○白", subtitle: "後手",
                                     selected: side == .white, accent: Theme.fillMuted,
                                     onAccent: .white) { side = .white }
                }
            }
            GameSetupSection("CPUの強さ") {
                // 説明は `OthelloEngine.bestMove` の中身と一致させる（#416）。
                CPUStrengthPicker(level: $level, details: [
                    "角のとなりが好き", "浅い読み", "標準", "深い読み",
                ])
            }
        }
    }
}
