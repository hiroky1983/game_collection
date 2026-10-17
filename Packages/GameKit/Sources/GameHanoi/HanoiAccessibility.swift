/// ハノイの塔の読み上げ文と、操作を断った理由の文言（#2003）。
/// 円盤の大きさは色ではなく数字（1 が最小）で読み、幅と数字の両方で見せる。
public enum HanoiAccessibility {
    /// 柱の名前（左・まんなか・右）。
    public static func pegName(_ peg: Int) -> String {
        switch peg {
        case 0: tr("左の柱")
        case 1: tr("まんなかの柱")
        default: tr("右の柱")
        }
    }

    /// 柱 1 本の読み上げ文（例: 「左の柱、上から小さい順に 1・2・3（3枚）」）。
    /// - Parameter disks: 下から上へ並んだ円盤の大きさ（`HanoiModel.pegs` の 1 本）。
    public static func pegLabel(peg: Int, disks: [Int], isSelected: Bool = false) -> String {
        let name = pegName(peg)
        let base: String
        if disks.isEmpty {
            base = tr("%@、円盤なし", name)
        } else {
            let fromTop = disks.reversed().map(String.init).joined(separator: tr("・"))
            base = tr("%1$@、上から小さい順に %2$@（%3$lld枚）", name, fromTop, disks.count)
        }
        return isSelected ? base + tr("、いちばん上を取っています") : base
    }

    /// 操作を断った理由（画面にも同じ文を出す）。
    public static func message(for rejection: HanoiLogic.Rejection) -> String {
        switch rejection {
        case .emptySource: tr("その柱には円盤がありません")
        case .largerOnSmaller: tr("大きい円盤は、小さい円盤の上には置けません")
        }
    }
}
