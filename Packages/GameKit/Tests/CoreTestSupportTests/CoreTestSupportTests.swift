import Testing
import Foundation
import Core
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
        for name in ["MemorySnapshotStore", "SpyFeedbackService"] {
            let pattern = #"\b(class|struct) "# + name + #"\b"#
            offenders += tests
                .filter { SourceScan.matchCount(of: pattern, in: SourceScan.strippingComments($0.text)) > 0 }
                .map { "\($0.path)（\(name)）" }
        }
        #expect(offenders.isEmpty, "CoreTestSupport の部品を使わずに定義し直している: \(offenders)")
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
