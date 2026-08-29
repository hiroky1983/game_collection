import SwiftUI
import Core

/// ハブ画面。登録された GameModule をカードで列挙し、選択で各ゲームを遅延ロード起動する。
/// NavigationStack の土台はこの一覧。各ゲームは push される（→ ゲーム側の「戻る」でここに戻れる）。
struct HubView: View {
    let registry: GameRegistry
    let services: GameServices
    let settings: GameSettings
    @State private var path: [String]
    @State private var showSettings: Bool
    /// 未サインインで実績・ランキングを開こうとしたときの案内（#334）。
    @State private var showGameCenterSignInGuidance = false

    /// ゲーム一覧のグリッド（#119）。iPhone は最小幅 130pt で必ず 2 列になり
    /// （SE 相当の 320pt 幅でも 3 列にはならない）、画面が広い iPad では列が増えて一望性が上がる。
    private static let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    init(
        registry: GameRegistry,
        services: GameServices,
        settings: GameSettings,
        initialGameID: String? = nil,
        showsSettingsInitially: Bool = false
    ) {
        self.registry = registry
        self.services = services
        self.settings = settings
        _path = State(initialValue: initialGameID.map { [$0] } ?? [])
        _showSettings = State(initialValue: showsSettingsInitially)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: 12) {
                        ForEach(Array(settings.visibleModules(from: registry).enumerated()), id: \.element.id) { index, module in
                            NavigationLink(value: module.id) {
                                GameCard(
                                    module: module,
                                    accent: Theme.palette[index % Theme.palette.count],
                                    hasResume: services.snapshots.exists(for: module.id),
                                    record: services.playLog?.summaryLine(gameID: module.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.pad)
                }
                BannerSlot(ads: services.ads)
            }
            .popBackground()
            .navigationTitle("あそびば")
            .toolbar {
                // 実績・ランキング（#334）。歯車より左に置き、既存の設定ボタンの位置は動かさない。
                ToolbarItem(placement: .primaryAction) {
                    Button { openGameCenter() } label: {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .accessibilityLabel("実績・ランキング")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let module = registry.module(id: id) {
                    module.makeView(services: services)
                }
            }
            // ゲーム画面から離れたことを解析へ伝える（#158）。次に開いたときを新しい
            // 1 プレイとして数え直すための境界で、ここが唯一の発火点。
            // レコメンドでの差し替え（空 path を経由する）も「離れた」で正しい。
            .onChange(of: path) { oldPath, newPath in
                if !oldPath.isEmpty, newPath.isEmpty, let leftGameID = oldPath.last {
                    services.gameDidLeave(gameID: leftGameID)
                }
            }
            // リザルトのレコメンドカードがタップされたら、そのゲームへ差し替えて遷移する。
            .onChange(of: services.recommendations?.requestedGameID) { _, requested in
                guard let id = requested else { return }
                services.recommendations?.requestedGameID = nil
                // NavigationStack は表示中の遷移先を1手で差し替えると描画が壊れる（画面が真っ白になる）。
                // いったん根まで戻し、次の runloop で積み直す。
                path = []
                DispatchQueue.main.async { path = [id] }
            }
            .task {
                // ATT はハブが描画された直後にシステムダイアログを直接出す（v1.1.0 Build 6 と同じ変更）。
                // 以前は自前の事前説明シートを挟み「最初のゲームを遊び終えてハブに戻った時点」で
                // 出していたが、(1) ゲームを完了しないレビュアーがダイアログに到達できず審査で
                // 「見つからない」と指摘された（Guideline 2.1）、(2) AdMob を収入源とする以上
                // ATT は避けて通れない、の2点から標準の形へ戻した（会長決裁 2026-08-27）。
                // ATT が既決の環境や、システム設定でトラッキング要求が無効の環境（新品のシミュレータや
                // 審査機がこれに当たる）では、requestTrackingAuthorization は何も表示せず即座に返る。
                // 撮影モードではスクショにダイアログが被るため出さない（DEBUG のみ有効）。
                if !AppEnvironment.isScreenshotMode {
                    try? await Task.sleep(for: .milliseconds(600))
                    await requestTrackingAuthorization()
                }
                #if DEBUG
                // 撮影・動作確認用: 提示条件を通さずにレコメンドカードを出す（`-simulateRecommendation <gameID>`）。
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-simulateRecommendation"), i + 1 < args.count {
                    // 久しぶり枠（#335）の見出しは `-simulateRecommendationDays <日数>` を併せて渡す。
                    let reason: RecommendationReason = args
                        .firstIndex(of: "-simulateRecommendationDays")
                        .flatMap { j in j + 1 < args.count ? Int(args[j + 1]) : nil }
                        .map { .revisit(days: $0) } ?? .unplayed
                    services.recommendations?.simulateSuggestion(gameID: args[i + 1], reason: reason)
                }
                // 撮影・動作確認用: 発火条件を通さずに評価リクエストを出す
                // （`-startGame <id> -simulateReviewRequest` でそのゲームのリザルト経路に乗せる）。
                if args.contains("-simulateReviewRequest") {
                    services.review?.simulateRequest()
                }
                // 動作確認用: ツールバーの「実績・ランキング」を押したのと同じ分岐を通す
                // （`-simulateGameCenterEntry`）。シミュレータは Game Center 未サインインのため、
                // 実際に確認できるのは案内アラートの側になる。
                if args.contains("-simulateGameCenterEntry") {
                    openGameCenter()
                }
                // 動作確認用: 触覚・効果音を発火条件を通さずに 1 種ずつ鳴らす（`-simulateFeedback`）。
                // 効果音が音声セッションをどう設定したかをシミュレータで確認するために使う
                // （ゲーム内の発火点はすべてタップ起点で、非対話の確認では叩けないため）。
                if args.contains("-simulateFeedback") {
                    for style: FeedbackImpact in [.light, .medium, .rigid] {
                        services.feedback.impact(style)
                    }
                    for type: FeedbackNotice in [.success, .warning, .error] {
                        services.feedback.notify(type)
                    }
                }
                #endif
            }
        }
        .tint(Theme.coral)
        .sheet(isPresented: $showSettings) {
            SettingsView(registry: registry, settings: settings, playLog: services.playLog)
                .presentationDetents([.large])
        }
        .alert("Game Center にサインインしていません", isPresented: $showGameCenterSignInGuidance) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("iPhone の「設定」＞「Game Center」からサインインすると、実績と世界のランキングを見られます。サインインしなくても、あそびはすべてそのまま遊べます。")
        }
    }

