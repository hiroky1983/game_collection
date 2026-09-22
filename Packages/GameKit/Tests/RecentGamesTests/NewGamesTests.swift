import Foundation
import Testing
import GameKitTestSupport
@testable import Core

/// 更新で増えたゲームの NEW 印（#723）。カードと1行は App ターゲットにあるので、
/// 増えたゲームの決め方と保存の規則をここで固定する。
@Suite("新しいゲームの判定")
struct NewGamesTests {
    private static let registered = ["2048", "shogi", "spider", "hanafuda"]

    @Test("前回の登録ゲームが記録されていれば、その差分だけを返す")
    func diffAgainstKnown() {
        let ids = NewGames.ids(registeredIDs: Self.registered, knownIDs: ["2048", "shogi"], hasPlayHistory: false)
        #expect(ids == ["spider", "hanafuda"])
    }

    @Test("記録もプレイの痕跡も無ければ新規インストールとみなし、何も返さない")
    func freshInstallHasNothingNew() {
        #expect(NewGames.ids(registeredIDs: Self.registered, knownIDs: nil, hasPlayHistory: false).isEmpty)
    }

    @Test("記録が無くプレイの痕跡があれば、記録を持たない版の収録ゲームと比べる")
    func updateFromLegacyUsesLegacyList() {
        let ids = NewGames.ids(registeredIDs: Self.registered, knownIDs: nil, hasPlayHistory: true)
        #expect(ids == ["spider", "hanafuda"])
    }

    @Test("登録から外れたゲームは返さない")
    func removedGamesAreNotNew() {
        let ids = NewGames.ids(registeredIDs: ["2048"], knownIDs: ["2048", "blockpuzzle"], hasPlayHistory: true)
        #expect(ids.isEmpty)
    }

    @Test("1行は増えた本数を出し、0本なら出さない")
    func noticeText() {
        #expect(NewGames.notice(count: 2) == "新しいあそびが2本増えました")
        #expect(NewGames.notice(count: 0) == nil)
    }

    @Test("記録を持たない版の一覧は、どれも実在するゲームの ID")
    func legacyIDsMatchRegisteredModules() throws {
        // 綴り違いがあると、更新した人にそのゲームが NEW として出てしまう。
        // このテストターゲットは Core にしか依存しないため、モジュールの宣言を読んで突き合わせる。
        let sources = SourceScan.packageRoot.appendingPathComponent("Sources")
        let declared = try FileManager.default
            .subpathsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix("Module.swift") }
            .map { try String(contentsOf: sources.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
        for id in NewGames.legacyKnownGameIDs {
            #expect(declared.contains(#"public let id = "\#(id)""#), "\(id) を宣言したモジュールが無い")
        }
    }
}

/// 増えたゲームの保存（#723 の受け入れ条件: 新規インストールで出さない・再起動で復活しない・消去で消える）。
@Suite("新しいゲームの保存")
@MainActor
struct NewGamesStorageTests {
    private static let v114 = Array(NewGames.legacyKnownGameIDs).sorted()
    private static let v115 = v114 + ["spider", "hanafuda"]

    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("新規インストールでは NEW を出さない")
    func freshInstall() {
        let name = "asobiba.newgames.tests.fresh"
        let defaults = makeDefaults(name)
        #expect(PlayLog(defaults: defaults).newGameIDs(registeredIDs: Self.v115).isEmpty)
        defaults.removePersistentDomain(forName: name)
    }

    @Test("記録を持たない版から更新した人には、増えたゲームを NEW にする")
    func updateFromLegacy() {
        let name = "asobiba.newgames.tests.legacy"
        let defaults = makeDefaults(name)
        PlayLog(defaults: defaults).recordFinish(gameID: "2048")   // v1.1.4 で遊んだ痕跡

        #expect(PlayLog(defaults: defaults).newGameIDs(registeredIDs: Self.v115) == ["spider", "hanafuda"])
        defaults.removePersistentDomain(forName: name)
    }

    @Test("遊び方ガイドを見ただけ（終局なし）でも更新とみなす")
    func guideOnlyCountsAsHistory() {
        let name = "asobiba.newgames.tests.guide"
        let defaults = makeDefaults(name)
        PlayLog(defaults: defaults).markGuideShown(for: "sudoku")

        #expect(PlayLog(defaults: defaults).newGameIDs(registeredIDs: Self.v115) == ["spider", "hanafuda"])
        defaults.removePersistentDomain(forName: name)
    }

    @Test("同じ起動の中では何度聞いても同じ値。再起動すると復活しない")
    func shownOnceThenGone() {
        let name = "asobiba.newgames.tests.once"
        let defaults = makeDefaults(name)
        defaults.set(Self.v114, forKey: PlayLog.knownGameIDsKey)

        let first = PlayLog(defaults: defaults)
        #expect(first.newGameIDs(registeredIDs: Self.v115) == ["spider", "hanafuda"])
        #expect(first.newGameIDs(registeredIDs: Self.v115) == ["spider", "hanafuda"], "描き直しで消えない")

        let relaunched = PlayLog(defaults: defaults)
        #expect(relaunched.newGameIDs(registeredIDs: Self.v115).isEmpty, "再起動で復活しない")
        defaults.removePersistentDomain(forName: name)
    }

