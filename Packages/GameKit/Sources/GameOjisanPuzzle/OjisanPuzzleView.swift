import SwiftUI
import Core

/// おじさんの荷物運びパズル（#1016・v1.1.11 で公開 #1904）のプレイ画面。
///
/// 盤の描画は `OjisanPuzzleModel.displayBoard`（盤 + 落下中の組）をそのまま並べるだけで、
/// 判定は一切持たない。操作は下のボタン列から Model の受け口を叩く。
public struct OjisanPuzzleView: View {
    private let services: GameServices
    @State private var model: OjisanPuzzleModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// いま触っているドラッグで、すでに何マスぶん左右へ動かしたか（右が +）。
    @State private var appliedColumns = 0
    /// 同じく、すでに何マスぶん落としたか。
    @State private var appliedRows = 0
    /// いま触っているドラッグが受け持つ向き。決まったら指を離すまで変えない（下へ払うときの横流れを拾わない・#2063）。
    @State private var dragAxis: OjisanPuzzleDrag.Axis?
    /// いま触っているドラッグが始まった時刻。下へ払う速さを測る（#2810）。
    @State private var dragStartedAt: Date?
    /// このドラッグですでに一気に落としたか。落としたあとの指の動きは、次に出る組へ流さない。
    @State private var didHardDrop = false
    /// 「速く下に払うと一気に落とせる」の初回案内を出すか（#2810）。更新後に初めてこのゲームを開いたとき 1 回だけ。
    @State private var showFlickGuide: Bool
    /// 遊び方を選ぶ開始シート（#1920）。開いた直後は出しておき、選んでから始める。
    @State private var showSetup = true
    /// シートで選んでいる遊び方。最初は荷運びモード。
    @State private var setupMode: OjisanPuzzleMode = .backpain
    @State private var showConfirmNewGame = false
    /// 遊び方（「？」）のシートを開いているか。背面から戻ったときに、読んでいるあいだの荷物を動かさないために持つ（#2353）。
    @State private var showHowTo = false
    /// 盤の 1 マスの大きさ。画面のどこで触っても同じ手触りになるよう、盤の外の操作もこれで刻む（#1946）。
    @State private var cellSide: CGFloat = 0
    /// 決着の結果シートを出してよいか。決着の瞬間は盤の上に一言だけ出し、少し置いてから結果に切り替える（#1954）。
    @State private var showResult = false
    /// 負けたあとの「広告を見て続ける」の段取り（連打ガード・広告・失敗アラート。#2013）。
    @State private var continueRescue = RewardedRescue()

    /// 決着してから結果シートを出すまでの間。何が起きて終わったかを盤で見せる時間。
    private static let resultDelay: Duration = .milliseconds(1200)

    /// 盤の内側の余白。
    private static let boardInset: CGFloat = 6

    /// 一気落としの案内の「見た」印。ゲーム ID のミニガイドとは別のキー（更新前から遊んでいる人にも出すため）。
    static let flickGuideKey = "ojisan_puzzle.hardDrop"

    public init(services: GameServices) {
        self.services = services
        // 撮影モードでは出さず、印も消費しない（ストア用スクショへの写り込み防止。ランナーの導入と同じ作法）。
        let isScreenshot = ProcessInfo.processInfo.arguments.contains("-screenshotMode")
        _showFlickGuide = State(
            initialValue: !isScreenshot && (services.playLog?.markGuideShown(for: Self.flickGuideKey) ?? false)
        )
        #if DEBUG
        // 動作確認用: 腰痛ゲージを最初から高くして始める（`-simulateOjisanPain 85`）。
        // 高いゲージの手触り（落下が速い・操作が遅れる）と顔は、実際に十数個積まないと出せないため。
        // 他ゲームの `-simulateBlocks` / `-simulateRunner` と同じ作法で、製品には入らない。
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-simulateOjisanPain"),
           index + 1 < args.count, let pain = Int(args[index + 1]) {
            // 盤は荷運びモードの開始時と同じ積み方・ライン・せり上がりにする（見出しのゲージを本番と同じ画面で確かめる・#2064）。
            var rng = OjisanPuzzleRandom(seed: 2064)
            _model = State(initialValue: OjisanPuzzleModel(
                services: services,
                board: OjisanPuzzleCleanup.initialBoard(using: &rng),
                current: OjisanPuzzleBoard.spawn(axisKind: 1, childKind: 2),
                pain: pain,
                clearLineRow: OjisanPuzzleCleanup.clearLineRow,
                riseIntervalMilliseconds: OjisanPuzzleCleanup.riseIntervalMilliseconds
            ))
            _showSetup = State(initialValue: false)
            return
        }
        // 動作確認用: 出る列が天井まで積まれた盤で始め、次の固定で積み上がりにする（`-simulateOjisanBuried`・#2064 の結果の絵の確認）。
        if args.contains("-simulateOjisanBuried") {
            var board = OjisanPuzzleBoard.emptyBoard()
            for row in 2..<OjisanPuzzleBoard.rows { board[row][OjisanPuzzleBoard.spawnColumn] = row % 2 + 1 }
            _model = State(initialValue: OjisanPuzzleModel(
                services: services,
                board: board,
                current: OjisanPuzzleBoard.spawn(axisKind: 3, childKind: 4)
            ))
            _showSetup = State(initialValue: false)
            return
        }
        // 動作確認用: 遊び方を指定して開始シート無しで始める（`-simulateOjisanMode puzzle`）。
        if let index = args.firstIndex(of: "-simulateOjisanMode"),
           index + 1 < args.count, let mode = OjisanPuzzleMode(rawValue: args[index + 1]) {
            let launched = OjisanPuzzleModel(services: services, mode: mode)
            // 動作確認用: 一時停止の画面で始める（`-simulateOjisanPaused`・#2135）。
            if args.contains("-simulateOjisanPaused") { launched.pauseByUser() }
            _model = State(initialValue: launched)
            _showSetup = State(initialValue: false)
            return
        }
        #endif
        // 開始シートで遊び方を選ぶまで `game_start` は送らない（既定の遊び方で数えない）。
        _model = State(initialValue: OjisanPuzzleModel(services: services, announcesStart: false))
    }

