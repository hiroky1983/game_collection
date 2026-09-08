import Foundation
import Core

/// プレイヤーが選べる1手。UI・ソルバー・中断復元がすべてこの型を通す（#492）。
///
/// **フリーセルの添字は手そのものに全部書く**（自動で空きセルを選ばない）。中断データは
/// 「種 + 手順」の再生で復元するので、同じ手順がいつ再生されても同じ盤面にならなければならない。
/// 「空いているセルへ」のような**実行時に解決する手**を混ぜると、セルの空き方が 1 つ違うだけで
/// 以降の手順が別物になる（ソリティアの `SolitaireMove` と同じ設計方針）。
public enum FreeCellMove: Equatable, Sendable, Codable, Hashable {
    /// 場札の一番上を空きセルへ退避する。
    case tableauToCell(from: Int, cell: Int)
    case tableauToFoundation(pile: Int)
    /// `cardIndex` は移動元の添字（そこから上を丸ごと動かす）。
    case tableauToTableau(from: Int, cardIndex: Int, to: Int)
    case cellToTableau(cell: Int, to: Int)
    case cellToFoundation(cell: Int)
}

/// フリーセルの盤面と規則を、乱数も UI も持たない値型として閉じ込めた層（#492）。
///
/// 採用ルール（標準フリーセル）: 場札8列・フリーセル4・組札4・**全カード表向き**・
/// 空列には任意の札を置ける・連続移動の上限は「空きセル + 空き列」で決まる。
public struct FreeCellBoard: Equatable, Sendable, Codable {
    public static let pileCount = 8
    public static let cellCount = 4

    /// 場札。すべて表向きなので伏せ札の概念が無い（`last` が一番上）。
    public var tableau: [[FreeCellCard]]
    /// フリーセル。空きは nil。**セル同士は完全に等価**だが、手には添字を明示する（上の注記）。
    public var cells: [FreeCellCard?]
    /// 添字は `PlayingCardSuit.rawValue`。値は積み上げた最大ランク（0 = 空）。
    public var foundations: [Int]

    public init(
        tableau: [[FreeCellCard]],
        cells: [FreeCellCard?] = Array(repeating: nil, count: FreeCellBoard.cellCount),
        foundations: [Int] = [0, 0, 0, 0]
    ) {
        self.tableau = tableau
        self.cells = cells
        self.foundations = foundations
    }

    // MARK: - 数え上げ

    public var freeCellCount: Int { cells.lazy.filter { $0 == nil }.count }

    public var emptyPileCount: Int { tableau.lazy.filter(\.isEmpty).count }

    public var isWon: Bool { foundations.allSatisfy { $0 == 13 } }

    // MARK: - 連続移動の上限

    /// 一度に動かせる最大枚数。
    ///
    /// フリーセルの「まとめて動かす」は、本来なら**空きセルと空き列を使った1枚ずつの往復**を
    /// 手数として省略しているだけの操作なので、上限は退避先の数から決まる:
    ///
    /// ```
    /// (空きセル + 1) × 2^(空き列)
    /// ```
    ///
    /// - Parameter destination: 置き先の列。**そこが空列なら空き列の数から1本引く**
    ///   （その列は退避先としては使えず、置き先として使うため）。ここを引き忘れると
    ///   実際には作れない手順を合法にしてしまう（フリーセル実装で最も典型的な取りこぼし）。
    public func maxMovableCount(destination: Int? = nil) -> Int {
        var empties = emptyPileCount
        if let destination, tableau.indices.contains(destination), tableau[destination].isEmpty {
            empties -= 1
        }
        // 場札は 8 列しか無いので指数は高々 8。念のため下も 0 で止める。
        let usableEmpties = min(max(empties, 0), Self.pileCount)
        return (freeCellCount + 1) << usableEmpties
    }

    // MARK: - 判定

    /// 組札へ送れるか。
    public func canSendToFoundation(_ card: FreeCellCard) -> Bool {
        foundations[card.suit.rawValue] == card.rank - 1
    }

    /// `tableau[pile][index...]` が場札の並び（降順・交互色）として丸ごと動かせるか。
    /// **枚数の上限はここでは見ない**（置き先が決まらないと上限が決まらないため）。
    public func isOrderedRun(pile: Int, from index: Int) -> Bool {
        guard tableau.indices.contains(pile), tableau[pile].indices.contains(index) else { return false }
        let run = tableau[pile][index...]
        for (upper, lower) in zip(run, run.dropFirst()) {
            if lower.rank != upper.rank - 1 || lower.isRed == upper.isRed { return false }
        }
        return true
    }

    /// `run`（下端が `first`）を `pile` の上に置けるか。連続移動の上限もここで見る。
    public func canPlace(_ run: [FreeCellCard], onPile pile: Int) -> Bool {
        guard tableau.indices.contains(pile), let bottom = run.first else { return false }
        guard run.count <= maxMovableCount(destination: pile) else { return false }
        guard let top = tableau[pile].last else {
            // 空列には任意の札を置ける（クロンダイクの「K だけ」とはここが違う）。
            return true
        }
        return bottom.rank == top.rank - 1 && bottom.isRed != top.isRed
    }

