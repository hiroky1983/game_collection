import Foundation
import CoreEngine

/// ステージモードの n 面目の決まり（#3048）。クリアしたら次の面へ進むだけの連番で、問題は固定データを持たず
/// **ステージ番号から決めた種でその場で作る**（同じ番号なら誰でも同じ問題）。
///
/// 難しさはステージ番号で上げていく: 盤を 6×6 → 7×7 → 8×8 → 9×9 → 10×10 → 11×11 → 141 面目から 12×12（頭打ち）と広げる。
/// 盤ごとの面数は `boards` の表のとおり（広い盤ほど長く遊べる・#3223）。
/// 6〜8・10・11 の盤は各盤の前半を「段 3 までで解ける」、後半を「段 4 が要る」問題にする。
/// 段の意味は `CatPuzzleSolver`。段 5（当て推量）が要る問題は出さない。
public struct CatPuzzleStage: Equatable, Sendable {
    /// 1 始まりのステージ番号。
    public let number: Int

    public init(_ number: Int) {
        self.number = max(1, number)
    }

    /// 盤ごとの面数。上から順に遊ぶ（最後の 12×12 は以降ずっと）。
    static let boards: [(size: CatPuzzleSize, stages: Int)] = [
        (.easy, 10), (.normal, 15), (.hard, 20), (.expert, 25), (.size10, 30), (.size11, 40),
    ]

    /// 12×12 の前半・後半を分ける周期（12×12 は面数が決まっていないので 10 面ごと）。
    static let lastBoardPeriod = 10

    /// 盤の大きさと、その盤の中での 0 始まりの位置・その盤の面数（12×12 は周期）。
    private var placement: (size: CatPuzzleSize, index: Int, count: Int) {
        var rest = number - 1
        for board in Self.boards {
            if rest < board.stages { return (board.size, rest, board.stages) }
            rest -= board.stages
        }
        return (.size12, rest % Self.lastBoardPeriod, Self.lastBoardPeriod)
    }

    /// 盤の大きさ。
    public var size: CatPuzzleSize { placement.size }

    /// その盤の前半か（面数が奇数なら後半のほうが 1 面多い）。
    private var isFirstHalf: Bool {
        let place = placement
        return place.index < place.count / 2
    }

    /// 採る問題の段の範囲（`CatPuzzleSolver` が測った、要った最上位の段）。
    /// 9×9 は段 3 で解ける問題が少なく作るのに時間がかかるので、段 4 までのどれでも採る。
    /// 12×12 も前半は同じ理由で段 4 までのどれでも採る（段 3 までに絞ると 1 問に 10 分以上かかった・#3201）。
    public var tiers: ClosedRange<Int> {
        guard size != .expert else { return 1...4 }
        if size == .size12 && isFirstHalf { return 1...4 }
        return isFirstHalf ? 1...3 : 4...4
    }

    /// 部屋の入り組み具合（`CatPuzzleLogic.generate` の `winding`）。9×9 までは従来どおり 0。
    /// 10×10 以上は、前半（段 3 まで）を 1、後半（段 4 が要る）を 2 にして、難しい面ほど細長い・曲がった部屋を増やす。
    public var winding: Int {
        guard size.side > CatPuzzleSize.expert.side else { return 0 }
        return isFirstHalf ? 1 : 2
    }

    /// 問題の種。ステージ番号を `SplitMix64` で 1 回かき混ぜる（隣の面で似た問題にならないように）。
    public var seed: UInt64 {
        var mixer = SplitMix64(seed: UInt64(number) &+ 3048)
        return mixer.next()
    }

    /// この面の問題。9×9 以上（46 面目から）は作るのに数秒〜数分かかり、iPhone SE では数倍になるので、
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
            let puzzle = CatPuzzleLogic.generate(size: size, winding: winding, using: &generator)
            if Task.isCancelled { return puzzle }
            let difficulty = CatPuzzleSolver.rate(puzzle, maxTier: 4)
            if difficulty.solved && tiers.contains(difficulty.tier) { return puzzle }
        }
    }
}
