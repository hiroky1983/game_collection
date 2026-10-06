import Foundation
import Testing
import GameKitTestSupport
@testable import Core

/// 盤の下の「操作の段」（#1834・#1856。会長決裁 2026-10-06 の案A）。
///
/// 描画の大きさには出ない性質（等幅・44pt・2 行目の文字・どの操作を段に出しどれを「⋯」に残すか）を固定する。
@Suite("盤下の操作の段")
struct GameActionRowTests {
    private static func rowSource() throws -> String {
        SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/GameActionRow.swift"))
    }

    // MARK: - 2 行目（たたき台 6: 広告は「▶」、無料は「あと◯回」）

    @Test("残り回数は「あと n 回」、広告が要るときは ▶ 付きで「広告を見て」か「あと n 回」")
    func badgeText() {
        #expect(GameActionBadge.count(3).text == "あと3回")
        #expect(!GameActionBadge.count(3).needsAd)
        #expect(GameActionBadge.ad().text == "広告を見て")
        #expect(GameActionBadge.ad().needsAd)
        #expect(GameActionBadge.ad(remaining: 5).text == "あと5回")
        #expect(GameActionBadge.ad(remaining: 5).needsAd)
        #expect(GameActionBadge.none.text == nil)
        #expect(!GameActionBadge.none.needsAd)
    }

    /// 「▶」は音声では読めないので、読み上げには必ず「広告を見て」を含める。
    @Test("読み上げは広告の有無を言葉で含める")
    func badgeAccessibilityValue() {
        #expect(GameActionBadge.count(2).accessibilityValue == "あと2回")
        #expect(GameActionBadge.ad().accessibilityValue == "広告を見て")
        #expect(GameActionBadge.ad(remaining: 3).accessibilityValue == "広告を見て、あと3回")
        #expect(GameActionBadge.none.accessibilityValue == nil)
    }

    // MARK: - カプセルの見た目

    @Test("カプセルは等幅・44pt 以上で、当たり判定はカプセルの中。押せないときは消さずに薄くする")
    func capsuleIsEqualWidthAnd44pt() throws {
        let source = try Self.rowSource()
        let style = try #require(SourceScan.declaration(of: "struct GameActionCapsuleStyle", in: source))
        #expect(style.contains(".frame(maxWidth: .infinity, minHeight: GameButtonMetrics.minTapTarget)"), "等幅・44pt になっていない")
        #expect(style.contains(".contentShape(Capsule())"))
        #expect(style.contains("isEnabled ? role.fill : Theme.fillMuted"), "押せないときの面がグレーでない")
        #expect(style.contains(": 0.55)"), "押せないときの薄さが GameButtonStyle と揃っていない")
        let capsule = try #require(SourceScan.declaration(of: "struct GameActionCapsule: View", in: source))
        #expect(capsule.contains(".disabled(!item.isEnabled)"), "押せない状態を Button に結線していない")
        #expect(capsule.contains(".accessibilityValue(accessibilityValue)"), "2 行目を読み上げに渡していない")
    }

    @Test("「⋯」の行は段のカプセルを並べ、段が無ければ従来どおり右寄せの「⋯」だけ")
    func overflowBarLaysOutActions() throws {
        let bar = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/GameOverflowBar.swift"))
        let body = try #require(SourceScan.declaration(of: "public var body: some View", in: bar))
        #expect(body.contains("ForEach(actions) { GameActionCapsule(item: $0) }"))
        #expect(body.contains("if actions.isEmpty {"))
        #expect(body.contains("Spacer(minLength: 0)"), "段が無いときに「⋯」が右端へ寄らない")
        #expect(GameOverflowBar.captionMaxWidth <= 150, "段と並ぶ表示が広すぎて SE でカプセルが潰れる")
    }

    // MARK: - どの操作を段に出すか（会長決裁 2026-10-06: 広告が絡む操作だけ）

