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

    // MARK: 柵越えおじさんの特別枠（#1761）

    /// 特別枠に出すゲーム。グリッドの通常カードからは外し、**登録されていて非表示にされていないときだけ**出す
    /// （非公開のままなら registry に居ないので何も変わらない）。
    private static let heroGameID = "homerun"

    private var showsHero: Bool {
        settings.visibleModules(from: registry).contains { $0.id == Self.heroGameID }
    }

    /// 表示するゲームの並び。この版の新着を先頭に固定し、そのあとに利用者の並びが続く（#2104）。
    /// 非表示にしたゲームは `visibleModules` の時点で除かれるので、新着でも出さない。
    private var pinnedVisibleModules: [GameModule] {
        let visible = settings.visibleModules(from: registry)
        let order = NewGames.pinned(visibleIDs: visible.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        return order.compactMap { byID[$0] }
    }

    /// グリッドに並べるゲーム（特別枠のゲームを除く）。特別枠のすぐ次に新着が来る。
    private var gridModules: [GameModule] {
        pinnedVisibleModules.filter { $0.id != Self.heroGameID }
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

    /// カテゴリーで絞ったあとにグリッドへ並べるゲーム。位置（`game_open` の `position`）は絞る前の
    /// 並びでの 1 始まり（絞り込みの有無で同じゲームの位置が変わらない）。
    private var shownGridEntries: [(position: Int, module: GameModule)] {
        let entries = Array(gridModules.enumerated()).map { (position: $0.offset + 1, module: $0.element) }
        guard activeCategory != .all else { return entries }
        return entries.filter { registry.category(of: $0.module.id) == activeCategory }
    }

    /// 特別枠（柵越えおじさん）を出すか。「すべて」と「おじさん」のときだけ。
    private var showsHeroInCategory: Bool {
        showsHero && (activeCategory == .all || registry.category(of: Self.heroGameID) == activeCategory)
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

    /// NEW 印と1行の対象。非表示にしたゲームは数えない。
    private var visibleNewGameIDs: Set<String> {
        newGameIDs.intersection(settings.visibleModules(from: registry).map(\.id))
    }

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
                // 更新で増えたゲームがあるときだけ、その回の起動で1行出す（#723）。数え方は `NewGames` が持つ。
                // 置き場所は「つづき・最近」と同じくスクロール領域の外（#485）。
                if let notice = NewGames.notice(count: visibleNewGameIDs.count) {
                    HubNewGamesNotice(message: notice)
                        .padding(.horizontal, Theme.pad)
                        .padding(.top, Theme.pad)
                }
                // 連続プレイ日数（#1625）。2 日以上のときだけ控えめに 1 行。`PlayLog` は監視対象ではないので、
                // ゲームから戻って `path` が変わったとき body が走って更新される（「つづき・最近」と同じ）。
                if let text = PlayDayStreak.hubText(streak: services.playLog?.playStreak() ?? 0) {
                    HubPlayStreakLine(text: text)
                        .padding(.horizontal, Theme.pad)
                        .padding(.top, Theme.pad)
                }
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
                // カテゴリーのチップ（#1831）。「つづき」と同じくスクロール領域の外に置き、常に見える。
                if !chipCategories.isEmpty {
                    HubCategoryChips(categories: chipCategories, selected: activeCategory) { category in
                        withGameAnimation(.easeOut(duration: 0.2)) { selectedCategory = category }
                    }
                    .padding(.top, Theme.pad)
                }
                ScrollView {
                    VStack(spacing: Self.gridSpacing) {
                    // 全ゲームを非表示にした直後は空白にせず、設定へ戻る導線を出す（#2002）。
                    if HubEmptyState.isShown(visibleGameIDs: settings.visibleModules(from: registry).map(\.id)) {
                        HubEmptyStateView { showSettings = true }
                    }
                    // 特別枠（#1761）: グリッドの先頭に 1 枚ぶち抜きで置き、スクロールで一緒に流れる。
                    if showsHeroInCategory, let hero = registry.module(id: Self.heroGameID) {
                        NavigationLink(value: HubRoute(
                            gameID: hero.id, source: .hero, position: nil,
                            resume: isResumable(hero.id)
                        )) {
                            HomerunHubHeroCard(description: hero.description)
                        }
                        .buttonStyle(.pop)
                        // 幅の上限は iPad の高さの頭打ち用（`AdaptiveLayout.hubHeroMaxWidth`）。上限より広ければ中央に置く。
                        .frame(maxWidth: AdaptiveLayout.hubHeroMaxWidth)
                        .frame(maxWidth: .infinity)
                        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        // 常に先頭なので「いちばん上に置く」は出さない。非表示にすると特別枠ごと消える（設定から戻せる）。
                        .contextMenu {
                            Button {
                                hide(hero)
                            } label: {
                                Label("非表示にする", systemImage: "eye.slash")
                            }
                        }
                    }
                    LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                        ForEach(shownGridEntries, id: \.module.id) { entry in
                            let module = entry.module
                            // 差し色は絞る前の並びの位置で引く（チップで絞っても同じゲームは同じ色）。
                            let index = entry.position - 1
                            let hasResume = isResumable(module.id)
                            // 位置は並べ替え設定を反映した**見えている順**の 1 始まり（#659）。
                            NavigationLink(value: HubRoute(
                                gameID: module.id, source: .hub, position: entry.position, resume: hasResume
                            )) {
                                GameCard(
                                    module: module,
                                    accent: Theme.palette[index % Theme.palette.count],
                                    accentFill: Theme.Fill.palette[index % Theme.Fill.palette.count],
                                    hasResume: hasResume,
                                    isNew: NewGames.currentVersionIDs.contains(module.id),
                                    record: services.playLog?.summaryLine(gameID: module.id)
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
                                // 先頭かどうかは非表示も含む並びで、新着の固定（#2104）を踏まえて見る（#2124）。
                                // 表示中の先頭でも、前に非表示のゲームがあれば動かす余地がある。
                                .disabled(NewGames.isAlreadyAtTop(
                                    id: module.id, orderedIDs: settings.orderedIDs, hiddenIDs: settings.hiddenIDs))
                                Button {
                                    hide(module)
                                } label: {
                                    Label("非表示にする", systemImage: "eye.slash")
                                }
                            }
                        }
                    }
                    }
                    .padding(Theme.pad)
                }
                .overlay(alignment: .bottom) {
                    Group {
                        if let hiddenNotice {
                            HubHiddenNotice(title: hiddenNotice.title) { undoHide(hiddenNotice) }
                                .transition(.opacity)
                        }
                    }
                    .gameAnimation(.easeOut(duration: 0.2), value: hiddenNotice)
                }
                .task(id: hiddenNotice) {
                    guard hiddenNotice != nil else { return }
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    hiddenNotice = nil
                }
                BannerSlot(ads: services.ads)
            }
            .popBackground()
            .navigationTitle("あそびば")
            // 大タイトルは右のボタンより一段下に出て、見出しの領域が縦に広かった（#2028）。
            // inline にして、タイトルを左の toolbar に置き、右のボタンと同じ行の上合わせにそろえる。
            // 標準の中央タイトルは二重にならないよう外す（iOS 26 以降。それ以前の inline は文字が中央に残る）。
            .navigationBarTitleDisplayMode(.inline)
            .hubHidesDefaultTitle()
            .toolbar {
                HubTitleToolbarItem()
                // きろく（#669）。以前は Game Center を直接開いていた（#334）が、未サインインだと案内で
                // 終わって手元の記録を見る場所が無かったため、アプリ内の画面に付け替えた。
                // Game Center はその画面の中のボタンから開く。歯車より左の位置は変えない。
                ToolbarItem(placement: .primaryAction) {
                    Button { showRecords = true } label: {
                        Image(systemName: "trophy.fill")
                            .scaledFont(18, weight: .semibold)
                    }
                    .accessibilityLabel("きろく")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .scaledFont(18, weight: .semibold)
                    }
                    // アイコンだけのボタンは VoiceOver がシンボル名を読む（#716）。
                    .accessibilityLabel("設定")
                }
            }
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
                }
            }
            // ゲーム画面を出したままホームボタン・アプリ切替で離れる中断にも続きのお知らせを予約し、
            // 前面へ戻ったら取り消す（#1951）。予約だけを行い、離脱計測（`gameDidLeave`）は呼ばない。
            .onChange(of: scenePhase) { _, phase in
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
                }
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
                    for type: FeedbackNotice in [.success, .warning, .error, .milestone] {
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
            anchor.alert("Game Center にサインインしていません", isPresented: $showGameCenterSignInGuidance) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("iPhone の「設定」＞「Game Center」からサインインすると、実績と世界のランキングを見られます。サインインしなくても、あそびはすべてそのまま遊べます。")
            }
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
        AccessibilityNotification.Announcement("「\(notice.title)」を元に戻しました").post()
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

