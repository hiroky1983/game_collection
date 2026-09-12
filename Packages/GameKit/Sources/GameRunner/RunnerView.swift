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
    /// 15 ステージぶんのベストタイム一覧を開いているか（既定は閉じて省スペースに、#583系）。
    ///
    /// 「ステージとベストタイムは上のセクションでいい。まだゲーム画面が真ん中にあって
    /// 一時停止ボタンが遠い」という会長QA（2026-09-10）を受け、既定は現在のステージの
    /// ベストだけを1行で見せ、15個のチップ一覧は開いたときだけ場所を取るようにした。
    @State private var showsAllBestTimes = false
    @Environment(\.scenePhase) private var scenePhase

    public init(services: GameServices) {
        self.services = services
        let model = RunnerModel(services: services)
        _model = State(initialValue: model)
        _scene = State(initialValue: RunnerScene(model: model))
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
            HStack {
                Spacer(minLength: 0)
                pauseButton
            }
            secondaryInfo
            Spacer(minLength: 0)
            BannerSlot(ads: services.ads)
        }
        .padding()
        .gameChrome(title: "チャリンコおじさん", review: services.review) {
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
            // 撮影・動作確認用: `-simulateRunner <running|paused|failed|cleared|showcase|bird>`（#494）。
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

    /// タイム・スピード・ステージ番号・記録を1枚にまとめた画面上部のセクション。
    ///
    /// 元は「タイム等」のカードと「ベストタイム一覧」のカードが縦に2枚並んでいたが、
    /// 「ステージとベストタイムは上のセクションでいい。まだゲーム画面が真ん中にあって
    /// 一時停止ボタンが遠い」という会長QA（2026-09-10）を受け、1枚に統合して縦の
    /// 占有を減らした——浮いた分だけ `course` が画面の下まで伸び、右下の一時停止ボタンが
    /// 自然と親指の届く位置に来る。
    private var topSummary: some View {
        VStack(spacing: 8) {
            header
            bestTimeSection
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .popCard(corner: Theme.cornerSmall)
    }

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
            speedMeter
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
    }

    /// ペダルの乗り（#569）。
    ///
    /// タイムが操作で動くようになったので、**いま速いのか遅いのか**を走りながら読めるようにする。
    /// 倍率の数字は走行中に読めないので、進み具合と同じ形のゲージにして伸び縮みだけで伝える。
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
            .frame(width: 72, height: 6)
        }
        .padding(.leading, 14)
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
        .disabled(
            model.phase == .falling || model.phase == .failed
                || model.phase == .cleared || model.phase == .allCleared
        )
    }

    /// ステージごとのベストタイム（#494 の「記録」）。
    ///
    /// 既定では現在のステージのベストだけを1行で見せ、15個のチップ一覧はタップして
    /// 開いたときだけ表示する（会長QA「上のセクションを縮めたい」を受けた折りたたみ化）。
    /// 開けば従来どおり「どこまで進んだか」「次にどこを縮めるか」が一目で分かる。
    ///
    /// チップ行の高さは**開閉に関わらず常に確保**する（レコメンドカードのひな形と同じ
    /// 「見えないひな形で高さを固定する」手法）。以前は開いたときだけ高さが増え、
    /// `topSummary` が伸びた分だけ `course`（`GeometryReader` + `aspectRatio(.fit)`）が
    /// 帳尻合わせに縮んでいた——「一時停止ボタンのセクションが固定になってるせいか、
    /// ベストタイムのセクションを出すとプレイ画面が縮む」という会長QA（2026-09-10）どおりの
    /// 症状。チップ行を常時同じ高さで確保しておけば `topSummary` の高さが動かなくなり、
    /// `course` も常に同じ大きさで安定する。
    private var bestTimeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withGameAnimation(.snappy(duration: 0.2)) { showsAllBestTimes.toggle() }
            } label: {
                HStack {
                    Text("ベストタイム")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSub)
                    Spacer(minLength: 0)
                    Text(RunnerAccessibility.bestLabel(seconds: model.bestSecondsForCurrentStage))
                        .themeCaption(12)
                        .foregroundStyle(Theme.inkSub)
                    Image(systemName: showsAllBestTimes ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.inkSub)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                showsAllBestTimes ? "全ステージの記録をとじる" : "全ステージの記録を見る"
            )
            .accessibilityValue(RunnerAccessibility.bestLabel(seconds: model.bestSecondsForCurrentStage))

            ZStack(alignment: .topLeading) {
                // 高さのひな形。常に同じレイアウトで場所を占め続け、当たり判定・読み上げには関わらない。
                stageChipsRow
                    .hidden()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if showsAllBestTimes {
                    stageChipsRow
                        .accessibilityElement(children: .combine)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var stageChipsRow: some View {
        HStack(spacing: 4) {
            ForEach(1...RunnerRules.stageCount, id: \.self) { number in
                stageChip(number)
            }
        }
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

    /// **`GeometryReader` で包んで `.layoutPriority(1)` を付ける**（囲碁の盤 `GoView.board` と同じ組み方）。
    ///
    /// `.frame(maxWidth: .infinity, maxHeight: .infinity)` だけでも幅基準では同じ結果になるが、
    /// `GeometryReader` は常に提案された枠いっぱいに広がる**「伸縮する子」だと `VStack` に
    /// 確実に伝わる**ので、この画面より縦に余裕のある端末（`topSummary` を畳んだ状態など）でも
    /// `course` が優先的に余った縦幅を取り、`BannerSlot` が浮かずに画面下へ収まることを保証できる。
    private var course: some View {
        GeometryReader { _ in
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
        case .falling:
            // 落下・激突の短い演出中（`RunnerScene`）。ミスパネルはこの演出が終わってから出す。
            EmptyView()
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
            // ゆっくりモードの切り替えは設定画面のみに一本化した（#631）。ゲーム内の
            // 一時停止からいつでも切り替えられると、難所の直前で止めてオンにする→通過後に
            // オフへ戻す、を繰り返すだけでベストタイムをいくらでも作り込めてしまい、
            // アクセシビリティの代替手段のはずが難易度調整の抜け道になっていた
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

    /// レコメンドカードの枠。高さの担保は `RecommendationArea`（#148）。
    private var recommendationArea: some View {
        RecommendationArea(services: services, isFinished: model.phase == .allCleared)
    }

    /// 遊び方のヒントとレコメンドは、プレイ中に何度も見るものではないので
    /// `course` の下に小さく残す（会長QA「ゲーム画面を下まで広げたい」）。
    /// どちらも中身が無ければ実質高さ 0（`HowToPlayHint` は2回目以降 `EmptyView`）か
    /// 固定の小さなプレースホルダなので、スクロールにしなくても場所を圧迫しない。
    private var secondaryInfo: some View {
        VStack(spacing: 6) {
            HowToPlayHint(.runner, playLog: services.playLog)
            recommendationArea
        }
    }
}
