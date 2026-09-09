import SwiftUI
import Foundation
import Core

public struct GoView: View {
    @State private var model: GoModel
    private let services: GameServices
    @State private var showNewGame: Bool
    @State private var showConfirmNewGame = false
    @State private var showUndoConfirm = false
    @State private var showResignConfirm = false
    @State private var showRewardNotEarned = false
    @Environment(\.dismiss) private var dismiss

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: GoModel(services: services))
        _showNewGame = State(initialValue: !services.snapshots.exists(for: "go"))
    }

    public var body: some View {
        // 縦の余白は 8。対局中と終局後で高さが変わらない `controlArea` を置くぶん、
        // 盤に回せる高さを間隔から捻出している（五目並べ #148 と同じ組み方）。
        VStack(spacing: 8) {
            statusBar
            stoneRow(stone: model.humanSide.opponent, isYou: false)
            board
                .layoutPriority(1)
            stoneRow(stone: model.humanSide, isYou: true)
            HowToPlayHint(.go, playLog: services.playLog)
            controlArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.none, value: model.phase)
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
                Text("囲碁")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
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
        .howToPlay(.go) { GoRuleDetails() }
        .sheet(isPresented: $showNewGame) {
            GoNewGameSheet(
                humanSide: model.humanSide,
                level: model.aiLevel,
                handicap: model.ruleset.handicap
            ) { side, level, handicap in
                model.newGame(humanSide: side, level: level, handicap: handicap)
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
        .task(id: model.phase) {
            await model.evaluateEndgameIfNeeded()
        }
        .task {
            #if DEBUG
            // 撮影用（#398）: 中盤風の盤面を機械的に作る。人間の手番で止まるので CPU は動かない。
            if ProcessInfo.processInfo.arguments.contains("-goScoring") {
                await model.applyPreviewScoringForTesting()
            } else if ProcessInfo.processInfo.arguments.contains("-goMidgame") {
                model.applyPreviewMidgameForTesting()
            }
            #endif
        }
    }

    // MARK: - 盤の下の操作エリア

    /// 対局中（投了・パス・待った）と終局後（もう一度・レコメンド）で中身が入れ替わるが、
    /// **高さは常に終局後の最大構成に揃える**（#148 の横展開）。
    /// 対局中（パス・投了）/ 死活確認中 / 終局後（もう一度）で中身が入れ替わるが、どれも
    /// 同じ余白の1行なので高さは変わらない（決着で盤が縮まない契約）。レコメンドの常時高さ予約は
    /// 盤を狭くしていたため撤廃し、盤の下端へのオーバーレイに移した（将棋 #405 と同じ手当て。
    /// 会長指摘 2026-09-02「碁盤が小さい」）。
    private var controlArea: some View {
        ZStack(alignment: .top) {
            switch model.phase {
            case .playing:
                gameControls
            case .scoring:
                scoringControls
            case .finished:
                resultControls
            }
        }
    }

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

    /// 両者パスのあとの確認。**ここで結果を承認するまで成績は記録しない**ので、
    /// 簡易死活の判定が怪しければ「対局続行」で戻れる（#398）。
    private var scoringControls: some View {
        VStack(spacing: 6) {
            if model.endgame == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("終局の計算中…").themeBody(13).foregroundStyle(Theme.inkSub)
                }
                .frame(maxWidth: .infinity)
            } else if let endgame = model.endgame {
                Text(endgame.score.summary)
                    .themeBody(16).foregroundStyle(Theme.coral)
                Text("黒 \(endgame.score.blackArea) 目 / 白 \(endgame.score.whiteArea) 目 + コミ \(komiText(endgame.score))")
                    .themeBody(12).foregroundStyle(Theme.inkSub)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if endgame.isUncertain {
                    Label("死活の判定があいまいです。続けて打って決着させることもできます。",
                          systemImage: "exclamationmark.triangle.fill")
                        .themeBody(11).foregroundStyle(Theme.inkSub)
                        .multilineTextAlignment(.leading)
                }
            }
            HStack(spacing: 12) {
                Button { model.resumePlay() } label: {
                    Label("対局続行", systemImage: "arrow.uturn.backward")
                }
                Spacer(minLength: 0)
                Button { model.acceptEndgame() } label: {
                    Text("この結果で終局")
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.Fill.coral))
                }
                .disabled(model.endgame == nil)
            }
            .themeBody(14)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    private func komiText(_ score: GoScore) -> String {
        let total = score.komi + Double(score.handicapCompensation)
        return total == total.rounded() ? String(Int(total)) : String(format: "%.1f", total)
    }

    // MARK: - Board

    private var board: some View {
        GeometryReader { geo in
            let size = model.board.size
            let pad: CGFloat = 18
            let inner = geo.size.width - pad * 2
            let spacing = inner / CGFloat(size - 1)

            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(hex: 0xDEB568))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)

                GoBoardCanvas(
                    board: model.board,
                    lastMove: model.lastMove,
                    dead: model.endgame?.dead ?? [],
                    moveCount: model.moveCount,
                    pad: pad,
                    revealedMoves: Double(model.moveCount)
                )
                // 置いた石が現れる演出（#202 の横展開）。`Canvas` は View が再評価されないと
                // 描き直されないため、`GoBoardCanvas` を `Animatable` にして手数を補間させている。
                .gameAnimation(.easeOut(duration: 0.18), value: model.moveCount)
                .gesture(
                    SpatialTapGesture()
                        .onEnded { val in
                            let col = Int(((val.location.x - pad) / spacing).rounded())
                            let row = Int(((val.location.y - pad) / spacing).rounded())
                            // 盤外・手番違い・禁じ手の判定は Model 側に集約する（#202）。
                            model.tap(row: row, col: col)
                        }
                )
                .accessibilityRepresentation {
                    accessibilityGrid(pad: pad, spacing: spacing)
                }
            }
            // 打てないタップを盤の横揺れで伝える（#202）。触覚・効果音は Model 側から鳴る。
            .modifier(GoShake(animatableData: CGFloat(model.rejectedTapCount)))
            .gameAnimation(.linear(duration: 0.32), value: model.rejectedTapCount)
        }
        .aspectRatio(1, contentMode: .fit)
        // 終局後のレコメンドは盤の下端に重ねる（常時高さ予約の代替。将棋 #405 と同じ）。
        .overlay(alignment: .bottom) {
            if model.phase == .finished {
                RecommendationSlot(services: services, isFinished: true)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
    }

    /// VoiceOver 用の交点グリッド（#188 の横展開）。
    ///
    /// `accessibilityRepresentation` は**描画も当たり判定もされず、支援技術に見せる姿としてだけ**
    /// 使われるので、見た目と指でのタップ挙動は一切変わらない。
    private func accessibilityGrid(pad: CGFloat, spacing: CGFloat) -> some View {
        let size = model.board.size
        let dead = model.endgame?.dead ?? []
        return VStack(spacing: 0) {
            ForEach(0..<size, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<size, id: \.self) { col in
                        Button {
                            model.tap(row: row, col: col)
                        } label: {
                            Color.clear.frame(width: spacing, height: spacing)
                        }
                        .disabled(model.phase != .playing || model.isAITurn)
                        .accessibilityLabel(GoAccessibility.pointLabel(
                            row: row,
                            col: col,
                            stone: model.board[row, col],
                            isLastMove: model.lastMove == GoPoint(row: row, col: col),
                            isDead: dead.contains(GoPoint(row: row, col: col))
                        ))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(x: pad - spacing / 2, y: pad - spacing / 2)
    }

    // MARK: - 手番の行

    private func stoneRow(stone: GoStone, isYou: Bool) -> some View {
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
            Text(stone == .black ? "黒・先番" : "白・後番")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            Spacer()
            Text("取った石 \(stone == model.humanSide ? model.capturedByHuman : model.capturedByCPU)")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.inkSub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 30)
        .padding(.horizontal, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - ステータスバー

    private var statusBar: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .finished:
                Label(resultText, systemImage: "flag.checkered")
                    .themeBody(16).foregroundStyle(Theme.coral)
                    .lineLimit(1).minimumScaleFactor(0.7)
            case .scoring:
                Label("終局の確認", systemImage: "list.bullet.clipboard")
                    .themeBody(15).foregroundStyle(Theme.inkSub)
                    .lineLimit(1).minimumScaleFactor(0.7)
            case .playing:
                let isMine = model.state.sideToMove == model.humanSide
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
                RecordLabel(model.recordResult)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("\(model.moveCount)手").themeBody(13).foregroundStyle(Theme.inkSub)
        }
        .frame(minHeight: 32)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(GoAccessibility.statusLabel(
            phase: model.phase,
            isHumanTurn: model.state.sideToMove == model.humanSide,
            capturedByHuman: model.capturedByHuman,
            capturedByCPU: model.capturedByCPU,
            result: model.phase == .playing ? nil : model.endgame?.score.summary ?? resultText
        ))
    }

    private var resultText: String {
        guard let winner = model.winner else { return "引き分け" }
        return winner == model.humanSide ? "あなたの勝ち！" : "CPUの勝ち"
    }

    private var gameControls: some View {
        HStack(spacing: 12) {
            Button { showResignConfirm = true } label: {
                Label("投了", systemImage: "flag.fill")
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Fill.coral))
            }
            .confirmationDialog("投了しますか？", isPresented: $showResignConfirm, titleVisibility: .visible) {
                Button("投了する", role: .destructive) { model.resign() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("現在の対局を終了します。CPUの勝ちになります。")
            }

            Spacer(minLength: 0)

            Button { model.pass() } label: {
                Label("パス", systemImage: "forward.fill")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.fillMuted))
            }
            .disabled(model.isAITurn || model.isThinking)

            Spacer(minLength: 0)

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
        .padding(.horizontal, 12).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - Board Canvas

/// 盤（格子・星・石・死に石の印）の描画。
///
/// `revealedMoves` は「何手目まで現れているか」を実数で持つ。`moveCount` が n-1 → n へ
/// 変わるとき SwiftUI がこの値を補間するので、直前手の石がスケールしながら現れる。
/// `Canvas` はビュー本体が作り直されない限り描き直されないため `Animatable` に適合させている
/// （#202 と同じ理由。Reduce Motion が ON なら `.gameAnimation` が補間ごと落とす）。
private struct GoBoardCanvas: View, Animatable {
    nonisolated let board: GoBoard
    nonisolated let lastMove: GoPoint?
    nonisolated let dead: Set<GoPoint>
    nonisolated let moveCount: Int
    nonisolated let pad: CGFloat
    nonisolated var revealedMoves: Double

    nonisolated var animatableData: Double {
        get { revealedMoves }
        set { revealedMoves = newValue }
    }

    /// 直前手の石が現れきったか（0→1）。「待った」で手数が減る向きではクランプする。
    private var placementProgress: Double {
        guard moveCount > 0 else { return 1 }
        return min(max(revealedMoves - Double(moveCount - 1), 0), 1)
    }

    /// 星の位置（9路は四隅の三々 4 つ + 天元）。
    private var starPoints: [GoPoint] {
        let size = board.size
        guard size >= 7 else { return [] }
        let star = size == 9 ? 2 : 3
        let far = size - 1 - star
        let centre = size / 2
        var points = [
            GoPoint(row: star, col: star), GoPoint(row: star, col: far),
            GoPoint(row: far, col: star), GoPoint(row: far, col: far),
        ]
        if size % 2 == 1 { points.append(GoPoint(row: centre, col: centre)) }
        return points
    }

    var body: some View {
        let progress = placementProgress
        let size = board.size
        Canvas { ctx, canvasSize in
            let s = (canvasSize.width - pad * 2) / CGFloat(size - 1)
            let lineColor = GraphicsContext.Shading.color(Color(hex: 0x7A5810).opacity(0.55))

            // 格子線
            for i in 0..<size {
                let x = pad + CGFloat(i) * s
                let y = pad + CGFloat(i) * s
                var vertical = Path()
                vertical.move(to: CGPoint(x: x, y: pad))
                vertical.addLine(to: CGPoint(x: x, y: canvasSize.height - pad))
                ctx.stroke(vertical, with: lineColor, lineWidth: 0.9)

                var horizontal = Path()
                horizontal.move(to: CGPoint(x: pad, y: y))
                horizontal.addLine(to: CGPoint(x: canvasSize.width - pad, y: y))
                ctx.stroke(horizontal, with: lineColor, lineWidth: 0.9)
            }

            // 星
            let dotColor = GraphicsContext.Shading.color(Color(hex: 0x7A5810).opacity(0.75))
            for point in starPoints {
                let cx = pad + CGFloat(point.col) * s
                let cy = pad + CGFloat(point.row) * s
                let r: CGFloat = 3
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                         with: dotColor)
            }

            // 石
            for row in 0..<size {
                for col in 0..<size {
                    let point = GoPoint(row: row, col: col)
                    guard let stone = board[point] else { continue }
                    let isLast = lastMove == point
                    let appear = isLast ? progress : 1
                    guard appear > 0 else { continue }

                    let cx = pad + CGFloat(col) * s
                    let cy = pad + CGFloat(row) * s
                    let r = s * 0.47 * (0.55 + 0.45 * appear)
                    let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                    let path = Path(ellipseIn: rect)

                    var layer = ctx
                    layer.opacity = appear * (dead.contains(point) ? 0.45 : 1)
                    // 碁石はドーム（半球）: 左上寄りのラジアルの照り + 落ち影（#366・#398 流用資産）。
                    // 五目並べ（GomokuBoardCanvas）と同じ描き方で、質感を共通にする。
                    layer.addFilter(.shadow(
                        color: .black.opacity(0.30),
                        radius: s * 0.09,
                        x: 0, y: s * 0.07))

                    let highlight = CGPoint(x: cx - r * 0.35, y: cy - r * 0.4)
                    if stone == .black {
                        layer.fill(path, with: .radialGradient(
                            Gradient(colors: [Color(hex: 0x3E3A34), Color(hex: 0x0C0A07)]),
                            center: highlight, startRadius: 0, endRadius: r * 1.5))
                    } else {
                        layer.fill(path, with: .radialGradient(
                            Gradient(colors: [Color(hex: 0xFFFCF0), Color(hex: 0xD9D2B8)]),
                            center: highlight, startRadius: 0, endRadius: r * 1.7))
                        layer.stroke(path, with: .color(Color.gray.opacity(0.4)), lineWidth: 1)
                    }

                    // 死に石には × 印。薄くするだけでは白石で見分けがつかない。
                    if dead.contains(point) {
                        var cross = Path()
                        let d = r * 0.55
                        cross.move(to: CGPoint(x: cx - d, y: cy - d))
                        cross.addLine(to: CGPoint(x: cx + d, y: cy + d))
                        cross.move(to: CGPoint(x: cx + d, y: cy - d))
                        cross.addLine(to: CGPoint(x: cx - d, y: cy + d))
                        ctx.stroke(cross, with: .color(Theme.coral), lineWidth: 2)
                    }

                    // 直前手マーカー（#202 と同じ、外周のリング + 中央のドット）。
                    // 石の落ち影フィルタを継がないよう、影なしの複製に描く（五目 #368 と同じ）。
                    if isLast {
                        var markerLayer = ctx
                        markerLayer.opacity = appear

                        let ring = rect.insetBy(dx: -2, dy: -2)
                        markerLayer.stroke(Path(ellipseIn: ring), with: .color(Theme.coral), lineWidth: 2.4)

                        let mr = r * 0.34
                        let markerRect = CGRect(x: cx - mr, y: cy - mr, width: mr * 2, height: mr * 2)
                        markerLayer.fill(Path(ellipseIn: markerRect),
                                   with: .color(stone == .black ? Color.white.opacity(0.9)
                                                                : Color(hex: 0x2A1600).opacity(0.75)))
                    }
                }
            }
        }
    }
}

