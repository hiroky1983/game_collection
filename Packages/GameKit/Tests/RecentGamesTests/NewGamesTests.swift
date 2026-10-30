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
            source.range(of: #"GameCard\([^{}]*isNew: NewGames\.currentVersionIDs\.contains\(module\.id\)"#, options: .regularExpression) != nil,
            "グリッドのカードに isNew が渡っていない"
        )
    }

    @Test("ハブに「新しいあそびが n 本増えました」の1行を出さない（#2175・モックに無い。NEW の印で足りる）")
    func noticeIsNotShownOnHub() throws {
        let source = try SourceScan.appSources()
        #expect(!source.contains("NewGames.notice("), "ハブに新着の1行が戻っている")
    }

    @Test("新着はグリッドの先頭へ固定する（#2104。柵越えおじさんは #2566 から通常のタイルで、この固定に従う）")
    func gridPinsNewGames() throws {
        let source = try SourceScan.appSources()
        #expect(
            source.range(of: #"NewGames\.pinned\(visibleIDs: visible\.map\(\\\.id\)\)"#, options: .regularExpression) != nil,
            "ハブの並びが NewGames.pinned を通っていない"
        )
        #expect(
            source.range(of: #"let entries = pinnedVisibleModules\.enumerated\(\)"#, options: .regularExpression) != nil,
            "グリッドが固定済みの並びを使っていない"
        )
    }

    @Test("NEW は「続きから」より優先して出す（#2104）")
    func newBadgeBeatsResume() throws {
        let source = try SourceScan.appSources()
        let newAt = try #require(source.range(of: #"var badge: some View \{\s*if isNew \{"#, options: .regularExpression))
        let resumeAt = try #require(source.range(of: #"\} else if hasResume \{"#, options: .regularExpression))
        #expect(newAt.lowerBound < resumeAt.lowerBound)
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
        #expect(source.contains(#"if isNew { parts.append(tr("新着")) }"#), "カードの読み上げに新着が入っていない")
    }
}

@Suite("この版の新着（#2104）")
struct NewGamesPinnedTests {
    @Test("新着は先頭へ、そのあとに元の順。それぞれ元の順を保つ")
    func pinsNewFirstKeepingOrder() {
        let order = NewGames.pinned(visibleIDs: ["2048", "b", "a", "c"], newIDs: ["a", "b"])
        #expect(order == ["b", "a", "2048", "c"])
    }

    @Test("非表示（visibleIDs に無い）の新着は出てこない")
    func hiddenNewGameStaysHidden() {
        #expect(NewGames.pinned(visibleIDs: ["2048", "a"], newIDs: ["a", "b"]) == ["a", "2048"])
    }

    @Test("新着が無ければ並びは変わらない")
    func noNewKeepsOrder() {
        #expect(NewGames.pinned(visibleIDs: ["x", "y"], newIDs: []) == ["x", "y"])
    }

    @Test("v1.1.15 は新着なし（#3112）: NEW 印・先頭固定・感想カードの対象が空")
    func currentVersionIDsIsEmpty() {
        #expect(NewGames.currentVersionIDs.isEmpty)
        let order = ["2048", "catpuzzle", "speed", "oldmaid", "hearts"]
        #expect(NewGames.pinned(visibleIDs: order) == order, "登録順のまま")
        #expect(!ReviewRequestPolicy.shouldAskAboutNewGame(state: .init(), gameID: "catpuzzle"))
        #expect(NewGames.notice(count: NewGames.currentVersionIDs.count) == nil)
    }

    @Test("新着の記録が無い・全ゲームが既知でも、空集合で全ゲームを新着扱いしない")
    func emptyCurrentDoesNotFlagEverything() {
        #expect(NewGames.ids(registeredIDs: ["a", "b"], knownIDs: ["a", "b"], hasPlayHistory: true).isEmpty)
        #expect(NewGames.ids(registeredIDs: ["a", "b"], knownIDs: nil, hasPlayHistory: false).isEmpty)
    }
}

@Suite("新着固定下の「いちばん上に置く」（#2124）")
struct NewGamesMoveToTopTests {
    private static let order = ["a", "b", "x", "y", "z"]
    private static let new: Set<String> = ["a", "b"]

    @Test("新着だけが前にある通常ゲームは、表示上すでに先頭（新着の次）なので無効")
    func firstAfterNewIsAtTop() {
        #expect(NewGames.isAlreadyAtTop(id: "x", orderedIDs: Self.order, hiddenIDs: [], newIDs: Self.new))
    }

    @Test("その次以降のゲームは動かせる")
    func laterIsMovable() {
        #expect(!NewGames.isAlreadyAtTop(id: "y", orderedIDs: Self.order, hiddenIDs: [], newIDs: Self.new))
    }

