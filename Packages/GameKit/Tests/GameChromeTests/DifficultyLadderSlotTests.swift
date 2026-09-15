import Foundation
import SwiftUI
import Testing
import Core
import CoreTestSupport
import GameKitTestSupport

/// リザルトの「階段」（#722）がレコメンドの枠に正しく相乗りしていることを見る。
@Suite("難易度の階段の枠")
@MainActor
struct DifficultyLadderSlotTests {
    /// iPhone SE（第3世代）の内寸に近い幅。文字が詰まる狭い側で見る。
    private static let width: CGFloat = 343

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

    /// 勧める条件を満たした提案（最長の段名「むずかしい」で幅の厳しい側を見る）。
    private func makeLadder() -> DifficultyLadderPrompt? {
        let record = PlayRecord(
            plays: DifficultyLadder.streakThreshold,
            wins: DifficultyLadder.streakThreshold,
            currentStreak: DifficultyLadder.streakThreshold
        )
        return DifficultyLadderPrompt(
            result: RecordResult(record: record, update: RecordUpdate()),
            currentLevel: 1,
            levelLabels: ["かんたん", "ふつう", "むずかしい"]
        ) { _ in }
    }

    /// 枠を使う画面（`GameControlArea` 等）はひな形で高さを確保している。カードがひな形より
    /// 1pt でも高いと、勧めが出た瞬間に下の領域が伸びて盤が縮む（#148 と同じ失敗）。
    @Test("階段のカードは枠のひな形と同じ高さで出る", arguments: [DynamicTypeSize.large, .accessibility3])
    func matchesPlaceholderHeight(size: DynamicTypeSize) throws {
        let ladder = try #require(makeLadder())
        let placeholder = height(RecommendationCard.heightPlaceholder, size)
        // レコメンドは無い（`services.recommendations` が nil）ので、描かれた高さは階段のカードのものだけ。
        let slot = RecommendationSlot(services: makeServices(), isFinished: true, ladder: ladder)
        #expect(height(slot, size) == placeholder)
    }

    @Test("決着前は勧めがあっても何も描かない")
    func hiddenBeforeFinish() throws {
        let ladder = try #require(makeLadder())
        #expect(height(RecommendationSlot(services: makeServices(), isFinished: false, ladder: ladder)) == 0)
    }

    /// 難易度を持つゲームだけが勧めを出す。1 本でも配線を忘れると、そのゲームだけ階段が無い。
    /// 走査は**ゲームごとのディレクトリ一式**を読み、コメント行は除く（言及に当たって空振りしないため）。
    @Test("難易度を選べるゲームはすべて階段を枠へ渡している")
    func everyLeveledGameWiresLadder() {
        let sources = SourceScan.packageRoot.appendingPathComponent("Sources")
        let leveled = [
            "GameChess", "GameConcentration", "GameGo", "GameGomoku", "GameHanafuda",
            "GameMinesweeper", "GameOthello", "GameShogi", "GameSudoku",
        ]
        for name in leveled {
            let dir = sources.appendingPathComponent(name)
            let code = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { $0.hasSuffix(".swift") }
                .compactMap { try? String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }
                .flatMap { $0.split(separator: "\n") }
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            #expect(!code.isEmpty, "\(name) のソースが読めていない")
            #expect(code.contains("DifficultyLadderPrompt("), "\(name) が階段の提案を作っていない")
            #expect(code.contains("ladder: ladder"), "\(name) が階段の提案を枠へ渡していない")
        }
    }
}
