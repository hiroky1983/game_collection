import Foundation

/// 柵越えおじさんの動作確認用の強制（回数無制限・月・ポール・空振りの演出）。**DEBUG ビルドだけで効く**。
///
/// 鍵は DEBUG ビルドのアプリが起動引数（`-homerunUnlimited` 等）を見て立てる（`GameCollectionApp`）。
/// 出荷ビルドでは鍵の宣言と読み取りがまるごと `#if DEBUG` の外に出ないので、端末に同じ名前の鍵が
/// 残っていても読まれない（v1.1.8・会長指示 2026-10-02）。Model はここの `current(_:)` だけを呼ぶ
/// （Model 本体に `#if DEBUG` を持ち込まない）。
struct HomerunDebugOverrides: Equatable {
    var unlimited = false
    var forcesMoon = false
    var forcesPole = false
    var forcesWhiffGag = false

    /// 何も強制しない（出荷ビルドの値）。
    static let none = HomerunDebugOverrides()

    /// このビルドが DEBUG か。出荷ビルドでは false。
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// いまの強制。`isDebugBuild` が false なら鍵を読まず常に `none`（テストで出荷ビルドの経路を通すための引数）。
    static func current(_ defaults: UserDefaults, isDebugBuild: Bool = HomerunDebugOverrides.isDebugBuild) -> HomerunDebugOverrides {
        guard isDebugBuild else { return .none }
        #if DEBUG
        return HomerunDebugOverrides(
            unlimited: defaults.bool(forKey: HomerunModel.debugUnlimitedKey),
            forcesMoon: defaults.bool(forKey: HomerunModel.debugForceMoonKey),
            forcesPole: defaults.bool(forKey: HomerunModel.debugForcePoleKey),
            forcesWhiffGag: defaults.bool(forKey: HomerunModel.debugForceWhiffGagKey)
        )
        #else
        return .none
        #endif
    }
}

#if DEBUG
extension HomerunModel {
    /// 動作確認用: この鍵が true なら挑戦回数を減らさない（会長 QA 用・2026-09-30）。アプリの DEBUG ビルドが
    /// 起動引数 `-homerunUnlimited` のときだけ立て、無ければ消す（`GameCollectionApp`）。
    nonisolated public static let debugUnlimitedKey = "homerun_debugUnlimited"
    /// 動作確認用: この鍵が true なら振れば必ず月まで飛ぶ（#1680・`HomerunChallenge.forcesMoon`）。アプリの DEBUG ビルドが
    /// 起動引数 `-homerunForceMoon` のときだけ立て、無ければ消す（`GameCollectionApp`）。
    nonisolated public static let debugForceMoonKey = "homerun_debugForceMoon"
    /// 動作確認用: この鍵が true なら振れば必ずファウルポールに当たる（#1686・`HomerunChallenge.forcesPole`）。アプリの DEBUG
    /// ビルドが起動引数 `-homerunForcePole` のときだけ立て、無ければ消す（`GameCollectionApp`）。
    nonisolated public static let debugForcePoleKey = "homerun_debugForcePole"
    /// 動作確認用: この鍵が true なら振った空振りで必ず演出を出す（#1681）。アプリの DEBUG ビルドが起動引数
    /// `-homerunForceWhiffGag` のときだけ立て、無ければ消す（`GameCollectionApp`）。
    nonisolated public static let debugForceWhiffGagKey = "homerun_debugForceWhiffGag"
}
#endif
