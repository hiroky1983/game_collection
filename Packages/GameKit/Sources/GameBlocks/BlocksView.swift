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
    @State private var showRewardNotEarned = false
    @State private var isContinuing = false
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
                Button { model.newGame() } label: {
                    Label("はじめから", systemImage: "arrow.clockwise")
                }
            }
        }
        .howToPlay(.blocks)
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
            if phase != .active { model.pause() }
        }
        .alert("コンティニューできませんでした", isPresented: $showRewardNotEarned) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("広告を最後まで視聴しなかったか、広告を読み込めませんでした。\nもう一度お試しください。")
        }
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
            pauseButton
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
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(paddleGesture(width: geo.size.width))
                overlay
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        }
        // シーンは `.aspectFit` なので、枠の縦横比をフィールドと必ず一致させる。
        // ずれると左右に余白が出て、タップ位置とパドルの対応も狂う。
        .aspectRatio(BlocksField.Metrics.width / BlocksField.Metrics.height, contentMode: .fit)
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
            // 広告のロード〜表示中の連打で2本目が失敗し、誤ってアラートが出るのを防ぐ。
            guard !isContinuing else { return }
            isContinuing = true
            Task {
                if await services.ads.showRewardedAd() {
                    model.continueAfterAd()
                } else {
                    showRewardNotEarned = true
                }
                isContinuing = false
            }
        } label: {
            Label("広告を見てコンティニュー", systemImage: "play.rectangle.fill")
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Fill.coral)
        .disabled(isContinuing)
    }

    private var restartButton: some View {
        Button("はじめから") { model.newGame() }
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
