import Foundation

/// 盤面の VoiceOver 読み上げ文（#188 の横展開）。
///
/// 盤は `Canvas` に線と円を直接描いているため、そのままでは 81 の交点が VoiceOver から
/// 1 つの塊にしか見えない。読み上げ文はここに集約して純関数にし、View を組まずにテストできる。
public enum GoAccessibility {
    /// 交点 1 つの読み上げ文（例: "5行5列、黒石、直前の手"）。
    ///
    /// - Parameter isDead: 終局判定で死に石として上げられている石。読み上げないと、
    ///   画面では×印で分かる情報が音声の利用者にだけ届かない。
    public static func pointLabel(
        row: Int,
        col: Int,
        stone: GoStone?,
        isLastMove: Bool,
        isDead: Bool = false,
        isHint: Bool = false
    ) -> String {
        var parts = [tr("%1$lld行%2$lld列", row + 1, col + 1)]
        switch stone {
        case .black: parts.append(tr("黒石"))
        case .white: parts.append(tr("白石"))
        case nil:    parts.append(tr("空点"))
        }
        if isDead { parts.append(tr("死に石")) }
        if isLastMove { parts.append(tr("直前の手")) }
        if isHint { parts.append(tr("ヒントの手")) }
        return parts.joined(separator: tr("、"))
    }

    /// ヒントの最善手がパスのときの案内（#2027）。盤に印を置けないので文字で示し、VoiceOver にも同じ文を読ませる。
    public static var hintPassMessage: String { tr("ここはパスでよい局面です") }

    /// 対局の状況を 1 行で（ステータスバーの読み上げ）。
    public static func statusLabel(
        phase: GoPhase,
        isHumanTurn: Bool,
        capturedByHuman: Int,
        capturedByCPU: Int,
        result: String?
    ) -> String {
        switch phase {
        case .playing:
            return tr("%1$@、あなたが取った石 %2$lld、CPUが取った石 %3$lld",
                      isHumanTurn ? tr("あなたの番") : tr("CPUの番"), capturedByHuman, capturedByCPU)
        case .scoring:
            return tr("終局の確認。%@", result ?? tr("計算中"))
        case .finished:
            return result ?? tr("対局終了")
        }
    }
}
