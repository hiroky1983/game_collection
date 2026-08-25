import Testing
import Foundation
@testable import GameConcentration

/// 終局演出と手番表示の演出（#208）。
///
/// 見た目そのものはシミュレータでしか確認できないので、**演出のトーン（長さの大小関係）**と
/// **View への結線**をここで固定する。定数だけを見ても View 側で外されれば素通しになるため、
/// `PokerMotionTests`（#206）と同じやり方でソースからも見る。
@Suite("神経衰弱の演出")
struct ConcentrationMotionTests {

    typealias Motion = ConcentrationMotion

    @Test("演出のトーンは手番の切り替え < 終局のフェード ≦ カードめくりの順")
    func toneIsLighterThanTheCardFlip() {
        // 何十回も起きる手番の入れ替えが最も軽く、1ゲームに1度の終局が重い、という濃淡。
        // 受け入れ条件3（既存のカードめくりとトーンが揃う）をここで固定する。
        #expect(Motion.turnHighlightDuration < Motion.resultOverlayFadeDuration)
        #expect(Motion.resultOverlayFadeDuration <= Motion.cardFlipResponse)

        // 一瞬で終わって気づけない・待たされ過ぎる、の両側を押さえる。
        #expect(Motion.turnHighlightDuration >= 0.1)
        #expect(Motion.cardFlipResponse <= 0.5)
    }

    @Test("終局オーバーレイは最後のめくりが返りきってから出る")
    func resultOverlayWaitsForTheFinalFlip() {
        // `isGameOver` は最後のペア成立と同じ更新で真になる（ConcentrationModel.checkGameOver）。
        // 待ちがめくりより短いと、最後の2枚が返る途中で暗幕が降りて決め手が見えなくなる。
        #expect(Motion.resultOverlayDelay >= Motion.cardFlipResponse)
        // 待ちが伸びすぎると「勝ったのか負けたのか」の答えが遅れて固まったように見える。
        #expect(Motion.resultOverlayDelay + Motion.resultOverlayFadeDuration <= 0.8)
    }

    @Test("カードめくりの跳ねが揺れ続けない範囲にある")
    func cardFlipDampingStaysCalm() {
        #expect(Motion.cardFlipDamping > 0.5)
        #expect(Motion.cardFlipDamping <= 1.0)
    }

    @Test("View が終局のフェード・手番の切り替え・めくりに結線されている")
    func viewIsWiredToTheMotion() throws {
        let source = try Self.viewSource()

        // 終局オーバーレイ: transition と、それを動かすアニメーションの両方が要る。
        // どちらか片方だけだと出現は従来どおり瞬間表示のままになる。
        #expect(
            Self.matchCount(of: #"resultOverlay\s*\n\s*\.transition\(\.opacity\)"#, in: source) == 1,
            "終局オーバーレイに .transition(.opacity) が付いていない"
        )
        #expect(
            Self.matchCount(of: #"ConcentrationMotion\.resultOverlayFade"#, in: source) == 1,
            "終局オーバーレイが ConcentrationMotion.resultOverlayFade で animate されていない"
        )
        // 旧実装（overlay 直下の素の if）に戻っていないこと。戻ると上の件数が保たれたまま
        // ZStack が消えて transition が効かなくなる。
        #expect(
            Self.matchCount(of: #"\.overlay \{\s*\n\s*if model\.isGameOver"#, in: source) == 0,
            "終局オーバーレイが transition の効かない素の if に戻っている"
        )

        // 手番のアクティブ表示。
        #expect(
            Self.matchCount(of: #"ConcentrationMotion\.turnHighlight, value: isActive"#, in: source) == 1,
            "手番のアクティブ表示が isActive で animate されていない"
        )

        // 既存のカードめくり。定数へ寄せたあとも結線が残っていること。
        #expect(
            Self.matchCount(of: #"ConcentrationMotion\.cardFlip, value: isFaceUp"#, in: source) == 1,
            "カードめくりが ConcentrationMotion.cardFlip で animate されていない"
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
            .deletingLastPathComponent()   // GameConcentrationTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GameConcentration/ConcentrationView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func matchCount(of pattern: String, in source: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(
            in: source, range: NSRange(source.startIndex..., in: source)
        )
    }
}