    public var body: some View {
        VStack(spacing: 12) {
            playArea
            // 画面下のバナーは他の公開ゲームと同じ共通部品（収益対策・v1.1.11）。
            // 操作の受け口（`playArea` のジェスチャ）の外に置き、バナー上のドラッグで荷物を動かさない。
            BannerSlot(ads: services.ads)
        }
        .padding()
        .rewardOffer(continueRescue, for: .continue, isPresented: showResult && model.canContinue,
                     services: services, gameID: OjisanPuzzleModel.gameID)
        .rewardedRescueAlerts(
            continueRescue,
            notEarned: tr("続けられませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("続けられませんでした"),
                message: tr("広告を見ているあいだに新しいゲームが始まったため、続けられませんでした。")
            )
        )
        .task(id: model.outcome) {
            guard model.outcome != nil else { showResult = false; return }
            try? await Task.sleep(for: Self.resultDelay)
            guard !Task.isCancelled else { return }
            showResult = true
        }
        // 新規ボタンは全ゲーム共通の部品を使う（`GameChromeTests` が自前のボタンを禁じている）。
        .gameChrome(title: tr("おじさんの荷物運びパズル"), review: services.review,
                    newGame: GameChromeNewGame(.solo) { startNewGameFromMenu() })
        // 図入りの遊び方（#2044 の先駆け）。`?` はヘッダー右に自動で並ぶ。読んでいるあいだは荷物を落とさない。
        // 内容は遊んでいるモードに合わせる（会長指示 2026-10-12。パズルモード中に腰痛ゲージ・入院・
        // クリアライン・せり上がりを出さない）。
        .howToPlay(howToPlayGuide,
                   onPresent: { showHowTo = true; model.pause() },
                   onDismiss: {
                       showHowTo = false
                       if !showSetup, scenePhase == .active { model.resume() }
                   })
        .sheet(isPresented: $showSetup) {
            OjisanPuzzleSetupSheet(mode: $setupMode) {
                showSetup = false
                // 何も置かずに同じ遊び方で始めるなら、開いた直後の局をそのまま使う
                // （始め直すと `game_start` が二重に数えられる）。
                if setupMode == model.mode, !model.hasProgress, model.outcome == nil {
                    model.announceStartIfNeeded()
                    // 一時停止の「はじめから」から来たときも止めたままにしない（CodeRabbit 指摘・#2135）。
                    model.resumeFromUserPause()
                } else {
                    withGameAnimation { model.newGame(mode: setupMode) }
                }
            } onCancel: {
                showSetup = false
                model.announceStartIfNeeded()
            }
        }
        .dialogs { anchor in
            anchor.confirmationDialog(tr("新規ゲームを始めますか？"), isPresented: $showConfirmNewGame, titleVisibility: .visible) {
                Button(tr("終了して新規ゲーム"), role: .destructive) { openSetup() }
                Button(tr("キャンセル"), role: .cancel) {}
            } message: {
                Text(tr("途中で終了すると、いまの盤面と得点が失われます。"))
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
            if OjisanPuzzleResume.shouldResume(phase: phase, showSetup: showSetup, showHowTo: showHowTo) {
                model.resume()
            } else {
                model.pause()
            }
        }
    }

    /// バナーを除いた遊ぶ部分。操作とリザルトはこの範囲に載せる。
    private var playArea: some View {
        VStack(spacing: 12) {
            header
            HStack(alignment: .top, spacing: 12) {
                boardView
                sidePanel
            }
            if showFlickGuide { flickGuide } else { controlHint }
            // 終局したら次に遊ぶゲームを勧める枠（#52・#722）。全ゲーム共通の部品をそのまま置く。
            // 一時停止ボタンは、高さが常に確保されているこの枠の右端に相乗りさせる（ブロック崩しと同じ位置・盤を削らない・#2135）。
            HStack(alignment: .center, spacing: 12) {
                RecommendationArea(services: services, isFinished: model.outcome != nil)
                pauseButton
            }
            Spacer(minLength: 0)
        }
        // 操作は盤の外（画面のどこ）でも受ける（#1946）。ボタンは子として先に反応するので、タップは奪わない。
        .contentShape(Rectangle())
        .gesture(dragGesture(step: max(24, cellSide)))
        // リザルトは盤の上ではなく遊ぶ部分全体に重ねる（盤は 6×12 で細長く、中に置くと文字が折り返す）。
        // バナーには重ねない（幕の裏のバナーを残さない・`docs/spec-app.md`「広告仕様」）。
        .overlay { if model.outcome != nil, showResult { resultOverlay } }
    }

    // MARK: - 一時停止（#2135）

    /// 一時停止ボタン。見た目・押せる領域は他ゲームの一時停止ボタンと同じ（珊瑚色の円・44pt）。
    private var pauseButton: some View {
        Button {
            if model.isUserPaused { model.resumeFromUserPause() } else { model.pauseByUser() }
        } label: {
            Image(systemName: model.isUserPaused ? "play.fill" : "pause.fill")
                .scaledFont(18, weight: .bold)
                .frame(width: BoardGameControlMetrics.minTapTarget, height: BoardGameControlMetrics.minTapTarget)
                .background(Circle().fill(Theme.Fill.coral))
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.pop)
        .accessibilityLabel(model.isUserPaused ? tr("再開") : tr("一時停止"))
        // 止めるものが無い（決着した）あとは押せない。
        .disabled(model.outcome != nil)
        .opacity(model.outcome != nil ? 0.35 : 1)
    }

    private var pausedOverlay: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.6))
            VStack(spacing: 12) {
                Text(tr("一時停止")).font(.title3.bold()).foregroundStyle(.white)
                GameDeadEndActionButton(tr("再開"), systemImage: "play.fill", tint: Theme.Fill.coral) {
                    model.resumeFromUserPause()
                }
                // 新規ゲームと同じ入口（進行があれば確認を挟む）。
                GameDeadEndDismissButton(tr("はじめから")) { startNewGameFromMenu() }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    /// 盤と「つぎ」の荷物を隠すか。一時停止中（決着前）だけ隠す。
    private var hidesLuggage: Bool { Self.hidesLuggage(isUserPaused: model.isUserPaused, outcome: model.outcome) }

    /// 一時停止中は荷物を見せない（止めて次の置き場所を考えるのを防ぐ・会長指示 2026-10-12・#2135）。
    /// 腰痛ゲージ・スコアは隠さない。**テストから分岐を確かめるため internal static**。
    static func hidesLuggage(isUserPaused: Bool, outcome: OjisanPuzzleModel.Outcome?) -> Bool {
        isUserPaused && outcome == nil
    }

    /// 盤に描く中身。隠すときは同じ大きさの空の盤を返す（枠の大きさは変えない）。
    static func visibleBoard(_ board: [[Int]], hidesLuggage: Bool) -> [[Int]] {
        hidesLuggage ? OjisanPuzzleBoard.emptyBoard() : board
    }

    /// 「つぎ」の欄に描く 2 つ。隠すときは空のマス（0）にする。
    static func visibleNextKinds(child: Int, axis: Int, hidesLuggage: Bool) -> (child: Int, axis: Int) {
        hidesLuggage ? (0, 0) : (child, axis)
    }

    /// 新規ゲームの入口。進行があれば確認、無ければ開始シート。
    private func startNewGameFromMenu() {
        if model.hasProgress { showConfirmNewGame = true } else { openSetup() }
    }

    /// 開始シートを開く。シートの初期選択は、いま遊んでいる遊び方。
    private func openSetup() {
        setupMode = model.mode
        showSetup = true
    }

    /// 「？」の遊び方。遊んでいるモードに合わせて文言・図を出し分ける（会長指示 2026-10-12）。
    /// 先頭には同じモードの図で見る「はじめての遊び方」（#2826）の入口が付く。
    private var howToPlayGuide: HowToPlayGuide {
        model.mode.howToPlayGuide.onboarding(OjisanPuzzleOnboarding.guide(mode: model.mode))
    }

    // MARK: - 見出し（荷運びモード: 腰痛ゲージ／パズルモード: スコア・連鎖）

    /// 荷運びモードは見出しをゲージ専用にし、スコア・連鎖は右の列の小カードへ移す（#2064 案B・会長決定 2026-10-11）。
    /// パズルモードはゲージが無いので、従来どおり見出しにスコアを出す。
    @ViewBuilder
    private var header: some View {
        if model.mode.hasGauge {
            gaugeHeader
        } else {
            scoreHeader
        }
    }

    private var scoreHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("スコア"))
                    .scaledFont(12, weight: .bold, design: .rounded, maxScale: 1.2)
                    .foregroundStyle(Theme.inkSubText)
                Text("\(model.score)")
                    .scaledFont(26, weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
                    // 桁が増えても折り返さない（見出しの高さ＝盤の大きさが揺れるため・#2063）。
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            if model.lastChain > 1 {
                Text(tr("%lld連鎖", model.lastChain))
                    .scaledFont(16, weight: .bold, design: .rounded, maxScale: 1.2)
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(Theme.coralText)
                    // 同じ連鎖数が続くと値が変わらずトランジションが再生されないので、
                    // 連鎖のたびに増える通し番号を `.id` にする（ブロックならべと同じ手）。
                    .id(model.chainEventID)
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if let best = model.liveBestScore {
                HeaderBestStat(title: tr("ベスト"), value: RecordFormat.number(best))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
        .gameAnimation(.easeOut(duration: 0.2), value: model.chainEventID)
    }

    /// 腰痛ゲージの見出し（#2064 案B）。カード幅いっぱいの太いバーに 3 段の地色を敷き、その上を段階色で塗る。
    /// 限界（80 以上）はバーとカードの枠を珊瑚色にし、枠を約 0.5 秒ごとに点滅させる（Reduce Motion では点けたまま）。
    private var gaugeHeader: some View {
        let isWarning = model.painStage == .severe
        return Group {
            // 決着したら点滅は止めて点けたままにする（結果を見ている裏で枠がちらつかない）。
            if isWarning, !reduceMotion, model.outcome == nil {
                TimelineView(.periodic(from: .now, by: Self.blinkInterval)) { context in
                    gaugeCard(warning: true, lit: Self.isBlinkLit(context.date))
                }
            } else {
                gaugeCard(warning: isWarning, lit: true)
            }
        }
        .gameAnimation(.easeInOut(duration: 0.2), value: model.pain)
    }

    /// 点滅の 1 コマの長さ。
    private static let blinkInterval: TimeInterval = 0.5

    /// 点滅の明るいコマか。時刻から決めるので、状態を持たずに TimelineView の更新だけで切り替わる。
    private static func isBlinkLit(_ date: Date) -> Bool {
        Int(date.timeIntervalSinceReferenceDate / blinkInterval).isMultiple(of: 2)
    }

    /// 見出しのカードの高さ。値・段階・警告で文字が変わっても高さを変えない（見出しの高さ＝盤の大きさ・#2063）。
    private static let gaugeCardHeight: CGFloat = 62
    /// バーの太さ。
    private static let gaugeBarHeight: CGFloat = 20

    private func gaugeCard(warning: Bool, lit: Bool) -> some View {
        let stage = model.painStage
        let caption = warning
            ? tr("こしが限界！ あと %lld で入院", max(0, OjisanPuzzlePain.limit - model.pain))
            : stage.caption
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(tr("腰痛ゲージ"))
                    .scaledFont(12, weight: .bold, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.inkSubText)
                    .fixedSize()
                Text(caption)
                    .scaledFont(12, weight: .bold, design: .rounded, maxScale: 1.15).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(stage == .easy ? Theme.inkSubText : Theme.coralText)
                Spacer(minLength: 0)
                Text("\(model.pain)")
                    .scaledFont(20, weight: .heavy, design: .rounded, maxScale: 1.15).monospacedDigit()
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(warning ? Theme.coralText : Theme.ink)
                    .contentTransition(.numericText())
            }
            gaugeBar(stage: stage, dimmed: warning && !lit)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.gaugeCardHeight)
        .popCard(fill: warning && lit ? Theme.Fill.coral.opacity(0.10) : Theme.surface,
                 corner: Theme.cornerSmall)
        .overlay {
            if warning && lit {
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .strokeBorder(Theme.coral, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("腰痛ゲージ %1$lld、%2$@", model.pain, caption))
    }

    /// 太いバー。3 段の地色（青緑・黄・珊瑚を薄く）の上を、いまの段階の色で塗る。段の境目に白い目盛を入れる。
    private func gaugeBar(stage: OjisanPuzzlePain.Stage, dimmed: Bool) -> some View {
        let barHeight = Self.gaugeBarHeight
        let limit = CGFloat(OjisanPuzzlePain.limit)
        let bounds = [0] + OjisanPuzzlePain.stageThresholds + [OjisanPuzzlePain.limit]
        return GeometryReader { geo in
            // GeometryReader は最初に 0 を渡してくるので、0 でも負の幅にしない（#874 と同じ守り）。
            let width = max(0, geo.size.width)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous)
                    .fill(Theme.fillMuted.opacity(0.15))
                ForEach(Array(OjisanPuzzlePain.Stage.allCases.enumerated()), id: \.offset) { index, zone in
                    let from = CGFloat(bounds[index]) / limit * width
                    let to = CGFloat(bounds[index + 1]) / limit * width
                    Rectangle()
                        .fill(Self.painColor(zone).opacity(0.22))
                        .frame(width: max(0, to - from - 1), height: max(0, barHeight - 6))
                        .offset(x: from + (index == 0 ? 0 : 1))
                }
                if model.pain > 0 {
                    RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous)
                        .fill(Self.painColor(stage).opacity(dimmed ? 0.4 : 1))
                        .frame(width: min(width, max(width * painRatio, barHeight)))
                }
                ForEach(OjisanPuzzlePain.stageThresholds, id: \.self) { threshold in
                    Rectangle()
                        .fill(Theme.surface)
                        .frame(width: 1.5, height: barHeight)
                        .offset(x: CGFloat(threshold) / limit * width - 0.75)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous))
        }
        .frame(height: barHeight)
    }

    private var painRatio: CGFloat {
        min(1, max(0, CGFloat(model.pain) / CGFloat(OjisanPuzzlePain.limit)))
    }

    private static func painColor(_ stage: OjisanPuzzlePain.Stage) -> Color {
        switch stage {
        case .easy: Theme.Fill.teal
        case .aching: Theme.Fill.yellow
        case .severe: Theme.Fill.coral
        }
    }

    /// 荷運びモードの右の列の一番上に置くスコアの小カード（#2064 案B）。連鎖と、せり上がりまでの秒数もここに出す。
    /// 連鎖の行は出ていないときも場所を取っておき、カードの高さ（＝下のおじさんの位置）を揺らさない。
    private var scoreCard: some View {
        VStack(spacing: 2) {
            Text(tr("スコア"))
                .scaledFont(11, weight: .bold, design: .rounded, maxScale: 1.15)
                .foregroundStyle(Theme.inkSubText)
            Text("\(model.score)")
                .scaledFont(20, weight: .heavy, design: .rounded, maxScale: 1.15).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(model.lastChain > 1 ? tr("%lld連鎖", model.lastChain) : " ")
                .scaledFont(11, weight: .bold, design: .rounded, maxScale: 1.15)
                .lineLimit(1)
                .foregroundStyle(Theme.coralText)
                .id(model.chainEventID)
                .transition(.scale.combined(with: .opacity))
            if let remaining = model.millisecondsUntilRise {
                Text(tr("せり上がり %lld秒", (remaining + 999) / 1000))
                    .scaledFont(10, weight: .bold, design: .rounded, maxScale: 1.15).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(Theme.inkSubText)
            }
        }
        .frame(width: Self.sideWidth)
        .padding(.vertical, 8)
        .popCard(corner: Theme.cornerSmall)
        .gameAnimation(.easeOut(duration: 0.2), value: model.chainEventID)
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
            // 一時停止中は荷物を描かない（止めて次の置き場所を考えられないようにする・会長指示 2026-10-12・#2135）。
            let board = Self.visibleBoard(model.displayBoard, hidesLuggage: hidesLuggage)
            VStack(spacing: 1) {
                ForEach(0..<OjisanPuzzleBoard.rows, id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(0..<OjisanPuzzleBoard.columns, id: \.self) { col in
                            Self.luggage(board[row][col], side: max(0, cell - 1))
                        }
                    }
                }
            }
            // マスの中身が替わるたびに空き⇄荷物がクロスフェードして点滅して見えるので、盤の中は補間しない（#1946）。
            .transaction { $0.animation = nil }
            // VoiceOver ではドラッグもタップもできないので、同じ操作をアクションで出す（#2490）。
            // マス単位の荷物は読み上げず、落下中の組の位置を値で伝える。覆い・バナーは別要素のまま残す。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("荷物の盤"))
            .accessibilityValue(boardAccessibilityValue)
            // 操作できない局面（結果表示・設定中・一時停止中）では出さない（#2688）。
            .accessibilityActions {
                if canOperate {
                    Button(tr("左へ")) { _ = model.move(by: -1) }
                    Button(tr("右へ")) { _ = model.move(by: 1) }
                    Button(tr("回す")) { withGameAnimation(.easeOut(duration: 0.1)) { _ = model.rotate(clockwise: true) } }
                    Button(tr("落とす")) { _ = model.softDrop() }
                }
            }
            .padding(Self.boardInset)
            .frame(width: geo.size.width, height: geo.size.height)
            .background {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.fillMuted.opacity(0.18))
            }
            // 組の出口の列（いつもここから出る・塞がると積み上がり）。天井が近いと警告色になる（#1954）。
            .overlay(alignment: .topLeading) {
                spawnColumnMark(cell: cell, origin: Self.boardOrigin(size: geo.size, cell: cell))
            }
            // 片付けのライン（荷運びモードだけ）。この線より上に荷物が無くなればクリア。
            .overlay(alignment: .topLeading) {
                if let line = model.clearLineRow {
                    clearLine(line: line, cell: cell, origin: Self.boardOrigin(size: geo.size, cell: cell))
                }
            }
            // 決着の瞬間は盤の上に一言出して、何が起きて終わったかをその場で伝える（#1954）。
            .overlay {
                if let outcome = model.outcome, !showResult { finishBanner(outcome) }
            }
            // 一時停止中は荷物を消した盤の上に覆いを重ね、再開・はじめからを選ばせる（#2135）。
            .overlay {
                if hidesLuggage { pausedOverlay }
            }
            .onChange(of: cell, initial: true) { _, newValue in cellSide = newValue }
        }
        .aspectRatio(CGFloat(OjisanPuzzleBoard.columns) / CGFloat(OjisanPuzzleBoard.rows), contentMode: .fit)
    }

    /// ドラッグと同じ条件で、操作を受け付けてよいか。
    private var canOperate: Bool { model.outcome == nil && !showSetup && !model.isUserPaused }

    /// 落下中の組の位置（左から何列目・何と何か）。落下中でなければ空。
    private var boardAccessibilityValue: String {
        guard let pair = model.current, model.outcome == nil else { return "" }
        let names = [pair.axisKind, pair.childKind].map { OjisanPuzzleLuggage.kind($0)?.name ?? "" }
        return tr("落下中 左から%1$lld列目（%2$@と%3$@）", pair.col + 1, names[0], names[1])
    }

    /// マスが並ぶ領域の左上。盤の枠は 1:2 固定で中身は枠の中央に置かれるため、余りぶんの上下左右のずれを含めて求める。
    private static func boardOrigin(size: CGSize, cell: CGFloat) -> CGPoint {
        let contentWidth = CGFloat(OjisanPuzzleBoard.columns) * cell - 1
        let contentHeight = CGFloat(OjisanPuzzleBoard.rows) * cell - 1
        return CGPoint(x: (size.width - contentWidth) / 2, y: (size.height - contentHeight) / 2)
    }

    /// 組の出口の列の帯と、頭の ▼。塞がったら積み上がりになる列なので、天井が近い・積み上がりで終わったときは珊瑚色にする。
    private func spawnColumnMark(cell: CGFloat, origin: CGPoint) -> some View {
        let warn = model.outcome == .buried || OjisanPuzzleBoard.isSpawnColumnNearTop(model.board)
        let tint = warn ? Theme.coral : Theme.inkSub
        let iconTint = warn ? Theme.coralText : Theme.inkSubText
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: max(1, cell * 0.2), style: .continuous)
                .fill(tint.opacity(warn ? 0.22 : 0.10))
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 9)) // fixed-size: 盤の枠内に収める印
                .foregroundStyle(iconTint)
                .offset(y: -7)
        }
        .frame(width: cell, height: cell * CGFloat(OjisanPuzzleBoard.rows))
        .offset(x: origin.x + CGFloat(OjisanPuzzleBoard.spawnColumn) * cell, y: origin.y)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// クリアのライン。荷物の色に埋もれないよう、太い実線に縁取りを付け、ラインより下（片付いた側）を色で塗って
    /// 「ここまで下げる」を示す（#1954: 細い破線では見えなかった）。
    private func clearLine(line: Int, cell: CGFloat, origin: CGPoint) -> some View {
        let y = origin.y + CGFloat(line) * cell - 1
        let left = origin.x
        let right = origin.x + CGFloat(OjisanPuzzleBoard.columns) * cell - 1
        let bottom = origin.y + CGFloat(OjisanPuzzleBoard.rows) * cell - 1
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Theme.Fill.teal.opacity(0.16))
                .frame(width: right - left, height: max(0, bottom - y))
                .offset(x: left, y: y)
            Path { path in
                path.move(to: CGPoint(x: left, y: y))
                path.addLine(to: CGPoint(x: right, y: y))
            }
            .stroke(Theme.surface, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            Path { path in
                path.move(to: CGPoint(x: left, y: y))
                path.addLine(to: CGPoint(x: right, y: y))
            }
            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            Text(tr("ここまで下げたらクリア"))
                .font(.system(size: 10, weight: .heavy, design: .rounded)) // fixed-size: 盤の枠内に収める印
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Theme.Fill.teal))
                .offset(x: right - 128, y: y + 3)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// 決着の一言。結果シートが出る前の 1 秒余りだけ盤の真ん中に出る。
    private func finishBanner(_ outcome: OjisanPuzzleModel.Outcome) -> some View {
        let fill = outcome == .cleared ? Theme.Fill.teal : Theme.Fill.coral
        return Text(resultTitle)
            .font(.system(size: 26, weight: .heavy, design: .rounded)) // fixed-size: 盤の枠内に収める印
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).fill(fill))
            .transition(.scale.combined(with: .opacity))
            .allowsHitTesting(false)
    }

    /// 荷物 1 個。**ピースそのものが荷物の形に見える**絵にする（会長指示 2026-10-07・#1909）。
    /// 5 種は形で見分けが付く（`OjisanPuzzleLuggageArt`。#2115 から 24 ドットのドット絵）。空きマスだけ薄い四角を敷く。
    /// 遊び方の図（`OjisanPuzzleHowToFigures`）も同じ部品で描く（絵を二重に持たない）。
    @ViewBuilder
    static func luggage(_ value: Int, side: CGFloat) -> some View {
        if OjisanPuzzleLuggage.kind(value) == nil {
            RoundedRectangle(cornerRadius: max(1, side * 0.24), style: .continuous)
                .fill(Theme.fillMuted.opacity(0.14))
                .frame(width: side, height: side)
        } else {
            OjisanPuzzleLuggageArt(value: value, side: side)
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
                guard model.outcome == nil, !showSetup, !model.isUserPaused else { return }
                if dragStartedAt == nil { dragStartedAt = value.time }
                if dragAxis == nil { dragAxis = OjisanPuzzleDrag.axis(for: value.translation) }
                switch dragAxis {
                case .horizontal:
                    let columns = OjisanPuzzleDrag.steps(value.translation.width, step: step)
                    while appliedColumns < columns { appliedColumns += 1; model.move(by: 1) }
                    while appliedColumns > columns { appliedColumns -= 1; model.move(by: -1) }
                case .vertical:
                    // 速く払ったら 1 回だけ一気に落とす（#2810）。以降はこの指の動きを捨てる。
                    guard !didHardDrop else { break }
                    if let startedAt = dragStartedAt,
                       OjisanPuzzleDrag.isFlickDown(distance: value.translation.height,
                                                    elapsed: value.time.timeIntervalSince(startedAt)),
                       model.current != nil {
                        didHardDrop = true
                        showFlickGuide = false
                        model.hardDrop()
                        break
                    }
                    // 下方向だけ拾う（上スワイプには何も割り当てない）。
                    let rows = OjisanPuzzleDrag.downSteps(value.translation.height, step: step)
                    while appliedRows < rows { appliedRows += 1; model.softDrop() }
                case nil:
                    break
                }
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
                dragAxis = nil
                dragStartedAt = nil
                didHardDrop = false
            }
    }

    // MARK: - 次の荷物

    private var sidePanel: some View {
        VStack(spacing: 10) {
            // 荷運びモードは見出しをゲージに譲ったので、スコアはここ（おじさんの上）に置く（#2064）。
            if model.mode.hasGauge { scoreCard }

            // おじさん本人。盤の横でずっと腰の具合を訴えている。
            VStack(spacing: 4) {
                ojisanFigure()
                if model.mode.hasGauge {
                    Text(model.painStage.caption)
                        .scaledFont(10, weight: .bold, design: .rounded, maxScale: 1.15)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(model.painStage == .easy ? Theme.inkSubText : Theme.coralText)
                }
            }
            .frame(width: Self.sideWidth)
            .padding(.vertical, 10)
            // 限界のときは面そのものを痛い色にして、目の端でも分かるようにする。
            .popCard(fill: model.painStage == .severe ? Theme.Fill.coral.opacity(0.28) : Theme.surface,
                     corner: Theme.cornerSmall)

            VStack(spacing: 6) {
                Text(tr("つぎ"))
                    .scaledFont(12, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundStyle(Theme.inkSubText)
                VStack(spacing: 2) {
                    // 一時停止中は「つぎ」も空の枠にする（盤と同じ理由・#2135）。
                    let next = Self.visibleNextKinds(child: model.next.childKind, axis: model.next.axisKind,
                                                     hidesLuggage: hidesLuggage)
                    Self.luggage(next.child, side: 26)
                    Self.luggage(next.axis, side: 26)
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
            hintItem(tr("よこにスワイプ"), systemImage: "arrow.left.and.right")
            hintItem(tr("タップで回す"), systemImage: "arrow.clockwise")
            hintItem(tr("下スワイプ"), systemImage: "arrow.down")
        }
        .scaledFont(11, weight: .bold, design: .rounded, maxScale: 1.3)
        .foregroundStyle(Theme.inkSubText)
    }

    /// 初回だけ、操作のヒント行の代わりに出す案内（共通の `HowToPlayHint` を流用・#2810）。
    private var flickGuide: some View {
        HowToPlayHint(
            HowToPlayGuide(
                gameID: OjisanPuzzleModel.gameID, title: "", lines: [],
                hint: tr("速く下に払うと一気に落とせるようになりました"),
                hintIcon: "arrow.down.to.line"
            ),
            isVisible: true
        )
        .lineLimit(2).minimumScaleFactor(0.8)
        .multilineTextAlignment(.center)
        .frame(minHeight: 18)
    }

    private func hintItem(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
    }

    // MARK: - 決着

    private var resultTitle: String {
        switch model.outcome {
        case .hospitalized: tr("入院！")
        case .cleared: tr("かたづいた！")
        default: tr("積みあがった！")
        }
    }

    private var resultMessage: String {
        switch model.outcome {
        case .hospitalized: tr("腰が限界です。おだいじに。")
        case .cleared: tr("荷物がラインより下になりました。")
        default: tr("荷物が天井まで届きました。")
        }
    }

    /// 秒数を「m:ss」にする。
    static func timeText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var resultOverlay: some View {
        VStack(spacing: 10) {
            if let outcome = model.outcome {
                // 入院はベッド（83×64 ドット）、積み上がりは倒れる絵（70×27）、片付いたら笑顔（#2064）。
                OjisanPuzzleArt.image(OjisanPuzzleArt.resultPose(for: outcome))
            }
            Text(resultTitle)
                .scaledFont(24, weight: .heavy, design: .rounded, maxScale: 1.4)
                .foregroundStyle(Theme.ink)
            Text(resultMessage)
                .scaledFont(14, weight: .semibold, design: .rounded, maxScale: 1.4)
                .foregroundStyle(Theme.inkSubText)
                .multilineTextAlignment(.center)
            if model.outcome == .cleared {
                Text(tr("タイム %@", Self.timeText(model.elapsedMilliseconds / 1000)))
                    .scaledFont(18, weight: .bold, design: .rounded, maxScale: 1.4).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            Text(tr("スコア %@", model.score.formatted()))
                .scaledFont(18, weight: .bold, design: .rounded, maxScale: 1.4).monospacedDigit()
                .foregroundStyle(Theme.ink)
            if model.maxChain >= 2 {
                Text(tr("最大 %lld連鎖", model.maxChain))
                    .scaledFont(16, weight: .bold, design: .rounded, maxScale: 1.4)
                    .foregroundStyle(Theme.coralText)
            }
            // 自己ベストの 1 行（他ゲームのリザルトと同じ共通部品・#1904）。
            RecordLabel(model.recordResult)
            if model.canContinue { continueButton }
            Button { // a11y-ok: 17pt 文字+縦余白 12×2 で 44pt 超（別 Issue で GameButtonStyle へ）
                withGameAnimation { model.newGame() }
            } label: {
                Text(tr("もう一回"))
                    .scaledFont(17, weight: .bold, design: .rounded, maxScale: 1.4)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                            .fill(Theme.Fill.coral)
                    )
            }
            .buttonStyle(.pop)
            // 広告の読み込み中に始め直すと、見終えても照合で弾かれて見損になる。
            .disabled(continueRescue.isWatching)
        }
        .padding(22)
        .popCard()
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .announcesResultAppearance([resultTitle, resultMessage].joined(separator: tr("。")))
    }

    /// 負けから 1 局 1 回だけ続ける（入院はゲージ半分、積み上がりは上から 4 段を片づける・#2013）。
    private var continueButton: some View {
        GameDeadEndActionButton(
            tr("広告を見て続ける"), systemImage: "play.rectangle.fill",
            tint: Theme.Fill.teal, isDisabled: continueRescue.isWatching
        ) {
            // どの局への続きかを広告前に控える。ロード中に始め直されたら適用せず知らせる。
            let run = model.gameGeneration
            continueRescue.request(
                services, gameID: OjisanPuzzleModel.gameID, purpose: .continue,
                guardedBy: .checkedByGrant
            ) {
                model.continueAfterAd(forRun: run)
            }
        }
    }
}

/// 背面から戻ったときに荷物の落下を再開してよいか。開始シートや遊び方を開いているあいだは再開しない（#2353）。
enum OjisanPuzzleResume {
    static func shouldResume(phase: ScenePhase, showSetup: Bool, showHowTo: Bool) -> Bool {
        phase == .active && !showSetup && !showHowTo
    }
}
