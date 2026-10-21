import Foundation

/// 盤の VoiceOver 読み上げ文（#188 の五目並べと同じ作り）。純関数にして View を組まずにテストする。
///
/// 盤は列ごとのボタン（7 本）として読ませる。1 マスずつだと 42 要素になり、落とす場所（列）を選ぶ操作と合わない。
public enum YonmokuAccessibility {
    /// 列 1 本の読み上げ文（例: "3列目、下から 黒・白、あと4個入る"）。
    ///
    /// - Parameters:
    ///   - col: 左からの列（0 始まり。読み上げは 1 始まり）。
    ///   - discs: 下から順の石。
    ///   - isLastMove: 直前の手が入った列か。
    public static func columnLabel(col: Int, discs: [YonmokuDisc], isLastMove: Bool) -> String {
        var parts = [tr("%lld列目", col + 1)]
        if discs.isEmpty {
            parts.append(tr("空"))
        } else {
            let order = discs.map { $0 == .black ? tr("黒") : tr("白") }.joined(separator: tr("・"))
            parts.append(tr("下から %@", order))
        }
        let room = YonmokuBoard.rows - discs.count
        parts.append(room > 0 ? tr("あと%lld個入る", room) : tr("満杯"))
        if isLastMove { parts.append(tr("直前の手")) }
        return parts.joined(separator: tr("、"))
    }

    /// CPU が石を落としたときの読み上げ文（#2280）。
    public static func cpuMoveAnnouncement(col: Int, row: Int) -> String {
        tr("CPUは%1$lld列目の下から%2$lld段目に入れました", col + 1, row + 1)
    }
}