    @Test("前に非表示のゲームがあれば動かす余地がある")
    func hiddenAheadIsMovable() {
        #expect(!NewGames.isAlreadyAtTop(id: "x", orderedIDs: ["h", "a", "x"], hiddenIDs: ["h"], newIDs: ["a"]))
    }

    @Test("前に非表示の新着があるときも動かす余地がある")
    func hiddenNewAheadIsMovable() {
        #expect(!NewGames.isAlreadyAtTop(id: "x", orderedIDs: ["a", "x"], hiddenIDs: ["a"], newIDs: ["a"]))
    }

    @Test("新着自身は並びの先頭のときだけ無効")
    func newGameOnlyAtVeryTop() {
        #expect(NewGames.isAlreadyAtTop(id: "a", orderedIDs: Self.order, hiddenIDs: [], newIDs: Self.new))
        #expect(!NewGames.isAlreadyAtTop(id: "b", orderedIDs: Self.order, hiddenIDs: [], newIDs: Self.new))
    }

    @Test("新着が無ければ従来どおり、並びの先頭だけが無効")
    func noNewBehavesAsBefore() {
        #expect(NewGames.isAlreadyAtTop(id: "x", orderedIDs: ["x", "y"], hiddenIDs: [], newIDs: []))
        #expect(!NewGames.isAlreadyAtTop(id: "y", orderedIDs: ["x", "y"], hiddenIDs: [], newIDs: []))
    }

    @Test("案内は新着が前に固定されているときだけ「新着の次」と言う")
    func announcement() {
        #expect(NewGames.moveToTopAnnouncement(title: "X", id: "y", orderedIDs: Self.order, hiddenIDs: [], newIDs: Self.new)
                == "「X」を新着の次に移しました")
        #expect(NewGames.moveToTopAnnouncement(title: "A", id: "b", orderedIDs: Self.order, hiddenIDs: [], newIDs: Self.new)
                == "「A」を先頭に移しました")
        #expect(NewGames.moveToTopAnnouncement(title: "X", id: "y", orderedIDs: Self.order, hiddenIDs: [], newIDs: [])
                == "「X」を先頭に移しました")
        #expect(NewGames.moveToTopAnnouncement(title: "X", id: "y", orderedIDs: ["a", "y"], hiddenIDs: ["a"], newIDs: ["a"])
                == "「X」を先頭に移しました")
    }
}

/// 更新タグ（#2790）。一覧に入ったゲームだけにタグが出る。
@Suite("更新タグ")
struct UpdatedGamesTests {
    @Test("一覧に入ったゲームだけにタグが出る。v1.1.15 はチャリンコおじさん（runner）の新ステージ追加")
    func onlyListedGames() {
        #expect(UpdatedGames.tag(for: "runner") == .newStage)
        #expect(UpdatedGames.tag(for: "2048") == nil)
        #expect(UpdatedGames.currentVersion.count == 1)
    }

    @Test("ブロック崩し（blocks）は一覧に 1 行足すだけでタグが出る。いまは付けない")
    func blocksReadyButOff() {
        #expect(UpdatedGames.tag(for: "blocks") == nil)
        #expect(UpdatedGames.tag(for: "blocks", in: ["blocks": .newStage]) == .newStage)
        #expect(UpdatedGames.tag(for: "runner", in: [:]) == nil)
    }

    @Test("タグの文言は種類ごとに持ち、英訳が xcstrings にある")
    func labelsAreLocalized() throws {
        let catalog = try SourceScan.packageSource("Sources/CoreEngine/Resources/Localization/Localizable.xcstrings")
        for tag in UpdateTag.allCases {
            let key = ["newStage": "新ステージ追加"][tag.rawValue] ?? ""
            #expect(catalog.contains("\"\(key)\" : {"), "\(tag.rawValue) の英訳が無い")
        }
    }

    @Test("タイルは NEW ＞ イベント ＞ 更新 ＞ 続きから の順で 1 つだけ出し、読み上げにも載せる")
    func badgePriorityWiring() throws {
        let source = try SourceScan.appSources()
        #expect(source.contains("updateTag: UpdatedGames.tag(for: module.id)"))
        let start = try #require(source.range(of: "private var badge: some View {"))
        let end = try #require(source.range(of: "\n    }\n", range: start.upperBound..<source.endIndex))
        let badge = String(source[start.lowerBound..<end.upperBound])
        let new = try #require(badge.range(of: #"badgeCapsule("NEW")"#))
        let event = try #require(badge.range(of: #"badgeCapsule(tr("イベント開催中"))"#))
        let update = try #require(badge.range(of: "badgeCapsule(updateTag.label)"))
        let resume = try #require(badge.range(of: #"badgeCapsule(tr("続きから"))"#))
        #expect(new.lowerBound < event.lowerBound && event.lowerBound < update.lowerBound && update.lowerBound < resume.lowerBound)
        #expect(source.contains("if let updateTag { parts.append(updateTag.label) }"), "読み上げに無い")
    }
}
