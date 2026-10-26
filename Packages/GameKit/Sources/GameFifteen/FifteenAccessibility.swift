/// 盤面の VoiceOver 読み上げ文。タイルは数字だけで、位置は見た目でしか分からないので行・列を添える。
public enum FifteenAccessibility {
    /// マス 1 つの読み上げ文（例: "2行3列、7" / "2行3列、7、正しい位置" / "4行4列、空き"）。
    public static func cellLabel(index: Int, value: Int, isHint: Bool = false, isHome: Bool = false, size: Int = FifteenLogic.defaultSize) -> String {
        let row = index / size + 1
        let col = index % size + 1
        let base = value > 0 ? tr("%1$lld行%2$lld列、%3$lld", row, col, value) : tr("%1$lld行%2$lld列、空き", row, col)
        // 正位置は色（teal）だけの区別だったので、読み上げにも出す（#2322）。空きマスは対象外。
        let placed = isHome && value > 0 ? base + tr("、正しい位置") : base
        return isHint ? placed + tr("、ヒント（次に動かすタイル）") : placed
    }

    /// ヒントボタンの読み上げ文。使い切ったあとは広告が要ることまで読む。
    public static func hintLabel(remaining: Int, needsAd: Bool) -> String {
        if needsAd { return tr("ヒント、無料の回数は使い切りました。広告を見ると1回追加") }
        return remaining > 0 ? tr("ヒント、残り%lld回", remaining) : tr("ヒント、残りなし")
    }
}
