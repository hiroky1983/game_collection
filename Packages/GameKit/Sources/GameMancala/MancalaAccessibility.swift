import Foundation

/// 盤の VoiceOver 読み上げ文（#188 のオセロと同じ作り）。
///
/// 穴とストアの種の数は画面の数字でも出しているが、読み上げ文はここに集約して純関数にし、
/// View を組まずにテストできるようにする。
public enum MancalaAccessibility {
    /// 穴 1 つの読み上げ文（例: "あなたの穴 3、種 4個、まけます"）。
    ///
    /// - Parameters:
    ///   - side: 穴の持ち主。
    ///   - column: 画面の左からの番号（0 始まり。読み上げは 1 始まり）。手前・奥とも画面で見たとおりに数える。
    ///   - seeds: 種の数。
    ///   - isPlayable: いまタップしてまける穴か。
    ///   - isLastMove: 直前の手でまいた穴か。
    public static func pitLabel(side: MancalaSide, column: Int, seeds: Int, isPlayable: Bool, isLastMove: Bool) -> String {
        var parts = [side == .south ? tr("あなたの穴 %lld", column + 1) : tr("CPUの穴 %lld", column + 1),
                     tr("種 %lld個", seeds)]
        if isPlayable { parts.append(tr("まけます")) }
        if isLastMove { parts.append(tr("直前にまいた穴")) }
        return parts.joined(separator: tr("、"))
    }

    /// ストアの読み上げ文（例: "あなたのストア、種 12個"）。
    public static func storeLabel(side: MancalaSide, seeds: Int) -> String {
        [side == .south ? tr("あなたのストア") : tr("CPUのストア"), tr("種 %lld個", seeds)]
            .joined(separator: tr("、"))
    }

    /// CPU の着手の読み上げ文（例: "CPUは穴3をまきました。ストアに入って、もう一度まきます"・#3062）。
    ///
    /// - Parameters:
    ///   - pitSlot: CPU がまいた穴の添字（北側の 7〜12）。穴の番号は画面の左からの数え方に合わせる。
    ///   - event: その手で起きたこと（連続手番・取った数）。
    public static func cpuMoveAnnouncement(pitSlot: Int, event: MancalaEvent?) -> String {
        let column = MancalaBoard.slotIndex(.north, pit: MancalaBoard.pitsPerSide - 1) - pitSlot
        let base = tr("CPUは穴%lld をまきました", column + 1)
        guard let event else { return base }
        if event.captured > 0 { return base + tr("。%lld個を取りました", event.captured) }
        if event.extraTurn { return base + tr("。ストアに入って、もう一度まきます") }
        return base
    }
}
