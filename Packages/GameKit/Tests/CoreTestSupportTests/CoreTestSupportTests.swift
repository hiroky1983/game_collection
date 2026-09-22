import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
import GameKitTestSupport

/// テスト用の差し替え部品の境界（#841）。
///
/// 部品を 1 か所に寄せても、製品コードから import されれば本番にテスト用の置き場が混ざり、
/// テスト側に同じ実装を書き足されれば重複が元に戻る。どちらもコンパイラは止めないので走査で固定する。
@Suite("CoreTestSupport の境界")
struct CoreTestSupportBoundaryTests {

    /// `root` 配下の Swift ファイルを（相対パス, 本文）で返す。
    private static func swiftFiles(under root: URL) throws -> [(path: String, text: String)] {
        try FileManager.default
            .subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { ($0, try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8)) }
    }

    @Test("製品コード（Sources と App）は CoreTestSupport を import しない")
    func productCodeDoesNotImportTestSupport() throws {
        let sources = try Self.swiftFiles(under: SourceScan.packageRoot.appendingPathComponent("Sources"))
            .filter { !$0.path.hasPrefix("CoreTestSupport/") }
        let app = try Self.swiftFiles(under: SourceScan.repositoryRoot.appendingPathComponent("App"))
        // 空振り防止。パスの導出が外れて 0 件になると「含まない」が素通りする。
        #expect(sources.count > 100, "Sources が読めていない（\(sources.count) 件）")
        #expect(!app.isEmpty, "App が読めていない")

        let needle = "import " + "CoreTestSupport"
        let offenders = (sources + app)
            .filter { SourceScan.strippingComments($0.text).contains(needle) }
            .map(\.path)
        #expect(offenders.isEmpty, "製品コードがテスト用の部品を import している: \(offenders)")
    }

    @Test("テスト側に同じモックを書き足していない")
    func testsDoNotRedefineSharedMocks() throws {
        let tests = try Self.swiftFiles(under: SourceScan.packageRoot.appendingPathComponent("Tests"))
        #expect(tests.count > 100, "Tests が読めていない（\(tests.count) 件）")

        var offenders: [String] = []
        for name in ["MemorySnapshotStore", "SpyFeedbackService", "SpyAnalyticsService", "SpyReminderScheduler"] {
            let pattern = #"\b(class|struct) "# + name + #"\b"#
            offenders += tests
                .filter { SourceScan.matchCount(of: pattern, in: SourceScan.strippingComments($0.text)) > 0 }
                .map { "\($0.path)（\(name)）" }
        }
        #expect(offenders.isEmpty, "CoreTestSupport の部品を使わずに定義し直している: \(offenders)")
    }

    /// チャリンコおじさんの自動操縦は `GameRunnerTestSupport` の 1 本だけにする（#1150）。
    ///
    /// 横断のテスト 5 本と `GameRunnerTests` が同じ塊を持っていたため、`RunnerPhase` に
    /// ケースを 1 つ足すだけで 5 ターゲットを同時に直すことになっていた（PR #1121）。
    /// 型ではなく関数なので上の走査には掛からない。旧名（`clearRunnerStage` /
    /// `failRunnerStage` / `failRunnerAfterCheckpoint`）の復活もここで止める。
    @Test("チャリンコおじさんの自動操縦はテスト側に書き足されていない")
    func runnerAutoPlayLivesOnlyInTestSupport() throws {
        let tests = try Self.swiftFiles(under: SourceScan.packageRoot.appendingPathComponent("Tests"))
        #expect(tests.count > 100, "Tests が読めていない（\(tests.count) 件）")

        let owned = ["autoPlayCurrentStage", "failCurrentStage"]
        let banned = ["clearRunnerStage", "failRunnerStage", "failRunnerAfterCheckpoint"]
        let owner = "GameRunnerTestSupport/RunnerAutoPlay.swift"
        // `func` と名前のあいだが改行・複数の空白でも当てる（`"func " + name` の文字列一致だと
        // 書式を変えただけのコピーが素通りする。CodeRabbit 指摘）。
        func declares(_ name: String, in file: (path: String, text: String)) -> Bool {
            SourceScan.matchCount(of: #"\bfunc\s+"# + name + #"\b"#,
                                  in: SourceScan.strippingComments(file.text)) > 0
        }

        var offenders: [String] = []
        for name in owned {
            offenders += tests
                .filter { declares(name, in: $0) && $0.path != owner }
                .map { "\($0.path)（\(name)）" }
        }
        for name in banned {
            offenders += tests
                .filter { declares(name, in: $0) }
                .map { "\($0.path)（\(name)・旧名）" }
        }
        #expect(offenders.isEmpty, "GameRunnerTestSupport の自動操縦を使わずに定義し直している: \(offenders)")

        // 空振り防止。寄せ先が消えた・改名されたら「0 件だから緑」で素通りする。
        let ownerHits = owned.filter { name in
            tests.contains { $0.path == owner && declares(name, in: $0) }
        }
        #expect(ownerHits == owned, "寄せ先に自動操縦が無い: \(ownerHits)")
    }

    /// `#filePath` から親ディレクトリを辿ってパスを作るのは `SourceScan` だけにする（#915）。
    /// テスト関数の中へインラインで書き直されると、`Tests/` や `Sources/` の階層を変えたときに
    /// 散らばった全箇所を個別に直すことになる。コンパイラは止めないので走査で固定する。
    @Test("パスの導出は SourceScan にだけある")
    func pathDerivationLivesOnlyInSourceScan() throws {
        let tests = try Self.swiftFiles(under: SourceScan.packageRoot.appendingPathComponent("Tests"))
        #expect(tests.count > 100, "Tests が読めていない（\(tests.count) 件）")

        // このファイル自身に当たらないよう、語を分けて組み立てる。
        let needle = "deletingLast" + "PathComponent"
        let owners = tests.filter { $0.text.contains(needle) }.map(\.path)
        // 検出できていることの確認を兼ねて、SourceScan 自身は必ず含まれる。
        #expect(owners == ["GameKitTestSupport/SourceScan.swift"],
                "SourceScan 以外でパスを導出している（SourceScan.packageSource / packageRoot を使う）: \(owners)")
    }
}

