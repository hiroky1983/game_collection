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
        _path = State(initialValue: initialGameID.map { [$0] } ?? [])
        _showSettings = State(initialValue: showsSettingsInitially)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                        ForEach(Array(settings.visibleModules(from: registry).enumerated()), id: \.element.id) { index, module in
                            NavigationLink(value: module.id) {
                                GameCard(
                                    module: module,
                                    accent: Theme.palette[index % Theme.palette.count],
                                    accentFill: Theme.Fill.palette[index % Theme.Fill.palette.count],
                                    hasResume: services.snapshots.exists(for: module.id),
                                    record: services.playLog?.summaryLine(gameID: module.id),
                                    minHeight: cardMinHeight
                                )
                            }
                            .buttonStyle(.plain)
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
