import SafariServices
import SwiftUI
import Core

struct SettingsView: View {
    let registry: GameRegistry
    let settings: GameSettings
    /// プレイ記録。注入されないとき（プレビュー等）は消去の導線を出さない。
    var playLog: PlayLog?
    /// 消去の完了を伝える触覚（#2936）。注入されないとき（プレビュー等）は何もしない。
    var feedback: FeedbackService = NoopFeedbackService()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var legalURL: IdentifiableURL?
    @State private var showClearPlayLogConfirm = false
    @State private var showResetOrderConfirm = false
    /// 通知の許諾状態（#1603）。開いたとき・設定アプリから戻ったときに読む。未確認の間は表示を変えない。
    @State private var notificationAuthorization: ReminderAuthorization?

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    private static let legalBaseURL = "https://web-murex-sigma-62.vercel.app"

    /// 規約・プライバシーポリシーの URL。表示言語（#2109・端末の言語ではなくアプリ内で選んだ言語）が
    /// English なら英語ページ（`/en/...`）、日本語ならそのまま（#2170）。
    private func legalPageURL(path: String) -> URL {
        let prefix = AppLanguageStore.shared.language == .english ? "/en" : ""
        return URL(string: "\(Self.legalBaseURL)\(prefix)/\(path)")!
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: アプリ
                Section(tr("アプリ")) {
                    LabeledContent(tr("バージョン"), value: appVersion)
                }

                // MARK: 言語（#2109）
                Section {
                    languagePicker
                } header: {
                    Text(tr("言語"))
                } footer: {
                    Text(tr("はじめは端末の言語に合わせています。切り替えるとすぐに反映され、アプリの再起動はいりません。"))
                }

                // MARK: あそび
                Section {
                    ForEach(settings.orderedIDs, id: \.self) { id in
                        if let module = registry.module(id: id) {
                            gameRow(module: module, id: id)
                        }
                    }
                    .onMove { settings.move(from: $0, to: $1) }
                    Button {
                        showResetOrderConfirm = true
                    } label: {
                        Label(tr("ハブの並びを初期に戻す"), systemImage: "arrow.counterclockwise")
                    }
                    .foregroundStyle(Theme.ink)
                    .dialogs { anchor in
                        anchor.confirmationDialog(
                            tr("ハブの並びを初期に戻しますか？"),
                            isPresented: $showResetOrderConfirm,
                            titleVisibility: .visible
                        ) {
                            Button(tr("初期に戻す"), role: .destructive) {
                                settings.resetToDefault()
                                AccessibilityNotification.Announcement(tr("ハブの並びを初期に戻しました")).post()
                            }
                            Button(tr("キャンセル"), role: .cancel) {}
                        } message: {
                            Text(tr("並べ替えた順番を、アプリ初期の並びに戻します。非表示にしたあそびもすべて表示に戻ります。"))
                        }
                    }
                } header: {
                    Text(tr("あそび"))
                } footer: {
                    Text(tr("ドラッグで並べ替え、トグルで表示 / 非表示を切り替えられます。"))
                }

                // MARK: フィードバック
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.hapticsEnabled },
                        set: { settings.hapticsEnabled = $0 }
                    )) {
                        Label(tr("触覚フィードバック"), systemImage: "iphone.radiowaves.left.and.right")
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.coral) // accent-text-ok: トグルのトラック（面）

                    Toggle(isOn: Binding(
                        get: { settings.soundEnabled },
                        set: { settings.soundEnabled = $0 }
                    )) {
                        Label(tr("効果音"), systemImage: "speaker.wave.2")
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.coral) // accent-text-ok: トグルのトラック（面）

                    if settings.soundEnabled {
                        Picker(selection: Binding(
                            get: { settings.soundVolume },
                            set: { settings.soundVolume = $0 }
                        )) {
                            Text(tr("小")).tag(SoundVolume.small)
                            Text(tr("中")).tag(SoundVolume.medium)
                            Text(tr("大")).tag(SoundVolume.large)
                        } label: {
                            Label(tr("効果音の音量"), systemImage: "speaker.wave.3")
                                .foregroundStyle(Theme.ink)
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text(tr("フィードバック"))
                } footer: {
                    Text(tr("駒を置く・マスを開く・勝敗が決まるといった場面で、端末を軽く振動させたり短い効果音を鳴らしたりします。効果音は本体を消音（サイレント）にしているときは鳴らず、ほかのアプリで再生中の音楽も止めません。"))
                }

                // MARK: ヒント
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.hintsEnabled },
                        set: { settings.hintsEnabled = $0 }
                    )) {
                        Label(tr("ヒント表示"), systemImage: "lightbulb")
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.coral) // accent-text-ok: トグルのトラック（面）
                } header: {
                    Text(tr("ヒント"))
                } footer: {
                    Text(tr("大富豪では、いま出せるカードを枠の色で目立たせ、出せない組を選んだときはその理由を1行で表示します。花札こいこいでは、取れる札を目立たせます。オフにすると何も表示しません。"))
                }

                // MARK: あそびやすさ
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.slowModeEnabled },
                        set: { settings.slowModeEnabled = $0 }
                    )) {
                        Label(tr("ゆっくりモード"), systemImage: "tortoise")
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.coral) // accent-text-ok: トグルのトラック（面）
                } header: {
                    Text(tr("あそびやすさ"))
                } footer: {
                    Text(tr("ブロック崩しの球と、チャリンコおじさんの進みを遅くします。切り替えると、両方の進行中のデータは消えます。"))
                }

                // MARK: 通知
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { settings.notificationsEnabled = $0 }
                    )) {
                        Label(tr("お知らせ"), systemImage: "bell")
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.coral) // accent-text-ok: トグルのトラック（面）
                    if notificationAuthorization == .denied {
                        Text(tr("この端末の設定で、あそびばの通知が許可されていません。スイッチをオンにしても、お知らせは届きません。"))
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Label(tr("設定アプリを開く"), systemImage: "gear")
                        }
                    }
                } header: {
                    Text(tr("通知"))
                } footer: {
                    Text(tr("途中でやめたあそびがあるとき、1日ほどたってから「続きから遊べます」とお知らせします。1つのあそびにつき1件・同時に3件までです。\nまた、よく遊んでいるあそびについて、最終プレイから7日・30日・60日後に「久しぶりに遊んでみませんか？」とお知らせします。複数のあそびで同時に進むことがあります（新しく始まるのは3日に1回まで）。そのあそびを開くと、そのあそびの分だけ止まります。60日後のお知らせにも触れないままだと、以降すべて届かなくなります。\nまた、柵越えおじさんの挑戦回数が戻ったときにも、1回お知らせします。\nオフにすると、3種類すべての予約済みのお知らせを取り消します。"))
                }

                // MARK: 解析
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.analyticsEnabled },
                        set: { settings.analyticsEnabled = $0 }
                    )) {
                        Label(tr("利用状況の送信"), systemImage: "chart.bar.doc.horizontal")
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.coral) // accent-text-ok: トグルのトラック（面）
                } header: {
                    Text(tr("解析"))
                } footer: {
                    Text(tr("どのあそびがどれくらい遊ばれているかを知るために、あそびの名前・勝敗・かかった時間を送ります。スコアや盤面、名前や連絡先のような個人を特定できる情報は送りません。オフにすると、これらに加えて起動回数などの自動計測もまとめて送信を止めます。"))
                }

                // MARK: プレイ記録
                if let playLog {
                    Section {
                        Button(role: .destructive) {
                            showClearPlayLogConfirm = true
                        } label: {
                            Label(tr("プレイ記録を消去"), systemImage: "trash")
                        }
                        .dialogs { anchor in
                            anchor.confirmationDialog(
                                tr("プレイ記録を消去しますか？"),
                                isPresented: $showClearPlayLogConfirm,
                                titleVisibility: .visible
                            ) {
                                Button(tr("消去する"), role: .destructive) {
                                    playLog.clear()
                                    // 久しぶり通知（#1193）はプレイ記録の最終プレイ日時を基準に予約するため、
                                    // 記録を消したのにスレッドや予約だけ残らないよう合わせて取り消す（#1269）。
                                    AppEnvironment.reengagement.cancelAll()
                                    // 結果を表示する場所が無いので、完了を VoiceOver と触覚で伝える（#2936）。
                                    feedback.notify(.success)
                                    AccessibilityNotification.Announcement(tr("プレイ記録を消去しました")).post()
                                }
                                Button(tr("キャンセル"), role: .cancel) {}
                            } message: {
                                Text(tr("ベストスコア・最短タイム・勝敗と連勝の記録、遊んだ回数・勝った回数、おすすめや評価のお願い・遊び方ガイドの表示履歴を消します。元に戻せません。"))
                            }
                        }
                    } header: {
                        Text(tr("プレイ記録"))
                    } footer: {
                        Text(tr("あそびごとのベストスコア・最短タイム・勝敗と連勝を、遊んだ回数・勝った回数・遊んだあそびの種類・おすすめと評価のお願い・遊び方ガイドの表示履歴とあわせてこの端末に保存しています（送信はしません）。盤面や棋譜は残していません。"))
                    }
                }

                // MARK: 規約
                Section(tr("規約")) {
                    Button {
                        legalURL = IdentifiableURL(url: legalPageURL(path: "terms"))
                    } label: {
                        Label(tr("利用規約"), systemImage: "doc.text")
                    }
                    .foregroundStyle(Theme.ink)
                    Button {
                        legalURL = IdentifiableURL(url: legalPageURL(path: "privacy"))
                    } label: {
                        Label(tr("プライバシーポリシー"), systemImage: "hand.raised")
                    }
                    .foregroundStyle(Theme.ink)
                }

                // MARK: その他
                Section(tr("その他")) {
                    Button {
                        // OS の `requestReview` は上限に達すると何も出ない。自分から押した人には
                        // 必ずレビュー画面が開く App Store の URL を使う（#1471）。
                        openURL(AppEnvironment.writeReviewURL)
                    } label: {
                        Label(tr("アプリを評価する"), systemImage: "star")
                    }
                    .foregroundStyle(Theme.ink)

                    ShareLink(
                        item: AppEnvironment.appStoreURL,
                        subject: Text(tr("あそびばアプリ")),
                        message: Text(tr("このゲームアプリ面白いよ！"))
                    ) {
                        Label(tr("アプリをシェア"), systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
            .environment(\.editMode, .constant(.active))
            .onAppear { settings.refreshFromDefaults() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                notificationAuthorization = await UserNotificationReminderScheduler().authorization()
            }
            .navigationTitle(tr("設定"))
            .sheet(item: $legalURL) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("完了")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    /// 表示言語のセレクトボックス（#2109）。初期値は端末の言語（`AppLanguageStore.bootstrap`）。
    /// 選んだ言語は保存され、アプリ本体と GameKit の全モジュールの文言にその場で効く。
    /// 選択肢はどの言語で表示していても、その言語自身の呼び名（日本語 / English）で出す。
    private var languagePicker: some View {
        Picker(selection: Binding(
            get: { AppLanguageStore.shared.language },
            set: { AppLanguageStore.shared.select($0) }
        )) {
            ForEach(AppLanguage.allCases) { language in
                Text(verbatim: language.nativeName).tag(language)
            }
        } label: {
            Label(tr("言語"), systemImage: "globe")
                .foregroundStyle(Theme.ink)
        }
        .pickerStyle(.menu)
        .tint(Theme.coralText)
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
                            .scaledFont(16, weight: .bold)
                            .foregroundStyle(Theme.onAccent)
                    }
                    .accessibilityHidden(true)
                Text(module.title)
                    .themeBody(16)
                    .foregroundStyle(isVisible ? Theme.ink : Theme.inkSubText)
            }
        }
        .tint(Theme.coral) // accent-text-ok: トグルのトラック（面）
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