/// ハブのゲームタイル（2列グリッド・#119、絵のタイルは #1831）。
///
/// 上に絵（1 ゲーム 1 枚・アセット `hubtile-<id>`）、下にゲーム名と 1 行。名前は絵に描き込まず、
/// アプリの文字で出す（英語化のとき文字だけ差し替えるため）。「続きから」「NEW」は絵の右上に重ねる。
/// 絵のアセットが無いゲームは、従来のアイコンチップの色面で代用する。
private struct GameCard: View {
    let module: GameModule
    /// 「続きから」バッジの**文字色**。明るい地の上に置くので差し色そのままを使う。
    let accent: Color
    /// 絵が無いときのアイコン面の**面色**。上に白ではなく `Theme.onAccent` を載せる（#220）。
    let accentFill: Color
    let hasResume: Bool
    /// この版の新着ゲームか（#2104）。「続きから」と同じ位置に NEW を常に出す（両方のときは NEW を優先）。
    let isNew: Bool
    /// プレイ記録の 1 行（#115）。まだ記録が無ければ nil で、その場合はゲームの説明を出す。
    let record: String?

    /// 固定 pt の部品（文字・余白）を広い画面で拡大するための倍率（#458）。狭い画面では恒等。
    @Environment(\.adaptiveLayout) private var layout

