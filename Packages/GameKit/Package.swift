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
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Game2048",           dependencies: ["Core"]),
        .target(name: "GameShogi",          dependencies: ["Core"],
                resources: [.process("Resources")]),
        .target(name: "GameGomoku",         dependencies: ["Core"]),
        .target(name: "GameMinesweeper",    dependencies: ["Core"]),
        .target(name: "GameOthello",        dependencies: ["Core"]),
        .target(name: "GamePoker",          dependencies: ["Core"]),
        .target(name: "GameConcentration",  dependencies: ["Core"]),
        .target(name: "GameBlackjack",      dependencies: ["Core"]),
        .executableTarget(name: "ShogiDataGen", dependencies: ["GameShogi"]),
        .testTarget(name: "Game2048Tests",    dependencies: ["Game2048"]),
        .testTarget(name: "GameShogiTests",   dependencies: ["GameShogi"]),
        .testTarget(name: "GameGomokuTests",  dependencies: ["GameGomoku"]),
        .testTarget(name: "GameOthelloTests", dependencies: ["GameOthello"]),
        .testTarget(name: "GamePokerTests",          dependencies: ["GamePoker"]),
        .testTarget(name: "GameConcentrationTests",  dependencies: ["GameConcentration"]),
    ]
)
