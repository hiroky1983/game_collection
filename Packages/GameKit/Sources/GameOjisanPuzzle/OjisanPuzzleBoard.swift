import Foundation
import CoreEngine

/// 種を与えると同じ並びを再現する乱数（SplitMix64）。テストから荷物の並びを固定するのに使う。
/// 実体は CoreEngine の `SplitMix64`（他ゲームと同じもの）。
public typealias OjisanPuzzleRandom = SplitMix64

/// 盤のマス 1 つ。
public struct OjisanPuzzleCell: Hashable, Sendable {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}

/// 腰痛おじさんパズルの純粋ロジック。SwiftUI 非依存・乱数は呼び出し側が持つので、
/// 盤の判定はすべてここで網羅的にテストできる（`BlockPuzzleBoard` と同じ作法）。
///
/// 盤は `[[Int]]` で、0 = 空きマス、1...4 = 荷物の種類。行は**上が 0**（`rows - 1` が床）。
public enum OjisanPuzzleBoard {
    /// 盤の列数。
    public static let columns = 6
    /// 盤の段数。
    public static let rows = 12
    /// 荷物の種類の数。
    public static let kindCount = 4
    /// 消えるのに必要な連結数。
    public static let clearThreshold = 4

    public static func emptyBoard() -> [[Int]] {
        Array(repeating: Array(repeating: 0, count: columns), count: rows)
    }

    /// 盤として妥当な形か（12 段 × 6 列・種類が 0...4）。
    public static func isValid(_ board: [[Int]]) -> Bool {
        guard board.count == rows else { return false }
        return board.allSatisfy { row in
            row.count == columns && row.allSatisfy { (0...kindCount).contains($0) }
        }
    }

    public static func isInside(row: Int, col: Int) -> Bool {
        row >= 0 && row < rows && col >= 0 && col < columns
    }

    /// 空きマスか。盤の外は「空いていない」として扱う（置ける場所の判定に直接使うため）。
    public static func isEmpty(_ board: [[Int]], row: Int, col: Int) -> Bool {
        isInside(row: row, col: col) && board[row][col] == 0
    }

    // MARK: - 連結・消去・重力

