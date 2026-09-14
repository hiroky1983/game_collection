import SwiftUI
import Core

public struct SudokuView: View {
    @State private var model: SudokuModel
    private let services: GameServices
    @State private var showNewGame = true
    @State private var showConfirmNewGame = false
    @State private var showGiveUpConfirm = false
    /// ヒントのリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var hintRescue = RewardedRescue()
    /// コンティニューのリワード広告の段取り（同上）。
    @State private var continueRescue = RewardedRescue()
    @State private var zoomMode = false
    /// 帯の実幅（拡大トグルに文字を出すかの判定に使う。0 は未計測＝出す）。
    @State private var statusBarWidth: CGFloat = 0
    /// いま光らせているマス（行・列・ブロックが揃った瞬間・#666）。Model の `unitFlash` から作る表示だけの状態。
    @State private var flashingCells: Set<Int> = []
    /// 光を消さずに残す（DEBUG の撮影 hook 専用。光は 0.25 秒で消えるため非対話では撮れない）。
    @State private var holdsUnitFlash = false

    public init(services: GameServices) {
        self.services = services
        _model = State(initialValue: SudokuModel(services: services))
        _showNewGame = State(initialValue: !services.snapshots.exists(for: "sudoku"))
    }

    public var body: some View {
        // 縦の余白は 8。プレイ中（数字パッド + 操作）と終局後（記録 + レコメンド）で
        // 盤の下の高さが揃うように組んであるので、決着した瞬間に盤が縮まない（#148 と同じ考え方）。
        VStack(spacing: 8) {
            statusBar
            board
                .layoutPriority(1)
                .overlay {
                    if model.state == .failed { failedOverlay }
                }
                // 広告のロード〜視聴中は盤に触れない。ここが開いていると、
                // 「広告を見ている間に自分で答えを埋めてしまい、視聴後のヒントが不発になる」
                // （＝広告だけ消費される）経路ができる。
                .disabled(hintRescue.isWatching)
            HowToPlayHint(.sudoku, playLog: services.playLog)
            controlArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding(Theme.pad)
        .gameChrome(title: "ナンプレ", review: services.review) {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if model.state == .playing {
                        showConfirmNewGame = true
                    } else {
                        showNewGame = true
                    }
                } label: {
                    Label("新規ゲーム", systemImage: "plus.circle.fill")
                }
                // 生成中の二度押しで 2 本目の生成が走らないようにする（Model 側でも再入を弾く）。
                // ヒントの広告中も押させない（#815。照合は `applyHint(forGame:at:)` が持つので、ここは
                // 「広告を見たのに入らなかった」を起こさないための緩和）。
                .disabled(model.isGenerating || hintRescue.isWatching)
            }
        }
        .howToPlay(.sudoku)
        .sheet(isPresented: $showNewGame) {
            SudokuNewGameSheet { difficulty in
                showNewGame = false
                zoomMode = false
                Task { await model.newGame(difficulty: difficulty) }
            } onCancel: {
                showNewGame = false
            }
        }
        .confirmationDialog("新規ゲームを始めますか？", isPresented: $showConfirmNewGame, titleVisibility: .visible) {
            Button("終了して新規ゲーム", role: .destructive) { showNewGame = true }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると解きかけの盤面が失われます。")
        }
        .confirmationDialog("諦めますか？", isPresented: $showGiveUpConfirm, titleVisibility: .visible) {
            Button("諦める", role: .destructive) { model.giveUp() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("答えがすべて表示され、この局は記録上「クリアできなかった」扱いになります。")
        }
        .rewardedRescueAlerts(
            hintRescue,
            notEarned: "ヒントを使えませんでした",
            unavailable: RewardUnavailableAlert(
                title: "ヒントを入れられませんでした",
                message: "広告を見ているあいだに盤面が変わったため、ヒントを入れられませんでした。\nヒントの残り回数は減っていません。"
            )
        )
        .rewardedRescueAlerts(
            continueRescue,
            notEarned: "コンティニューできませんでした",
            unavailable: RewardUnavailableAlert(
                title: "コンティニューできませんでした",
                message: "広告を見ているあいだに新しいゲームが始まったか、この局を諦めたため、コンティニューできませんでした。"
            )
        )
        // 画面を離れたら計時を止める（#375）。止めないと計時の Task が self を握ったまま
        // 残り、モデルが解放されずに経過秒だけが進み続ける。戻れば .task が再開する。
        .onDisappear { model.pauseTimer() }
        .task {
            model.resumeTimerIfNeeded()
            #if DEBUG
            // 撮影・動作確認用（DEBUG 限定）: タップ無しで終局後のレイアウトにする（`-simulateGiveUp`）。
            // 数独の終局は「81マス埋める」か「諦める」でしか作れず、非対話のシミュレータ確認では
            // この経路が要る（マインスイーパー #148 と同じ）。
            if ProcessInfo.processInfo.arguments.contains("-simulateGiveUp") {
                showNewGame = false
                if !model.hasPuzzle { await model.newGame(difficulty: .easy) }
                model.giveUp()
            }
            // 撮影・動作確認用（DEBUG 限定）: 新規ゲームシートをキャンセルした直後（`.idle`）の
            // 画面を非対話で出す（#354。シミュレータは自動タップができないため）。
            if ProcessInfo.processInfo.arguments.contains("-sudokuCancelSheet") {
                showNewGame = false
            }
            // 撮影・動作確認用（DEBUG 限定）: シートを飛ばしてプレイ中の画面を出す（#353）。
            if ProcessInfo.processInfo.arguments.contains("-sudokuAutoStart") {
                showNewGame = false
                if !model.hasPuzzle { await model.newGame(difficulty: .easy) }
            }
            // 撮影・動作確認用（DEBUG 限定）: 空きマスをすべて正解で埋めてクリアさせる（#722 の階段の撮影）。
            // `-sudokuAutoStart` と併用する。記録・リザルトは本物の決着の経路をそのまま通る。
            if ProcessInfo.processInfo.arguments.contains("-sudokuAutoSolve"), model.state == .playing {
                for index in 0..<SudokuEngine.cellCount where model.board[index] == 0 {
                    if model.selected != index { model.select(index: index) }
                    model.enter(digit: model.solution[index])
                }
            }
            // 撮影・動作確認用（DEBUG 限定）: 揃った行の光と、使い切った数字パッドを止めた状態で出す（#666）。
            // `-sudokuAutoStart` と併用する。数字 5 をすべて正解で埋めてから、1 行目を最後に揃える。
            if ProcessInfo.processInfo.arguments.contains("-sudokuUnitFlashPreview"), model.state == .playing {
                holdsUnitFlash = true
                let fives = (0..<SudokuEngine.cellCount).filter { model.board[$0] == 0 && model.solution[$0] == 5 }
                let firstRow = SudokuEngine.cells(ofUnit: 0).filter { model.board[$0] == 0 && model.solution[$0] != 5 }
                for index in fives + firstRow {
                    if model.selected != index { model.select(index: index) }
                    model.enter(digit: model.solution[index])
                }
            }
            // 撮影・動作確認用（DEBUG 限定）: 起動 2 秒後に空きマスへ誤答を 1 つ入れ、揺れを非対話で起こす（#666）。
            // `-sudokuAutoStart` と併用する。揺れが補間されるかの実測（連続スクショ）に使う。
            if ProcessInfo.processInfo.arguments.contains("-sudokuMistakePreview"), model.state == .playing,
               let index = (0..<SudokuEngine.cellCount).first(where: { model.board[$0] == 0 }) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if model.selected != index { model.select(index: index) }
                model.enter(digit: model.solution[index] % SudokuEngine.size + 1)
            }
            #endif
        }
        .task(id: model.unitFlash) { await flashCompletedUnits(model.unitFlash) }
    }

    /// 行・列・ブロックが揃ったマスを一瞬光らせる（#666）。
    ///
    /// 光は即座に出し、`unitFlashHoldDuration` 待ってからフェードで消す。Reduce Motion では
    /// `withGameAnimation` がフェードを落とすだけで、出る・消えるの状態変化は必ず起きる。
    /// 次の合図が来ると `.task(id:)` が前の待ちを取り消すので、古い光の消し忘れも起きない。
    private func flashCompletedUnits(_ flash: SudokuUnitFlash?) async {
        guard let flash else {
            flashingCells = []
            return
        }
        flashingCells = flash.cells
        try? await Task.sleep(nanoseconds: UInt64(SudokuMetrics.unitFlashHoldDuration * 1_000_000_000))
        guard !Task.isCancelled, !holdsUnitFlash else { return }
        withGameAnimation(.easeOut(duration: SudokuMetrics.unitFlashFadeDuration)) {
            flashingCells = []
        }
    }

    // MARK: - Status Bar

    /// 帯は要素が多い（残り・ミス・難易度・時計・拡大）ので、拡大トグルの文字「拡大／全体」は
    /// **入る幅のときだけ**出す（`SudokuMetrics.showsZoomTitle`）。iPhone SE（帯の幅 343pt）では
    /// 文字を付けると「残り49」「ミス 0/3」が「残…」「ミ…」に潰れた（実測）。
    /// `ViewThatFits` は文字の縮小（`minimumScaleFactor`）を見込まず iPhone 17 Pro Max でも文字を
    /// 落としてしまったので、帯の実幅で判定する。
    private var statusBar: some View {
        statusBarRow(zoomTitle: SudokuMetrics.showsZoomTitle(statusBarWidth: statusBarWidth),
                     statusIcons: SudokuMetrics.showsStatusIcons(statusBarWidth: statusBarWidth))
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { statusBarWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in statusBarWidth = w }
                }
            )
    }

    private func statusBarRow(zoomTitle: Bool, statusIcons: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if model.isFinished {
                    let cleared = model.state == .cleared
                    Label(cleared ? "クリア！" : "答えを見た",
                          systemImage: cleared ? "flag.checkered" : "eye.fill")
                        .themeBody(15)
                        // 文字を拡大しても右のタイマー・トグルを押し出さないよう縮めて収める（#189）。
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(cleared ? Theme.teal : Theme.coral)
                } else if model.hasPuzzle {
                    statusLabel("残り\(model.remainingCount)", systemImage: "square.grid.3x3", showsIcon: statusIcons)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Theme.coral)
                    // ミスの残量。上限に近づくほど目に入るよう、2回目からは色を変える。
                    statusLabel("ミス \(model.mistakes)/\(SudokuModel.maxMistakes)", systemImage: "xmark.circle",
                                showsIcon: statusIcons)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(model.mistakes >= SudokuModel.maxMistakes - 1 ? Theme.coral : Theme.inkSub)
                } else {
                    // まだ出題が無い（#354）。存在しない問題の「残り81」「ミス 0/3」を出さない。
                    Text("難易度を選んでください")
                        .themeBody(15)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Theme.inkSub)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(model.difficulty.label)
                .themeCaption(11)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(difficultyAccent))
                .fixedSize(horizontal: true, vertical: false)
                .opacity(model.hasPuzzle ? 1 : 0)

            HStack(spacing: 8) {
                Label(RecordFormat.time(model.elapsedSeconds), systemImage: "clock")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.teal)
                    // 出題前の「0:00」も存在しない問題の数字なので、難易度カプセルと同じく隠す（#354）。
                    .opacity(model.hasPuzzle ? 1 : 0)

                // 拡大トグル。麻雀ソリティア・マインスイーパーと共通の `BoardToggleButton`（Core・#641）。
                // 以前は素のアイコン（13pt・枠なし・`Theme.surface`）を手書きしていて、他のゲームと
                // 見た目が揃っていなかった（会長 QA 2026-09-13）。
                BoardToggleButton(
                    isOn: zoomMode,
                    systemImage: zoomMode ? "minus.magnifyingglass" : "plus.magnifyingglass",
                    title: zoomTitle ? (zoomMode ? "全体" : "拡大") : nil,
                    fill: Theme.Fill.teal,
                    accent: Theme.teal,
                    label: zoomMode ? "盤全体を表示" : "盤を拡大"
                ) {
                    zoomMode.toggle()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, SudokuMetrics.statusBarVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
        // 3 つを別々に読ませるとスワイプ回数が増えるだけなので 1 要素にまとめる（#188）。
        .accessibilityElement(children: .contain)
    }

    /// 帯の「残り」「ミス」。狭い帯ではアイコンを省いて文字に幅を渡す（#775・`SudokuMetrics.showsStatusIcons`）。
    @ViewBuilder
    private func statusLabel(_ title: String, systemImage: String, showsIcon: Bool) -> some View {
        if showsIcon {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }

    private var difficultyAccent: Color {
        switch model.difficulty {
        case .easy:   return Theme.Fill.teal
        case .normal: return Theme.Fill.yellow
        case .hard:   return Theme.Fill.coral
        }
    }

    // MARK: - Board

    private var board: some View {
        Group {
            if model.isGenerating {
                // 生成中も盤と同じ面積を占め、出来上がった瞬間にレイアウトが跳ねないようにする。
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                        .fill(Theme.surface)
                    ProgressView()
                }
                .aspectRatio(1, contentMode: .fit)
            } else if zoomMode {
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        boardGrid(cellSide: SudokuMetrics.zoomedCellSide(availableWidth: geo.size.width))
                            // 画面のほうが広い（iPad）ときは等倍と同じく中央に置く。
                            .frame(minWidth: geo.size.width, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                .shadow(color: Theme.cardShadow, radius: 10, y: 6)
            } else {
                GeometryReader { geo in
                    boardGrid(cellSide: geo.size.width / CGFloat(SudokuEngine.size))
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                .shadow(color: Theme.cardShadow, radius: 10, y: 6)
            }
        }
    }

    private func boardGrid(cellSide: CGFloat) -> some View {
        let errors = model.errorCells
        let peers = model.highlightedCells
        let sameDigits = model.sameDigitCells
        let flashing = flashingCells
        return VStack(spacing: 0) {
            ForEach(0..<SudokuEngine.size, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<SudokuEngine.size, id: \.self) { col in
                        cellView(
                            row: row, col: col, side: cellSide,
                            errors: errors, peers: peers, sameDigits: sameDigits, flashing: flashing
                        )
                    }
                }
            }
        }
        .background(Theme.surface)
        .overlay(blockLines(cellSide: cellSide))
        .frame(
            width: cellSide * CGFloat(SudokuEngine.size),
            height: cellSide * CGFloat(SudokuEngine.size)
        )
    }

    /// 3×3 ブロックの太線。マスの枠とは別に上から引く（マス側で描くと隣と二重になる）。
    ///
    /// **外周だけは直線ではなく角丸の枠で描く**（会長QA #595-1）。盤は `Theme.cornerSmall` の
    /// 角丸で切り抜いてあるため、端に置いた直線は 4 隅で切り落とされ、隅の枠が消えて見える。
    /// 切り抜きと同じ角丸を `strokeBorder`（内側に引く）で描けば、隅まで途切れない。
    private func blockLines(cellSide: CGFloat) -> some View {
        let full = cellSide * CGFloat(SudokuEngine.size)
        return ZStack(alignment: .topLeading) {
            ForEach(SudokuMetrics.innerBlockLineIndices, id: \.self) { i in
                Rectangle()
                    .fill(Theme.ink)
                    .frame(width: full, height: SudokuMetrics.blockBorderWidth)
                    .offset(y: cellSide * CGFloat(i * 3))
            }
            ForEach(SudokuMetrics.innerBlockLineIndices, id: \.self) { i in
                Rectangle()
                    .fill(Theme.ink)
                    .frame(width: SudokuMetrics.blockBorderWidth, height: full)
                    .offset(x: cellSide * CGFloat(i * 3))
            }
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .strokeBorder(Theme.ink, lineWidth: SudokuMetrics.blockBorderWidth)
                .frame(width: full, height: full)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func cellView(
        row: Int, col: Int, side: CGFloat,
        errors: Set<Int>, peers: Set<Int>, sameDigits: Set<Int>, flashing: Set<Int>
    ) -> some View {
        let index = row * SudokuEngine.size + col
        let digit = model.board[index]
        let isGiven = model.given[index]
        let isSelected = model.selected == index
        let isError = errors.contains(index)
        let isHinted = model.hintedCells.contains(index)
        let noteDigits = (1...SudokuEngine.size).filter { model.hasNote($0, at: index) }
        let shakes = model.mistakeShakes[index] ?? 0

        return ZStack {
            Rectangle()
                .fill(cellFill(
                    isSelected: isSelected,
                    isPeer: peers.contains(index),
                    isSameDigit: sameDigits.contains(index),
                    isError: isError
                ))
            // 行・列・ブロックが揃った瞬間の光（#666）。色の判定（`cellFill`）とは別の層に重ね、
            // 選択・間違いの色を塗り替えない。
            Rectangle()
                .fill(Theme.yellow.opacity(0.45))
                .opacity(flashing.contains(index) ? 1 : 0)
            if digit != 0 {
                Text("\(digit)")
                    .font(.system(size: side * 0.58, weight: isGiven ? .black : .semibold, design: .rounded))
                    .foregroundStyle(digitColor(isGiven: isGiven, isError: isError, isHinted: isHinted))
                    .minimumScaleFactor(0.5)
            } else if !noteDigits.isEmpty {
                noteGrid(noteDigits: noteDigits, side: side)
            }
        }
        // 誤答を入れたマスの中身だけを短く横に揺らす（#666。五目並べの無効タップ #202 と同じ型）。
        .modifier(SudokuShake(animatableData: CGFloat(shakes)))
        // 演出の修飾子は入れ子にすると内側が外側のトランザクションを打ち消す（#199）。ここでは
        // **それを前提に**、揺れを数字の演出（下）の内側に置いている: 誤答では両方の値が同時に変わり、
        // 内側の linear が勝つので揺れは必ず補間される（その 1 回だけ数字の出方も linear になる）。
        // 正答では揺れの値が変わらないので、下の数字の演出が従来どおり効く。
        .gameAnimation(.linear(duration: SudokuMetrics.mistakeShakeDuration), value: shakes)
        .frame(width: side, height: side)
        .border(Theme.inkSub.opacity(0.35), width: SudokuMetrics.cellBorderWidth)
        .gameAnimation(.easeOut(duration: SudokuMetrics.fillDuration), value: digit)
        .contentShape(Rectangle())
        .onTapGesture { model.select(index: index) }
        // 色とメモの小さな数字だけで状態を表しているため、読み上げ文を明示する（#188）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SudokuAccessibility.cellLabel(
            row: row, col: col, digit: digit,
            isGiven: isGiven, isHinted: isHinted, isError: isError,
            noteDigits: noteDigits, isSelected: isSelected
        ))
        .accessibilityHint(SudokuAccessibility.cellHint(
            isGiven: isGiven, isPlaying: model.state == .playing
        ))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.select(index: index) }
    }

    private func noteGrid(noteDigits: [Int], side: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { c in
                        let digit = r * 3 + c + 1
                        Text(noteDigits.contains(digit) ? "\(digit)" : " ")
                            .font(.system(size: side * 0.22, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.inkSub)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(1)
        .accessibilityHidden(true)
    }

    private func cellFill(isSelected: Bool, isPeer: Bool, isSameDigit: Bool, isError: Bool) -> Color {
        if isError { return Theme.coral.opacity(0.30) }
        if isSelected { return Theme.teal.opacity(0.35) }
        if isSameDigit { return Theme.teal.opacity(0.18) }
        if isPeer { return Theme.inkSub.opacity(0.12) }
        return .clear
    }

    private func digitColor(isGiven: Bool, isError: Bool, isHinted: Bool) -> Color {
        if isError { return Theme.coral }
        if isGiven { return Theme.ink }
        // 諦めて表示した答えは自力で入れた数字と同じ色にしない
        // （同じ teal だと「自分で解いた盤」と見分けが付かない）。
        if model.state == .givenUp { return Theme.inkSub }
        if isHinted { return Theme.purple }
        return Theme.teal
    }

    // MARK: - 盤の下の操作エリア

    /// プレイ中（数字パッド + ヒント / 諦める）と終局後（記録 + 次のゲーム + レコメンド）で
    /// 中身が入れ替わる。**高さは常に両者の最大構成に揃える**（#148 と同じ理由）。
    /// ここが伸び縮みすると `board`（`aspectRatio(1, .fit)` + `layoutPriority(1)`）が
    /// 帳尻合わせに縮み、解き終わった瞬間に盤が一段小さくなって見える。
    private var controlArea: some View {
        // 数字パッドは終局後の構成より高いことがあるので、`GameControlArea` が確保する
        // 「終局後のぶん」に加えてプレイ中のぶんも隠しのひな形で確保する（この 1 枚だけ他ゲームに無い）。
        ZStack(alignment: .top) {
            playingControls
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            GameControlArea(isFinished: model.isFinished, services: services, ladder: ladder) {
                resultControls
            } playing: {
                if model.state == .playing {
                    playingControls
                        // 盤と同じ理由でロックする（数字パッドからも答えを埋められるため）。
                        .disabled(hintRescue.isWatching)
                } else if model.state == .idle {
                    // 新規ゲームシートをキャンセルした直後（#354）。ここに何も出さないと空盤の下が
                    // 無の領域になり、次に何をすればよいかが画面から読めない。シートを開き直す導線を置く。
                    idleControls
                }
            }
        }
    }

    /// まだ出題が無い（`.idle`）ときの操作エリア。高さは ZStack の隠し構成が確保しているので、
    /// ここはシートを開き直すボタン1つでよい。
    private var idleControls: some View {
        HStack {
            Spacer(minLength: 0)
            Button { showNewGame = true } label: {
                Label("難易度を選んで始める", systemImage: "play.fill")
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 16)
                    .frame(minHeight: SudokuMetrics.padButtonMinSide)
                    .background(Capsule().fill(Theme.Fill.coral))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pop)
            Spacer(minLength: 0)
        }
        .themeBody(14)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .popCard(corner: Theme.cornerSmall)
    }

    private var playingControls: some View {
        VStack(spacing: 8) {
            numberPad
            gameControls
        }
    }

    // MARK: - 数字パッド

    /// 1〜9 と消しゴムを 2 段に割る。1 段に 10 個並べると iPhone SE で 1 個 37pt 台になり
    /// 最小タップ標的（44pt）を割るため（`SudokuMetrics.padColumns`）。
    private var numberPad: some View {
        VStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<SudokuMetrics.padColumns, id: \.self) { col in
                        let slot = row * SudokuMetrics.padColumns + col
                        if slot < SudokuEngine.size {
                            digitButton(slot + 1)
                        } else {
                            eraseButton
                        }
                    }
                }
            }
        }
    }

    private func digitButton(_ digit: Int) -> some View {
        let exhausted = model.isDigitExhausted(digit)
        return Button {
            model.enter(digit: digit)
        } label: {
            Text("\(digit)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                // 使い切った数字は文字だけを薄くする（#666）。ボタンの面は残し、並びの位置は変えない。
                .opacity(exhausted ? SudokuMetrics.exhaustedDigitOpacity : 1)
                .frame(maxWidth: .infinity)
                .frame(minHeight: SudokuMetrics.padButtonMinSide)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                        .fill(model.noteMode ? Theme.purple.opacity(0.18) : Theme.surface)
                )
                .foregroundStyle(exhausted ? Theme.inkSub : Theme.ink)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pop)
        .accessibilityLabel(SudokuAccessibility.padLabel(
            digit: digit, noteMode: model.noteMode, isExhausted: exhausted
        ))
    }

    private var eraseButton: some View {
        Button {
            model.erase()
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: SudokuMetrics.padButtonMinSide)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                        .fill(Theme.surface)
                )
                .foregroundStyle(Theme.inkSub)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pop)
        .accessibilityLabel("消す")
    }

    // MARK: - 操作ボタン

    private var gameControls: some View {
        HStack(spacing: 6) {
            Button { model.toggleNoteMode() } label: {
                Label("メモ", systemImage: "pencil.tip")
                    .foregroundStyle(model.noteMode ? Theme.onAccent : Theme.inkSub)
                    .padding(.horizontal, 12)
                    .frame(minHeight: SudokuMetrics.padButtonMinSide)
                    .background(Capsule().fill(model.noteMode ? Theme.Fill.purple : Theme.surface))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pop)
            .accessibilityLabel(model.noteMode ? "メモモード、オン" : "メモモード、オフ")

            // 元に戻す（#353）。誤タップの救済用に**直前の1手だけ**取り消せる。
            Button { model.undo() } label: {
                Label("戻す", systemImage: "arrow.uturn.backward")
                    // 有効時は差し色の面、無効時は濃いグレーの面。面ごとに読める文字色が違う（#220）。
                    .foregroundStyle(model.canUndo ? Theme.onAccent : .white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: SudokuMetrics.padButtonMinSide)
                    .background(Capsule().fill(model.canUndo ? Theme.Fill.teal : Theme.fillMuted))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pop)
            .disabled(!model.canUndo)
            .accessibilityLabel("元に戻す")
            .accessibilityHint(
                model.canUndo
                    ? "直前の1手を取り消します。ミスもその手のぶんだけ戻ります"
                    : "取り消せる手がありません"
            )

            Button {
                requestHint()
            } label: {
                Label("ヒント\(model.remainingHints)", systemImage: "lightbulb.fill")
                    .foregroundStyle(model.canHint ? Theme.onAccent : .white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: SudokuMetrics.padButtonMinSide)
                    .background(Capsule().fill(model.canHint ? Theme.Fill.yellow : Theme.fillMuted))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pop)
            .disabled(!model.canHint || hintRescue.isWatching)
            .accessibilityLabel(SudokuAccessibility.hintLabel(remaining: model.remainingHints))
            .accessibilityHint(model.canHint ? "広告を見ると選択中のマスの答えが入ります" : "答えを入れたいマスを選んでください")

            Spacer(minLength: 0)

            Button { showGiveUpConfirm = true } label: {
                Label("諦める", systemImage: "flag.fill")
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: SudokuMetrics.padButtonMinSide)
                    .background(Capsule().fill(Theme.Fill.coral))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pop)
        }
        .themeBody(14)
        // 4ボタン+残数表示で幅が詰まり「ヒント」が改行していた（会長指摘 2026-09-02）。
        // 1行固定+縮小許容で確実に収める。
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .popCard(corner: Theme.cornerSmall)
    }

    /// リワード広告を最後まで見たときだけヒントを与える（既存のコンティニューと同じ形・#262）。
    ///
    /// **対象のマスは要求した時点で確定させる**。広告の読み込み〜視聴のあいだに盤の操作は
    /// 止めてある（`hintRescue.isWatching` で `board` と数字パッドを無効化）が、
    /// それでも「広告を見たのにヒントが入らない」経路を残さないよう、
    /// 入れる先を選択状態から切り離しておく。
    private func requestHint() {
        guard !hintRescue.isWatching, let target = model.selected, model.canHint(at: target) else { return }
        // どの局に対するヒントかを広告を出す前に控え、ロード中に始めた新しい局へは入れない（#815）。
        let game = model.gameSerial
        hintRescue.request(
            services, gameID: model.gameID, purpose: .hint,
            guardedBy: .checkedByGrant
        ) {
            // 広告を見たのに入らなかったら黙って終わらせない（対価が無い状態を作らない）。
            model.applyHint(forGame: game, at: target)
        }
    }

    // MARK: - ミス上限（広告コンティニュー・2048 と同型）

    private var failedOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .fill(.black.opacity(0.55))
            VStack(spacing: 12) {
                Text("ミスが\(SudokuModel.maxMistakes)回になりました")
                    .font(.title3.bold()).foregroundStyle(.white)
                Text("広告を見るとミスが0に戻り、続きから遊べます")
                    .themeCaption(12).foregroundStyle(.white.opacity(0.85))
                Button {
                    // 視聴完了（報酬獲得）したときだけコンティニューを許可する。どの局に対するものかを
                    // 広告を出す前に控え、ロード中に入れ替わった局へは乗せない（#729）。
                    let game = model.gameSerial
                    continueRescue.request(
                        services, gameID: model.gameID, purpose: .continue,
                        guardedBy: .checkedByGrant
                    ) {
                        model.continueAfterAd(forGame: game)
                    }
                } label: {
                    Label("広告を見てコンティニュー", systemImage: "play.rectangle.fill")
                    .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Fill.coral)
                .disabled(continueRescue.isWatching)
                Button("諦めて答えを見る") { model.giveUp() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
    }

    /// クリアが続いたら一段上の難易度を勧める（#722）。始め直しの後始末は新規ゲームシートと同じ。
    private var ladder: DifficultyLadderPrompt? {
        let levels = SudokuDifficulty.allCases
        return DifficultyLadderPrompt(result: model.recordResult, currentLevel: levels.firstIndex(of: model.difficulty),
                                      levelLabels: levels.map(\.label)) { level in
            zoomMode = false
            Task { await model.newGame(difficulty: levels[level]) }
        }
    }

    // MARK: - Result Controls

    private var resultControls: some View {
        HStack(spacing: 12) {
            RecordLabel(model.recordResult)
                .lineLimit(1).minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Button { showNewGame = true } label: {
                Label("次のゲーム", systemImage: "arrow.clockwise")
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: SudokuMetrics.padButtonMinSide)
                    .background(Capsule().fill(Theme.Fill.coral))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pop)
        }
        .themeBody(14)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - 誤答の揺れ

/// 誤答を入れたマスの横揺れ（#666）。五目並べの `GomokuShake`（#202）と同じ型。
///
/// `animatableData` にそのマスの誤答の回数を渡す。値が 1 進むあいだに左右へ `shakes` 往復し、
/// 整数では `sin` が 0 になるので**必ず元位置へ戻る**。Reduce Motion が ON のときは
/// `.gameAnimation` がアニメーションを落とすため補間自体が起きず、マスは静止したままになる
/// （触覚は Model 側から従来どおり鳴る）。
private struct SudokuShake: GeometryEffect {
    /// 片側の振れ幅（pt）。マスの枠の内側で収まるよう、盤全体を揺らす五目並べより小さくする。
    var amount: CGFloat = 3
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

struct SudokuNewGameSheet: View {
    let onStart: (SudokuDifficulty) -> Void
    let onCancel: () -> Void
    @State private var difficulty: SudokuDifficulty = .normal

    /// 「かんたん／ふつう／むずかしい」は横3つでは収まらないので、題名を縮めて1行に収める。
    private static let metrics = GameSetupChooser.Metrics(
        title: .title(20), subtitleSize: 11, titleMinimumScale: 0.6
    )

    var body: some View {
        GameSetupSheet(
            title: "新規ゲーム", startTitle: "スタート",
            onStart: { onStart(difficulty) }, onCancel: onCancel
        ) {
            GameSetupSection("難易度") {
                HStack(spacing: 12) {
                    // 「約」を付けるのは、唯一解を保てないマスは削れずに戻すため、実際の
                    // 空きマス数が範囲の上限に届かないことがあるから（`SudokuEngine` の
                    // `removalRange` のコメント参照・#354 の S6）。
                    difficultyTile(.easy,   subtitle: "空き 約30〜35", accent: Theme.Fill.teal)
                    difficultyTile(.normal, subtitle: "空き 約40〜45", accent: Theme.Fill.yellow)
                    difficultyTile(.hard,   subtitle: "空き 約46〜50", accent: Theme.Fill.coral)
                }
            }
        }
    }

    private func difficultyTile(_ value: SudokuDifficulty, subtitle: String, accent: Color) -> some View {
        GameSetupChooser(title: value.label, subtitle: subtitle,
                         selected: difficulty == value, accent: accent,
                         metrics: Self.metrics) {
            difficulty = value
        }
    }
}
