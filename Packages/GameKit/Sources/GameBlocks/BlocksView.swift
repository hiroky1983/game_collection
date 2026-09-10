import Core
import SpriteKit
import SwiftUI

/// ブロック崩しのプレイ画面（#463）。
///
/// SpriteKit（`BlocksScene`）が描くのはプレイフィールドだけで、
/// ヘッダー・オーバーレイ・遊び方・レコメンド・バナーはこれまでのゲームと同じ SwiftUI 部品を使う。
/// これが基盤規約の「メニュー・リザルト・設定は SwiftUI」の実体。
public struct BlocksView: View {
    private let services: GameServices
    @State private var model: BlocksModel
    @State private var scene: BlocksScene
    /// コンティニューのリワード広告の段取り（連打ガード・広告・失敗アラート。#526）。
    @State private var continueRescue = RewardedRescue()
    @State private var showConfirmNewGame = false
    /// 確認ダイアログを出すために**自分で**止めたか（#515）。
    /// 元から一時停止中だった場合まで再開してしまわないよう区別する。
    @State private var pausedForNewGameConfirm = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    public init(services: GameServices) {
        self.services = services
        let model = BlocksModel(services: services)
        _model = State(initialValue: model)
        _scene = State(initialValue: BlocksScene(model: model))
    }

    public var body: some View {
        VStack(spacing: 14) {
            header
            playfield
            HowToPlayHint(.blocks, playLog: services.playLog)
            recommendationArea
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding()
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
                Text("ブロック崩し")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { startNewGame() } label: {
                    Label("はじめから", systemImage: "arrow.clockwise")
                }
            }
        }
        .howToPlay(.blocks, onPresent: {
            // 読んでいる間に落球しないよう止める。発射前（.ready）は動くものが無いので
            // 止めない（初見の人が遊ぶ前に開く一番多い経路で、余計な「再開」を挟まない）。
            if model.phase == .playing { model.pause() }
        })
        .onAppear {
            // 設定画面で切り替えられていたら取り込む（書き手は設定画面とポーズ画面の 2 か所）。
            model.syncSlowModeFromPreference()
            #if DEBUG
            // 撮影・動作確認用: `-simulateBlocks <playing|paused|cleared|gameover>`（#463）。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-simulateBlocks"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            // 反射神経を使うゲームなので、画面が引っ込んだ瞬間に必ず止める
            // （基盤規約「バックグラウンド移行時は即一時停止」）。
            guard phase != .active else { return }
            model.pause()
            // 背面に回ったら「止めたのは確認ダイアログだ」という記憶は捨てる。
            // 残すと、戻ってきてダイアログを閉じた瞬間に球が動き出し、上の規約に反する
            // （発射前から開いた場合は元から記憶していないので、揃えて止めたままにする）。
            pausedForNewGameConfirm = false
        }
        .rewardedRescueAlerts(
            continueRescue,
            notEarned: "コンティニューできませんでした",
            unavailable: RewardUnavailableAlert(
                title: "コンティニューできませんでした",
                message: "広告を見ているあいだに新しいゲームが始まったため、コンティニューできませんでした。"
            )
        )
        .confirmationDialog(
            "はじめからやり直しますか？",
            isPresented: $showConfirmNewGame,
            titleVisibility: .visible
        ) {
            Button("終了してはじめから", role: .destructive) {
                pausedForNewGameConfirm = false
                model.newGame()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("途中で終了すると今のスコアとステージが失われます。")
        }
        .onChange(of: showConfirmNewGame) { _, isPresented in
            // キャンセルボタンを経由せず閉じた場合（iPad のポップオーバーで外側をタップ等）も
            // 取りこぼさないよう、閉じたことそのものを再開の合図にする。
            guard !isPresented, pausedForNewGameConfirm else { return }
            pausedForNewGameConfirm = false
            model.resume()
        }
    }

    /// 進行中は確認を挟んでからやり直す（#515）。
    ///
    /// 反射神経を使うゲームなので、迷っているあいだに落球しないよう球を止めてから訊く
    /// （`.howToPlay` を開いたときと同じ扱い）。
    private func startNewGame() {
        guard model.hasProgressToLose else {
            model.newGame()
            return
        }
        if model.phase == .playing {
            model.pause()
            pausedForNewGameConfirm = true
        }
        showConfirmNewGame = true
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("スコア")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Text("\(model.score)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text("ステージ \(model.stageNumber) / \(BlocksRules.stageCount)")
                    .themeCaption(12)
                    .foregroundStyle(Theme.inkSub)
                livesView
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var livesView: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(0, model.lives), id: \.self) { _ in
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.coral)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("残機 \(model.lives)")
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
        // 決着後は止めるものが無い。
        .disabled(model.phase.isFinished || model.phase == .stageCleared)
    }

    // MARK: - プレイフィールド

