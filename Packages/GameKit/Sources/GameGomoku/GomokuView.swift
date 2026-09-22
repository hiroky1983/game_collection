import SwiftUI
import Foundation
import Core

public struct GomokuView: View {
    @State private var model: GomokuModel
    private let services: GameServices
    @State private var showNewGame: Bool
    @State private var showConfirmNewGame = false
    @State private var showResignConfirm = false
    /// 「待った」のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var undoRescue = RewardedRescue()

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: GomokuModel(services: services))
        _showNewGame = State(initialValue: !services.snapshots.exists(for: "gomoku"))
    }

    public var body: some View {
        // 縦の余白は 8。対局中と終局後で高さが変わらない `controlArea` を置くぶん、
        // 盤に回せる高さを間隔から捻出している（#148・#139 の横展開）。
        VStack(spacing: 8) {
            statusBar
            stoneRow(stone: model.humanSide.opponent, isYou: false)
            board
                .layoutPriority(1)
            stoneRow(stone: model.humanSide, isYou: true)
            HowToPlayHint(model.forbiddenMovesEnabled ? .gomokuRenju : .gomoku,
                          playLog: services.playLog)
            controlArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.none, value: model.gameOver)
        .padding(Theme.pad)
        .gameChrome(title: "五目並べ", review: services.review) {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.gameOver || model.moveCount == 0 {
                        showNewGame = true
                    } else {
                        showConfirmNewGame = true
                    }
                } label: {
                    Label("新規対局", systemImage: "plus.circle.fill")
                }
            }
        }
        .howToPlay(model.forbiddenMovesEnabled ? .gomokuRenju : .gomoku)
        .sheet(isPresented: $showNewGame) {
            GomokuNewGameSheet(humanSide: model.humanSide, aiLevel: model.aiLevel,
                               forbiddenMoves: model.forbiddenMovesEnabled) { side, level, renju in
                model.newGame(humanSide: side, aiLevel: level, forbiddenMoves: renju)
                showNewGame = false
            } onCancel: { showNewGame = false }
        }
        .confirmationDialog("新規対局しますか？", isPresented: $showConfirmNewGame, titleVisibility: .visible) {
            Button("終了して新規対局", role: .destructive) { showNewGame = true }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると対局データが失われます。")
        }
        .task(id: model.aiTurnKey) {
            await model.performAIMoveIfNeeded()
        }
        .task {
            #if DEBUG
            // 撮影用（#366）: 中盤風の盤面を機械的に作る。人間の手番で止まるので CPU は動かない。
            if ProcessInfo.processInfo.arguments.contains("-gomokuMidgame") {
                model.applyPreviewMidgameForTesting()
            }
            // 撮影用（#441）: 禁じ手で断られた直後の画面。
            if ProcessInfo.processInfo.arguments.contains("-gomokuRenjuBlocked") {
                model.applyRenjuBlockedPreviewForTesting()
            }
            #endif
        }
    }

    // MARK: - 盤の下の操作エリア

    /// 対局中（投了・待った）と終局後（もう一度・レコメンド）で中身が入れ替わるが、
    /// **高さは常に終局後の最大構成に揃える**（#148。高さの担保は `GameControlArea`）。
    private var controlArea: some View {
        GameControlArea(isFinished: model.gameOver, services: services, ladder: ladder) {
            resultControls
        } playing: {
            gameControls
        }
    }

    /// 勝ちが続いたら一段上の強さを勧める（#722）。並びは開始シートの「CPUの強さ」と同じで、
    /// 石の色と禁じ手の有無は今の対局のものを引き継ぐ。
    private var ladder: DifficultyLadderPrompt? {
        DifficultyLadderPrompt(result: model.recordResult,
                               currentLevel: CPUStrength.ladderIndex(forLevel: model.aiLevel),
                               levelLabels: CPUStrength.labels) { index in
            model.newGame(humanSide: model.humanSide,
                          aiLevel: CPUStrength.level(atLadderIndex: index),
                          forbiddenMoves: model.forbiddenMovesEnabled)
        }
    }

    /// 「もう一度」は 1 段にまとめ、対局中の `gameControls` と同じ高さに収める（#148）。
    /// 記録ラベルは行を増やさずステータスバーへ同居させている。
    private var resultControls: some View {
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

    // MARK: - Board

    private var board: some View {
        GeometryReader { geo in
            let pad: CGFloat = 14
            let inner = geo.size.width - pad * 2
            let spacing = inner / CGFloat(gomokuBoardSize - 1)

            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(hex: 0xDEB568))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)

                GomokuBoardCanvas(
                    board: model.board,
                    lastMove: model.lastMove,
                    moveCount: model.moveCount,
                    pad: pad,
                    revealedMoves: Double(model.moveCount)
                )
                // 置いた石が現れる演出（#202）。`Canvas` は View が再評価されないと描き直されない
                // ため、`GomokuBoardCanvas` を `Animatable` にして手数を補間させている。
                .gameAnimation(.easeOut(duration: GomokuMotion.placementDuration), value: model.moveCount)
                .gesture(
                    SpatialTapGesture()
                        .onEnded { val in
                            let col = Int(((val.location.x - pad) / spacing).rounded())
                            let row = Int(((val.location.y - pad) / spacing).rounded())
                            // 盤外・手番違いの判定は Model 側に集約する（#202）。
                            // ここで早期 return すると無効タップが無反応のまま残る。
                            model.tap(row: row, col: col)
                        }
                )
                .accessibilityRepresentation {
                    accessibilityGrid(pad: pad, spacing: spacing)
                }

                // 決着した五を光らせる（#665）。盤の前面に重ねるので、タップと VoiceOver の
                // 交点グリッドを横取りしないよう当たり判定・支援技術の両方から外す。
                GomokuWinLineCanvas(
                    line: model.winningLine ?? [],
                    pad: pad,
                    progress: model.winningLine == nil ? 0 : 1
                )
                .gameAnimation(GomokuMotion.winLine, value: model.winningLine)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                // ヒントが示す交点（#1118）。盤の前面に重ねるので、勝ち筋と同じく
                // タップと VoiceOver の交点グリッドを横取りしないよう両方から外す。
                hintMark(pad: pad, spacing: spacing)
            }
            // 打てないタップを盤の横揺れで伝える（#202）。触覚・効果音は Model 側から鳴る。
            .modifier(GomokuShake(animatableData: CGFloat(model.rejectedTapCount)))
            .gameAnimation(.linear(duration: 0.32), value: model.rejectedTapCount)
            // 禁じ手の理由は揺れの外に置く（一緒に揺らすと読めない）。
            .overlay(alignment: .top) { forbiddenNotice }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// ヒントが示す交点の印（#1118）。次に打つと良い 1 点を紫の輪で囲む。
    ///
    /// 出す条件は `model.hintPoint` だけで、盤が動けば Model 側が印を落とす。
    /// 色は将棋・チェスと共通（`BoardGameHintColor`）。読み上げは VoiceOver 用の交点グリッド
    /// （`accessibilityGrid` の `isHint`）が持つ。
    @ViewBuilder
    private func hintMark(pad: CGFloat, spacing: CGFloat) -> some View {
        if let point = model.hintPoint {
            Circle()
                .stroke(BoardGameHintColor.color, lineWidth: 3)
                .background(Circle().fill(BoardGameHintColor.color.opacity(0.22)))
                .frame(width: spacing * 0.9, height: spacing * 0.9)
                .position(x: pad + spacing * CGFloat(point.col),
                          y: pad + spacing * CGFloat(point.row))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// 禁じ手で打てなかったことを盤の上に出す（#441）。
    ///
    /// 空いている交点なのに石が入らないので、震え（#202）と警告音だけでは
    /// 「なぜ打てないのか」が伝わらない。次に打てたら `place` が `lastRejection` を
    /// 消すので自然に引っ込む。盤への `overlay` なので、出ても消えても盤や
    /// その下の操作エリアの高さは変わらない（#148 で揃えた高さを崩さない）。
    @ViewBuilder
    private var forbiddenNotice: some View {
        if case .forbidden(let reason) = model.lastRejection {
            Text("\(reason.label)は打てません（禁じ手）")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.Fill.coral))
                .padding(.top, 10)
                // 帯は盤より前面なので、既定のままだと重なった交点へのタップを吸ってしまう。
                // 見せるだけの表示なので当たり判定から外す。
                .allowsHitTesting(false)
        }
    }

    /// VoiceOver 用の交点グリッド（#188）。
    ///
    /// 盤は `Canvas` 1 つで描いているため、そのままでは 225 個の交点が 1 要素にしか見えず、
    /// 石の有無も打てる場所も音声で分からない。`accessibilityRepresentation` は
    /// **描画も当たり判定もされず、支援技術に見せる姿としてだけ使われる**ので、
    /// 見た目と指でのタップ挙動（下の `Canvas` の `SpatialTapGesture`）は一切変わらない。
    private func accessibilityGrid(pad: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<gomokuBoardSize, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<gomokuBoardSize, id: \.self) { col in
                        Button {
                            model.tap(row: row, col: col)
                        } label: {
                            Color.clear.frame(width: spacing, height: spacing)
                        }
                        // 打てない局面では「利用不可」として案内されるようにする。
                        // ここは支援技術にだけ見せる Button なので、見た目には影響しない。
                        .disabled(model.gameOver || model.isAITurn)
                        .accessibilityLabel(GomokuAccessibility.pointLabel(
                            row: row,
                            col: col,
                            stone: model.board[row, col],
                            isLastMove: model.lastMove.map { $0.row == row && $0.col == col } ?? false,
                            isHint: model.hintPoint == GomokuPoint(row: row, col: col)
                        ))
                    }
                }
            }
        }
        // 交点が各マスの中心に来るよう、格子ぶんの半マスだけ左上へずらす
        // （`SpatialTapGesture` 側の四捨五入の境界とちょうど一致する）。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(x: pad - spacing / 2, y: pad - spacing / 2)
    }

    // MARK: - Stone Info Row

    private func stoneRow(stone: GomokuStone, isYou: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stone == .black
                      ? AnyShapeStyle(Color(hex: 0x18140E))
                      : AnyShapeStyle(Color(hex: 0xF0E8D0)))
                .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
                .frame(width: 18, height: 18)
            Text(isYou ? "あなた" : "CPU")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isYou ? Theme.teal : Theme.inkSub)
            Text(stone == .black ? "黒・先手" : "白・後手")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 高さは 30。終局後に出るもののぶんを確保しても盤が小さくならないよう、
        // 石・文字の大きさは変えずに余白から捻出している（#148）。
        .frame(minHeight: 30)
        .padding(.horizontal, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let w = model.winner {
                Label(w == model.humanSide ? "あなたの勝ち！" : "CPUの勝ち",
                      systemImage: "flag.checkered")
                    .themeBody(16).foregroundStyle(Theme.coral)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else if model.isDraw {
                Label("引き分け", systemImage: "equal.circle")
                    .themeBody(16).foregroundStyle(Theme.inkSub)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                let isMine = model.currentStone == model.humanSide
                Text(isMine ? "あなたの番" : "CPUの番")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(isMine ? Theme.Fill.teal : Theme.Fill.coral))
                if model.isThinking {
                    ProgressView().controlSize(.small)
                    Text("思考中…").themeBody(13).foregroundStyle(Theme.inkSub)
                }
            }
            Spacer(minLength: 8)
            if model.gameOver {
                // 終局後の記録は行を増やさずここに同居させる（#148）。
                // 将棋（#139）は手数を検討ナビの「n/N手」に譲れたが、五目並べには
                // 代わりの表示が無いため、手数はここに残したまま記録を足す。
                RecordLabel(model.recordResult)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("\(model.moveCount)手").themeBody(13).foregroundStyle(Theme.inkSub)
        }
        .frame(minHeight: 32)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .popCard(corner: Theme.cornerSmall)
    }

    private var gameControls: some View {
        HStack(spacing: 12) {
            // 2 つとも同じカプセルに揃え、当たり判定を 44pt にする（#711）。中身は盤ゲーム 5 本で共通（#828）。
            BoardResignButton(look: .tapTargetCapsule) { showResignConfirm = true }
                .boardResignConfirmation(isPresented: $showResignConfirm) { model.resign() }

            Spacer()

            // ヒントは 3 本とも同じ部品・同じ見た目（#1118）。ここは元から枠 44pt のカプセルで
            // 組んである列なので、将棋・チェスのような余白の詰めは要らない。
            BoardHintButton(model: model)

            BoardUndoButton(model: model, services: services, rescue: undoRescue, usesTapTargetCapsule: true)
        }
        .themeBody(14)
        // ヒントが増えて 3 つ並ぶので、iPhone SE の幅でも改行させず 1 行に収める（将棋・チェスと同じ）。
        .lineLimit(1).minimumScaleFactor(0.8)
        // ボタンの枠が 44pt になったぶん上下の余白を詰め、操作列の外寸を据え置く（#711・#148）。
        .padding(.horizontal, 16).padding(.vertical, BoardGameControlMetrics.rowVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - Board Canvas

/// 盤（格子・星・石）の描画（#202）。
///
/// `revealedMoves` は「何手目まで現れているか」を実数で持つ。`moveCount` が n-1 → n へ
/// 変わるとき SwiftUI がこの値を補間するので、`revealedMoves - Double(moveCount - 1)` が
/// そのまま「直前手の石がどこまで現れたか（0→1）」になる。
///
/// `Canvas` はビュー本体が作り直されない限り描き直されないため、外から `.gameAnimation` を
/// 掛けただけでは石が瞬間表示のままになる。`Animatable` に適合させて毎フレーム `body` を
/// 評価させるのがここでの肝。Reduce Motion が ON のときは `.gameAnimation` が
/// アニメーションを落とし、補間が起きない = 従来どおりの即時表示になる。
private struct GomokuBoardCanvas: View, Animatable {
    nonisolated let board: GomokuBoard
    nonisolated let lastMove: (row: Int, col: Int)?
    nonisolated let moveCount: Int
    nonisolated let pad: CGFloat
    nonisolated var revealedMoves: Double

    // `View` への適合でこの型は MainActor 隔離になるが、`Animatable` の要求は nonisolated。
    // 保持しているのは値型（すべて Sendable）だけなので、格納プロパティごと nonisolated にして
    // 適合を成立させる。
    nonisolated var animatableData: Double {
        get { revealedMoves }
        set { revealedMoves = newValue }
    }

    /// 直前手の石が現れきったか（0→1）。
    ///
    /// 「待った」で手数が減る向きでは 1 を超えた値になるためクランプする
    /// （巻き戻しの最中に残った石が薄くなるのを防ぐ）。
    private var placementProgress: Double {
        guard moveCount > 0 else { return 1 }
        return min(max(revealedMoves - Double(moveCount - 1), 0), 1)
    }

    var body: some View {
        let progress = placementProgress
        Canvas { ctx, size in
            let s = (size.width - pad * 2) / CGFloat(gomokuBoardSize - 1)
            let lineColor = GraphicsContext.Shading.color(Color(hex: 0x7A5810).opacity(0.55))

            // 盤の格子線
            for i in 0..<gomokuBoardSize {
                let x = pad + CGFloat(i) * s
                let y = pad + CGFloat(i) * s
                var vp = Path()
                vp.move(to: CGPoint(x: x, y: pad))
                vp.addLine(to: CGPoint(x: x, y: size.height - pad))
                ctx.stroke(vp, with: lineColor, lineWidth: 0.8)

                var hp = Path()
                hp.move(to: CGPoint(x: pad, y: y))
                hp.addLine(to: CGPoint(x: size.width - pad, y: y))
                ctx.stroke(hp, with: lineColor, lineWidth: 0.8)
            }

            // 星（天元 + 4隅）
            let dotColor = GraphicsContext.Shading.color(Color(hex: 0x7A5810).opacity(0.7))
            for ri in [3, 7, 11] {
                for ci in [3, 7, 11] {
                    let cx = pad + CGFloat(ci) * s
                    let cy = pad + CGFloat(ri) * s
                    let dr: CGFloat = 2.5
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - dr, y: cy - dr, width: dr*2, height: dr*2)),
                             with: dotColor)
                }
            }

            // 駒（石）
            for row in 0..<gomokuBoardSize {
                for col in 0..<gomokuBoardSize {
                    guard let stone = board[row, col] else { continue }
                    let isLast = lastMove.map { $0.row == row && $0.col == col } ?? false
                    // 直前手だけスケール + フェードで現れる。それ以外は常に実寸。
                    let appear = isLast ? progress : 1
                    guard appear > 0 else { continue }

                    let cx = pad + CGFloat(col) * s
                    let cy = pad + CGFloat(row) * s
                    let r  = s * 0.46 * (0.55 + 0.45 * appear)
                    let rect = CGRect(x: cx - r, y: cy - r, width: r*2, height: r*2)
                    let path = Path(ellipseIn: rect)

                    // 透明度は複製したレイヤーに掛ける（元の ctx に残すと以降の石まで薄くなる）。
                    var layer = ctx
                    layer.opacity = appear
                    // 碁石はドーム（半球）に見せる: 左上寄りのラジアルの照り + 落ち影（#366）。
                    // オセロの石（円柱・上面が平ら）とは意図的に描き分けている。
                    layer.addFilter(.shadow(
                        color: .black.opacity(0.30),
                        radius: s * 0.09,
                        x: 0, y: s * 0.07))

                    let highlight = CGPoint(x: cx - r * 0.35, y: cy - r * 0.4)
                    if stone == .black {
                        layer.fill(path, with: .radialGradient(
                            Gradient(colors: [Color(hex: 0x55504A), Color(hex: 0x0F0C08)]),
                            center: highlight, startRadius: 0, endRadius: r * 1.7))
                    } else {
                        layer.fill(path, with: .radialGradient(
                            Gradient(colors: [Color(hex: 0xFFFCF0), Color(hex: 0xD9D2B8)]),
                            center: highlight, startRadius: 0, endRadius: r * 1.7))
                        layer.stroke(path, with: .color(Color.gray.opacity(0.4)), lineWidth: 1)
                    }

                    // 直前手マーカー: 外周のリング + 中央のドット（#202）。
                    // 内側の小さなドットだけでは黒石の上でほとんど見えず、初見では
                    // 直前手の位置が分からなかった。盤色・黒石・白石のいずれとも差が出る
                    // アクセント色のリングを外周に足し、ドットも一回り大きく濃くする。
                    if isLast {
                        // マーカーには石の落ち影を付けたくないので、影フィルタなしの複製に描く。
                        var markerLayer = ctx
                        markerLayer.opacity = appear

                        let ring = rect.insetBy(dx: -2, dy: -2)
                        markerLayer.stroke(Path(ellipseIn: ring), with: .color(Theme.coral), lineWidth: 2.4)

                        let mr = r * 0.34
                        let mRect = CGRect(x: cx - mr, y: cy - mr, width: mr*2, height: mr*2)
                        markerLayer.fill(Path(ellipseIn: mRect),
                                   with: .color(stone == .black ? Color.white.opacity(0.9)
                                                                : Color(hex: 0x2A1600).opacity(0.75)))
                    }
                }
            }
        }
    }
}

