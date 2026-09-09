import Foundation

/// このビルドの配布経路（App Store / TestFlight / それ以外の内部ビルド）。
///
/// 計測（#347）と広告ユニット ID（`AdConfig`）の切り替えに使う。実ユーザーの指標に
/// 内部トラフィック（シミュレータ・リリース前実機確認）を混ぜないための分別で、
/// 3値は GA4 のユーザープロパティ `build_channel` の値としてそのまま送られるため変更しない。
///
/// `debug` は「DEBUG 構成」だけを指すのではなく、**App Store とも TestFlight とも確認できない
/// ビルド全般**（Xcode からの Release 実行・シミュレータの Release ビルド）を含む（#382）。
/// GA4 側は `build_channel = appstore` で実ユーザーを抽出する運用なので、値を増やさずに
/// 内部ビルドを1つにまとめるほうがカスタム定義の登録（#214）と整合する。
enum BuildChannel: String {
    case debug
    case testflight
    case appstore

    /// 現在のビルドの配布経路。起動中に変わらないので1回だけ判定する。
    ///
    /// 判定は「App Store が埋め込んだレシートが実在するか」を先に見る。Xcode からビルドした
    /// アプリはレシートを持たない（`appStoreReceiptURL` は URL を返すが**ファイルが無い**）ため、
    /// ここを見ないと内部の Release ビルドが `appstore` に倒れ、本番広告ユニットを叩き（AdMob の
    /// 無効なトラフィックに当たりうる）、GA4 でも実ユーザーとして数えられてしまう（#382）。
    ///
    /// TestFlight 判定は「レシートのファイル名が `sandboxReceipt`」という定石。
    /// App Review の審査端末も sandbox レシートになることがあるが、その場合に
    /// テスト広告・testflight 扱いへ倒れるのは安全側（本番ユニットを叩かない）なので許容する。
    ///
    /// - Note: `appStoreReceiptURL` は deprecated だが、後継の `AppTransaction.shared` は
    ///   async かつネットワークを要しうるため、起動時に同期で1回だけ引きたいこの用途では
    ///   従来 API を意図して使う。判定に迷うケースはすべて `debug`（= テスト広告・収集オフ）
    ///   に倒すので、誤判定しても安全側にしか転ばない。
    static let current: BuildChannel = {
        #if DEBUG
        return .debug
        #else
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: receiptURL.path)
        else {
            return .debug
        }
        return receiptURL.lastPathComponent == "sandboxReceipt" ? .testflight : .appstore
        #endif
    }()
}
