import Foundation

/// 王手の連続で詰ます筋の探索（#2779）。ヒントが「詰みがある局面」「詰まされかけている局面」で
/// 的外れな手を出さないよう、ヒントの探索の前に短い手数の詰みだけを確かめる。
///
/// 攻め方は王手になる手だけを読む（詰将棋の約束）ので、王手でない手を挟む詰みは見つけない。
/// 見つけた詰みは本物（受け方の全返答に詰みが続く）。見つけられないことは詰みが無い証拠ではない。
struct ShogiMateSearch {
    /// これを過ぎたら読みを打ち切り、`timedOut` を立てる（打ち切った答えは「詰みなし」と読まない）。
    let deadline: Date
    private(set) var timedOut = false
    private var nodes = 0

    init(deadline: Date = .distantFuture) { self.deadline = deadline }

    /// 手番側が `maxPlies` 手（奇数・攻め方の手で終わる）以内に詰ませられるなら、その最初の手。
    /// 短い詰みを優先して 1・3・…と深くする。
    mutating func shortestMate(_ pos: inout Position, maxPlies: Int) -> Move? {
        var plies = 1
        while plies <= maxPlies {
            if let move = mate(&pos, plies: plies) { return move }
            if timedOut { return nil }
            plies += 2
        }
        return nil
    }

    /// 手番側が `plies` 手以内に詰ませられるなら、その最初の手。
    mutating func mate(_ pos: inout Position, plies: Int) -> Move? {
        let side = pos.sideToMove
        for move in pos.legalMovesInPlace() {
            if isOutOfTime() { return nil }
            let undo = pos.make(move)
            let wins = pos.isKingInCheck(side.opponent) && defenderLoses(&pos, plies: plies - 1)
            pos.unmake(undo)
            if wins { return move }
            if timedOut { return nil }
        }
        return nil
    }

    /// 手番側（受け方・王手が掛かっている）が、残り `plies` 手のうちに詰まされるか。
    private mutating func defenderLoses(_ pos: inout Position, plies: Int) -> Bool {
        let replies = pos.legalMovesInPlace()
        if replies.isEmpty { return true }
        guard plies >= 2 else { return false }
        for reply in replies {
            let undo = pos.make(reply)
            let loses = mate(&pos, plies: plies - 1) != nil
            pos.unmake(undo)
            if !loses { return false }
        }
        return true
    }

    private mutating func isOutOfTime() -> Bool {
        nodes += 1
        if timedOut { return true }
        if nodes & 0xFF == 1, Date() > deadline { timedOut = true }
        return timedOut
    }
}
