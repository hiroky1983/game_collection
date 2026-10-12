import Foundation

/// 盤面の VoiceOver 読み上げ文と操作名（#712）。
///
/// 盤はスワイプ（`DragGesture`）でしか動かせず、VoiceOver 有効時はスワイプが支援技術に
/// 吸われて 1 手も動かせない。マスの読み上げ文と方向アクションの名前はここに集約して純関数にし、
/// View を組まずにテストできるようにする（オセロの `OthelloAccessibility` と同型）。
public enum Game2048Accessibility {
    /// マス 1 つの読み上げ文（例: "2行3列、128" / "1行1列、空き"）。
    public static func tileLabel(row: Int, col: Int, value: Int) -> String {
        let content = value > 0 ? String(value) : tr("空き")
        return tr("%1$lld行%2$lld列、%3$@", row + 1, col + 1, content)
    }

    /// 盤を動かすアクションの名前。VoiceOver のアクション一覧（上下スワイプで選ぶ）に出る。
    public static func moveActionName(_ direction: Direction) -> String {
        switch direction {
        case .up:    return tr("上へ動かす")
        case .down:  return tr("下へ動かす")
        case .left:  return tr("左へ動かす")
        case .right: return tr("右へ動かす")
        }
    }
}
