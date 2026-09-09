import Testing
import Foundation
@testable import GameBlackjack

/// 伏せカードの公開・配布・勝敗バッジの演出（#209）。
///
/// 見た目そのものはシミュレータでしか確認できないので、**進捗 → 見え方の翻訳**と
/// **長さの大小関係**をここで固定する。定数だけでは View 側の外し忘れを素通しするため、
/// 結線もポーカー（`PokerMotionTests`）と同じやり方でソースから見る。
@Suite("ブラックジャックの演出")
struct BlackjackMotionTests {

    typealias Motion = BlackjackMotion

    // MARK: - 受け入れ条件1: 伏せカードの公開

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

    // MARK: - 受け入れ条件2: 配布

    @Test("初期配牌はあなた→ディーラーの交互で、4 枚ぶんの段差になる")
    func dealDelaysAlternateBetweenSeats() {
        let s = Motion.dealStagger
        #expect(abs(Motion.dealDelay(index: 0, isDealer: false) - 0) < 0.0001)
        #expect(abs(Motion.dealDelay(index: 0, isDealer: true) - s) < 0.0001)
        #expect(abs(Motion.dealDelay(index: 1, isDealer: false) - s * 2) < 0.0001)
        #expect(abs(Motion.dealDelay(index: 1, isDealer: true) - s * 3) < 0.0001)

        // 段差が無くなると 4 枚が同時に出て、どちらに何枚配られたのかを追えなくなる。
        #expect(s > 0)
    }

    @Test("ヒット・ディーラーの引きで後から増えた 3 枚目以降は遅らせない")
    func extraCardsAreNotDelayed() {
        // 1 枚ずつ引く場面で段差ぶん待たされると、操作そのものが重く感じられる。
        for index in Motion.initialCardsPerHand...5 {
            #expect(abs(Motion.dealDelay(index: index, isDealer: false)) < 0.0001)
            #expect(abs(Motion.dealDelay(index: index, isDealer: true)) < 0.0001)
        }
        // 異常な index でも遅れが負にならないこと。
        #expect(abs(Motion.dealDelay(index: -1, isDealer: false)) < 0.0001)
    }

    @Test("4 枚ぶんの段差を含めた配布全体の長さが定数と一致する")
    func dealTotalCoversEveryCard() {
        let expected = Motion.dealCardDuration
            + Motion.dealStagger * Double(Motion.initialCardsPerHand * 2 - 1)
        #expect(abs(Motion.dealTotalDuration - expected) < 0.0001)
        #expect(Motion.initialCardsPerHand == 2)
        // ベットしてから盤面が揃うまでが長いと、毎ラウンド待たされる。
        #expect(Motion.dealTotalDuration <= 0.7)
    }

    @Test("配られる前のカードは実寸より小さく、上に持ち上がっている")
    func dealStartsAboveAndSmaller() {
        #expect(Motion.dealOffset < 0)          // 上（負方向）から落ちてくる
        #expect(Motion.dealStartScale < 1)      // 実寸より小さいところから
        #expect(Motion.dealStartScale > 0)
    }

    // MARK: - 演出のトーン

    @Test("演出のトーンは勝敗バッジ ≦ 配りの1枚 < 伏せカードの公開の順")
    func holeCardRevealIsTheHeaviestEffect() {
        // 山場（伏せカードの公開）が最も濃く、日常の表示（配り・バッジ）は軽い、という濃淡を固定する。
        #expect(Motion.outcomeBadgeDuration <= Motion.dealCardDuration)
        #expect(Motion.dealCardDuration < Motion.holeCardFlipDuration)
    }

    // MARK: - 受け入れ条件3 + 結線

    @Test("View が公開・配布・勝敗バッジの演出に結線されている")
    func viewIsWiredToTheMotion() throws {
        let source = try Self.viewSource()

        // 1. 伏せカードが反転ビュー経由で描かれていること（定義 1 + 呼び出し 1）。
        #expect(
            Self.matchCount(of: #"BJFlipCardView"#, in: source) >= 2,
            "ディーラーの手札が BJFlipCardView を経由していない"
        )
        #expect(
            Self.matchCount(of: #"BlackjackMotion\.holeCardFlip"#, in: source) == 1,
            "伏せカードの公開にアニメーションが掛かっていない"
        )
        // 旧実装（素の BJCardView を faceUp フラグで切り替えるだけ）へ戻っていないことも見る。
        // 戻ると上の件数が保たれたまま演出だけ消えうる。
        #expect(
            Self.matchCount(of: #"BJCardView\(card: card, faceUp: !hidden\)"#, in: source) == 0,
            "ディーラーの手札が素の BJCardView に戻っている"
        )

        // 2. 両者の手札が配布の演出を通っていること（定義 1 + ディーラー 1 + あなた 1）。
        #expect(
            Self.matchCount(of: #"BJDealtCardView"#, in: source) >= 3,
            "ディーラー・あなたの手札が BJDealtCardView を経由していない"
        )
        #expect(
            Self.matchCount(of: #"BlackjackMotion\.dealAppear\(index:"#, in: source) == 1,
            "配布に段差付きのアニメーションが掛かっていない"
        )
        // プレイヤー側は通常の手札とスプリット後の各手（#439）で複数箇所から呼ぶため
        // 件数は固定しない。ディーラー側は 1 箇所のままであることを見る。
        #expect(
            Self.matchCount(of: #"isDealer: true"#, in: source) == 1
                && Self.matchCount(of: #"isDealer: false"#, in: source) >= 1,
            "配る順（あなた → ディーラー）の指定が View 側で失われている"
        )

        // 3. 勝敗バッジのトランジション。
        #expect(
            Self.matchCount(of: #"BlackjackMotion\.outcomeBadge"#, in: source) == 1,
            "勝敗バッジがフェードで出ていない"
        )
        #expect(
            Self.matchCount(of: #"\.transition\(\.opacity"#, in: source) == 1,
            "勝敗バッジに .transition が付いていない"
        )

        // Reduce Motion に追従しない素の `.animation(` / `withAnimation(` が
        // 紛れ込んでいないこと（#210）。
        #expect(
            Self.matchCount(of: #"[^e]\.animation\("#, in: source) == 0,
            "Reduce Motion に追従しない .animation( が使われている"
        )
        #expect(
            Self.matchCount(of: #"[^e]withAnimation\("#, in: source) == 0,
            "Reduce Motion に追従しない withAnimation( が使われている"
        )
    }

    // MARK: - ヘルパー

    private static func viewSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // GameBlackjackTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // GameKit
            .appendingPathComponent("Sources/GameBlackjack/BlackjackView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func matchCount(of pattern: String, in source: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(
            in: source, range: NSRange(source.startIndex..., in: source)
        )
    }
}