    /// ツールバーの「実績・ランキング」。サインイン済みなら Game Center を開き、
    /// 未サインインのときだけサインインを促す（#334 の受け入れ条件）。
    private func openGameCenter() {
        if GameCenterEntry.open() == .needsSignInGuidance {
            showGameCenterSignInGuidance = true
        }
    }
}

/// ハブのゲームカード（2列グリッド・#119）。
///
/// 全 10 本を 1 画面に収めるため縦に積む情報は 3 段までに絞っている
/// （アイコン + ゲーム名 + 1 行）。「続きから」はカード右上のバッジに移し、
/// 記録（#115）の行を潰さずに両方見えるようにした。
private struct GameCard: View {
    let module: GameModule
    let accent: Color
    let hasResume: Bool
    /// プレイ記録の 1 行（#115）。まだ記録が無ければ nil で、その場合はゲームの説明を出す。
    let record: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                // カラフルなアイコンチップ
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .fill(accent.gradient)
                    .frame(width: 44, height: 44)
                    .overlay {
                        module.icon
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: accent.opacity(0.4), radius: 5, y: 3)

                Spacer(minLength: 0)

                if hasResume {
                    Text("続きから")
                        .themeCaption(11)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accent.opacity(0.15)))
                        .fixedSize()
                }
            }

            Text(module.title)
                .themeTitle(18)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // 記録が無いうちはゲームの説明を出す（初見の手掛かり）。遊んだあとは記録に入れ替わる。
            Group {
                if let record {
                    Label(record, systemImage: "chart.bar.fill")
                        .foregroundStyle(Theme.inkSub)
                } else {
                    Text(module.description)
                        .foregroundStyle(Theme.inkSub)
                }
            }
            .themeCaption(11)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .popCard()
        // 「続きから」バッジを右上（＝先頭行）に置いたため、既定の読み上げ順ではゲーム名より先に
        // 読まれてしまう。カードを 1 要素にまとめ、必ずゲーム名から読ませる。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [module.title, record ?? module.description]
        if hasResume { parts.append("続きから") }
        return parts.joined(separator: "、")
    }
}