    /// `(モジュール, 段に出す id, 「⋯」に残す id)`。広告の無い操作（パス・ジョーカー・配る・メモ・旗モード・拡大・
    /// 投了・諦める・自動で上がる）を段に置き直すと、ここで赤くなる。
    static let placements: [(String, [String], [String])] = [
        ("GameConcentration", ["matta"], []),
        ("GameSolitaire", ["undo"], ["joker", "autoFinish"]),
        ("GameSpider", ["undo"], ["deal", "zoom"]),
        ("GameFreeCell", ["undo"], ["zoom", "autoFinish"]),
        // 麻雀ソリティア・ナンプレの戻すは回数制（無料のあと広告で補充・#1855）なので段。
        ("GameMahjongSolitaire", ["undo", "hint", "shuffle"], ["zoom"]),
        ("GameSudoku", ["undo", "hint"], ["note", "giveUp"]),
        ("GameMinesweeper", [], ["flag", "zoom", "giveUp"]),
    ]

    @Test("広告が絡む操作だけ段に出し、広告の無い操作は「⋯」に残す", arguments: placements.indices)
    func onlyAdActionsLiveInTheRow(index: Int) throws {
        let (module, rowIDs, menuIDs) = Self.placements[index]
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        for id in rowIDs {
            #expect(SourceScan.matchCount(of: #"GameActionItem\(\s*id: "\#(id)""#, in: source) == 1, "\(module) の \(id) が段に無い")
            #expect(SourceScan.matchCount(of: #"GameControlMenuItem\(\s*id: "\#(id)""#, in: source) == 0, "\(module) の \(id) が「⋯」にも残っている")
        }
        for id in menuIDs {
            #expect(SourceScan.matchCount(of: #"GameControlMenuItem\(\s*id: "\#(id)""#, in: source) == 1, "\(module) の \(id) が「⋯」に無い")
            #expect(SourceScan.matchCount(of: #"GameActionItem\(\s*id: "\#(id)""#, in: source) == 0, "\(module) の \(id) が段に出ている")
        }
        if rowIDs.isEmpty {
            #expect(SourceScan.matchCount(of: #"GameActionItem\("#, in: source) == 0,
                    "\(module) に段がある（ゲーム中に広告の操作が無いので「⋯」だけのはず）")
        }
    }

    /// 麻雀ソリティアのヒント・並べ替えは毎回広告（上限なし）、神経衰弱の待ったは 1 局 1 回無料のあと広告。
    @Test("麻雀ソリティアと神経衰弱の 2 行目は広告の有無を ▶ で見せる")
    func mahjongAndConcentrationBadges() throws {
        let mahjong = SourceScan.strippingComments(try SourceScan.moduleSources("GameMahjongSolitaire"))
        #expect(SourceScan.matchCount(of: #"id: "hint", title: "ヒント", systemImage: "lightbulb.fill", role: \.hint, badge: \.ad\(\)"#, in: mahjong) == 1,
                "麻雀ソリティアのヒントの 2 行目が「▶ 広告を見て」でない")
        #expect(SourceScan.matchCount(of: #"id: "shuffle", title: "並べ替え", systemImage: "shuffle", role: \.primary, badge: \.ad\(\)"#, in: mahjong) == 1,
                "麻雀ソリティアの並べ替えの 2 行目が「▶ 広告を見て」でない")
        let concentration = SourceScan.strippingComments(try SourceScan.moduleSources("GameConcentration"))
        #expect(concentration.contains("badge: model.mattaUsed ? .ad() : .count(1)"),
                "神経衰弱の待ったの 2 行目が無料 1 回 → 広告になっていない")
    }

    /// 専用の読み上げ文（「1手戻す、残り3回」など残り回数を含む）を渡した項目では 2 行目を重ねて読まない。
    /// 渡していない項目（盤ゲームの待った・麻雀ソリティア）は題 + 2 行目を読む。
    @Test("読み上げ文を渡した項目では 2 行目を重ねて読まない")
    func accessibilityValueIsNotDuplicated() throws {
        let source = try Self.rowSource()
        let capsule = try #require(SourceScan.declaration(of: "struct GameActionCapsule: View", in: source))
        #expect(capsule.contains("guard item.accessibilityLabel == nil else { return \"\" }"))
        let bar = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/BoardGameControlBar.swift"))
        #expect(!bar.contains(#"accessibilityLabel: "待った""#), "盤ゲームの待ったに題と同じ読み上げ文を渡していて 2 行目が読まれない")
    }

    @Test("盤ゲーム 5 本の共通の行は待った・ヒントを段に、ゲーム固有の項目（囲碁のパス）と投了を「⋯」に置く")
    func boardGamesRowPlacement() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/BoardGameControlBar.swift"))
        #expect(SourceScan.matchCount(of: #"GameActionItem\(\s*id: "undo""#, in: source) == 1)
        #expect(SourceScan.matchCount(of: #"GameActionItem\(\s*id: "hint""#, in: source) == 1)
        #expect(source.contains("badge: model.undoUsed ? .ad() : .count(1)"), "待ったの 2 行目が無料 1 回 → 広告になっていない")
        let menu = try #require(SourceScan.declaration(of: "private var menuItems: [GameControlMenuItem]", in: source))
        #expect(menu.contains("extraItems +"), "囲碁のパスが「⋯」に無い")
        #expect(menu.contains(#"id: "resign""#))
        // 囲碁のパスは `extraItems` 経由で「⋯」に入る（段には出さない）。
        let go = SourceScan.strippingComments(try SourceScan.moduleSources("GameGo"))
        #expect(go.contains(#"GameControlMenuItem(id: "pass""#) || SourceScan.matchCount(of: #"GameControlMenuItem\(\s*id: "pass""#, in: go) == 1,
                "囲碁のパスが GameControlMenuItem でない")
    }

    @Test("ナンプレのヒントは 2 行目に広告と残り回数（▶ あと n 回）を出す")
    func sudokuHintShowsAdAndRemaining() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameSudoku"))
        #expect(source.contains("badge: .ad(remaining: model.remainingHints)"))
    }

    @Test("ソリティア・スパイダー・フリーセル・麻雀ソリティア・ナンプレの戻すは無料の残りを出し、使い切ったら「▶ 広告を見て」",
          arguments: ["GameSolitaire", "GameSpider", "GameFreeCell", "GameMahjongSolitaire", "GameSudoku"])
    func undoBadgeShowsRemainingThenAd(module: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        #expect(source.contains("badge: model.undosRemaining > 0 ? .count(model.undosRemaining) : .ad()"),
                "\(module) の戻すの 2 行目が残り回数 → 広告になっていない")
    }

    /// 段の並びはソリティア系・盤ゲームと同じく「戻す → 助ける（ヒント）」。麻雀ソリティアはその後ろに並べ替え。
    @Test("麻雀ソリティア・ナンプレの段は戻す → ヒント（→ 並べ替え）の順",
          arguments: [("GameMahjongSolitaire", ["undo", "hint", "shuffle"]), ("GameSudoku", ["undo", "hint"])])
    func undoComesFirstInTheRow(module: String, order: [String]) throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
        let positions = try order.map { id in
            try #require(source.range(of: #"GameActionItem\(\s*id: "\#(id)""#, options: .regularExpression),
                         "\(module) の \(id) が段に無い").lowerBound
        }
        #expect(positions == positions.sorted(), "\(module) の段の並びが \(order) でない")
    }

    /// 「⋯」の行の左端にあった表示だけの文字の置き場所（#1856）。神経衰弱はカプセルの 2 行目、スパイダーは段と「⋯」のあいだ、
    /// ソリティアのルール名は状態の帯。
    @Test("行の左端にあった一言は、段のあるゲームでも読める場所に残る")
    func captionsSurviveTheRow() throws {
        let concentration = SourceScan.strippingComments(try SourceScan.moduleSources("GameConcentration"))
        #expect(concentration.contains(#"note: model.canMatta ? "今だけ！" : nil"#), "神経衰弱の「今だけ」が消えている")
        let spider = SourceScan.strippingComments(try SourceScan.moduleSources("GameSpider"))
        #expect(spider.contains(#"GameOverflowCaption("空の列を埋めると配れます""#), "スパイダーの配れない理由が消えている")
        let solitaire = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameSolitaire/SolitaireView.swift"))
        let status = try #require(SourceScan.declaration(of: "private var statusBar: some View", in: solitaire))
        #expect(status.contains("if model.rules.drawMode != .one {"), "ソリティアのルール名が帯に無い")
        #expect(!status.contains("Button"), "帯にボタンがある")
    }
}
