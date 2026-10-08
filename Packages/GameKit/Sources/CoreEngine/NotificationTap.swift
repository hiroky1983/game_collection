import Foundation

/// タップされたローカル通知が、**どの種類で・どのゲームへ着地するか**（#1950）。
///
/// 通知の種類は識別子の接頭辞で決まる（`userInfo` の `gameID` は種類をまたいで同じ鍵名のため、判別に使えない）。
/// `AppDelegate` が `UNNotificationResponse` から取り出した値をここへ渡し、結果に応じて各サービスへ配る。
public enum NotificationTapTarget: Equatable, Sendable {
    /// 中断したゲームのお知らせ（#663）。
    case resumeReminder(gameID: String)
    /// 久しぶりに遊ぼうの再エンゲージメント通知（#1193）。
    case reengagement(gameID: String)
    /// 挑戦回数が戻ったお知らせ（#1576）。
    case challengeReturn(gameID: String)

    public static let resumeReminderPrefix = "resume-reminder."
    public static let reengagementPrefix = "reengagement-reminder."
    /// 予約は常に 1 件なので、接頭辞ではなく識別子そのもの。
    public static let challengeReturnIdentifier = "challenge-return.homerun"
    /// 回数制のゲームは柵越えおじさんだけ。通知に `userInfo` を持たせないため、行き先は固定で返す。
    public static let challengeReturnGameID = "homerun"

    /// 通知の識別子と `userInfo` の `gameID` から行き先を決める。知らない識別子・`gameID` の欠けは nil。
    public static func resolve(identifier: String, gameID: String?) -> NotificationTapTarget? {
        if identifier == challengeReturnIdentifier {
            return .challengeReturn(gameID: challengeReturnGameID)
        }
        if identifier.hasPrefix(resumeReminderPrefix) {
            return gameID.map { .resumeReminder(gameID: $0) }
        }
        if identifier.hasPrefix(reengagementPrefix) {
            return gameID.map { .reengagement(gameID: $0) }
        }
        return nil
    }
}
