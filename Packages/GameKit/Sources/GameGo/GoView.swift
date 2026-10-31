import SwiftUI
import Foundation
import Core

public struct GoView: View {
    @State private var model: GoModel
    private let services: GameServices
    @State private var showNewGame: Bool
    @State private var showConfirmNewGame = false
    /// 「待った」のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var undoRescue = RewardedRescue()
    /// 「ヒント」のリワード広告の段取り（#2027）。
    @State private var hintRescue = RewardedRescue()
    /// 出ている「パス」の札（#664）。モデルの `passEventID` をそのまま入れ、一定時間後に nil へ戻す。
    @State private var passBannerID: Int?
    /// 結果カードを閉じたか（#1753）。新しい対局が始まる（`gameOver` が偽に戻る）とリセットする。
    @State private var resultCardClosed = false

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
                .boardGameResultCard(isPresented: model.gameOver && !resultCardClosed) { resultCard }
            stoneRow(stone: model.humanSide, isYou: true)
            controlArea
            HowToPlayHint(.go, playLog: services.playLog)
            // 余りの高さは「⋯」の行と広告のあいだに置く（盤→「⋯」→余白→広告・#1485）。
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.none, value: model.phase)
        .onChange(of: model.gameOver) { _, over in
            if !over { resultCardClosed = false }
        }
        .padding(Theme.pad)
        .gameChrome(title: tr("囲碁"), review: services.review,
                    condition: GameChromeCondition(conditionParts),
                    newGame: GameChromeNewGame(.match) { requestNewGame() })
        .howToPlay(HowToPlayGuide.go.illustrated(GoHowToFigures.items).onboarding(GoOnboarding.guide)) { GoRuleDetails() }
        .sheet(isPresented: $showNewGame, onDismiss: { model.startPlayIfPending() }) {
            GoNewGameSheet(
                humanSide: model.humanSide,
                level: model.aiLevel,
                handicap: model.ruleset.handicap,
                boardSize: model.boardSize
            ) { side, level, handicap, boardSize in
                model.newGame(humanSide: side, level: level, handicap: handicap, boardSize: boardSize)
                showNewGame = false
            } onCancel: { showNewGame = false }
        }
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規対局しますか？"), isPresented: $showConfirmNewGame, titleVisibility: .visible) {
                Button(tr("終了して新規対局"), role: .destructive) { showNewGame = true }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると対局データが失われます。"))
            }
        }
        .task(id: model.aiTurnKey) {
            await model.performAIMoveIfNeeded()
        }
        // CPU の着手・パスを読み上げる（#2280）。パスは `lastMove` が nil になる。
        .cpuMoveAnnouncement(key: model.aiTurnKey, cpuMoveKey: model.lastCPUMoveKey) {
            GoAccessibility.cpuMoveAnnouncement(point: model.lastMove)
        }
        .task(id: model.phase) {
            await model.evaluateEndgameIfNeeded()
        }
        // パスした瞬間だけ札を出し、少し置いて引っ込める（#664・将棋 #377 と同じ機構）。
        //
        // 引っ込めるのは**自分が出した札がまだ出ているときだけ**にする。`.task(id:)` は
        // 契機が変わると古いタスクを取り消すが、`Task.sleep` の `CancellationError` は
        // `try?` が飲み込むので古いタスクは最後まで走る。素朴に nil を書くと、続けて
        // 相手もパスしたときに**古い後始末が新しい札を消す**（将棋・チェスで既知・#519）。
        .task(id: model.passEventID) {
            let id = model.passEventID
            guard id > 0 else { return }
            passBannerID = id
            try? await Task.sleep(for: .seconds(passBannerHold))
            if passBannerID == id { passBannerID = nil }
        }
        // 待った・新規対局・投了・対局続行・終局の確定で盤の意味が変わったら、
        // 上の固定待ちを待たずに札を畳む（#519 と同じ手当て）。
        .onChange(of: model.passBannerDismissID) { _, _ in
            passBannerID = nil
        }
        // 最善手がパスのときは文字の帯だけが手がかりなので、VoiceOver にも読ませる（#2027）。
        .onChange(of: model.hintSuggestsPass) { _, suggests in
            if suggests { AccessibilityNotification.Announcement(GoAccessibility.hintPassMessage).post() }
        }
        .task {
            #if DEBUG
            // 撮影用（#2360）: 終局後レイアウト（「もう一回」の段）を即再現する（将棋・チェスの -xxxAutoResign と同じ）。
            if ProcessInfo.processInfo.arguments.contains("-goAutoResign") {
                model.resign()
                showNewGame = false   // 中断データが無い起動では開始シートが結果を隠す（CodeRabbit 指摘）
            }
            // 撮影用（#398）: 中盤風の盤面を機械的に作る。人間の手番で止まるので CPU は動かない。
            if ProcessInfo.processInfo.arguments.contains("-goScoring") {
                await model.applyPreviewScoringForTesting()
            } else if ProcessInfo.processInfo.arguments.contains("-goMidgame") {
                model.applyPreviewMidgameForTesting()
                // 撮影用（#2027）: 中盤の盤面でヒントを 1 回読ませて、紫の印を出す。
                if ProcessInfo.processInfo.arguments.contains("-goHint") {
                    showNewGame = false
                    await model.requestHint()
                }
            }
            #endif
        }
    }

    /// 新規対局の入口（ヘッダーの「新規」と条件のチップが共通で呼ぶ・#1690）。
    private func requestNewGame() {
        if model.gameOver || model.moveCount == 0 {
            showNewGame = true
        } else {
            showConfirmNewGame = true
        }
    }

    /// タイトルの下のチップに出す今の条件。強さ → 自分の石 → 置き石（ハンデがあるときだけ）。
    private var conditionParts: [String] {
        var parts = [model.aiLevel.label, model.humanSide == .black ? tr("黒・先番") : tr("白・後番")]
        if model.boardSize != .nine { parts.append(model.boardSize.label) }
        if model.ruleset.handicap > 0 { parts.append(tr("%lld子", model.ruleset.handicap)) }
        return parts
    }

    // MARK: - 盤の下の操作エリア

    /// 対局中（投了・パス・待った）と終局後（もう一度・レコメンド）で中身が入れ替わるが、
    /// **高さは常に終局後の最大構成に揃える**（#148 の横展開）。
    /// 対局中（パス・投了）/ 死活確認中 / 終局後（もう一回）で中身が入れ替わる。終局後の段（`GameReplayBar`・60pt・#2360）が
    /// 対局中の操作列（46pt）より高いので、最低の高さを終局後の段に揃えて決着で盤が縮まないようにする（#139）。
    /// レコメンドの常時高さ予約は盤を狭くしていたため撤廃し、盤の下端へのオーバーレイに移した（将棋 #405 と同じ手当て。
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
        .frame(minHeight: GameReplayBarMetrics.cardHeight)
    }

    private var resultControls: some View {
        GameReplayBar(
            onReplay: {
                model.newGame(humanSide: model.humanSide, level: model.aiLevel, handicap: model.ruleset.handicap, boardSize: model.boardSize)
            },
            onChangeSettings: { showNewGame = true }
        )
    }

    /// 両者パスのあとの確認。**ここで結果を承認するまで成績は記録しない**ので、
    /// 簡易死活の判定が怪しければ「対局続行」で戻れる（#398）。
    private var scoringControls: some View {
        VStack(spacing: 6) {
            if model.endgame == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(tr("終局の計算中…")).themeBody(13).foregroundStyle(Theme.inkSubText)
                }
                .frame(maxWidth: .infinity)
            } else if let endgame = model.endgame {
                Text(endgame.score.summary)
                    .themeBody(16).foregroundStyle(Theme.coralText)
                Text(tr("黒 %1$lld 目 / 白 %2$lld 目 + コミ %3$@", endgame.score.blackArea, endgame.score.whiteArea, komiText(endgame.score)))
                    .themeBody(12).foregroundStyle(Theme.inkSubText)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if endgame.isUncertain {
                    Label(tr("死活の判定があいまいです。続けて打って決着させることもできます。"),
                          systemImage: "exclamationmark.triangle.fill")
                        .themeBody(11).foregroundStyle(Theme.inkSubText)
                        .multilineTextAlignment(.leading)
                }
            }
            HStack(spacing: 12) {
                Button { model.resumePlay() } label: {
                    Label(tr("対局続行"), systemImage: "arrow.uturn.backward")
                        .frame(minHeight: GameButtonMetrics.minTapTarget)
                        .contentShape(Rectangle())
                }
                Spacer(minLength: 0)
                Button { model.acceptEndgame() } label: {
                    Text(tr("この結果で終局"))
                }
                .buttonStyle(.game(.primary))
                .disabled(model.endgame == nil)
            }
            .themeBody(14)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
    }

    /// 終局の結果カード（#1753）。確定後は目数の内訳（黒・白・コミ）を残す。投了には内訳が無い。
    @ViewBuilder
    private var resultCard: some View {
        if model.gameOver {
            let verdict: BoardGameResultCard.Verdict = model.winner == nil ? .draw
                : (model.winner == model.humanSide ? .win : .loss)
            if let score = model.endgame?.score {
                BoardGameResultCard(
                    verdict: verdict,
                    reason: score.summary,
                    details: [tr("黒 %1$lld 目 / 白 %2$lld 目 + コミ %3$@", score.blackArea, score.whiteArea, komiText(score)),
                              tr("%lld手", model.moveCount)],
                    record: model.recordResult
                ) { resultCardClosed = true }
            } else {
                BoardGameResultCard(verdict: verdict, reason: tr("投了"), details: [tr("%lld手", model.moveCount)],
                                    record: model.recordResult) {
                    resultCardClosed = true
                }
            }
        }
    }

    private func komiText(_ score: GoScore) -> String {
        let total = score.komi + Double(score.handicapCompensation)
        return total == total.rounded() ? String(Int(total)) : String(format: "%.1f", total)
    }

    // MARK: - Board

    private var board: some View {
        GeometryReader { geo in
            let size = model.board.size
            // 余白は間隔に比例させる（9 路で縁の石が角丸からはみ出していた・`GoBoardMetrics`）。
            let pad = GoBoardMetrics.pad(boardWidth: geo.size.width, size: size)
            let spacing = GoBoardMetrics.spacing(boardWidth: geo.size.width, size: size)

            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(hex: 0xDEB568))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 6)

                GoBoardCanvas(
                    board: model.board,
                    lastMove: model.lastMove,
                    dead: model.endgame?.dead ?? [],
                    territory: model.endgame?.territory ?? [],
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

                // ヒントが示す交点（#2027）。盤の前面に重ねるので、タップと VoiceOver の
                // 交点グリッドを横取りしないよう両方から外す。
                hintMark(pad: pad, spacing: spacing)
            }
            // 打てないタップを盤の横揺れで伝える（#202）。触覚・効果音は Model 側から鳴る。
            .modifier(GoShake(animatableData: CGFloat(model.rejectedTapCount)))
            .gameAnimation(.linear(duration: 0.32), value: model.rejectedTapCount)
            // 拒否の理由は揺れの外に置く（一緒に揺らすと読めない・五目 #441 と同じ組み方）。
            .overlay(alignment: .top) { rejectionNotice }
            // 最善手がパスのときは印を置く交点が無いので、文字で示す（#2027）。
            .overlay(alignment: .bottom) { hintPassNotice }
        }
        .aspectRatio(1, contentMode: .fit)
        // 終局後のレコメンドは盤の下端に重ねる（常時高さ予約の代替。将棋 #405 と同じ）。
        .overlay(alignment: .bottom) {
            if model.phase == .finished {
                RecommendationSlot(services: services, isFinished: true, ladder: ladder)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
    }

    /// 勝ちが続いたら一段上の強さを勧める（#722）。石の色と置き石は今の対局のものを引き継ぐ。
    private var ladder: DifficultyLadderPrompt? {
        let levels = GoLevel.allCases
        return DifficultyLadderPrompt(result: model.recordResult, currentLevel: levels.firstIndex(of: model.aiLevel),
                                      levelLabels: levels.map(\.label)) { level in
            model.newGame(humanSide: model.humanSide, level: levels[level], handicap: model.ruleset.handicap, boardSize: model.boardSize)
        }
    }

    /// ヒントが示す交点の印（#2027）。次に打つと良い 1 点を紫の輪で囲む。
    ///
    /// 出す条件は `model.hintPoint` だけで、盤が動けば Model 側が印を落とす。
    /// 色は将棋・チェス・五目並べと共通（`BoardGameHintColor`）。読み上げは VoiceOver 用の交点グリッド
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

    /// 最善手がパスのときの案内（#2027）。盤に印を置けないので帯で伝える。
    /// 拒否理由の帯（上端）と重ならないよう下端に出す。盤への `overlay` なので、出ても消えても盤と操作エリアの高さは変わらない。
    @ViewBuilder
    private var hintPassNotice: some View {
        if model.hintSuggestsPass {
            Text(GoAccessibility.hintPassMessage)
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(BoardGameHintColor.color))
                .padding(.bottom, 10)
                .allowsHitTesting(false)
        }
    }

    /// 打てなかった理由を盤の上に出す（#664。五目の `forbiddenNotice` #441 と同じ組み方）。
    ///
    /// 自殺手・コウは**空いている交点なのに石が入らない**ので、震え（#202）と警告音だけでは
    /// 「なぜ打てないのか」が伝わらない。理由の文言は `GoTapRejection.message` に定義済みで、
    /// ここが初めての参照箇所になる。次に打てたら `apply` が `lastRejection` を消すので
    /// 自然に引っ込む。盤への `overlay` なので、出ても消えても盤と操作エリアの高さは変わらない。
    @ViewBuilder
    private var rejectionNotice: some View {
        if let rejection = model.lastRejection {
            Text(rejection.message)
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Theme.Fill.coral))
                .padding(.top, 10)
                // 帯は盤より前面なので、既定のままだと重なった交点へのタップを吸ってしまう。
                // 見せるだけの表示なので当たり判定から外す。
                .allowsHitTesting(false)
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
                            stone: model.board.stone(row: row, col: col),
                            isLastMove: model.lastMove == GoPoint(row: row, col: col),
                            isDead: dead.contains(GoPoint(row: row, col: col)),
                            isHint: model.hintPoint == GoPoint(row: row, col: col)
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
            Text(isYou ? tr("あなた") : "CPU")
                .scaledFont(13, weight: .bold, design: .rounded)
                .foregroundStyle(isYou ? Theme.tealText : Theme.inkSubText)
            Text(stone == .black ? tr("黒・先番") : tr("白・後番"))
                .scaledFont(13, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
            Spacer()
            Text(tr("取った石 %lld", stone == model.humanSide ? model.capturedByHuman : model.capturedByCPU))
                .scaledFont(12, design: .rounded)
                .foregroundStyle(Theme.inkSubText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 30)
        .padding(.horizontal, 12)
        .popCard(corner: Theme.cornerSmall)
    }

    // MARK: - ステータスバー

    private var statusBar: some View {
        GameStatusBar {
            switch model.phase {
            case .finished:
                Label(resultVerdict.title, systemImage: resultVerdict.bandSymbol)
                    .themeBody(16).foregroundStyle(Theme.coralText)
                    .lineLimit(1).minimumScaleFactor(0.7)
            case .scoring:
                Label(tr("終局の確認"), systemImage: "list.bullet.clipboard")
                    .themeBody(15).foregroundStyle(Theme.inkSubText)
                    .lineLimit(1).minimumScaleFactor(0.7)
            case .playing:
                TurnBadge(isYourTurn: model.state.sideToMove == model.humanSide)
                if model.isThinking {
                    ProgressView().controlSize(.small)
                    Text(tr("CPU思考中…")).themeBody(13).foregroundStyle(Theme.inkSubText)
                }
            }
            passBanner
        } trailing: {
            if model.gameOver {
                RecordLabel(model.recordResult)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(tr("%lld手", model.moveCount)).themeBody(13).foregroundStyle(Theme.inkSubText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(GoAccessibility.statusLabel(
            phase: model.phase,
            isHumanTurn: model.state.sideToMove == model.humanSide,
            capturedByHuman: model.capturedByHuman,
            capturedByCPU: model.capturedByCPU,
            result: model.phase == .playing ? nil : model.endgame?.score.summary ?? resultVerdict.title
        ))
    }

    /// 「パス」の札を出しておく時間（#664）。将棋・チェスの王手札（#377）と同じ
    /// 「盤が動かない合図を一定時間だけ出す」機構なので、尺もその値をそのまま借りる。
    private var passBannerHold: TimeInterval { BoardGameMotion.checkBannerHold }

    /// パスの合図（#664）。盤も手番バッジも動かないパスで、唯一「何かが起きた」を示す要素。
    ///
    /// 分岐は**この層の中**に置く（将棋 #201 と同じ）。呼び出し側の `if` にすると、
    /// 出入りする枝と一緒に修飾子まで消えて `.transition` が効かない。
    /// 読み上げは持たせない — 1 秒あまりで消える要素に VoiceOver のフォーカスが乗ると、
    /// 消えた瞬間にフォーカスごと飛ぶ（将棋の王手札と同じ判断）。
    ///
    /// 面色は**パスボタンと同じ** `Theme.fillMuted`。将棋の王手札の緋色
    /// （`BoardGameCheckColor`）は危急の合図の色で、この画面には投了ボタンと拒否理由の帯という
    /// 赤系がすでに 2 つある。パスは危急ではないので、押した相手（ボタン）と同じ色にして
    /// 「押したものの結果」と読めるようにする。
    private var passBanner: some View {
        ZStack {
            if passBannerID != nil {
                Text(tr("パス"))
                    .scaledFont(13, weight: .bold, design: .rounded)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.fillMuted))
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .gameAnimation(BoardGameMotion.checkBanner, value: passBannerID)
    }

    private var resultVerdict: BoardGameResultCard.Verdict {
        guard let winner = model.winner else { return .draw }
        return winner == model.humanSide ? .win : .loss
    }

    private var gameControls: some View {
        // 待った・「⋯」（投了）の並びは盤ゲーム 5 本で共通。囲碁だけ「パス」も「⋯」に入る（#1421・#1468）。
        BoardGameControlBar(
            model: model, services: services, rescue: undoRescue,
            hint: BoardControlBarHint(model, rescue: hintRescue, game: model.gameSerial, activity: [model.moveCount, model.rejectedTapCount]),
            extraItems: [
                GameControlMenuItem(id: "pass", title: tr("パス"), systemImage: "forward.fill",
                                    isEnabled: !(model.isAITurn || model.isThinking)) { model.pass() }
            ],
            onResign: { model.resign() }
        )
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
    /// 終局時の地の持ち主（空なら色分けしない）。
    nonisolated let territory: [GoStone?]
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

            // 地（終局のとき）: 黒地は黒、白地は白の小さな角丸。石より先に描いて死に石の下にも敷く。
            if territory.count == size * size {
                let half = s * 0.19
                for row in 0..<size {
                    for col in 0..<size {
                        guard let owner = territory[row * size + col] else { continue }
                        let cx = pad + CGFloat(col) * s
                        let cy = pad + CGFloat(row) * s
                        let rect = CGRect(x: cx - half, y: cy - half, width: half * 2, height: half * 2)
                        let mark = Path(roundedRect: rect, cornerRadius: half * 0.3)
                        if owner == .black {
                            ctx.fill(mark, with: .color(Color(hex: 0x1C1812).opacity(0.85)))
                        } else {
                            ctx.fill(mark, with: .color(Color(hex: 0xFFFCF0)))
                            ctx.stroke(mark, with: .color(Color(hex: 0x7A5810).opacity(0.7)), lineWidth: 1)
                        }
                    }
                }
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
                    let r = s * GoBoardMetrics.stoneRadiusRatio * (0.55 + 0.45 * appear)
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
    // `body` の中で引く（表示言語の切り替えで描き直されるように・#2169）。
    private var sections: [(String, [String])] { [
        (tr("石を取る"), [
            tr("たて・よこにつながった自分の石のまわりの空点を「呼吸点」と呼びます。"),
            tr("相手の石の呼吸点をすべて埋めると、その石を取り上げられます。"),
            tr("自分の呼吸点が無くなる場所には打てません（ただし、その手で相手を取れるなら打てます）。"),
        ]),
        (tr("コウ"), [
            tr("取り返すと同じ形がくり返される場所は、すぐには打ち返せません。"),
            tr("一度よそに打ってからなら打てます。同じ盤面が何度も現れる手も禁止です。"),
        ]),
        (tr("終局と勝ち負け"), [
            tr("打つところが無くなったら「パス」します。両者が続けてパスすると終局です。"),
            tr("数え方は中国ルール（面積計算）。盤上の自分の石と、自分だけが囲んでいる空点の合計で競います。"),
            tr("白にはコミ 6.5 目が加算されます（置き石ありの対局はコミ 0.5 目 + 置き石 1 子につき 1 目）。"),
            tr("終局の画面では、死んでいる石に × が付きます。判定に納得できなければ「対局続行」で打ち続けられます。"),
        ]),
    ] }

    var body: some View {
        RuleListSheet(rules: sections.map { title, lines in
            (title, lines.map { tr("・%@", $0) }.joined(separator: "\n"))
        })
    }
}

// MARK: - 新規対局シート

struct GoNewGameSheet: View {
    @State private var side: GoStone
    @State private var level: GoLevel
    @State private var handicap: Int
    @State private var boardSize: GoBoardSize
    let onStart: (GoStone, GoLevel, Int, GoBoardSize) -> Void
    let onCancel: () -> Void

    init(
        humanSide: GoStone,
        level: GoLevel,
        handicap: Int,
        boardSize: GoBoardSize,
        onStart: @escaping (GoStone, GoLevel, Int, GoBoardSize) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _side = State(initialValue: humanSide)
        _level = State(initialValue: level)
        _handicap = State(initialValue: handicap)
        _boardSize = State(initialValue: boardSize)
        self.onStart = onStart
        self.onCancel = onCancel
    }

    /// 選択肢が横に3つ並ぶうえ「互先／2子…」と数が多いので、標準より一回り小さく詰める。
    private static let metrics = GameSetupChooser.Metrics(
        title: .title(20), subtitleSize: 11, verticalPadding: 14, subtitleMinimumScale: 0.7
    )

    var body: some View {
        // 選択肢3節 + 置き石の条件節で .medium には収まらない（会長指摘 2026-09-02:
        // ハンデ以降がはみ出て操作できない）。開始シートは共通枠が常に `.large` で開く（#1415）。
        GameSetupSheet(
            kind: .versus, spacing: 20,
            onboarding: GoOnboarding.guide,
            onStart: { onStart(side, level, side == .black ? handicap : 0, boardSize) }, onCancel: onCancel
        ) {
            Text(tr("中国ルール（面積計算）"))
                .themeBody(13).foregroundStyle(Theme.inkSubText)

            GameSetupSection(tr("碁盤の大きさ")) {
                HStack(spacing: 12) {
                    ForEach(GoBoardSize.allCases, id: \.self) { size in
                        GameSetupChooser(title: size.label,
                                         subtitle: size == .nine ? tr("短時間で終わる") : tr("じっくり打つ"),
                                         selected: boardSize == size, accent: Theme.Fill.purple,
                                         metrics: Self.metrics) { boardSize = size }
                    }
                }
            }

            GameSetupSection(tr("あなたの石")) {
                HStack(spacing: 12) {
                    GameSetupChooser(title: tr("●黒"), subtitle: tr("先番"),
                                     selected: side == .black, accent: Theme.fillStrong,
                                     onAccent: .white, metrics: Self.metrics) { side = .black }
                    GameSetupChooser(title: tr("○白"), subtitle: tr("後番"),
                                     selected: side == .white, accent: Theme.fillMuted,
                                     onAccent: .white, metrics: Self.metrics) { side = .white }
                }
            }
            GameSetupSection(tr("CPUの強さ")) {
                CPUStrengthPicker(
                    level: Binding(get: { level.rawValue }, set: { level = GoLevel(rawValue: $0) ?? .normal }),
                    details: GoLevel.allCases.map(\.detail)
                )
            }
            // 置き石は黒（人間）がハンデをもらう仕組みなので、白を選んだときは出さない。
            if side == .black {
                GameSetupSection(tr("置き石（ハンデ）")) {
                    HStack(spacing: 8) {
                        ForEach(GoRuleset.handicapChoices, id: \.self) { count in
                            GameSetupChooser(title: count == 0 ? tr("互先") : tr("%lld子", count),
                                             subtitle: count == 0 ? tr("コミ6.5") : tr("コミ0.5"),
                                             selected: handicap == count,
                                             accent: Theme.Fill.purple,
                                             metrics: Self.metrics) { handicap = count }
                        }
                    }
                }
            }
        }
    }
}
