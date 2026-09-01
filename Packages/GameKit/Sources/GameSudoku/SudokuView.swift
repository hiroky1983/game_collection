import SwiftUI
import Core

public struct SudokuView: View {
    @State private var model: SudokuModel
    private let services: GameServices
    @State private var showNewGame = true
    @State private var showConfirmNewGame = false
    @State private var showGiveUpConfirm = false
    @State private var showRewardNotEarned = false
    @State private var isRequestingHint = false
    @State private var isContinuing = false
    @State private var showContinueNotEarned = false
    @State private var showHintUnavailable = false
    @State private var zoomMode = false
    @Environment(\.dismiss) private var dismiss

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
                .disabled(isRequestingHint)
            HowToPlayHint(.sudoku, playLog: services.playLog)
            controlArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
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
                Text("ナンプレ")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
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
                .disabled(model.isGenerating)
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
        .alert("ヒントを使えませんでした", isPresented: $showRewardNotEarned) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。")
        }
        .alert("コンティニューできませんでした", isPresented: $showContinueNotEarned) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。")
        }
        .alert("ヒントを入れられませんでした", isPresented: $showHintUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を見ているあいだに盤面が変わったため、ヒントを入れられませんでした。\nヒントの残り回数は減っていません。")
        }
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
            #endif
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
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
                    Label("残り\(model.remainingCount)", systemImage: "square.grid.3x3")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Theme.coral)
                    // ミスの残量。上限に近づくほど目に入るよう、2回目からは色を変える。
                    Label("ミス \(model.mistakes)/\(SudokuModel.maxMistakes)", systemImage: "xmark.circle")
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
                .foregroundStyle(.white)
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

                // 拡大トグル。マインスイーパー（#203）と同じ 44pt の矩形で受ける。
                Button { zoomMode.toggle() } label: {
                    Image(systemName: zoomMode ? "minus.magnifyingglass" : "plus.magnifyingglass")
                        .font(.system(size: 13, weight: .bold))
                        .frame(
                            minWidth: SudokuMetrics.padButtonMinSide,
                            minHeight: SudokuMetrics.padButtonMinSide
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(zoomMode ? Theme.teal : Theme.surface)
                        )
                        .foregroundStyle(zoomMode ? .white : Theme.inkSub)
                        // 背景の角丸ではなく矩形全体を受ける（角の 44pt も取りこぼさない）。
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(zoomMode ? "盤全体を表示" : "盤を拡大")
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, SudokuMetrics.statusBarVerticalPadding)
        .popCard(corner: Theme.cornerSmall)
        // 3 つを別々に読ませるとスワイプ回数が増えるだけなので 1 要素にまとめる（#188）。
        .accessibilityElement(children: .contain)
    }

    private var difficultyAccent: Color {
        switch model.difficulty {
        case .easy:   return Theme.teal
        case .normal: return Theme.yellow
        case .hard:   return Theme.coral
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
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    boardGrid(cellSide: SudokuMetrics.zoomedCellSide)
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
        return VStack(spacing: 0) {
            ForEach(0..<SudokuEngine.size, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<SudokuEngine.size, id: \.self) { col in
                        cellView(
                            row: row, col: col, side: cellSide,
                            errors: errors, peers: peers, sameDigits: sameDigits
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
    private func blockLines(cellSide: CGFloat) -> some View {
        let full = cellSide * CGFloat(SudokuEngine.size)
        return ZStack(alignment: .topLeading) {
            ForEach(0...3, id: \.self) { i in
                let offset = cellSide * CGFloat(i * 3)
                Rectangle()
                    .fill(Theme.ink)
                    .frame(width: full, height: SudokuMetrics.blockBorderWidth)
                    .offset(y: min(offset, full - SudokuMetrics.blockBorderWidth))
            }
            ForEach(0...3, id: \.self) { i in
                let offset = cellSide * CGFloat(i * 3)
                Rectangle()
                    .fill(Theme.ink)
                    .frame(width: SudokuMetrics.blockBorderWidth, height: full)
                    .offset(x: min(offset, full - SudokuMetrics.blockBorderWidth))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func cellView(
        row: Int, col: Int, side: CGFloat,
        errors: Set<Int>, peers: Set<Int>, sameDigits: Set<Int>
    ) -> some View {
        let index = row * SudokuEngine.size + col
        let digit = model.board[index]
        let isGiven = model.given[index]
        let isSelected = model.selected == index
        let isError = errors.contains(index)
        let isHinted = model.hintedCells.contains(index)
        let noteDigits = (1...SudokuEngine.size).filter { model.hasNote($0, at: index) }

        return ZStack {
            Rectangle()
                .fill(cellFill(
                    isSelected: isSelected,
                    isPeer: peers.contains(index),
                    isSameDigit: sameDigits.contains(index),
                    isError: isError
                ))
            if digit != 0 {
                Text("\(digit)")
                    .font(.system(size: side * 0.58, weight: isGiven ? .black : .semibold, design: .rounded))
                    .foregroundStyle(digitColor(isGiven: isGiven, isError: isError, isHinted: isHinted))
                    .minimumScaleFactor(0.5)
            } else if !noteDigits.isEmpty {
                noteGrid(noteDigits: noteDigits, side: side)
            }
        }
        .frame(width: side, height: side)
        .border(Theme.inkSub.opacity(0.35), width: SudokuMetrics.cellBorderWidth)
        // 演出の修飾子はマスに **1 つだけ** 置く。入れ子にすると内側が外側のトランザクションを
        // 打ち消し、どちらかの演出が静かに効かなくなる（#199 で実際に踏んだ）。
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
        ZStack(alignment: .top) {
            playingControls
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            finishedControls { RecommendationCard.heightPlaceholder }
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if model.isFinished {
                finishedControls {
                    RecommendationSlot(services: services, isFinished: true)
                }
            } else if model.state == .playing {
                playingControls
                    // 盤と同じ理由でロックする（数字パッドからも答えを埋められるため）。
                    .disabled(isRequestingHint)
            } else if model.state == .idle {
                // 新規ゲームシートをキャンセルした直後（#354）。ここに何も出さないと空盤の下が
                // 無の領域になり、次に何をすればよいかが画面から読めない。シートを開き直す導線を置く。
                idleControls
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
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: SudokuMetrics.padButtonMinSide)
                    .background(Capsule().fill(Theme.coral))
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

    private func finishedControls<Recommendation: View>(
        @ViewBuilder recommendation: () -> Recommendation
    ) -> some View {
        VStack(spacing: 8) {
            resultControls
            recommendation()
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
                    .foregroundStyle(model.noteMode ? .white : Theme.inkSub)
                    .padding(.horizontal, 12)
                    .frame(minHeight: SudokuMetrics.padButtonMinSide)
                    .background(Capsule().fill(model.noteMode ? Theme.purple : Theme.surface))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pop)
            .accessibilityLabel(model.noteMode ? "メモモード、オン" : "メモモード、オフ")

            // 元に戻す（#353）。誤タップの救済用に**直前の1手だけ**取り消せる。
            Button { model.undo() } label: {
                Label("戻す", systemImage: "arrow.uturn.backward")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: SudokuMetrics.padButtonMinSide)
                    .background(Capsule().fill(model.canUndo ? Theme.teal : Theme.fillMuted))
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
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: SudokuMetrics.padButtonMinSide)
                    .background(Capsule().fill(model.canHint ? Theme.yellow : Theme.fillMuted))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pop)
            .disabled(!model.canHint || isRequestingHint)
            .accessibilityLabel(SudokuAccessibility.hintLabel(remaining: model.remainingHints))
            .accessibilityHint(model.canHint ? "広告を見ると選択中のマスの答えが入ります" : "答えを入れたいマスを選んでください")

            Spacer(minLength: 0)

            Button { showGiveUpConfirm = true } label: {
                Label("諦める", systemImage: "flag.fill")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: SudokuMetrics.padButtonMinSide)
                    .background(Capsule().fill(Theme.coral))
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
    /// 止めてある（`isRequestingHint` で `board` と数字パッドを無効化）が、
    /// それでも「広告を見たのにヒントが入らない」経路を残さないよう、
    /// 入れる先を選択状態から切り離しておく。
    private func requestHint() {
        guard !isRequestingHint, let target = model.selected, model.canHint(at: target) else { return }
        isRequestingHint = true
        Task {
            if await services.ads.showRewardedAd() {
                // 広告を見たのに入らなかったら黙って終わらせない（対価が無い状態を作らない）。
                if !model.applyHint(at: target) { showHintUnavailable = true }
            } else {
                showRewardNotEarned = true
            }
            isRequestingHint = false
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
                    // 広告のロード〜表示中の連打で2本目が失敗し、誤ってアラートが出るのを防ぐ
                    guard !isContinuing else { return }
                    isContinuing = true
                    Task {
                        // 視聴完了（報酬獲得）したときだけコンティニューを許可する
                        if await services.ads.showRewardedAd() {
                            model.continueAfterAd()
                        } else {
                            showContinueNotEarned = true
                        }
                        isContinuing = false
                    }
                } label: {
                    Label("広告を見てコンティニュー", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.coral)
                .disabled(isContinuing)
                Button("諦めて答えを見る") { model.giveUp() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Result Controls

    private var resultControls: some View {
        HStack(spacing: 12) {
            RecordLabel(model.recordResult)
                .lineLimit(1).minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            Button { showNewGame = true } label: {
                Label("次のゲーム", systemImage: "arrow.clockwise")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: SudokuMetrics.padButtonMinSide)
                    .background(Capsule().fill(Theme.coral))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pop)
        }
        .themeBody(14)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .popCard(corner: Theme.cornerSmall)
    }
}

// MARK: - New Game Sheet

struct SudokuNewGameSheet: View {
    let onStart: (SudokuDifficulty) -> Void
    let onCancel: () -> Void
    @State private var difficulty: SudokuDifficulty = .normal

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("難易度").themeBody(15).foregroundStyle(Theme.inkSub)
                    HStack(spacing: 12) {
                        // 「約」を付けるのは、唯一解を保てないマスは削れずに戻すため、実際の
                        // 空きマス数が範囲の上限に届かないことがあるから（`SudokuEngine` の
                        // `removalRange` のコメント参照・#354 の S6）。
                        chooser(.easy,   subtitle: "空き 約30〜35", accent: Theme.teal)
                        chooser(.normal, subtitle: "空き 約40〜45", accent: Theme.yellow)
                        chooser(.hard,   subtitle: "空き 約46〜50", accent: Theme.coral)
                    }
                }
                Spacer()
                Button {
                    onStart(difficulty)
                } label: {
                    Text("スタート").themeBody(18).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.coral)
            }
            .padding(Theme.pad)
            .popBackground()
            .navigationTitle("新規ゲーム")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
            }
        }
        .gameSheetDetents()
    }

    private func chooser(_ value: SudokuDifficulty, subtitle: String, accent: Color) -> some View {
        let selected = difficulty == value
        return Button {
            difficulty = value
        } label: {
            VStack(spacing: 4) {
                Text(value.label).themeTitle(20).foregroundStyle(selected ? .white : Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(subtitle).font(.system(size: 11, weight: .semibold, design: .rounded))
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
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
