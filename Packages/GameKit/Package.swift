// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GameKit",
    // macOS も含めることで、SwiftUI を含む各ターゲットを `swift test`（macターゲット）で
    // シミュレータ抜きにビルド・検証できる。iOS 専用 API は使わず、必要なら #if os(iOS) で隔離する。
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "Core",             targets: ["Core"]),
        .library(name: "Game2048",         targets: ["Game2048"]),
        .library(name: "GameShogi",        targets: ["GameShogi"]),
        .library(name: "GameGomoku",       targets: ["GameGomoku"]),
        .library(name: "GameMinesweeper",  targets: ["GameMinesweeper"]),
        .library(name: "GameOthello",      targets: ["GameOthello"]),
        .library(name: "GamePoker",         targets: ["GamePoker"]),
        .library(name: "GameConcentration", targets: ["GameConcentration"]),
        .library(name: "GameBlackjack",     targets: ["GameBlackjack"]),
        .library(name: "GameDaifugo",       targets: ["GameDaifugo"]),
        .library(name: "GameMahjongSolitaire", targets: ["GameMahjongSolitaire"]),
        .library(name: "GameMahjong",      targets: ["GameMahjong"]),
        .library(name: "MahjongTiles",     targets: ["MahjongTiles"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Game2048",           dependencies: ["Core"]),
        .target(name: "GameShogi",          dependencies: ["Core"]),
        .target(name: "GameGomoku",         dependencies: ["Core"]),
        .target(name: "GameMinesweeper",    dependencies: ["Core"]),
        .target(name: "GameOthello",        dependencies: ["Core"]),
        .target(name: "GamePoker",          dependencies: ["Core"]),
        .target(name: "GameConcentration",  dependencies: ["Core"]),
        .target(name: "GameBlackjack",      dependencies: ["Core"]),
        .target(name: "GameDaifugo",        dependencies: ["Core"]),
        // 牌の絵柄と描画。麻雀ソリティアと四人打ち麻雀(#106)で共有するのでゲームの外に置く。
        .target(name: "MahjongTiles",       dependencies: ["Core"]),
        .target(name: "GameMahjongSolitaire", dependencies: ["Core", "MahjongTiles"]),
        // 四人打ち麻雀（#106）。牌の描画は上の共有部品を使い、独自に描き直さない。
        .target(name: "GameMahjong",        dependencies: ["Core", "MahjongTiles"]),
        // 配色（#187 のダークモード対応）はゲーム横断の共有資産なので Core 単体で検証する。
        .testTarget(name: "ThemeTests",       dependencies: ["Core"]),
        .testTarget(name: "Game2048Tests",    dependencies: ["Game2048"]),
        .testTarget(name: "GameShogiTests",   dependencies: ["GameShogi"]),
        .testTarget(name: "GameGomokuTests",  dependencies: ["GameGomoku"]),
        .testTarget(name: "GameMinesweeperTests", dependencies: ["GameMinesweeper"]),
        .testTarget(name: "GameOthelloTests", dependencies: ["GameOthello"]),
        .testTarget(name: "GamePokerTests",          dependencies: ["GamePoker"]),
        .testTarget(name: "GameConcentrationTests",  dependencies: ["GameConcentration"]),
        .testTarget(name: "GameBlackjackTests",       dependencies: ["GameBlackjack"]),
        .testTarget(name: "GameDaifugoTests",         dependencies: ["GameDaifugo"]),
        .testTarget(name: "GameMahjongSolitaireTests", dependencies: ["GameMahjongSolitaire"]),
        .testTarget(name: "GameMahjongTests",           dependencies: ["GameMahjong"]),
        .testTarget(name: "MahjongTilesTests",          dependencies: ["MahjongTiles"]),
        // 触覚フィードバックは全ゲーム横断のため 1 ターゲットにまとめる（スパイ実装の重複を避ける）。
        .testTarget(name: "FeedbackTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong",
        ]),
        // ゲーム間レコメンドも全ゲーム横断（決着の数え上げを全 Model で検証する）。
        .testTarget(name: "RecommendationTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong",
        ]),
        // プレイ記録（#115）も全ゲーム横断（どのゲームがどの指標を記録するかを全 Model で検証する）。
        .testTarget(name: "PlayRecordTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong",
        ]),
        // 遊び方ガイド（#118）も全ゲーム横断（全ゲームぶんの文言と初回フラグの永続化を検証する）。
        .testTarget(name: "HowToPlayTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong",
        ]),
        // 解析イベント（#158）も全ゲーム横断（1プレイ 1 組の発火を全 Model で検証する）。
        .testTarget(name: "AnalyticsTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong",
        ]),
        // VoiceOver の読み上げ文（#188）も盤面を持つゲーム横断。
        // 読み上げ文の生成は純関数に切り出してあるので、View を組まずに検証できる。
        // Reduce Motion 追従（#210）の共通レイヤーも同じアクセシビリティ横断の関心なのでここに置く。
        .testTarget(name: "AccessibilityTests", dependencies: [
            "Core", "GameShogi", "GameGomoku", "GameMinesweeper", "GameOthello",
            "GameDaifugo", "GameMahjongSolitaire", "GameMahjong", "MahjongTiles",
        ]),
        // 評価リクエストも全ゲーム横断（勝敗の振り分けを全 Model で検証する）。
        .testTarget(name: "ReviewRequestTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong",
        ]),
    ]
)
