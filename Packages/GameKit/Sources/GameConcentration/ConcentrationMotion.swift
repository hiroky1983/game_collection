import SwiftUI

/// 神経衰弱の演出の長さと形（#208）。**状態を持たない定数だけ**を置き、View から切り出す。
///
/// オセロ（`OthelloBoardStyle`）・ポーカー（`PokerMotion`）と同じ方針。`Animation` からは
/// 長さを読み出せないため、秒の定数を経由しないと「手番の切り替えはカードめくりより軽い」
/// のような**演出のトーン（濃淡）の大小関係をテストで固定できない**。
///
/// Reduce Motion への追従は `gameAnimation(_:value:)` 側が持つ（#210）。ON のときは
/// 補間が起きず、めくり・手番の色・終局オーバーレイはいずれも即時に切り替わるだけになる。
enum ConcentrationMotion {

    /// カードが裏から表へ返りきるまでの長さ（秒）。この演出が既存の基準で、
    /// 他の演出はこれより軽く（短く）することでトーンを揃える。
    static let cardFlipResponse: TimeInterval = 0.35

    /// カードめくりの跳ね方。1.0 に近いほど跳ねが減る。
    static let cardFlipDamping: Double = 0.75

    /// カードめくり。`isFaceUp` の変化に掛ける。
    static let cardFlip: Animation = .spring(
        response: cardFlipResponse, dampingFraction: cardFlipDamping
    )

    /// 手番のアクティブ表示（`scoreChip` の背景 Capsule と文字色）が入れ替わる長さ（秒）。
    ///
    /// 手番は1ゲームで何十回も入れ替わる**日常の変化**なので、めくりより軽く取る。
    /// 長くすると「どちらの番か」の答えが遅れて、次の1手を待たせることになる。
    static let turnHighlightDuration: TimeInterval = 0.2

    /// 手番のアクティブ表示の切り替え。
    static let turnHighlight: Animation = .easeInOut(duration: turnHighlightDuration)

    /// 終局オーバーレイがフェードインしきるまでの長さ（秒）。オセロ（#205）と同じ 0.25。
    static let resultOverlayFadeDuration: TimeInterval = 0.25

    /// 終局オーバーレイが出はじめるまでの待ち（秒）。
    ///
    /// `isGameOver` は**最後のペアが成立したのと同じ更新**で真になる（`ConcentrationModel.checkGameOver`）。
    /// 待ちが無いと、最後の2枚が返る 0.35 秒のあいだに暗幕が降りてしまい、
    /// 「何で終わったのか」が見えないまま結果だけが出る。めくりが返りきる時間だけ待つ。
    static let resultOverlayDelay: TimeInterval = cardFlipResponse

    /// 終局オーバーレイの出現。`.transition(.opacity)` と組で使う。
    static let resultOverlayFade: Animation = .easeOut(duration: resultOverlayFadeDuration)
        .delay(resultOverlayDelay)
}
