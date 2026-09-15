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
        .library(name: "GameGo",           targets: ["GameGo"]),
        .library(name: "GameChess",        targets: ["GameChess"]),
        .library(name: "GameMinesweeper",  targets: ["GameMinesweeper"]),
        .library(name: "GameOthello",      targets: ["GameOthello"]),
        .library(name: "GamePoker",         targets: ["GamePoker"]),
        .library(name: "GameConcentration", targets: ["GameConcentration"]),
        .library(name: "GameBlackjack",     targets: ["GameBlackjack"]),
        .library(name: "GameDaifugo",       targets: ["GameDaifugo"]),
        .library(name: "GameMahjongSolitaire", targets: ["GameMahjongSolitaire"]),
        .library(name: "GameMahjong",      targets: ["GameMahjong"]),
        .library(name: "GameSudoku",       targets: ["GameSudoku"]),
        .library(name: "GameSolitaire",    targets: ["GameSolitaire"]),
        .library(name: "GameBlocks",       targets: ["GameBlocks"]),
        .library(name: "GameFreeCell",     targets: ["GameFreeCell"]),
        .library(name: "GameSpider",       targets: ["GameSpider"]),
        .library(name: "GameBlockPuzzle",  targets: ["GameBlockPuzzle"]),
        .library(name: "GameRunner",       targets: ["GameRunner"]),
        .library(name: "GameHanafuda",     targets: ["GameHanafuda"]),
        .library(name: "MahjongTiles",     targets: ["MahjongTiles"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Game2048",           dependencies: ["Core"]),
        .target(name: "GameShogi",          dependencies: ["Core"]),
        .target(name: "GameGomoku",         dependencies: ["Core"]),
        // 囲碁（#398）。ルール・終局計算・MCTS はすべて純粋ロジックなので Core だけに依存する。
        .target(name: "GameGo",             dependencies: ["Core"]),
        // チェス（#462）。ルール・探索は純粋ロジックなので Core だけに依存する。
        .target(name: "GameChess",          dependencies: ["Core"]),
        .target(name: "GameMinesweeper",    dependencies: ["Core"]),
        .target(name: "GameOthello",        dependencies: ["Core"]),
        .target(name: "GamePoker",          dependencies: ["Core"]),
        .target(name: "GameConcentration",  dependencies: ["Core"]),
        .target(name: "GameBlackjack",      dependencies: ["Core"]),
        .target(name: "GameDaifugo",        dependencies: ["Core"]),
        // 数独（#262・元 #5）。生成アルゴリズムは純粋ロジックなので Core だけに依存する。
        .target(name: "GameSudoku",         dependencies: ["Core"]),
        // ソリティア（クロンダイク・#397）。ルール・ソルバー・配札生成は純粋ロジックなので Core だけに依存する。
        .target(name: "GameSolitaire",      dependencies: ["Core"]),
        // ブロック崩し（#463）。アクション枠の 1 本目で、**唯一 SpriteKit に依存するターゲット**。
        // ルール・当たり判定・得点は SpriteKit 非依存の純粋ロジックに分けてあるため、
        // 検証はこれまでどおりシミュレータ抜きの `swift test` で足りる。
        .target(name: "GameBlocks",         dependencies: ["Core"]),
        // フリーセル（#492）。ルール・ソルバー・配札生成は純粋ロジックなので Core だけに依存する。
        .target(name: "GameFreeCell",       dependencies: ["Core"]),
        // スパイダーソリティア（#717）。盤・配札・ソルバーは Core すら import しない純粋ロジックで、
        // 種の事前計算は `swiftc -O` で単体バイナリにして回す（`SpiderDealerTests` に手順）。
        .target(name: "GameSpider",         dependencies: ["Core"]),
        // ブロックならべ（#493）。置き型の行列消しパズル。判定・得点・手札生成は純粋ロジックなので
        // Core だけに依存する。
        .target(name: "GameBlockPuzzle",    dependencies: ["Core"]),
        // チャリンコおじさん（#494）。アクション枠の2本目。地形・ジャンプ・当たり判定は
        // SpriteKit に依存しない純粋ロジックなので Core だけに依存する。
        .target(name: "GameRunner",         dependencies: ["Core"]),
        // 花札こいこい（#495）。札の絵柄・役の判定・CPU はすべて純粋ロジックなので
        // Core だけに依存する。麻雀牌のような共有描画基盤は持たない（花札は他ゲームと札を共有しない）。
        .target(name: "GameHanafuda",       dependencies: ["Core"]),
        // 牌の絵柄と描画。麻雀ソリティアと四人打ち麻雀(#106)で共有するのでゲームの外に置く。
        .target(name: "MahjongTiles",       dependencies: ["Core"]),
        .target(name: "GameMahjongSolitaire", dependencies: ["Core", "MahjongTiles"]),
        // 四人打ち麻雀（#106）。牌の描画は上の共有部品を使い、独自に描き直さない。
        .target(name: "GameMahjong",        dependencies: ["Core", "MahjongTiles"]),
        // テストの共通部品（#529。ソース走査の読み口・非同期タスクのゲート）。製品には含めず、
        // テストターゲットからだけ依存する。
        .target(name: "GameKitTestSupport", path: "Tests/GameKitTestSupport"),
        // テスト用の Core の差し替え部品（#841。メモリ上の中断データ置き場・触覚フィードバックのスパイ）。
        // GameKitTestSupport と違って Core に依存するので別ターゲットにする。製品には含めない。
        .target(name: "CoreTestSupport",    dependencies: ["Core"]),
        // 上の部品を製品コードが import していないことと、テスト側に同じ実装が再び増えていないことの走査。
        .testTarget(name: "CoreTestSupportTests", dependencies: ["CoreTestSupport", "GameKitTestSupport"]),
        // 配色（#187 のダークモード対応）はゲーム横断の共有資産なので Core 単体で検証する。
        .testTarget(name: "ThemeTests",       dependencies: ["Core", "GameKitTestSupport"]),
        .testTarget(name: "PixelArtTests",    dependencies: ["Core"]),
        // 広告枠（バナー）の生成判断。実際の GADBannerView は端末側なので、判断だけを純粋関数で検証する。
        .testTarget(name: "AdsTests",         dependencies: ["Core"]),
        // 画面の広さに応じた適応レイヤ（#458 の iPad 対応）。判定と数値を Core に集約しているため、
        // レイアウトの正しさはシミュレータを起動しなくてもここで検証できる。
        .testTarget(name: "LayoutTests",      dependencies: ["Core", "GameKitTestSupport"]),
        // ハブ最上部の「つづき・最近」行（#660）。行は App ターゲットにあるが、並び順と
        // 打ち切りの規則は Core の純粋関数なので、シミュレータ無しでここで固定できる。
        .testTarget(name: "RecentGamesTests", dependencies: ["Core", "GameKitTestSupport"]),
        // 中断したゲームのお知らせ（#663）。対象外の宣言を持つチャリンコおじさんと、既定のまま使う
        // 2048 を並べて、宣言が規則に届いていることまで確かめる。終局後も見返しを保存する将棋・
        // チェスは、決着済みの局に予約しないことを Model を通して確かめる。
        .testTarget(name: "ResumeReminderTests", dependencies: [
            "Core", "Game2048", "GameRunner", "GameShogi", "GameChess", "GameMahjong",
            "MahjongTiles", "GameKitTestSupport", "CoreTestSupport",
        ]),
        // 盤ゲーム（将棋・チェス）の共通の枠（#530）。値も重なり順も「両方で同じ」であることが
        // 性質そのものなので、各ゲームではなく Core 単体で検証する。
        .testTarget(name: "BoardGameChromeTests", dependencies: ["Core"]),
        .testTarget(name: "GameChromeTests",   dependencies: ["Core", "CoreTestSupport"]),
        .testTarget(name: "Game2048Tests",    dependencies: ["Game2048", "CoreTestSupport"]),
        .testTarget(name: "GameShogiTests",   dependencies: ["GameShogi", "GameKitTestSupport", "CoreTestSupport"]),
        .testTarget(name: "GameGomokuTests",  dependencies: ["GameGomoku", "GameKitTestSupport", "CoreTestSupport"]),
        .testTarget(name: "GameGoTests",      dependencies: ["GameGo", "CoreTestSupport"]),
        .testTarget(name: "GameChessTests",   dependencies: ["GameChess", "CoreTestSupport"]),
        .testTarget(name: "GameMinesweeperTests", dependencies: ["GameMinesweeper", "CoreTestSupport"]),
        .testTarget(name: "GameOthelloTests", dependencies: ["GameOthello", "GameKitTestSupport", "CoreTestSupport"]),
        .testTarget(name: "GamePokerTests",          dependencies: ["GamePoker", "GameKitTestSupport", "CoreTestSupport"]),
        .testTarget(name: "GameConcentrationTests",  dependencies: ["GameConcentration", "GameKitTestSupport", "CoreTestSupport"]),
        .testTarget(name: "GameBlackjackTests",       dependencies: ["GameBlackjack", "GameKitTestSupport", "CoreTestSupport"]),
        .testTarget(name: "GameDaifugoTests",         dependencies: ["GameDaifugo", "CoreTestSupport"]),
        .testTarget(name: "GameSudokuTests",          dependencies: ["GameSudoku", "GameKitTestSupport", "CoreTestSupport"]),
        .testTarget(name: "GameSolitaireTests",       dependencies: ["GameSolitaire", "GameKitTestSupport", "CoreTestSupport"]),
        .testTarget(name: "GameBlocksTests",         dependencies: ["GameBlocks", "CoreTestSupport"]),
        .testTarget(name: "GameFreeCellTests",       dependencies: ["GameFreeCell", "GameKitTestSupport", "CoreTestSupport"]),
        .testTarget(name: "GameSpiderTests",         dependencies: ["GameSpider", "CoreTestSupport"]),
        .testTarget(name: "GameBlockPuzzleTests",    dependencies: ["GameBlockPuzzle", "CoreTestSupport"]),
        .testTarget(name: "GameRunnerTests",         dependencies: ["GameRunner", "GameKitTestSupport", "CoreTestSupport"]),
        .testTarget(name: "GameHanafudaTests",       dependencies: ["GameHanafuda", "CoreTestSupport"]),
        .testTarget(name: "GameMahjongSolitaireTests", dependencies: ["GameMahjongSolitaire", "GameKitTestSupport", "CoreTestSupport"]),
        .testTarget(name: "GameMahjongTests",           dependencies: ["GameMahjong", "GameKitTestSupport", "CoreTestSupport"]),
        .testTarget(name: "MahjongTilesTests",          dependencies: ["MahjongTiles"]),
        // 触覚フィードバックは全ゲーム横断のため 1 ターゲットにまとめる（スパイ実装の重複を避ける）。
        .testTarget(name: "FeedbackTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong", "GameSudoku", "GameGo", "GameSolitaire",
            "GameChess", "GameBlocks", "GameFreeCell", "GameBlockPuzzle", "GameRunner",
            "GameHanafuda", "GameSpider", "CoreTestSupport",
        ]),
        // ゲーム間レコメンドも全ゲーム横断（決着の数え上げを全 Model で検証する）。
        .testTarget(name: "RecommendationTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong", "GameSudoku", "GameGo", "GameSolitaire",
            "GameChess", "GameBlocks", "GameFreeCell", "GameBlockPuzzle", "GameRunner",
            "GameHanafuda", "GameSpider", "CoreTestSupport",
        ]),
        // プレイ記録（#115）も全ゲーム横断（どのゲームがどの指標を記録するかを全 Model で検証する）。
        .testTarget(name: "PlayRecordTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong", "GameSudoku", "GameGo", "GameSolitaire",
            "GameChess", "GameBlocks", "GameFreeCell", "GameBlockPuzzle", "GameRunner",
            "GameHanafuda", "GameSpider", "CoreTestSupport",
        ]),
        // 遊び方ガイド（#118）も全ゲーム横断（全ゲームぶんの文言と初回フラグの永続化を検証する）。
        .testTarget(name: "HowToPlayTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong", "GameSudoku", "GameGo", "GameSolitaire",
            "GameChess", "GameBlocks", "GameFreeCell", "GameBlockPuzzle", "GameRunner",
            "GameHanafuda", "GameSpider",
        ]),
        // 解析イベント（#158）も全ゲーム横断（1プレイ 1 組の発火を全 Model で検証する）。
        .testTarget(name: "AnalyticsTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong", "GameSudoku", "GameGo", "GameSolitaire",
            "GameChess", "GameBlocks", "GameFreeCell", "GameBlockPuzzle", "GameRunner",
            "GameHanafuda", "GameSpider", "GameKitTestSupport", "CoreTestSupport",
        ]),
        // Game Center（#289）も全ゲーム横断（どのゲームがどのリーダーボードへ送るかを全 Model で検証する）。
        .testTarget(name: "GameCenterTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong", "GameSudoku", "GameGo", "GameSolitaire",
            "GameChess", "GameBlocks", "GameFreeCell", "GameBlockPuzzle", "GameRunner",
            "GameHanafuda", "GameSpider", "CoreTestSupport",
        ]),
        // VoiceOver の読み上げ文（#188）も盤面を持つゲーム横断。
        // 読み上げ文の生成は純関数に切り出してあるので、View を組まずに検証できる。
        // Reduce Motion 追従（#210）の共通レイヤーも同じアクセシビリティ横断の関心なのでここに置く。
        .testTarget(name: "AccessibilityTests", dependencies: [
            "Core", "GameShogi", "GameGomoku", "GameMinesweeper", "GameOthello",
            "GameDaifugo", "GameMahjongSolitaire", "GameMahjong", "MahjongTiles", "GameSudoku",
            "GameGo", "GameSolitaire", "GameChess", "GameBlocks", "GameFreeCell", "GameBlockPuzzle",
            "GameHanafuda", "GameSpider",
        ]),
        // 評価リクエストも全ゲーム横断（勝敗の振り分けを全 Model で検証する）。
        .testTarget(name: "ReviewRequestTests", dependencies: [
            "Core", "Game2048", "GameShogi", "GameGomoku", "GameMinesweeper",
            "GameOthello", "GamePoker", "GameConcentration", "GameBlackjack", "GameDaifugo",
            "GameMahjongSolitaire", "GameMahjong", "GameSudoku", "GameGo", "GameSolitaire",
            "GameChess", "GameBlocks", "GameFreeCell", "GameBlockPuzzle", "GameRunner",
            "GameHanafuda", "GameSpider", "CoreTestSupport",
        ]),
    ]
)
