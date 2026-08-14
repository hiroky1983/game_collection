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
        playLog: playLog
    )

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
    static let registry = GameRegistry([
        Game2048Module(),
        ShogiModule(),
        GomokuModule(),
        MinesweeperModule(),
        OthelloModule(),
        PokerModule(),
        ConcentrationModule(),
        BlackjackModule(),
        DaifugoModule(),
        MahjongSolitaireModule(),
    ])

    static let settings = GameSettings(registeredIDs: registry.modules.map(\.id))
}
