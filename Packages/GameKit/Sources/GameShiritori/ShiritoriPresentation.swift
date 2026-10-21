import Foundation

/// 画面に出す文言と VoiceOver の読み上げ文（#1243）。View を組まずにテストできるよう純関数にする。
public enum ShiritoriPresentation {
    /// 文言に引用する「ん」（負けになる語尾）。しりとりのかなそのものなので英語でも日本語のまま見せ、
    /// 文言の表には `%@` で埋め込む（#2169）。
    static let nKana = "ん"  // i18n-keep: しりとりのかなそのもの（言語を切り替えられない）

    // MARK: - 場・手番

    /// 場の札の下に出す案内。語尾を「ん」と読ませないよう、受ける字をそのまま出す。
    public static func prompt(tail: Character?, isPlayerTurn: Bool, phase: ShiritoriPhase) -> String {
        switch phase {
        case .idle:   return tr("ゲームを始めよう")
        case .result: return tr("決着")
        case .playing:
            guard let tail else { return "" }
            return isPlayerTurn ? tr("「%@」からはじまる札を取ろう", String(tail)) : tr("CPUが考え中…")
        }
    }

    /// 直近の出来事の一言。
    public static func eventText(_ event: ShiritoriEvent) -> String {
        switch event {
        case .miss:
            return tr("おてつき！ -%lldびょう", Int(ShiritoriTime.missPenalty))
        case let .played(by, reading, isAlternate):
            let who = by == .player ? tr("あなた") : "CPU"
            return isAlternate ? tr("%1$@：「%2$@」 うらよみ！", who, reading) : tr("%1$@：「%2$@」", who, reading)
        }
    }

    // MARK: - 結果

    public static func resultTitle(ending: ShiritoriEnding, didWin: Bool, mode: ShiritoriMode = .quota) -> String {
        switch ending {
        case .cpuHitN:    return didWin ? tr("CPUが「%@」で終わった！勝ち！", nKana) : tr("決着")
        case .playerHitN: return tr("「%@」で終わってしまった…負け", nKana)
        case .cpuStuck:   return tr("CPUが続けられない！勝ち！")
        case .playerStuck: return tr("続けられる札がない…負け")
        case .timeUp:     return mode == .endless ? tr("時間切れ…負け") : tr("時間切れ…ノルマ未達で負け")
        case .quotaReached: return tr("ノルマ達成！勝ち！")
        case .perfect:    return tr("パーフェクト！札を全部取った！")
        }
    }

    /// 結果カード（`BoardGameResultCard`）の理由の行（#1876）。勝敗は見出しが持つので、決着のわけだけを短く言う。
    public static func resultReason(ending: ShiritoriEnding) -> String {
        switch ending {
        case .cpuHitN:      return tr("CPUが「%@」で終わった", nKana)
        case .playerHitN:   return tr("「%@」で終わってしまった", nKana)
        case .cpuStuck:     return tr("CPUが続けられない")
        case .playerStuck:  return tr("続けられる札がない")
        case .timeUp:       return tr("時間切れ")
        case .quotaReached: return tr("ノルマ達成")
        case .perfect:      return tr("パーフェクト！札を全部取った")
        }
    }

    /// 結果に添える内訳（例: "あなた3枚・CPU2枚／ノルマ: 6枚取ったらクリア"）。
    /// ノルマが勝敗に絡むのは時間切れと到達の決着だけなので、ノルマの説明もそのときだけ添える。
    /// とことんモードにはノルマが無いので、ノルマの説明は添えない。
    public static func resultDetail(player: Int, cpu: Int, quota: ShiritoriQuota, ending: ShiritoriEnding,
                                    mode: ShiritoriMode = .quota, clearSeconds: Int? = nil) -> String {
        var base = tr("あなた%1$lld枚・CPU%2$lld枚", player, cpu)
        if let clearSeconds { base += tr("・今回%lld秒", clearSeconds) }
        guard mode == .quota else { return base }
        return ending == .timeUp || ending == .quotaReached ? base + tr("／ノルマ: %@", quota.summary) : base
    }

    // MARK: - VoiceOver

    /// CPU の手番が始まったときの読み上げ文（#2610）。検討中のカーソルの途中経過は読まない。
    public static func cpuThinkingAnnouncement() -> String {
        tr("CPUが考えています")
    }

    /// CPU が札を取ったときの読み上げ文。対局が続くなら自分の番に戻ったことも添える（#2610）。
    public static func cpuPlayedAnnouncement(reading: String, continues: Bool) -> String {
        continues ? tr("CPUが「%@」を取りました。あなたの番です", reading) : tr("CPUが「%@」を取りました", reading)
    }

    /// 盤の札 1 枚の読み上げ文。取れるかどうかはゲームの中身なので、読み上げでも教えない。
    /// 絵の名前は表示言語に従い、読み（しりとりの中身）は日本語のまま添える。
    public static func slotLabel(_ slot: ShiritoriSlot) -> String {
        let name = tr("%1$@、%2$@", slot.card.kind.displayName, slot.displayReading)
        switch slot.owner {
        case nil:     return name
        case .player: return tr("%@、あなたが取りました", name)
        case .cpu:    return tr("%@、CPUが取りました", name)
        }
    }

    /// 場の札の読み上げ文。
    public static func currentLabel(card: ShiritoriCard?, reading: String) -> String {
        guard let card else { return tr("場の札はまだありません") }
        return tr("場の札は%1$@、読みは%2$@", card.kind.displayName, reading)
    }
}
