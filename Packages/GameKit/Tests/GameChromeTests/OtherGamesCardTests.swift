import Foundation
import SwiftUI
import Testing
import Core

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

/// 「ほかのあそび」（#661）がレコメンドの枠の高さ契約を守っていることを見る。
///
/// 枠を使う画面の多く（`GameControlArea` / `RecommendationArea`）は、カードが出ていなくても
/// `RecommendationCard.heightPlaceholder` で高さを確保している。空いた枠に出すボタンが
/// ひな形より 1pt でも高いと、決着した瞬間に下の領域が伸びて盤が縮む（#148 と同じ失敗）。
@Suite("ほかのあそび")
@MainActor
struct OtherGamesCardTests {
    /// iPhone SE（第3世代）の内寸に近い幅。文字が詰まる狭い側で見る。
    private static let width: CGFloat = 343

    /// 描いた高さ（pt）。何も描かないときは 0。
    private func height(_ view: some View, _ size: DynamicTypeSize = .large) -> Int {
        let renderer = ImageRenderer(content: view
            .frame(width: Self.width)
            .environment(\.dynamicTypeSize, size))
        renderer.scale = 1
        return renderer.cgImage?.height ?? 0
    }

    private func makeServices() -> GameServices {
        GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
    }

    @Test("枠のひな形と同じ高さで出る", arguments: [DynamicTypeSize.large, .accessibility3])
    func matchesPlaceholderHeight(size: DynamicTypeSize) {
        let placeholder = height(RecommendationCard.heightPlaceholder, size)
        #expect(placeholder >= Int(RecommendationCard.placeholderMinimumHeight))
        #expect(height(OtherGamesCard(), size) == placeholder)
    }

    @Test("決着前は何も描かず、決着後はレコメンドが無ければ枠の高さで出る")
    func slotShowsOtherGamesOnlyAfterFinish() {
        let services = makeServices()
        let placeholder = height(RecommendationCard.heightPlaceholder)
        #expect(height(RecommendationSlot(services: services, isFinished: false)) == 0)
        #expect(height(RecommendationSlot(services: services, isFinished: true)) == placeholder)
        #expect(height(RecommendationSlot(services: services, isFinished: true, showsOtherGames: false)) == 0)
    }

    /// 解析の `gameDidLeave` はハブの `onChange(of: path)` の 1 か所だけが送る（#158）。
    /// ボタン側から送ると、左上の戻ると合わせて 1 回の離脱が 2 回に数えられる。
    @Test("ほかのあそびは戻るだけで、解析を自分で送らない")
    func onlyDismissesWithoutAnalytics() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameChromeTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/Core/RecommendationCard.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        // コメントの言及（「gameDidLeave は呼ばない」）に当たらないよう、コードの行だけを見る。
        let code = source.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let start = try #require(code.range(of: "public struct OtherGamesCard"))
        let end = try #require(code.range(of: "public struct RecommendationSlot"))
        let body = code[start.lowerBound..<end.lowerBound]
        #expect(body.contains("dismiss()"))
        #expect(!body.contains("gameDidLeave"))
        #expect(!body.contains("analytics"))
    }
}
