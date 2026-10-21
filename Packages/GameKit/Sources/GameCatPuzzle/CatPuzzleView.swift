import SwiftUI
import Core

/// おじさんの飼い猫パズル（#2250）のプレイ画面。家の間取りのマスをタップして ×・猫を置く。
public struct CatPuzzleView: View {
    private let services: GameServices
    @State private var model: CatPuzzleModel
    /// 最後に選んだ盤の大きさ（次に開いたときの開始シートの初期値）。
    @AppStorage("catPuzzleSize") private var preferredSize = CatPuzzleSize.normal.rawValue
    /// 開始シート（難易度を選ぶ）。続きの盤が無ければ最初に出す（他のゲームと同じ・会長 QA 2026-10-21・build 43）。
    @State private var showNewGame: Bool
    /// 「＋」で途中の局をやめるかの確認。
    @State private var showConfirmNewGame = false
    /// 「やり直し」（印を全部消す）の確認。
    @State private var showConfirmClear = false
    /// ミス上限の終局カードを「盤を見る」で閉じたか（新しい局で開け直す）。
    @State private var failCardClosed = false

    public init(services: GameServices) {
        self.services = services
        let saved = UserDefaults.standard.string(forKey: "catPuzzleSize").flatMap(CatPuzzleSize.init(rawValue:))
        let model = CatPuzzleModel(services: services, size: saved ?? .normal)
        _model = State(initialValue: model)
        // 続きの盤が無ければ、まず難易度を選んでもらう（ナンプレ・マインスイーパー・明かり消しと同じ）。
        _showNewGame = State(initialValue: Self.startsWithNewGameSheet(model))
    }

    /// 狙った局面を描くための入口（静止画の確認・テスト用）。
    init(services: GameServices, model: CatPuzzleModel, showNewGame: Bool = false) {
        self.services = services
        _model = State(initialValue: model)
        _showNewGame = State(initialValue: showNewGame)
    }

    /// 開いたときに開始シートを出すか。中断データから再開した盤（印がある）なら出さずに続きを見せる。
    static func startsWithNewGameSheet(_ model: CatPuzzleModel) -> Bool {
        !model.hasProgressToLose
    }

    /// 計時を止めておくか（開始シート・確認を出している間。遊び方・広告・背面は `gameTimerLifecycle` が止める）。
    static func holdsClock(showNewGame: Bool, showConfirmNewGame: Bool, showConfirmClear: Bool) -> Bool {
        showNewGame || showConfirmNewGame || showConfirmClear
    }

