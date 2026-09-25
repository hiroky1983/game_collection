import Foundation
import GameKit
import Core
import Game2048
import GameShogi
import GameGomoku
import GameMinesweeper
import GameOthello
import GamePoker
import GameConcentration
import GameBlackjack
import GameDaifugo
import GameMahjongSolitaire
import GameMahjong
import GameSudoku
import GameGo
import GameSolitaire
import GameChess
import GameBlocks
import GameFreeCell
import GameRunner
import GameHanafuda
import GameSpider
import GameShiritori
import GameFifteen
import GameRoulette
import GameFruits
import GameColorRelay
import GameAnzan
import GameBackgammon
import GameSpeed
// GameBlockPuzzle は import しない（#642 で v1.1.4 のハブから外したまま、#603 の差し替え判断が
// 続いているため v1.1.5 でも戻さない。コード自体は残っているので、戻す判断が出たら
// `registry` に1行足せば復活できる）。

/// アプリ本体が組み立てる GameServices の実体。
/// MVP: 永続化 = FileSnapshotStore、広告 = NoopAdService（M5 で AdMob に差し替え）。
@MainActor
enum AppEnvironment {
    static let services = GameServices(
        // 中断データの消去（終局・やり直し・設定の切り替え）を横で捕まえ、そのゲームの
        // お知らせを取り消す（#663）。保存形式と読み書きは `FileSnapshotStore` のまま。
        snapshots: ClearObservingSnapshotStore(base: FileSnapshotStore()) { gameID in
            // 消去は UI 起点の主スレッドで起きる。そうでない呼び出しだけ主スレッドへ回す。
            if Thread.isMainThread {
                MainActor.assumeIsolated { reminders.snapshotDidClear(gameID: gameID) }
            } else {
                Task { @MainActor in reminders.snapshotDidClear(gameID: gameID) }
            }
        },
        ads: isScreenshotMode ? NoopAdService() : AdMobAdService(),
        // 触覚と効果音は同じ発火点に相乗りさせ、オン / オフだけを別々に見る（#116）。
        feedback: CompositeFeedbackService([
            GatedFeedbackService(base: HapticFeedbackService()) { settings.hapticsEnabled },
            GatedFeedbackService(base: SoundFeedbackService()) { settings.soundEnabled },
        ]),
        recommendations: recommendations,
        review: review,
        playLog: playLog,
        analytics: analytics,
        gameCenter: gameCenter,
        reminders: reminders,
        reengagement: reengagement
    )

    /// 中断したゲームのお知らせ（#663）。中断データを持ってハブへ戻ったときだけ、1 日ほど後に予約する。
    /// 撮影モードと DEBUG ビルドでは予約しない（撮影・開発中の動作確認の端末に溜めない）。
    static let reminders = ResumeReminderService(
        scheduler: UserNotificationReminderScheduler(),
        isEnabled: { settings.notificationsEnabled },
        isSuppressed: isScreenshotMode || isDebugBuild,
        // 通知に出すゲーム名。中断データから局を復元しないゲーム（チャリンコおじさん）は対象外。
        // 設定で非表示にしたゲームも、ハブの他の導線（レコメンド・最近遊んだ）と同じく対象外（#810）。
        // タップ時もここで弾くので、非表示のゲームへは遷移しない。
        reminderTitle: { gameID in
            guard let module = registry.module(id: gameID), module.resumesFromSnapshot else { return nil }
            guard !settings.hiddenIDs.contains(gameID) else { return nil }
            return module.title
        }
    )

    /// よく遊んでいたのに最近開いていないゲームへの再エンゲージメント通知（#1193）。
    /// アプリがバックグラウンドに入るたびに対象を判定し直す（`GameCollectionApp` から呼ぶ）。
    /// 撮影モードと DEBUG ビルドでは予約しない（#663 と同じ理由）。
    static let reengagement = ReengagementReminderService(
        scheduler: UserNotificationReengagementScheduler(),
        isEnabled: { settings.reengagementRemindersEnabled },
        isSuppressed: isScreenshotMode || isDebugBuild,
        // #663 と異なり「中断データから局を復元できるか」は問わない。設定で非表示にしたゲームだけ除く。
        reminderTitle: { gameID in
            guard let module = registry.module(id: gameID) else { return nil }
            guard !settings.hiddenIDs.contains(gameID) else { return nil }
            return module.title
        }
    )

