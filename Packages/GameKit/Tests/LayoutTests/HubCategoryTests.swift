import Foundation
import SwiftUI
import Testing
import Core
import GameKitTestSupport

/// ハブのカテゴリーのチップと絵のタイル（#1831）。
@Suite("ハブのカテゴリーと絵のタイル")
struct HubCategoryTests {
    private struct Stub: GameModule {
        let id: String
        var title: String { id }
        var description: String { "" }
        var icon: Image { Image(systemName: "circle") }
        @MainActor func makeView(services: GameServices) -> AnyView { AnyView(EmptyView()) }
    }

    private func registry() -> GameRegistry {
        GameRegistry(
            ["a", "b", "c", "d"].map(Stub.init),
            categories: ["a": .cards, "b": .board, "c": .cards]
        )
    }

    @Test("カテゴリーに載っていないゲームは「パズル・その他」に入る")
    func unlistedFallsBackToPuzzleOther() {
        #expect(registry().category(of: "d") == .puzzleOther)
        #expect(registry().category(of: "unknown") == .puzzleOther)
    }

    @Test("`.all` を割り当てられても分類としては返さない")
    func allIsNeverReturnedAsCategory() {
        let r = GameRegistry([Stub(id: "a")], categories: ["a": .all])
        #expect(r.category(of: "a") == .puzzleOther)
    }

    @Test("絞り込みは並びを保ち、「すべて」は全件を返す")
    func filterKeepsOrder() {
        let r = registry()
        #expect(r.filter(["d", "c", "b", "a"], by: .cards) == ["c", "a"])
        #expect(r.filter(["d", "c", "b", "a"], by: .all) == ["d", "c", "b", "a"])
    }

    @Test("チップに出すのは、表示中のゲームが 1 本以上入るカテゴリーだけ")
    func populatedOnly() {
        let r = registry()
        #expect(r.populatedCategories(among: ["a", "b", "c", "d"]) == [.board, .cards, .puzzleOther])
        #expect(r.populatedCategories(among: ["b"]) == [.board])
        #expect(r.populatedCategories(among: []).isEmpty)
    }

    /// `AppEnvironment.registry` の `categories:` に載った ID。
    private func categorizedIDs(_ source: String) throws -> [String] {
        let start = try #require(source.range(of: "categories: ["))
        let end = try #require(source.range(of: "])", range: start.upperBound..<source.endIndex))
        let body = String(source[start.upperBound..<end.lowerBound])
        let ids = try body.matches(of: Regex(#""([a-z0-9]+)": \."#)).compactMap { $0.output[1].substring.map(String.init) }
        #expect(ids.count >= 20, "カテゴリーの表が読めない（走査のパターンが壊れている可能性）")
        return ids
    }

    @Test("ハブに並ぶ全ゲームがカテゴリーを持ち、絵のアセットが同梱されている")
    func everyRegisteredGameHasCategoryAndArt() throws {
        let source = try String(
            contentsOf: SourceScan.repositoryRoot.appendingPathComponent("App/AppGameServices.swift"), encoding: .utf8)
        let ids = try categorizedIDs(source)
        // コメントアウトされていない `XxxModule(),` の行数 = 登録ゲーム数。
        let registered = SourceScan.matchCount(of: #"(?m)^\s{8}[A-Za-z0-9]+Module\(\),"#, in: source)
        #expect(Set(ids).count == ids.count, "同じ ID が 2 回載っている")
        #expect(ids.count == registered, "カテゴリーの表（\(ids.count)）と登録ゲーム数（\(registered)）が合わない")
        for id in ids {
            let png = SourceScan.repositoryRoot
                .appendingPathComponent("App/Assets.xcassets/HubTiles/hubtile-\(id).imageset/hubtile-\(id).png")
            #expect(FileManager.default.fileExists(atPath: png.path), "\(id) の絵（hubtile-\(id).png）が無い")
        }
    }

    @Test("ハブはカテゴリーを GameRegistry から引き、ゲーム ID を直書きしない")
    func hubUsesRegistryData() throws {
        let source = try SourceScan.appSources()
        let hub = try #require(source.range(of: "struct HubView: View {"))
        let end = try #require(source.range(of: "private struct GameCard", range: hub.upperBound..<source.endIndex))
        let body = String(source[hub.lowerBound..<end.lowerBound])
        #expect(body.contains("registry.category(of:"))
        #expect(body.contains("registry.populatedCategories("))
        // 特別枠の `heroGameID` 以外に、ゲーム ID の文字列リテラルを持たない。
        let literals = SourceScan.matchCount(of: #"(?m)^(?!.*heroGameID).*"(homerun|ojisanpuzzle|runner|shogi|poker)""#, in: body)
        #expect(literals == 0)
    }
}
