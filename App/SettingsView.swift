import SafariServices
import SwiftUI
import Core

struct SettingsView: View {
    let registry: GameRegistry
    let settings: GameSettings
    @Environment(\.dismiss) private var dismiss
    @State private var legalURL: IdentifiableURL?

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: アプリ
                Section("アプリ") {
                    LabeledContent("バージョン", value: appVersion)
                }

                // MARK: あそび
                Section {
                    ForEach(settings.orderedIDs, id: \.self) { id in
                        if let module = registry.module(id: id) {
                            gameRow(module: module, id: id)
                        }
                    }
                    .onMove { settings.move(from: $0, to: $1) }
                } header: {
                    Text("あそび")
                } footer: {
                    Text("ドラッグで並べ替え、トグルで表示 / 非表示を切り替えられます。")
                }

                // MARK: 規約
                Section("規約") {
                    Button {
                        legalURL = IdentifiableURL(url: URL(string: "https://web-murex-sigma-62.vercel.app/terms")!)
                    } label: {
                        Label("利用規約", systemImage: "doc.text")
                    }
                    .foregroundStyle(Theme.ink)
                    Button {
                        legalURL = IdentifiableURL(url: URL(string: "https://web-murex-sigma-62.vercel.app/privacy")!)
                    } label: {
                        Label("プライバシーポリシー", systemImage: "hand.raised")
                    }
                    .foregroundStyle(Theme.ink)
                }

                // MARK: その他
                Section("その他") {
                    Button {
                        // アプリがリリースされたら App Store の評価ページへ
                        // SKStoreReviewController.requestReview() を使う想定
                    } label: {
                        Label("アプリを評価する", systemImage: "star")
                    }
                    .foregroundStyle(Theme.ink)

                    ShareLink(
                        item: URL(string: "https://apps.apple.com")!,
                        subject: Text("あそびばアプリ"),
                        message: Text("このゲームアプリ面白いよ！")
                    ) {
                        Label("アプリをシェア", systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("設定")
            .sheet(item: $legalURL) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func gameRow(module: GameModule, id: String) -> some View {
        let isVisible = !settings.hiddenIDs.contains(id)
        let idx = settings.orderedIDs.firstIndex(of: id) ?? 0
        let accent = Theme.palette[idx % Theme.palette.count]

        return Toggle(isOn: Binding(
            get: { isVisible },
            set: { _ in settings.toggleHidden(id) }
        )) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.gradient)
                    .frame(width: 32, height: 32)
                    .overlay {
                        module.icon
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                Text(module.title)
                    .font(Theme.body(16))
                    .foregroundStyle(isVisible ? Theme.ink : Theme.inkSub)
            }
        }
        .tint(Theme.coral)
    }
}

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
