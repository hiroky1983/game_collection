import Core

/// おじさんの飼い猫パズルの読み上げ文（#2250）。部屋は色ではなく名前で読み、矛盾は「ちがう」の言葉で伝える。
public enum CatPuzzleAccessibility {
    /// マス 1 つの読み上げ文（例: 「2行3列、居間、猫」「1行1列、台所、×」「4行5列、寝室、空き、ヒント」）。
    public static func cellLabel(
        row: Int, col: Int, roomName: String, mark: CatPuzzleModel.Mark,
        isConflict: Bool = false, isHint: Bool = false
    ) -> String {
        var parts = [tr("%1$lld行%2$lld列", row + 1, col + 1), roomName]
        switch mark {
        case .empty: parts.append(tr("空き"))
        case .cross: parts.append(tr("×"))
        case .cat: parts.append(tr("猫"))
        }
        if isConflict { parts.append(tr("ちがう")) }
        if isHint { parts.append(tr("ヒント")) }
        return parts.joined(separator: tr("、"))
    }

    /// 矛盾の説明（画面にも同じ文を出す）。複数あれば「・」でつなぐ。
    public static func message(for violations: CatPuzzleViolations) -> String? {
        guard !violations.isEmpty else { return nil }
        var words: [String] = []
        if violations.kinds.contains(.room) { words.append(tr("同じ部屋に2匹")) }
        if violations.kinds.contains(.row) { words.append(tr("同じ行に2匹")) }
        if violations.kinds.contains(.column) { words.append(tr("同じ列に2匹")) }
        if violations.kinds.contains(.adjacent) { words.append(tr("猫どうしが隣")) }
        return words.joined(separator: tr("・"))
    }

    /// 上の帯の読み上げ（残りの猫・ミス・難易度）。
    public static func statusLabel(remaining: Int, mistakes: Int, difficulty: String, isSolved: Bool) -> String {
        let head = isSolved ? tr("全員みつけた！") : tr("残り %lld匹", remaining)
        return [head, tr("ミス %lld", mistakes), difficulty].joined(separator: tr("、"))
    }
}
