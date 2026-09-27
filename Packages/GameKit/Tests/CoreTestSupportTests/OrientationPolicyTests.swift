import Testing
import CoreEngine

/// 横向き許可の判定（#1511）を UIKit 抜きで固定する。
///
/// `OrientationPolicy` は `OrientationLockController`（App 層・UIKit 依存）が
/// `UIInterfaceOrientationMask` に変換する前段の純粋なロジック。ここを固定しておけば、
/// 「対象外の画面は縦のまま」「iPad の上下逆さまを横向き対応で失わない」を
/// シミュレータなしで検証できる。
@Suite("OrientationPolicy")
struct OrientationPolicyTests {
    @Test("iPhone は既定で縦のみ")
    func phoneDefaultsToPortraitOnly() {
        let policy = OrientationPolicy(idiom: .phone, allowsLandscape: false)
        #expect(policy.allowedOrientations == [.portrait])
    }

    @Test("iPad は既定で縦＋上下逆さま")
    func padDefaultsToPortraitAndUpsideDown() {
        let policy = OrientationPolicy(idiom: .pad, allowsLandscape: false)
        #expect(policy.allowedOrientations == [.portrait, .portraitUpsideDown])
    }

    @Test("iPhone は許可中だけ横 2 方向が足される")
    func phoneAddsLandscapeWhenAllowed() {
        let policy = OrientationPolicy(idiom: .phone, allowsLandscape: true)
        #expect(policy.allowedOrientations == [.portrait, .landscapeLeft, .landscapeRight])
    }

    @Test("iPad は許可中も上下逆さまを失わない")
    func padKeepsUpsideDownWhenLandscapeAllowed() {
        let policy = OrientationPolicy(idiom: .pad, allowsLandscape: true)
        #expect(policy.allowedOrientations == [
            .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight,
        ])
    }
}
