/// 盤面の VoiceOver 読み上げ文（#2235）。点の位置と線の状態を、色ではなく数字で読む。
public enum TsunagiAccessibility {
    /// マス 1 つの読み上げ文（例: "2行3列、3の点、つながった" / "1行1列、2の線" / "4行5列、空き"）。
    /// - Parameters:
    ///   - number: このマスの持ち主の数字（1 始まり）。空きなら nil。
    ///   - isEndpoint: 点のマスか。
    ///   - isConnected: その数字の線が両方の点をつないでいるか。
    ///   - isSelected: VoiceOver で選んでいる数字の線の先端か。
    public static func cellLabel(cell: Int, side: Int, number: Int?, isEndpoint: Bool,
                                 isConnected: Bool, isSelected: Bool = false) -> String {
        let row = cell / side + 1
        let col = cell % side + 1
        var label: String
        switch (number, isEndpoint) {
        case (let n?, true):
            label = tr("%1$lld行%2$lld列、%3$lldの点", row, col, n)
        case (let n?, false):
            label = tr("%1$lld行%2$lld列、%3$lldの線", row, col, n)
        case (nil, _):
            label = tr("%1$lld行%2$lld列、空き", row, col)
        }
        if number != nil {
            label += isConnected ? tr("、つながった") : tr("、つながっていない")
        }
        if isSelected { label += tr("、選択中（隣のマスを選ぶと線がのびます）") }
        return label
    }

    /// 盤の上の進み具合（例: "つながった数字 3/6、うまったマス 20/25"）。
    public static func progressLabel(connected: Int, pairs: Int, filled: Int, cells: Int) -> String {
        tr("つながった数字 %1$lld/%2$lld、うまったマス %3$lld/%4$lld", connected, pairs, filled, cells)
    }
}