// MARK: - 勝ち筋

/// 五目並べの演出の尺（#665）。View の `static` は MainActor 隔離になるため、別の enum に置く。
enum GomokuMotion {
    /// 置いた石が現れる時間（#202）。
    static let placementDuration: TimeInterval = 0.18
    /// 勝ち筋が光りきるまでの時間。
    static let winLineDuration: TimeInterval = 0.3
    /// 決着の石が現れきってから線を引き始める。
    static var winLine: Animation {
        .easeOut(duration: winLineDuration).delay(placementDuration)
    }
}

/// 決着した五を盤上で光らせる（#665）。
///
/// 端の石から端の石へ線を伸ばし、並んだ石をリングで囲む。`progress`（0→1）で線の長さと
/// リングの濃さが増える。`GomokuBoardCanvas` と同じく `Animatable` にして補間させ、
/// Reduce Motion が ON のときは `.gameAnimation` が補間を落とすので即座に光りきる。
private struct GomokuWinLineCanvas: View, Animatable {
    nonisolated let line: [GomokuPoint]
    nonisolated let pad: CGFloat
    nonisolated var progress: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let progress = min(max(progress, 0), 1)
        Canvas { ctx, size in
            guard let first = line.first, let last = line.last, progress > 0 else { return }
            let s = (size.width - pad * 2) / CGFloat(gomokuBoardSize - 1)
            func center(_ p: GomokuPoint) -> CGPoint {
                CGPoint(x: pad + CGFloat(p.col) * s, y: pad + CGFloat(p.row) * s)
            }

            var layer = ctx
            layer.opacity = progress
            for point in line {
                let c = center(point)
                let r = s * 0.46 + 3
                layer.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .color(Theme.coral), lineWidth: 3)
            }