    public var body: some View {
        VStack(spacing: 12) {
            statusBar
            // 盤は残りの高さを Spacer と山分けしない（操作の段が増えた分だけ盤が縮むのを防ぐ）。
            // クリアのダイアログは最後の猫が出る演出を見せてから 1 拍（`CatPuzzleModel.clearCardDelay`）おいて重ねる。
            board
                .gameClearCard(isPresented: model.showsClearCard, title: tr("クリア！"), details: clearDetails)
                .boardGameResultCard(isPresented: model.isFailed && !failCardClosed) { failCard }
                .layoutPriority(1)
            messageLine
            controlArea
            // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.catPuzzle, playLog: services.playLog)
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding()
        .gameChrome(title: tr("おじさんの飼い猫パズル"), review: services.review,
                    newGame: GameChromeNewGame(.solo) { requestNewGame() })
        .howToPlay(HowToPlayGuide.catPuzzle.illustrated(CatPuzzleHowToFigures.items))
        .sheet(isPresented: $showNewGame) {
            CatPuzzleNewGameSheet(initial: model.size) { size in
                showNewGame = false
                startNewGame(size: size)
            } onCancel: {
                showNewGame = false
            }
        }
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規ゲームを始めますか？"), isPresented: $showConfirmNewGame, titleVisibility: .visible) {
                Button(tr("終了して新規ゲーム"), role: .destructive) { showNewGame = true }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると、いまの盤面とタイムが失われます。"))
            }
            anchor.confirmationDialog(tr("印を全部消しますか？"), isPresented: $showConfirmClear, titleVisibility: .visible) {
                Button(tr("全部消してやり直す"), role: .destructive) { withGameAnimation { model.reset() } }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("同じ問題を最初から解きます。タイムとミスはそのままです。"))
            }
        }
        // 答えでないマスに赤い × が付いたら読み上げる（3 回目の終局は結果カードが読み上げる）。
        .onChange(of: model.mistakes) { _, _ in
            if model.lastWrongCell != nil, !model.isFailed {
                AccessibilityNotification.Announcement(
                    tr("そこに猫はいない。赤い×を置いた。ミス %1$lld/%2$lld", model.mistakes, CatPuzzleModel.maxMistakes)
                ).post()
            }
        }
        // 新しい局が始まったら、次の負けでまたカードが出るよう開け直す。
        .onChange(of: model.isFailed) { _, failed in
            if !failed { failCardClosed = false }
        }
        // 最後の猫を置いたら 1 拍おいてクリアのダイアログを出す。
        .task(id: model.isSolved) {
            guard let wait = model.clearCardWait else { return }
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard !Task.isCancelled else { return }
            withGameAnimation { model.revealClearCardIfDue() }
        }
        // 計時は盤が出た時点から（会長 QA 2026-10-21・build 43）。開始シート・確認・遊び方・広告・背面の間は止め、
        // 画面を離れたら止め、戻ったら再開する（#375・#1734・#1857・#2406）。
        .gameTimerLifecycle(
            isHeld: Self.holdsClock(showNewGame: showNewGame, showConfirmNewGame: showConfirmNewGame,
                                    showConfirmClear: showConfirmClear),
            pause: { model.pauseTimer() },
            resume: { model.resumeTimerIfNeeded() }
        )
        .task {
            // 開始シートを出している間は動かさない（シートを閉じた時点で `gameTimerLifecycle` が動かす）。
            if !showNewGame { model.resumeTimerIfNeeded() }
        }
    }

    // MARK: - 上の帯

    /// 左に残りの猫（終局後は結果）、右にミス（「ミス 1/3」）・難易度・タイム。
    private var statusBar: some View {
        GameStatusBar {
            Text(model.isSolved ? tr("全員みつけた！")
                 : model.isFailed ? tr("%lld回まちがえた…", CatPuzzleModel.maxMistakes)
                 : tr("残り %lld匹", model.remainingCats))
                .scaledFont(17, weight: .heavy, design: .rounded, maxScale: 1.3)
                .foregroundStyle(model.isSolved ? Theme.tealText : model.isFailed ? Theme.coralText : Theme.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } trailing: {
            // 右側は折り返さない（「0:00」が 2 行に割れないよう固定幅で勝たせる）。
            HStack(spacing: 6) {
                // ミスの残量。1 回目から色を変える（ナンプレの「ミス 1/3」と同じ形）。
                Text(tr("ミス %1$lld/%2$lld", model.mistakes, CatPuzzleModel.maxMistakes))
                    .scaledFont(13, weight: .bold, design: .rounded, maxScale: 1.3).monospacedDigit()
                    .foregroundStyle(model.mistakes > 0 ? Theme.coralText : Theme.inkSub)
                    .accessibilityLabel(tr("ミス %1$lld回、あと%2$lld回で終わり", model.mistakes, model.mistakesRemaining))
                Text(tr("・")).foregroundStyle(Theme.inkSub).accessibilityHidden(true)
                Text(model.size.label)
                    .scaledFont(13, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundStyle(Theme.inkSub)
                    .accessibilityLabel(tr("難易度 %@", model.size.label))
                Text(tr("・")).foregroundStyle(Theme.inkSub).accessibilityHidden(true)
                GameClockLabel(RecordFormat.time(model.elapsedSeconds))
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - 盤

    private var board: some View {
        GeometryReader { geo in
            let n = model.puzzle.side
            let inset: CGFloat = 8
            let boardSide = min(geo.size.width, geo.size.height)
            let cellSide = max(1, (boardSide - inset * 2) / CGFloat(n))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
                CatPuzzleBoardCanvas(
                    puzzle: model.puzzle, marks: model.marks,
                    wrongCrosses: model.wrongCrosses, lastWrongCell: model.lastWrongCell,
                    hintCells: model.hintCells, hintCrosses: model.hintCrosses, lastHint: model.lastHint,
                    shakeToken: model.mistakes, isSolved: model.isSolved, cellSide: cellSide
                )
                .offset(x: inset, y: inset)
                cells(cellSide: cellSide, inset: inset)
            }
            .frame(width: boardSide, height: boardSide)
            .frame(maxWidth: .infinity, alignment: .center)
            .gameAnimation(.easeOut(duration: 0.15), value: model.marks)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// タップと VoiceOver 用のマスの並び。見た目は Canvas で描き、操作と読み上げだけをこちらに置く。
    private func cells(cellSide: CGFloat, inset: CGFloat) -> some View {
        let n = model.puzzle.side
        return ForEach(0..<model.puzzle.cellCount, id: \.self) { index in
            Color.clear
                .frame(width: cellSide, height: cellSide)
                .contentShape(Rectangle())
                .offset(x: inset + CGFloat(index % n) * cellSide, y: inset + CGFloat(index / n) * cellSide)
                .onTapGesture { withGameAnimation { model.tap(cell: index) } }
                .accessibilityElement()
                .accessibilityLabel(CatPuzzleAccessibility.cellLabel(
                    row: index / n, col: index % n,
                    roomName: CatPuzzleHouse.room(model.puzzle.rooms[index]).name,
                    mark: model.marks[index],
                    isConflict: model.wrongCrosses.contains(index),
                    isHint: model.hintCells.contains(index) || model.hintCrosses.contains(index)
                ))
                .accessibilityHint(model.isOver ? "" : model.hintCells.contains(index)
                                   ? tr("ヒントで置いた猫は消せません") : model.hintCrosses.contains(index)
                                   ? tr("ヒントで置いた × は消せません") : model.wrongCrosses.contains(index)
                                   ? tr("ここに猫はいません。赤い × は消せません") : tr("押すと ×、猫、空きの順に変わります"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { withGameAnimation { model.tap(cell: index) } }
        }
    }

    // MARK: - 盤の下

    /// 盤の下の 1 行。ヒント・赤い × の説明・終局のおじさんの一言。高さは常に確保して盤が跳ねないようにする。
    private var messageLine: some View {
        ZStack {
            if model.isSolved {
                // おじさんの一言は横いっぱいの吹き出しにして、文字が窮屈にならないようにする（会長 QA 2026-10-21・build 42）。
                ojisanLine(face: .cheer, text: tr("%lld匹ともくつろいでおる", model.size.side))
            } else if model.isFailed {
                ojisanLine(face: .frown, text: tr("猫はどこへ行ったんじゃ…"))
            } else if model.lastWrongCell != nil {
                Text(tr("そこに猫はいない！ 赤い×はミス（あと%lld回で終わり）", model.mistakesRemaining))
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.coralText)
                    .multilineTextAlignment(.center)
                    // 読み上げは `onChange` の通知で伝える。
                    .accessibilityHidden(true)
            } else if let hint = model.lastHint {
                Label(CatPuzzleAccessibility.message(for: hint, puzzle: model.puzzle, roomName: { CatPuzzleHouse.room($0).name }),
                      systemImage: "lightbulb.fill")
                    .scaledFont(14, weight: .bold, design: .rounded)
                    .foregroundStyle(Theme.yellowText)
                    .multilineTextAlignment(.center)
            } else {
                Text(tr("タップで ×、もう一度で猫"))
                    .scaledFont(14, weight: .semibold, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
            }
        }
        .frame(minHeight: 36)
    }

    /// 終局のおじさんの一言（顔＋横いっぱいの吹き出し）。
    private func ojisanLine(face: OjisanPixel.Face, text: String) -> some View {
        HStack(spacing: 10) {
            OjisanPixel.faceImage(face)
                .frame(width: 40, height: 37.5)
            Text(text)
                .scaledFont(16, weight: .bold, design: .rounded, maxScale: 1.4)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .popCard(corner: Theme.cornerSmall)
        }
        .frame(maxWidth: .infinity)
    }

    /// 盤の下の操作（#148・#1689）。遊んでいる間はヒント・戻す・⋯、終局（クリア・ミス 3 回の負け）したら他のゲームと同じ
    /// 「同じ条件でもう一回」「設定を変える」（`GameReplayBar`）とレコメンドに替える（会長 QA 2026-10-21・build 42）。
    /// 高さは `GameControlArea` が終局後の最大構成に揃える（決着で盤が縮まない）。
    private var controlArea: some View {
        GameControlArea(isFinished: model.isOver, services: services) {
            GameReplayBar(
                onReplay: { startNewGame(size: nil) },
                onChangeSettings: { showNewGame = true }
            ) {
                RecordLabel(model.recordResult)
            }
        } playing: {
            let controls = Self.playControls(
                for: model,
                onClear: { showConfirmClear = true },
                onUndo: { withGameAnimation { model.undo() } },
                onHint: { withGameAnimation { model.useHint() } }
            )
            if !controls.menu.isEmpty || !controls.actions.isEmpty {
                GameOverflowBar(menuItems: controls.menu, actions: controls.actions, verticalPadding: 4)
            }
        }
    }

    /// 遊んでいる間の操作の段（#1834）。広告が絡むヒントと「戻す」を段に、やり直しは「⋯」に入れる。
    /// 終局した後は何も返さない（終局後は `GameReplayBar` に替わる）。
    static func playControls(
        for model: CatPuzzleModel,
        onClear: @escaping () -> Void = {}, onUndo: @escaping () -> Void = {}, onHint: @escaping () -> Void = {}
    ) -> (menu: [GameControlMenuItem], actions: [GameActionItem]) {
        guard !model.isOver else { return ([], []) }
        let menu = [
            GameControlMenuItem(
                id: "clear", title: tr("やり直し"), systemImage: "arrow.counterclockwise",
                isDestructive: true, isEnabled: model.hasProgressToLose, action: onClear
            ),
        ]
        let actions = [
            GameActionItem(
                id: "undo", title: tr("戻す"), systemImage: "arrow.uturn.backward", role: .undo,
                isEnabled: model.canUndo, action: onUndo
            ),
            GameActionItem(
                id: "hint", title: tr("ヒント"), systemImage: "lightbulb.fill", role: .hint,
                badge: hintBadge(for: model),
                isEnabled: model.canHint,
                accessibilityLabel: tr("ヒント、あと%lld回", model.hintsRemaining),
                accessibilityHint: tr("推理の1歩を示します。確実に猫のいないマスに×を置き、確定するときだけ猫を置きます"),
                action: onHint
            ),
        ]
        return (menu, actions)
    }

    /// ヒントの 2 行目。無料ぶんを使い切ったら「0回 ▶ 広告を見て +1」の面にする。
    /// **試作では広告の差し込み口だけ**で、`RewardedRescue` は呼ばない（押せない）。本導入時に
    /// ナンプレのヒントの救済（`hintRescue`・目的はヒント）と同じ経路をここへつなぐ。
    private static func hintBadge(for model: CatPuzzleModel) -> GameActionBadge {
        model.hintsRemaining > 0 ? .count(model.hintsRemaining) : .ad(gain: 1)
    }

    private var clearDetails: [String] {
        [
            tr("タイム %@", RecordFormat.time(model.elapsedSeconds)),
            tr("%1$@（%2$@）", model.size.label, model.size.sizeLabel),
            tr("ミス %lld", model.mistakes),
        ]
    }

    /// ミス上限の終局カード（他のゲームの負けと同じ `BoardGameResultCard`）。
    private var failCard: some View {
        BoardGameResultCard(
            verdict: .loss,
            reason: tr("%lld回まちがえた…", CatPuzzleModel.maxMistakes),
            details: [
                tr("%1$@（%2$@）", model.size.label, model.size.sizeLabel),
                tr("タイム %@", RecordFormat.time(model.elapsedSeconds)),
            ],
            record: model.recordResult
        ) { failCardClosed = true }
    }

    // MARK: - 新規ゲーム

    /// 「＋」。途中の盤面があるときは確認を挟んでから開始シートを出す（他のゲームと同じ）。
    /// やめた局は、開始シートで始めた時点で途中離脱（quit）として数える（`CatPuzzleModel.newGame` → `gameDidRestart`）。
    private func requestNewGame() {
        if model.hasProgressToLose {
            showConfirmNewGame = true
        } else {
            showNewGame = true
        }
    }

    /// `size` が nil なら同じ大きさで始め直す（「同じ条件でもう一回」）。
    private func startNewGame(size: CatPuzzleSize?) {
        if let size { preferredSize = size.rawValue }
        withGameAnimation { model.newGame(size: size) }
    }
}

// MARK: - 開始シート

/// 難易度（盤の大きさ）を選んで始めるシート。他のゲームと同じ共通の枠（`GameSetupSheet`）。
struct CatPuzzleNewGameSheet: View {
    let onStart: (CatPuzzleSize) -> Void
    let onCancel: () -> Void
    @State private var size: CatPuzzleSize

    init(initial: CatPuzzleSize,
         onStart: @escaping (CatPuzzleSize) -> Void,
         onCancel: @escaping () -> Void) {
        self.onStart = onStart
        self.onCancel = onCancel
        _size = State(initialValue: initial)
    }

    var body: some View {
        GameSetupSheet(
            kind: .solo,
            onStart: { onStart(size) }, onCancel: onCancel
        ) {
            Self.sizeSection(selection: $size)
        }
    }

    /// 難易度の節（静止画の確認でも中身だけ描けるよう切り出している）。
    static func sizeSection(selection: Binding<CatPuzzleSize>) -> some View {
        GameSetupSection(tr("難易度")) {
            HStack(spacing: 6) {
                let levels = CatPuzzleSize.allCases
                ForEach(Array(levels.enumerated()), id: \.element) { step, value in
                    GameSetupChooser(title: value.label, subtitle: value.sizeLabel,
                                     selected: selection.wrappedValue == value,
                                     accent: DifficultyTile.accent(step: step, of: levels.count),
                                     metrics: DifficultyTile.metrics) {
                        selection.wrappedValue = value
                    }
                }
            }
        }
    }
}
