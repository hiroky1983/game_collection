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

    /// `AppEnvironment.registry` の `categories:` に載った ID（登録中・企画倉庫どちらも含む）。
    private func categorizedIDs(_ source: String) throws -> [String] {
        let start = try #require(source.range(of: "categories: ["))
        let end = try #require(source.range(of: "])", range: start.upperBound..<source.endIndex))
        let body = String(source[start.upperBound..<end.lowerBound])
        let ids = try body.matches(of: Regex(#""([a-z0-9]+)": \."#)).compactMap { $0.output[1].substring.map(String.init) }
        #expect(ids.count >= 20, "カテゴリーの表が読めない（走査のパターンが壊れている可能性）")
        return ids
    }

    /// `registry = GameRegistry([ ... ], categories:` のゲーム一覧から、コメントアウトされていない
    /// （= ハブに登録中の）`XxxModule()` の型名一覧を拾う。倉庫ゲームの説明文コメントも行頭が `//` なので、
    /// 行単位で `//` 始まりを落とすだけで登録行だけが残る。
    private func registeredModuleTypeNames(_ source: String) throws -> [String] {
        let start = try #require(source.range(of: "static let registry = GameRegistry(["))
        let end = try #require(source.range(of: "], categories: [", range: start.upperBound..<source.endIndex))
        let body = String(source[start.upperBound..<end.lowerBound])
        let activeBody = body.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return try activeBody.matches(of: Regex(#"([A-Za-z0-9]+Module)\(\)"#))
            .compactMap { $0.output[1].substring.map(String.init) }
    }

    /// `Packages/GameKit/Sources/**/*Module.swift` 全部から `id` を読み、型名をキーにして返す
    /// （ハブに登録中・企画倉庫（コメントアウト中）どちらも含む・#2385）。
    private func allGameModuleIDsByTypeName() throws -> [String: String] {
        let sourcesRoot = SourceScan.packageRoot.appendingPathComponent("Sources")
        let enumerator = try #require(
            FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil),
            "\(sourcesRoot.path) を走査できない")
        var result: [String: String] = [:]
        while let item = enumerator.nextObject() {
            guard let url = item as? URL, url.lastPathComponent.hasSuffix("Module.swift"),
                  url.lastPathComponent != "GameModule.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            guard let typeMatch = text.firstMatch(of: /public struct (\w+): GameModule/),
                  let idMatch = text.firstMatch(of: /public let id = "([a-z0-9]+)"/) else { continue }
            result[String(typeMatch.output.1)] = String(idMatch.output.1)
        }
        // 空振り防止。パスがずれて 0 件になると、以降の照合がすべて素通りしてしまう。
        #expect(result.count >= 35, "ゲームモジュールの走査が空振りしている可能性（\(result.count) 件しか読めていない）")
        return result
    }

    @Test("ハブに並ぶ全ゲームがカテゴリーを持ち、絵のアセットが同梱されている")
    func everyRegisteredGameHasCategoryAndArt() throws {
        let source = try String(
            contentsOf: SourceScan.repositoryRoot.appendingPathComponent("App/AppGameServices.swift"), encoding: .utf8)
        let categorized = try categorizedIDs(source)
        #expect(Set(categorized).count == categorized.count, "同じ ID が 2 回載っている")

        // 実際にハブへ出るのは、コメントアウトされていない登録行の分だけ（企画倉庫のゲームは除く）。
        let moduleIDsByType = try allGameModuleIDsByTypeName()
        let registeredTypeNames = try registeredModuleTypeNames(source)
        let registeredIDs = registeredTypeNames.compactMap { moduleIDsByType[$0] }
        #expect(registeredIDs.count == registeredTypeNames.count,
                 "登録行の型名からゲーム ID を引けないものがある: \(Set(registeredTypeNames).subtracting(moduleIDsByType.keys))")
        #expect(Set(registeredIDs).isSubset(of: Set(categorized)),
                 "ハブに登録中なのにカテゴリーの表に無い: \(Set(registeredIDs).subtracting(categorized))")

        for id in registeredIDs {
            let png = SourceScan.repositoryRoot
                .appendingPathComponent("App/Assets.xcassets/HubTiles/hubtile-\(id).imageset/hubtile-\(id).png")
            #expect(FileManager.default.fileExists(atPath: png.path), "\(id) の絵（hubtile-\(id).png）が無い")
            // 英語のゲーム名入りの版（#2181）。
            let en = SourceScan.repositoryRoot
                .appendingPathComponent("App/Assets.xcassets/HubTiles/hubtile-\(id)-en.imageset/hubtile-\(id)-en.png")
            #expect(FileManager.default.fileExists(atPath: en.path), "\(id) の英語版の絵（hubtile-\(id)-en.png）が無い")
            // 「つづき・最近」のアイコン（名前なしの絵・#2175）。
            let thumb = SourceScan.repositoryRoot
                .appendingPathComponent("App/Assets.xcassets/HubTiles/hubthumb-\(id).imageset/hubthumb-\(id).png")
            #expect(FileManager.default.fileExists(atPath: thumb.path), "\(id) の小さい絵（hubthumb-\(id).png）が無い")
        }
    }

    @Test("企画倉庫（コメントアウト中）のゲームも含め、ゲームモジュール全部がカテゴリーの表に載っている（#2385）")
    func everyGameModuleIncludingWarehousedHasCategory() throws {
        let source = try String(
            contentsOf: SourceScan.repositoryRoot.appendingPathComponent("App/AppGameServices.swift"), encoding: .utf8)
        let categorized = Set(try categorizedIDs(source))
        let allIDs = Set(try allGameModuleIDsByTypeName().values)
        #expect(allIDs.isSubset(of: categorized),
                 "カテゴリーの表に無いゲームモジュールがある（倉庫のコメントアウト分も含めて行を用意すること）: \(allIDs.subtracting(categorized))")
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

    @Test("柵越えおじさんだけ横長のタイルでグリッドの上に置き、iPhone 用・iPad 用の画像を同梱している（#2184）")
    func homerunIsWideTileAboveGrid() throws {
        for name in ["hubtile-homerun-wide", "hubtile-homerun-wide-pad", "hubtile-homerun-wide-en", "hubtile-homerun-wide-pad-en"] {
            let png = SourceScan.repositoryRoot
                .appendingPathComponent("App/Assets.xcassets/HubTiles/\(name).imageset/\(name).png")
            #expect(FileManager.default.fileExists(atPath: png.path), "\(name).png が無い")
        }
        let source = try SourceScan.appSources()
        let hub = try #require(source.range(of: "struct HubView: View {"))
        let end = try #require(source.range(of: "private struct GameCard", range: hub.upperBound..<source.endIndex))
        let body = String(source[hub.lowerBound..<end.lowerBound])
        let wide = try #require(body.range(of: "gridTile(hero, wide: true)"), "横長タイルが置かれていない")
        let grid = try #require(body.range(of: "LazyVGrid(", range: wide.upperBound..<body.endIndex), "横長タイルがグリッドの上に無い")
        // グリッドからは柵越えおじさんを除く（2 回出さない）。
        #expect(body[grid.lowerBound...].contains("ForEach(entries.filter { $0.module.id != Self.heroGameID }"))
    }

    @Test("カテゴリーのチップは押せる範囲が 44pt 以上（HIG の最小値・#2184 の誤タップ対策）")
    func chipsHaveMinimumHitArea() throws {
        let source = try SourceScan.appSources()
        let start = try #require(source.range(of: "private struct HubCategoryChips: View {"))
        let end = source.range(of: "\n}\n", range: start.upperBound..<source.endIndex)?.upperBound ?? source.endIndex
        let chips = String(source[start.lowerBound..<end])
        #expect(chips.contains("static let minHitHeight: CGFloat = 44"))
        #expect(chips.contains(".frame(minHeight: Self.minHitHeight)\n                            .contentShape(Rectangle())"),
                "当たり判定（contentShape）が 44pt の枠に掛かっていない")
    }

    @Test("ハブのタイルは表示言語で日本語版・英語版の画像を選ぶ（#2181）")
    func tileImageFollowsAppLanguage() throws {
        let source = try SourceScan.appSources()
        let start = try #require(source.range(of: "private struct GameCard: View {"))
        let end = try #require(source.range(of: "enum HubTileStyle {", range: start.upperBound..<source.endIndex))
        let card = String(source[start.lowerBound..<end.lowerBound])
        #expect(card.contains("let language = AppLanguageStore.shared.language"))
        #expect(card.contains("HubTileStyle.tileName(for: module.id, language: language)"))
        #expect(card.contains("HubTileStyle.wideTileName(for: module.id, pad: layout.isWide, language: language)"))
    }

    @Test("見出しの「きろく」「設定」ボタンは押せる範囲が 44pt 以上で、間隔を空けている（#2201）")
    func headerButtonsHaveMinimumHitArea() throws {
        let source = try SourceScan.appSources()
        let size = try #require(source.firstMatch(of: /static let headerButtonSize: CGFloat = (\d+)/))
        #expect(Int(size.output.1)! >= 44)
        let spacing = try #require(source.firstMatch(of: /static let headerButtonSpacing: CGFloat = (\d+)/))
        #expect(Int(spacing.output.1)! > 0)
        let start = try #require(source.range(of: "private var header: some View {"))
        let end = try #require(source.range(of: "\n    }\n", range: start.upperBound..<source.endIndex))
        let header = String(source[start.lowerBound..<end.upperBound])
        #expect(SourceScan.matchCount(
            of: #"\.frame\(width: layout\.scaled\(Self\.headerButtonSize\), height: layout\.scaled\(Self\.headerButtonSize\)\)\n\s*\.contentShape\(Rectangle\(\)\)"#,
            in: header) == 2, "2 つのボタンの当たり判定が 44pt 以上の枠に掛かっていない")
        #expect(header.contains("HStack(spacing: layout.scaled(Self.headerButtonSpacing))"))
    }
}
