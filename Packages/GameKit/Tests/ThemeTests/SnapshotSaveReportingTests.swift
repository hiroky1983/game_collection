import Testing
import Foundation
import Core
import GameKitTestSupport

/// 中断データの保存失敗を握りつぶさない（#3382）。
struct SnapshotSaveReportingTests {

    /// `save` が必ず失敗するストア。空き容量不足などで書き込めない状況を作る。
    private final class AlwaysFailingStore: SnapshotStore, @unchecked Sendable {
        struct Failure: Error {}
        func save<T: Codable>(_ snapshot: T, for gameID: String) throws { throw Failure() }
        func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? { nil }
        func clear(for gameID: String) {}
        func exists(for gameID: String) -> Bool { false }
    }

    private final class SucceedingStore: SnapshotStore, @unchecked Sendable {
        func save<T: Codable>(_ snapshot: T, for gameID: String) throws {}
        func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? { nil }
        func clear(for gameID: String) {}
        func exists(for gameID: String) -> Bool { false }
    }

    @Test("保存に失敗したら gameID とエラーが報告され、戻り値は false")
    func failureIsReported() {
        var reported: [(String, Error)] = []
        let ok = AlwaysFailingStore().saveReportingFailure(["a": 1], for: "test-game") { id, error in
            reported.append((id, error))
        }
        #expect(!ok)
        #expect(reported.count == 1)
        #expect(reported.first?.0 == "test-game")
        #expect(reported.first?.1 is AlwaysFailingStore.Failure)
    }

    @Test("保存に成功したら報告しない")
    func successIsNotReported() {
        var reportCount = 0
        let ok = SucceedingStore().saveReportingFailure(["a": 1], for: "test-game") { _, _ in reportCount += 1 }
        #expect(ok)
        #expect(reportCount == 0)
    }
}

/// `try?` での中断データの保存が新しく入るのを止める（#3382）。固定フォント検査（#1858）と同じ型。
struct SnapshotSaveTryOptionalScanTests {

    private static func sourceLines() throws -> [(location: String, text: String)] {
        let roots = [
            SourceScan.packageRoot.appendingPathComponent("Sources"),
            SourceScan.repositoryRoot.appendingPathComponent("App"),
        ]
        var result: [(String, String)] = []
        var fileCount = 0
        for root in roots {
            let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                fileCount += 1
                let source = try String(contentsOf: file, encoding: .utf8)
                for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    result.append(("\(file.path):\(index + 1)", String(line)))
                }
            }
        }
        #expect(fileCount > 100) // 空振り防止
        return result
    }

    /// `try? <何か>.snapshots.save(` / `try? snapshots.save(`（コメント行は除く）。
    static func isSwallowedSave(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//") else { return false }
        return line.contains("try?") && line.contains("snapshots") && line.contains(".save(")
    }

    @Test("中断データの保存は try? で握りつぶさず saveReportingFailure を使う")
    func noSwallowedSave() throws {
        let offenders = try Self.sourceLines()
            .filter { Self.isSwallowedSave($0.text) }
            .map { "\($0.location): \($0.text.trimmingCharacters(in: .whitespaces))" }
        #expect(offenders.isEmpty, """
            保存失敗を握りつぶさない。saveReportingFailure(_:for:) を使う（#3382）。\n\(offenders.joined(separator: "\n"))
            """)
    }

    @Test("判定は try? の保存を拾い、報告つきの保存・コメント行は通す")
    func detectionRules() {
        #expect(Self.isSwallowedSave("        try? services?.snapshots.save(snap, for: gameID)"))
        #expect(!Self.isSwallowedSave("        services?.snapshots.saveReportingFailure(snap, for: gameID)"))
        #expect(!Self.isSwallowedSave("        // try? services?.snapshots.save(snap, for: gameID)"))
    }
}
