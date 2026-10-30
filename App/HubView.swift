import SwiftUI
import Core
import GameHomerun

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
    /// アプリ内「きろく」画面（#669）。ツールバーのトロフィーから開く。
    @State private var showRecords: Bool
    /// 「きろく」の中から Game Center を求められた。シートが閉じ切ってから開くための印
    /// （シートを出したまま Game Center のオーバーレイやサインイン画面を重ねない）。
    @State private var opensGameCenterAfterRecords = false
    /// 「きろく」のゲーム行で選ばれたゲーム（#1974）。シートが閉じ切ってから開く（Game Center と同じ理由）。
    @State private var opensGameAfterRecords: String?
    /// 未サインインで実績・ランキングを開こうとしたときの案内（#334）。
    @State private var showGameCenterSignInGuidance = false
    /// カードの長押しメニューで非表示にした直後に出す案内（#662）。数秒で消える。
    @State private var hiddenNotice: HiddenNotice?
    /// 柵越えおじさんの今日の残り回数（タイルの印・#2208。通常のタイルになっても出す・#2572）。
    /// 数え方は `HomerunHubCount`（打席前と同じ台帳）。ゲームから戻ったとき・前面に戻ったとき・
    /// ハブを開いたまま 0:00 を越えたときに読み直す。
    @State private var homerunTally = HomerunHubCount.tally()

    /// 非表示 1 回ぶんの案内。消えるまでの時間は `.task(id:)` で数えるため、名前だけでなく回ごとの ID を持たせる
    /// （設定で戻して同じゲームを続けて隠すと、名前が同じで数え直しが起きない）。
    private struct HiddenNotice: Equatable {
        let moduleID: String
        let title: String
        let id = UUID()
    }
    /// 画面の広さ（#458）。カードの最小幅だけをここから受け取る。
    @Environment(\.adaptiveLayout) private var layout
    @Environment(\.scenePhase) private var scenePhase
    /// VoiceOver・スイッチコントロール中は「元に戻す」に辿り着くのに 5 秒では足りないため、案内を自動で消さない（#2330）。
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    /// 選んでいるカテゴリーのチップ（#1831）。保存しない（起動のたびに「すべて」）。
    @State private var selectedCategory: HubCategory = .all

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

    /// 表示するゲームの並び。この版の新着を先頭に固定し、そのあとに利用者の並びが続く（#2104）。
    /// 非表示にしたゲームは `visibleModules` の時点で除かれるので、新着でも出さない。
    private var pinnedVisibleModules: [GameModule] {
        let visible = settings.visibleModules(from: registry)
        let order = NewGames.pinned(visibleIDs: visible.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        return order.compactMap { byID[$0] }
    }

    /// 実際に絞り込むカテゴリー。選んだカテゴリーのゲームが全部非表示になって消えたら「すべて」に戻す。
    private var activeCategory: HubCategory {
        chipCategories.contains(selectedCategory) ? selectedCategory : .all
    }

    /// チップに出すカテゴリー（「すべて」＋表示中のゲームが 1 本以上入るもの）。1 種類しか無いなら出さない。
    private var chipCategories: [HubCategory] {
        let populated = registry.populatedCategories(among: pinnedVisibleModules.map(\.id))
        return populated.count > 1 ? [.all] + populated : []
    }

    /// グリッドの 1 枚。
    private struct GridEntry {
        let module: GameModule
        /// `game_open` の `position`（1 始まり・絞る前の並びでの位置）。
        let position: Int
    }

    /// カテゴリーで絞ったあとにグリッドへ並べるゲーム。位置は絞る前の並びでの 1 始まり
    /// （絞り込みの有無で同じゲームの位置が変わらない）。
    private var shownGridEntries: [GridEntry] {
        let entries = pinnedVisibleModules.enumerated().map { GridEntry(module: $0.element, position: $0.offset + 1) }
        guard activeCategory != .all else { return entries }
        return entries.filter { registry.category(of: $0.module.id) == activeCategory }
    }

    /// 「つづき・最近」行（#660）に出す候補。順序と打ち切りの規則は `RecentGames` が持つ。
    ///
    /// `PlayLog` も `SnapshotStore` も監視対象ではないので、行が更新されるのはハブが描き直される
    /// ときだけ。ゲームから戻れば `path` が変わって body が走るため、グリッドの「続きから」バッジと
    /// 同じタイミングで揃う（新しい監視の仕組みは足さない）。
    private var recentCandidates: [RecentGames.Candidate] {
        let visible = settings.visibleModules(from: registry).map(\.id)
        let resuming = visible.filter { isResumable($0) }
        return RecentGames.candidates(
            visibleGameIDs: visible,
            resumingGameIDs: Set(resuming),
            resumeUpdatedAt: resuming.reduce(into: [:]) { result, id in
                if let date = services.snapshots.modifiedAt(for: id) { result[id] = date }
            },
            lastPlayedAt: services.playLog?.lastPlayedAtByGame ?? [:]
        )
    }

    /// 「続きから」で戻れる途中の局があるか（#809）。行・グリッドのバッジ・`game_open` の `resume` は
    /// すべてここを通す。中断データの有無だけで決めると、局を復元しないチャリンコおじさんと、
    /// 終局後も見返しを残す将棋・チェスが「つづきから」として先頭を占め続ける。
    private func isResumable(_ gameID: String) -> Bool {
        registry.hasResumableSnapshot(gameID: gameID, in: services.snapshots)
    }

    /// 更新で増えたゲームのうち、まだ開いていないもの（#723）。起動して最初にハブを組み立てた時点で決まり、
    /// 開いたゲームから外していく。保存はしない（次の起動では `PlayLog` が「既知」として返さない）。
    @State private var newGameIDs: Set<String>

    /// 差し色を引くための、ハブの並びのなかでの位置。グリッドのカードは `enumerated()` の
    /// index で色を引くので、行側も同じ index を使わないと同じゲームが2か所で違う色になる。
    private var paletteIndexByGame: [String: Int] {
        var result: [String: Int] = [:]
        for (index, module) in pinnedVisibleModules.enumerated() {
            result[module.id] = index
        }
        return result
    }

    init(
        registry: GameRegistry,
        services: GameServices,
        settings: GameSettings,
        initialGameID: String? = nil,
        showsSettingsInitially: Bool = false,
        showsRecordsInitially: Bool = false
    ) {
        self.registry = registry
        self.services = services
        self.settings = settings
        // 起動引数で直接開く経路（撮影・動作確認）。`onChange(of: path)` は初期値では走らないので
        // `game_open` は送られない（ユーザーの導線ではないため、それで正しい）。
        _path = State(initialValue: initialGameID.map {
            [HubRoute(
                gameID: $0, source: .hub, position: nil,
                resume: registry.hasResumableSnapshot(gameID: $0, in: services.snapshots)
            )]
        } ?? [])
        #if DEBUG
        // 撮影用: チップで絞った状態から始める（`-hubCategory <ojisan|board|cards|mahjongHanafuda|puzzleOther>`・#1831）。
        // シミュレータではタップを自動化できないため。
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-hubCategory"), i + 1 < args.count, let c = HubCategory(rawValue: args[i + 1]) {
            _selectedCategory = State(initialValue: c)
        }
        #endif
        _showSettings = State(initialValue: showsSettingsInitially)
        _showRecords = State(initialValue: showsRecordsInitially)
        // `init` は描き直しのたびに走るが、`PlayLog` が起動中は同じ値を返すので保存は1回きり。
        _newGameIDs = State(initialValue: services.playLog?.newGameIDs(
            registeredIDs: registry.modules.map(\.id)
        ) ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                // 見出し（あそびば・きろく・設定）。モック（docs/design/hub-redesign-1831 の 01・04b）どおり、
                // 大きな題字と白いピルのボタンを自前で描く（標準のナビゲーションバーは出さない・#2175）。
                header
                // カテゴリーのチップ（#1831）。見出しのすぐ下に置き、スクロールしても常に見える。
                // チップは 44pt の当たり判定を持つので、見た目の上下の余白（モックの 10pt）からそのぶんを引く。
                if !chipCategories.isEmpty {
                    HubCategoryChips(categories: chipCategories, selected: activeCategory) { category in
                        withGameAnimation(.easeOut(duration: 0.2)) { selectedCategory = category }
                    }
                    .padding(.top, 10 - HubCategoryChips.hitSlop(layout))
                    .padding(.bottom, -HubCategoryChips.hitSlop(layout))
                    .zIndex(1)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                    if activeCategory == .all {
                        // 中断・記録ともゼロなら**行ごと出さない**（#660）。「すべて」のときだけ出す（モック 01・04b）。
                        // 連続プレイ日数（#1625）は 2 日以上のときだけ、行の見出しの右に控えめに出す。
                        let recent = recentCandidates
                        if !recent.isEmpty {
                            HubRecentRow(
                                candidates: recent,
                                registry: registry,
                                streakText: PlayDayStreak.hubText(streak: services.playLog?.playStreak() ?? 0)
                            )
                        }
                        // 記録がゼロの初回だけ「はじめの1本」を1枚出す（#721）。出す条件と何を出すかは `FirstPick` が持つ。
                        if let pick = FirstPick.gameID(
                            playedGameIDs: services.playLog?.playedGameIDs,
                            visibleGameIDs: settings.visibleModules(from: registry).map(\.id),
                            showsRecentRow: !recent.isEmpty
                        ), let module = registry.module(id: pick) {
                            NavigationLink(value: HubRoute(
                                gameID: pick, source: .firstPick, position: nil,
                                resume: isResumable(pick)
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
                    } else {
                        // カテゴリーを選んだときの見出し（モック 04b の「トランプ　7本」）。
                        HubCategoryHeading(title: activeCategory.title, count: shownGridEntries.count)
                            .padding(.horizontal, Theme.pad)
                            .padding(.top, 14)
                    }
                    // 全ゲームを非表示にした直後は空白にせず、設定へ戻る導線を出す（#2002）。
                    if HubEmptyState.isShown(visibleGameIDs: settings.visibleModules(from: registry).map(\.id)) {
                        HubEmptyStateView { showSettings = true }
                            .padding(.horizontal, Theme.pad)
                            .padding(.top, 12)
                    }
                    LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                        ForEach(shownGridEntries, id: \.module.id) { entry in
                            gridTile(entry)
                        }
                    }
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 12)
                    .padding(.bottom, Theme.pad)
                    }
                }
                .overlay(alignment: .bottom) {
                    Group {
                        if let hiddenNotice {
                            HubHiddenNotice(title: hiddenNotice.title) { undoHide(hiddenNotice) } onDismiss: { self.hiddenNotice = nil }
                                .transition(.opacity)
                        }
                    }
                    .gameAnimation(.easeOut(duration: 0.2), value: hiddenNotice)
                }
                .task(id: hiddenNotice) {
                    guard hiddenNotice != nil, !voiceOverEnabled, !switchControlEnabled else { return }
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    hiddenNotice = nil
                }
                BannerSlot(ads: services.ads)
            }
            .popBackground()
            // 遊んだ日数の節目の評価のお願い（#3078）。ハブが前面にある間だけ実行する（ゲームを開いたら破棄）。
            .hubReviewRequestPrompt(services.review, isActive: path.isEmpty)
            // 戻るボタンの文字に使う。ハブ自身ではナビゲーションバーを隠し、見出しは `header` が描く（#2175）。
            .navigationTitle(tr("あそびば"))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HubRoute.self) { route in
                if let module = registry.module(id: route.gameID) {
                    // 自己ベスト更新のリザルトに出す共有ボタンの情報（#1043）。20 本の `RecordLabel` の
                    // 呼び出しを直さずに済むよう、ゲーム画面を作るここ 1 か所から配る。
                    let gameID = module.id
                    let services = services
                    // 描き直しのたびに model を作って捨てないよう、1 回だけ作る入れ物を通す（#1926）。
                    GameScreenHost { module.makeView(services: services) }
                        .environment(\.recordShare, RecordShareContext(
                            gameTitle: module.title,
                            url: AppEnvironment.appStoreURL,
                            didTap: { services.gameDidTapShare(gameID: gameID) }
                        ))
                        .environment(\.playStreakProvider, { services.playLog?.playStreak() ?? 0 })
                        .task {
                            // 手つかずの中断データを開き直した回の `game_start` を数える（#2161）。
                            services.gameScreenDidAppear(
                                gameID: gameID,
                                hasUntouchedSnapshot: module.hasUntouchedSnapshot(in: services.snapshots)
                            )
                        }
                }
            }
            // ハブを開いたまま 0:00 を越えたら、その場で残り回数を戻す（#2208。打席前のボタンと同じ境目）。
            .task {
                while !Task.isCancelled {
                    let wait = HomerunHubCount.nextReset(after: Date()).timeIntervalSinceNow + 1
                    do { try await Task.sleep(for: .seconds(max(1, wait))) } catch { return }
                    homerunTally = HomerunHubCount.tally()
                }
            }
            // ゲーム画面を出したままホームボタン・アプリ切替で離れる中断にも続きのお知らせを予約し、
            // 前面へ戻ったら取り消す（#1951）。予約だけを行い、離脱計測（`gameDidLeave`）は呼ばない。
            .onChange(of: scenePhase) { _, phase in
                // 日付をまたいで戻った回数を、前面に戻ったハブで出し直す（#2208）。
                if phase == .active {
                    homerunTally = HomerunHubCount.tally()
                    // 日付をまたいで前面に戻った日も、遊んだ日として数える（#3078。評価のお願いは出さない）。
                    services.review?.appDidOpen()
                }
                guard let current = path.last else { return }
                switch phase {
                case .background: services.gameDidEnterBackground(gameID: current.gameID)
                case .active: services.gameDidReturnToForeground(gameID: current.gameID)
                default: break
                }
            }
            .onChange(of: path) { oldPath, newPath in
                // ゲーム画面から離れたことを解析へ伝える（#158）。次に開いたときを新しい
                // 1 プレイとして数え直すための境界で、ここが唯一の発火点。
                // レコメンドでの差し替え（空 path を経由する）も「離れた」で正しい。
                if !oldPath.isEmpty, newPath.isEmpty, let left = oldPath.last {
                    services.gameDidLeave(gameID: left.gameID)
                    // ハブに戻ったら柵越えおじさんの残り回数を読み直す（遊んだ分・0:00 の補充・#2208）。
                    homerunTally = HomerunHubCount.tally()
                }
                // ハブに戻った区切りで、遊んだ日数の節目なら評価のお願いの予定を立てる（#3078）。
                if newPath.isEmpty { services.review?.hubDidBecomeVisible() }
                // ハブからゲーム画面を開いたことを解析へ伝える（#659）。離脱と対になる
                // 「空 → 非空」の1か所だけで送る。導線ごとに送ると付け忘れと二重送信の両方が起きる。
                if oldPath.isEmpty, let opened = newPath.first {
                    services.gameDidOpen(
                        gameID: opened.gameID, source: opened.source,
                        position: opened.position, resume: opened.resume
                    )
                    // 開いたゲームは「見た」ので NEW 印を外す（#723）。導線を問わずここ1か所で外す。
                    newGameIDs.remove(opened.gameID)
                    // 先読みしたリワード広告が失効・未取得なら、ゲームを開いたこの時点で読み直す（#658）。
                    // 救済の広告はゲーム画面の中でしか出ないので、ここで読んでおけばタップに間に合う。
                    (services.ads as? AdMobAdService)?.preloadRewardedAd()
                }
            }
            // リザルトのレコメンドカードがタップされたら、そのゲームへ差し替えて遷移する。
            .onChange(of: services.recommendations?.requestedGameID) { _, requested in
                guard let id = requested else { return }
                services.recommendations?.requestedGameID = nil
                openFromOutside(HubRoute(
                    gameID: id, source: .recommendation, position: nil,
                    resume: isResumable(id)
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
                showRecords = false
                openFromOutside(HubRoute(
                    gameID: id, source: .resumeReminder, position: nil,
                    resume: isResumable(id)
                ))
            }
            // 再エンゲージメント通知（#1193）がタップされたら、そのゲームを直接開く。
            .onChange(of: services.reengagement?.requestedGameID, initial: true) { _, requested in
                guard let id = requested else { return }
                services.reengagement?.requestedGameID = nil
                showSettings = false
                showRecords = false
                openFromOutside(HubRoute(
                    gameID: id, source: .reengagement, position: nil,
                    resume: isResumable(id)
                ))
            }
            // 挑戦回数が戻ったお知らせ（#1576・#1950）がタップされたら、そのゲームを直接開く。
            // 設定で非表示にしたゲームは開かない（クイックアクションと同じ）。
            .onChange(of: services.returnReminder?.requestedGameID, initial: true) { _, requested in
                guard let id = requested else { return }
                services.returnReminder?.requestedGameID = nil
                guard settings.visibleModules(from: registry).contains(where: { $0.id == id }) else { return }
                showSettings = false
                showRecords = false
                openFromOutside(HubRoute(
                    gameID: id, source: .challengeReturn, position: nil,
                    resume: isResumable(id)
                ))
            }
            // ホーム画面アイコン長押し（#1642）の項目がタップされたら、そのゲームを直接開く。
            // 終了していた状態からの起動は値がハブより先に入るため、初期値でも走らせる。
            // 設定で非表示にしたゲームは、項目が古いままでも開かない。
            .onChange(of: AppEnvironment.quickActions.requestedGameID, initial: true) { _, requested in
                guard let id = requested else { return }
                AppEnvironment.quickActions.requestedGameID = nil
                guard settings.visibleModules(from: registry).contains(where: { $0.id == id }) else { return }
                showSettings = false
                showRecords = false
                openFromOutside(HubRoute(
                    gameID: id, source: .quickAction, position: nil,
                    resume: isResumable(id)
                ))
            }
            // ディープリンク `asobiba://game/<game_id>`（#2141・App 内イベントの審査で必須）。
            // 終了していた状態からの起動でも、ハブが描かれた後にここへ届く。
            // 未知・設定で非表示のゲーム、`asobiba://` 単体はハブのまま（遷移しない）。
            .onOpenURL { url in
                let openable = Set(settings.visibleModules(from: registry).map(\.id))
                guard case .game(let id) = DeepLink.destination(for: url, openableGameIDs: openable) else { return }
                // 「きろく」を閉じる途中に届いたら、閉じた後に予約していた遷移・案内より URL を優先する。
                opensGameAfterRecords = nil
                opensGameCenterAfterRecords = false
                showSettings = false
                showRecords = false
                openFromOutside(HubRoute(
                    gameID: id, source: .deeplink, position: nil,
                    resume: isResumable(id)
                ))
            }
            .task {
                // 起動した日を遊んだ日として数える（#3078。起動直後には評価のお願いを出さない）。
                services.review?.appDidOpen()
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
                // 撮影用: 新しいゲームの感想カード（#3061）を条件を通さずに出す（`-startGame <id> -simulateNewGameCard`）。
                // 画面遷移の最中に立てると、画面の作り直しで予定が破棄されるため、遷移が落ち着いてから立てる。
                if args.contains("-simulateNewGameCard") {
                    try? await Task.sleep(for: .seconds(2))
                    services.review?.simulateNewGameCard()
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
                // 動作確認用: 起動の 2 秒後に、設定の言語のセレクトボックスで選んだのと同じく表示言語を切り替える
                // （`-simulateLanguageSwitch en`。保存はしない）。再起動なしでハブが描き直されるかを見る（#2201）。
                if let i = args.firstIndex(of: "-simulateLanguageSwitch"), i + 1 < args.count,
                   let language = AppLanguage(rawValue: args[i + 1]) {
                    try? await Task.sleep(for: .seconds(2))
                    AppLanguageStore.shared.apply(language)
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
                    for type: FeedbackNotice in [.success, .warning, .error, .milestone] {
                        services.feedback.notify(type)
                    }
                }
                #endif
            }
        }
        .tint(Theme.coralText)
        .sheet(isPresented: $showSettings) {
            SettingsView(
                registry: registry, settings: settings, playLog: services.playLog, feedback: services.feedback)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showRecords, onDismiss: {
            if let id = opensGameAfterRecords {
                opensGameAfterRecords = nil
                openFromOutside(HubRoute(gameID: id, source: .records, position: nil, resume: isResumable(id)))
                return
            }
            guard opensGameCenterAfterRecords else { return }
            opensGameCenterAfterRecords = false
            openGameCenter()
        }) {
            RecordsView(
                registry: registry, settings: settings, playLog: services.playLog,
                onOpenGame: { id in
                    opensGameAfterRecords = id
                    showRecords = false
                }
            ) {
                opensGameCenterAfterRecords = true
                showRecords = false
            }
            .presentationDetents([.large])
        }
        .dialogs { anchor in
            anchor.alert(tr("Game Center にサインインしていません"), isPresented: $showGameCenterSignInGuidance) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(tr("iPhone の「設定」＞「Game Center」からサインインすると、実績と世界のランキングを見られます。サインインしなくても、あそびはすべてそのまま遊べます。"))
            }
        }
    }

    /// 見出しの「きろく」「設定」ボタン（会長 QA #2201「小さくて押しにくい」）。押せる範囲は HIG の最小値
    /// 44×44pt 以上（https://developer.apple.com/design/human-interface-guidelines/accessibility#Buttons-and-controls）、
    /// アイコンは 20pt→24pt、2 つの間隔も空ける。iPad は `layout.scaled` で 1.5 倍。
    static let headerButtonSize: CGFloat = 48
    static let headerIconSize: CGFloat = 24
    static let headerButtonSpacing: CGFloat = 6

    /// 見出し（モック 01・04b の `.hdr`）。題字 34pt・右に白いピルの「きろく」「設定」（珊瑚色のアイコン）。
    private var header: some View {
        HStack(alignment: .top) {
            Text(tr("あそびば"))
                .themeTitle(layout.scaled(34), weight: .black, maxScale: 1.3)
                .tracking(0.5)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            HStack(spacing: layout.scaled(Self.headerButtonSpacing)) {
                // きろく（#669）。以前は Game Center を直接開いていた（#334）が、未サインインだと案内で
                // 終わって手元の記録を見る場所が無かったため、アプリ内の画面に付け替えた。
                // Game Center はその画面の中のボタンから開く。歯車より左の位置は変えない。
                Button { showRecords = true } label: {
                    Image(systemName: "trophy.fill")
                        .scaledFont(layout.scaled(Self.headerIconSize), weight: .semibold, maxScale: 1.2)
                        .frame(width: layout.scaled(Self.headerButtonSize), height: layout.scaled(Self.headerButtonSize))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(tr("きろく"))
                // アイコンだけのボタンは VoiceOver がシンボル名を読む（#716）。
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .scaledFont(layout.scaled(Self.headerIconSize), weight: .semibold, maxScale: 1.2)
                        .frame(width: layout.scaled(Self.headerButtonSize), height: layout.scaled(Self.headerButtonSize))
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(tr("設定"))
            }
            .foregroundStyle(Theme.coralText)
            .buttonStyle(.pop)
            .padding(.horizontal, layout.scaled(6))
            .background(
                Capsule()
                    .fill(Theme.surface)
                    .shadow(color: Theme.cardShadow, radius: 5, x: 0, y: 6)
            )
            .padding(.top, 2)
        }
        .padding(.horizontal, Theme.pad)
        .padding(.top, 2)
    }

    /// ハブの外（リザルトのレコメンド・中断のお知らせ）から求められたゲームへ遷移する。
    ///
    /// NavigationStack は表示中の遷移先を1手で差し替えると描画が壊れる（画面が真っ白になる）。
    /// いったん根まで戻し、次の runloop で積み直す。
    /// グリッドの 1 枚。
    private func gridTile(_ entry: GridEntry) -> some View {
        let module = entry.module
        let hasResume = isResumable(module.id)
        // 記録が無い（一度も遊んでいない）ゲームに出す。1 回遊べば消える（#2849）。記録が読めないときは出さない。
        let isUnplayed = services.playLog.map { !$0.hasPlayed(gameID: module.id) } ?? false
        // 位置は並べ替え設定を反映した**見えている順**の 1 始まり（#659）。
        return NavigationLink(value: HubRoute(
            gameID: module.id, source: .hub, position: entry.position, resume: hasResume
        )) {
            GameCard(
                module: module,
                hasResume: hasResume,
                resumeProgress: hasResume ? registry.resumeProgress(gameID: module.id, in: services.snapshots) : nil,
                isNew: NewGames.currentVersionIDs.contains(module.id),
                isEvent: HubEventBadge.isShown(gameID: module.id),
                updateTag: UpdatedGames.tag(for: module.id),
                isUnplayed: isUnplayed,
                // 柵越えおじさんだけ、今日の残り回数（#2208。ボールの絵は #2273）。「イベント開催中」と両方出す（#2572）。
                count: HubCountBadge.isShown(gameID: module.id) ? homerunTally : nil
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
                Label(tr("いちばん上に置く"), systemImage: "arrow.up.to.line")
            }
            // 先頭かどうかは非表示も含む並びで、新着の固定（#2104）を踏まえて見る（#2124）。
            // 表示中の先頭でも、前に非表示のゲームがあれば動かす余地がある。
            .disabled(NewGames.isAlreadyAtTop(
                id: module.id, orderedIDs: settings.orderedIDs, hiddenIDs: settings.hiddenIDs))
            Button {
                hide(module)
            } label: {
                Label(tr("非表示にする"), systemImage: "eye.slash")
            }
        }
    }

    private func openFromOutside(_ route: HubRoute) {
        path = []
        DispatchQueue.main.async { path = [route] }
    }

    /// 長押しメニューの「いちばん上に置く」（#662）。位置は表示中の並びではなく、非表示も含む
    /// `orderedIDs` の中で数える（設定シートの `onMove` と同じ座標）。
    private func moveToTop(_ id: String) {
        guard let from = settings.orderedIDs.firstIndex(of: id), from > 0 else { return }
        // 新着は表示で先頭に固定される（#2104）ので、案内は動かす前の並びから実際の位置を伝える（#2124）。
        let announcement = registry.module(id: id).map {
            NewGames.moveToTopAnnouncement(
                title: $0.title, id: id, orderedIDs: settings.orderedIDs, hiddenIDs: settings.hiddenIDs)
        }
        // 並びの入れ替えを動きで見せる（Reduce Motion では即時）。無音のままだと VoiceOver 利用者は
        // 動いたことが分からないので、非表示（`hide`）と同じくアナウンスも流す。
        withGameAnimation(.easeOut(duration: 0.25)) {
            settings.move(from: IndexSet(integer: from), to: 0)
        }
        if let announcement {
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    /// 長押しメニューの「非表示にする」（#662）。戻す場所が設定シートの奥にあるため、直後に案内を出す。
    private func hide(_ module: GameModule) {
        guard !settings.hiddenIDs.contains(module.id) else { return }
        settings.toggleHidden(module.id)
        hiddenNotice = HiddenNotice(moduleID: module.id, title: module.title)
        AccessibilityNotification.Announcement(HubHiddenNotice.message(title: module.title)).post()
    }

    /// 案内の「元に戻す」（#2047）。非表示は並びを動かさないので、`toggleHidden` でもとの位置に戻る。
    /// 案内が出ている間に設定シートで先に戻されていたら、押しても再び隠さない。
    private func undoHide(_ notice: HiddenNotice) {
        hiddenNotice = nil
        guard settings.hiddenIDs.contains(notice.moduleID) else { return }
        settings.toggleHidden(notice.moduleID)
        AccessibilityNotification.Announcement(tr("「%@」を元に戻しました", notice.title)).post()
    }

    /// 「きろく」の中の「Game Center で実績・ランキングを見る」（#669。以前はツールバーから直接・#334）。
    /// サインイン済みなら Game Center を開き、
    /// 未サインインのときだけサインインを促す（#334 の受け入れ条件）。
    private func openGameCenter() {
        if GameCenterEntry.open() == .needsSignInGuidance {
            showGameCenterSignInGuidance = true
        }
    }
}

/// ハブの絵のタイル（2列グリッド・#119、絵のタイルは #1831、モックどおりの見た目は #2175）。
///
/// 絵・ゲーム名・下線は 1 枚の画像（アセット `hubtile-<id>`）に入っている
/// （会長指示「画像で良いからちゃんとしてくれ」#2175）。画像は `Scripts/generate-hub-tiles.py` がモック
/// （docs/design/hub-redesign-1831 の 01）の HTML・CSS そのままで書き出す。アプリはタイルの比率で敷き、
/// 角丸と影を付け、「続きから」「NEW」だけを左下に重ねる（モック 01 の `.badge`）。記録・説明文は出さない。
private struct GameCard: View {
    let module: GameModule
    let hasResume: Bool
    /// 中断データの進み具合（「32手目」等・#2870）。「続きから」の印を出しているときだけ、その下に出す。
    var resumeProgress: String?
    /// この版の新着ゲームか（#2104）。「続きから」と同じ位置に NEW を常に出す（両方のときは NEW を優先）。
    let isNew: Bool
    /// 「イベント開催中」の印を出すか（#2566）。NEW のほうが優先で、文字の印は左下に 1 つだけ。
    let isEvent: Bool
    /// その版で中身が増えたゲームのタグ（「新ステージ追加」など・#2790）。優先順は NEW ＞ イベント ＞ 更新 ＞ 続きから。
    var updateTag: UpdateTag?
    /// 一度も遊んでいないゲームか（#2849）。NEW・イベント・続きからのどれも無いときだけ「未プレイ」を出す。
    let isUnplayed: Bool
    /// 今日の残り回数（柵越えおじさんだけ・#2208）。ボールを上限ぶん並べ、残りは白・使った分は灰色（#2273）。
    /// 「続きから」「NEW」「イベント開催中」と同じ部品（`badgeCapsule`）・同じ大きさで、文字の印と**両方**出す
    /// （#2572。横に並ばない幅では 2 段）。読み上げは「残り n 回」。
    var count: HomerunHubCount.Tally?

    @Environment(\.adaptiveLayout) private var layout

    /// 表示言語（アプリ内の言語設定）で日本語版・英語版の画像を選ぶ（#2181）。`language` は Observation で
    /// 見張られるので、設定で言語を変えた瞬間にタイルも描き直される。
    private var tileName: String {
        let language = AppLanguageStore.shared.language
        return HubTileStyle.tileName(for: module.id, language: language)
    }

    var body: some View {
        Color.clear
            .aspectRatio(HubTileStyle.aspect, contentMode: .fit)
            .overlay { art }
            .overlay(alignment: .bottomLeading) {
                badges.padding(layout.scaled(10))
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: Theme.cardShadow, radius: 5, x: 0, y: 6)
            )
            // 名前は画像の中にあるので、読み上げはここで組み立てる。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    /// 絵。アセットが無いゲーム（新しく足して絵をまだ作っていない等）は、差し色の面に名前を出して代用する。
    @ViewBuilder
    private var art: some View {
        if UIImage(named: tileName) != nil {
            Image(tileName)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(HubTileStyle.accent(for: module.id).gradient)
                .overlay(alignment: .topLeading) {
                    Text(module.title)
                        .themeTitle(layout.scaled(19), weight: .black)
                        .foregroundStyle(Theme.Fixed.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(layout.scaled(12))
                }
        }
    }

    /// 左下の印。文字の印（`badge`）と残り回数（`countBadge`）の両方があるときは、横に並ぶ幅なら 1 段
    /// （文字が左・回数が右）、並ばない幅（iPhone の 2 列）なら 2 段（文字の上に回数）にする（#2572）。
    @ViewBuilder
    private var badges: some View {
        if let count {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: layout.scaled(6)) {
                    badgeWithProgress
                    Spacer(minLength: 0)
                    countBadge(count)
                }
                VStack(alignment: .leading, spacing: layout.scaled(6)) {
                    countBadge(count)
                    badgeWithProgress
                }
            }
        } else {
            badgeWithProgress
        }
    }

    /// 「続きから」の印を出す局面か（NEW・イベントが優先）。
    private var showsResumeBadge: Bool { !isNew && !isEvent && hasResume }

    /// 文字の印。「続きから」を出しているときは、その下に進み具合の印を 1 段足す（#2870）。
    @ViewBuilder
    private var badgeWithProgress: some View {
        if showsResumeBadge, let resumeProgress {
            VStack(alignment: .leading, spacing: layout.scaled(4)) {
                badge
                badgeCapsule(resumeProgress)
            }
        } else {
            badge
        }
    }

    @ViewBuilder
    private var badge: some View {
        if isNew {
            badgeCapsule("NEW")
        } else if isEvent {
            badgeCapsule(tr("イベント開催中"))
        } else if let updateTag {
            badgeCapsule(updateTag.label)
        } else if hasResume {
            badgeCapsule(tr("続きから"))
        } else if isUnplayed {
            badgeCapsule(tr("未プレイ"))
        }
    }

    /// 残り回数のボールの印（#2208・#2273）。
    private func countBadge(_ count: HomerunHubCount.Tally) -> some View {
        badgeCapsule(ballsText(count), fill: Self.ballBadgeFill)
    }

    /// モック 01 の `.badge`（白 92% の地に、そのゲームの下線と同じ色の太字）。
    /// 文字は会長 QA（#2273）で 11pt → 14pt に上げた。「続きから」「NEW」「イベント開催中」はすべてこの 1 つの部品で、
    /// 同じ文字の大きさ・同じ余白なので高さもそろう。
    private func badgeCapsule(_ label: String) -> some View {
        badgeCapsule(Text(label).foregroundStyle(HubTileStyle.textAccent(for: module.id)), fill: Color.white.opacity(0.92))
    }

    private func badgeCapsule(_ label: Text, fill: Color) -> some View {
        label
            .themeCaption(layout.scaled(14), weight: .heavy, maxScale: 1.3)
            .padding(.horizontal, layout.scaled(11))
            .padding(.vertical, layout.scaled(5))
            .background(Capsule().fill(fill))
            .fixedSize()
    }

    /// 残り回数のボールの地。白いボールが絵の上でも見えるよう、ほかのラベルの白い地の代わりに暗い地にする。
    private static let ballBadgeFill = Color.black.opacity(0.55)
    /// 使った分のボール（灰色）。
    private static let usedBall = Color(white: 0.45)

    /// ボールを上限ぶん並べた 1 行の文字（SF Symbols を文字に埋めるので、ほかのラベルと同じ書体の大きさ・行の高さになる）。
    /// 上限が多すぎて並ばないとき（6 以上）は、打席前のボタンと同じくボール 1 つ＋「×残り」。
    private func ballsText(_ count: HomerunHubCount.Tally) -> Text {
        func ball(_ lit: Bool) -> Text {
            Text(Image(systemName: "baseball.fill")).foregroundStyle(lit ? Color.white : Self.usedBall)
        }
        guard let dots = count.dots else {
            return ball(count.remaining > 0) + Text(verbatim: " ×\(max(0, count.remaining))")
                .foregroundStyle(count.remaining > 0 ? Color.white : Self.usedBall)
        }
        return (0..<dots.total).reduce(Text(verbatim: "")) { text, i in
            text + (i == 0 ? Text(verbatim: "") : Text(verbatim: " ")) + ball(i < dots.lit)
        }
    }

    private var accessibilityLabel: String {
        var parts = [module.title]
        if hasResume { parts.append(tr("続きから")) }
        if showsResumeBadge, let resumeProgress { parts.append(resumeProgress) }
        if isNew { parts.append(tr("新着")) }
        if isEvent { parts.append(tr("イベント開催中")) }
        if let updateTag { parts.append(updateTag.label) }
        if isUnplayed { parts.append(tr("未プレイ")) }
        if let count { parts.append(count.labelText()) }
        return parts.joined(separator: tr("、"))
    }
}

/// ハブのタイルの残り回数の印（#2208・#2572）。柵越えおじさんだけ（1 日の回数がある唯一のゲーム）。
enum HubCountBadge {
    @MainActor static func isShown(gameID: String) -> Bool { gameID == HomerunModel.gameID }
}

enum HubEventBadge {
    /// 「イベント開催中」の印を出すゲームの ID。イベントを入れ替えるときはここ 1 か所だけ直す
    /// （#2958。v1.1.15 は将棋「将棋の達人に挑め」＝#2722。柵越えおじさんの週間ランキング自体は続く）。
    static let eventGameID = "shogi"

    static func isShown(gameID: String) -> Bool {
        gameID == eventGameID
    }
}

/// タイルの画像とゲームごとの差し色（#2175）。差し色は画像に描き込んだ下線の色と同じで、
/// 「続きから」「NEW」と「つづき・最近」の文字色に使う。値は `Scripts/generate-hub-tiles.py` の `GAMES` と同じ表
/// （モック 01 の各タイルの `.ul` の色）。表に無いゲームは珊瑚色。
enum HubTileStyle {
    /// モックのタイルの寸法（179 × 215pt）の比率。画像もこの比率で書き出している。
    static let aspect: CGFloat = 179.0 / 215.0

    /// 名前入りの画像。英語版は末尾に `-en`（#2181。`Scripts/generate-hub-tiles.py` の `asset_name` と同じ規則）。
    static func tileName(for gameID: String, language: AppLanguage = .japanese) -> String {
        localized("hubtile-\(gameID)", language)
    }
    static func thumbName(for gameID: String) -> String { "hubthumb-\(gameID)" }

    private static func localized(_ name: String, _ language: AppLanguage) -> String {
        language == .japanese ? name : "\(name)-\(language.rawValue)"
    }

    private static let coral: UInt32 = 0xFF6F61, teal: UInt32 = 0x22C3BE, purple: UInt32 = 0x8C7BE0
    private static let yellow: UInt32 = 0xFFC24B, pink: UInt32 = 0xFF8FB1
    private static let accentHex: [String: UInt32] = [
        "homerun": purple, "poker": coral, "solitaire": teal, "runner": purple, "mahjong4": yellow,
        "sudoku": pink, "othello": coral, "2048": teal, "shogi": purple, "shiritori": yellow,
        "daifugo": pink, "gomoku": coral, "minesweeper": teal, "spider": purple, "blackjack": yellow,
        "mahjong": pink, "hanafuda": coral, "go": teal, "blocks": purple, "concentration": yellow,
        "chess": pink, "freecell": coral, "fifteen": teal, "ojisanpuzzle": yellow, "anzan": coral,
        "colorrelay": purple, "fruits": teal, "dicecombo": pink, "catpuzzle": teal,
        "speed": teal, "oldmaid": purple, "hearts": coral,
    ]

    static func accent(for gameID: String) -> Color { Color(hex: accentHex[gameID] ?? coral) }

    /// 白い地に載せる文字（「続きから」「NEW」「つづきから」）の色。黄・桃・青緑は白地では薄くて読めないので、
    /// 同じ色相のまま濃くした値を使う（珊瑚・紫はモックの文字色そのまま）。
    static func textAccent(for gameID: String) -> Color {
        let hex = accentHex[gameID] ?? coral
        let dark: [UInt32: UInt32] = [yellow: 0xB7791F, pink: 0xD9467A, teal: 0x14918D]
        return Color(hex: dark[hex] ?? hex)
    }
}

/// カテゴリーを選んだときの見出し（モック 04b の「トランプ　7本」: 名前 15pt・本数 12pt の補助色）。
private struct HubCategoryHeading: View {
    let title: String
    let count: Int

    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(title)
                .themeBody(layout.scaled(15), weight: .black)
                .foregroundStyle(Theme.ink)
            Text(verbatim: "\u{3000}")
                .themeBody(layout.scaled(15), weight: .black)
            Text(tr("%d本", count))
                .themeCaption(layout.scaled(12), weight: .heavy)
                .foregroundStyle(Theme.inkSubText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// カテゴリーのチップの行（#1831）。モック 04b の `.chips`（白地・選択中は濃い茶の地に白文字）。
/// 画面幅を超えるときは横にスクロールする。
///
/// 会長 QA（#2184「ボタンとして小さく、指で押すと誤タップする」）で、モックの大きさ（12pt・高さ約 29pt・間隔 8pt）から
/// 文字 14pt・見た目の高さ 36pt・間隔 12pt に大きくした。押せる範囲は Apple のヒューマンインターフェイスガイドラインの
/// 最小値 44×44pt 以上（https://developer.apple.com/design/human-interface-guidelines/accessibility#Buttons-and-controls）。
private struct HubCategoryChips: View {
    let categories: [HubCategory]
    let selected: HubCategory
    let onSelect: (HubCategory) -> Void

    /// 押せる範囲の最小の高さ（HIG の最小値）。
    static let minHitHeight: CGFloat = 44

    /// 見た目のチップの高さ。iPad は 1.5 倍（54pt）になり、そのまま 44pt を超える。
    static func chipHeight(_ layout: AdaptiveLayout) -> CGFloat { layout.scaled(36) }

    /// 見た目のチップを 44pt の当たり判定に広げたときの、上下それぞれのはみ出し（iPhone 4pt・iPad 0pt）。
    static func hitSlop(_ layout: AdaptiveLayout) -> CGFloat { max(0, (minHitHeight - chipHeight(layout)) / 2) }

    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: layout.scaled(12)) {
                ForEach(categories, id: \.self) { category in
                    let isSelected = category == selected
                    Button { onSelect(category) } label: {
                        Text(category.title)
                            .themeCaption(layout.scaled(14), weight: .heavy, maxScale: 1.4)
                            .foregroundStyle(isSelected ? Theme.background : Theme.ink)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, layout.scaled(16))
                            .frame(minWidth: Self.minHitHeight, minHeight: Self.chipHeight(layout))
                            .background(
                                Capsule()
                                    .fill(isSelected ? Theme.ink : Theme.surface)
                                    .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 3)
                            )
                            .frame(minHeight: Self.minHitHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pop)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.pad)
        }
        .scrollClipDisabled()
    }
}

