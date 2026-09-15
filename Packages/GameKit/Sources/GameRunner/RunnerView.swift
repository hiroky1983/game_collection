import Core
import SpriteKit
import SwiftUI

/// チャリンコおじさんのプレイ画面（#494）。
///
/// SpriteKit（`RunnerScene`）が描くのはコースだけで、ヘッダー・オーバーレイ・遊び方・
/// レコメンド・バナーはこれまでのゲームと同じ SwiftUI 部品を使う
/// （基盤規約「メニュー・リザルト・設定は SwiftUI」）。
public struct RunnerView: View {
    private let services: GameServices
    @State private var model: RunnerModel
    @State private var scene: RunnerScene
    /// チェックポイント再開のリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var resumeRescue = RewardedRescue()
    /// 開始シート（モード選択・#675）を出しているか。
    @State private var showStartSheet = false
    /// 開始シートで選んでいるモード。ここは「次の走行に使う設定」で、進行中の走行が
    /// 見ているのは `model.mode`（開始時に焼き込んだ値）のほう（麻雀の `selectedLength` と同じ分け方）。
    @State private var selectedMode: RunnerMode = .stages
    /// 開始シートのワールドマップ（#798）で選んでいる面。`selectedMode` と同じく「次の走行に
    /// 使う設定」で、開始時に `RunnerModel.newGame(startingAtStage:)` で焼き込む。
    /// ツールバーの「はじめから」は 1 面、スタート画面の「マップ」はいまの面を選んだ状態で開く。
    @State private var selectedStage = 1
    /// 初回プレイの操作ガイド（#988）をいま出しているか。判定と「見せた」の記録は `init` で
    /// 1 回だけ済ませる（`HowToPlayHint` と同じ作法）。「はじめる」で false になる。
    @State private var showsTutorial: Bool
    /// この画面を開いたときにガイドを出したか。**閉じたあとも true のまま**で、
    /// 1 行ヒント（`secondaryInfo`）を出すかの判断に使う。`showsTutorial` で判断すると、
    /// 「はじめる」で閉じた直後の再描画でヒントが組み立てられ、同じプレイの中で
    /// 同じ文言（「タップでジャンプ」）をもう一度出してしまう。
    @State private var tutorialShownOnOpen: Bool
    @Environment(\.scenePhase) private var scenePhase

    public init(services: GameServices) {
        self.services = services
        let model = RunnerModel(services: services)
        _model = State(initialValue: model)
        _scene = State(initialValue: RunnerScene(model: model))
        // 判定は 1 回だけ（`shouldShow` が「見せた」の記録も兼ねるので二度呼ばない）。
        let showsTutorial = RunnerTutorial.shouldShow(playLog: services.playLog)
        _showsTutorial = State(initialValue: showsTutorial)
        _tutorialShownOnOpen = State(initialValue: showsTutorial)
    }

