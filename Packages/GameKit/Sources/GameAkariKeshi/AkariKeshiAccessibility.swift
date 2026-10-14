/// 盤面の VoiceOver 読み上げ文（#1883）。点灯は色だけで伝えず、語で読む。
public enum AkariKeshiAccessibility {
    /// マス 1 つの読み上げ文（例: "2行3列、点灯"）。
    public static func cellLabel(index: Int, isLit: Bool) -> String {
        let row = index / AkariKeshiLogic.size + 1
        let col = index % AkariKeshiLogic.size + 1
        return isLit ? tr("%1$lld行%2$lld列、点灯", row, col) : tr("%1$lld行%2$lld列、消灯", row, col)
    }

    /// マスの操作の説明。
    public static var cellHint: String { tr("押すと、このマスと上下左右の明かりが入れ替わります") }

    /// 盤全体の要約（残りの点灯数）。
    public static func boardSummary(litCount: Int) -> String {
        litCount == 0 ? tr("明かりはすべて消えています") : tr("点灯しているマス、%lld個", litCount)
    }
}