            let start = center(first), end = center(last)
            var path = Path()
            path.move(to: start)
            path.addLine(to: CGPoint(x: start.x + (end.x - start.x) * progress,
                                     y: start.y + (end.y - start.y) * progress))
            ctx.stroke(path, with: .color(Theme.coral.opacity(0.75)),
                       style: StrokeStyle(lineWidth: s * 0.16, lineCap: .round))
        }
    }
}

// MARK: - 無効操作の震え

/// 打てないタップを伝える盤の横揺れ（#202）。
///
/// `animatableData` に拒否の通し番号を渡す。値が 1 進むあいだに左右へ `shakes` 往復し、
/// 整数では `sin` が 0 になるので**必ず元位置へ戻る**（振れっぱなしにならない）。
/// Reduce Motion が ON のときは `.gameAnimation` がアニメーションを落とすため補間自体が
/// 起きず、盤は静止したままになる（触覚・効果音は Model 側から従来どおり鳴る）。
private struct GomokuShake: GeometryEffect {
    /// 片側の振れ幅（pt）。
    var amount: CGFloat = 5
    /// 通し番号 1 つにつき往復する回数。
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: amount * sin(animatableData * .pi * 2 * shakes), y: 0)
        )
    }
}

// MARK: - New Game Sheet

struct GomokuNewGameSheet: View {
    @State private var side: GomokuStone
    @State private var level: Int
    @State private var renju: Bool
    let onStart: (GomokuStone, Int, Bool) -> Void
    let onCancel: () -> Void

