import Foundation

/// アプリは既定で縦固定だが、対象画面（トランプのソリティア系3本・#1511）が表示されている間だけ
/// 横向きを許可する。App 層が UIKit 実装（`UIViewController.setNeedsUpdateOfSupportedInterfaceOrientations`）
/// を注入し、テスト・プレビューでは `NoopOrientationLockService` を使う（`FeedbackService` と同じ設計）。
public protocol OrientationLockService {
    /// この画面が表示されている間、横向きを許可する。
    @MainActor func beginAllowingLandscape()
    /// 横向きの許可を終える。横向きのまま画面を離れた場合は縦へ戻す。
    @MainActor func endAllowingLandscape()
}

/// 何もしない実装。テスト・プレビュー・対象外の画面用。
public struct NoopOrientationLockService: OrientationLockService {
    public init() {}
    @MainActor public func beginAllowingLandscape() {}
    @MainActor public func endAllowingLandscape() {}
}

/// 端末の種類（`UIUserInterfaceIdiom` 相当）。UIKit に依存させず `swift test` の macOS ホストでも
/// 検証できるようにするための最小限の写し（`AdaptiveLayout` が幅を使うのと同じ理由）。
public enum DeviceIdiom: Sendable, Equatable {
    case phone
    case pad
}

/// UIKit の `UIInterfaceOrientationMask` 相当。ビットマスクではなく集合として持つことで
/// マスクの構築ロジックを UIKit 非依存のまま純粋関数として検証できる。
public enum InterfaceOrientation: Sendable, Equatable, CaseIterable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
}

/// 「いま横向きを許可するか」の判定を UIKit から切り離した純粋な型（#1511）。
///
/// 既定は縦のみ（iPad は上下反転も許可 = project.yml の既存の向き設定と同じ）。
/// 対象 3 画面が表示中だけ、既定の集合に横 2 方向を足す。**既定から何かを引くことはしない**
/// （iPad の上下反転のような、この画面と無関係な既存の許可を横向き対応のために失わせない）。
public struct OrientationPolicy: Sendable, Equatable {
    public let idiom: DeviceIdiom
    public let allowsLandscape: Bool

    public init(idiom: DeviceIdiom, allowsLandscape: Bool) {
        self.idiom = idiom
        self.allowsLandscape = allowsLandscape
    }

    /// 既定で許可する向き（対象画面の外・アプリ起動直後の値）。
    private var baseOrientations: Set<InterfaceOrientation> {
        idiom == .pad ? [.portrait, .portraitUpsideDown] : [.portrait]
    }

    /// いま許可すべき向きの集合。
    public var allowedOrientations: Set<InterfaceOrientation> {
        guard allowsLandscape else { return baseOrientations }
        return baseOrientations.union([.landscapeLeft, .landscapeRight])
    }
}
