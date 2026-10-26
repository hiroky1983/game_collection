import Testing
import Foundation
import GameKitTestSupport
@testable import GamePoker

/// ショーダウン（CPU 手札の公開）と合計点の表示の演出（#206・#2551）。
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

    @Test("演出のトーンは合計点 ≦ 手札の選択 < 反転1枚 < ショーダウン全体の順")
    func showdownIsTheHeaviestEffect() {
        // 山場（ショーダウン）が最も濃く、日常操作（数値の入れ替え・カードの選択）は軽い、
        // という濃淡を固定する（#206 の受け入れ条件3。もとは逆転していた）。
        #expect(Motion.pointsChangeDuration <= Motion.handSelectionResponse)
        #expect(Motion.handSelectionResponse <= Motion.showdownFlipDuration)
        #expect(Motion.showdownFlipDuration < Motion.showdownTotalDuration)
    }

    @Test("View がショーダウンの反転と合計点の数値遷移に結線されている")
    func viewIsWiredToTheMotion() throws {
        let source = try Self.viewSource()

        // CPU の手札が反転ビュー経由で描かれていること（定義 1 + 呼び出し 1）。
        #expect(
            SourceScan.matchCount(of: #"FlipRevealCardView"#, in: source) >= 2,
            "CPU の手札が FlipRevealCardView を経由していない"
        )
        #expect(
            SourceScan.matchCount(of: #"PokerMotion\.showdownFlip\(index:"#, in: source) == 1,
            "反転に段差付きのアニメーションが掛かっていない"
        )
        // 反転の前に、旧実装（素の CardView を faceUp フラグで切り替えるだけ）へ
        // 戻っていないことも見る。戻ると上の件数が保たれたまま演出だけ消えうる。
        #expect(
            SourceScan.matchCount(of: #"CardView\(card: card, faceUp: revealCPU"#, in: source) == 0,
            "CPU の手札が素の CardView に戻っている"
        )

        // 合計点の数値遷移。
        #expect(
            SourceScan.matchCount(of: #"\.contentTransition\(\.numericText\(value:"#, in: source) == 1,
            "合計点に数値トランジションが掛かっていない"
        )
        #expect(
            SourceScan.matchCount(of: #"PokerMotion\.pointsChange"#, in: source) >= 1,
            "合計点の変化が PokerMotion.pointsChange で animate されていない"
        )
        // 位置まで animate されると、画面が動く場面で数字だけが帯の外へ滑る（実測）。
        #expect(
            SourceScan.matchCount(of: #"\.geometryGroup\(\)"#, in: source) == 1,
            "合計点に .geometryGroup() が付いていない（数字が枠外へ滑る）"
        )

        // Reduce Motion に追従しない素の `.animation(` が紛れ込んでいないこと（#210）。
        #expect(
            SourceScan.matchCount(of: #"[^e]\.animation\("#, in: source) == 0,
            "Reduce Motion に追従しない .animation( が使われている"
        )
    }

    @Test("公開の合図は onChange だけが立てる（.result 直読みだと演出が飛ぶ）")
    func revealFlagIsDrivenOnlyByOnChange() throws {
        let source = try Self.viewSource()

        // `cpuRevealed` に `model.phase == .result` を混ぜると、`.result` に入った描画で
        // 既に真になる。役名 Text とカードはその描画で新規に挿入されるため
        // `.gameAnimation(_:value:)` に比較対象の前値が無く、遅延フェードも段差付きの反転も
        // 一度も走らない（= 役名がカードより先に出る・#383）。
        #expect(
            SourceScan.matchCount(of: #"cpuRevealed: Bool \{ revealCPU \}"#, in: source) == 1,
            "cpuRevealed が revealCPU 単独になっていない"
        )
        // 合図を立てるのは phase の変化を見る onChange の1か所だけ。
        #expect(
            SourceScan.matchCount(of: #"if phase == \.result \{ revealCPU = true \}"#, in: source) == 1,
            "公開の合図が onChange から立っていない"
        )
        // 役名と「○枚交換」バッジは「返り終わってから」出す遅延付き（2 か所）。定数ごと外れていないか見る。
        #expect(
            SourceScan.matchCount(of: #"\.delay\(PokerMotion\.showdownTotalDuration\)"#, in: source) == 2,
            "役名かバッジのフェードから、カードが返り終わるまでの遅延が外れている"
        )
    }

    @Test("役名が出る時刻は 5 枚の反転が終わる時刻と一致する（#667）")
    func revealDelayMatchesTheFlip() {
        #expect(Motion.showdownRevealDelay
            == .milliseconds(Int((Motion.showdownTotalDuration * 1000).rounded())))
    }

    @Test("ショーダウンの合計点は反転が終わるまで動かず、画面が遅れを Model へ渡している（#667）")
    func pointsWaitForTheReveal() throws {
        let motion = try SourceScan.packageSource("Sources/GamePoker/PokerMotion.swift")
        #expect(motion.contains("static let pointsSettle: Animation = pointsChange.delay(showdownTotalDuration)"))
        let view = try SourceScan.moduleSources("GamePoker")
        #expect(view.contains(".gameAnimation(pointsAnimation, value: model.playerPoints)"))
        #expect(view.contains("model.phase == .result ? PokerMotion.pointsSettle : PokerMotion.pointsChange"))
        #expect(view.contains(
            "showdownRevealDelay: Motion.isReduceMotionEnabled ? .zero : PokerMotion.showdownRevealDelay"
        ))
    }

    // MARK: - 「次の勝負へ」の待ち（#2701）

    @Test("次への待ちは、めくりと役名の出現が終わるまで（約0.85秒）")
    func nextButtonLockCoversReveal() {
        let lock = PokerMotion.nextButtonLockDuration
        #expect(lock >= PokerMotion.showdownTotalDuration + PokerMotion.pointsChangeDuration)
        #expect(lock < 0.9)
    }

    @Test("「次の勝負へ」は待ちが終わるまで押せない")
    func nextButtonIsDisabledWhileLocked() throws {
        let source = try Self.viewSource()
        #expect(SourceScan.matchCount(of: #"disabled: nextLocked"#, in: source) == 1)
        #expect(SourceScan.matchCount(of: #"PokerMotion\.nextButtonLockDuration"#, in: source) == 1)
    }

    // MARK: - ヘルパー

    /// モジュール一式を読む（#831）。コメントを落とすのは、`PokerMotion` の説明文にある
    /// `.contentTransition(.numericText(value:))` への言及が「1 か所」の件数に混ざるため。
    private static func viewSource() throws -> String {
        SourceScan.strippingComments(try SourceScan.moduleSources("GamePoker"))
    }
}
