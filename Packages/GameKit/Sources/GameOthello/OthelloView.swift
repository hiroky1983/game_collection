import SwiftUI
import Core

public struct OthelloView: View {
    @State private var model: OthelloModel
    private let services: GameServices
    @State private var showNewGame = false
    @State private var showConfirmNewGame = false
    /// 出ている「パス」の札（#2797）。モデルの `passEventID` をそのまま入れ、一定時間後に nil へ戻す。
    @State private var passBannerID: Int?
    /// 結果カードを閉じたか（#2797）。新しい対局が始まる（`gameOver` が偽に戻る）とリセットする。
    @State private var resultCardClosed = false
    /// 結果カードで数え上げ済みの空きマス数（#2813）。nil は数え終わり（確定スコアを出す）。
    @State private var revealedBonus: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 「待った」のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var undoRescue = RewardedRescue()
    /// ヒントの広告救済（無料枠を使い切った後の1回・#2011）。
    @State private var hintRescue = RewardedRescue()

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
                        if model.gameOver && !resultCardClosed {
                            resultOverlay
                                .transition(.opacity)
                        }
                    }
                    .gameAnimation(
                        .easeOut(duration: OthelloBoardStyle.resultOverlayFadeDuration),
                        value: model.gameOver && !resultCardClosed
                    )
                }
            // 「⋯」の行は盤のすぐ下に付け、盤の下の余りは「⋯」の行と広告のあいだに回す（#1485）。
            controlArea
            HowToPlayHint(.othello, playLog: services.playLog)
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .gameAnimation(.none, value: model.gameOver)
        .onChange(of: model.gameOver) { _, over in
            if !over { resultCardClosed = false }
        }
        .padding(Theme.pad)
        .gameChrome(title: tr("オセロ"), review: services.review,
                    condition: GameChromeCondition([CPUStrength.strength(for: model.aiLevel).label,
                                                    model.humanSide == .black ? tr("先手") : tr("後手")]),
                    newGame: GameChromeNewGame(.match) { requestNewGame() })
        .howToPlay(HowToPlayGuide.othello.illustrated(OthelloHowToFigures.items).onboarding(OthelloOnboarding.guide))
        .sheet(isPresented: $showNewGame) {
            OthelloNewGameSheet(humanSide: model.humanSide, aiLevel: model.aiLevel) { side, level in
                model.newGame(humanSide: side, aiLevel: level)
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
        // 人間側に打てるマスが無いときは、確認を挟まず自動でパスする（#2797。ブロッキングのアラートをやめた）。
        // `initial: true` が要る（#414）。パスが済む前に中断すると `mustPass = true` のまま保存され、
        // 復元後は値が変化しないので 2 引数版 `onChange` は既定では発火しない。
        // パスの手段はここだけなので、発火しないと着手も「待った」も塞がったまま詰む。
        // CPU 側のパスは `performAIMoveIfNeeded` が自分で確定する。
        .onChange(of: model.mustPass, initial: true) { _, newValue in
            guard newValue, !model.isAITurn else { return }
            // 札は文字の合図なので、VoiceOver には同じ内容を読み上げで伝える。
            AccessibilityNotification.Announcement(tr("打てるマスがありません。パスします。")).post()
            model.confirmPass()
        }
        // パスした瞬間だけ札を出し、少し置いて引っ込める（囲碁 #664 と同じ機構）。
        // 引っ込めるのは自分が出した札がまだ出ているときだけ（続けて相手もパスしたとき、
        // 古い後始末が新しい札を消さないため）。
        .task(id: model.passEventID) {
            let id = model.passEventID
            guard id > 0 else { return }
            passBannerID = id
            try? await Task.sleep(for: .seconds(BoardGameMotion.checkBannerHold))
            if passBannerID == id { passBannerID = nil }
        }
        // 待った・新規対局・投了で盤の意味が変わったら、固定時間を待たずに札を畳む。
        .onChange(of: model.passBannerDismissID) { _, _ in
            passBannerID = nil
        }
        .task(id: model.aiTurnKey) {
            await model.performAIMoveIfNeeded()
        }
        // CPU の着手・パスを読み上げる（#2280）。
        .cpuMoveAnnouncement(key: model.aiTurnKey, cpuMoveKey: model.lastCPUMoveKey) {
            OthelloAccessibility.cpuMoveAnnouncement(
                move: model.lastCPUPassed ? nil : model.lastMove,
                black: model.blackScore, white: model.whiteScore)
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
                TurnBadge(tr("終局"), kind: .finished)
            } else {
                TurnBadge(isYourTurn: !model.isAITurn)
                if model.isThinking {
                    ProgressView().controlSize(.small)
                    Text(tr("CPU思考中…")).themeBody(13).foregroundStyle(Theme.inkSubText)
                }
            }
        } trailing: {
            // コンパクトスコア（終局後はリザルトと同じ「残りマス加算」後の数字。#440）
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: 0x1A1A1A))
                    .frame(width: 13, height: 13)
                Text("\(model.blackScore)")
                    .themeBody(15, weight: .black, maxScale: 1.5)
                    .foregroundStyle(Theme.ink)
                Text("–")
                    .themeCaption(13, weight: .semibold, maxScale: 1.5)
                    .foregroundStyle(Theme.inkSubText)
                Text("\(model.whiteScore)")
                    .themeBody(15, weight: .black, maxScale: 1.5)
                    .foregroundStyle(Theme.ink)
                Circle()
                    .fill(Color(hex: 0xF0ECD8))
                    .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
                    .frame(width: 13, height: 13)
            }
            // 黒・白の石は図形なので、どちらの数字かが読み上げに出ない。終局カードと同じ文言で読ませる（#2280）。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(OthelloAccessibility.scoreLabel(black: model.blackScore, white: model.whiteScore))
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

                // ヒントが示す升（#2011）。盤の前面に重ねるので、タップと VoiceOver の升グリッドを
                // 横取りしないよう両方から外す。
                hintMark(cell: cell)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// ヒントが示す升の印。次に置くと良い 1 升を紫の輪で囲む（色は将棋・チェス・五目並べと共通の `BoardGameHintColor`）。
    ///
    /// 出す条件は `model.hintPoint` だけで、盤が動けば Model 側が印を落とす。読み上げは VoiceOver 用の
    /// 升グリッド（`accessibilityGrid` の `isHint`）が持つ。
    @ViewBuilder
    private func hintMark(cell: CGFloat) -> some View {
        if let point = model.hintPoint {
            Circle()
                .stroke(BoardGameHintColor.color, lineWidth: 3)
                .background(Circle().fill(BoardGameHintColor.color.opacity(0.22)))
                .frame(width: cell * 0.8, height: cell * 0.8)
                .position(x: cell * (CGFloat(point.col) + 0.5), y: cell * (CGFloat(point.row) + 0.5))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
                            isLastMove: model.lastMove.map { $0.row == row && $0.col == col } ?? false,
                            isHint: model.hintPoint == OthelloPoint(row: row, col: col)
                        ))
                    }
                }
            }
        }
    }

    // MARK: - Controls

    private var gameControls: some View {
        // 待った・「⋯」（投了・ヒント）の並びは盤ゲーム 5 本で共通（#1421）。
        BoardGameControlBar(
            model: model, services: services, rescue: undoRescue,
            hint: BoardControlBarHint(model, rescue: hintRescue, game: model.gameSerial, activity: [model.turnID]),
            onResign: { model.resign() }
        )
    }

    private var resultOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 12) {
                // 記号・勝敗文・スコアは 1 回で読ませる（RecordLabel は共有ボタンを持つので外に置く・#1716）
                VStack(spacing: 12) {
                    if let w = model.winner {
                        let isWin = w == model.humanSide
                        Image(systemName: isWin ? "trophy.fill" : "flag.fill")
                            .scaledFont(40, maxScale: 1.2)
                            .foregroundStyle(isWin ? Theme.yellowText : Theme.coralText)
                        Text(isWin ? tr("あなたの勝ち！") : tr("CPUの勝ち"))
                            .themeBody(24, weight: .bold)
                            .foregroundStyle(isWin ? Theme.tealText : Theme.coralText)
                    } else {
                        Image(systemName: "equal.circle.fill")
                            .scaledFont(40, maxScale: 1.2)
                            .foregroundStyle(Theme.inkSubText)
                        Text(tr("引き分け"))
                            .themeBody(24, weight: .bold)
                            .foregroundStyle(Theme.inkSubText)
                    }
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: 0x1A1A1A))
                            .frame(width: 22, height: 22)
                        Text("\(shownScore.black)")
                            .themeBody(30, weight: .black)
                            .foregroundStyle(Theme.ink)
                        Text("–")
                            .themeBody(22, weight: .semibold)
                            .foregroundStyle(Theme.inkSubText)
                        Text("\(shownScore.white)")
                            .themeBody(30, weight: .black)
                            .foregroundStyle(Theme.ink)
                        Circle()
                            .fill(Color(hex: 0xF0ECD8))
                            .overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
                            .frame(width: 22, height: 22)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(resultAccessibilityLabel)
                RecordLabel(model.recordResult)
                // 結果を閉じて盤面を見返す（将棋・チェス・囲碁・五目並べの `BoardGameResultCard` と同じ口・#2797）。
                Button { resultCardClosed = true } label: {
                    Text(tr("盤を見る"))
                        .themeBody(15, weight: .bold, maxScale: 1.5)
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Theme.Fill.coral))
                }
                .accessibilityHint(tr("結果を閉じて盤面を見返します"))
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        // 背後の盤へ VoiceOver が移れないようにし、出現を告げる（#2232。`BoardGameResultCard` と同じ形）。
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .announcesResultAppearance(resultAccessibilityLabel)
        .task { await countUpBonus() }
    }

    /// 結果カードに出すスコア。数え上げ中は空きマスを途中まで加算した値（#2813）。
    private var shownScore: (black: Int, white: Int) {
        guard let revealed = revealedBonus else { return (model.blackScore, model.whiteScore) }
        return model.score(revealingBonus: revealed)
    }

    /// 終局の空きマスを 1 マスずつ勝者へ加算して見せる（#2813）。加算が無い終局・Reduce Motion では何もしない。
    /// 全体が 1.5 秒を超えないよう、1 マスあたりの間隔は `bonus` に応じて縮める。
    private func countUpBonus() async {
        let bonus = model.bonusCellCount
        guard bonus > 0, !reduceMotion else { return }
        revealedBonus = 0
        defer { revealedBonus = nil }
        let step = Duration.seconds(min(0.06, 1.5 / Double(bonus)))
        try? await Task.sleep(for: .seconds(OthelloBoardStyle.resultOverlayFadeDuration + 0.2))
        for n in 1...bonus {
            if Task.isCancelled { return }
            revealedBonus = n
            try? await Task.sleep(for: step)
        }
    }

    private var resultAccessibilityLabel: String {
        let verdict: String
        if let w = model.winner {
            verdict = w == model.humanSide ? tr("あなたの勝ち") : tr("CPUの勝ち")
        } else {
            verdict = tr("引き分け")
        }
        return tr("%1$@ 黒 %2$lld 対 白 %3$lld", verdict, model.blackScore, model.whiteScore)
    }

    /// 新規対局の入口（ヘッダーの「新規」と条件のチップが共通で呼ぶ・#1690）。
    private func requestNewGame() {
        if model.hasProgressToLose {
            showConfirmNewGame = true
        } else {
            showNewGame = true
        }
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
        .overlay(alignment: .top) { passBanner }
    }

    /// パスの合図（#2797。囲碁 #664 と同じ札）。盤も手番も動かないパスで、唯一「何かが起きた」を示す要素。
    /// 分岐はこの層の中に置く（呼び出し側の `if` だと `.transition` が効かない）。
    /// 1 秒あまりで消えるので、VoiceOver のフォーカスは乗せない（読み上げは別に出す）。
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

    /// 勝ちが続いたら一段上の強さを勧める（#722）。並びは開始シートの「CPUの強さ」と同じ。
    private var ladder: DifficultyLadderPrompt? {
        DifficultyLadderPrompt(result: model.recordResult,
                               currentLevel: CPUStrength.ladderIndex(forLevel: model.aiLevel),
                               levelLabels: CPUStrength.labels) { index in
            model.newGame(humanSide: model.humanSide,
                          aiLevel: CPUStrength.level(atLadderIndex: index))
        }
    }

    /// 「もう一回」「設定を変える」は対局中の `gameControls` と同じ高さの 1 段に収める（#148）。
    /// 全幅の大ボタンのままだと盤の下が伸び、決着の瞬間に盤が縮む。
    private var newGameButton: some View {
        GameReplayBar(
            onReplay: { model.newGame(humanSide: model.humanSide, aiLevel: model.aiLevel) },
            onChangeSettings: { showNewGame = true }
        )
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
            onboarding: OthelloOnboarding.guide,
            onStart: { onStart(side, level) }, onCancel: onCancel
        ) {
            GameSetupSection(tr("あなたの石")) {
                HStack(spacing: 12) {
                    GameSetupChooser(title: tr("●黒"), subtitle: tr("先手"),
                                     selected: side == .black, accent: Theme.fillStrong,
                                     onAccent: .white) { side = .black }
                    GameSetupChooser(title: tr("○白"), subtitle: tr("後手"),
                                     selected: side == .white, accent: Theme.fillMuted,
                                     onAccent: .white) { side = .white }
                }
            }
            GameSetupSection(tr("CPUの強さ")) {
                // 説明は `OthelloEngine.bestMove` の中身と一致させる（#416）。
                CPUStrengthPicker(level: $level, details: [
                    tr("1手先だけ読む"), tr("3手先まで読む"), tr("5手先まで読む"), tr("終盤は最後まで読む"),
                ])
            }
        }
    }
}
