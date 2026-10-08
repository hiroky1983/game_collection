import SwiftUI
import Core

/// 腰痛おじさんパズル（#1016・v1.1.11 で公開 #1904）のプレイ画面。
///
/// 盤の描画は `OjisanPuzzleModel.displayBoard`（盤 + 落下中の組）をそのまま並べるだけで、
/// 判定は一切持たない。操作は下のボタン列から Model の受け口を叩く。
public struct OjisanPuzzleView: View {
    private let services: GameServices
    @State private var model: OjisanPuzzleModel
    @Environment(\.scenePhase) private var scenePhase
    /// いま触っているドラッグで、すでに何マスぶん左右へ動かしたか（右が +）。
    @State private var appliedColumns = 0
    /// 同じく、すでに何マスぶん落としたか。
    @State private var appliedRows = 0
    /// 遊び方を選ぶ開始シート（#1920）。開いた直後は出しておき、選んでから始める。
    @State private var showSetup = true
    /// シートで選んでいる遊び方。最初は腰痛モード。
    @State private var setupMode: OjisanPuzzleMode = .backpain
    @State private var showConfirmNewGame = false
    /// 盤の 1 マスの大きさ。画面のどこで触っても同じ手触りになるよう、盤の外の操作もこれで刻む（#1946）。
    @State private var cellSide: CGFloat = 0

    /// 盤の内側の余白。
    private static let boardInset: CGFloat = 6