    init(humanSide: GomokuStone, aiLevel: Int, forbiddenMoves: Bool,
         onStart: @escaping (GomokuStone, Int, Bool) -> Void,
         onCancel: @escaping () -> Void) {
        _side  = State(initialValue: humanSide)
        _level = State(initialValue: aiLevel)
        _renju = State(initialValue: forbiddenMoves)
        self.onStart  = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        // 選択肢が3節あり `.medium` には収まらない（囲碁 GoNewGameSheet と同じで、
        // はみ出すと「対局開始」が押せなくなる）。`.scrolling` は常に `.large` で開く。
        GameSetupSheet(
            title: "新規対局", startTitle: "対局開始", layout: .scrolling,
            onStart: { onStart(side, level, renju) }, onCancel: onCancel
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
                // 説明は `SimpleGomokuEngine.init(level:)` の中身と一致させる（#416）。
                CPUStrengthPicker(level: $level, details: [
                    "見のがしが多い", "浅い読み", "標準", "深い読み",
                ])
            }
            // 既定はオフ（自由五目）。オンにすると黒だけが三三・四四・長連を打てなくなる。
            GameSetupSection("禁じ手（連珠ルール）") {
                HStack(spacing: 12) {
                    GameSetupChooser(title: "なし", subtitle: "自由五目",
                                     selected: !renju, accent: Theme.Fill.teal)   { renju = false }
                    GameSetupChooser(title: "あり", subtitle: "黒に三三・四四・長連",
                                     selected: renju,  accent: Theme.Fill.purple) { renju = true }
                }
            }
        }
    }
}
