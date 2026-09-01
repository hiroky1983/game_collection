import Foundation

/// 終局時の点数（中国ルール・面積計算）。
///
/// **面積計算の定義**: ある色の得点 = 盤上に残っているその色の石の数 + その色の石だけに
/// 囲まれた空点の数。取った石の数は数えない（日本ルールとの最大の違い）。
///
/// **セキ（相互に取れない形）の扱い**: 特別扱いをしない。セキの石は盤上に残るので双方の
/// 得点にそのまま入り、両者に接する共有の空点（ダメ）はどちらの色にも囲まれていないので
/// `neutral` に入る。日本ルールのように「セキの目は数えない」といった例外規定が要らないのが
/// 面積計算を採った理由のひとつ（#398）。
public struct GoScore: Equatable, Sendable {
    /// 黒の面積（石 + 黒だけに囲まれた空点）。
    public let blackArea: Int
    /// 白の面積。
    public let whiteArea: Int
    /// どちらの色にも囲まれていない空点（ダメ・セキの共有点）。
    public let neutral: Int
    public let komi: Double
    /// 置き石補正（白に加算する目数）。
    public let handicapCompensation: Int

    public init(blackArea: Int, whiteArea: Int, neutral: Int, komi: Double, handicapCompensation: Int) {
        self.blackArea = blackArea
        self.whiteArea = whiteArea
        self.neutral = neutral
        self.komi = komi
        self.handicapCompensation = handicapCompensation
    }

    public var blackTotal: Double { Double(blackArea) }
    public var whiteTotal: Double { Double(whiteArea) + komi + Double(handicapCompensation) }

    /// 黒から見た差（正なら黒勝ち）。
    public var margin: Double { blackTotal - whiteTotal }

    /// 勝者。コミが半目なら必ずどちらかに決まる（引き分けは nil）。
    public var winner: GoStone? {
        if margin > 0 { return .black }
        if margin < 0 { return .white }
        return nil
    }

    /// 「白 3.5 目勝ち」のような 1 行。
    public var summary: String {
        guard let winner else { return "引き分け" }
        let diff = abs(margin)
        let text = diff == diff.rounded() ? String(Int(diff)) : String(format: "%.1f", diff)
        return "\(winner.name) \(text)目勝ち"
    }
}

/// 面積計算と終局処理（#398）。すべて純関数。
public enum GoScoring {
    /// 面積計算。石と、その色だけに囲まれた空点を数える。
    ///
    /// **保存則**: `blackArea + whiteArea + neutral == 盤の交点数` が常に成り立つ
    /// （テストで固定している）。
    public static func area(of board: GoBoard) -> (black: Int, white: Int, neutral: Int) {
        var black = 0, white = 0, neutral = 0
        var visited = [Bool](repeating: false, count: board.pointCount)

        for point in board.allPoints {
            let index = point.row * board.size + point.col
            if let stone = board[point] {
                if stone == .black { black += 1 } else { white += 1 }
                continue
            }
            guard !visited[index] else { continue }

            // 空点の連結領域をまとめて調べ、接している石の色を集める。
            var region: [GoPoint] = []
            var borders = Set<GoStone>()
            var stack = [point]
            visited[index] = true
            while let current = stack.popLast() {
                region.append(current)
                board.forEachNeighbor(of: current) { neighbor in
                    let neighborIndex = neighbor.row * board.size + neighbor.col
                    if let stone = board[neighbor] {
                        borders.insert(stone)
                    } else if !visited[neighborIndex] {
                        visited[neighborIndex] = true
                        stack.append(neighbor)
                    }
                }
            }

            if borders.count == 1, let owner = borders.first {
                if owner == .black { black += region.count } else { white += region.count }
            } else {
                // 空の盤（borders が 0 件）も、両者に接する点（2 件）も中立。
                neutral += region.count
            }
        }
        return (black, white, neutral)
    }

    /// 死に石を取り除いてから面積計算する。
    ///
    /// - Parameter dead: 取り除く石の交点（`GoDeadStones.analyze` の結果）。
    public static func score(
        board: GoBoard,
        removing dead: Set<GoPoint> = [],
        ruleset: GoRuleset
    ) -> GoScore {
        var work = board
        for point in dead { work[point] = nil }
        let counted = area(of: work)
        return GoScore(
            blackArea: counted.black,
            whiteArea: counted.white,
            neutral: counted.neutral,
            komi: ruleset.komi,
            handicapCompensation: ruleset.handicapCompensation
        )
    }
}

