import SwiftUI

/// 広告サービスの境界。MVP ではバナー 1 枚のみ。オンライン時のみ表示し、
/// ロード失敗は握りつぶしてゲーム本体はオフラインで通常動作させる。
public protocol AdService {
    /// バナー広告ビュー。広告無効・未ロード時は nil（ゲームは通常動作）。
    /// `width` は実際にバナーが置かれる SwiftUI 側の幅（pt）。アダプティブバナーの
    /// サイズ計算に使う。`UIScreen.main.bounds.width`（画面全体の幅）を使うと、
    /// 呼び出し側が `.padding()` などで余白を取っている場合に実際の表示幅より広いサイズで
    /// 広告を要求してしまい、左右に黒い余白（レターボックス）が出る（#マージ済みPRの会長指摘）。
    @MainActor func makeBannerView(width: CGFloat) -> AnyView?
    /// インタースティシャル広告を表示し、閉じられるまで待つ。ロード失敗時は即 return。
    @MainActor func showInterstitial() async
    /// リワード広告を表示し、視聴完了なら true を返す。ロード失敗・キャンセル時は false。
    @MainActor func showRewardedAd() async -> Bool
}

/// 広告を出さない実装。
public struct NoopAdService: AdService {
    public init() {}
    @MainActor public func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor public func showInterstitial() async {}
    @MainActor public func showRewardedAd() async -> Bool { true }
}
