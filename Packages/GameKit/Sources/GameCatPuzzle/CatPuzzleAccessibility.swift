import Core

/// おじさんちのねこさがしの読み上げ文（#2250）。部屋は色ではなく名前で読み、矛盾は「ちがう」の言葉で伝える。
public enum CatPuzzleAccessibility {
    /// マス 1 つの読み上げ文（例: 「2行3列、居間、猫」「1行1列、台所、×」「4行5列、寝室、猫、ヒントで置いた」）。
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
        if isHint { parts.append(tr("ヒントで置いた")) }
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

    /// 行・列・部屋の呼び方（「2列目」「3行目」「台所」）。
    public static func groupName(_ group: CatPuzzleHint.Group, roomName: (Int) -> String) -> String {
        switch group {
        case .row(let index): tr("%lld行目", index + 1)
        case .column(let index): tr("%lld列目", index + 1)
        case .room(let room): roomName(room)
        }
    }

    /// 複数の行・列・部屋を「と」でつなぐ（「台所と書斎」「2列目と4列目」）。
    static func groupList(_ groups: [CatPuzzleHint.Group], roomName: (Int) -> String) -> String {
        groups.map { groupName($0, roomName: roomName) }.joined(separator: tr("と"))
    }

    /// ヒントの理由の文（画面に出す・読み上げる）。推理の 1 歩を「〜なので、〜」の形で言う。
    /// `roomName` は部屋の番号 → 名前（`CatPuzzleHouse.room(_:).name`）。
    public static func message(for hint: CatPuzzleHint, puzzle: CatPuzzle, roomName: (Int) -> String) -> String {
        func room(of cell: Int) -> String { roomName(puzzle.rooms[cell]) }
        switch hint.reason {
        case .wrongCat(let cell, let violation):
            switch violation {
            case .room: return tr("ヒント: 同じ部屋に2匹はいないので、%@の猫を1匹外すよ", room(of: cell))
            case .row: return tr("ヒント: 同じ行に2匹はいないので、%@の猫を外すよ", room(of: cell))
            case .column: return tr("ヒント: 同じ列に2匹はいないので、%@の猫を外すよ", room(of: cell))
            case .adjacent: return tr("ヒント: 猫どうしは隣り合わないので、%@の猫を外すよ", room(of: cell))
            case .none: return tr("ヒント: %@の猫は答えと合わないので外すよ", room(of: cell))
            }
        case .confined(let sources, let targets):
            let from = groupList(sources, roomName: roomName), to = groupList(targets, roomName: roomName)
            return tr("ヒント: %1$@の猫は%2$@にしかいないので、%2$@のほかのマスに猫はいない", from, to)
        case .aroundCat(let cell):
            return tr("ヒント: %@の猫と同じ行・列・部屋と、その隣のマスに、ほかの猫はいない", room(of: cell))
        case .onlyCell(let group, _):
            return tr("ヒント: %@で猫が入れるのはここだけ。猫はここ！", groupName(group, roomName: roomName))
        case .wouldBlock(_, let blocked):
            return tr("ヒント: ここに猫がいると%@に猫が入れなくなるので、ここに猫はいない", groupName(blocked, roomName: roomName))
        case .wouldBlockChain(_, let blocked):
            return tr("ヒント: ここに猫がいると、決まるマスを埋めていくと%@に猫が入れなくなるので、ここに猫はいない", groupName(blocked, roomName: roomName))
        case .forced(let cell):
            return tr("ヒント: ここは決まり。%@の猫はここ！", room(of: cell))
        }
    }
}