    /// (row, col) と同じ種類でつながっているマスの一覧（自分を含む）。上下左右のみ。
    /// 空きマス・盤の外を指したら空配列。
    public static func connectedGroup(_ board: [[Int]], row: Int, col: Int) -> [OjisanPuzzleCell] {
        guard isInside(row: row, col: col) else { return [] }
        let kind = board[row][col]
        guard kind != 0 else { return [] }

        var seen: Set<OjisanPuzzleCell> = [OjisanPuzzleCell(row: row, col: col)]
        var stack = [OjisanPuzzleCell(row: row, col: col)]
        var group: [OjisanPuzzleCell] = []
        while let cell = stack.popLast() {
            group.append(cell)
            for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let next = OjisanPuzzleCell(row: cell.row + dr, col: cell.col + dc)
                guard isInside(row: next.row, col: next.col) else { continue }
                guard board[next.row][next.col] == kind, !seen.contains(next) else { continue }
                seen.insert(next)
                stack.append(next)
            }
        }
        // 並びを固定しておくとテストの比較が楽（上から・左から）。
        return group.sorted { $0.row == $1.row ? $0.col < $1.col : $0.row < $1.row }
    }

    /// 盤の中で `clearThreshold` 以上つながっている塊をすべて返す。**同時に判定してからまとめて消す**
    /// （1 つ消してから数え直すと、隣り合う別の塊が数え漏れる）。
    public static func clearableGroups(_ board: [[Int]]) -> [[OjisanPuzzleCell]] {
        var visited = Array(repeating: Array(repeating: false, count: columns), count: rows)
        var groups: [[OjisanPuzzleCell]] = []
        for row in 0..<rows {
            for col in 0..<columns {
                guard !visited[row][col], board[row][col] != 0 else { continue }
                let group = connectedGroup(board, row: row, col: col)
                for cell in group { visited[cell.row][cell.col] = true }
                if group.count >= clearThreshold { groups.append(group) }
            }
        }
        return groups
    }

    /// 指定のマスを空きにした盤を返す。
    public static func removing(_ board: [[Int]], groups: [[OjisanPuzzleCell]]) -> [[Int]] {
        var result = board
        for group in groups {
            for cell in group where isInside(row: cell.row, col: cell.col) {
                result[cell.row][cell.col] = 0
            }
        }
        return result
    }

    /// 重力。列ごとに、浮いている荷物を下詰めする（順序は保つ）。
    public static func applyingGravity(_ board: [[Int]]) -> [[Int]] {
        var result = emptyBoard()
        for col in 0..<columns {
            var write = rows - 1
            for row in stride(from: rows - 1, through: 0, by: -1) where board[row][col] != 0 {
                result[write][col] = board[row][col]
                write -= 1
            }
        }
        return result
    }

    /// 重力 → 消去 → 重力 …… を落ち着くまで繰り返す。
    ///
    /// - Returns: 落ち着いた盤と、連鎖ごとに消えたマス数（`chains[0]` が 1 連鎖目）。
    public static func resolve(_ board: [[Int]]) -> (board: [[Int]], chains: [Int]) {
        var current = applyingGravity(board)
        var chains: [Int] = []
        while true {
            let groups = clearableGroups(current)
            guard !groups.isEmpty else { break }
            chains.append(groups.reduce(0) { $0 + $1.count })
            current = applyingGravity(removing(current, groups: groups))
        }
        return (current, chains)
    }

    // MARK: - 落ちてくる 2 個組

    /// 組が盤に収まっていて、2 マスとも空いているか。
    public static func canPlace(_ board: [[Int]], _ pair: OjisanPuzzlePair) -> Bool {
        pair.cells.allSatisfy { isEmpty(board, row: $0.cell.row, col: $0.cell.col) }
    }

    /// 左右へ 1 マス動かした組。動かせなければ nil。
    public static func moved(_ board: [[Int]], _ pair: OjisanPuzzlePair, byColumns delta: Int) -> OjisanPuzzlePair? {
        var moved = pair
        moved.col += delta
        return canPlace(board, moved) ? moved : nil
    }

    /// 1 段下げた組。下げられなければ nil（＝接地）。
    public static func steppedDown(_ board: [[Int]], _ pair: OjisanPuzzlePair) -> OjisanPuzzlePair? {
        var moved = pair
        moved.row += 1
        return canPlace(board, moved) ? moved : nil
    }

    /// 落ちるところまで落とした組。1 段も落ちなければそのまま返す。
    public static func hardDropped(_ board: [[Int]], _ pair: OjisanPuzzlePair) -> OjisanPuzzlePair {
        var current = pair
        while let next = steppedDown(board, current) { current = next }
        return current
    }

    /// 回した組。**壁・床に当たったら軸をずらして逃がす**（いわゆる壁蹴り）。どうやっても
    /// 置けないときだけ nil を返す。
    public static func rotated(_ board: [[Int]], _ pair: OjisanPuzzlePair, clockwise: Bool) -> OjisanPuzzlePair? {
        var turned = pair
        turned.rotation = clockwise ? pair.rotation.turnedRight : pair.rotation.turnedLeft
        let offset = turned.rotation.offset
        // 子が出っ張る向きと逆へ軸を 1 マス逃がす。縦横どちらかしか 0 以外にならない。
        let kicks = [(0, 0), (0, -offset.col), (-offset.row, 0)]
        for (dr, dc) in kicks {
            var candidate = turned
            candidate.row += dr
            candidate.col += dc
            if canPlace(board, candidate) { return candidate }
        }
        return nil
    }

    /// 組を盤に固定した盤を返す。盤の外にはみ出したマスは捨てる（呼び出し側は接地済みの組を渡す）。
    public static func locking(_ board: [[Int]], _ pair: OjisanPuzzlePair) -> [[Int]] {
        var result = board
        for placed in pair.cells where isInside(row: placed.cell.row, col: placed.cell.col) {
            result[placed.cell.row][placed.cell.col] = placed.kind
        }
        return result
    }

    /// 次の組を作る。軸は盤の中央、子は真上。
    public static func spawn(axisKind: Int, childKind: Int) -> OjisanPuzzlePair {
        OjisanPuzzlePair(axisKind: axisKind, childKind: childKind,
                         row: 1, col: columns / 2 - 1, rotation: .up)
    }

    /// 乱数から次の組を引く。
    public static func makePair(using rng: inout OjisanPuzzleRandom) -> OjisanPuzzlePair {
        spawn(axisKind: Int.random(in: 1...kindCount, using: &rng),
              childKind: Int.random(in: 1...kindCount, using: &rng))
    }
}

/// 運ぶ荷物の中身。盤の `Int`（1...4）に「何を運んでいるか」と「重さ」を結び付ける。
///
/// **重さはまだルールに効かせていない**（見た目だけ・会長の「何を運んでいるか分かるようにしたい」への
/// プロトタイプの答え）。腰へのこたえ方を重さで変える案はここに `perLock` を足す形で入れられるよう、
/// 表示側ではなくこの純粋な層に置いてある。
public enum OjisanPuzzleLuggage {
    /// 荷物 1 種。
    public struct Kind: Equatable, Sendable {
        /// 盤に入る番号（1...4）。
        public let value: Int
        /// 表示名（読み上げ・説明に使う）。
        public let name: String
        /// 見た目に使う SF Symbol の名前。ドット絵の描き起こしは試作の範囲外なので記号で代用する。
        public let symbol: String
        /// 重さ（1 = 軽い 〜 4 = いちばん重い）。今は色の濃さにしか効かない。
        public let weight: Int
    }

