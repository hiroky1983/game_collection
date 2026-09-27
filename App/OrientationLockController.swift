import UIKit
import Core

/// `OrientationLockService` の実体（#1511）。対象画面（ソリティア系3本）が表示されている間だけ
/// `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` が返すマスクへ横向きを足す。
///
/// マスクの構築ロジックそのもの（既定 + 横向きの足し引き）は `CoreEngine.OrientationPolicy` に
/// 切り出してあり、UIKit 非依存のまま `swift test` で検証できる。ここは
/// 「いま許可中か」を保持し、UIKit の型へ変換して OS に変更を知らせるだけ。
@MainActor
public final class OrientationLockController: OrientationLockService {
    public static let shared = OrientationLockController()

    private init() {}

    private var allowsLandscape = false

    /// `AppDelegate` がそのまま返すマスク。
    var mask: UIInterfaceOrientationMask {
        let policy = OrientationPolicy(idiom: currentIdiom, allowsLandscape: allowsLandscape)
        return UIInterfaceOrientationMask(policy.allowedOrientations)
    }

    private var currentIdiom: DeviceIdiom {
        UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
    }

    public func beginAllowingLandscape() {
        allowsLandscape = true
        notifySystemOrientationChanged()
    }

    public func endAllowingLandscape() {
        allowsLandscape = false
        notifySystemOrientationChanged()
        forceRotateToPortraitIfNeeded()
    }

    /// マスクが変わったことを OS に伝える。iOS 16 以降の作法（`attemptRotationToDeviceOrientation`
    /// は非推奨）。呼ばないと、許可を外してもすでに横向きの画面がそのまま残ることがある。
    private func notifySystemOrientationChanged() {
        keyRootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    /// 横向きのまま画面を離れたら縦へ戻す（この画面専用の許可が消えた直後に横向きのままだと、
    /// 縦専用の他画面へ戻ったときに向きが宙に浮く）。
    private func forceRotateToPortraitIfNeeded() {
        guard let scene = keyWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
    }

    private var keyWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ??
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    private var keyRootViewController: UIViewController? {
        keyWindowScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    }
}

private extension UIInterfaceOrientationMask {
    /// `InterfaceOrientation` の集合から作る。空集合は渡さない前提
    /// （`OrientationPolicy` は既定側に必ず `.portrait` を含むため空にはならない）。
    init(_ orientations: Set<InterfaceOrientation>) {
        self = orientations.reduce(into: []) { mask, orientation in
            switch orientation {
            case .portrait: mask.insert(.portrait)
            case .portraitUpsideDown: mask.insert(.portraitUpsideDown)
            case .landscapeLeft: mask.insert(.landscapeLeft)
            case .landscapeRight: mask.insert(.landscapeRight)
            }
        }
    }
}

extension AppDelegate {
    /// アプリ全体で許可する向き（#1511）。既定は project.yml の縦固定と同じで、
    /// `OrientationLockController` を通じて対象画面の表示中だけ横向きが足される。
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLockController.shared.mask }
    }
}