    /// 再エンゲージメント通知（#1193）の対象判定に渡す、登録ゲームぶんの通算プレイ回数・最終プレイ日時。
    static func reengagementCandidateInputs() -> [ReengagementCandidateInput] {
        let plays = playLog.totalPlaysByGame
        let lastPlayedAt = playLog.lastPlayedAtByGame
        return registry.modules.map { module in
            ReengagementCandidateInput(gameID: module.id, plays: plays[module.id] ?? 0, lastPlayedAt: lastPlayedAt[module.id])
        }
    }

    /// Game Center のリーダーボード・実績（#289 段階②③）。
    /// **未サインイン**では `isAvailable` が false になり、送信そのものが起きない。
    /// サインイン済みのままオフラインになった場合は送信を試みるが、投げっぱなしなので
    /// ゲームの進行は待たされない（失敗した実績は次の決着で送り直す）。
    /// 撮影モードは広告・解析と同じ理由で止める（動作確認の記録を実データに混ぜない）。
    static let gameCenter = GameCenterReporter(
        service: isScreenshotMode ? NoopGameCenterService() : AppGameCenterService(),
        // ハブに登録済みのゲーム ID だけを対象にする（`analytics` と同じ方針）。
        // 実績「全ゲームを 1 回ずつ遊ぶ」の分母もこの件数になる。
        allowedGameIDs: Set(registry.modules.map(\.id)),
        isAvailable: { GKLocalPlayer.local.isAuthenticated }
    )

    /// 解析イベント（#158）。送るイベントの全量は `AnalyticsEvent`（`game_start` には #1195 で遊び込み具合を載せる）。
    /// 設定でオフにすると `GatedAnalyticsService` が Firebase へ渡さない。
    /// 撮影モードは広告と同じ理由で送信そのものを止める（動作確認の操作を実データに混ぜない）。
    static let analytics = GameAnalytics(
        service: GatedAnalyticsService(
            base: isScreenshotMode ? NoopAnalyticsService() : FirebaseAnalyticsService()
        ) { settings.analyticsEnabled },
        // ハブに登録済みのゲーム ID だけを送信対象にする（未知の文字列が game_id にならない）。
        allowedGameIDs: Set(registry.modules.map(\.id)),
        // `game_start` に「そのゲームの通算プレイ回数・前回からの経過日数」を載せる（#1195）。
        engagement: { gameID, now in playLog.engagement(gameID: gameID, now: now) }
    )

    /// 設定の「利用状況の送信」を **Firebase SDK 全体の収集状態**へ反映する。
    ///
    /// `GatedAnalyticsService` は `game_start` / `game_end` しか止められないため、これを呼ばないと
    /// オフにしても自動収集イベント（`session_start` 等）が送られ続け、設定画面の説明と食い違う。
    /// 起動直後（`FirebaseApp.configure()` の後）と、トグルを切り替えたときに呼ぶ。
    /// `Info.plist` 側で収集を既定オフにしてあるため、ここは「許可された経路で ON を立てる」役割で、
    /// 呼ばれるまでの一瞬に自動収集イベントが漏れることはない（#382）。
    static func applyAnalyticsCollectionState() {
        // 撮影モードに加え、開発ビルド（シミュレータ・Xcode 実行）も送信そのものを止める（#347）。
        // 8月の計測初データが内部トラフィックで埋まり実ユーザー指標として読めなくなったため、
        // debug は送らない・TestFlight は build_channel で分別・App Store 版は現状どおり、と分ける。
        let isAllowedChannel = BuildChannel.current != .debug
        FirebaseAnalyticsService.setCollectionEnabled(
            !isScreenshotMode && isAllowedChannel && settings.analyticsEnabled
        )
        // 配布経路をユーザープロパティで付与し、GA4 側で実ユーザー（appstore）だけを
        // 抽出できるようにする（#347 案A相当。収集オフのビルドでは SDK が送らないだけなので常に設定する）。
        FirebaseAnalyticsService.setBuildChannel(BuildChannel.current.rawValue)
    }

    /// プレイ履歴（回数カウンタ・遊んだゲームの ID・ゲーム別の記録。盤面や棋譜は持たない）。
    static let playLog = PlayLog()

    /// ゲーム間レコメンド。候補はハブに並んでいるゲーム（非表示を除く）に限る。
    static let recommendations = RecommendationService(
        log: playLog,
        availableModules: { settings.visibleModules(from: registry) }
    )

    /// 評価リクエスト。勝った直後にだけ、生涯で1〜2回だけ聞く（条件は `ReviewRequestPolicy`）。
    /// バージョンごとに1回までのため、`CFBundleShortVersionString` を判定に使う。
    static let review = ReviewRequestService(log: playLog, appVersion: shortVersion)

