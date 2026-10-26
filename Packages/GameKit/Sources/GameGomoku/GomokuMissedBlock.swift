import Foundation

/// 負けた局の「ここで止めていれば」（#2851）。CPU の勝ち筋を止められた最後の局面と、止める手。
struct GomokuMissedBlock: Equatable, Sendable {
    /// 人間が打つ直前の盤（止められた最後の局面）。
    let position: GomokuBoard
    /// この局面で打てば CPU の勝ち筋が消えた交点（近い順・最大 `maxStopPoints` 個）。
    let stopPoints: [GomokuPoint]
    /// この局面を作った CPU の直前手。
    let previousMove: GomokuPoint?
    /// 実際に打った手。
    let playedPoint: GomokuPoint
}

/// 負けた局を末尾から遡り、CPU の勝ち筋を止められた最後の局面を探す（#2851）。
///
/// 「勝ち筋」は **CPU が四を連続で作って勝つ（四追い）** までを読む（五・達四・四四・四三・活三からの達四）。
/// 静かな手（二→三など）を挟む長い読みは見ない。見つからなければ `nil`（結果カードに案内を出さない）。
/// 人間が自分の四を作って止める手は、CPU が受けたあとの読みまでは見ないので候補から外す。
enum GomokuMissedBlockFinder {
    /// 遡る人間の手番の数。これより前は「いつ止められたか」を示しても役に立たない。
    static let maxLookback = 6
    /// 四追いの読みの深さ（四を作る手の回数）。
    static let maxForcingDepth = 4
    static let maxStopPoints = 4

    typealias Move = (row: Int, col: Int, stone: GomokuStone)

    static func find(base: GomokuBoard, moves: [Move], humanSide: GomokuStone,
                     forbiddenMoves: Bool = false) -> GomokuMissedBlock? {
        let cpu = humanSide.opponent
        guard moves.count >= 2, let last = moves.last, last.stone == cpu else { return nil }

        // boards[i] = moves[i] を打つ直前の盤。
        var boards = [GomokuBoard]()
        var running = base
        for move in moves {
            boards.append(running)
            running[move.row, move.col] = move.stone
        }

        var checked = 0
        var index = moves.count - 2
        while index >= 0, checked < maxLookback {
            defer { index -= 1 }
            guard moves[index].stone == humanSide else { continue }
            checked += 1
            let position = boards[index]
            // 自分が勝てる局面を見逃していた・CPU に脅しが無かった局は、「止める」話ではない。
            guard completionPoints(position, stone: humanSide).isEmpty,
                  cpuWins(position, cpu: cpu, depth: maxForcingDepth, forbiddenMoves: forbiddenMoves) else { return nil }

            let played = GomokuPoint(row: moves[index].row, col: moves[index].col)
            var stops = [GomokuPoint]()
            for point in candidates(position) {
                // 禁じ手ルールで黒の人間が打てない交点は、止める手として示さない。
                guard !isForbidden(position, point: point, stone: humanSide, enabled: forbiddenMoves) else { continue }
                var after = position
                after[point.row, point.col] = humanSide
                guard completionPoints(after, stone: humanSide).isEmpty,
                      !cpuWins(after, cpu: cpu, depth: maxForcingDepth, forbiddenMoves: forbiddenMoves) else { continue }
                stops.append(point)
            }
            // 実際の手が「止める手」と判定された = この読みでは負け筋を説明できない局面。さらに遡る。
            guard !stops.isEmpty, !stops.contains(played) else { continue }

            stops.sort { (distance($0, last), $0.row, $0.col) < (distance($1, last), $1.row, $1.col) }
            let previous = index > 0 ? GomokuPoint(row: moves[index - 1].row, col: moves[index - 1].col) : nil
            return GomokuMissedBlock(position: position, stopPoints: Array(stops.prefix(maxStopPoints)),
                                     previousMove: previous, playedPoint: played)
        }
        return nil
    }

