import Foundation
import Testing
import GameKitTestSupport
@testable import Core

/// ホーム画面アイコン長押し（#1642）の項目の組み立て。`UIApplicationShortcutItem` への変換は
/// App ターゲットにあるので、件数・順序・ゼロ件・種別の往復だけをここで固定する。
@Suite("Quick Actions の項目")
struct QuickActionsTests {
    private static let visible = ["shogi", "poker", "2048", "othello", "sudoku", "mahjong"]
    private static let titles = [
        "shogi": "将棋", "poker": "ポーカー", "2048": "2048",
        "othello": "オセロ", "sudoku": "数独", "mahjong": "麻雀",
    ]

    private static func date(_ minutesAgo: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 - Double(minutesAgo) * 60)
    }

    private static func items(
        visible: [String] = visible, resuming: Set<String> = [], lastPlayedAt: [String: Date] = [:]
    ) -> [QuickActions.Item] {
        QuickActions.items(
            candidates: RecentGames.candidates(
                visibleGameIDs: visible, resumingGameIDs: resuming, lastPlayedAt: lastPlayedAt
            ),
            title: { titles[$0] }
        )
    }

    @Test("プレイ記録も中断も無ければ項目ゼロ")
    func emptyWhenNothingPlayed() {
        #expect(Self.items().isEmpty)
    }

    @Test("5本以上遊んでいても最大4件で打ち切る")
    func capsAtFour() {
        let played = Dictionary(uniqueKeysWithValues: Self.visible.enumerated().map { ($1, Self.date($0)) })
        let items = Self.items(lastPlayedAt: played)
        #expect(items.count == 4)
        #expect(items.map(\.gameID) == ["shogi", "poker", "2048", "othello"])
    }

    @Test("続きから可能なゲームが先で、補足に「続きから」が付く")
    func resumingFirstWithSubtitle() {
        let items = Self.items(
            resuming: ["mahjong"], lastPlayedAt: ["poker": Self.date(1), "mahjong": Self.date(5)]
        )
        #expect(items.map(\.gameID) == ["mahjong", "poker"])
        #expect(items.map(\.subtitle) == ["続きから", nil])
        #expect(items.map(\.title) == ["麻雀", "ポーカー"])
    }

    @Test("非表示にしたゲームは項目に出ない")
    func hiddenGamesAreExcluded() {
        let items = Self.items(
            visible: Self.visible.filter { $0 != "poker" },
            lastPlayedAt: ["poker": Self.date(1), "shogi": Self.date(9)]
        )
        #expect(items.map(\.gameID) == ["shogi"])
    }

    @Test("名前を引けないゲームは項目から外れる")
    func untitledGamesAreDropped() {
        let items = QuickActions.items(
            candidates: [.init(gameID: "ghost", hasResume: true), .init(gameID: "shogi", hasResume: false)],
            title: { Self.titles[$0] }
        )
        #expect(items.map(\.gameID) == ["shogi"])
    }

    @Test("種別はゲーム ID と往復でき、他人の種別は拒む")
    func typeRoundTrips() {
        let item = Self.items(lastPlayedAt: ["shogi": Self.date(1)])[0]
        #expect(QuickActions.gameID(fromType: item.type) == "shogi")
        #expect(QuickActions.gameID(fromType: "other.type") == nil)
        #expect(QuickActions.gameID(fromType: QuickActions.typePrefix) == nil)
    }

    @Test("結線: 起動時・起動中の両方の受け口と、ハブの遷移・項目の組み直しが残っている")
    func wiringIsPresent() throws {
        let source = try SourceScan.appSources()
        #expect(source.contains("options.shortcutItem"), "コールド起動の項目を AppDelegate が受けていない")
        #expect(source.contains("performActionFor shortcutItem"), "起動中・復帰のタップを受ける口が無い")
        #expect(source.contains("source: .quickAction"), "ハブが quick_action の導線で開いていない")
        #expect(source.contains("AppEnvironment.quickActions.refresh("), "項目の組み直しが呼ばれていない")
    }
}
