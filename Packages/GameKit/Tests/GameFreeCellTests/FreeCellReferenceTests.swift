import Testing
import Foundation
import Core
@testable import GameFreeCell

/// 合法手生成の**独立参照実装**（#492 のテスト計画「独立参照実装との照合」・囲碁 #398 と同じ方針）。
///
/// `FreeCellBoard` 側は「並びの判定」「上限の計算」「置けるか」を関数に分けて組んでいるので、
/// どこか 1 か所の思い込みが全体に効く。ここでは**素朴で遅いやり方**で同じ集合を作り直す:
///
/// - 並びの判定は `zip` を使わず 1 枚ずつ手で辿る
/// - 上限は式ではなく**実際に 1 枚ずつ退避してみて何枚動かせるかを数える**
///   （フリーセルの「まとめて動かす」の定義そのもの。式が合っているかの検証になる）
/// - 空きセル・空列の重複は落とさず全部挙げてから、最後に集合として比べる
enum FreeCellReference {

    /// 降順・交互色か（1 枚ずつ手で辿る）。
    static func isRun(_ cards: ArraySlice<FreeCellCard>) -> Bool {
        var previous: FreeCellCard?
        for card in cards {
            if let previous {
                if card.rank != previous.rank - 1 { return false }
                if card.isRed == previous.isRed { return false }
            }
            previous = card
        }
        return true
    }

    /// 実際に 1 枚ずつ退避して何枚まで動かせるかを数える。
    ///
    /// 「n 枚の並びを移す」= 「上の n-1 枚を空きセル・空列へ散らし、下の 1 枚を移し、
    /// 散らしたぶんを積み直す」なので、**退避先の総数からしか決まらない**。
    /// 空列 1 本は「そこへ並びを作って積める」ぶんセルより強く、再帰的に効く。
    static func maxMovable(freeCells: Int, emptyPiles: Int) -> Int {
        guard emptyPiles > 0 else { return freeCells + 1 }
        // 空列を 1 本使うと、そこへ「残りの資源で運べるぶん」を丸ごと退避できる。
        return maxMovable(freeCells: freeCells, emptyPiles: emptyPiles - 1) * 2
    }

    /// 合法手の全量（重複・等価な手を落とさない素朴版）。
    static func legalMoves(_ board: FreeCellBoard) -> Set<FreeCellMove> {
        var moves: Set<FreeCellMove> = []
        let freeCells = board.cells.filter { $0 == nil }.count
        let emptyPiles = board.tableau.filter(\.isEmpty).count

        func canPlace(_ run: [FreeCellCard], on pile: Int) -> Bool {
            guard let bottom = run.first else { return false }
            let empties = board.tableau[pile].isEmpty ? emptyPiles - 1 : emptyPiles
            guard run.count <= maxMovable(freeCells: freeCells, emptyPiles: max(0, empties)) else {
                return false
            }
            guard let top = board.tableau[pile].last else { return true }
            return bottom.rank == top.rank - 1 && bottom.isRed != top.isRed
        }

        for pile in board.tableau.indices {
            guard let top = board.tableau[pile].last else { continue }
            if board.foundations[top.suit.rawValue] == top.rank - 1 {
                moves.insert(.tableauToFoundation(pile: pile))
            }
        }
        for cell in board.cells.indices {
            guard let card = board.cells[cell] else { continue }
            if board.foundations[card.suit.rawValue] == card.rank - 1 {
                moves.insert(.cellToFoundation(cell: cell))
            }
            for to in board.tableau.indices where canPlace([card], on: to) {
                moves.insert(.cellToTableau(cell: cell, to: to))
            }
        }
        for from in board.tableau.indices {
            let pile = board.tableau[from]
            for index in pile.indices where isRun(pile[index...]) {
                let run = Array(pile[index...])
                for to in board.tableau.indices where to != from && canPlace(run, on: to) {
                    moves.insert(.tableauToTableau(from: from, cardIndex: index, to: to))
                }
            }
            // 退避はセルを 1 つに絞らず全部挙げる。実装側は先頭 1 つだけを返すので、
            // 比較のときにこちらを「先頭のセルへ寄せた形」へ畳む。
            if !pile.isEmpty {
                for cell in board.cells.indices where board.cells[cell] == nil {
                    moves.insert(.tableauToCell(from: from, cell: cell))
                }
            }
        }
        return moves
    }

