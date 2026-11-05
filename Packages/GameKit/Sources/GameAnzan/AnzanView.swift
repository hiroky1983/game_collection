import SwiftUI
import Core

/// ぱっと暗算（#1321）のプレイ画面。
///
/// 上から: 難易度と記録の見出し → 出題の板（数 / 入力中の答え / 正誤）→ テンキー（入力中だけ有効）
/// → 遊び方の 1 行 → レコメンド → バナー。板は縦の余りを吸い、テンキーは常に同じ高さで置く
/// （局面が変わるたびに板が伸び縮みしないため）。
public struct AnzanView: View {
    @State private var model: AnzanModel
    private let services: GameServices
    /// 同じ問題をもう一度見る救済（広告 1 本で 1 問 1 回）。
    @State private var replayRescue = RewardedRescue()
    @State private var showSetup: Bool
    /// 遊び方のシートを開いているあいだ true（閉じたときに、まだバックグラウンドなら再開しない）。
    @State private var showHowToPlay = false
    /// 間違えた問題の一覧（#2855）。
    @State private var showMisses = false
    @Environment(\.scenePhase) private var scenePhase

    public init(services: GameServices) {
        self.services = services
        let model = AnzanModel(services: services)
        #if DEBUG
        // 撮影・動作確認用: `-anzanScenario flash|answer|correct|wrong` で局面を差し替える。
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-anzanScenario"), i + 1 < args.count {
            model.applyDebugScenario(args[i + 1])
        }
        #endif
        _model = State(initialValue: model)
        // まだ 1 問も始めていなければ難易度のシートから入る。撮影で局面を差し替えたときは畳んだまま
        // （`.task` で開くとシートの提示と競合する）。
        _showSetup = State(initialValue: model.phase == .idle)
    }

    /// 正解が続いたら一段速い表示を勧める（#2599。段は速さの 1 軸だけ・仮置き）。桁数・個数は今のまま。
    private var ladder: DifficultyLadderPrompt? {
        let speeds = AnzanSpeed.allCases
        let current = model.settings
        return DifficultyLadderPrompt(result: model.recordResult, currentLevel: speeds.firstIndex(of: current.speed),
                                      levelLabels: speeds.map(\.label)) { level in
            withGameAnimation {
                model.start(AnzanSettings(digits: current.digits, count: current.count, speed: speeds[level]))
            }
        }
    }

    public var body: some View {
        VStack(spacing: 14) {
            header
            stage
            controls
            // 初回だけ出す 1 行（以降は `?` ボタンからいつでも読める）。
            HowToPlayHint(.anzan, playLog: services.playLog)
            RecommendationSlot(services: services, isFinished: model.phase == .result, ladder: ladder)
            BannerSlot(ads: services.ads)
        }
        .padding()
        .gameChrome(title: tr("ぱっと暗算"), review: services.review) {
            ToolbarItem(placement: .primaryAction) {
                Button { showSetup = true } label: {
                    Label(tr("難易度"), systemImage: "slider.horizontal.3")
                }
                // 数が出ているあいだにシートを被せると見逃すので、出し終わるまで待たせる。
                // 広告の視聴中も塞ぐ（難易度を変えると問題が入れ替わり、見終えた広告の見直しが乗らない）。
                .disabled(model.phase == .flashing || replayRescue.isWatching)
            }
        }
        .howToPlay(HowToPlayGuide.anzan.illustrated(AnzanHowToFigures.items).onboarding(AnzanOnboarding.guide), onPresent: {
            // 数が出ているあいだに読むと出題が進んで誤答になるので、止めて頭から出し直す。
            showHowToPlay = true
            model.pauseDisplay()
        }, onDismiss: {
            showHowToPlay = false
            if scenePhase == .active { model.resumeDisplay() }
        })
        .onChange(of: scenePhase) { _, phase in
            // 背面ではタイマーが即満了して数が飛ぶので、数の表示中に画面が引っ込んだら止める（入力中は何もしない）。
            if phase != .active {
                model.pauseDisplay()
            } else if AnzanModel.canResumeDisplay(isActive: true, showHowToPlay: showHowToPlay, showSetup: showSetup) {
                model.resumeDisplay()
            }
        }
        .onChange(of: showSetup) { _, open in
            // 入力中に難易度のシートを開いたままにした時間は回答時間に乗せない。
            if open {
                model.pauseDisplay()
            } else if AnzanModel.canResumeDisplay(isActive: scenePhase == .active, showHowToPlay: showHowToPlay, showSetup: showSetup) {
                model.resumeDisplay()
            }
        }
        .sheet(isPresented: $showSetup) {
            AnzanSetupSheet(initial: model.settings) { settings in
                showSetup = false
                withGameAnimation { model.start(settings) }
            } onCancel: {
                showSetup = false
            }
        }
        .sheet(isPresented: $showMisses) {
            AnzanMissesSheet(misses: model.misses) { showMisses = false }
        }
        // 見直しの提示（#780）。入力中で見直しボタンが出ているあいだを 1 回の提示として数える。
        .rewardOffer(replayRescue, for: .hint, isPresented: model.canReplay,
                     services: services, gameID: AnzanModel.gameID)
        .rewardedRescueAlerts(
            replayRescue,
            notEarned: tr("もう一度見られませんでした"),
            unavailable: RewardUnavailableAlert(
                title: tr("もう一度見られませんでした"),
                message: tr("広告を見ているあいだに問題が変わったため、見直せませんでした。")
            )
        )
        // 表示の並びは Model が 1 コマずつ進め、ここは待つだけ。問題が変わる・見直すたびに
        // `displayRun` が進んで前のループが止まり、画面を離れれば `.task` ごと止まる。
        .task(id: model.displayRun) { await runDisplay() }
    }

    private func runDisplay() async {
        while !Task.isCancelled, let wait = model.advanceDisplay() {
            do { try await Task.sleep(for: wait) } catch { return }
        }
    }

    // MARK: - 見出し

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("難易度")).themeCaption(11).foregroundStyle(Theme.inkSubText)
                Text(model.settings.variantLabel)
                    .themeBody(15)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            stat(tr("連続正解"), value: "\(model.streak)")
            if let best = model.bestSeconds {
                stat(tr("最速"), value: tr("%lld秒", best))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private func stat(_ title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).themeCaption(11).foregroundStyle(Theme.inkSubText)
            Text(verbatim: value)
                .scaledFont(22, weight: .heavy, design: .rounded).monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 出題の板

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.fillStrong)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
            stageContent
        }
        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
        // コマ（よーい・数・空白）の切り替えにはアニメーションを付けない。フェードは速い設定の空白（180ms）と
        // 重なり、前の数が消えきらないまま次の数が出て「書き換わる」ように見えた（#2067）。
        .gameAnimation(.easeInOut(duration: 0.2), value: model.phase)
        // 板は 1 つの要素として読み上げつつ、中の見直しボタンには VoiceOver で届くようにする
        // （`.ignore` にすると板の中の Button がフォーカスから外れる。ソリティアの救済ダイアログと同じ `.contain`）。
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AnzanAccessibility.stageLabel(
            phase: model.phase, step: model.step, displayedNumber: model.displayedNumber,
            input: model.input, sum: model.sum, answer: model.answer, isCorrect: model.isCorrect
        ))
    }

    @ViewBuilder
    private var stageContent: some View {
        switch model.phase {
        case .idle:
            Text(tr("難易度を選んでスタート"))
                .themeBody(17)
                .foregroundStyle(.white.opacity(0.85))
        case .flashing:
            flashContent
        case .answering:
            answerContent
        case .result:
            resultContent
        }
    }

    @ViewBuilder
    private var flashContent: some View {
        if model.isShowingReady {
            Text(tr("よーい"))
                .scaledFont(34, weight: .heavy, design: .rounded, maxScale: 1.2)
                .foregroundStyle(Theme.Fill.yellow)
        } else if let number = model.displayedNumber {
            Text(verbatim: "\(number)")
                .scaledFont(88, weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
        }
    }

    private var answerContent: some View {
        VStack(spacing: 10) {
            Text(tr("ぜんぶ足すと？"))
                .themeBody(15)
                .foregroundStyle(.white.opacity(0.85))
            Text(verbatim: model.input.isEmpty ? "?" : model.input)
                .scaledFont(56, weight: .heavy, design: .rounded, maxScale: 1.2).monospacedDigit()
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            if model.canReplay {
                replayButton
            } else if model.replayUsed {
                Text(tr("見直しずみ"))
                    .themeCaption(11)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(12)
    }

    /// 広告を見て同じ問題をもう一度見る。どの問題に対するものかを広告を出す前に控え、
    /// ロード中に次の問題へ進んでいたら乗せない（#729）。
    private var replayButton: some View {
        Button {
            let serial = model.questionSerial
            replayRescue.request(
                services, gameID: AnzanModel.gameID, purpose: .hint,
                guardedBy: .checkedByGrant
            ) {
                model.replayAfterAd(forGame: serial)
            }
        } label: {
            Label(tr("もう一度見る（広告）"), systemImage: "play.rectangle.fill")
                .themeBody(13)
        }
        .buttonStyle(GameButtonStyle(role: .ad))
        .disabled(replayRescue.isWatching)
    }

    private var resultContent: some View {
        VStack(spacing: 8) {
            Text(model.isCorrect ? tr("せいかい！") : tr("ざんねん…"))
                .scaledFont(30, weight: .heavy, design: .rounded, maxScale: 1.2)
                .foregroundStyle(model.isCorrect ? Theme.Fill.yellow : .white)
            Text(verbatim: AnzanLogic.expression(model.numbers))
                .themeBody(14)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            HStack(spacing: 12) {
                if !model.isCorrect, let answer = model.answer {
                    Text(verbatim: tr("あなたの答え %lld", answer))
                }
                if let seconds = model.answerSeconds {
                    // 記録の 1 行（`RecordLabel`）は勝敗の指標なので秒数を出さない。最速を更新した回は
                    // 「自己ベスト更新！」の中身がここで分かるように添える。
                    Text(verbatim: model.recordResult?.update.seconds == true ? tr("回答 %lld秒（最速！）", seconds) : tr("回答 %lld秒", seconds))
                }
            }
            .themeCaption(12)
            .foregroundStyle(.white.opacity(0.75))
            RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
        }
        .padding(12)
    }

    // MARK: - 操作

    /// テンキーの高さを常に確保し、局面ごとの操作をその上に重ねる（板が伸び縮みしないため）。
    private var controls: some View {
        // 広告のロード〜視聴中は決定も塞ぐ。ここで決定すると問題が決着して、見終えた広告の見直しが
        // 局ガードで弾かれて見損になる（コンティニューの幕の #911 と同型）。
        let canType = model.phase == .answering && !replayRescue.isWatching
        return ZStack {
            keypad
                .opacity(model.phase == .answering ? (canType ? 1 : 0.5) : 0)
                .allowsHitTesting(canType)
                .accessibilityHidden(!canType)
            switch model.phase {
            case .idle:
                Button { showSetup = true } label: {
                    Text(tr("はじめる")).themeBody(18).frame(maxWidth: .infinity)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
                .padding(.horizontal, 24)
            case .flashing:
                Text(tr("出た数をぜんぶ足そう"))
                    .themeBody(15)
                    .foregroundStyle(Theme.inkSubText)
            case .answering:
                EmptyView()
            case .result:
                resultControls
            }
        }
    }

    private static let keyRows: [[AnzanKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.backspace, .digit(0), .submit],
    ]

    private var keypad: some View {
        VStack(spacing: 8) {
            ForEach(Array(Self.keyRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
        }
    }

    private func keyButton(_ key: AnzanKey) -> some View {
        let isSubmit = key == .submit
        let enabled = !isSubmit || model.canSubmit
        return Button { press(key) } label: {
            Group {
                switch key {
                case let .digit(digit):
                    Text(verbatim: "\(digit)")
                        .scaledFont(24, weight: .heavy, design: .rounded)
                case .backspace:
                    Image(systemName: "delete.left.fill")
                        .scaledFont(20, weight: .bold)
                case .submit:
                    Text(tr("決定"))
                        .scaledFont(18, weight: .heavy, design: .rounded)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(isSubmit ? Theme.onAccent : Theme.ink)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(isSubmit ? Theme.Fill.coral : Theme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            )
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.pop)
        .disabled(!enabled)
        .accessibilityLabel(AnzanAccessibility.keyLabel(key))
    }

    private func press(_ key: AnzanKey) {
        switch key {
        case let .digit(digit): model.tapDigit(digit)
        case .backspace:        model.backspace()
        case .submit:           withGameAnimation { model.submit() }
        }
    }

    private var resultControls: some View {
        VStack(spacing: 10) {
            Button { withGameAnimation { model.next() } } label: {
                Label(tr("次の問題"), systemImage: "arrow.right.circle.fill")
                    .themeBody(17).frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(Theme.Fill.coral)
            Button { showSetup = true } label: {
                Text(tr("難易度を変える")).themeBody(15).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large).tint(Theme.coralText)
            if !model.misses.isEmpty {
                Button { showMisses = true } label: {
                    Text(tr("まちがえた問題を見る（%lld）", model.misses.count))
                        .themeBody(14).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.pop)
                .foregroundStyle(Theme.coralText)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - まちがえた問題のシート

/// この画面を開いてから間違えた問題を、新しい順に「式・自分の答え・正解」で並べる（#2855）。
struct AnzanMissesSheet: View {
    let misses: [AnzanMiss]
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(misses.reversed().enumerated()), id: \.offset) { _, miss in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: miss.expression)
                            .themeBody(15).foregroundStyle(Theme.ink)
                        HStack(spacing: 16) {
                            Text(verbatim: tr("あなたの答え %lld", miss.answer))
                                .foregroundStyle(Theme.inkSubText)
                            Text(verbatim: tr("正解 %lld", miss.correct))
                                .foregroundStyle(Theme.coralText)
                        }
                        .themeCaption(13)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tr("%1$@。あなたの答えは%2$lld、正解は%3$lld", miss.expression, miss.answer, miss.correct))
                }
            }
            .navigationTitle(tr("まちがえた問題"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("閉じる"), action: onClose)
                }
            }
        }
    }
}

// MARK: - 難易度のシート

/// 桁数・個数・速さをそれぞれ選ぶ（#1321 の受け入れ条件）。節が 3 つあるので常に `.large` で開き、
/// スタートは共通枠が下に固定する（#1415）。
struct AnzanSetupSheet: View {
    let onStart: (AnzanSettings) -> Void
    let onCancel: () -> Void
    @State private var settings: AnzanSettings

    init(initial: AnzanSettings, onStart: @escaping (AnzanSettings) -> Void, onCancel: @escaping () -> Void) {
        self.onStart = onStart
        self.onCancel = onCancel
        _settings = State(initialValue: initial)
    }

    /// 3 つ横に並ぶので、見出しと副題を標準より少し小さくする。
    private static let metrics = GameSetupChooser.Metrics(title: .title(20), subtitleSize: 11)

    var body: some View {
        GameSetupSheet(
            kind: .solo,
            onboarding: AnzanOnboarding.guide,
            onStart: { onStart(settings) }, onCancel: onCancel
        ) {
            GameSetupSection(tr("桁数")) {
                HStack(spacing: 12) {
                    ForEach(AnzanDigits.allCases, id: \.self) { digits in
                        GameSetupChooser(title: digits.label, subtitle: digits.subtitle,
                                         selected: settings.digits == digits,
                                         accent: Theme.Fill.teal, metrics: Self.metrics) {
                            settings.digits = digits
                        }
                    }
                }
            }
            GameSetupSection(tr("個数")) {
                HStack(spacing: 12) {
                    ForEach(AnzanCount.allCases, id: \.self) { count in
                        GameSetupChooser(title: count.label, subtitle: "",
                                         selected: settings.count == count,
                                         accent: Theme.Fill.purple, metrics: Self.metrics) {
                            settings.count = count
                        }
                    }
                }
            }
            GameSetupSection(tr("速さ")) {
                HStack(spacing: 12) {
                    ForEach(AnzanSpeed.allCases, id: \.self) { speed in
                        GameSetupChooser(title: speed.label, subtitle: speed.subtitle,
                                         selected: settings.speed == speed,
                                         accent: Theme.Fill.coral, metrics: Self.metrics) {
                            settings.speed = speed
                        }
                    }
                }
            }
        }
    }
}
