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
                    VStack(spacing: 16) {
                        ForEach(Array(settings.visibleModules(from: registry).enumerated()), id: \.element.id) { index, module in
                            NavigationLink(value: module.id) {
                                GameCard(
                                    module: module,
                                    accent: Theme.palette[index % Theme.palette.count],
                                    hasResume: services.snapshots.exists(for: module.id)
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
                // ATT はハブが描画された直後にシステムダイアログを直接出す（Build 6・審査指摘 2.1 対応）。
                // 以前は自前の事前説明シートを挟み「最初のゲームを遊び終えてハブに戻った時点」で
                // 出していたが、(1) ゲームを完了しないレビュアーがダイアログに到達できず審査で
                // 「見つからない」と指摘された、(2) AdMob を収入源とする以上 ATT は避けて通れない、
                // の2点から標準の形（起動直後にシステムダイアログのみ）へ戻した（会長決裁 2026-08-27）。
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
                    services.recommendations?.simulateSuggestion(gameID: args[i + 1])
                }
                // 撮影・動作確認用: 発火条件を通さずに評価リクエストを出す
                // （`-startGame <id> -simulateReviewRequest` でそのゲームのリザルト経路に乗せる）。
                if args.contains("-simulateReviewRequest") {
                    services.review?.simulateRequest()
                }
                #endif
            }
        }
        .tint(Theme.coral)
        .sheet(isPresented: $showSettings) {
            SettingsView(registry: registry, settings: settings, playLog: services.recommendations?.log)
                .presentationDetents([.large])
        }
    }

}

/// ハブのゲームカード。
private struct GameCard: View {
    let module: GameModule
    let accent: Color
    let hasResume: Bool

    var body: some View {
        HStack(spacing: 16) {
            // カラフルなアイコンチップ
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .fill(accent.gradient)
                .frame(width: 60, height: 60)
                .overlay {
                    module.icon
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: accent.opacity(0.4), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(module.title)
                    .font(Theme.title(22))
                    .foregroundStyle(Theme.ink)
                Text(module.description)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSub)
                if hasResume {
                    Text("続きから")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accent.opacity(0.15)))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.inkSub)
        }
        .padding(16)
        .popCard()
    }
}
