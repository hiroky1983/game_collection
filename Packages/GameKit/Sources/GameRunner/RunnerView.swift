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
    /// **`private` を付けないのは意図的**（#1106）。ヘッダーを別ファイルの extension
    /// （`RunnerView+Header.swift`）へ分けた際、そちらから読むため。Swift では別ファイルの
    /// extension から `private` に手が届かないので、同じモジュール内にだけ開けてある。
    @State var model: RunnerModel
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
    /// 初回プレイの操作ガイド（#988）をいま出しているか。「はじめる」で false になる。
    ///
    /// **判定と「見せた」の記録は、実際に出す直前（`presentTutorialIfNeeded`）でまとめて行う**
    /// （#1144）。`init` で済ませると、先に流れるストーリーの始まり（#1092・最長 4.8 秒）の
    /// あいだに「戻る」で離れた人が、一度も見ていないのに二度と見られなくなる。
    @State private var showsTutorial = false
    /// `init` の時点で「ストーリーの始まりを出す回」だったか（#1092）。
    /// 判定だけで印は付かない（付けるのは見せ終えた時点・#1144）。
    @State private var pendingIntro: Bool
    /// いま流している始まり。世界の締めのほうは `model.storyScene` が持つ。
    @State private var introScene: RunnerStoryScene?
    /// 撮影・QA で止めるコマ（`-simulateRunner story-world3:2`）。製品では常に nil のまま
    /// （立てるのは `onAppear` の `#if DEBUG` の中だけ）。
    @State private var frozenStoryPanel: Int?
    @Environment(\.scenePhase) private var scenePhase

    public init(services: GameServices) {
        self.services = services
        let model = RunnerModel(services: services)
        _model = State(initialValue: model)
        _scene = State(initialValue: RunnerScene(model: model))
        // 順番は 始まり → 操作ガイド → 開始シート（#1092 の受け入れ条件 A）。
        // ここで見るのは始まりだけ（「見せた」の印は付かない・#1144）。操作ガイドの判定は
        // 始まりが明けてから（`presentTutorialIfNeeded`）で、`init` では触らない。
        _pendingIntro = State(initialValue: RunnerStory.shouldShowIntro(playLog: services.playLog))
    }

    /// いま画面を覆っているストーリーの場面（始まり or 世界の締め）。
    private var presentedStory: RunnerStoryScene? { introScene ?? model.storyScene }

    /// 画面下のバナー広告を出すか（#1147）。
    ///
    /// ストーリー（#1092）の幕は画面いっぱいを覆うので、出したままだと**見えないバナーの
    /// インプレッションが計上されうる**（AdMob の「広告を他の要素で覆わない」に触れる）。
    /// 幕が出ているあいだは枠ごと外す。**枠の高さ（`BannerSlot.height`）は空の帯で保つ**——
    /// 縦幅の分配が変わるとコース（SpriteKit の面）の高さまで動くため。
    ///
    /// 幕が明けると `BannerSlot` が作り直され、そのぶん広告のリクエストが増える（ストーリーは
    /// 1 人あたり最大 6 回・各 5 秒以内なので、ゲーム画面を開き直すのと同程度）。見えない
    /// インプレッションを残すより副作用が小さいと判断した（PR の `## 社長判断`）。
    static func showsBanner(isStoryPresented: Bool) -> Bool { !isStoryPresented }

    /// 始まりが明けた / 出さない回の続き。操作ガイドがあればそれを、無ければ開始シートを出す。
    private func beginAfterIntro() {
        if !presentTutorialIfNeeded() {
            presentStartSheetIfNeeded()
        }
    }

    /// 初回プレイの操作ガイド（#988）を出す回なら出す。**判定と「見せた」の記録はここだけ**（#1144）。
    ///
    /// `RunnerTutorial.shouldShow` は判定と記録を兼ねるので、呼ぶ場所が提示の瞬間から離れると
    /// その分だけ「印は付いたのに見ていない」窓ができる。#1123 で始まり（#1092）のオーバーレイが
    /// 手前に入り、`init` で呼んでいた従来の作りでは最長 4.8 秒の窓ができていた。
    ///
    /// - Returns: 出したか。false なら開始シートへ進んでよい。
    @discardableResult
    private func presentTutorialIfNeeded() -> Bool {
        guard RunnerTutorial.shouldShow(playLog: services.playLog) else { return false }
        showsTutorial = true
        return true
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
            if Self.showsBanner(isStoryPresented: presentedStory != nil) {
                BannerSlot(ads: services.ads)
            } else {
                // 幕のあいだも枠の高さだけは残す（`showsBanner` の doc）。
                Color.clear.frame(height: BannerSlot.height)
            }
        }
        .padding()
        .gameChrome(title: "チャリンコおじさん", review: services.review) {
            ToolbarItem(placement: .primaryAction) {
                // モードを変える唯一の導線（#1027）。開始シートを経由する（#675。チェスの
                // 「新規対局」と同じ作法）。走行中なら読んでいる間にミスしないよう止める。
                // アイコンを一回り大きくして見つけやすくする（会長指摘「トグルボタンが小さい」・
                // 2026-09-16）。
                Button {
                    if model.phase == .running { model.pause() }
                    openStartSheet(mode: model.mode, stage: 1)
                } label: {
                    Label("はじめから", systemImage: "arrow.clockwise")
                }
                .imageScale(.large)
                // ストーリー（#1092）が画面を覆っているあいだは押せない。ナビバーはオーバーレイの
                // 外にあるので物理的には押せてしまい、始まり → 操作ガイド → 開始シートの順番
                // （決裁の受け入れ条件 A）が崩れる。飛ばしたい人はタップか「スキップ」で抜けられる。
                .disabled(presentedStory != nil)
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
        // 初回プレイの操作ガイド（#988）は**モーダル**で出す（会長指摘 2026-09-16）。
        // 以前はコースの上のカードで出していたが、その「はじめる」がステージ制で走り出す
        // 作りだったため、初回だけモードを選べず・右上からエンドレスを選んでもガードの
        // 「はじめる」がステージ制で上書きしてしまっていた。閉じたら（`onDismiss`）
        // そのまま開始シートへ送り、初回も 2 回目以降と同じ導線にする。
        .sheet(isPresented: $showsTutorial, onDismiss: { presentStartSheetIfNeeded() }) {
            RunnerTutorialSheet { showsTutorial = false }
        }
        // ストーリー（#1092）。始まりは開く前・世界の締めはクリアの結果パネルの手前に、
        // どちらも画面いっぱいで流す。シートより下に置くので、シートが出ているあいだは被らない。
        .overlay {
            if let scene = presentedStory {
                RunnerStoryView(scene: scene) {
                    if introScene != nil {
                        introScene = nil
                        // 最後のコマまで送った／「スキップ」（画面タップ）で抜けた時点が
                        // 「見せた」。途中で戻った人には次回もう一度流す（#1144）。
                        RunnerStory.markIntroShown(playLog: services.playLog)
                        beginAfterIntro()
                    } else {
                        model.finishStory()
                    }
                }
                .frozenStoryPanel(frozenStoryPanel)
            }
        }
        .sheet(isPresented: $showStartSheet, onDismiss: {
            // 始まり（#1092）を中断してここへ来た場合、操作ガイドがまだ出ていないので拾う。
            // ふつうの経路では出し終えている＝印が付いているので、`shouldShow` が false になり
            // 何も起きない（#1144 で印の消費を提示の直前へ寄せたため、二重表示にならない）。
            _ = presentTutorialIfNeeded()
        }) {
            RunnerStartSheet(
                mode: $selectedMode, selectedStage: $selectedStage, reachedStage: model.reachedStage,
                playLog: services.playLog
            ) {
                // 選んだモード・面でコースを作るところまで。**走り出しはしない**——シートを
                // 閉じるとコースの上に「タップでスタート」（`tapToStartHint`）が出て、
                // 画面のどこかを 1 回タップした瞬間に走り出す（会長指示「一回タップしたら
                // スタートさせる形にしてほしい」・2026-09-16）。
                // 遅延で勝手に走り出す合図（0.45 秒のフラッシュ）は同じ指示で撤去した。
                showStartSheet = false
                switch selectedMode {
                case .stages:  model.newGame(startingAtStage: selectedStage)
                case .endless: model.newGame(mode: .endless)
                }
            } onCancel: {
                showStartSheet = false
            }
        }
        .onAppear {
            // 設定画面で切り替えられていたら取り込む（書き手は設定画面とポーズ画面の 2 か所）。
            model.syncSlowModeFromPreference()
            #if DEBUG
            // 撮影・動作確認用: `-simulateRunner <running|paused|failed|cleared|chasing|showcase|bird|bird:N|platform|floor|invincible|wall|wall-double|wall:N|stage:N|stage:N@距離|map:N|story-intro|story-world1〜story-world5|endless|endless-running|endless-far|endless-far-failed|endless-autopilot|endless-failed>`（#494・#675・#797・#1086・#1009・#1091・#1092）。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-simulateRunner"), i + 1 < args.count {
                // ストーリーの始まり（#1092）だけは走行と無関係な View の状態なので、
                // モデルのシナリオではなくここで立てる（締めのほうはモデルが `.story` にする）。
                frozenStoryPanel = RunnerStory.debugPanelIndex(for: args[i + 1])
                if RunnerStory.debugScene(for: args[i + 1]) == .intro {
                    introScene = .intro
                } else {
                    model.applyDebugScenario(args[i + 1])
                }
            }
            // 撮影用: 開始シート（ワールドマップ #798）を開いた状態にする（`-showRunnerStartSheet`）。
            if args.contains("-showRunnerStartSheet") {
                openStartSheet(mode: model.mode, stage: 1)
            }
            #endif
            // 自動表示の判断は**起動引数を適用したあと**（#1063）。先に判断すると、その時点では
            // まだ `.ready` なので撮影・QA の画面（`-simulateRunner`）にもシートが被る。
            // ストーリーの始まり（#1092）を出す回は、それが明けてから操作ガイド・開始シートへ進む。
            if pendingIntro {
                pendingIntro = false
                introScene = .intro
            } else {
                beginAfterIntro()
            }
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

    /// 開始シート（`RunnerStartSheet`）を、選んでおくモードと面を決めて開く。
    /// ツールバーの「はじめから」の経路（#1027。「マップ」導線はカードごと廃止した）。
    private func openStartSheet(mode: RunnerMode, stage: Int) {
        // 始まり（#1092）が出ているあいだツールバーは押せないようにしてあるが、撮影用の
        // `-showRunnerStartSheet` など他の経路から来ても取り残しを作らないよう畳んでおく。
        // 畳まないと開始シートの下に始まりが残り、閉じた拍子に開始シートがもう一度開く。
        // 出していない操作ガイドは開始シートの `onDismiss` が引き取る。
        introScene = nil
        selectedMode = mode
        selectedStage = stage
        showStartSheet = true
    }

    /// **ハブから画面を開いた直後だけ**、モード・面を選ぶ開始シートを自動で出す（#1027）。
    ///
    /// `.ready` に着地するたびに出してはいけない（会長QA「失敗したときにもう一度を押すと
    /// モーダルが出てくる。同じゲームをもう一回続けるだけでOK」・2026-09-16）。エンドレスの
    /// 「もう一度」は `.ready` に戻るので、局面の変化を見て出す作りだとミスのたびに
    /// モード選びが挟まっていた。呼び出しは `onAppear` の 1 か所だけにしてある。
    ///
    /// チェックポイント再開直後（`canChooseMode == false`）は出さない——広告で得た再開を
    /// 誤って手放させない。初回の操作ガイド中（`showsTutorial`）も出さない。
    private func presentStartSheetIfNeeded() {
        guard Self.shouldPresentStartSheet(
            phase: model.phase, canChooseMode: model.canChooseMode,
            showsTutorial: showsTutorial, showStartSheet: showStartSheet
        ) else { return }
        openStartSheet(mode: model.mode, stage: model.stageNumber)
    }

    /// `presentStartSheetIfNeeded` の実体（純関数・#1063）。
    ///
    /// 撮影モード（`-screenshotMode`）と QA・撮影用の画面（`-simulateRunner`）では出さない——
    /// 走行中の画を撮る指定にシートが被ると、ASO のスクリーンショット
    /// （`Scripts/capture-aso-screenshots.sh` の `05-runner`）がシートごと写る。開始シートそのものを
    /// 撮る `-showRunnerStartSheet` は別の経路（`openStartSheet`）で開くので、ここで塞いでよい。
    /// `-simulateRunner` が効くのは DEBUG だけだが、判定は構成で分けない——リリース構成に
    /// 撮影用の引数が渡ることは無く、渡っても開始シートが出ないだけで済む。
    ///
    /// - Parameter arguments: 起動引数。既定は実プロセスのもので、テストが撮影・QA の起動を固定するために差し替える。
    static func shouldPresentStartSheet(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        phase: RunnerPhase,
        canChooseMode: Bool,
        showsTutorial: Bool,
        showStartSheet: Bool
    ) -> Bool {
        guard !arguments.contains("-screenshotMode"), !arguments.contains("-simulateRunner") else { return false }
        return phase == .ready && canChooseMode && !showsTutorial && !showStartSheet
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
        .accessibilityHint(RunnerAccessibility.courseHint(phase: model.phase))
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
        case .chasing:
            // 宝くじを追いかける短い演出中（#1092）。クリアのパネルはこの演出が終わってから出す。
            EmptyView()
        case .story:
            // 世界の締めの演出中（#1092）。場面は `RunnerStoryView` が画面いっぱいに被せるので、
            // コースの上には何も出さない（クリアのパネルは締めが明けてから）。
            EmptyView()
        case .failed:
            // ミスの表示は両モードで同じ枠（#675「既存の失敗リザルトを流用」）。エンドレスは
            // ミスがそのまま決着なので、走行距離と自己ベストの行が加わる。
            panel(title: "ミス！", face: resultFace, faceScale: faceScale) {
                if model.mode == .endless { endlessDetail }
                if model.canResumeFromCheckpoint { resumeButton }
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

    /// おじさんの顔をドット絵の比率（32×30）のまま整数倍で置く（#702）。`scale` は旧来（16×15）の 1 ドット = 何 pt かで、
    /// 顔が細かくなった（#1349）ぶん実際の 1 ドットは `scale / faceResolution` pt になり、大きさは変わらない。
    /// `Core` の `OjisanPixel.faceImage` は装飾画像なので VoiceOver には出ない。
    private func ojisanFace(_ face: OjisanPixel.Face, scale: Int) -> some View {
        let dots = OjisanPixel.faceDotSize
        let res = OjisanPixel.faceResolution
        return OjisanPixel.faceImage(face)
            .frame(width: CGFloat(dots.width * scale / res), height: CGFloat(dots.height * scale / res))
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
    ///
    /// 広告のロード〜視聴中は押せない（#1068）。押すと `runGeneration` が進み、見終えた広告が
    /// `resumeFromCheckpoint(forRun:)` の世代照合で弾かれて視聴が無駄になる（#816 / #911 と同型）。
    private var retryButton: some View {
        Button {
            model.retryStage()
        } label: {
            Label("もう一度", systemImage: "arrow.clockwise")
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Fill.coral)
        .disabled(resumeRescue.isWatching)
    }

    // MARK: - スタート画面（#931 → #1027 でカードを縮小）

    /// 走り出す前（`.ready`）にコースの上へ重ねるカード。
    ///
    /// #931 では「▶ 次の面」「∞ エンドレス」「マップ」の 3 段カードをここへ毎回自動で出していたが、
    /// 「マップ」を押す→別シートで選ぶ→**このカードに戻ってもう一度スタートを押す**、という
    /// 二度打ちが起きていた（会長QA「はじめからモーダルからセレクトしてもう一回モード選択が
    /// 挟まるのでうざい」・2026-09-16）。#1027 でモード・面選びは開始シート（`RunnerStartSheet`）
    /// 1 本に統一し（`presentStartSheetIfNeeded`）、**このカードはチェックポイント再開と
    /// 初回ガイドの 2 パターンだけ**になった。
    ///
    /// - チェックポイント再開の直後（`!canChooseMode`）: 広告で得た途中からの再開を
    ///   誤タップで手放させないよう、「▶ つづきから」の主ボタン 1 つだけを出す
    /// - どちらでもない（`canChooseMode == true`）: 「タップでスタート」（`tapToStartHint`）
    ///
    /// カードは**コースの中に重ねる**（コースの外に行を足さない）ので、iPhone SE でも盤・カード・
    /// 広告帯の縦の配分は変わらない。
    ///
    /// 「次の面へ」「もう一度（ステージ制）」「このステージをもう一度」は `.ready` を挟まず
    /// その場で走り出す（#941。面をまたぐたびにここでもう 1 タップさせない）。
    @ViewBuilder
    private var startScreen: some View {
        if model.canChooseMode {
            tapToStartHint
        } else {
            ZStack {
                // 薄い幕でカードを立たせる。タップは透過（コースで走り出せる）。
                Rectangle().fill(.black.opacity(0.3)).allowsHitTesting(false)
                // 主ボタンの左におじさんの笑顔を小さく添える（#702・2 倍 = 32×30pt）。
                // 顔は装飾なので VoiceOver には出ず、主ボタンの読み上げはこれまでどおり。
                HStack(spacing: 10) {
                    if let face = RunnerResultFace.face(for: .ready) {
                        ojisanFace(face, scale: RunnerResultFace.startDotScale)
                    }
                    startMainButton
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
    }

    /// 走り出す前（`.ready`）にコースへ重ねる「タップでスタート」（#1027）。
    ///
    /// 会長指示「一回タップしたらスタートさせる形にしてほしい（UIも追加）」（2026-09-16）。
    /// **押すボタンではない**——`allowsHitTesting(false)` でタップを素通りさせ、コースのどこを
    /// タップしても `playfield` のジェスチャー（`RunnerModel.press()`）が拾って走り出す。
    /// 「スタート」を押した 0.45 秒後に勝手に走り出す合図は、同じ指示で撤去した。
    private var tapToStartHint: some View {
        VStack(spacing: 12) {
            if let face = RunnerResultFace.face(for: .ready) {
                ojisanFace(face, scale: RunnerResultFace.startDotScale)
            }
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 17, weight: .heavy))
                Text("タップでスタート")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(Capsule().fill(Theme.Fill.coral))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .allowsHitTesting(false)
        // 読み上げはコース側（`courseLabel` / `accessibilityHint`「ダブルタップでジャンプ」）が
        // 受け持つ。ここを独立した要素にすると同じ案内が二重に読まれる。
        .accessibilityHidden(true)
    }

    /// 世界の色の上に載せる文字色。
    ///
    /// `RunnerWorld.mapColor` は文字を載せる前提の色ではない（ワールドマップでは帯と薄い色味にだけ
    /// 使っている）。主ボタンは面いっぱいに塗るので、どの世界でも読めるよう**ライト / ダークで
    /// 変わらない濃い茶**にする。白は朝の水色（0x6FC3EE）で 2:1 を切り、`Theme.ink` は夜（0x6B7FC2）で
    /// 3:1 を切るが、この色なら朝 9:1・夕方 5:1・夜 4.7:1・里山（田の緑）9:1・港町（海の青）7.7:1 で
    /// 4.5:1 以上（`RunnerStageCodeTests.mapColorsAreDistinguishable` が固定・#1009）。
    private static let onWorld = Color(hex: 0x1A1410)

    /// 画面に出す面の見出し。QA 用のショーケース（DEBUG）を走っているあいだは面の番号を
    /// 名乗らない——コースが本番の面と違うのに「3-3」と出ると取り違える（2026-09-15）。
    var stageHeadlineText: String {
        model.isRunningDebugStage
            ? "ショーケース"
            : RunnerAccessibility.stageHeadline(number: model.stageNumber)
    }

    /// 主ボタン（チェックポイント再開の「つづきから」）。世界の色で塗る。
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

    /// 一時停止・全ステージクリアから「はじめから」。ツールバーの同名ボタンと同じく
    /// 開始シートを経由する（#1027。`.ready` に着地しただけではシートを出さなくなったので、
    /// モードや面を選び直したいこの導線だけは自分で開く）。
    private var restartButton: some View {
        Button("はじめから") { openStartSheet(mode: model.mode, stage: 1) }
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
            // 操作の 1 行は**走行中ずっと出す**（会長指摘「タップしてジャンプはゲーム中に常時
            // 出てほしいセクションなのになんでゲーム中に消えんの」・2026-09-16）。
            // 共通部品の既定（`HowToPlayHint(_:playLog:)`）は「初回だけ」で、印を消費した
            // 次の再描画から消えるため、遊んでいる最中に行ごと消えて画面が動いていた。
            // 出すかを呼び出し側が決める初期化子（#650）に true を固定で渡し、消さない。
            HowToPlayHint(.runner, isVisible: true)
            recommendationArea
        }
    }
}