    /// 等価な手（どの空きセルへ退避するか）を先頭のセルへ寄せる。
    static func canonical(_ moves: some Sequence<FreeCellMove>, firstFreeCell: Int?) -> Set<FreeCellMove> {
        Set(moves.map { move in
            guard case .tableauToCell(let from, _) = move, let cell = firstFreeCell else { return move }
            return .tableauToCell(from: from, cell: cell)
        })
    }
}

@Suite("独立参照実装との照合")
struct FreeCellReferenceTests {

    /// ランダムな局面を作る。**ソルバーの勝ち筋を途中まで指す**ことで、
    /// 実戦で現れる形（並びが育ち、セルが埋まり、列が空く）に寄せる。
    private func positions(seedIndex: Int, sampleEvery: Int = 3) -> [FreeCellBoard] {
        let seed = FreeCellDealer.verifiedSeeds[seedIndex]
        var board = FreeCellDealer.deal(seed: seed)
        guard let solution = FreeCellSolver.solve(board).solution else { return [board] }
        var result = [board]
        for (index, move) in solution.enumerated() {
            guard board.apply(move) else { break }
            if index % sampleEvery == 0 { result.append(board) }
        }
        return result
    }

    @Test("合法手の集合が参照実装と一致する", arguments: [0, 5, 40, 200, 700])
    func legalMovesMatchReference(seedIndex: Int) {
        for board in positions(seedIndex: seedIndex) {
            let firstFreeCell = board.cells.firstIndex(where: { $0 == nil })
            let mine = FreeCellReference.canonical(board.legalMoves, firstFreeCell: firstFreeCell)
            let reference = FreeCellReference.canonical(
                FreeCellReference.legalMoves(board), firstFreeCell: firstFreeCell)
            #expect(mine == reference, """
                合法手が参照実装と食い違う
                実装にだけある: \(mine.subtracting(reference))
                参照にだけある: \(reference.subtracting(mine))
                """)
        }
    }

    /// 上限は式（`(空きセル + 1) × 2^空き列`）で持っているが、定義は「退避を繰り返して運べる枚数」。
    /// 再帰で書き下した参照実装と全組み合わせで突き合わせる。
    @Test("連続移動の上限が参照実装と一致する")
    func maxMovableMatchesReference() {
        for freeCells in 0...FreeCellBoard.cellCount {
            for emptyPiles in 0...FreeCellBoard.pileCount {
                var board = FreeCellBoard(
                    tableau: Array(repeating: [], count: FreeCellBoard.pileCount))
                var deck = FreeCellCard.makeDeck()
                for pile in emptyPiles..<FreeCellBoard.pileCount {
                    board.tableau[pile] = [deck.removeFirst()]
                }
                for cell in 0..<(FreeCellBoard.cellCount - freeCells) {
                    board.cells[cell] = deck.removeFirst()
                }
                #expect(board.maxMovableCount()
                        == FreeCellReference.maxMovable(freeCells: freeCells, emptyPiles: emptyPiles),
                        "空きセル \(freeCells) / 空き列 \(emptyPiles)")
            }
        }
    }

    @Test("並びの判定が参照実装と一致する", arguments: [0, 5, 40, 200, 700])
    func runDetectionMatchesReference(seedIndex: Int) {
        for board in positions(seedIndex: seedIndex) {
            for pile in board.tableau.indices {
                for index in board.tableau[pile].indices {
                    #expect(board.isOrderedRun(pile: pile, from: index)
                            == FreeCellReference.isRun(board.tableau[pile][index...]),
                            "\(pile)列目 \(index)枚目からの並びの判定が食い違う")
                }
            }
        }
    }
}