    public var body: some View {
        VStack(spacing: 10) {
            topSummary
            // `layoutPriority(1)` で縦幅の分配を先取りする（囲碁の盤と同じ組み方。詳細は `course` の doc）。
            course
                .layoutPriority(1)
            // 一時停止はコース（ゲーム画面）の**外**に出す（会長QA「一時停止ボタンは画面外に出したい」
            // ・2026-09-10）。以前はコースの右下に重ねていたが、ゲームの絵の一部に見えてしまう・
            // 誤タップで盤面が隠れる、という指摘を受けた。右寄せの専用の行として独立させる。
            // 走り出す前の導線（次の面・エンドレス・マップ）はこの行ではなくコースの上の
            // スタート画面（`startScreen`・#931）に置く——#919 でこの行に相乗りさせた切り替えは
            // 「発想が貧弱」（会長 QA 2026-09-15）で撤去した。
            HStack(spacing: 8) {
                Spacer(minLength: 4)
                pauseButton
            }
            secondaryInfo
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding()
        .gameChrome(title: "チャリンコおじさん", review: services.review) {
            ToolbarItem(placement: .primaryAction) {
                // 「はじめから」はモードを選ぶ開始シートを経由する（#675。チェスの「新規対局」と
                // 同じ作法）。走行中なら読んでいる間にミスしないよう止める。
                Button {
                    if model.phase == .running { model.pause() }
                    openStartSheet(mode: model.mode, stage: 1)
                } label: {
                    Label("はじめから", systemImage: "arrow.clockwise")
                }
            }
        }
        .howToPlay(.runner) {
            // 読んでいる間にミスしないよう止める。走り出す前（.ready）は動くものが無いので
            // 止めない（初見の人が遊ぶ前に開く一番多い経路で、余計な「再開」を挟まない）。
            if model.phase == .running { model.pause() }
        } extra: {
            // 初回プレイの操作ガイド（#988）をいつでも開き直せる場所。「くわしいルール」の
            // 見出しは共通部品（`HowToPlaySheet`）が持つ。
            RunnerTutorialPage()
        }
        .sheet(isPresented: $showStartSheet) {
            RunnerStartSheet(
                mode: $selectedMode, selectedStage: $selectedStage, reachedStage: model.reachedStage
            ) {
                switch selectedMode {
                case .stages:  model.newGame(startingAtStage: selectedStage)
                case .endless: model.newGame(mode: .endless)
                }
                showStartSheet = false
            } onCancel: {
                showStartSheet = false
            }
        }
        .onAppear {
            // 設定画面で切り替えられていたら取り込む（書き手は設定画面とポーズ画面の 2 か所）。
            model.syncSlowModeFromPreference()
            #if DEBUG
            // 撮影・動作確認用: `-simulateRunner <running|paused|failed|cleared|showcase|bird|bird:N|platform|floor|invincible|stage:N|map:N|endless|endless-running|endless-failed>`（#494・#675・#797）。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-simulateRunner"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
            }
            // 撮影用: 開始シート（ワールドマップ #798）を開いた状態にする（`-showRunnerStartSheet`）。
            if args.contains("-showRunnerStartSheet") {
                openStartSheet(mode: model.mode, stage: 1)
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            // 反射神経を使うゲームなので、画面が引っ込んだ瞬間に必ず止める
            // （基盤規約「バックグラウンド移行時は即一時停止」）。
            if phase != .active { model.pause() }
        }
        .rewardedRescueAlerts(
            resumeRescue,
            notEarned: "再開できませんでした",
            unavailable: RewardUnavailableAlert(
                title: "再開できませんでした",
                message: "広告を見ているあいだに新しいコースが始まったため、途中から再開できませんでした。"
            )
        )
    }

    // MARK: - ヘッダー

    /// 面の見出し・スピード・進み具合を 1 行にまとめた画面上部のセクション。
    ///
    /// #931 で**秒数（タイム・ベストタイム）を外した**（会長決裁「ステージのタイムは要らない」。
    /// ステージ制は難しい横スクロールを攻略して先へ進むのが主役で、秒を縮める遊びではない）。
    /// 代わりに「いまどの面を走っているか」（`RunnerAccessibility.stageHeadline`）を主役にする。
    /// ベストタイムのチップ一覧も無くなったので 1 行だけになり、浮いた縦幅は `course` が取る。
    /// **モードを切り替えても高さが変わらない**よう、ステージ制とエンドレスで同じ 3 区画の並び
    /// （左: 見出し / 中: スピード / 右: 進み具合か自己ベスト）にしてある。
    private var topSummary: some View {
        header
            .padding(.horizontal, 16).padding(.vertical, 10)
            .popCard(corner: Theme.cornerSmall)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            switch model.mode {
            case .stages:  stageHeadline
            case .endless: distanceReadout
            }
            speedMeter
            Spacer(minLength: 0)
            switch model.mode {
            case .stages:  progressReadout
            case .endless: endlessBestReadout
            }
        }
    }