    public func isLegal(_ move: FreeCellMove) -> Bool {
        switch move {
        case .tableauToCell(let from, let cell):
            guard tableau.indices.contains(from), !tableau[from].isEmpty else { return false }
            guard cells.indices.contains(cell) else { return false }
            return cells[cell] == nil
        case .tableauToFoundation(let pile):
            guard tableau.indices.contains(pile), let card = tableau[pile].last else { return false }
            return canSendToFoundation(card)
        case .tableauToTableau(let from, let cardIndex, let to):
            guard tableau.indices.contains(from), tableau.indices.contains(to), from != to else { return false }
            guard isOrderedRun(pile: from, from: cardIndex) else { return false }
            return canPlace(Array(tableau[from][cardIndex...]), onPile: to)
        case .cellToTableau(let cell, let to):
            guard cells.indices.contains(cell), let card = cells[cell] else { return false }
            return canPlace([card], onPile: to)
        case .cellToFoundation(let cell):
            guard cells.indices.contains(cell), let card = cells[cell] else { return false }
            return canSendToFoundation(card)
        }
    }

    // MARK: - 適用

    /// 合法手を適用する。非合法な手は無視して false を返す（呼び出し側で握り潰さないよう戻り値で伝える）。
    @discardableResult
    public mutating func apply(_ move: FreeCellMove) -> Bool {
        guard isLegal(move) else { return false }
        switch move {
        case .tableauToCell(let from, let cell):
            cells[cell] = tableau[from].removeLast()
        case .tableauToFoundation(let pile):
            let card = tableau[pile].removeLast()
            foundations[card.suit.rawValue] = card.rank
        case .tableauToTableau(let from, let cardIndex, let to):
            let run = Array(tableau[from][cardIndex...])
            tableau[from].removeSubrange(cardIndex...)
            tableau[to].append(contentsOf: run)
        case .cellToTableau(let cell, let to):
            // 先に取り出す。置いてから消すと、置き先の判定に使った盤面と実際の盤面がずれる。
            guard let card = cells[cell] else { return false }
            cells[cell] = nil
            tableau[to].append(card)
        case .cellToFoundation(let cell):
            guard let card = cells[cell] else { return false }
            cells[cell] = nil
            foundations[card.suit.rawValue] = card.rank
        }
        return true
    }

    // MARK: - 詰み検知

    /// 指せる手が1つも無い状態。
    ///
    /// クロンダイク（#397）と違い、フリーセルには**山めくりのような「進まないが指せる手」が無い**。
    /// セルが1つでも空いていれば必ず退避できるので、`legalMoves` が空になるのは
    /// 「全セルが埋まり、どの札もどこにも置けず、組札にも送れない」完全な行き止まりだけ。
    /// したがって「進む手」と「合法手」を区別する必要が無く、判定に近似が入らない。
    public var isDeadEnd: Bool { !isWon && legalMoves.isEmpty }

    /// 合法手の全量。詰み検知と、テストからの網羅に使う。
    ///
    /// 退避（`tableauToCell`）は**空きセルのうち先頭の1つだけ**を挙げる。セルは等価なので、
    /// 4 つ全部を挙げると同じ盤面へ至る手が最大4本に増えるだけで意味が無い。
    public var legalMoves: [FreeCellMove] {
        var moves: [FreeCellMove] = []
        for pile in tableau.indices where isLegal(.tableauToFoundation(pile: pile)) {
            moves.append(.tableauToFoundation(pile: pile))
        }
        for cell in cells.indices where isLegal(.cellToFoundation(cell: cell)) {
            moves.append(.cellToFoundation(cell: cell))
        }
        for from in tableau.indices {
            for index in tableau[from].indices where isOrderedRun(pile: from, from: index) {
                let run = Array(tableau[from][index...])
                for to in tableau.indices where to != from && canPlace(run, onPile: to) {
                    moves.append(.tableauToTableau(from: from, cardIndex: index, to: to))
                }
            }
        }
        for cell in cells.indices {
            for to in tableau.indices where isLegal(.cellToTableau(cell: cell, to: to)) {
                moves.append(.cellToTableau(cell: cell, to: to))
            }
        }
        if let cell = cells.firstIndex(where: { $0 == nil }) {
            for from in tableau.indices where !tableau[from].isEmpty {
                moves.append(.tableauToCell(from: from, cell: cell))
            }
        }
        return moves
    }

    // MARK: - 探索用のキー

    /// 同一局面の判定に使う正準表現。
    ///
    /// **列とセルは並べ替えても同じ局面**（合法手の集合が完全に一致する）なので、
    /// 符号化する前に並びを揃える。これをしないと探索が「列を入れ替えただけの局面」を
    /// 最大 8! 通り別物として掘る。
    public var stateKey: Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(72)
        bytes.append(contentsOf: foundations.map { UInt8($0) })
        bytes.append(0xFE)
        // セルは中身の id 順（空きは最後）に揃える。
        for id in cells.compactMap({ $0?.id }).sorted() { bytes.append(UInt8(id)) }
        bytes.append(0xFD)
        // 列は「札の id の並び」を辞書順に揃える。空列は空配列なので先頭に集まる。
        for pile in tableau.map({ $0.map(\.id) }).sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            bytes.append(contentsOf: pile.map { UInt8($0) })
            bytes.append(0xFF)
        }
        return Data(bytes)
    }
}
