import Foundation

/// このビルドの配布経路（App Store / TestFlight / 開発ビルド）。
///
/// 計測（#347）と広告ユニット ID（`AdConfig`）の切り替えに使う。実ユーザーの指標に
/// 内部トラフィック（シミュレータ・リリース前実機確認）を混ぜないための分別で、
/// 3値は GA4 のユーザープロパティ `build_channel` の値としてそのまま送られるため変更しない。
enum BuildChannel: String {
    case debug
    case testflight
    case appstore

    /// 現在のビルドの配布経路。起動中に変わらないので1回だけ判定する。
    ///
    /// TestFlight 判定は「レシートのファイル名が `sandboxReceipt`」という定石。
    /// App Review の審査端末も sandbox レシートになることがあるが、その場合に
    /// テスト広告・testflight 扱いへ倒れるのは安全側（本番ユニットを叩かない）なので許容する。
    ///
    /// - Note: `appStoreReceiptURL` は deprecated だが、後継の `AppTransaction.shared` は
    ///   async かつネットワークを要しうるため、起動時に同期で1回だけ引きたいこの用途では
    ///   従来 API を意図して使う（誤判定してもテスト広告に倒れるだけで実害がない）。
    static let current: BuildChannel = {
        #if DEBUG
        return .debug
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return .testflight
        }
        return .appstore
        #endif
    }()
}
