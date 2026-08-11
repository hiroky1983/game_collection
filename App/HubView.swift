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
    @State private var showTrackingConsent = false
    @State private var pendingTrackingRequest = false
    @State private var gameEnteredAt: Date?

    /// 「遊んだ」とみなす最短の滞在時間。開いてすぐ戻っただけのときに ATT の事前説明を出さないための下限。
    private static let minimumPlaySeconds: TimeInterval = 30

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
            // ゲームを一定時間遊んでからハブに戻ってきたタイミングで、ATT の事前説明を1回だけ出す。
            // 設定シートと同じビューに .sheet を2つ重ねないよう、こちらは NavigationStack の中身に付ける。
            .onChange(of: path) { oldPath, newPath in
                if oldPath.isEmpty, !newPath.isEmpty {
                    gameEnteredAt = Date()
                    return
                }
                guard !oldPath.isEmpty, newPath.isEmpty else { return }
                let played = gameEnteredAt.map { Date().timeIntervalSince($0) >= Self.minimumPlaySeconds } ?? false
                gameEnteredAt = nil
                // 開いてすぐ戻った（＝遊んでいない）場合は出さない。次に遊び終えたときに回る。
                if played { didFinishGameSession() }
            }
            // システムの ATT ダイアログは説明シートが**閉じ切ってから**出す。
            // 前面にシートが残っている間に要求すると、表示されずに終わることがあるため。
            .sheet(isPresented: $showTrackingConsent, onDismiss: {
                guard pendingTrackingRequest else { return }
                pendingTrackingRequest = false
                Task { await requestTrackingAuthorization() }
            }) {
                TrackingConsentPrompt {
                    TrackingConsentGate.markPrompted()
                    pendingTrackingRequest = true
                    showTrackingConsent = false
                }
                .interactiveDismissDisabled()
            }
            .task {
                #if DEBUG
                // 撮影・動作確認用（DEBUG 限定）。ハブへ戻ってきたのと同じ経路を叩く。
                if ProcessInfo.processInfo.arguments.contains("-simulateReturnToHub") {
                    didFinishGameSession()
                }
                #endif
            }
        }
        .tint(Theme.coral)
        .sheet(isPresented: $showSettings) {
            SettingsView(registry: registry, settings: settings)
                .presentationDetents([.large])
        }
    }

    /// ゲームを1つ遊び終えてハブに戻ったときの処理。
    @MainActor
    private func didFinishGameSession() {
        // 撮影モードでは説明シートも ATT もスクショに被るため出さない（DEBUG のみ有効）。
        guard !AppEnvironment.isScreenshotMode else { return }
        if TrackingConsentGate.shouldPrompt(isUndetermined: isTrackingAuthorizationUndetermined) {
            showTrackingConsent = true
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
