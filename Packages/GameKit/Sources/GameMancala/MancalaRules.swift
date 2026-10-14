import Foundation

/// マンカラのルール（2×6 穴・各 4 個・ストア付きの基本ルール）。純粋関数だけを持つ。
///
/// 1. 自分の穴を 1 つ選び、中の種をすべて取って、反時計回りに 1 個ずつ次の置き場へまく。
///    自分のストアには入れるが、**相手のストアは飛ばす**。
/// 2. 最後の種が**自分のストア**に入ったら、もう一度続けて打つ。
/// 3. 最後の種が**自分の側の空の穴**に入り、向かいの相手の穴に種があれば、その種と最後の 1 個を
///    まとめて自分のストアへ取る（向かいが空なら取らない）。
/// 4. どちらかの側の穴がすべて空になったら終局。残った種はそれぞれの側のストアへ入れ、
///    ストアの種が多いほうの勝ち（同数は引き分け）。
public enum MancalaRules {
    /// 打てる穴（0〜5・種のある穴）。
    public static func legalMoves(board: MancalaBoard, side: MancalaSide) -> [Int] {
        (0..<MancalaBoard.pitsPerSide).filter { board.seeds(side, pit: $0) > 0 }
    }

    public static func isLegal(pit: Int, board: MancalaBoard, side: MancalaSide) -> Bool {
        (0..<MancalaBoard.pitsPerSide).contains(pit) && board.seeds(side, pit: pit) > 0
    }

    /// `side` が `pit` をまいた結果。打てない穴を渡してはいけない（`isLegal` で確かめてから呼ぶ）。
    public static func apply(pit: Int, side: MancalaSide, to board: MancalaBoard) -> MancalaMoveResult {
        precondition(isLegal(pit: pit, board: board, side: side), "打てない穴: \(side) \(pit)")
        var slots = board.slots
        let start = MancalaBoard.slotIndex(side, pit: pit)
        var hand = slots[start]
        slots[start] = 0
        let skip = MancalaBoard.storeIndex(side.opponent)
        var index = start
        while hand > 0 {
            index = (index + 1) % MancalaBoard.slotCount
            if index == skip { continue }
            slots[index] += 1
            hand -= 1
        }

        var captured = 0
        let ownStore = MancalaBoard.storeIndex(side)
        // 空の自分の穴に最後の 1 個が入った = いま 1 個だけ。
        if MancalaBoard.isPit(index), MancalaBoard.owner(ofSlot: index) == side, slots[index] == 1 {
            let opposite = MancalaBoard.oppositeIndex(index)
            if slots[opposite] > 0 {
                captured = slots[opposite]
                slots[ownStore] += slots[opposite] + 1
                slots[opposite] = 0
                slots[index] = 0
            }
        }

        var result = MancalaBoard(slots: slots)
        let ended = isGameOver(result)
        if ended { result = sweep(result) }
        return MancalaMoveResult(
            board: result, lastSlot: index,
            extraTurn: !ended && index == ownStore,
            captured: captured, gameEnded: ended
        )
    }

    /// どちらかの側の穴がすべて空か。
    public static func isGameOver(_ board: MancalaBoard) -> Bool {
        board.pitTotal(.south) == 0 || board.pitTotal(.north) == 0
    }

    /// 終局の回収: 穴に残った種をそれぞれの側のストアへ入れる。
    public static func sweep(_ board: MancalaBoard) -> MancalaBoard {
        var b = board
        for side in MancalaSide.allCases {
            var total = 0
            for pit in 0..<MancalaBoard.pitsPerSide {
                let i = MancalaBoard.slotIndex(side, pit: pit)
                total += b.slots[i]
                b.slots[i] = 0
            }
            b.slots[MancalaBoard.storeIndex(side)] += total
        }
        return b
    }

    /// 終局した盤の勝者。同数なら nil（引き分け）。
    public static func winner(of board: MancalaBoard) -> MancalaSide? {
        let s = board.store(.south), n = board.store(.north)
        if s == n { return nil }
        return s > n ? .south : .north
    }

    /// 中断データから読んだ盤が壊れていないか（置き場の数・負の数・種の総数）。
    public static func isConsistent(_ board: MancalaBoard) -> Bool {
        board.slots.count == MancalaBoard.slotCount
            && board.slots.allSatisfy { $0 >= 0 }
            && board.slots.reduce(0, +) == MancalaBoard.totalSeeds
    }
}
