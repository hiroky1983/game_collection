import SwiftUI

/// 広告サービスの境界。MVP ではバナー 1 枚のみ。オンライン時のみ表示し、
/// ロード失敗は握りつぶしてゲーム本体はオフラインで通常動作させる。
public protocol AdService {
    /// バナー広告ビュー。広告無効・未ロード時は nil（ゲームは通常動作）。
    @MainActor func makeBannerView() -> AnyView?
}

/// 広告を出さない実装。M5 で AdMob 実装に差し替える。
public struct NoopAdService: AdService {
    public init() {}
    @MainActor public func makeBannerView() -> AnyView? { nil }
}