    /// 絵の縦横比（幅 ÷ 高さ）。アセットは 4:3。
    private static let artAspect: CGFloat = 4.0 / 3.0

    var body: some View {
        VStack(alignment: .leading, spacing: layout.scaled(6)) {
            art
                .overlay(alignment: .topTrailing) { badge.padding(layout.scaled(4)) }

            VStack(alignment: .leading, spacing: layout.scaled(2)) {
                Text(module.title)
                    .themeTitle(layout.scaled(16))
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
            .padding(.horizontal, layout.scaled(4))
            .padding(.bottom, layout.scaled(2))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(layout.scaled(6))
        .popCard()
        // 「続きから」バッジを絵の右上に置いたため、既定の読み上げ順ではゲーム名より先に
        // 読まれてしまう。カードを 1 要素にまとめ、必ずゲーム名から読ませる。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// 絵。幅は親（グリッドの列）が決め、高さは比率で決まる。`Color.clear` を土台にして、
    /// 絵そのものの理想サイズに列幅が引きずられないようにする。
    private var art: some View {
        Color.clear
            .aspectRatio(Self.artAspect, contentMode: .fit)
            .overlay {
                if UIImage(named: Self.assetName(for: module.id)) != nil {
                    Image(Self.assetName(for: module.id))
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(accentFill.gradient)
                        .overlay {
                            module.icon
                                .font(.system(size: layout.scaled(34), weight: .bold)) // fixed-size: 絵の代わりの面に収めるアイコン。面の寸法は比率で決まるため固定 pt で足りる
                                .foregroundStyle(Theme.onAccent)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: layout.scaled(Theme.cornerSmall), style: .continuous))
    }

    /// 絵のアセット名。`Scripts/generate-hub-tiles.py` が `hubtile-<game_id>` で書き出す。
    static func assetName(for gameID: String) -> String { "hubtile-\(gameID)" }

    @ViewBuilder
    private var badge: some View {
        if isNew {
            badgeCapsule("NEW")
        } else if hasResume {
            badgeCapsule("続きから")
        }
    }

    /// 「続きから」と NEW は同じ部品・同じ配色（#220 のコントラスト確認済みの組み合わせ）。絵の上でも
    /// 読めるよう、薄い差し色の下に白の地を敷く。
    private func badgeCapsule(_ label: String) -> some View {
        Text(label)
            .themeCaption(layout.scaled(11))
            .foregroundStyle(accent)
            .padding(.horizontal, layout.scaled(8))
            .padding(.vertical, layout.scaled(3))
            .background(Capsule().fill(Color.white))
            .background(Capsule().fill(accent.opacity(0.15)))
            .fixedSize()
    }

    private var accessibilityLabel: String {
        var parts = [module.title, record ?? module.description]
        if hasResume { parts.append("続きから") }
        if isNew { parts.append("新着") }
        return parts.joined(separator: "、")
    }
}

/// カテゴリーのチップの行（#1831）。画面幅を超えるときは横にスクロールする。
/// チップは 44pt の高さを枠の中に取る（枠の外へはみ出させても当たり判定は広がらない）。
private struct HubCategoryChips: View {
    let categories: [HubCategory]
    let selected: HubCategory
    let onSelect: (HubCategory) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    let isSelected = category == selected
                    Button { onSelect(category) } label: {
                        Text(category.title)
                            .themeCaption(14)
                            .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .frame(minWidth: 64, minHeight: 44)
                            .background(Capsule().fill(isSelected ? Theme.Fill.coral : Color.white))
                            .overlay(Capsule().strokeBorder(Theme.ink.opacity(isSelected ? 0 : 0.15), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pop)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.pad)
        }
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
            Button(HubEmptyState.buttonTitle, action: openSettings)
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

/// 更新で増えたゲームがあるときだけハブ上部に出す1行（#723）。
///
/// 閉じるボタンは置かない。この起動のあいだだけ出て、次の起動では `PlayLog` が同じゲームを
/// 「増えた」と返さないので自然に消える。
private struct HubNewGamesNotice: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "sparkles")
            .themeCaption(13)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.pad)
            .padding(.vertical, 10)
            .popCard(corner: Theme.cornerSmall)
            .accessibilityElement(children: .combine)
    }
}

/// 連続プレイ日数の 1 行（#1625）。カードにはせず、文字だけで控えめに出す。報酬・広告・通知には繋げない。
private struct HubPlayStreakLine: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "flame.fill")
            .themeCaption(13)
            .foregroundStyle(Theme.inkSub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

/// カードを長押しメニューで非表示にした直後の案内（#662）。「元に戻す」で取り消せる（#2047）。
///
/// 案内の文言は `HubView.hide` が同じ文言をアナウンスで流すため、VoiceOver からは隠す（二重に読ませない）。
/// 「元に戻す」ボタンだけは VoiceOver で辿れる。
private struct HubHiddenNotice: View {
    let title: String
    let onUndo: () -> Void

    static func message(title: String) -> String {
        "「\(title)」を非表示にしました。元に戻せます"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("「\(title)」を非表示にしました")
                .themeCaption(13)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            Button(action: onUndo) {
                Text("元に戻す")
                    .themeCaption(13)
                    .fontWeight(.bold)
                    .underline()
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pop)
            .accessibilityLabel("「\(title)」の非表示を元に戻す")
        }
        .padding(.horizontal, Theme.pad)
        .popCard(corner: Theme.cornerSmall)
        .padding(Theme.pad)
    }
}

private extension View {
    /// 標準の（中央の）ナビゲーションタイトルを隠す。iOS 26 未満では何もしない。
    @ViewBuilder
    func hubHidesDefaultTitle() -> some View {
        if #available(iOS 26.0, *) {
            toolbar(removing: .title)
        } else {
            self
        }
    }
}

/// 左上に置くハブの見出し。iOS 26 の toolbar 項目に付くガラスの丸い背景は、文字には付けない。
private struct HubTitleToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { title }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { title }
            // 標準の中央タイトルは principal を空にして隠す（`toolbar(removing:)` は iOS 26 から）。
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
        }
    }

    private var title: some View {
        Text("あそびば")
            .scaledFont(28, weight: .heavy, maxScale: 1.3)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }
}
