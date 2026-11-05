import Foundation

/// 総当たり・多数の種を回すテストの大きさを、CI と夜間で切り替える（#2952）。
///
/// Debug ビルドの CI で 1 件 20 秒前後かかる「全盤を解く・数百種を回す」検査は、CI（`GameKit 全テスト`）では
/// 代表の少数だけを回し、夜間（`nightly-gamekit-full.yml`・環境変数 `GAMEKIT_NIGHTLY=1`）で全数を回す。
/// 全数を回さない CI でも、検査の中身（式・不変条件）は夜間と同じものを代表に当てる。
public enum NightlyScale {
    /// 夜間の全数実行か。
    public static let isNightly = ProcessInfo.processInfo.environment["GAMEKIT_NIGHTLY"] == "1"

    /// `arguments:` に渡す範囲。CI は `ci`、夜間は `nightly`。
    public static func range(ci: Range<Int>, nightly: Range<Int>) -> Range<Int> {
        isNightly ? nightly : ci
    }

    /// 個数・上限など単独の値。
    public static func value<T>(ci: T, nightly: T) -> T {
        isNightly ? nightly : ci
    }
}
