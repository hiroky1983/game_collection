import Foundation
import CoreEngine

/// CPU の手順選び。`CPUStrength` の 4 段階（入門 / 簡単 / ふつう / むずかしい）に対応する。
///
/// | 段階 | 中身 |
/// |---|---|
/// | 入門（-1） | 合法な手順から無作為に 1 つ |
/// | 簡単（0） | ピップ差と叩きだけを見る貪欲 |
/// | ふつう（1） | ブロットの危険・作ったポイント・自陣・バーまで見る静的評価 |
/// | むずかしい（2） | 上の評価で絞った候補について、相手の 21 通りの目の最善応手まで読む（1 手先の期待値） |
///
/// 開始シートの説明（`BackgammonView`）はこの表と一致させること（#416）。
public struct BackgammonEngine: Sendable {
    public let level: Int
    /// 入門の無作為選択に使う乱数の種。nil なら毎回変わる。
    public let seed: UInt64?

    public init(level: Int, seed: UInt64? = nil) {
        self.level = level
        self.seed = seed
    }

    /// 出た目に対する最善の手順（先頭から順に適用する）。動かせなければ空。
    public func bestSequence(board: BackgammonBoard, side: BackgammonSide, dice: [Int]) -> [BackgammonMove] {
        let candidates = BackgammonRules.sequences(board: board, side: side, dice: dice)
        guard !candidates.isEmpty else { return [] }
        if candidates.count == 1 { return candidates[0] }
        let strength = CPUStrength.strength(for: level)
        switch strength {
        case .novice:
            var rng = SplitMix64(seed: seed ?? UInt64.random(in: 0...UInt64.max))
            return candidates[Int(rng.next() % UInt64(candidates.count))]
        case .easy:
            return argmax(candidates) { Self.greedyScore(Self.result(of: $0, board, side), side) }
        case .normal:
            return argmax(candidates) { Self.evaluate(Self.result(of: $0, board, side), for: side) }
        case .hard:
            return lookahead(candidates: candidates, board: board, side: side)
        }
    }

    /// 同点なら**先に列挙された手順**を選ぶ。列挙は決定的なので、同じ局面・同じ目なら同じ手順になる。
    private func argmax(_ seqs: [[BackgammonMove]], _ score: ([BackgammonMove]) -> Double) -> [BackgammonMove] {
        var best = seqs[0], bestScore = -Double.infinity
        for s in seqs {
            let v = score(s)
            if v > bestScore { bestScore = v; best = s }
        }
        return best
    }

    static func result(of seq: [BackgammonMove], _ board: BackgammonBoard, _ side: BackgammonSide) -> BackgammonBoard {
        seq.reduce(board) { BackgammonRules.apply($1, to: $0, side: side) }
    }

    // MARK: - 評価

    /// 簡単: ピップの差と、相手をバーへ送った数だけ。
    static func greedyScore(_ board: BackgammonBoard, _ side: BackgammonSide) -> Double {
        Double(board.pipCount(side.opponent) - board.pipCount(side)) + Double(board.bar(for: side.opponent)) * 10
    }

    /// ふつう以上の静的評価（`side` にとって大きいほど良い）。
    ///
    /// 数字は「ピップ 1 = 1 点」を基準にした重み。ブロットの危険は、相手の駒が 1〜6 手前に
    /// いれば直接叩かれうる（約 1/3 前後の確率）ものとして、叩かれたときに失うピップに掛ける。
    static func evaluate(_ board: BackgammonBoard, for side: BackgammonSide) -> Double {
        var score = Double(board.pipCount(side.opponent) - board.pipCount(side))
        score += Double(board.off(for: side)) * 3
        score -= Double(board.off(for: side.opponent)) * 3
        score += sideFeatures(board, side)
        score -= sideFeatures(board, side.opponent)
        return score
    }

