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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    public init(services: GameServices) {
        self.services = services
        let model = RunnerModel(services: services)
        _model = State(initialValue: model)
        _scene = State(initialValue: RunnerScene(model: model))
    }

    public var body: some View {
        VStack(spacing: 14) {
            header
            course
            bestTimeStrip
            HowToPlayHint(.runner, playLog: services.playLog)
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
                Text("チャリンコおじさん")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.newGame() } label: {
                    Label("はじめから", systemImage: "arrow.clockwise")
                }
            }
        }
        .howToPlay(.runner, onPresent: {
            // 読んでいる間にミスしないよう止める。走り出す前（.ready）は動くものが無いので
            // 止めない（初見の人が遊ぶ前に開く一番多い経路で、余計な「再開」を挟まない）。
            if model.phase == .running { model.pause() }
        })
        .onAppear {
            // 設定画面で切り替えられていたら取り込む（書き手は設定画面とポーズ画面の 2 か所）。
            model.syncSlowModeFromPreference()
            #if DEBUG
            // 撮影・動作確認用: `-simulateRunner <running|paused|failed|cleared>`（#494）。
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-simulateRunner"), i + 1 < args.count {
                model.applyDebugScenario(args[i + 1])
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

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("タイム")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Text(timeText(model.elapsed))
                    .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityElement()
            .accessibilityLabel(RunnerAccessibility.timeLabel(seconds: Int(model.elapsed)))
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(RunnerAccessibility.stageLabel(
                    number: model.stageNumber, total: RunnerRules.stageCount
                ))
                .themeCaption(12)
                .foregroundStyle(Theme.inkSub)
                progressBar
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Fill.coral.opacity(0.2))
                Capsule().fill(Theme.Fill.coral)
                    .frame(width: geo.size.width * model.field.progress)
            }
        }
        .frame(width: 96, height: 6)
        .accessibilityElement()
        .accessibilityLabel(RunnerAccessibility.progressLabel(model.field.progress))
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
        .disabled(model.phase == .failed || model.phase == .cleared || model.phase == .allCleared)
    }

    /// ステージごとのベストタイム（#494 の「記録」）。
    ///
    /// 横長のコースは縦持ちの画面では帯にしかならないので、その下に記録を置いて
    /// 「どこまで進んだか」「次にどこを縮めるか」が一目で分かるようにする。
    /// 15 個を横に並べ、いま挑んでいるステージだけ色を変える。
    private var bestTimeStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ベストタイム")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                Spacer(minLength: 0)
                Text(RunnerAccessibility.bestLabel(seconds: model.bestSecondsForCurrentStage))
                    .themeCaption(12)
                    .foregroundStyle(Theme.inkSub)
            }
            HStack(spacing: 4) {
                ForEach(1...RunnerRules.stageCount, id: \.self) { number in
                    stageChip(number)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .combine)
    }

    private func stageChip(_ number: Int) -> some View {
        let best = model.best(forStage: number)
        let isCurrent = number == model.stageNumber
        return VStack(spacing: 1) {
            // 数値の桁区切りが入らないよう verbatim で出す（#494 時点の既知の落とし穴）。
            Text(verbatim: "\(number)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(isCurrent ? Theme.onAccent : Theme.inkSub)
            Text(best.map { "\($0)" } ?? "–")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isCurrent ? Theme.onAccent : Theme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isCurrent ? Theme.Fill.coral : Theme.Fill.coral.opacity(0.12))
        )
        .accessibilityLabel(
            "ステージ \(number) " + RunnerAccessibility.bestLabel(seconds: best)
        )
    }

    // MARK: - コース

    private var course: some View {
        ZStack {
            // 操作はすべて下の透明レイヤーで受ける。SpriteView 自身に当たり判定を残すと、
            // 機種によってはタップが SKView に吸われる。
            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
                .gesture(jumpGesture)
            overlay
        }
        // シーンは `.aspectFit` なので、枠の縦横比をコースと必ず一致させる。
        // ずれると余白が出て、見えている範囲と当たり判定の対応も狂う。
        .aspectRatio(RunnerField.Metrics.width / RunnerField.Metrics.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(RunnerAccessibility.resultLabel(
            phase: model.phase, stageNumber: model.stageNumber
        ))
        .accessibilityHint("ダブルタップでジャンプ")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.press(); model.release() }
        // 一時停止は右上のヘッダーではなく、コースの右下に浮かせる（会長QA「右上は片手操作で押せない」）。
        // 親指の自然なリーチに合わせる。`.accessibilityElement()` の**あとに**重ねることで、
        // コース本体の1個の要素（ジャンプ）に飲み込まれず、独立した VoiceOver 要素のまま残る。
        .overlay(alignment: .bottomTrailing) {
            pauseButton.padding(10)
        }
    }

    /// 押している間だけ高く跳べるので、押し下げと離しの両方を拾う。
    private var jumpGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in model.press() }
            .onEnded { _ in model.release() }
    }

    // MARK: - オーバーレイ

    @ViewBuilder
    private var overlay: some View {
        switch model.phase {
        case .ready:
            readyOverlay
        case .running:
            EmptyView()
        case .paused:
            pausedOverlay
        case .failed:
            panel(title: "ミス！") {
                if model.canResumeFromCheckpoint { resumeButton }
                Button {
                    model.retryStage()
                } label: {
                    Label("もう一度", systemImage: "arrow.clockwise")
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Fill.coral)
            }
        case .cleared:
            panel(title: "ステージ \(model.stageNumber) クリア！") {
                clearedDetail
                Button {
                    model.advanceToNextStage()
                } label: {
                    Label("次のステージへ", systemImage: "arrow.forward.circle.fill")
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Fill.coral)
                replayButton
            }
        case .allCleared:
            panel(title: "全ステージクリア！") {
                clearedDetail
                replayButton
                restartButton
            }
        }
    }

    /// クリア表示のタイム 2 行（今回とベスト）。
    private var clearedDetail: some View {
        VStack(spacing: 4) {
            Text("タイム \(timeText(model.elapsed))")
                .themeBody(15)
                .foregroundStyle(.white)
            Text(RunnerAccessibility.bestLabel(seconds: model.bestSecondsForCurrentStage))
                .themeCaption(13)
                .foregroundStyle(.white.opacity(0.85))
            if model.didSetBestTime {
                // 共通の `RecordLabel` はここでは出さない。あちらが出す「自己ベスト N」は
                // このゲームでは**到達ステージ数**（ハブの 1 行で使う指標）で、同じ枠に
                // 並ぶタイムと取り違えられる。この画面で意味があるのはタイムのほう。
                Text("ベストタイム更新！")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.Fill.coral))
            }
        }
    }

    /// 走り出す前。操作を邪魔しないよう**タップを透過させる**（そのまま画面を触れば走り出す）。
    private var readyOverlay: some View {
        VStack {
            Spacer()
            Label("タップでスタート", systemImage: "hand.tap.fill")
                .themeCaption(13)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.35)))
                .padding(.bottom, 20)
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

    /// `0:00` 形式。**秒だけの表示にしない**（ステージによっては 1 分を超える）。
    private func timeText(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    /// レコメンドカードの枠。**カードの有無で高さが動かない**ようひな形で確保する（#148）。
    private var recommendationArea: some View {
        ZStack(alignment: .top) {
            RecommendationCard.heightPlaceholder
            RecommendationSlot(services: services, isFinished: model.phase == .allCleared)
        }
    }
}