// MARK: - 無効操作の震え

/// 打てないタップを伝える盤の横揺れ（#202 の横展開）。
private struct GoShake: GeometryEffect {
    var amount: CGFloat = 5
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: amount * sin(animatableData * .pi * 2 * shakes), y: 0)
        )
    }
}

// MARK: - くわしいルール

/// 遊び方シートの「くわしいルール」。3 行に収まらない終局まわりをここへ逃がす（#118 の規約）。
struct GoRuleDetails: View {
    private let sections: [(String, [String])] = [
        ("石を取る", [
            "たて・よこにつながった自分の石のまわりの空点を「呼吸点」と呼びます。",
            "相手の石の呼吸点をすべて埋めると、その石を取り上げられます。",
            "自分の呼吸点が無くなる場所には打てません（ただし、その手で相手を取れるなら打てます）。",
        ]),
        ("コウ", [
            "取り返すと同じ形がくり返される場所は、すぐには打ち返せません。",
            "一度よそに打ってからなら打てます。同じ盤面が何度も現れる手も禁止です。",
        ]),
        ("終局と勝ち負け", [
            "打つところが無くなったら「パス」します。両者が続けてパスすると終局です。",
            "数え方は中国ルール（面積計算）。盤上の自分の石と、自分だけが囲んでいる空点の合計で競います。",
            "白にはコミ 6.5 目が加算されます（置き石ありの対局はコミ 0.5 目 + 置き石 1 子につき 1 目）。",
            "終局の画面では、死んでいる石に × が付きます。判定に納得できなければ「対局続行」で打ち続けられます。",
        ]),
    ]