@Suite("MemorySnapshotStore")
struct MemorySnapshotStoreTests {
    private struct Sample: Codable, Equatable {
        var value: Int
    }

    @Test("書いたものを読み返せて、消すと無くなる")
    func roundTrip() throws {
        let store = MemorySnapshotStore()
        #expect(store.isEmpty)
        #expect(store.load(Sample.self, for: "game") == nil)

        try store.save(Sample(value: 3), for: "game")
        #expect(store.exists(for: "game"))
        #expect(store.load(Sample.self, for: "game") == Sample(value: 3))
        #expect(!store.exists(for: "other"), "ID ごとに分かれている")
        #expect(store.saveCount == 1)

        store.clear(for: "game")
        #expect(!store.exists(for: "game"))
        #expect(store.isEmpty)
    }

    @Test("生のバイト列を置いて読み返せる。置いただけでは保存回数に数えない")
    func injectRawData() throws {
        let store = MemorySnapshotStore()
        let broken = Data("{\"value\":".utf8)
        store.inject(broken, for: "game")

        #expect(store.rawData(for: "game") == broken)
        #expect(store.exists(for: "game"))
        #expect(store.load(Sample.self, for: "game") == nil, "壊れた JSON は nil で返す")
        #expect(store.saveCount == 0)
    }
}

@Suite("SpyFeedbackService")
@MainActor
struct SpyFeedbackServiceTests {
    @Test("届いた呼び出しを種類ごとに記録し、reset で空に戻る")
    func recordsAndResets() {
        let spy = SpyFeedbackService()
        spy.impact(.light)
        spy.notify(.warning)
        spy.notify(.warning)
        spy.notify(.success)

        #expect(spy.impacts == [.light])
        #expect(spy.notices == [.warning, .warning, .success])
        #expect(spy.notices(of: .warning) == 2)
        #expect(spy.callCount == 4)

        spy.reset()
        #expect(spy.callCount == 0)
    }
}

/// Zobrist ハッシュと対局テストの「でたらめ役」が使う共通の乱数（#1150）。
///
/// `SplitMix64` を 1 本化した #1074 では MMIX 系が対象外で、製品 3 本（チェス・将棋・五目並べ）と
/// テスト 2 本に同じ実装が残っていた。**出力が 1 ビットでも変わると Zobrist の表が別物になり、
/// 千日手判定・置換表と、固定してある対局テストの期待値がすべて崩れる**ので、
/// 共通化のあとも出力列そのものを既知の値で固定する。
@Suite("共通の乱数（MMIXRandom）")
struct MMIXRandomTests {

