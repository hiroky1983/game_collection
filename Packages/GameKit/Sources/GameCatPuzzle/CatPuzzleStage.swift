import Foundation
import CoreEngine

/// ステージモードの n 面目の決まり（#3048）。クリアしたら次の面へ進むだけの連番で、問題は固定データを持たず
/// **ステージ番号から決めた種でその場で作る**（同じ番号なら誰でも同じ問題）。
///
/// 難しさはステージ番号で上げていく: 10 面ごとに盤を 1 回り広げ（6×6 → 7×7 → 8×8 → 31 面目から 9×9）、
/// 6〜8 の盤は各 10 面の前半を「段 3 までで解ける」、後半を「段 4 が要る」問題にする。
/// 段の意味は `CatPuzzleSolver`。段 5（当て推量）が要る問題は出さない。
public struct CatPuzzleStage: Equatable, Sendable {
    /// 1 始まりのステージ番号。
    public let number: Int

    public init(_ number: Int) {
        self.number = max(1, number)
    }

    /// 1 回りの盤で遊ぶ面の数。
    public static let stagesPerSize = 10

    /// 盤の大きさ。
    public var size: CatPuzzleSize {
        switch (number - 1) / Self.stagesPerSize {
        case 0: .easy
        case 1: .normal
        case 2: .hard
        default: .expert
        }
    }

    /// 採る問題の段の範囲（`CatPuzzleSolver` が測った、要った最上位の段）。
    /// 9×9 は段 3 で解ける問題が少なく作るのに時間がかかるので、段 4 までのどれでも採る。
    public var tiers: ClosedRange<Int> {
        guard size != .expert else { return 1...4 }
        return (number - 1) % Self.stagesPerSize < Self.stagesPerSize / 2 ? 1...3 : 4...4
    }

    /// 問題の種。ステージ番号を `SplitMix64` で 1 回かき混ぜる（隣の面で似た問題にならないように）。
    public var seed: UInt64 {
        var mixer = SplitMix64(seed: UInt64(number) &+ 3048)
        return mixer.next()
    }

    /// この面の問題。9×9（31 面目から）は作るのに最大で数秒かかり、iPhone SE では数倍になるので、
    /// 前もって作った問題（`CatPuzzleStageBank`）があればそれを使う（同梱の範囲を越えたら `generatePuzzle` で作る）。
    public func makePuzzle() -> CatPuzzle {
        CatPuzzleStageBank.puzzle(for: number) ?? generatePuzzle()
    }

    /// この面の問題をその場で作る。種から決まるので、何度作っても同じ問題になる。
    /// 生成した問題（解は必ず 1 つ）を解き手で測り、段が `tiers` に入る最初の 1 問を採る。
    /// 呼び出し元の `Task` が取り消されたら、その時点の問題（段が範囲外のこともある）を返して抜ける。
    /// 取り消した側はその問題を使わない（`CatPuzzleModel.startStage`）。
    public func generatePuzzle() -> CatPuzzle {
        var generator = SplitMix64(seed: seed)
        while true {
            let puzzle = CatPuzzleLogic.generate(size: size, using: &generator)
            if Task.isCancelled { return puzzle }
            let difficulty = CatPuzzleSolver.rate(puzzle, maxTier: 4)
            if difficulty.solved && tiers.contains(difficulty.tier) { return puzzle }
        }
    }
}
