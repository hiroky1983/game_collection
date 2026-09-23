/// 盤面の VoiceOver 読み上げ文。タイルは数字だけで、位置は見た目でしか分からないので行・列を添える。
public enum FifteenAccessibility {
    /// マス 1 つの読み上げ文（例: "2行3列、7" / "4行4列、空き"）。
    public static func cellLabel(index: Int, value: Int) -> String {
        let row = index / FifteenLogic.size + 1
        let col = index % FifteenLogic.size + 1
        return "\(row)行\(col)列、\(value > 0 ? String(value) : "空き")"
    }
}