    public init(services: GameServices) {
        self.services = services
        #if DEBUG
        // 動作確認用: 腰痛ゲージを最初から高くして始める（`-simulateOjisanPain 85`）。
        // 高いゲージの手触り（落下が速い・操作が遅れる）と顔は、実際に十数個積まないと出せないため。
        // 他ゲームの `-simulateBlocks` / `-simulateRunner` と同じ作法で、製品には入らない。
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-simulateOjisanPain"),
           index + 1 < args.count, let pain = Int(args[index + 1]) {
            _model = State(initialValue: OjisanPuzzleModel(
                services: services,
                board: OjisanPuzzleBoard.emptyBoard(),
                current: OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2),
                pain: pain
            ))
            _showSetup = State(initialValue: false)
            return
        }
        // 動作確認用: 遊び方を指定して開始シート無しで始める（`-simulateOjisanMode puzzle`）。
        if let index = args.firstIndex(of: "-simulateOjisanMode"),
           index + 1 < args.count, let mode = OjisanPuzzleMode(rawValue: args[index + 1]) {
            _model = State(initialValue: OjisanPuzzleModel(services: services, mode: mode))
            _showSetup = State(initialValue: false)
            return
        }
        #endif
        // 開始シートで遊び方を選ぶまで `game_start` は送らない（既定の遊び方で数えない）。
        _model = State(initialValue: OjisanPuzzleModel(services: services, announcesStart: false))
    }

    public var body: some View {
        VStack(spacing: 12) {
            header
            HStack(alignment: .top, spacing: 12) {
                boardView
                sidePanel
            }
            controlHint
            // 終局したら次に遊ぶゲームを勧める枠（#52・#722）。全ゲーム共通の部品をそのまま置く。
            RecommendationArea(services: services, isFinished: model.outcome != nil)
            Spacer(minLength: 0)
        }
        .padding()
        // 操作は盤の外（画面のどこ）でも受ける（#1946）。ボタンは子として先に反応するので、タップは奪わない。
        .contentShape(Rectangle())
        .gesture(dragGesture(step: max(24, cellSide)))
        // リザルトは盤の上ではなく画面全体に重ねる（盤は 6×12 で細長く、中に置くと文字が折り返す）。
        .overlay { if model.outcome != nil { resultOverlay } }
        // 新規ボタンは全ゲーム共通の部品を使う（`GameChromeTests` が自前のボタンを禁じている）。
        .gameChrome(title: "腰痛おじさんパズル", review: services.review,
                    newGame: GameChromeNewGame(.solo) {
                        if model.hasProgress {
                            showConfirmNewGame = true
                        } else {
                            openSetup()
                        }
                    })
        .sheet(isPresented: $showSetup) {
            OjisanPuzzleSetupSheet(mode: $setupMode) {
                showSetup = false
                // 何も置かずに同じ遊び方で始めるなら、開いた直後の局をそのまま使う
                // （始め直すと `game_start` が二重に数えられる）。
                if setupMode == model.mode, !model.hasProgress, model.outcome == nil {
                    model.announceStartIfNeeded()
                    model.resume()
                } else {
                    withGameAnimation { model.newGame(mode: setupMode) }
                }
            } onCancel: {
                showSetup = false
                model.announceStartIfNeeded()
            }
        }
        .dialogs { anchor in
            anchor.confirmationDialog("新規ゲームを始めますか？", isPresented: $showConfirmNewGame, titleVisibility: .visible) {
                Button("終了して新規ゲーム", role: .destructive) { openSetup() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("途中で終了すると、いまの盤面と得点が失われます。")
            }
        }
        .task { if !showSetup { model.resume() } }
        .onDisappear { model.pause() }
        .onChange(of: showConfirmNewGame) { _, isShown in
            // 確認を聞いているあいだも荷物を落とさない。
            if isShown { model.pause() } else if !showSetup { model.resume() }
        }
        .onChange(of: showSetup) { _, isShown in
            // 選んでいるあいだは荷物を落とさない。閉じたら（キャンセルも含め）続きから。
            if isShown { model.pause() } else { model.resume() }
        }
        .onChange(of: scenePhase) { _, phase in
            // 裏に回っているあいだに荷物が落ち続けないようにする。
            if phase == .active, !showSetup { model.resume() } else { model.pause() }
        }
    }

    /// 開始シートを開く。シートの初期選択は、いま遊んでいる遊び方。
    private func openSetup() {
        setupMode = model.mode
        showSetup = true
    }

    // MARK: - 見出し（スコア・連鎖・腰痛ゲージ）

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("スコア")
                    .font(.system(size: 12, weight: .bold, design: .rounded)) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.score)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit()) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            if model.lastChain > 1 {
                Text("\(model.lastChain)連鎖")
                    .font(.system(size: 16, weight: .bold, design: .rounded)) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
                    .foregroundStyle(Theme.coral)
                    // 同じ連鎖数が続くと値が変わらずトランジションが再生されないので、
                    // 連鎖のたびに増える通し番号を `.id` にする（ブロックならべと同じ手）。
                    .id(model.chainEventID)
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer(minLength: 0)
            // ゲージはパズルモードには無い（見た目の違いはここだけ）。
            if model.mode.hasGauge { painGauge }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        .gameAnimation(.easeOut(duration: 0.2), value: model.chainEventID)
    }

    private var painGauge: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("腰痛 \(model.pain)　\(model.painStage.caption)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit()) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
                .foregroundStyle(model.painStage == .easy ? Theme.inkSub : Theme.coral)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fillMuted.opacity(0.22))
                GeometryReader { geo in
                    Capsule()
                        .fill(Self.painColor(model.painStage))
                        .frame(width: max(0, geo.size.width) * painRatio)
                }
            }
            .frame(width: 128, height: 8)
            if let remaining = model.millisecondsUntilRise {
                Text("せり上がりまで \((remaining + 999) / 1000)秒")
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit()) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
                    .foregroundStyle(Theme.inkSub)
            }
        }
        .gameAnimation(.easeInOut(duration: 0.2), value: model.pain)
    }

    private var painRatio: CGFloat {
        CGFloat(model.pain) / CGFloat(OjisanPuzzlePain.limit)
    }

    private static func painColor(_ stage: OjisanPuzzlePain.Stage) -> Color {
        switch stage {
        case .easy: Theme.Fill.teal
        case .aching: Theme.Fill.yellow
        case .severe: Theme.Fill.coral
        }
    }

    // MARK: - おじさん

    /// 腰の痛みを全身の姿で出す（会長指示 2026-09-17・絵の差し替えは #1909）。数字のバーより姿が崩れるほうが伝わる。
    /// 絵は作業服おじさんのドット絵（`OjisanPuzzleArt`）。段階ごとにコマを替える。
    private func ojisanFigure() -> some View {
        OjisanPuzzleArt.image(OjisanPuzzleArt.pose(for: model.painStage))
            .frame(width: Self.figureBoxWidth, height: Self.figureBoxHeight)
            .gameAnimation(.easeInOut(duration: 0.2), value: model.painStage)
    }

    /// 右の列の幅と、おじさんを置く箱（立ちポーズの最大 40×47 ドット ＝ 80×94pt が収まる大きさ）。
    static let sideWidth: CGFloat = 104
    static let figureBoxWidth: CGFloat = 88
    static let figureBoxHeight: CGFloat = 96

    // MARK: - 盤

    private var boardView: some View {
        GeometryReader { geo in
            // GeometryReader は最初に 0 を渡してくるので、0 でも割らない・負にしない（#874 と同じ守り）。
            let cell = max(0, min(
                (geo.size.width - Self.boardInset * 2) / CGFloat(OjisanPuzzleBoard.columns),
                (geo.size.height - Self.boardInset * 2) / CGFloat(OjisanPuzzleBoard.rows)
            ))
            let board = model.displayBoard
            VStack(spacing: 1) {
                ForEach(0..<OjisanPuzzleBoard.rows, id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(0..<OjisanPuzzleBoard.columns, id: \.self) { col in
                            luggage(board[row][col], side: max(0, cell - 1))
                        }
                    }
                }
            }
            // マスの中身が替わるたびに空き⇄荷物がクロスフェードして点滅して見えるので、盤の中は補間しない（#1946）。
            .transaction { $0.animation = nil }
            .padding(Self.boardInset)
            .frame(width: geo.size.width, height: geo.size.height)
            .background {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.fillMuted.opacity(0.18))
            }
            // 片付けのライン（腰痛モードだけ）。この線より上に荷物が無くなればクリア。
            .overlay(alignment: .topLeading) {
                if let line = model.clearLineRow {
                    clearLine(width: geo.size.width)
                        .offset(y: Self.boardInset + CGFloat(line) * cell - 1)
                }
            }
            .onChange(of: cell, initial: true) { _, newValue in cellSide = newValue }
        }
        .aspectRatio(CGFloat(OjisanPuzzleBoard.columns) / CGFloat(OjisanPuzzleBoard.rows), contentMode: .fit)
    }

    /// クリアのラインの破線。
    private func clearLine(width: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: Self.boardInset, y: 1))
            path.addLine(to: CGPoint(x: max(Self.boardInset, width - Self.boardInset), y: 1))
        }
        .stroke(Theme.coral, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        .frame(width: width, height: 2)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// 荷物 1 個。**ピースそのものが荷物の形に見える**絵にする（会長指示 2026-10-07・#1909）。
    /// 5 種は形で見分けが付く（`OjisanPuzzleLuggageArt`）。空きマスだけ薄い四角を敷く。
    @ViewBuilder
    private func luggage(_ value: Int, side: CGFloat) -> some View {
        if OjisanPuzzleLuggage.kind(value) == nil {
            RoundedRectangle(cornerRadius: max(1, side * 0.24), style: .continuous)
                .fill(Theme.fillMuted.opacity(0.14))
                .frame(width: side, height: side)
        } else {
            OjisanPuzzleLuggageArt(value: value)
                .frame(width: side, height: side)
                .accessibilityElement()
                .accessibilityLabel(OjisanPuzzleLuggage.kind(value)?.name ?? "")
        }
    }

    // MARK: - 操作（スワイプ・タップ）

    /// 画面全体で受ける操作（会長指示 2026-09-17: 左右ボタンは置かない・#1946: 盤の外でも動かせる）。
    ///
    /// - 横スワイプ … 1 マスずつ左右へ動かす
    /// - 下スワイプ … 1 マスずつ落とす（ソフトドロップ）
    /// - タップ … 回す
    ///
    /// 指に張り付かせず `step`（1 マスぶん）で刻むのは、落ちものの標準的な手触りに合わせるため。
    /// 「これまでに何マスぶん適用したか」を持ち、指の総移動量との差だけを追いかける
    /// （毎フレームの差分を足すと、ゆっくり動かしたときに取りこぼす）。
    private func dragGesture(step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard model.outcome == nil, !showSetup else { return }
                let columns = OjisanPuzzleDrag.steps(value.translation.width, step: step)
                while appliedColumns < columns { appliedColumns += 1; model.move(by: 1) }
                while appliedColumns > columns { appliedColumns -= 1; model.move(by: -1) }

                // 下方向だけ拾う（上スワイプには何も割り当てない）。
                let rows = OjisanPuzzleDrag.downSteps(value.translation.height, step: step)
                while appliedRows < rows { appliedRows += 1; model.softDrop() }
            }
            .onEnded { value in
                if OjisanPuzzleDrag.isTap(
                    translation: value.translation,
                    movedColumns: appliedColumns,
                    movedRows: appliedRows
                ) {
                    withGameAnimation(.easeOut(duration: 0.1)) { model.rotate(clockwise: true) }
                }
                appliedColumns = 0
                appliedRows = 0
            }
    }

    // MARK: - 次の荷物

    private var sidePanel: some View {
        VStack(spacing: 10) {
            // おじさん本人。盤の横でずっと腰の具合を訴えている。
            VStack(spacing: 4) {
                ojisanFigure()
                if model.mode.hasGauge {
                    Text(model.painStage.caption)
                        .font(.system(size: 10, weight: .bold, design: .rounded)) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
                        .foregroundStyle(model.painStage == .easy ? Theme.inkSub : Theme.coral)
                }
            }
            .frame(width: Self.sideWidth)
            .padding(.vertical, 10)
            // 限界のときは面そのものを痛い色にして、目の端でも分かるようにする。
            .popCard(fill: model.painStage == .severe ? Theme.Fill.coral.opacity(0.28) : Theme.surface,
                     corner: Theme.cornerSmall)

            VStack(spacing: 6) {
                Text("つぎ")
                    .font(.system(size: 12, weight: .bold, design: .rounded)) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
                    .foregroundStyle(Theme.inkSub)
                VStack(spacing: 2) {
                    luggage(model.next.childKind, side: 26)
                    luggage(model.next.axisKind, side: 26)
                }
            }
            .frame(width: Self.sideWidth)
            .padding(.vertical, 12)
            .popCard(corner: Theme.cornerSmall)

            // 盤と同じ高さまで白い面を伸ばさない（カードは中身ぶんだけ）。
            Spacer(minLength: 0)
        }
    }

    // MARK: - 操作の説明

    /// 操作はすべて盤の上のスワイプ・タップなので、代わりに 1 行だけ遊び方を出す。
    private var controlHint: some View {
        HStack(spacing: 14) {
            hintItem("よこにスワイプ", systemImage: "arrow.left.and.right")
            hintItem("タップで回す", systemImage: "arrow.clockwise")
            hintItem("下スワイプ", systemImage: "arrow.down")
        }
        .font(.system(size: 11, weight: .bold, design: .rounded)) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
        .foregroundStyle(Theme.inkSub)
    }

    private func hintItem(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
    }

    // MARK: - 決着

    private var resultTitle: String {
        switch model.outcome {
        case .hospitalized: "入院！"
        case .cleared: "かたづいた！"
        default: "積みあがった！"
        }
    }

    private var resultMessage: String {
        switch model.outcome {
        case .hospitalized: "腰が限界です。おだいじに。"
        case .cleared: "荷物がラインより下になりました。"
        default: "荷物が天井まで届きました。"
        }
    }

    /// 秒数を「m:ss」にする。
    static func timeText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var resultOverlay: some View {
        VStack(spacing: 10) {
            if model.outcome == .hospitalized {
                // 倒れたおじさん（70×27 ドット）。
                OjisanPuzzleArt.image(.fallen)
            } else {
                // 作業服の全身ドット絵（#1946）。クリアは笑顔、積み上がりは汗のコマ。
                OjisanPuzzleArt.image(model.outcome == .cleared ? .easy : .aching)
            }
            Text(resultTitle)
                .font(.system(size: 24, weight: .heavy, design: .rounded)) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
                .foregroundStyle(Theme.ink)
            Text(resultMessage)
                .font(.system(size: 14, weight: .semibold, design: .rounded)) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
                .foregroundStyle(Theme.inkSub)
                .multilineTextAlignment(.center)
            if model.outcome == .cleared {
                Text("タイム \(Self.timeText(model.elapsedMilliseconds / 1000))")
                    .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit()) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
                    .foregroundStyle(Theme.ink)
            }
            Text("スコア \(model.score)")
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit()) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
                .foregroundStyle(Theme.ink)
            // 自己ベストの 1 行（他ゲームのリザルトと同じ共通部品・#1904）。
            RecordLabel(model.recordResult)
            Button {
                withGameAnimation { model.newGame() }
            } label: {
                Text("もう一度")
                    .font(.system(size: 17, weight: .bold, design: .rounded)) // fixed-size: 試作から移したままの寸法。文字サイズ設定への追従は作り込みの別 issue で扱う（#1904）
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                            .fill(Theme.Fill.coral)
                    )
            }
            .buttonStyle(.pop)
        }
        .padding(22)
        .popCard()
        .padding(12)
    }
}
