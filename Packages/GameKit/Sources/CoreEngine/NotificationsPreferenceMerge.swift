import Foundation

/// 通知の設定を1つのトグルにまとめる規則（#1508）。
///
/// 「続きのお知らせ」（#663）と「久しぶり通知」（#1193）は判定条件・予約ロジックは別のまま、
/// 設定画面のトグルと保存値だけを1つに束ねる。規則は `GameSettings`（App ターゲット）から
/// 呼ばれるが、App にはテストが無いので純粋関数としてここへ切り出して固定する
/// （`GameOrderMerge` と同じ作り）。
public enum NotificationsPreferenceMerge {
    /// 個別の2つの保存値から、統合トグルの初期値を決める。
    /// どちらか一方でもオフにしていた利用者はオフ（利用者が止めた通知を勝手に再開しない）。
    public static func mergedIsEnabled(resume: Bool, reengagement: Bool) -> Bool {
        resume && reengagement
    }
}
