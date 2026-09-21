import Foundation

/// 画面に出す文言と VoiceOver の読み上げ文（#1243）。View を組まずにテストできるよう純関数にする。
public enum ShiritoriPresentation {
    // MARK: - 場・手番

    /// 場の札の下に出す案内。語尾を「ん」と読ませないよう、受ける字をそのまま出す。
    public static func prompt(tail: Character?, isPlayerTurn: Bool, phase: ShiritoriPhase) -> String {
        switch phase {
        case .idle:   return "ゲームを始めよう"
        case .result: return "決着"
        case .playing:
            guard let tail else { return "" }
            return isPlayerTurn ? "「\(tail)」からはじまる札を取ろう" : "CPUが考え中…"
        }
    }

    /// 直近の出来事の一言。
    public static func eventText(_ event: ShiritoriEvent) -> String {
        switch event {
        case .miss:
            return "おてつき！ -\(Int(ShiritoriTime.missPenalty))びょう"
        case let .played(by, reading, isAlternate):
            let who = by == .player ? "あなた" : "CPU"
            return "\(who)：「\(reading)」" + (isAlternate ? " うらよみ！" : "")
        }
    }

    // MARK: - 結果

    public static func resultTitle(ending: ShiritoriEnding, didWin: Bool) -> String {
        switch ending {
        case .cpuHitN:    return didWin ? "CPUが「ん」で終わった！勝ち！" : "決着"
        case .playerHitN: return "「ん」で終わってしまった…負け"
        case .cpuStuck:   return "CPUが続けられない！勝ち！"
        case .playerStuck: return "続けられる札がない…負け"
        case .timeUp:     return "時間切れ…ノルマ未達で負け"
        case .quotaReached: return "ノルマ達成！勝ち！"
        }
    }

    /// 結果に添える内訳（例: "あなた3枚・CPU2枚／ノルマ: 6枚取ったらクリア"）。
    /// ノルマが勝敗に絡むのは時間切れと到達の決着だけなので、ノルマの説明もそのときだけ添える。
    public static func resultDetail(player: Int, cpu: Int, quota: ShiritoriQuota, ending: ShiritoriEnding) -> String {
        let base = "あなた\(player)枚・CPU\(cpu)枚"
        return ending == .timeUp || ending == .quotaReached ? base + "／ノルマ: \(quota.summary)" : base
    }

    // MARK: - VoiceOver

    /// 盤の札 1 枚の読み上げ文。取れるかどうかはゲームの中身なので、読み上げでも教えない。
    public static func slotLabel(_ slot: ShiritoriSlot) -> String {
        let name = "\(slot.card.kind.displayName)、\(slot.card.primaryReading)"
        switch slot.owner {
        case nil:     return name
        case .player: return "\(name)、あなたが取りました"
        case .cpu:    return "\(name)、CPUが取りました"
        }
    }

    /// 場の札の読み上げ文。
    public static func currentLabel(card: ShiritoriCard?, reading: String) -> String {
        guard let card else { return "場の札はまだありません" }
        return "場の札は\(card.kind.displayName)、読みは\(reading)"
    }
}
