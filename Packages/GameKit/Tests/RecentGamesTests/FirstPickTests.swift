import Foundation
import Testing
import GameKitTestSupport
@testable import Core

/// 記録がゼロの初回だけ出す「はじめの1本」（#721）。カードは App ターゲットにあるので、
/// 出す・出さないと何を出すかの規則だけをここで固定する。
@Suite("はじめの1本の選び方")
struct FirstPickTests {
    /// ハブの並び（既定の表示順の抜粋）。勧めるゲームを非表示にしたときの倒し先に効く。
    private static let visible = ["2048", "shogi", "mahjong4", "blackjack", "poker"]

    @Test("一度も終局していなければ、固定のゲームを勧める")
    func suggestsFixedGameWhenNothingPlayed() {
        let pick = FirstPick.gameID(playedGameIDs: [], visibleGameIDs: Self.visible, showsRecentRow: false)
        #expect(pick == "blackjack")
        #expect(pick == FirstPick.preferredGameID)
    }

    @Test("1本でも終局していたら出さない（勧めたゲーム以外で終局しても同じ）")
    func hiddenOnceAnyGameFinished() {
        #expect(FirstPick.gameID(playedGameIDs: ["blackjack"], visibleGameIDs: Self.visible, showsRecentRow: false) == nil)
        #expect(FirstPick.gameID(playedGameIDs: ["shogi"], visibleGameIDs: Self.visible, showsRecentRow: false) == nil)
    }

    @Test("記録の仕組みが無い環境では出さない")
    func hiddenWithoutPlayLog() {
        #expect(FirstPick.gameID(playedGameIDs: nil, visibleGameIDs: Self.visible, showsRecentRow: false) == nil)
    }

    @Test("「つづき・最近」の行が出ているあいだは並べない")
    func hiddenWhileRecentRowIsShown() {
        // 終局前でも中断データがあれば行が出る。「続きから」の導線と2段にしない。
        #expect(FirstPick.gameID(playedGameIDs: [], visibleGameIDs: Self.visible, showsRecentRow: true) == nil)
    }

    @Test("勧めるゲームを非表示にしていたら、並びの先頭に倒す")
    func fallsBackToFirstVisibleWhenPreferredIsHidden() {
        let visible = Self.visible.filter { $0 != FirstPick.preferredGameID }
        #expect(FirstPick.gameID(playedGameIDs: [], visibleGameIDs: visible, showsRecentRow: false) == "2048")
    }

    @Test("表示中のゲームが無ければ出さない")
    func hiddenWhenNoVisibleGames() {
        #expect(FirstPick.gameID(playedGameIDs: [], visibleGameIDs: [], showsRecentRow: false) == nil)
    }

    @Test("何度呼んでも同じゲームを返す（乱数なし）")
    func deterministic() {
        let picks = Set((0..<50).compactMap { _ in
            FirstPick.gameID(playedGameIDs: [], visibleGameIDs: Self.visible, showsRecentRow: false)
        })
        #expect(picks == ["blackjack"])
    }

    @Test("勧めるゲームの ID は、登録されているブラックジャックの ID と一致する")
    func preferredIDMatchesRegisteredModule() throws {
        // ID が綴り違いだと、勧めるゲームが「非表示」と同じ扱いになって先頭のゲームに黙って倒れる。
        // このテストターゲットは Core にしか依存しないため、モジュールの宣言を読んで突き合わせる。
        let source = try SourceScan.packageSource("Sources/GameBlackjack/BlackjackModule.swift")
        #expect(source.contains(#"public let id = "\#(FirstPick.preferredGameID)""#))
    }
}

/// 「はじめの1本」の**結線**（#721）。カードは App ターゲットにあるため、ソースを走査して固定する
/// （読み口は `SourceScan.appSources()` の `App/` 一式・行コメント除去済み）。
@Suite("はじめの1本の結線")
struct FirstPickWiringTests {
    /// アニメーションを付ける書き方。どれか1つでも入ると Reduce Motion 下で位置が動きうる。
    private static let motionTokens = [".transition(", ".animation(", "withAnimation", ".gameAnimation("]

    /// `HubView` の本体（`GameCard` の手前まで）。ファイル全体を見るとグリッド側の記述に当たる。
    private static func hubViewBody(_ source: String) throws -> Substring {
        let start = try #require(source.range(of: "struct HubView: View {"), "HubView が見つからない")
        let end = source.range(of: "private struct GameCard", range: start.upperBound..<source.endIndex)
        return source[start.lowerBound..<(end?.lowerBound ?? source.endIndex)]
    }

    @Test("出す条件は Core の規則（FirstPick）に、記録・表示中の並び・行の有無を渡して決めている")
    func conditionComesFromCore() throws {
        let body = try Self.hubViewBody(SourceScan.appSources())
        #expect(
            body.range(
                of: #"if let pick = FirstPick\.gameID\(\s*playedGameIDs: services\.playLog\?\.playedGameIDs,\s*visibleGameIDs: settings\.visibleModules\(from: registry\)\.map\(\\\.id\),\s*showsRecentRow: !recent\.isEmpty\s*\)"#,
                options: .regularExpression
            ) != nil,
            "ハブが FirstPick を使わずに出す条件を組んでいる、または渡す材料が違う"
        )
    }

    @Test("カードはグリッドと同じ NavigationLink(value:) で、導線 first_pick として遷移する")
    func cardUsesNavigationLinkWithFirstPickSource() throws {
        let body = try Self.hubViewBody(SourceScan.appSources())
        #expect(
            body.range(
                of: #"NavigationLink\(value: HubRoute\(\s*gameID: pick, source: \.firstPick, position: nil,\s*resume: [^\n]*\n\s*\)\) \{\s*HubFirstPickCard\("#,
                options: .regularExpression
            ) != nil,
            "はじめの1本が NavigationLink(value: HubRoute(... .firstPick ...)) で遷移していない"
        )
    }

    @Test("カードはグリッドのスクロール領域の外（上）に置く")
    func cardIsOutsideGridScrollView() throws {
        let body = try Self.hubViewBody(SourceScan.appSources())
        let card = try #require(body.range(of: "HubFirstPickCard("), "はじめの1本がハブに置かれていない")
        let grid = try #require(body.range(of: "ScrollView {"), "グリッドの ScrollView が見つからない")
        #expect(card.lowerBound < grid.lowerBound,
                "カードがスクロール領域の中にある（iPad のカード高さの割り付けが溢れる・#485）")
    }

    @Test("カードの出し入れにも中身にもアニメーションを付けない（Reduce Motion 下で位置が変わらない）")
    func noMotionOnCard() throws {
        let source = try SourceScan.appSources()
        let body = try Self.hubViewBody(source)
        let wiringStart = try #require(body.range(of: "if let pick = FirstPick.gameID("))
        let wiringEnd = try #require(body.range(of: "ScrollView {", range: wiringStart.upperBound..<body.endIndex))
        let wiring = body[wiringStart.lowerBound..<wiringEnd.lowerBound]

        let cardStart = try #require(source.range(of: "struct HubFirstPickCard: View {"), "カードの型が見つからない")
        let rest = source[cardStart.upperBound...]
        let cardEnd = ["\nstruct ", "\nprivate struct ", "\nextension "]
            .compactMap { rest.range(of: $0)?.lowerBound }
            .min() ?? rest.endIndex
        let card = source[cardStart.lowerBound..<cardEnd]

        for token in Self.motionTokens {
            #expect(!wiring.contains(token), "ハブ側の結線に \(token) がある")
            #expect(!card.contains(token), "カードに \(token) がある")
        }
    }
}