    /// ステージ制の見出し。「ステージ 9 / 18」の小さな行の下に「2-3」（#931。面の名前は #946 で
    /// 外し、番号だけ）。
    private var stageHeadline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RunnerAccessibility.stageLabel(number: model.stageNumber, total: RunnerRules.stageCount))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            Text(stageHeadlineText)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement()
        // 番号に世界の名前（#703）と「世界-面」の表記を添える——画面では背景の色で分かる
        // 「どこを走っているか」を、見えない人にも言葉で伝える。
        .accessibilityLabel(
            RunnerAccessibility.stageLabelWithWorld(number: model.stageNumber, total: RunnerRules.stageCount)
                + "、" + stageHeadlineText
        )
    }

    /// ステージ制の進み具合。ゲージだけでは何のゲージか分からないので「ゴールまで」の見出しを添える。
    private var progressReadout: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("ゴールまで")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            progressBar
        }
        .accessibilityElement()
        .accessibilityLabel(RunnerAccessibility.progressLabel(model.field.progress))
    }

    /// エンドレス（#675）は「ステージ N / 18」と進み具合の代わりに走行距離を出す。
    /// 進み具合は出さない——固定長の終わりを見せると「エンドレス」の看板と食い違う。
    private var distanceReadout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("走行距離")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            Text(distanceText(model.distanceMeters))
                .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement()
        .accessibilityLabel(RunnerAccessibility.distanceLabel(model.distanceMeters))
    }

    /// エンドレスの自己ベスト（走行距離）。走りながら「あとどれだけで更新か」を読めるように残す。
    private var endlessBestReadout: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("自己ベスト")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            Text(model.endlessBestDistance.map(distanceText) ?? "–")
                .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement()
        .accessibilityLabel(RunnerAccessibility.bestDistanceLabel(model.endlessBestDistance))
    }

    /// 走行距離の表示（`1,234 m`）。単位はワールド単位だが、数字に「m」を添えて距離と分かるようにする。
    private func distanceText(_ distance: Int) -> String {
        "\(RecordFormat.number(max(0, distance))) m"
    }

    /// ペダルの乗り（#569）。
    ///
    /// **いま速いのか遅いのか**を走りながら読めるようにする。倍率の数字は走行中に読めないので、
    /// 進み具合と同じ形のゲージにして伸び縮みだけで伝える。
    private var speedMeter: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("スピード")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Fill.coral.opacity(0.2))
                    Capsule().fill(Theme.Fill.coral)
                        .frame(width: geo.size.width * speedRatio)
                }
            }
            .frame(width: 64, height: 6)
        }
        .padding(.leading, 8)
        .accessibilityElement()
        .accessibilityLabel(RunnerAccessibility.speedLabel(ratio: speedRatio))
    }

    /// ゲージの割合。0 が基準の速さ、1 が上限。
    private var speedRatio: Double {
        let span = RunnerRules.maxPedalBoost - 1
        guard span > 0 else { return 0 }
        return min(1, max(0, (model.field.pedalBoost - 1) / span))
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Fill.coral.opacity(0.2))
                Capsule().fill(Theme.Fill.coral)
                    .frame(width: geo.size.width * model.field.progress)
            }
        }
        .frame(width: 88, height: 6)
    }

    private var pauseButton: some View {
        Button {
            if model.phase == .paused { model.resume() } else { model.pause() }
        } label: {
            Image(systemName: model.phase == .paused ? "play.fill" : "pause.fill")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.Fill.coral))
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.pop)
        .accessibilityLabel(model.phase == .paused ? "再開" : "一時停止")
        // 止めるものが無い状態では押せない。
        .disabled(
            model.phase == .falling || model.phase == .failed
                || model.phase == .cleared || model.phase == .allCleared
        )
    }

    /// 開始シート（`RunnerStartSheet`）を、選んでおくモードと面を決めて開く。
    /// ツールバーの「はじめから」と、スタート画面の「マップ」（#931）の共通の経路。
    private func openStartSheet(mode: RunnerMode, stage: Int) {
        selectedMode = mode
        selectedStage = stage
        showStartSheet = true
    }

    // MARK: - コース

    /// **`GeometryReader` で包んで `.layoutPriority(1)` を付ける**（囲碁の盤 `GoView.board` と同じ組み方）。
    ///
    /// `.frame(maxWidth: .infinity, maxHeight: .infinity)` だけでも幅基準では同じ結果になるが、
    /// `GeometryReader` は常に提案された枠いっぱいに広がる**「伸縮する子」だと `VStack` に
    /// 確実に伝わる**ので、この画面より縦に余裕のある端末でも `course` が優先的に余った縦幅を取り、
    /// `BannerSlot` が浮かずに画面下へ収まることを保証できる。
    ///
    /// 読み上げの 1 要素にまとめるのは**絵とタップの層だけ**（`playfield`）。上に重ねる
    /// スタート画面・一時停止・リザルトのボタンは別の要素として残す（`ZStack` 全体を 1 要素に
    /// すると、重ねたボタンが VoiceOver から消える）。
    private var course: some View {
        GeometryReader { geo in
            ZStack {
                playfield
                // 無敵の残り時間（#797）はコースの上端に重ねる（ヘッダーは幅が詰まっていて、
                // 出たり消えたりする要素を足すと他の欄が動く）。読み上げは `courseLabel` に
                // 含めてあるので、ここは要素として出さない。
                VStack {
                    invincibleBadge
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                // リザルトの顔（#702）はコースの高さから倍率を決める（SE では 3 倍に落として
                // カードをコースの中に収める）。`geo` は最初に 0 を渡すことがあるが、
                // `RunnerResultFace.dotScale` は 0 でも最小の 2 倍を返す。
                overlay(faceScale: RunnerResultFace.dotScale(forCourseHeight: geo.size.height))
            }
        }
        // シーンは `.aspectFit` なので、枠の縦横比をコースと必ず一致させる。
        // ずれると余白が出て、見えている範囲と当たり判定の対応も狂う。
        .aspectRatio(RunnerField.Metrics.width / RunnerField.Metrics.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
    }

    /// コースの絵とタップを受ける層。
    private var playfield: some View {
        ZStack {
            // 操作はすべて下の透明レイヤーで受ける。SpriteView 自身に当たり判定を残すと、
            // 機種によってはタップが SKView に吸われる。
            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
                .gesture(jumpGesture)
        }
        .accessibilityElement()
        .accessibilityLabel(courseLabel)
        .accessibilityHint("ダブルタップでジャンプ")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.press(); model.release() }
    }

    /// コースの読み上げ。ステージ制はステージ番号、エンドレスは走行距離で結果を言う。
    /// 無敵中（#797）は残り時間を添える——コースは 1 つの要素にまとめてあるので、
    /// 上に重ねた `invincibleBadge` のラベルは単独では読まれない。
    private var courseLabel: String {
        let base: String
        switch model.mode {
        case .stages:
            base = RunnerAccessibility.resultLabel(phase: model.phase, stageNumber: model.stageNumber)
        case .endless:
            base = RunnerAccessibility.endlessResultLabel(phase: model.phase, distance: model.distanceMeters)
        }
        guard model.phase == .running, model.field.isInvincible else { return base }
        return base + "、" + RunnerAccessibility.invincibleLabel(remaining: model.field.invincibleRemaining)
    }

    /// たこ焼き（#797）の無敵の残り時間。縮むゲージと秒数の両方で見せる（受け入れ条件
    /// 「無敵の残り時間が画面で分かる」）。無敵でないあいだは何も出さない。ミス後は
    /// `field` が無敵のまま凍るので、走行中と一時停止中にだけ出す（`RunnerScene` の点滅と同じ条件）。
    @ViewBuilder
    private var invincibleBadge: some View {
        if model.field.isInvincible, model.phase == .running || model.phase == .paused {
            let remaining = model.field.invincibleRemaining
            let ratio = min(1, max(0, remaining / RunnerRules.invincibleDuration))
            HStack(spacing: 8) {
                Text("無敵")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.onAccent.opacity(0.25))
                        Capsule().fill(Theme.onAccent)
                            .frame(width: geo.size.width * ratio)
                    }
                }
                .frame(width: 72, height: 6)
                Text(String(format: "%.1f", remaining))
                    .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Theme.Fill.yellow))
            .padding(.top, 8)
        }
    }

    /// 押している間だけ高く跳べるので、押し下げと離しの両方を拾う。
    private var jumpGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in model.press() }
            .onEnded { _ in model.release() }
    }

    // MARK: - オーバーレイ

    /// いまの局面で出すおじさんの顔（#702）。選び方は `RunnerResultFace.face(for:isNewBest:)` で固定。
    private var resultFace: OjisanPixel.Face? {
        RunnerResultFace.face(for: model.phase, isNewBest: model.didSetBestDistance)
    }

    /// - Parameter faceScale: リザルトの顔の倍率（1 ドット = 何 pt か）。コースの高さから決める。
    @ViewBuilder
    private func overlay(faceScale: Int) -> some View {
        switch model.phase {
        case .ready:
            startScreen
        case .running:
            EmptyView()
        case .paused:
            pausedOverlay
        case .falling:
            // 落下・激突の短い演出中（`RunnerScene`）。ミスパネルはこの演出が終わってから出す。
            EmptyView()
        case .failed:
            // ミスの表示は両モードで同じ枠（#675「既存の失敗リザルトを流用」）。エンドレスは
            // ミスがそのまま決着なので、走行距離と自己ベストの行が加わる。
            panel(title: "ミス！", face: resultFace, faceScale: faceScale) {
                if model.mode == .endless { endlessDetail }
                if model.canResumeFromCheckpoint { resumeButton }
                retryButton
            }
        case .allCleared where model.mode == .endless:
            // 固定長のコースを走り切った（第 1 弾は 400 区画で打ち切り・#675）。
            panel(title: "コースを走りきった！", face: resultFace, faceScale: faceScale) {
                endlessDetail
                retryButton
            }
        case .cleared:
            // 主役は「次の面へ」（#931）。秒数の表示・ベストタイム更新の印は廃止し、
            // 到達点が伸びた回だけ「新しい面に到達！」の印を出す。
            panel(
                title: "\(stageHeadlineText) クリア！",
                face: resultFace, faceScale: faceScale
            ) {
                clearedDetail
                Button {
                    model.advanceToNextStage()
                } label: {
                    Label("次の面へ", systemImage: "arrow.forward.circle.fill")
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Fill.coral)
                replayButton
            }
        case .allCleared:
            panel(title: "全ステージクリア！", face: resultFace, faceScale: faceScale) {
                replayButton
                restartButton
            }
        }
    }

    /// おじさんの顔をドット絵の比率（16×15）のまま整数倍で置く（#702）。
    /// `Core` の `OjisanPixel.faceImage` は装飾画像なので VoiceOver には出ない。
    private func ojisanFace(_ face: OjisanPixel.Face, scale: Int) -> some View {
        let dots = OjisanPixel.faceDotSize
        return OjisanPixel.faceImage(face)
            .frame(width: CGFloat(dots.width * scale), height: CGFloat(dots.height * scale))
    }

    /// クリア表示の添え書き。初到達の印と、次に走る面の番号（「つぎは 2-4」・#946）。
    private var clearedDetail: some View {
        VStack(spacing: 6) {
            if model.didReachNewStage {
                // 見た目は共通の `RecordBadge`（塗りつぶさない印。「次の面へ」ボタンと
                // 同じ塗りだと押せるものに見える・会長 QA 2026-09-14）。
                RecordBadge("新しい面に到達！")
            }
            Text("つぎは \(RunnerAccessibility.stageHeadline(number: model.stageNumber + 1))")
                .themeCaption(13)
                .foregroundStyle(.white.opacity(0.85))
        }
        .accessibilityElement(children: .combine)
    }

    /// エンドレスのリザルト 2 行（走行距離と自己ベスト・#675）。
    ///
    /// 共通の `RecordLabel` は使わない。あちらの「自己ベスト N」は単位が無く、
    /// 走行距離であることが読み取れない。
    private var endlessDetail: some View {
        VStack(spacing: 4) {
            Text("走行距離 \(distanceText(model.distanceMeters))")
                .themeBody(15)
                .foregroundStyle(.white)
            Text(model.endlessBestDistance.map { "自己ベスト \(distanceText($0))" } ?? "自己ベストはまだありません")
                .themeCaption(13)
                .foregroundStyle(.white.opacity(0.85))
            if model.didSetBestDistance {
                // 全ゲーム共通の印（#794）。塗りつぶしだと隣の「もう一度」ボタンと同色で押せるものに見える
                // （監査 #808 → #819。#794 の 22 分後にマージされた #795 が旧来の書き方を持ち込んでいた）。
                RecordBadge("自己ベスト更新！")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            RunnerAccessibility.distanceLabel(model.distanceMeters) + "。"
                + RunnerAccessibility.bestDistanceLabel(model.endlessBestDistance)
                + (model.didSetBestDistance ? "。自己ベスト更新" : "")
        )
    }

    /// ミスからのやり直し。ステージ制は同じステージの頭から、エンドレスは新しいコースで。
    private var retryButton: some View {
        Button {
            model.retryStage()
        } label: {
            Label("もう一度", systemImage: "arrow.clockwise")
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Fill.coral)
    }

    // MARK: - スタート画面（#931）

    /// 走り出す前（`.ready`）にコースの上へ重ねるカード。
    ///
    /// 「エンドレスはどこから選べる？」（会長 QA 2026-09-15）に #919 は一時停止ボタンの行へ
    /// 小さな切り替えを相乗りさせて応えたが、「発想が貧弱」とやり直しになった。ここでは
    /// **走り出す前の画面そのものをスタート画面**にする。上から、
    /// 1. 主ボタン「▶ 2-3」——次に遊ぶ面の番号（名前は #946 で外した）を世界の色で。押せばその面で走り出す
    /// 2. 「∞ エンドレス」——自己ベストを添えて。押せば新しい種で走り出す
    /// 3. 「マップ」——ワールドマップ（開始シート #798）を開く
    ///
    /// カードは**コースの中に重ねる**（コースの外に行を足さない）ので、iPhone SE でも盤・カード・
    /// 広告帯の縦の配分は変わらない。カードの外側のタップはこれまでどおりコースに届き、
    /// いまのコースをそのまま走り出す（主ボタンと同じ）。
    /// チェックポイント再開の直後（`!canChooseMode`）は、広告で得た途中からの再開を捨てさせないよう
    /// 「▶ つづきから」の主ボタン 1 つだけにする。
    ///
    /// 出るのは**ハブから入った直後・「はじめから」・マップで面を選んだとき・チェックポイント再開**だけ。
    /// 「次の面へ」「もう一度」「このステージをもう一度」は `.ready` を挟まずその場で走り出す
    /// （#941。面をまたぐたびにここでもう 1 タップさせない）。
    private var startScreen: some View {
        ZStack {
            // 薄い幕でカードを立たせる。タップは透過（コースで走り出せる）。
            // 初回の操作ガイド（#988）が出ている間だけは幕でタップを受け止める——読んでいる
            // 途中の指が当たって走り出すのを防ぐだけで、ガイド自体は対話型にしない
            // （「はじめる」を押せば閉じてそのまま走り出す）。
            Rectangle()
                .fill(.black.opacity(showsTutorial ? 0.45 : 0.3))
                .allowsHitTesting(showsTutorial)
            VStack(spacing: 10) {
                if showsTutorial {
                    tutorialCard
                } else {
                    // 主ボタンの左におじさんの笑顔を小さく添える（#702・2 倍 = 32×30pt）。
                    // 顔は装飾なので VoiceOver には出ず、主ボタンの読み上げはこれまでどおり。
                    HStack(spacing: 10) {
                        if let face = RunnerResultFace.face(for: .ready) {
                            ojisanFace(face, scale: RunnerResultFace.startDotScale)
                        }
                        startMainButton
                    }
                    if model.canChooseMode {
                        startEndlessButton
                        mapLink
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 300)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            )
            .padding(.horizontal, 20)
        }
    }

    /// 初回プレイだけスタート画面に出す操作ガイド（#988）。
    ///
    /// 覚えてほしい 3 つ（`RunnerTutorial.steps`）を短い文と小さな絵で 1 画面に。頭の絵は
    /// 走者の「跳ぶ」コマ（`OjisanPixel.RiderFrame.jump`）で、新しいドット絵は描き起こさない。
    /// **コースの中に重ねる**ので盤・カード・広告帯の縦の配分は変わらない（スタート画面と同じ枠）。
    /// 「はじめる」で閉じ、そのままステージ制で走り出す（印は `init` で残してあるので次からは出ない）。
    private var tutorialCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RunnerTutorial.riderJump(height: 40)
                Text("そうさのしかた")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            RunnerTutorialSteps()
            Button {
                showsTutorial = false
                model.start(.stages)
            } label: {
                Label("はじめる", systemImage: "play.fill")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                            .fill(Theme.Fill.coral)
                    )
            }
            .buttonStyle(.pop)
            .accessibilityLabel("はじめる")
        }
    }

    /// 世界の色の上に載せる文字色。
    ///
    /// `RunnerWorld.mapColor` は文字を載せる前提の色ではない（ワールドマップでは帯と薄い色味にだけ
    /// 使っている）。主ボタンは面いっぱいに塗るので、どの世界でも読めるよう**ライト / ダークで
    /// 変わらない濃い茶**にする。白は朝の水色（0x6FC3EE）で 2:1 を切り、`Theme.ink` は夜（0x6B7FC2）で
    /// 3:1 を切るが、この色なら朝 9:1・夕方 5:1・夜 4.7:1 で 3 世界とも 4.5:1 以上。
    private static let onWorld = Color(hex: 0x1A1410)

    /// 画面に出す面の見出し。QA 用のショーケース（DEBUG）を走っているあいだは面の番号を
    /// 名乗らない——コースが本番の面と違うのに「3-3」と出ると取り違える（2026-09-15）。
    private var stageHeadlineText: String {
        model.isRunningDebugStage
            ? "ショーケース"
            : RunnerAccessibility.stageHeadline(number: model.stageNumber)
    }

    /// 主ボタン。次に遊ぶ面（`stageNumber`）をその世界の色で。
    private var startMainButton: some View {
        let number = model.stageNumber
        let world = RunnerWorld.world(forStage: number)
        let resumingFromCheckpoint = !model.canChooseMode
        return Button {
            model.start(.stages)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .heavy))
                VStack(alignment: .leading, spacing: 1) {
                    if resumingFromCheckpoint {
                        Text("つづきから")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                    } else {
                        Text("ワールド \(world.number) \(world.displayName)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .opacity(0.8)
                        Text(RunnerAccessibility.stageHeadline(number: number))
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Self.onWorld)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(Color(hex: world.mapColor))
            )
        }
        .buttonStyle(.pop)
        .accessibilityLabel(
            resumingFromCheckpoint ? "つづきから走る" : RunnerAccessibility.startStageLabel(number: number)
        )
    }

    /// エンドレス（#675）。自己ベストを添える（無ければ「まだ記録なし」）。
    private var startEndlessButton: some View {
        Button {
            model.start(.endless)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "infinity")
                    .font(.system(size: 18, weight: .heavy))
                VStack(alignment: .leading, spacing: 1) {
                    Text("エンドレス")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                    Text(model.endlessBestDistance.map { "自己ベスト \(distanceText($0))" } ?? "まだ記録なし")
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.inkSub)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(Theme.Fill.coral.opacity(0.12))
            )
        }
        .buttonStyle(.pop)
        .accessibilityLabel(RunnerAccessibility.startEndlessLabel(bestDistance: model.endlessBestDistance))
    }

    /// ワールドマップ（#798）へ。開始シートをステージ制・いまの面を選んだ状態で開く。
    /// ツールバーの「はじめから」（1 面から）と違い、「どの面から走るか」を選びに行く導線なので
    /// つづきの面を選んでおく。
    private var mapLink: some View {
        Button {
            openStartSheet(mode: .stages, stage: model.stageNumber)
        } label: {
            Label("マップ", systemImage: "map.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
                .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .buttonStyle(.pop)
        .accessibilityHint("ワールドマップを開いて面を選ぶ")
    }

    private var pausedOverlay: some View {
        panel(title: "一時停止") {
            // ゆっくりモードの切り替えは設定画面のみに一本化した（#631）。ゲーム内の
            // 一時停止からいつでも切り替えられると、難所の直前で止めてオンにする→通過後に
            // オフへ戻す、を繰り返すだけで難易度をいくらでも調整できてしまい、
            // アクセシビリティの代替手段のはずが抜け道になっていた
            // （会長QA「一時停止でゆっくりモードに変えれるといくらでも難易度調整できる」・
            // 2026-09-11）。設定変更時は`GameSettings.slowModeEnabled`のdidSetで
            // 中断データを破棄するため、この画面を経由した抜け道は無い。

            Button {
                model.resume()
            } label: {
                Label("再開", systemImage: "play.fill")
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Fill.coral)

            restartButton
        }
    }

    private var resumeButton: some View {
        Button {
            // どのコースへの再開かを広告前に控える。ロード中に「はじめから」等で
            // コースが作り直されたら適用せず知らせる（ソリティアの補充と同じ契約。#509）。
            let run = model.runGeneration
            resumeRescue.request(
                services, gameID: RunnerModel.gameID, purpose: .checkpoint,
                guardedBy: .checkedByGrant
            ) {
                model.resumeFromCheckpoint(forRun: run)
            }
        } label: {
            Label("広告を見て途中から再開", systemImage: "play.rectangle.fill")
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Fill.coral)
        .disabled(resumeRescue.isWatching)
    }

    private var replayButton: some View {
        Button("このステージをもう一度") { model.replayCurrentStage() }
            .buttonStyle(.bordered)
            .tint(.white)
    }

    private var restartButton: some View {
        Button("はじめから") { model.newGame() }
            .buttonStyle(.bordered)
            .tint(.white)
    }

    /// リザルト・一時停止の幕。`face` を渡すと見出しの上におじさんの顔を出す（#702。一時停止は nil）。
    /// 幕はコースの中に重ねるので、顔を足しても盤・カード・広告帯の縦の配分は変わらない。
    private func panel<Content: View>(
        title: String,
        face: OjisanPixel.Face? = nil,
        faceScale: Int = 4,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.6))
            VStack(spacing: 12) {
                if let face {
                    ojisanFace(face, scale: faceScale)
                }
                Text(title).font(.title3.bold()).foregroundStyle(.white)
                content()
            }
            .padding(20)
        }
    }

    /// レコメンドカードの枠。高さの担保は `RecommendationArea`（#148）。
    private var recommendationArea: some View {
        // ステージ制は全クリアで、エンドレスはミス（= 1 回の決着）で「終わった」（#675）。
        RecommendationArea(services: services, isFinished: model.isRunOver)
    }

    /// 遊び方のヒントとレコメンドは、プレイ中に何度も見るものではないので
    /// `course` の下に小さく残す（会長QA「ゲーム画面を下まで広げたい」）。
    /// どちらも中身が無ければ実質高さ 0（`HowToPlayHint` は2回目以降 `EmptyView`）か
    /// 固定の小さなプレースホルダなので、スクロールにしなくても場所を圧迫しない。
    private var secondaryInfo: some View {
        VStack(spacing: 6) {
            // 初回の操作ガイド（#988）を出した回は出さない。ガイドの 1 行目と同じ
            // 「タップでジャンプ」を同じ画面で二度言うことになる。見るのは
            // `showsTutorial`（いま出しているか）ではなく `tutorialShownOnOpen`
            // （この画面で出したか）——「はじめる」で閉じた直後の再描画でヒントが
            // 組み立てられてしまうため。`HowToPlayHint` は組み立てた時点で印を消費するので、
            // ここを通らない回は消費もしない ＝ 次にこの画面を開いたときに 1 行ヒントとして出る。
            if !tutorialShownOnOpen {
                HowToPlayHint(.runner, playLog: services.playLog)
            }
            recommendationArea
        }
    }
}

