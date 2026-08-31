import Testing
import Foundation
@testable import GamePoker

/// ショーダウン（CPU 手札の公開）とポット表示の演出（#206）。
///
/// 見た目そのものはシミュレータでしか確認できないので、**進捗 → 見え方の翻訳**と
/// **長さの大小関係**をここで固定する。定数だけでは View 側の外し忘れを素通しするため、
/// 結線も `PokerMetricsTests` と同じやり方でソースから見る。
@Suite("ポーカーの演出")
struct PokerMotionTests {

    typealias Motion = PokerMotion

    @Test("反転の前半は裏・真横を越えたら表")
    func flipSwapsFaceAtHalfway() {
        #expect(Motion.showsFace(progress: 0) == false)
        #expect(Motion.showsFace(progress: 0.49) == false)
        #expect(Motion.showsFace(progress: 0.5) == true)
        #expect(Motion.showsFace(progress: 1) == true)
    }

    @Test("回転角は 0 度から 180 度まで単調に進み、範囲外は頭打ちになる")
    func flipDegreesAreMonotonicAndClamped() {
        #expect(abs(Motion.flipDegrees(progress: 0) - 0) < 0.0001)
        #expect(abs(Motion.flipDegrees(progress: 0.5) - 90) < 0.0001)
        #expect(abs(Motion.flipDegrees(progress: 1) - 180) < 0.0001)

        // バネ等で 0〜1 を外れた進捗が来ても、カードが裏返り過ぎないこと。
        #expect(abs(Motion.flipDegrees(progress: -0.2) - 0) < 0.0001)
        #expect(abs(Motion.flipDegrees(progress: 1.2) - 180) < 0.0001)

        var previous = -1.0
        for step in 0...10 {
            let degrees = Motion.flipDegrees(progress: Double(step) / 10)
            #expect(degrees > previous)
            previous = degrees
        }
    }

    @Test("5 枚ぶんの段差を含めた全体の長さが定数と一致する")
    func totalDurationCoversEveryCard() {
        let expected = Motion.showdownFlipDuration + Motion.showdownStagger * Double(Motion.cardsPerHand - 1)
        #expect(abs(Motion.showdownTotalDuration - expected) < 0.0001)
        #expect(Motion.cardsPerHand == 5)
        // 段差が無くなると 5 枚が同時に返り、何枚めが何かを追えなくなる。
        #expect(Motion.showdownStagger > 0)
        // 山場が一瞬で終わらないこと・待たされ過ぎないことの両側を押さえる。
        #expect(Motion.showdownFlipDuration >= 0.2)
        #expect(Motion.showdownTotalDuration <= 0.8)
    }

    @Test("演出のトーンはポット ≦ 手札の選択 < 反転1枚 < ショーダウン全体の順")
    func showdownIsTheHeaviestEffect() {
        // 山場（ショーダウン）が最も濃く、日常操作（数値の入れ替え・カードの選択）は軽い、
        // という濃淡を固定する（#206 の受け入れ条件3。もとは逆転していた）。
        #expect(Motion.potChangeDuration <= Motion.handSelectionResponse)
        #expect(Motion.handSelectionResponse <= Motion.showdownFlipDuration)
        #expect(Motion.showdownFlipDuration < Motion.showdownTotalDuration)
    }

    @Test("View がショーダウンの反転とポットの数値遷移に結線されている")
    func viewIsWiredToTheMotion() throws {
        let source = try Self.viewSource()

        // CPU の手札が反転ビュー経由で描かれていること（定義 1 + 呼び出し 1）。
        #expect(
            Self.matchCount(of: #"FlipRevealCardView"#, in: source) >= 2,
            "CPU の手札が FlipRevealCardView を経由していない"
        )
        #expect(
            Self.matchCount(of: #"PokerMotion\.showdownFlip\(index:"#, in: source) == 1,
            "反転に段差付きのアニメーションが掛かっていない"
        )
        // 反転の前に、旧実装（素の CardView を faceUp フラグで切り替えるだけ）へ
        // 戻っていないことも見る。戻ると上の件数が保たれたまま演出だけ消えうる。
        #expect(
            Self.matchCount(of: #"CardView\(card: card, faceUp: revealCPU"#, in: source) == 0,
            "CPU の手札が素の CardView に戻っている"
        )

        // ポットの数値遷移。
        #expect(
            Self.matchCount(of: #"\.contentTransition\(\.numericText\(value:"#, in: source) == 1,
            "ポットの枚数に数値トランジションが掛かっていない"
        )
        #expect(
            Self.matchCount(of: #"PokerMotion\.potChange"#, in: source) >= 1,
            "ポットの枚数変化が PokerMotion.potChange で animate されていない"
        )
        // 位置まで animate されると、画面が動く場面で数字だけがポットの枠の外へ滑る（実測）。
        #expect(
            Self.matchCount(of: #"\.geometryGroup\(\)"#, in: source) == 1,
            "ポットの枚数に .geometryGroup() が付いていない（数字が枠外へ滑る）"
        )

        // Reduce Motion に追従しない素の `.animation(` が紛れ込んでいないこと（#210）。
        #expect(
            Self.matchCount(of: #"[^e]\.animation\("#, in: source) == 0,
            "Reduce Motion に追従しない .animation( が使われている"
        )
    }

    // MARK: - ヘルパー

    private static func viewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GamePokerTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GamePoker/PokerView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func matchCount(of pattern: String, in source: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(
            in: source, range: NSRange(source.startIndex..., in: source)
        )
    }
}
