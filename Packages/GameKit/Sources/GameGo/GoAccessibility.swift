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
        isDead: Bool = false
    ) -> String {
        var parts = ["\(row + 1)行\(col + 1)列"]
        switch stone {
        case .black: parts.append("黒石")
        case .white: parts.append("白石")
        case nil:    parts.append("空点")
        }
        if isDead { parts.append("死に石") }
        if isLastMove { parts.append("直前の手") }
        return parts.joined(separator: "、")
    }

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
            return "\(isHumanTurn ? "あなたの番" : "CPUの番")、あなたが取った石 \(capturedByHuman)、CPUが取った石 \(capturedByCPU)"
        case .scoring:
            return "終局の確認。\(result ?? "計算中")"
        case .finished:
            return result ?? "対局終了"
        }
    }
}