// MARK: - 開始シート（#675）

/// 「はじめから」で開く、モード（ステージ制／エンドレス）と始める面を選ぶシート。
///
/// 枠は共通の `GameSetupSheet`、モードの選び方は麻雀の東風戦／一局戦（`MahjongStartSheet`）と
/// 同じセグメントのピッカー + 1 行の説明。ステージ制のときだけ下にワールドマップ（#798）が
/// 付く。選んだモードと面は `RunnerModel.newGame(startingAtStage:)` / `newGame(mode:)` で
/// 走行に焼き込まれ、走行中に読み替えられることはない（1局=1RuleSet）。
///
/// 並べ方は `.scrolling`（常に `.large`）。3 世界 × 6 面の格子は 3 列 × 2 段を 3 つ積むので、
/// モードの節と合わせると `.medium` には収まらない（`GameSetupSheet` の注意書きどおり、
/// 収まらない中身を `pinnedStart` にすると開始ボタンが押せなくなる）。エンドレスを選んで
/// 格子が消えても高さは変えない——シートの高さが開いている最中に動くのを避ける。
struct RunnerStartSheet: View {
    @Binding var mode: RunnerMode
    /// ワールドマップで選んでいる面（1 始まり）。
    @Binding var selectedStage: Int
    /// 到達した最大の面。これより先は鍵付きで押せない（`RunnerModel.reachedStage`）。
    let reachedStage: Int
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        GameSetupSheet(
            title: "はじめから", startTitle: "スタート", layout: .scrolling,
            onStart: onStart, onCancel: onCancel
        ) {
            GameSetupSection("モード") {
                Picker("モード", selection: $mode) {
                    ForEach(RunnerMode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text(mode.summary)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if mode == .stages {
                GameSetupSection("ステージを選ぶ") {
                    RunnerWorldMap(selectedStage: $selectedStage, reachedStage: reachedStage)
                }
            }
        }
    }
}

// MARK: - ワールドマップ（#798）

/// 開始シートに載せる 3 世界 × 6 面の格子。到達済みの面だけ選べる。
///
/// **世界ごとに 3 列 × 2 段**にしてある。マスに出すのは「1-1」の表記だけ（面の名前は #946 で
/// 外した）。6 列 1 段だと iPhone SE（幅 375pt・シートの余白を引いて 343pt）では 1 マスが
/// 50pt 前後になり鍵の絵と並べると窮屈なので、3 列のままにしてある。
/// マスの高さは名前の行が無くなっても 44pt を割らないよう `minHeight` で担保する。
///
/// 世界の色（`RunnerWorld.mapColor`）は**見出しの丸・マスの上端の帯・マスの薄い色味**にだけ
/// 使い、文字はその上に載せない（世界の空の色は文字とのコントラストが世界ごとにばらつくため。
/// 面と文字の組み合わせは `Theme` のまま）。選択中は他の設定シート（`GameSetupChooser`）と
/// 同じ「差し色で塗って `onAccent` の文字」にして、選んでいることの見え方をアプリ全体で揃える。
/// 未到達は鍵の絵と薄い文字で、押せない（`disabled`）。
struct RunnerWorldMap: View {
    @Binding var selectedStage: Int
    let reachedStage: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(RunnerWorld.allCases, id: \.self) { world in
                VStack(alignment: .leading, spacing: 8) {
                    worldHeader(world)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(world.stageRange, id: \.self) { number in
                            stageCell(number, world: world)
                        }
                    }
                }
            }
        }
    }

    private func worldHeader(_ world: RunnerWorld) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: world.mapColor))
                .frame(width: 10, height: 10)
            Text("ワールド \(world.number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSub)
            Text(world.displayName)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func stageCell(_ number: Int, world: RunnerWorld) -> some View {
        let reached = number <= reachedStage
        let selected = reached && number == selectedStage
        let tint = Color(hex: world.mapColor)
        return Button {
            selectedStage = number
        } label: {
            HStack(spacing: 4) {
                // 数値の桁区切りが入らないよう verbatim で出す。
                Text(verbatim: RunnerWorld.code(forStage: number))
                    .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                if !reached {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(selected ? Theme.onAccent : (reached ? Theme.ink : Theme.inkSub))
            // 上下の余白 10pt と合わせて 44pt（iOS の最小のタップ寸）。
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                        .fill(selected ? Theme.Fill.coral : (reached ? tint.opacity(0.16) : Theme.surface))
                    // 世界の色の帯。未到達は薄くして「まだ塗られていない」ことを見せる。
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(reached ? 1 : 0.35))
                        .frame(height: 4)
                        .padding(.horizontal, 10)
                        .padding(.top, 3)
                }
                .shadow(color: .black.opacity(selected ? 0.15 : 0.06), radius: 6, y: 3)
            )
        }
        .buttonStyle(.pop)
        .disabled(!reached)
        .accessibilityLabel(RunnerAccessibility.stageMapLabel(number: number, reached: reached))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
