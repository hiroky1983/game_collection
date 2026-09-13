import SwiftUI
import Core

/// ハブからゲーム画面への遷移先（#659）。
///
/// `NavigationLink(value:)` に載せる値を ID の文字列からこの型に広げ、**どの導線から入ったか**を
/// 遷移そのものに持たせる。タップの横で別の状態に書き留める形にすると、タップと `path` の変化の
/// 順序が保証されず、`game_open` の `source` に前の導線の値が載りうる。
struct HubRoute: Hashable {
    let gameID: String
    let source: GameOpenSource
    /// 導線の中での位置（1 始まり）。並びを持たない導線では nil。
    let position: Int?
    /// タップした時点で「続きから」だったか。
    let resume: Bool
}

/// ハブ画面。登録された GameModule をカードで列挙し、選択で各ゲームを遅延ロード起動する。
/// NavigationStack の土台はこの一覧。各ゲームは push される（→ ゲーム側の「戻る」でここに戻れる）。
struct HubView: View {
    let registry: GameRegistry
    let services: GameServices
    let settings: GameSettings
    @State private var path: [HubRoute]
    @State private var showSettings: Bool
    /// 未サインインで実績・ランキングを開こうとしたときの案内（#334）。
    @State private var showGameCenterSignInGuidance = false
    /// カードの長押しメニューで非表示にした直後に出す案内（#662）。非表示にしたゲーム名が入り、数秒で消える。
    @State private var hiddenNotice: String?
    /// 画面の広さ（#458）。カードの最小幅だけをここから受け取る。
    @Environment(\.adaptiveLayout) private var layout

    /// グリッドを載せるスクロール領域の高さ（#485）。カードの高さを行数で割り付けるために測る。
    @State private var viewportHeight: CGFloat = 0

    /// 行と列の間隔。列数・行の高さの計算にも同じ値を使う。
    private static let gridSpacing: CGFloat = 12

    /// ゲーム一覧のグリッド（#119）。iPhone は最小幅 130pt で必ず 2 列になり
    /// （SE 相当の 320pt 幅でも 3 列にはならない）、画面が広い iPad では
    /// 最小幅が 200pt へ上がって 4〜6 列に並ぶ（#458。130pt のままだと 7 列に割れて
    /// カードが iPhone より小さくなる）。
    ///
    /// `.adaptive` ではなく列数ぶんの `.flexible()` を並べるのは、**行数を知るため**（#485）。
    /// 並びかたは同じで、`AdaptiveLayout.hubColumnCount` が `.adaptive` と同じ数え方をする。
    ///
    /// ただし幅がまだ測れていない最初の 1 フレームだけは `.adaptive` に任せる。列数を自分で
    /// 数えると幅 0 から 1 列という答えが出てしまい、2 列に落ち着くまでの 1 フレームだけ
    /// 1 列で描かれてちらつく（`.adaptive` は容器の実寸から数えるのでこれが起きない）。
    private var columns: [GridItem] {
        guard layout.width > 0 else {
            return [GridItem(.adaptive(minimum: layout.hubCardMinWidth), spacing: Self.gridSpacing)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: Self.gridSpacing), count: columnCount)
    }

    private var columnCount: Int {
        max(1, layout.hubColumnCount(containerWidth: layout.width, spacing: Self.gridSpacing))
    }

    /// 「つづき・最近」行（#660）に出す候補。順序と打ち切りの規則は `RecentGames` が持つ。
    ///
    /// `PlayLog` も `SnapshotStore` も監視対象ではないので、行が更新されるのはハブが描き直される
    /// ときだけ。ゲームから戻れば `path` が変わって body が走るため、グリッドの「続きから」バッジと
    /// 同じタイミングで揃う（新しい監視の仕組みは足さない）。
    private var recentCandidates: [RecentGames.Candidate] {
        let visible = settings.visibleModules(from: registry).map(\.id)
        let resuming = visible.filter { services.snapshots.exists(for: $0) }
        return RecentGames.candidates(
            visibleGameIDs: visible,
            resumingGameIDs: Set(resuming),
            resumeUpdatedAt: resuming.reduce(into: [:]) { result, id in
                if let date = services.snapshots.modifiedAt(for: id) { result[id] = date }
            },
            lastPlayedAt: services.playLog?.lastPlayedAtByGame ?? [:]
        )
    }