    var body: some View {
        // 他ゲームのルールシート（大富豪・ポーカー）と同じ包み: スクロール + 左右余白 + 共通背景
        // （会長指摘 2026-09-02: 全面白地・余白なしで見た目が他と違う）。
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sections, id: \.0) { title, lines in
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).themeBody(15).foregroundStyle(Theme.coral)
                    ForEach(lines, id: \.self) { line in
                        Text("・\(line)")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.pad)
        }
        .popBackground()
    }
}

// MARK: - 新規対局シート

struct GoNewGameSheet: View {
    @State private var side: GoStone
    @State private var level: GoLevel
    @State private var handicap: Int
    let onStart: (GoStone, GoLevel, Int) -> Void
    let onCancel: () -> Void

    init(
        humanSide: GoStone,
        level: GoLevel,
        handicap: Int,
        onStart: @escaping (GoStone, GoLevel, Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _side = State(initialValue: humanSide)
        _level = State(initialValue: level)
        _handicap = State(initialValue: handicap)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("9路盤・中国ルール（面積計算）")
                        .themeBody(13).foregroundStyle(Theme.inkSub)

                    section("あなたの石") {
                        HStack(spacing: 12) {
                            chooser(title: "●黒", subtitle: "先番",
                                    selected: side == .black, accent: Theme.fillStrong,
                                    onAccent: .white) { side = .black }
                            chooser(title: "○白", subtitle: "後番",
                                    selected: side == .white, accent: Theme.fillMuted,
                                    onAccent: .white) { side = .white }
                        }
                    }
                    section("CPUの強さ") {
                        HStack(spacing: 12) {
                            ForEach(GoLevel.allCases, id: \.self) { candidate in
                                chooser(title: candidate.label, subtitle: candidate.detail,
                                        selected: level == candidate,
                                        accent: accent(for: candidate)) { level = candidate }
                            }
                        }
                    }
                    // 置き石は黒（人間）がハンデをもらう仕組みなので、白を選んだときは出さない。
                    if side == .black {
                        section("置き石（ハンデ）") {
                            HStack(spacing: 8) {
                                ForEach(GoRuleset.handicapChoices, id: \.self) { count in
                                    chooser(title: count == 0 ? "互先" : "\(count)子",
                                            subtitle: count == 0 ? "コミ6.5" : "コミ0.5",
                                            selected: handicap == count,
                                            accent: Theme.Fill.purple) { handicap = count }
                                }
                            }
                        }
                    }

                    Button { onStart(side, level, side == .black ? handicap : 0) } label: {
                        Text("対局開始").themeBody(18).frame(maxWidth: .infinity)
                        .foregroundStyle(Theme.onAccent)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
                }
                .padding(Theme.pad)
            }
            .popBackground()
            .navigationTitle("新規対局")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
            }
        }
        // 選択肢3節 + 置き石の条件節で .medium には収まらない（会長指摘 2026-09-02:
        // ハンデ以降がはみ出て操作できない）。このシートだけ常に .large で開く。
        .presentationDetents([.large])
    }

    private func accent(for level: GoLevel) -> Color {
        switch level {
        case .easy:   return Theme.Fill.teal
        case .normal: return Theme.Fill.yellow
        case .hard:   return Theme.Fill.coral
        }
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).themeBody(15).foregroundStyle(Theme.inkSub)
            content()
        }
    }

    /// - Parameter onAccent: 選択中（＝面が `accent` で塗られている状態）の文字色。
    ///   差し色の面には `Theme.onAccent`、`fillStrong` / `fillMuted` のような濃い面には白を渡す（#220）。
    private func chooser(title: String, subtitle: String,
                         selected: Bool, accent: Color, onAccent: Color = Theme.onAccent,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).themeTitle(20).foregroundStyle(selected ? onAccent : Theme.ink)
                Text(subtitle).font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? onAccent : Theme.inkSub)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(selected ? accent : Theme.surface)
                    .shadow(color: .black.opacity(selected ? 0.15 : 0.06), radius: 6, y: 3)
            )
        }
        .buttonStyle(.plain)
    }
}