    /// 片側だけを見た特徴量（大きいほどその側に良い）。
    private static func sideFeatures(_ board: BackgammonBoard, _ side: BackgammonSide) -> Double {
        let n = BackgammonBoard.pointCount
        var score = 0.0
        // 自陣で作ったポイントは相手の入場と逃げを塞ぐ。
        var homePoints = 0
        var madeRun = 0, bestRun = 0
        for index in 0..<n {
            let mine = board.signedCount(at: index, for: side)
            let norm = side.normalized(index)
            if mine >= 2 {
                score += 2
                if norm <= 5 { homePoints += 1; score += 2 }
                // 相手陣（自分から見て 19〜24）のアンカーは逃げ道になる。
                if norm >= 18 { score += 1.5 }
                madeRun += 1
                bestRun = max(bestRun, madeRun)
            } else {
                madeRun = 0
            }
            if mine == 1 {
                score -= blotRisk(board, side, index: index)
            }
            // 同じポイントに積み過ぎ（4 個以上）は柔軟性を失う。
            if mine > 3 { score -= Double(mine - 3) * 0.5 }
        }
        // 4 つ以上連続したポイント（プライム）は大きく評価する。
        if bestRun >= 4 { score += Double(bestRun - 3) * 4 }
        // 相手がバーにいるとき、自陣の閉じ具合がそのまま相手の手番を奪う。
        score += Double(board.bar(for: side.opponent)) * Double(2 + homePoints * 2)
        score -= Double(board.bar(for: side)) * 6
        return score
    }

    /// `index` にあるブロットが叩かれる危険（失うピップ × おおまかな確率）。
    private static func blotRisk(_ board: BackgammonBoard, _ side: BackgammonSide, index: Int) -> Double {
        let n = BackgammonBoard.pointCount
        let opponent = side.opponent
        // 相手がここまで来るのに要する距離（相手の進行方向で手前にいる駒だけ）。
        var direct = false, indirect = false
        if board.bar(for: opponent) > 0 {
            // バーからの入場先は相手から見て 1〜6 ポイント = 自分から見た 19〜24。
            let distance = opponent == .white ? n - index : index + 1
            if distance <= 6 { direct = true }
        }
        for from in 0..<n where board.signedCount(at: from, for: opponent) > 0 {
            let distance = (index - from) * opponent.direction
            if distance >= 1 && distance <= 6 { direct = true }
            else if distance >= 7 && distance <= 12 { indirect = true }
        }
        // 叩かれたときに失うピップ = その駒の進み具合（自分の 24 ポイント側へ戻る）。
        let loss = Double(n - side.normalized(index))
        if direct { return loss * 0.35 }
        if indirect { return loss * 0.12 }
        return 0
    }

    // MARK: - 1 手先の読み（むずかしい）

    /// 相手の 21 通りの目について、相手の最善応手（静的評価）を確率で平均する。
    private func lookahead(candidates: [[BackgammonMove]], board: BackgammonBoard, side: BackgammonSide) -> [BackgammonMove] {
        // 静的評価で上位に絞ってから読む（候補は数百に達しうる）。
        let ranked = candidates
            .map { ($0, Self.evaluate(Self.result(of: $0, board, side), for: side)) }
            .sorted { $0.1 > $1.1 }
            .prefix(4)
        var best = ranked.first!.0, bestScore = -Double.infinity
        for (seq, _) in ranked {
            let after = Self.result(of: seq, board, side)
            // 自分の手であがっていればそれが最善。
            if after.hasWon(side) { return seq }
            let expected = Self.expectedOpponentReply(after, side: side)
            if expected > bestScore { bestScore = expected; best = seq }
        }
        return best
    }

    /// 相手が最善（相手にとって最良の静的評価）を返した後の局面の、`side` から見た評価の期待値。
    static func expectedOpponentReply(_ board: BackgammonBoard, side: BackgammonSide) -> Double {
        let opponent = side.opponent
        var total = 0.0
        for a in 1...6 {
            for b in a...6 {
                let weight = a == b ? 1.0 / 36 : 2.0 / 36
                let dice = BackgammonRules.dice(for: (a, b))
                let replies = BackgammonRules.sequences(board: board, side: opponent, dice: dice)
                var worst = evaluate(board, for: side)
                if !replies.isEmpty {
                    worst = Double.infinity
                    for r in replies {
                        let v = evaluate(result(of: r, board, opponent), for: side)
                        if v < worst { worst = v }
                    }
                }
                total += weight * worst
            }
        }
        return total
    }
}
