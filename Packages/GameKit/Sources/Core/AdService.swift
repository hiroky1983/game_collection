import SwiftUI

/// 広告サービスの境界。MVP ではバナー 1 枚のみ。オンライン時のみ表示し、
/// ロード失敗は握りつぶしてゲーム本体はオフラインで通常動作させる。
public protocol AdService {
    /// バナー広告ビュー。広告無効・未ロード時は nil（ゲームは通常動作）。
    @MainActor func makeBannerView() -> AnyView?
    /// インタースティシャル広告を表示し、閉じられるまで待つ。ロード失敗時は即 return。
    @MainActor func showInterstitial() async
    /// リワード広告を表示し、視聴完了なら true を返す。ロード失敗・キャンセル時は false。
    @MainActor func showRewardedAd() async -> Bool
}

/// 広告を出さない実装。
public struct NoopAdService: AdService {
    public init() {}
    @MainActor public func makeBannerView() -> AnyView? { nil }
    @MainActor public func showInterstitial() async {}
    @MainActor public func showRewardedAd() async -> Bool { true }
}
