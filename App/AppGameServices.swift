import Foundation
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

/// アプリ本体が組み立てる GameServices の実体。
/// MVP: 永続化 = FileSnapshotStore、広告 = NoopAdService（M5 で AdMob に差し替え）。
@MainActor
enum AppEnvironment {
    static let services = GameServices(
        snapshots: FileSnapshotStore(),
        ads: isScreenshotMode ? NoopAdService() : AdMobAdService(),
        // 触覚と効果音は同じ発火点に相乗りさせ、オン / オフだけを別々に見る（#116）。
        feedback: CompositeFeedbackService([
            GatedFeedbackService(base: HapticFeedbackService()) { settings.hapticsEnabled },
            GatedFeedbackService(base: SoundFeedbackService()) { settings.soundEnabled },
        ]),
        recommendations: recommendations,
        review: review,
        playLog: playLog,
        analytics: analytics
    )

    /// 解析イベント（#158）。送るのは `game_start` / `game_end` の2種だけ。
    /// 設定でオフにすると `GatedAnalyticsService` が Firebase へ渡さない。
    /// 撮影モードは広告と同じ理由で送信そのものを止める（動作確認の操作を実データに混ぜない）。
    static let analytics = GameAnalytics(
        service: GatedAnalyticsService(
            base: isScreenshotMode ? NoopAnalyticsService() : FirebaseAnalyticsService()
        ) { settings.analyticsEnabled },
        // ハブに登録済みのゲーム ID だけを送信対象にする（未知の文字列が game_id にならない）。
        allowedGameIDs: Set(registry.modules.map(\.id))
    )

    /// 設定の「利用状況の送信」を **Firebase SDK 全体の収集状態**へ反映する。
    ///
    /// `GatedAnalyticsService` は `game_start` / `game_end` しか止められないため、これを呼ばないと
    /// オフにしても自動収集イベント（`session_start` 等）が送られ続け、設定画面の説明と食い違う。
    /// 起動直後（`FirebaseApp.configure()` の後）と、トグルを切り替えたときに呼ぶ。
    static func applyAnalyticsCollectionState() {
        // 撮影モードは広告と同じ理由で送信そのものを止める（動作確認の操作を実データに混ぜない）。
        FirebaseAnalyticsService.setCollectionEnabled(!isScreenshotMode && settings.analyticsEnabled)
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

    /// ハブに並べるゲーム群。新ゲームはここに 1 行追加するだけ。
    /// 並び順 = 新規インストール時の既定表示順（会長判断・2026-08-24）。ゲーム数が増えて
    /// 1画面で全ては見渡せなくなったため、五目並べ・神経衰弱を下へ、麻雀（4人打ち）を上へ寄せた。
    /// 既にアプリを使っている人の並びには影響しない（`GameSettings` はユーザーの並び替えを
    /// 優先し、ここは「まだ並び替えたことがない人」の初期値だけを決める）。
    static let registry = GameRegistry([
        Game2048Module(),
        ShogiModule(),
        MahjongModule(),
        OthelloModule(),
        MahjongSolitaireModule(),
        DaifugoModule(),
        PokerModule(),
        BlackjackModule(),
        MinesweeperModule(),
        GomokuModule(),
        ConcentrationModule(),
    ])

    static let settings = GameSettings(registeredIDs: registry.modules.map(\.id))
}
