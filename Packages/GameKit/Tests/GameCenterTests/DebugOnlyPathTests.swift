import Testing
import Foundation

// MARK: - デバッグ経路が Release ビルドに残っていないこと（#514）

/// 起動引数で有効になるデバッグ経路が Release にも残っていると、審査後のバイナリに対して
/// 引数を注入するだけで自動プレイが回り、その戦績が Game Center の実績
/// （`mahjong4` の wins10 / wins50 と `playAll`）へ計上できてしまう。
///
/// 「Release ビルドに存在しない」ことは `swift test`（常に DEBUG 構成）からは実行して確かめられない。
/// そのため `InternalTrafficSeparationTests` と同じくソースを走査して固定する。ただし素の
/// `contains` では**囲ったつもりで `#else` 側に置いた**ような壊れ方を拾えないので、
/// `#if DEBUG` を実際に評価して「Release に残る行」だけを取り出してから突き合わせる。
///
/// 置き場所がこの target なのは、対象が GameMahjong と GameBlocks の2パッケージにまたがり、
/// 被害の出口が Game Center の実績だから（この target は全ゲームに依存している）。
@Suite("デバッグ経路の Release 残存")
struct DebugOnlyPathTests {
    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameCenterTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // GameKit/
            .appendingPathComponent("Sources")
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: Self.sourcesDirectory.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Release ビルドで生き残る行だけを残したソース。コメント行は落とす
    /// （経緯を説明する doc コメントに symbol 名が出るため、素の文字列比較だとそちらに当たる）。
    ///
    /// `#if DEBUG` の本体は落とし、その `#else` 側は残す。`DEBUG` 以外の条件（`#if canImport(…)` 等）は
    /// 両側とも残す = 判定を厳しい側へ倒す。
    private func releaseVisibleCode(_ relativePath: String) throws -> String {
        struct Level {
            let isDebug: Bool
            var isInElse = false
            var survivesRelease: Bool { !(isDebug && !isInElse) }
        }
        var stack: [Level] = []
        var kept: [Substring] = []

        for line in try source(relativePath).split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if ") {
                stack.append(Level(isDebug: trimmed == "#if DEBUG"))
            } else if trimmed == "#else" || trimmed.hasPrefix("#elseif ") {
                guard !stack.isEmpty else { continue }
                stack[stack.count - 1].isInElse = true
            } else if trimmed == "#endif" {
                if !stack.isEmpty { stack.removeLast() }
            } else if !trimmed.hasPrefix("//"), stack.allSatisfy(\.survivesRelease) {
                kept.append(line)
            }
        }
        return kept.joined(separator: "\n")
    }

    @Test("走査そのものが機能している（Release 側の通常コードは残る）")
    func scannerKeepsOrdinaryCode() throws {
        // 走査が空文字列を返していると、以下の #expect は理由なく緑になる。
        // 各ファイルの「必ず Release に残るはずの行」で裏を取る。
        #expect(try releaseVisibleCode("GameMahjong/MahjongView.swift").contains("public var body: some View"))
        #expect(try releaseVisibleCode("GameMahjong/MahjongModel.swift").contains("public func startGame("))
        #expect(try releaseVisibleCode("GameBlocks/BlocksModel.swift").contains("public func tick(dt: Double)"))
    }

    @Test("-mahjongAutoPlay の読み取りは Release に残っていない")
    func autoPlayLaunchArgumentIsDebugOnly() throws {
        let raw = try source("GameMahjong/MahjongView.swift")
        // 引数名を変えただけで緑になるのを防ぐ（対象が実在することを先に固定する）。
        #expect(raw.contains("-mahjongAutoPlay"),
                "起動引数 -mahjongAutoPlay が見つからない。名前を変えたならこのテストも直すこと")

        #expect(
            try releaseVisibleCode("GameMahjong/MahjongView.swift").contains("-mahjongAutoPlay") == false,
            "-mahjongAutoPlay の読み取りが Release ビルドに残っている。引数注入で全自動対局が回り、戦績が Game Center の実績へ載る（#514）"
        )
    }

    @Test("自動プレイを有効化する API は Release に残っていない")
    func enableAutoPlayIsDebugOnly() throws {
        let raw = try source("GameMahjong/MahjongModel.swift")
        #expect(raw.contains("func enableAutoPlay()"),
                "enableAutoPlay() が見つからない。名前を変えたならこのテストも直すこと")

        // 起動引数を塞いでも、有効化の入口が public のまま残っていれば他経路から立てられる。
        #expect(
            try releaseVisibleCode("GameMahjong/MahjongModel.swift").contains("enableAutoPlay") == false,
            "enableAutoPlay() が Release ビルドに残っている（#514）"
        )
    }

    @Test("球を直接置くテスト用 API は Release に残っていない")
    func placeBallForTestingIsDebugOnly() throws {
        let raw = try source("GameBlocks/BlocksModel.swift")
        #expect(raw.contains("func placeBallForTesting("),
                "placeBallForTesting が見つからない。名前を変えたならこのテストも直すこと")

        // 呼び出し元（applyDebugScenario / breakBlocksForDebug）ごと DEBUG 限定なので、
        // Release 側にはこの識別子が1つも出てこないのが正しい状態。
        #expect(
            try releaseVisibleCode("GameBlocks/BlocksModel.swift").contains("placeBallForTesting") == false,
            "placeBallForTesting が Release ビルドに残っている。任意の位置・速度で球を置ける API が出荷される（#514）"
        )
    }
}