    private var playfield: some View {
        GeometryReader { geo in
            ZStack {
                // 操作はすべて下の透明レイヤーの `DragGesture` で受ける。SpriteView 自身に
                // 当たり判定を残すと、機種によってはドラッグが SKView に吸われる。
                SpriteView(scene: scene, preferredFramesPerSecond: 60)
                    .allowsHitTesting(false)
                    // 描いたら止めてよいか見直す。画面を開き直して SKView が作り直された
                    // ときも、次の 1 フレームでここに戻ってくる（#522）。
                    .onAppear { scene.onFrameRendered = { syncRenderLoop() } }
                    .onChange(of: model.phase) { _, _ in syncRenderLoop() }
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(paddleGesture(width: geo.size.width))
                overlay
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            // 一時停止は右上のヘッダーではなく、フィールドの右下に浮かせる
            // （会長QA「右上は片手操作で押せない」）。親指の自然なリーチに合わせる。
            .overlay(alignment: .bottomTrailing) {
                pauseButton.padding(10)
            }
        }
        // シーンは `.aspectFit` なので、枠の縦横比をフィールドと必ず一致させる。
        // ずれると左右に余白が出て、タップ位置とパドルの対応も狂う。
        .aspectRatio(BlocksField.Metrics.width / BlocksField.Metrics.height, contentMode: .fit)
    }

    /// 描画ループを局面に合わせる（#522）。
    ///
    /// 一時停止・結果オーバーレイ中は中身が動かないので、60fps を回し続けるのは電池を使うだけ。
    /// 遊び方シートで止めた場合（#510）も `paused` になるのでここに揃う。
    ///
    /// **止めるのは `SKView` で、`SpriteView` の引数ではない**。`isPaused` も
    /// `preferredFramesPerSecond` も生成時にしか効かず、あとから値を変えても伝わらない
    /// （実測: 止まっているあいだ 1fps に落とすと、**再開しても 1fps のまま**だった）。
    /// `SKScene.isPaused` のほうは SpriteView が毎フレーム上書きするので、これも使えない。
    ///
    /// 呼ぶのは局面が変わったときと、1 フレーム描き終えたとき。後者が要るのは、
    /// **一度も描かないうちに止めると盤が出ないまま暗い矩形になる**ため
    /// （`-simulateBlocks paused` で実測。ブロックもパドルも消えた）。
    private func syncRenderLoop() {
        scene.view?.isPaused = !model.phase.needsAnimationFrames
    }

    private func paddleGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                movePaddle(toViewX: value.location.x, width: width)
            }
            .onEnded { value in
                movePaddle(toViewX: value.location.x, width: width)
                // タップ（= 距離 0 のドラッグ）でも発射できる。
                model.launch()
            }
    }

    private func movePaddle(toViewX x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        model.movePaddle(to: Double(x / width) * BlocksField.Metrics.width)
    }

    // MARK: - オーバーレイ

    @ViewBuilder
    private var overlay: some View {
        switch model.phase {
        case .ready:
            readyOverlay
        case .playing:
            EmptyView()
        case .paused:
            pausedOverlay
        case .stageCleared:
            panel(title: "ステージ \(model.stageNumber) クリア！") {
                Button {
                    model.advanceToNextStage()
                } label: {
                    Label("次のステージへ", systemImage: "arrow.forward.circle.fill")
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Fill.coral)
            }
        case .gameOver:
            panel(title: "ゲームオーバー") {
                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
                if !model.continueUsed {
                    continueButton
                }
                restartButton
            }
        case .allCleared:
            panel(title: "全ステージクリア！") {
                RecordLabel(model.recordResult, textColor: .white.opacity(0.85))
                restartButton
            }
        }
    }

    /// 発射前。操作を邪魔しないよう**タップを透過させる**（そのままパドルを動かして発射できる）。
    private var readyOverlay: some View {
        VStack {
            Spacer()
            Label("タップで発射", systemImage: "hand.tap.fill")
                .themeCaption(13)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.35)))
                .padding(.bottom, 46)
        }
        .allowsHitTesting(false)
    }

    private var pausedOverlay: some View {
        panel(title: "一時停止") {
            Toggle(isOn: Binding(
                get: { model.isSlowMode },
                set: { model.setSlowMode($0) }
            )) {
                Text("ゆっくりモード")
                    .themeBody(15)
                    .foregroundStyle(.white)
            }
            .tint(Theme.Fill.coral)
            .padding(.horizontal, 24)

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

    private var continueButton: some View {
        Button {
            // どの局へのコンティニューかを広告前に控える。ロード中に「はじめから」で
            // 盤が作り直されたら適用せず知らせる（ソリティアの補充と同じ契約。#509）。
            let run = model.fieldGeneration
            continueRescue.request(
                services, gameID: BlocksModel.gameID, purpose: .continue,
                guardedBy: .checkedByGrant
            ) {
                model.continueAfterAd(forRun: run)
            }
        } label: {
            Label("広告を見てコンティニュー", systemImage: "play.rectangle.fill")
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Fill.coral)
        .disabled(continueRescue.isWatching)
    }

    /// 一時停止中とリザルトで共用する。前者は進行が残っているので確認を挟み、
    /// 後者は `hasProgressToLose` が false なのでこれまでどおり即やり直す。
    private var restartButton: some View {
        Button("はじめから") { startNewGame() }
            .buttonStyle(.bordered)
            .tint(.white)
    }

    private func panel<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.6))
            VStack(spacing: 12) {
                Text(title).font(.title3.bold()).foregroundStyle(.white)
                content()
            }
            .padding(20)
        }
    }

    /// レコメンドカードの枠。**カードの有無で高さが動かない**ようひな形で確保する（#148）。
    private var recommendationArea: some View {
        ZStack(alignment: .top) {
            RecommendationCard.heightPlaceholder
            RecommendationSlot(services: services, isFinished: model.phase.isFinished)
        }
    }
}