/// 簡易死活判定の結果。
public struct GoDeadStoneAnalysis: Equatable, Sendable {
    /// 明確に死んでいると判断した石の交点。
    public let dead: Set<GoPoint>
    /// 判定の曖昧さ（0 = 全ての石が明確・1 = 五分）。**これが大きいときは自動除去を信用しない**。
    public let uncertainty: Double
    /// 交点ごとの「黒が持つ確率」（0…1）。デバッグ・テスト用。
    public let blackOwnership: [Double]

    /// 会長指示の「判定が疑わしい場合は対局続行に戻れる導線」を出すしきい値。
    public static let uncertainThreshold = 0.35

    public var isConfident: Bool { uncertainty < Self.uncertainThreshold }
}

/// 両者パスのあとの「明確な死に石」の判定（#398）。
///
/// **やり方**: 現局面からランダム対局（自分の眼は埋めない）を最後まで打ち切るのを N 回繰り返し、
/// 各交点が最終的にどちらの色のものになったかを数える。相手の色に **85% 以上**倒れた石だけを
/// 死んだ石とみなす。決め打ちの形状ルールを並べるより誤判定が少なく、乱数の種を固定すれば
/// 完全に再現するのでテストで固定できる。
///
/// この方式は「明確な死に石のみ自動除去」（#398 の仕様）とちょうど対応する。曖昧な石が残る
/// 局面では `uncertainty` が上がるので、UI は自動確定せず「対局続行」を促す。
public enum GoDeadStones {
    /// 死んだと判断するしきい値（相手側の所有率）。
    public static let deadThreshold = 0.85

    public static func analyze(
        state: GoState,
        playouts: Int = 400,
        seed: UInt64 = 0x60_0D_5EED
    ) -> GoDeadStoneAnalysis {
        let board = state.board
        let count = board.pointCount
        guard playouts > 0 else {
            return GoDeadStoneAnalysis(dead: [], uncertainty: 1, blackOwnership: Array(repeating: 0.5, count: count))
        }

        var blackOwnedCount = [Int](repeating: 0, count: count)
        var random = GoRandom(seed: seed)

        for _ in 0..<playouts {
            // 終局判定からの再開なので、パス数を戻してから打ち切る。
            var playout = state.playoutCopy()
            playout.resumePlay()
            GoPlayout.run(&playout, random: &random)
            let owners = owners(of: playout.board)
            for index in 0..<count where owners[index] == .black {
                blackOwnedCount[index] += 1
            }
        }

        let ownership = blackOwnedCount.map { Double($0) / Double(playouts) }
        var dead = Set<GoPoint>()
        var maxAmbiguity = 0.0
        for point in board.allPoints {
            guard let stone = board[point] else { continue }
            let index = point.row * board.size + point.col
            let ownedByOwner = stone == .black ? ownership[index] : 1 - ownership[index]
            if 1 - ownedByOwner >= deadThreshold { dead.insert(point) }
            // 「自分のもの」でも「相手のもの」でもない石ほど曖昧。0.5 で最大 1 になる。
            maxAmbiguity = max(maxAmbiguity, 1 - abs(ownedByOwner * 2 - 1))
        }
        return GoDeadStoneAnalysis(dead: dead, uncertainty: maxAmbiguity, blackOwnership: ownership)
    }

    /// 打ち切った盤面で、各交点が最終的にどちらのものかを返す（面積計算と同じ定義）。
    static func owners(of board: GoBoard) -> [GoStone?] {
        var result = [GoStone?](repeating: nil, count: board.pointCount)
        var visited = [Bool](repeating: false, count: board.pointCount)

        for point in board.allPoints {
            let index = point.row * board.size + point.col
            if let stone = board[point] {
                result[index] = stone
                continue
            }
            guard !visited[index] else { continue }

            var region: [Int] = []
            var borders = Set<GoStone>()
            var stack = [point]
            visited[index] = true
            while let current = stack.popLast() {
                region.append(current.row * board.size + current.col)
                board.forEachNeighbor(of: current) { neighbor in
                    let neighborIndex = neighbor.row * board.size + neighbor.col
                    if let stone = board[neighbor] {
                        borders.insert(stone)
                    } else if !visited[neighborIndex] {
                        visited[neighborIndex] = true
                        stack.append(neighbor)
                    }
                }
            }
            if borders.count == 1, let owner = borders.first {
                for cell in region { result[cell] = owner }
            }
        }
        return result
    }
}