    private static func distance(_ point: GomokuPoint, _ move: Move) -> Int {
        max(abs(point.row - move.row), abs(point.col - move.col))
    }

    // MARK: - 四追い

    /// `cpu` の手番で、四を作り続けて勝てるか。
    static func cpuWins(_ board: GomokuBoard, cpu: GomokuStone, depth: Int, forbiddenMoves: Bool = false) -> Bool {
        if !completionPoints(board, stone: cpu).isEmpty { return true }
        guard depth > 0 else { return false }
        for point in candidates(board) {
            // 禁じ手ルールで黒の CPU が打てない交点は、四を作る手に数えない。
            guard !isForbidden(board, point: point, stone: cpu, enabled: forbiddenMoves) else { continue }
            var after = board
            after[point.row, point.col] = cpu
            let fives = completionPoints(after, stone: cpu, through: point)
            guard !fives.isEmpty else { continue }
            // 相手がこちらの四を受ける前に五を作れるなら、この四は脅しにならない。
            guard completionPoints(after, stone: cpu.opponent).isEmpty else { continue }
            if fives.count >= 2 { return true }   // 達四・四四: 1 手では受けきれない
            var blocked = after
            blocked[fives[0].row, fives[0].col] = cpu.opponent
            if cpuWins(blocked, cpu: cpu, depth: depth - 1, forbiddenMoves: forbiddenMoves) { return true }
        }
        return false
    }

    /// 連珠の禁じ手ルールが有効で、黒が `point` へ打てないか（五が揃う手は規定どおり打てるので除く）。
    private static func isForbidden(_ board: GomokuBoard, point: GomokuPoint, stone: GomokuStone,
                                    enabled: Bool) -> Bool {
        guard enabled, stone == .black else { return false }
        return board.renjuForbidden(row: point.row, col: point.col) != nil
    }

    /// 空点で、`stone` を置くと五（以上）が揃う交点。
    static func completionPoints(_ board: GomokuBoard, stone: GomokuStone) -> [GomokuPoint] {
        candidates(board).filter { makesFive(board, row: $0.row, col: $0.col, stone: stone) }
    }

    /// `through` を通る線の上だけで、空点に `stone` を置くと五が揃う交点（`through` に置いた直後の盤で使う）。
    private static func completionPoints(_ board: GomokuBoard, stone: GomokuStone,
                                         through origin: GomokuPoint) -> [GomokuPoint] {
        var found = Set<GomokuPoint>()
        for (dr, dc) in gomokuLineDirections {
            for step in -4...4 where step != 0 {
                let r = origin.row + step * dr, c = origin.col + step * dc
                guard GomokuBoard.inBounds(r, c), board[r, c] == nil,
                      makesFive(board, row: r, col: c, stone: stone) else { continue }
                found.insert(GomokuPoint(row: r, col: c))
            }
        }
        return found.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
    }

    private static func makesFive(_ board: GomokuBoard, row: Int, col: Int, stone: GomokuStone) -> Bool {
        for (dr, dc) in gomokuLineDirections {
            var count = 1
            for sign in [-1, 1] {
                var r = row + dr * sign, c = col + dc * sign
                while GomokuBoard.inBounds(r, c), board[r, c] == stone {
                    count += 1; r += dr * sign; c += dc * sign
                }
            }
            if count >= 5 { return true }
        }
        return false
    }

    /// 石から 2 マス以内の空点（読む手の候補）。
    private static func candidates(_ board: GomokuBoard) -> [GomokuPoint] {
        var near = Set<Int>()
        for row in 0..<gomokuBoardSize {
            for col in 0..<gomokuBoardSize where board[row, col] != nil {
                for dr in -2...2 {
                    for dc in -2...2 {
                        let r = row + dr, c = col + dc
                        if GomokuBoard.inBounds(r, c), board[r, c] == nil { near.insert(r * gomokuBoardSize + c) }
                    }
                }
            }
        }
        return near.sorted().map { GomokuPoint(row: $0 / gomokuBoardSize, col: $0 % gomokuBoardSize) }
    }
}
