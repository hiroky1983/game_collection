import SafariServices
import StoreKit
import SwiftUI
import Core

struct SettingsView: View {
    let registry: GameRegistry
    let settings: GameSettings
    /// プレイ記録。注入されないとき（プレビュー等）は消去の導線を出さない。
    var playLog: PlayLog?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var legalURL: IdentifiableURL?
    @State private var showClearPlayLogConfirm = false

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

                // MARK: フィードバック
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.hapticsEnabled },
                        set: { settings.hapticsEnabled = $0 }
                    )) {
                        Label("触覚フィードバック", systemImage: "iphone.radiowaves.left.and.right")
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.coral)

                    Toggle(isOn: Binding(
                        get: { settings.soundEnabled },
                        set: { settings.soundEnabled = $0 }
                    )) {
                        Label("効果音", systemImage: "speaker.wave.2")
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.coral)
                } header: {
                    Text("フィードバック")
                } footer: {
                    Text("駒を置く・マスを開く・勝敗が決まるといった場面で、端末を軽く振動させたり短い効果音を鳴らしたりします。効果音は本体を消音（サイレント）にしているときは鳴らず、ほかのアプリで再生中の音楽も止めません。")
                }

                // MARK: ヒント
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.hintsEnabled },
                        set: { settings.hintsEnabled = $0 }
                    )) {
                        Label("ヒント表示", systemImage: "lightbulb")
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.coral)
                } header: {
                    Text("ヒント")
                } footer: {
                    Text("大富豪で、いま出せるカードを枠の色で目立たせ、出せない組を選んだときはその理由を1行で表示します。オフにすると何も表示しません。")
                }

                // MARK: あそびやすさ
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.blocksSlowModeEnabled },
                        set: { settings.blocksSlowModeEnabled = $0 }
                    )) {
                        Label("ゆっくりモード", systemImage: "tortoise")
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.coral)
                } header: {
                    Text("あそびやすさ")
                } footer: {
                    Text("ブロック崩しの球の速さを落とします。ゲーム中の一時停止画面からも切り替えられます。")
                }

                // MARK: 解析
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.analyticsEnabled },
                        set: { settings.analyticsEnabled = $0 }
                    )) {
                        Label("利用状況の送信", systemImage: "chart.bar.doc.horizontal")
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.coral)
                } header: {
                    Text("解析")
                } footer: {
                    Text("どのあそびがどれくらい遊ばれているかを知るために、あそびの名前・勝敗・かかった時間を送ります。スコアや盤面、名前や連絡先のような個人を特定できる情報は送りません。オフにすると、これらに加えて起動回数などの自動計測もまとめて送信を止めます。")
                }

                // MARK: プレイ記録
                if let playLog {
                    Section {
                        Button(role: .destructive) {
                            showClearPlayLogConfirm = true
                        } label: {
                            Label("プレイ記録を消去", systemImage: "trash")
                        }
                        .confirmationDialog(
                            "プレイ記録を消去しますか？",
                            isPresented: $showClearPlayLogConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("消去する", role: .destructive) { playLog.clear() }
                            Button("キャンセル", role: .cancel) {}
                        } message: {
                            Text("ベストスコア・最短タイム・勝敗と連勝の記録、遊んだ回数・勝った回数、おすすめや評価のお願い・遊び方ガイドの表示履歴を消します。元に戻せません。")
                        }
                    } header: {
                        Text("プレイ記録")
                    } footer: {
                        Text("あそびごとのベストスコア・最短タイム・勝敗と連勝を、遊んだ回数・勝った回数・遊んだあそびの種類・おすすめと評価のお願い・遊び方ガイドの表示履歴とあわせてこの端末に保存しています（送信はしません）。盤面や棋譜は残していません。")
                    }
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
                        requestReview()
                    } label: {
                        Label("アプリを評価する", systemImage: "star")
                    }
                    .foregroundStyle(Theme.ink)

                    ShareLink(
                        item: URL(string: "https://apps.apple.com/jp/app/id6781719499")!,
                        subject: Text("あそびばアプリ"),
                        message: Text("このゲームアプリ面白いよ！")
                    ) {
                        Label("アプリをシェア", systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
            .environment(\.editMode, .constant(.active))
            // ゲーム画面からも切り替えられる設定（ゆっくりモード・#463）があるため、
            // 開くたびに保存値を読み直す。
            .onAppear { settings.refreshFromDefaults() }
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
        let accent = Theme.Fill.palette[idx % Theme.Fill.palette.count]

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
                            .foregroundStyle(Theme.onAccent)
                    }
                Text(module.title)
                    .themeBody(16)
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