    /// 軽い順に並べた 4 種。並びを変えると既存の盤の見た目が入れ替わるので、足すときは末尾に足す。
    public static let all: [Kind] = [
        Kind(value: 1, name: "段ボール箱", symbol: "shippingbox.fill",  weight: 1),
        Kind(value: 2, name: "座布団",     symbol: "square.stack.fill", weight: 2),
        Kind(value: 3, name: "米袋",       symbol: "bag.fill",          weight: 3),
        Kind(value: 4, name: "タンス",     symbol: "bed.double.fill",   weight: 4),
    ]

    /// 盤の番号から引く。空きマス（0）・範囲外は nil。
    public static func kind(_ value: Int) -> Kind? {
        all.first { $0.value == value }
    }
}

/// 腰痛ゲージ（0...100）。固定するたびに増え、消すと減る。純関数なのでそのままテストできる。
///
/// **ゲージはただの体力バーではない**（会長指示 2026-09-17）。溜まるほど荷物が速く落ち、
/// 左右移動と回転がワンテンポ遅れる＝「痛くて体が思うように動かない」を遊びに効かせる。
/// 「溜まる → 動けない → さらに詰む」の悪循環がこの企画の核心なので、段階と係数はすべてここに置く。
public enum OjisanPuzzlePain {
    /// 腰の重さの段階。数字ではなくこの段階で挙動を決める（調整は下の定数だけで済む）。
    public enum Stage: Int, CaseIterable, Sendable, Comparable {
        /// まだ平気（0...39）。
        case easy = 0
        /// 腰にくる（40...79）。落ちが速くなり、操作が少し遅れる。
        case aching
        /// 限界（80...99）。落ちがかなり速く、操作もはっきり遅れる。
        case severe

        public static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }

        /// 見出しに出す短い呼び名。
        public var caption: String {
            switch self {
            case .easy: "まだ平気"
            case .aching: "腰にくる"
            case .severe: "こしが限界"
            }
        }
    }

    /// 段階の境目。`[40, 80]` なら 0...39 / 40...79 / 80... の 3 段。
    public static let stageThresholds = [40, 80]

    /// ゲージから段階を引く。
    public static func stage(for pain: Int) -> Stage {
        let level = stageThresholds.filter { clamped(pain) >= $0 }.count
        return Stage(rawValue: level) ?? .severe
    }

    /// 落下の速さの倍率（段階ごと）。1.0 = 元の速さ、小さいほど速く落ちる。
    /// `dropInterval`（ミリ秒）に掛けるので、0.55 なら刻みがおよそ半分＝倍の速さ。
    public static func fallFactor(for pain: Int) -> Double {
        switch stage(for: pain) {
        case .easy: 1.0
        case .aching: 0.72
        case .severe: 0.5
        }
    }

    /// 左右移動・回転を次に受け付けるまで空ける時間（ミリ秒）。0 なら連続で効く。
    ///
    /// 落とす操作（下スワイプ）は遅らせない。詰みかけているときに落とせなくなると、
    /// 「重くなった」ではなく「操作を奪われた」手触りになるため。
    public static func inputDelayMilliseconds(for pain: Int) -> Int {
        switch stage(for: pain) {
        case .easy: 0
        case .aching: 110
        case .severe: 240
        }
    }

    /// 入院する値。
    public static let limit = 100
    /// 荷物を 1 組固定したときに増える量。
    public static let perLock = 7
    /// 荷物 1 個を消したときに減る量。
    public static let perClearedCell = 2
    /// 2 連鎖目以降、1 連鎖ごとに追加で減る量。
    public static let perExtraChain = 5

    /// 固定したあとのゲージ。
    public static func afterLock(_ pain: Int) -> Int {
        clamped(pain + perLock)
    }

    /// 1 連鎖ぶん消したあとのゲージ。`chain` は 1 から数える（深いほどよく減る）。
    public static func afterChain(_ pain: Int, cells: Int, chain: Int) -> Int {
        guard cells > 0, chain > 0 else { return clamped(pain) }
        return clamped(pain - cells * perClearedCell - (chain - 1) * perExtraChain)
    }

    /// 連鎖全体を消したあとのゲージ。`chains` は `OjisanPuzzleBoard.resolve` の戻り値と同じ形。
    public static func afterClears(_ pain: Int, chains: [Int]) -> Int {
        chains.enumerated().reduce(clamped(pain)) {
            afterChain($0, cells: $1.element, chain: $1.offset + 1)
        }
    }

    /// 入院（ゲームオーバー）か。
    public static func isHospitalized(_ pain: Int) -> Bool { pain >= limit }

    public static func clamped(_ pain: Int) -> Int { min(max(0, pain), limit) }
}

/// 得点。消したマス数と連鎖の深さで決まる。
public enum OjisanPuzzleScoring {
    /// 1 連鎖ぶんの点。`chain` は 1 から数える。
    public static func chainPoints(cells: Int, chain: Int) -> Int {
        guard cells > 0, chain > 0 else { return 0 }
        return cells * 10 * chain
    }

    /// 連鎖全体の点。
    public static func totalPoints(chains: [Int]) -> Int {
        chains.enumerated().reduce(0) { $0 + chainPoints(cells: $1.element, chain: $1.offset + 1) }
    }
}
