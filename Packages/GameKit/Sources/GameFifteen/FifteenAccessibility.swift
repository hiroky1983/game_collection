/// 盤面の VoiceOver 読み上げ文。タイルは数字だけで、位置は見た目でしか分からないので行・列を添える。
public enum FifteenAccessibility {
    /// マス 1 つの読み上げ文（例: "2行3列、7" / "4行4列、空き"）。
    public static func cellLabel(index: Int, value: Int, isHint: Bool = false) -> String {
        let row = index / FifteenLogic.size + 1
        let col = index % FifteenLogic.size + 1
        let base = "\(row)行\(col)列、\(value > 0 ? String(value) : "空き")"
        return isHint ? base + "、ヒント（次に動かすタイル）" : base
    }

    /// ヒントボタンの読み上げ文。使い切ったあとは広告が要ることまで読む。
    public static func hintLabel(remaining: Int, needsAd: Bool) -> String {
        if needsAd { return "ヒント、無料の回数は使い切りました。広告を見ると1回追加" }
        return remaining > 0 ? "ヒント、残り\(remaining)回" : "ヒント、残りなし"
    }
}
