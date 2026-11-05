import GameKit
import UIKit

/// 実績・ランキング画面への導線（#334）。
///
/// v1.1.1 で実績4種・リーダーボード10種の**送信**（`AppGameCenterService`）は完成したが、
/// アプリ内から**見る手段が無かった**ため、解除された実績が誰にも気づかれないままだった。
/// ここはハブのツールバーから叩かれ、Apple 標準のダッシュボードを出すだけ。自前の画面は持たない。
///
/// 画面の出し方は `GKAccessPoint.trigger(state:)` を使う。`GKGameCenterViewController` は
/// **iOS 26.0 で deprecated**（SDK のヘッダが `Replaced by GKAccessPoint` と明記）で、
/// iOS 26 では Game Center の UI 自体が「ゲーム」アプリのオーバーレイに置き換わっているため。
/// なお `trigger` の完了ハンドラは iOS 26 で呼ばれない既知の不具合があるが
/// （Apple Developer Forums thread 797727・Feedback #19169961。**オーバーレイの表示自体は正常**）、
/// ここは閉じたあとに何もしないので影響を受けない。常設バッジ（`isActive`）は
/// ゲーム画面まで居座って邪魔になるため使わない。
@MainActor
enum GameCenterEntry {
    /// タップの結果。`needsSignInGuidance` のときだけ、呼び出し側が案内を出す。
    enum Outcome: Equatable {
        /// ダッシュボードを開いた。
        case openedDashboard
        /// 未サインインで、GameKit から預かっていたサインイン画面を出した。
        case presentedSignIn
        /// 未サインインで、出せるサインイン画面も無い（= 設定アプリへ誘導するしかない）。
        case needsSignInGuidance
    }

    /// 実績・ランキングを開く。**サインインは起動時のまま**で、ここで新たに認証は始めない
    /// （受け入れ条件「起動時の挙動は変えない」）。
    @discardableResult
    static func open() -> Outcome {
        // 未サインインのまま `trigger` を呼んでも何も起きない（GameKit は認証済みを前提にする）。
        // 黙って無反応になるのが最悪なので、先に判定して必ず何かを返す。
        guard GameCenterAuth.isSignedIn else {
            return GameCenterAuth.presentSignInIfAvailable() ? .presentedSignIn : .needsSignInGuidance
        }
        GKAccessPoint.shared.trigger(state: .dashboard) {}
        return .openedDashboard
    }

    /// 未サインインで出せるサインイン画面も無いときの案内の文言（ハブの「きろく」と、ゲーム内の導線で共有）。
    static var signInGuidanceTitle: String { tr("Game Center にサインインしていません") }
    static var signInGuidanceMessage: String {
        tr("iPhone の「設定」＞「Game Center」からサインインすると、実績と世界のランキングを見られます。サインインしなくても、あそびはすべてそのまま遊べます。")
    }

    /// ゲーム内の導線（ねこさがしの「ランキングを見る」・#3204）から開く。`needsSignInGuidance` のときは、
    /// ハブと同じ案内をいちばん手前の画面（開始シートの上）にアラートで出す（黙って無反応にしない）。
    static func openShowingGuidance() {
        guard open() == .needsSignInGuidance else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var presenter = scene?.keyWindow?.rootViewController else { return }
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed { presenter = presented }
        let alert = UIAlertController(title: signInGuidanceTitle, message: signInGuidanceMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        presenter.present(alert, animated: true)
    }
}
