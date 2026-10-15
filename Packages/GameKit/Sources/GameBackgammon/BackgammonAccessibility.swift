import Foundation

/// 盤面の VoiceOver 読み上げ文（#188 のオセロと同じ作り）。
///
/// 盤は `Canvas` に三角と円を直接描いているため、そのままでは 24 ポイントが 1 つの塊にしか見えない。
/// 読み上げ文はここに集約して純関数にし、View を組まずにテストできるようにする。
public enum BackgammonAccessibility {
    /// ポイント 1 つの読み上げ文（例: "6ポイント、あなたの駒5個、動かせます"）。
    ///
    /// - Parameters:
    ///   - index: 盤の添字（0 = 1 ポイント）。
    ///   - owner: 駒の持ち主。空なら nil。
    ///   - count: 駒の数。
    ///   - isMovable: 選べる駒か（選択のヒントが出ているポイント）。
    ///   - isSelected: 選択中の移動元か。
    ///   - isDestination: 選択中の駒の移動先か。
    public static func pointLabel(
        index: Int,
        owner: BackgammonSide?,
        count: Int,
        isMovable: Bool,
        isSelected: Bool,
        isDestination: Bool
    ) -> String {
        var parts = [tr("%lldポイント", index + 1)]
        switch owner {
        case .white: parts.append(tr("あなたの駒%lld個", count))
        case .black: parts.append(tr("CPUの駒%lld個", count))
        case nil:    parts.append(tr("空"))
        }
        if isSelected { parts.append(tr("選択中")) }
        else if isMovable { parts.append(tr("動かせます")) }
        if isDestination { parts.append(tr("ここへ動かせます")) }
        return parts.joined(separator: tr("、"))
    }

    /// バーの読み上げ文。
    public static func barLabel(humanCount: Int, cpuCount: Int, isMovable: Bool, isSelected: Bool) -> String {
        var parts = [tr("バー")]
        if humanCount == 0 && cpuCount == 0 { parts.append(tr("空")) }
        if humanCount > 0 { parts.append(tr("あなたの駒%lld個", humanCount)) }
        if cpuCount > 0 { parts.append(tr("CPUの駒%lld個", cpuCount)) }
        if isSelected { parts.append(tr("選択中")) }
        else if isMovable { parts.append(tr("動かせます")) }
        return parts.joined(separator: tr("、"))
    }

    /// あがりの置き場の読み上げ文。
    public static func offLabel(humanCount: Int, cpuCount: Int, isDestination: Bool) -> String {
        var parts = [tr("あがり"), tr("あなた%lld個", humanCount), tr("CPU%lld個", cpuCount)]
        if isDestination { parts.append(tr("ここへあがれます")) }
        return parts.joined(separator: tr("、"))
    }

    /// サイコロの読み上げ文（例: "サイコロ 5と3、残り 3"）。
    public static func diceLabel(dice: [Int], remaining: [Int]) -> String {
        guard !dice.isEmpty else { return tr("サイコロはまだ振っていません") }
        let shown = dice.count == 4 ? tr("%lldのゾロ目", dice[0]) : dice.map(String.init).joined(separator: tr("と"))
        if remaining.isEmpty { return tr("サイコロ %@、使い切りました", shown) }
        return tr("サイコロ %1$@、残り %2$@", shown, remaining.map(String.init).joined(separator: tr("と")))
    }

    /// CPU の手番が終わったときの読み上げ文（#2280）。`moves` が空ならパス。
    /// 駒を 1 つ動かすたびには読まず、手番の締めに 1 回だけ、動かした数と叩かれた駒の数を伝える。
    public static func cpuTurnAnnouncement(moves: [BackgammonMove]) -> String {
        guard !moves.isEmpty else { return tr("CPUはパスしました") }
        let hits = moves.filter(\.hits).count
        let moved = tr("CPUは駒を%lld個動かしました", moves.count)
        guard hits > 0 else { return moved }
        return moved + tr("。") + tr("あなたの駒が%lld個バーに送られました", hits)
    }
}