/// 表示するゲームが 0 本のときにハブへ出す案内と、設定を開くボタン（#2002）。
private struct HubEmptyStateView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(HubEmptyState.message)
                .themeCaption(15)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Button(action: openSettings) {
                Text(HubEmptyState.buttonTitle).foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.Fill.coral)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.pad)
        .popCard(corner: Theme.cornerSmall)
        .accessibilityElement(children: .contain)
    }
}

/// カードを長押しメニューで非表示にした直後の案内（#662）。「元に戻す」で取り消せる（#2047）。
///
/// 案内の文言は `HubView.hide` が同じ文言をアナウンスで流すため、VoiceOver からは隠す（二重に読ませない）。
/// 「元に戻す」ボタンだけは VoiceOver で辿れる。
private struct HubHiddenNotice: View {
    let title: String
    let onUndo: () -> Void
    /// 支援技術中は自動で消えないため、VoiceOver の「戻る」ジェスチャ（二本指のスクラブ）で閉じられるようにする（#2330）。
    let onDismiss: () -> Void

    static func message(title: String) -> String {
        tr("「%@」を非表示にしました。元に戻せます", title)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(tr("「%@」を非表示にしました", title))
                .themeCaption(13)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            Button(action: onUndo) {
                Text(tr("元に戻す"))
                    .themeCaption(13)
                    .fontWeight(.bold)
                    .underline()
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pop)
            .accessibilityLabel(tr("「%@」の非表示を元に戻す", title))
        }
        .padding(.horizontal, Theme.pad)
        .popCard(corner: Theme.cornerSmall)
        .padding(Theme.pad)
        .accessibilityAction(.escape, onDismiss)
    }
}
