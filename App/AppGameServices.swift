import Core
import Game2048
import GameShogi
import GameGomoku
import GameMinesweeper
import GameOthello
import GamePoker
import GameConcentration
import GameBlackjack

/// アプリ本体が組み立てる GameServices の実体。
/// MVP: 永続化 = FileSnapshotStore、広告 = NoopAdService（M5 で AdMob に差し替え）。
@MainActor
enum AppEnvironment {
    static let services = GameServices(
        snapshots: FileSnapshotStore(),
        ads: AdMobAdService()
    )

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
    ])

    static let settings = GameSettings(registeredIDs: registry.modules.map(\.id))
}