    @Test("次の更新では、その回に増えたゲームだけを NEW にする")
    func nextUpdateOnlyFlagsItsOwnAdditions() {
        let name = "asobiba.newgames.tests.next"
        let defaults = makeDefaults(name)
        defaults.set(Self.v114, forKey: PlayLog.knownGameIDsKey)
        _ = PlayLog(defaults: defaults).newGameIDs(registeredIDs: Self.v115)

        let ids = PlayLog(defaults: defaults).newGameIDs(registeredIDs: Self.v115 + ["nonogram"])
        #expect(ids == ["nonogram"])
        defaults.removePersistentDomain(forName: name)
    }

    @Test("キーは PlayLog.allKeys に入り、プレイ記録の消去で消える")
    func clearedWithPlayLog() {
        let name = "asobiba.newgames.tests.clear"
        let defaults = makeDefaults(name)
        #expect(PlayLog.allKeys.contains(PlayLog.knownGameIDsKey))

        let log = PlayLog(defaults: defaults)
        log.recordFinish(gameID: "2048")
        _ = log.newGameIDs(registeredIDs: Self.v115)
        #expect(defaults.object(forKey: PlayLog.knownGameIDsKey) != nil)

        log.clear()
        #expect(defaults.object(forKey: PlayLog.knownGameIDsKey) == nil, "消去で残っている")
        #expect(log.newGameIDs(registeredIDs: Self.v115).isEmpty, "消去した起動の中でも NEW を出し続けない")
        // 消去後の起動は新規インストールと同じ扱い。
        #expect(PlayLog(defaults: defaults).newGameIDs(registeredIDs: Self.v115).isEmpty)
        defaults.removePersistentDomain(forName: name)
    }

    @Test("保存するのは登録ゲーム ID の1配列だけで、何度起動してもキーは増えない")
    func storageIsBounded() {
        let name = "asobiba.newgames.tests.size"
        let defaults = makeDefaults(name)
        for _ in 0..<5 { _ = PlayLog(defaults: defaults).newGameIDs(registeredIDs: Self.v115) }

        let domain = defaults.persistentDomain(forName: name) ?? [:]
        #expect(Set(domain.keys) == [PlayLog.knownGameIDsKey])
        #expect(defaults.stringArray(forKey: PlayLog.knownGameIDsKey) == Self.v115.sorted())
        defaults.removePersistentDomain(forName: name)
    }
}

/// NEW 印と1行の**結線**（#723）。カードは App ターゲットにあるため、ソースを走査して固定する。
@Suite("新しいゲームの印の結線")
struct NewGamesWiringTests {
    private static let motionTokens = [".transition(", ".animation(", "withAnimation", ".gameAnimation("]

    @Test("ハブは PlayLog に登録ゲーム全体を渡して判定し、カードへ isNew を渡している")
    func hubPassesIsNewToCard() throws {
        let source = try SourceScan.appSources()
        #expect(
            source.range(
                of: #"services\.playLog\?\.newGameIDs\(\s*registeredIDs: registry\.modules\.map\(\\\.id\)\s*\)"#,
                options: .regularExpression
            ) != nil,
            "ハブが PlayLog.newGameIDs を登録ゲーム全体で呼んでいない"
        )
        #expect(
            source.range(of: #"GameCard\([^{}]*isNew: newGameIDs\.contains\(module\.id\)"#, options: .regularExpression) != nil,
            "グリッドのカードに isNew が渡っていない"
        )
    }

    @Test("1行はグリッドのスクロール領域の外（上）に置き、アニメーションを付けない")
    func noticeIsOutsideGridWithoutMotion() throws {
        let source = try SourceScan.appSources()
        let body = try #require(source.range(of: "struct HubView: View {"))
        let rest = source[body.upperBound...]
        let notice = try #require(rest.range(of: "HubNewGamesNotice(message:"), "1行がハブに置かれていない")
        let grid = try #require(rest.range(of: "ScrollView {"), "グリッドの ScrollView が見つからない")
        #expect(notice.lowerBound < grid.lowerBound, "1行がスクロール領域の中にある（#485）")

        let typeStart = try #require(source.range(of: "struct HubNewGamesNotice: View {"), "1行の型が見つからない")
        let typeRest = source[typeStart.upperBound...]
        let typeEnd = ["\nstruct ", "\nprivate struct ", "\nextension "]
            .compactMap { typeRest.range(of: $0)?.lowerBound }
            .min() ?? typeRest.endIndex
        let type = source[typeStart.lowerBound..<typeEnd]
        for token in Self.motionTokens {
            #expect(!type.contains(token), "1行に \(token) がある")
        }
    }

    @Test("ゲームを開いたら、そのゲームの NEW 印を外す")
    func openingGameClearsBadge() throws {
        let source = try SourceScan.appSources()
        #expect(
            source.range(
                of: #"if oldPath\.isEmpty, let opened = newPath\.first \{[\s\S]{0,600}?newGameIDs\.remove\(opened\.gameID\)"#,
                options: .regularExpression
            ) != nil,
            "ゲームを開いた経路で NEW 印を外していない"
        )
    }

    @Test("NEW 印は読み上げにも含める")
    func badgeIsSpoken() throws {
        let source = try SourceScan.appSources()
        #expect(source.contains(#"if isNew { parts.append("新着") }"#), "カードの読み上げに新着が入っていない")
    }
}