    /// 差し色を引くための、ハブの並びのなかでの位置。グリッドのカードは `enumerated()` の
    /// index で色を引くので、行側も同じ index を使わないと同じゲームが2か所で違う色になる。
    private var paletteIndexByGame: [String: Int] {
        var result: [String: Int] = [:]
        for (index, module) in settings.visibleModules(from: registry).enumerated() {
            result[module.id] = index
        }
        return result
    }

    /// カード 1 枚に与える最小の高さ。iPad では縦を使い切るために伸び、iPhone では `nil`（＝据え置き）。
    private var cardMinHeight: CGFloat? {
        let count = settings.visibleModules(from: registry).count
        guard count > 0 else { return nil }
        let rows = (count + columnCount - 1) / columnCount
        return layout.hubCardMinHeight(viewportHeight: viewportHeight, rows: rows, spacing: Self.gridSpacing)
    }

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
        // 起動引数で直接開く経路（撮影・動作確認）。`onChange(of: path)` は初期値では走らないので
        // `game_open` は送られない（ユーザーの導線ではないため、それで正しい）。
        _path = State(initialValue: initialGameID.map {
            [HubRoute(gameID: $0, source: .hub, position: nil, resume: services.snapshots.exists(for: $0))]
        } ?? [])
        _showSettings = State(initialValue: showsSettingsInitially)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                // 中断・記録ともゼロなら**行ごと出さない**（#660）。`RecommendationSlot` が
                // 「決着前は何も描かない」のと同じ流儀で、初回ユーザーのハブは
                // 1pt も動かない。
                let recent = recentCandidates
                if !recent.isEmpty {
                    HubRecentRow(
                        candidates: recent,
                        registry: registry,
                        paletteIndexByGame: paletteIndexByGame
                    )
                }
                // 記録がゼロの初回だけ「はじめの1本」を1枚出す（#721）。出す条件と何を出すかは
                // `FirstPick` が持つ。置き場所は「つづき・最近」と同じくスクロール領域の外
                // （中に入れると iPad のカード高さの割り付けが溢れる・#485）。
                if let pick = FirstPick.gameID(
                    playedGameIDs: services.playLog?.playedGameIDs,
                    visibleGameIDs: settings.visibleModules(from: registry).map(\.id),
                    showsRecentRow: !recent.isEmpty
                ), let module = registry.module(id: pick) {
                    NavigationLink(value: HubRoute(
                        gameID: pick, source: .firstPick, position: nil,
                        resume: services.snapshots.exists(for: pick)
                    )) {
                        HubFirstPickCard(
                            module: module,
                            accentFill: Theme.Fill.palette[(paletteIndexByGame[pick] ?? 0) % Theme.Fill.palette.count]
                        )
                    }
                    .buttonStyle(.pop)
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, Theme.pad)
                }
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                        ForEach(Array(settings.visibleModules(from: registry).enumerated()), id: \.element.id) { index, module in
                            let hasResume = services.snapshots.exists(for: module.id)
                            // 位置は並べ替え設定を反映した**見えている順**の 1 始まり（#659）。
                            NavigationLink(value: HubRoute(
                                gameID: module.id, source: .hub, position: index + 1, resume: hasResume
                            )) {
                                GameCard(
                                    module: module,
                                    accent: Theme.palette[index % Theme.palette.count],
                                    accentFill: Theme.Fill.palette[index % Theme.Fill.palette.count],
                                    hasResume: hasResume,
                                    record: services.playLog?.summaryLine(gameID: module.id),
                                    minHeight: cardMinHeight
                                )
                            }
                            // `.plain` は押下フィードバックまで消す（#716）。ゲーム本体は遅延ロードで
                            // 画面が出るまで間があるため、押した手応えを `.pop` で返す。
                            .buttonStyle(.pop)
                            // 設定シートの奥にある並べ替え・非表示をハブから呼ぶ（#662）。
                            // 同じ `GameSettings` を触るので、設定シートの並びと二重の状態にならない。
                            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                            .contextMenu {
                                Button {
                                    moveToTop(module.id)
                                } label: {
                                    Label("いちばん上に置く", systemImage: "arrow.up.to.line")
                                }
                                .disabled(index == 0)
                                Button {
                                    hide(module)
                                } label: {
                                    Label("非表示にする", systemImage: "eye.slash")
                                }
                            }
                        }
                    }
                    .padding(Theme.pad)
                }
                // スクロール領域の高さを測る（#485）。`GeometryReader` をコンテナに使うと中身が
                // 左上寄せに変わるため、`AdaptiveLayout` と同じく `.background` に潜り込ませる。
                //
                // `size.height` そのままではなく安全領域を引くのが要点。`ScrollView` の枠は
                // ナビゲーションバー（大きなタイトル）の下まで伸びていて、中身はその内側に
                // 置かれる。引き忘れるとバーの高さぶんだけ行が高くなり、**最終行が画面外へ
                // はみ出して見切れる**（実測: 13 インチで 4 行目の説明文が切れた）。
                .background {
                    GeometryReader { geo in
                        let usable = geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom
                        Color.clear
                            .task(id: usable) { viewportHeight = usable }
                    }
                }
                .overlay(alignment: .bottom) {
                    Group {
                        if let hiddenNotice {
                            HubHiddenNotice(title: hiddenNotice)
                                .transition(.opacity)
                        }
                    }
                    .gameAnimation(.easeOut(duration: 0.2), value: hiddenNotice)
                }
                .task(id: hiddenNotice) {
                    guard hiddenNotice != nil else { return }
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    hiddenNotice = nil
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
                    // アイコンだけのボタンは VoiceOver がシンボル名を読む（#716）。
                    .accessibilityLabel("設定")
                }
            }
            .navigationDestination(for: HubRoute.self) { route in
                if let module = registry.module(id: route.gameID) {
                    module.makeView(services: services)
                }
            }
            .onChange(of: path) { oldPath, newPath in
                // ゲーム画面から離れたことを解析へ伝える（#158）。次に開いたときを新しい
                // 1 プレイとして数え直すための境界で、ここが唯一の発火点。
                // レコメンドでの差し替え（空 path を経由する）も「離れた」で正しい。
                if !oldPath.isEmpty, newPath.isEmpty, let left = oldPath.last {
                    services.gameDidLeave(gameID: left.gameID)
                }
                // ハブからゲーム画面を開いたことを解析へ伝える（#659）。離脱と対になる
                // 「空 → 非空」の1か所だけで送る。導線ごとに送ると付け忘れと二重送信の両方が起きる。
                if oldPath.isEmpty, let opened = newPath.first {
                    services.gameDidOpen(
                        gameID: opened.gameID, source: opened.source,
                        position: opened.position, resume: opened.resume
                    )
                }
            }
            // リザルトのレコメンドカードがタップされたら、そのゲームへ差し替えて遷移する。
            .onChange(of: services.recommendations?.requestedGameID) { _, requested in
                guard let id = requested else { return }
                services.recommendations?.requestedGameID = nil
                openFromOutside(HubRoute(
                    gameID: id, source: .recommendation, position: nil,
                    resume: services.snapshots.exists(for: id)
                ))
            }
            // 中断したゲームのお知らせ（#663）がタップされたら、そのゲームを直接開く。
            // アプリが終了していた状態からのタップはハブが描かれる前に値が入ることがあるため、
            // 初期値でも走らせる。
            .onChange(of: services.reminders?.requestedGameID, initial: true) { _, requested in
                guard let id = requested else { return }
                services.reminders?.requestedGameID = nil
                // 設定を開いたままだと、その裏で遷移して何も起きていないように見える。
                showSettings = false
                openFromOutside(HubRoute(
                    gameID: id, source: .notification, position: nil,
                    resume: services.snapshots.exists(for: id)
                ))
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
                // 動作確認用: 中断のお知らせ（#663）をタップしたのと同じ入口でゲームを開く
                // （`-simulateNotificationTap <gameID>`）。シミュレータでは通知をタップできないため。
                if let i = args.firstIndex(of: "-simulateNotificationTap"), i + 1 < args.count {
                    services.reminders?.notificationTapped(gameID: args[i + 1])
                }
                // 動作確認用: ツールバーの「実績・ランキング」を押したのと同じ分岐を通す
                // （`-simulateGameCenterEntry`）。シミュレータは Game Center 未サインインのため、
                // 実際に確認できるのは案内アラートの側になる。
                if args.contains("-simulateGameCenterEntry") {
                    openGameCenter()
                }
                // 撮影・動作確認用: カードの長押しメニューで「非表示にする」を選んだのと同じ経路を通す
                // （`-simulateHubHide <gameID>`・#662）。シミュレータでは長押しを自動化できないため。
                if let i = args.firstIndex(of: "-simulateHubHide"), i + 1 < args.count,
                   let module = registry.module(id: args[i + 1]) {
                    hide(module)
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

    /// ハブの外（リザルトのレコメンド・中断のお知らせ）から求められたゲームへ遷移する。
    ///
    /// NavigationStack は表示中の遷移先を1手で差し替えると描画が壊れる（画面が真っ白になる）。
    /// いったん根まで戻し、次の runloop で積み直す。
    private func openFromOutside(_ route: HubRoute) {
        path = []
        DispatchQueue.main.async { path = [route] }
    }

    /// 長押しメニューの「いちばん上に置く」（#662）。位置は表示中の並びではなく、非表示も含む
    /// `orderedIDs` の中で数える（設定シートの `onMove` と同じ座標）。
    private func moveToTop(_ id: String) {
        guard let from = settings.orderedIDs.firstIndex(of: id), from > 0 else { return }
        settings.move(from: IndexSet(integer: from), to: 0)
    }

    /// 長押しメニューの「非表示にする」（#662）。戻す場所が設定シートの奥にあるため、直後に案内を出す。
    private func hide(_ module: GameModule) {
        guard !settings.hiddenIDs.contains(module.id) else { return }
        settings.toggleHidden(module.id)
        hiddenNotice = module.title
        AccessibilityNotification.Announcement(HubHiddenNotice.message(title: module.title)).post()
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
    /// 「続きから」バッジの**文字色**。明るい地の上に置くので差し色そのままを使う。
    let accent: Color
    /// アイコンチップの**面色**。上に白ではなく `Theme.onAccent` を載せる（#220）。
    let accentFill: Color
    let hasResume: Bool
    /// プレイ記録の 1 行（#115）。まだ記録が無ければ nil で、その場合はゲームの説明を出す。
    let record: String?
    /// iPad で縦を使い切るための最小の高さ（#485）。iPhone では nil ＝中身が決める高さのまま。
    let minHeight: CGFloat?

    /// 固定 pt の部品（アイコンチップ・文字）を広い画面で拡大するための倍率（#458 / #485）。
    /// 狭い画面では恒等なので、iPhone のカードは 1pt も動かない。
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        VStack(alignment: .leading, spacing: layout.scaled(6)) {
            HStack(alignment: .top, spacing: layout.scaled(6)) {
                // カラフルなアイコンチップ
                RoundedRectangle(cornerRadius: layout.scaled(Theme.cornerSmall), style: .continuous)
                    .fill(accentFill.gradient)
                    .frame(width: layout.scaled(44), height: layout.scaled(44))
                    .overlay {
                        module.icon
                            .font(.system(size: layout.scaled(22), weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                    }
                    .shadow(color: accent.opacity(0.4), radius: 5, y: 3)

                Spacer(minLength: 0)

                if hasResume {
                    Text("続きから")
                        .themeCaption(layout.scaled(11))
                        .foregroundStyle(accent)
                        .padding(.horizontal, layout.scaled(8))
                        .padding(.vertical, layout.scaled(3))
                        .background(Capsule().fill(accent.opacity(0.15)))
                        .fixedSize()
                }
            }

            Text(module.title)
                .themeTitle(layout.scaled(18))
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
            .themeCaption(layout.scaled(11))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        // `.leading` は横だけの指定で縦は中央。高さを与えられた iPad では中身がカードの
        // 縦中央に来る（上詰めのままだとカードの下半分が空く）。iPhone は高さが中身ぶんの
        // ままなので、中央寄せは何も動かさない。
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .padding(layout.scaled(10))
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

/// カードを長押しメニューで非表示にした直後の案内（#662）。
///
/// 戻す操作は設定シートにしか無いので、その場所だけを1行で伝える。読み上げは `HubView.hide` が
/// 同じ文言をアナウンスで流すため、ここは VoiceOver から隠す（二重に読ませない）。
private struct HubHiddenNotice: View {
    let title: String

    static func message(title: String) -> String {
        "「\(title)」を非表示にしました。設定から戻せます"
    }

    var body: some View {
        Text(Self.message(title: title))
            .themeCaption(13)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.pad)
            .padding(.vertical, 10)
            .popCard(corner: Theme.cornerSmall)
            .padding(Theme.pad)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
