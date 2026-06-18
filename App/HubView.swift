import SwiftUI
import Core

/// ハブ画面。登録された GameModule をカードで列挙し、選択で各ゲームを遅延ロード起動する。
/// NavigationStack の土台はこの一覧。各ゲームは push される（→ ゲーム側の「戻る」でここに戻れる）。
struct HubView: View {
    let registry: GameRegistry
    let services: GameServices
    let settings: GameSettings
    @State private var path: [String]
    @State private var showSettings = false

    init(registry: GameRegistry, services: GameServices, settings: GameSettings, initialGameID: String? = nil) {
        self.registry = registry
        self.services = services
        self.settings = settings
        _path = State(initialValue: initialGameID.map { [$0] } ?? [])
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
        }
        .tint(Theme.coral)
        .sheet(isPresented: $showSettings) {
            SettingsView(registry: registry, settings: settings)
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
