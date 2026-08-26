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

    /// 認証を開始する。多重呼び出しは無視する（`authenticateHandler` は一度設定すれば
    /// GameKit 側がサインイン状態の変化に追従するため、再設定は不要）。
    static func start() {
        guard !started else { return }
        started = true
        GKLocalPlayer.local.authenticateHandler = { viewController, _ in
            // エラー（オフライン・ユーザーのキャンセル等）は握りつぶす: リトライも UI も出さない。
            // Game Center 無しでも全機能が従来どおり動くのが本機能の前提。
            guard let viewController else { return }
            // 未サインインのときだけ、GameKit からサインイン用の画面を渡される。
            // DEBUG では出さない: シミュレータでの自動検証・スクリーンショット撮影が
            // サインインシートで止まるのを防ぐ（サインイン済みデバイスなら DEBUG でも
            // シート無しで認証まで進み、ウェルカムバナーが出る）。
            #if !DEBUG
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.keyWindow?.rootViewController?
                .present(viewController, animated: true)
            #else
            _ = viewController
            #endif
        }
    }
}
