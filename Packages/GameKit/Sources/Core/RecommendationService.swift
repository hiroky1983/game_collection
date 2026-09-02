import SwiftUI

/// ゲーム間レコメンドの司令塔。全ゲームで1つを共有する（画面に出ているゲームは常に1つのため）。
///
/// 各ゲームの Model が決着した瞬間に `gameDidFinish` を呼び、提示するかどうかはここで決める。
/// 提示のトリガーを Model（＝決着の判定済みの場所）に置くことで、中断データの復元で開き直した
/// だけの画面を「遊び終えた」と数えてしまうのを避ける。
@MainActor
@Observable
public final class RecommendationService {
    public let log: PlayLog
    private let availableModules: @MainActor () -> [GameModule]
    private let now: () -> Date

    /// 提示中のレコメンド先。nil なら何も出さない。
    public private(set) var suggestedGameID: String?
    /// 提示中のカードの見出し（未プレイへの提案か、久しぶり枠か・#335）。
    public private(set) var suggestedReason: RecommendationReason = .unplayed
    /// タップされたレコメンド先。ハブが監視して遷移し、nil に戻す。
    public var requestedGameID: String?

    /// - Parameter availableModules: ハブに並んでいるゲーム（非表示を除き、ハブの並び順）。
    public init(
        log: PlayLog,
        availableModules: @escaping @MainActor () -> [GameModule],
        now: @escaping () -> Date = { Date() }
    ) {
        self.log = log
        self.availableModules = availableModules
        self.now = now
    }

    public var suggestedModule: GameModule? {
        guard let id = suggestedGameID else { return nil }
        return availableModules().first { $0.id == id }
    }

    /// 提示中のゲームに割り当てる差し色。ハブのカードと同じ順で選び、見た目を揃える。
    /// アイコンチップとボタンの**面色**として使うので `Theme.Fill` 側を返す（#220）。
    public var suggestedAccent: Color {
        guard let id = suggestedGameID,
              let index = availableModules().firstIndex(where: { $0.id == id })
        else { return Theme.Fill.coral }
        return Theme.Fill.palette[index % Theme.Fill.palette.count]
    }

    /// リザルトが表示された（＝ゲームを1つ遊び終えた）ときに各ゲームの Model から呼ぶ。
    ///
    /// - Parameter isSuppressedByOtherPrompt: 同じリザルト画面に他の依頼（評価リクエスト #53）が
    ///   出る場合は true。そちらを優先し、レコメンドは**提示カウントを消費せず**次回に送る。
    public func gameDidFinish(gameID: String, isSuppressedByOtherPrompt: Bool = false) {
        log.recordFinish(gameID: gameID)
        suggestedGameID = nil

        guard !isSuppressedByOtherPrompt else { return }
        guard RecommendationPolicy.shouldShow(state: log.state, now: now()) else { return }
        guard let suggestion = RecommendationPolicy.candidate(
            finishedGameID: gameID,
            playedGameIDs: log.playedGameIDs,
            availableIDs: availableModules().map(\.id),
            lastPlayedAt: log.lastPlayedAtByGame,
            now: now()
        ) else { return }

        log.markShown(at: now())
        suggestedGameID = suggestion.gameID
        suggestedReason = suggestion.reason
    }

    /// ×で閉じられたとき。無視の連続回数はそのまま（提示時に加算済み）。
    public func dismiss() {
        suggestedGameID = nil
    }

    /// レコメンドがタップされたとき。連続無視をリセットし、ハブに遷移を依頼する。
    public func accept() {
        guard let id = suggestedGameID else { return }
        log.markAccepted()
        suggestedGameID = nil
        requestedGameID = id
    }

    #if DEBUG
    /// 撮影・動作確認用（DEBUG 限定）。提示条件を通さずにカードを出す。
    public func simulateSuggestion(gameID: String, reason: RecommendationReason = .unplayed) {
        suggestedGameID = gameID
        suggestedReason = reason
    }
    #endif
}