    /// 期待値は共通化の前の実装（`ChessLCG` / `LCG` / `GomokuLCG` と同じ式）で出したもの。
    @Test("内部状態から始めた出力列が既知の値と一致する")
    func goldenVectorsFromState() {
        let expected: [(state: UInt64, outputs: [UInt64])] = [
            (0, [0x1405_7B7E_FD65_3CF0, 0x1A08_EE11_89BE_1A3A, 0x9AF6_7822_6309_BD08]),
            // 将棋の駒の表が使っている合言葉。
            (0xDEAD_BEEF_CAFE_BABE, [0x9AFF_B273_5017_4F8C, 0xF886_21C0_04A5_DAC0, 0x449A_D043_F893_80CE]),
        ]
        for (state, outputs) in expected {
            var rng = MMIXRandom(state: state)
            #expect(outputs.indices.map { _ in rng.next() } == outputs, "状態 \(state)")
        }
    }

    /// `init(seed:)` は種を 1 歩進めてから始める（対局テストの「でたらめ役」の入り口）。
    @Test("種から始めた出力列が既知の値と一致する")
    func goldenVectorsFromSeed() {
        let expected: [(seed: UInt64, outputs: [UInt64])] = [
            (0, [0x1A08_EE11_89BE_1A3A, 0x9AF6_7822_6309_BD08, 0x66B6_1AE9_4C7B_94C0]),
            (42, [0x39B7_F8A5_DA97_093E, 0x69AF_C5A5_DC5C_DB99, 0xA161_C43F_D543_2A61]),
        ]
        for (seed, outputs) in expected {
            var rng = MMIXRandom(seed: seed)
            #expect(outputs.indices.map { _ in rng.next() } == outputs, "種 \(seed)")
        }
    }

    /// 種を 1 歩進めるのと、進めた値を状態に置くのは同じこと（`init` の 2 つが食い違っていない）。
    @Test("init(seed:) は 1 歩進めた init(state:) と同じ")
    func seedInitMatchesAdvancedState() {
        for seed in [UInt64(0), 1, 42, .max] {
            var fromSeed = MMIXRandom(seed: seed)
            var fromState = MMIXRandom(state: seed &* MMIXRandom.multiplier &+ MMIXRandom.increment)
            #expect((0..<5).map { _ in fromSeed.next() } == (0..<5).map { _ in fromState.next() }, "種 \(seed)")
        }
    }

    /// MMIX の定数が CoreEngine の共通部品にしか現れないことの固定（#1150。#1074 の
    /// `SplitMix64` 版は `SpiderDealerTests` にある）。区切りの `_` と大文字小文字、
    /// 16 進表記まで揃えて数える。`Sources` だけでなく `Tests` も見る——テスト側にも
    /// 2 本コピーが残っていたのが今回の出どころなので、片側だけ見ても再発を止められない。
    @Test("MMIX の定数は CoreEngine の共通部品にしか現れない")
    func mmixConstantsHaveSingleImplementation() throws {
        // このファイル自身に当たらないよう、語を分けて組み立てる。
        let decimals = ["63641362" + "23846793005", "14426950" + "40888963407"]
        let hexes = ["5851f42d" + "4c957f2d", "14057b7e" + "f767814f"]

        var hits: [String] = []
        for dir in ["Sources", "Tests"] {
            let root = SourceScan.packageRoot.appendingPathComponent(dir)
            let files = try Self.swiftFiles(under: root)
            #expect(files.count > 50, "\(dir) が読めていない（\(files.count) 件）")
            hits += files
                .filter { file in
                    let text = file.text.replacingOccurrences(of: "_", with: "").lowercased()
                    return (decimals + hexes).contains { text.contains($0) }
                }
                .map { "\(dir)/\($0.path)" }
        }
        #expect(hits == ["Sources/CoreEngine/MMIXRandom.swift"])
    }

    private static func swiftFiles(under root: URL) throws -> [(path: String, text: String)] {
        try FileManager.default
            .subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { ($0, try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8)) }
    }
}
