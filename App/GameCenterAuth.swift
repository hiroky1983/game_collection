import GameKit
import UIKit

/// Game Center 認証（Issue #289 の段階①）。
///
/// 認証しておくと、iOS 26 の「ゲーム」アプリ（Apple Games）で Home / Friends タブの
/// ソーシャル推薦と Top Played チャートに載る資格を得る（developer.apple.com/games-app/）。
/// リーダーボード・実績は同 Issue の段階②③で載せる（このファイルは認証だけを担う）。
///
/// Game Center はあくまで**任意機能**として上に載せる:
/// - 未サインイン・認証失敗・オフラインでも、ゲームの進行には一切関与しない
///   （ストア文言「機内モードでも全ゲームが最後まで遊べる」の根拠を壊さないため）。
/// - 認証に成功したときのウェルカムバナー（「◯◯でサインインしました」）は GameKit が
///   自動表示するので、アプリ側の UI は何も持たない。
@MainActor
enum GameCenterAuth {
    private static var started = false

    /// 表示できる状態になるまで保持しておくサインイン画面。
    /// GameKit が `authenticateHandler` に画面を渡してくるタイミングと、こちらが
    /// 画面を出せるタイミング（広告や ATT のシートを出していない・シーンが前面にある）は
    /// 一致しないため、出せないときは捨てずにここへ置いて後で出す。
    private static var pendingViewController: UIViewController?

    /// Game Center にサインイン済みか（#334）。実績・ランキング画面を出せるかの判定に使う。
    static var isSignedIn: Bool { GKLocalPlayer.local.isAuthenticated }

    /// 預かったまま出しそびれているサインイン画面があれば出す（#334）。
    ///
    /// 認証を新しく始めることはしない（`authenticateHandler` は一度きりの設定で、こちらから
    /// サインインシートを呼び出す API は GameKit に無い）。ここでできるのは、起動時に
    /// 「他の画面を表示中で出せなかった」ぶんを消化することだけ。
    ///
    /// - Returns: 出せる画面があったら `true`。`false` のときは呼び出し側が案内を出す。
    @discardableResult
    static func presentSignInIfAvailable() -> Bool {
        #if !DEBUG
        guard pendingViewController != nil else { return false }
        presentPendingIfPossible()
        return true
        #else
        // DEBUG ではサインイン画面そのものを保持しない（`start()` のコメント参照）ため常に false。
        return false
        #endif
    }

    /// 認証を開始する。多重呼び出しは無視する（`authenticateHandler` は一度設定すれば
    /// GameKit 側がサインイン状態の変化に追従するため、再設定は不要）。
    static func start() {
        guard !started else { return }
        started = true
        GKLocalPlayer.local.authenticateHandler = { viewController, _ in
            // エラー（オフライン・ユーザーのキャンセル等）は握りつぶす: リトライも UI も出さない。
            // Game Center 無しでも全機能が従来どおり動くのが本機能の前提。
            guard let viewController else {
                // 画面が渡されなかった = 認証が完了したか、サインインを求める必要が無くなった。
                // 保持していた画面はもう出してはいけないので捨てる。
                pendingViewController = nil
                return
            }
            // 未サインインのときだけ、GameKit からサインイン用の画面を渡される。
            // DEBUG では出さない: シミュレータでの自動検証・スクリーンショット撮影が
            // サインインシートで止まるのを防ぐ（サインイン済みデバイスなら DEBUG でも
            // シート無しで認証まで進み、ウェルカムバナーが出る）。
            #if !DEBUG
            pendingViewController = viewController
            presentPendingIfPossible()
            #else
            _ = viewController
            #endif
        }
    }

    #if !DEBUG
    /// 保持しているサインイン画面を、出せる状態なら出す。出せなければ捨てずに再試行する。
    ///
    /// `retriesLeft` は 0.5 秒間隔で最大 60 回 = 30 秒ぶん。無期限には粘らない
    /// （Game Center は任意機能であり、出せないまま粘り続けて他の UI を邪魔しないため）。
    private static func presentPendingIfPossible(retriesLeft: Int = 60) {
        guard let viewController = pendingViewController else { return }
        // 何かを表示中（インタースティシャル広告・ATT の説明など）のときは割り込まず待つ。
        guard let presenter = topPresenter(), presenter.presentedViewController == nil else {
            guard retriesLeft > 0 else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                presentPendingIfPossible(retriesLeft: retriesLeft - 1)
            }
            return
        }
        pendingViewController = nil
        presenter.present(viewController, animated: true)
    }

    /// サインイン画面を出す親。前面のシーンを優先して選ぶ
    /// （`connectedScenes.first` は前面でないシーンを引くことがある）。
    private static func topPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow?.rootViewController
    }
    #endif
}
