import SwiftUI
import Core

public struct GomokuView: View {
    @State private var model: GomokuModel
    private let services: GameServices
    @State private var showNewGame: Bool
    @State private var showConfirmNewGame = false
    @State private var showUndoConfirm = false
    @State private var showResignConfirm = false
    @State private var showRewardNotEarned = false
    @Environment(\.dismiss) private var dismiss

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
            HowToPlayHint(.gomoku, playLog: services.playLog)
            controlArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .animation(.none, value: model.gameOver)
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
                Text("五目並べ")
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
        .howToPlay(.gomoku)
        .sheet(isPresented: $showNewGame) {
            GomokuNewGameSheet(humanSide: model.humanSide, aiLevel: model.aiLevel) { side, level in
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
        .task(id: model.aiTurnKey) {
            await model.performAIMoveIfNeeded()
        }
    }

    // MARK: - 盤の下の操作エリア

    /// 対局中（投了・待った）と終局後（もう一度・レコメンド）で中身が入れ替わるが、
    /// **高さは常に終局後の最大構成に揃える**（#148）。
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
            resultControls
            recommendation()
        }
    }

    /// 「もう一度」は 1 段にまとめ、対局中の `gameControls` と同じ高さに収める（#148）。
    /// 記録ラベルは行を増やさずステータスバーへ同居させている。
    private var resultControls: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Button { showNewGame = true } label: {
                Label("もう一度", systemImage: "arrow.clockwise")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.coral))
            }
            Spacer(minLength: 0)
        }
        .font(Theme.body(14))
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
                            guard let stone = model.board[row, col] else { continue }
                            let cx = pad + CGFloat(col) * s
                            let cy = pad + CGFloat(row) * s
                            let r  = s * 0.46
                            let rect = CGRect(x: cx - r, y: cy - r, width: r*2, height: r*2)
                            let path = Path(ellipseIn: rect)

                            if stone == .black {
                                ctx.fill(path, with: .color(Color(hex: 0x18140E)))
                            } else {
                                ctx.fill(path, with: .color(Color(hex: 0xF0E8D0)))
                                ctx.stroke(path, with: .color(Color.gray.opacity(0.4)), lineWidth: 1)
                            }

                            // 直前手マーカー
                            if let last = model.lastMove, last.row == row && last.col == col {
                                let mr = r * 0.32
                                let mRect = CGRect(x: cx - mr, y: cy - mr, width: mr*2, height: mr*2)
                                ctx.fill(Path(ellipseIn: mRect),
                                         with: .color(stone == .black ? Color.white.opacity(0.65)
                                                                      : Color(hex: 0x2A1600).opacity(0.4)))
                            }
                        }
                    }
                }
                .gesture(
                    SpatialTapGesture()
                        .onEnded { val in
                            guard !model.gameOver, !model.isAITurn else { return }
                            let col = Int(((val.location.x - pad) / spacing).rounded())
                            let row = Int(((val.location.y - pad) / spacing).rounded())
                            guard row >= 0 && row < gomokuBoardSize,
                                  col >= 0 && col < gomokuBoardSize else { return }
                            model.tap(row: row, col: col)
                        }
                )
                .accessibilityRepresentation {
                    accessibilityGrid(pad: pad, spacing: spacing)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
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
                            guard !model.gameOver, !model.isAITurn else { return }
                            model.tap(row: row, col: col)
                        } label: {
                            Color.clear.frame(width: spacing, height: spacing)
                        }
                        .accessibilityLabel(GomokuAccessibility.pointLabel(
                            row: row,
                            col: col,
                            stone: model.board[row, col],
                            isLastMove: model.lastMove.map { $0.row == row && $0.col == col } ?? false
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
                    .font(Theme.body(16)).foregroundStyle(Theme.coral)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else if model.isDraw {
                Label("引き分け", systemImage: "equal.circle")
                    .font(Theme.body(16)).foregroundStyle(Theme.inkSub)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                let isMine = model.currentStone == model.humanSide
                Text(isMine ? "あなたの番" : "CPUの番")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(isMine ? Theme.teal : Theme.coral))
                if model.isThinking {
                    ProgressView().controlSize(.small)
                    Text("思考中…").font(Theme.body(13)).foregroundStyle(Theme.inkSub)
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
            Text("\(model.moveCount)手").font(Theme.body(13)).foregroundStyle(Theme.inkSub)
        }
        .frame(minHeight: 32)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .popCard(corner: Theme.cornerSmall)
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
        .font(Theme.body(14))
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - New Game Sheet

struct GomokuNewGameSheet: View {
    @State private var side: GomokuStone
    @State private var level: Int
    let onStart: (GomokuStone, Int) -> Void
    let onCancel: () -> Void

    init(humanSide: GomokuStone, aiLevel: Int,
         onStart: @escaping (GomokuStone, Int) -> Void,
         onCancel: @escaping () -> Void) {
        _side  = State(initialValue: humanSide)
        _level = State(initialValue: aiLevel)
        self.onStart  = onStart
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                section("あなたの石") {
                    HStack(spacing: 12) {
                        chooser(title: "●黒", subtitle: "先手",
                                selected: side == .black, accent: Theme.fillStrong) { side = .black }
                        chooser(title: "○白", subtitle: "後手",
                                selected: side == .white, accent: Theme.fillMuted) { side = .white }
                    }
                }
                section("CPUの強さ") {
                    HStack(spacing: 12) {
                        chooser(title: "弱",   subtitle: "1手読み",
                                selected: level == 0, accent: Theme.teal)   { level = 0 }
                        chooser(title: "普通", subtitle: "2手読み",
                                selected: level == 1, accent: Theme.yellow) { level = 1 }
                        chooser(title: "強",   subtitle: "3手読み",
                                selected: level == 2, accent: Theme.coral)  { level = 2 }
                    }
                }
                Spacer()
                Button { onStart(side, level) } label: {
                    Text("対局開始").font(Theme.body(18)).frame(maxWidth: .infinity)
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
        .presentationDetents([.medium, .large])
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.body(15)).foregroundStyle(Theme.inkSub)
            content()
        }
    }

    private func chooser(title: String, subtitle: String,
                         selected: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).font(Theme.title(22)).foregroundStyle(selected ? .white : Theme.ink)
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
