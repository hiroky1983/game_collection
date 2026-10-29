import SwiftUI
import Core

/// 明かり消しパズルのプレイ画面（#1883）。マスを押すと、そのマスと上下左右の明かりが入れ替わる。
public struct AkariKeshiView: View {
    private let services: GameServices
    @State private var model: AkariKeshiModel
    @State private var showNewGame: Bool
    @State private var showConfirmNewGame = false

    public init(services: GameServices) {
        self.services = services
        let model = AkariKeshiModel(services: services)
        _model = State(initialValue: model)
        // 続きの盤が無ければ、まず難易度を選んでもらう（ナンプレ・マインスイーパーと同じ）。
        _showNewGame = State(initialValue: !model.hasPuzzle)
    }

    public var body: some View {
        VStack(spacing: 8) {
            statusBar
            board
                .layoutPriority(1)
                .gameClearCard(isPresented: model.state == .cleared,
                               details: [tr("%1$@ / %2$lld手（最短%3$lld手） / タイム %4$@",
                                            model.difficulty.label, model.moves, model.par,
                                            RecordFormat.time(model.elapsedSeconds))])
            controlArea
            // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.akariKeshi, playLog: services.playLog)
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .gameChrome(title: tr("明かり消しパズル"), review: services.review,
                    newGame: GameChromeNewGame(.solo) {
                        if model.hasProgressToLose {
                            showConfirmNewGame = true
                        } else {
                            showNewGame = true
                        }
                    })
        .howToPlay(HowToPlayGuide.akariKeshi.illustrated(AkariKeshiHowToFigures.items))
        .sheet(isPresented: $showNewGame) {
            AkariKeshiNewGameSheet(initial: model.difficulty) { difficulty in
                showNewGame = false
                withGameAnimation { model.newGame(difficulty: difficulty) }
            } onCancel: {
                showNewGame = false
            }
        }
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規ゲームを始めますか？"), isPresented: $showConfirmNewGame, titleVisibility: .visible) {
                Button(tr("終了して新規ゲーム"), role: .destructive) { showNewGame = true }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると、いまの盤面と手数が失われます。"))
            }
        }
        // 画面を離れたら・背面に回ったら計時を止め、戻ったら再開する（#375・#1734・#1857）。
        .gameTimerLifecycle(
            isHeld: showNewGame,
            pause: { model.pauseTimer() },
            resume: { model.resumeTimerIfNeeded() }
        )
        .task { model.resumeTimerIfNeeded() }
    }

    // MARK: - 帯

    private var statusBar: some View {
        GameStatusBar {
            Group {
                if model.state == .cleared {
                    Label(tr("クリア！"), systemImage: "checkmark.seal.fill")
                        .themeBody(15)
                        .foregroundStyle(Theme.tealText)
                } else if model.hasPuzzle {
                    Text(tr("手数 %1$lld ／ 最短 %2$lld", model.moves, model.par))
                        .scaledFont(15, weight: .bold, design: .rounded).monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                } else {
                    Text(tr("難易度を選んで始めましょう"))
                        .themeBody(14)
                        .foregroundStyle(Theme.inkSubText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } trailing: {
            GameClockLabel(RecordFormat.time(model.elapsedSeconds), elapsedSeconds: model.elapsedSeconds)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - 盤

    private var board: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let n = AkariKeshiLogic.size
            let side = (geo.size.width - spacing * CGFloat(n + 1)) / CGFloat(n)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.fillMuted)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                VStack(spacing: spacing) {
                    ForEach(0..<n, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<n, id: \.self) { col in
                                cell(row * n + col, side: side)
                            }
                        }
                    }
                }
                if !model.hasPuzzle { idleOverlay }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AkariKeshiAccessibility.boardSummary(litCount: model.litCount))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func cell(_ index: Int, side: CGFloat) -> some View {
        let isLit = model.board[index]
        return AkariKeshiLamp(isLit: isLit, side: side)
            .onTapGesture { withGameAnimation { model.press(at: index) } }
            .gameAnimation(.easeOut(duration: 0.15), value: isLit)
            .accessibilityElement()
            .accessibilityLabel(AkariKeshiAccessibility.cellLabel(index: index, isLit: isLit))
            .accessibilityHint(AkariKeshiAccessibility.cellHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { withGameAnimation { model.press(at: index) } }
            .disabled(model.state != .playing)
    }

    /// 盤がまだ無いとき（開始シートを閉じた直後）に、盤の上から始め直せるようにする。
    private var idleOverlay: some View {
        Button { showNewGame = true } label: {
            Text(tr("はじめる")).foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Fill.coral)
    }

    // MARK: - 盤の下

    private var controlArea: some View {
        GameControlArea(isFinished: model.state == .cleared, services: services, ladder: ladder) {
            GameReplayBar(
                onReplay: { withGameAnimation { model.newGame(difficulty: model.difficulty) } },
                onChangeSettings: { showNewGame = true }
            ) {
                RecordLabel(model.recordResult)
            }
        } playing: {
            EmptyView()
        }
    }

    /// クリアが続いたら一段上の難易度を勧める（#722）。
    private var ladder: DifficultyLadderPrompt? {
        let levels = AkariKeshiDifficulty.allCases
        return DifficultyLadderPrompt(result: model.recordResult, currentLevel: levels.firstIndex(of: model.difficulty),
                                      levelLabels: levels.map(\.label)) { level in
            withGameAnimation { model.newGame(difficulty: levels[level]) }
        }
    }
}

/// 明かり 1 つ。点灯は「黄色の面 + 光る電球」、消灯は「暗い面 + 線だけの電球」で、色だけに頼らず形でも分ける。
struct AkariKeshiLamp: View {
    let isLit: Bool
    let side: CGFloat
    /// 遊び方の図で「ここを押した」を示す枠。
    var isPressed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
        return shape
            .fill(isLit ? Theme.Fill.yellow : Theme.ink.opacity(0.55))
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: isLit ? "lightbulb.max.fill" : "lightbulb")
                    .font(.system(size: side * 0.48, weight: .bold)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                    .foregroundStyle(isLit ? Theme.onAccent : Color.white.opacity(0.45))
            }
            .shadow(color: isLit ? Theme.Fill.yellow.opacity(0.7) : .clear, radius: side * 0.15)
            .overlay {
                if isPressed {
                    shape.strokeBorder(Theme.coral, lineWidth: max(2, side * 0.1))
                }
            }
            .contentShape(Rectangle())
    }
}

// MARK: - 開始シート

struct AkariKeshiNewGameSheet: View {
    let onStart: (AkariKeshiDifficulty) -> Void
    let onCancel: () -> Void
    @State private var difficulty: AkariKeshiDifficulty

    init(initial: AkariKeshiDifficulty,
         onStart: @escaping (AkariKeshiDifficulty) -> Void,
         onCancel: @escaping () -> Void) {
        self.onStart = onStart
        self.onCancel = onCancel
        _difficulty = State(initialValue: initial)
    }

    var body: some View {
        GameSetupSheet(
            kind: .solo,
            onStart: { onStart(difficulty) }, onCancel: onCancel
        ) {
            GameSetupSection(tr("難易度")) {
                HStack(spacing: 6) {
                    let levels = AkariKeshiDifficulty.allCases
                    ForEach(Array(levels.enumerated()), id: \.element) { step, value in
                        GameSetupChooser(title: value.label, subtitle: tr("最短%lld手", value.presses),
                                         selected: difficulty == value,
                                         accent: DifficultyTile.accent(step: step, of: levels.count),
                                         metrics: DifficultyTile.metrics) {
                            difficulty = value
                        }
                    }
                }
            }
        }
    }
}