    /// App Store の商品ページ。設定の「アプリをシェア」と、リザルトの記録の共有（#1043）が添える URL。
    /// キャンペーンのパラメータは付けない（付けるには ASC の Campaign Link の設定が要る・#1043）。
    static let appStoreURL = URL(string: "https://apps.apple.com/jp/app/id6781719499")!

    /// 表示用のバージョン番号（例 "1.1.1"）。取れなければ判定を止めないよう "0" を使う。
    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// App Store 用スクリーンショットの撮影モード（**DEBUG ビルドのみ有効**）。
    /// `-screenshotMode` 付きで起動すると広告を出さず ATT も聞かない。
    /// シミュレータは AdMob 側で自動的にテストデバイス扱いになり、Release ビルドでも
    /// バナーに `Test mode` の帯が写り込むため、撮影時は広告そのものを無効化する。
    static var isScreenshotMode: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-screenshotMode")
        #else
        return false
        #endif
    }

    /// DEBUG ビルドか。
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// ハブに並べるゲーム群。新ゲームはここに 1 行追加するだけ。
    /// 並び順 = 新規インストール時の既定表示順。2026-09-23〜09-25 の GA4 実績から出したスコア順
    /// （プレイ時間 50%・プレイ回数 25%・プレイ人数 25%。各指標を収録20本の中での順位パーセンタイルに
    /// 直して重み付け）を基本に、会長の手動配置として チャリンコおじさん を 3位、四人打ち麻雀 を 4位、
    /// カードしりとり を 9位、15パズル を最後に置いている（#1014・会長決裁 2026-09-25）。
    /// ナンプレを上位に置く方針（国内の検索需要が最大級・#355 会長決裁 2026-08-31）はスコア順でも満たしている。
    /// 既にアプリを使っている人の並びには影響しない（`GameSettings` はユーザーの並び替えを
    /// 優先し、ここは「まだ並び替えたことがない人」の初期値だけを決める）。
    static let registry = GameRegistry([
        PokerModule(),
        SolitaireModule(),
        RunnerModule(),
        MahjongModule(),
        SudokuModule(),
        OthelloModule(),
        Game2048Module(),
        ShogiModule(),
        ShiritoriModule(),
        DaifugoModule(),
        GomokuModule(),
        MinesweeperModule(),
        SpiderModule(),
        BlackjackModule(),
        MahjongSolitaireModule(),
        HanafudaModule(),
        GoModule(),
        BlocksModule(),
        ConcentrationModule(),
        ChessModule(),
        FreeCellModule(),
        FifteenModule(),
        // ルーレット（企画倉庫・#1318）。出荷する版が決まるまでハブには並べない
        // （`docs/ai-devops.md`「新ゲームの企画〜倉庫〜リリースの流れ」。`#if DEBUG` では分岐しない）。
        // 出荷を決める Issue でこの行のコメントアウトを外し、`web/app/lib/games.ts` にも同じ順で足す。
        // RouletteModule(),
        // くっつきフルーツ（企画倉庫・#1319）。ルーレットと同じ扱いで、出荷する版が決まるまでハブには並べない。
        // 出荷を決める Issue でこの行のコメントアウトを外し、`web/app/lib/games.ts` にも同じ順で足す。
        // FruitsModule(),
        // いろリレー（企画倉庫・#1320）。ルーレット・くっつきフルーツと同じ扱いで、出荷する版が決まるまでハブには並べない。
        // 出荷を決める Issue でこの行のコメントアウトを外し、`web/app/lib/games.ts` にも同じ順で足す。
        // ColorRelayModule(),
        // ぱっと暗算（企画倉庫・#1321）。上の 3 本と同じ扱いで、出荷する版が決まるまでハブには並べない。
        // 出荷を決める Issue でこの行のコメントアウトを外し、`web/app/lib/games.ts` にも同じ順で足す。
        // AnzanModule(),
        // バックギャモン（企画倉庫・#1322）。上の 4 本と同じ扱いで、出荷する版が決まるまでハブには並べない。
        // 出荷を決める Issue でこの行のコメントアウトを外し、`web/app/lib/games.ts` にも同じ順で足す。
        // BackgammonModule(),
        // スピード（企画倉庫・#1323）。上の 5 本と同じ扱いで、出荷する版が決まるまでハブには並べない。
        // 出荷を決める Issue でこの行のコメントアウトを外し、`web/app/lib/games.ts` にも同じ順で足す。
        // SpeedModule(),
    ])

    static let settings = GameSettings(registeredIDs: registry.modules.map(\.id))
}
