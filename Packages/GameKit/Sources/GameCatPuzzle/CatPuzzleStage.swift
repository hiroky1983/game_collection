import Foundation
import CoreEngine

/// ステージモードの n 面目の決まり（#3048）。クリアしたら次の面へ進むだけの連番で、問題は固定データを持たず
/// **ステージ番号から決めた種でその場で作る**（同じ番号なら誰でも同じ問題）。
///
/// 難しさはステージ番号で上げていく: 盤を 6×6 → 7×7 → 8×8 → 9×9 → 10×10 → 11×11 → 141 面目から 12×12（頭打ち）と広げる。
/// 盤ごとの面数は `boards` の表のとおり（広い盤ほど長く遊べる・#3223）。
/// 6〜8・10・11 の盤は各盤の前半を「段 3 までで解ける」、後半を「段 4 が要る」問題にする。
/// 段の意味は `CatPuzzleSolver`。段 5（当て推量）が要る問題は出さない。
/// 鍵の面（#3235）は、9×9 までは 10 面ごと（10・20…70 面目）、10×10 以上は 20 面ごと（80・100・120…面目・#3259）。
/// 鍵を持った猫の部屋が先に論理だけで決まる問題を採る（`CatPuzzleSolver.keyCat`）。10×10 以上の鍵の面は難しすぎないよう、
/// 段 3 まで（12×12 は段 4 まで可）・入り組みも前半と同じにする。
public struct CatPuzzleStage: Equatable, Sendable {
    /// 1 始まりのステージ番号。
    public let number: Int

    public init(_ number: Int) {
        self.number = max(1, number)
    }

    /// 鍵の面（#3235）の周期。9×9 までは 10 面ごとに「鍵を持った猫」の面を入れる。
    static let keyPeriod = 10

    /// 10×10 以上の鍵の面の周期（#3259）。盤が大きいと鍵の制限が重なって難しすぎるので間を空ける。
    static let wideKeyPeriod = 20

    /// 9×9 までの最後の面（70 面目）。この次の面（71 面目）から 10×10 以上で、鍵の面が 20 面ごとになる。
    private static let lastSmallBoardStage = boards.filter { $0.size.side <= CatPuzzleSize.expert.side }.reduce(0) { $0 + $1.stages }

    /// 鍵の面か（9×9 までは 10・20…70 面目、10×10 以上は 80・100・120…面目）。
    public var isKey: Bool { number == nextKeyNumber }

    /// この面以降（この面を含む）で最初の鍵の面の番号。
    private var nextKeyNumber: Int {
        let period = number <= Self.lastSmallBoardStage ? Self.keyPeriod : Self.wideKeyPeriod
        return (number + period - 1) / period * period
    }

    /// 10×10 以上の鍵の面か（難しさを 1 段下げる面）。
    private var isWideKey: Bool { isKey && size.side > CatPuzzleSize.expert.side }

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
    /// 10×10 以上の鍵の面は、盤の前半と同じ段 3 までを狙う（12×12 は前半が段 4 まで可なので同じ）（#3259）。
    public var tiers: ClosedRange<Int> {
        guard size != .expert else { return 1...4 }
        if isWideKey { return size == .size12 ? 1...4 : 1...3 }
        if size == .size12 && isFirstHalf { return 1...4 }
        return isFirstHalf ? 1...3 : 4...4
    }

    /// 部屋の入り組み具合（`CatPuzzleLogic.generate` の `winding`）。9×9 までは従来どおり 0。
    /// 10×10 以上は、前半（段 3 まで）を 1、後半（段 4 が要る）を 2 にして、難しい面ほど細長い・曲がった部屋を増やす。
    public var winding: Int {
        guard size.side > CatPuzzleSize.expert.side else { return 0 }
        return isFirstHalf || isWideKey ? 1 : 2
    }

    /// 今の位置の見せ方（#3240）。開始シートとクリアのカードに出す。
    public struct Progress: Equatable, Sendable {
        /// 盤の大きさ。
        public let size: CatPuzzleSize
        /// その盤の中での 1 始まりの位置（12×12 は 141 面目が 1）。
        public let position: Int
        /// その盤の面数。12×12 は以降ずっとなので nil（ゲージも出さない）。
        public let count: Int?
        /// 次の盤。12×12 では nil。
        public let nextSize: CatPuzzleSize?
        /// 次の盤に入るまでに、この面のあとに残る今の盤の面数（盤の最後の面で 0）。12×12 では nil。
        public let toNextBoard: Int?
        /// 鍵の面そのものか。
        public let isKey: Bool
        /// 鍵の面に着くまでに、この面のあとに挟まる面数（鍵の面の 1 つ前で 0。鍵の面そのものでは 0）。
        public let toKey: Int

        /// ゲージの進み具合（0〜1。盤の面数が決まっていない 12×12 は nil）。
        public var fraction: Double? { count.map { Double(position) / Double($0) } }
    }

    /// この面の位置（#3240）。
    public var progress: Progress {
        let place = placement
        let isLast = place.size == .size12
        var count: Int?
        var next: CatPuzzleSize?
        if !isLast, let at = Self.boards.firstIndex(where: { $0.size == place.size }) {
            count = place.count
            next = at + 1 < Self.boards.count ? Self.boards[at + 1].size : .size12
        }
        let position = isLast ? number - Self.boards.reduce(0) { $0 + $1.stages } : place.index + 1
        return Progress(
            size: place.size, position: position, count: count, nextSize: next,
            toNextBoard: count.map { $0 - position },
            isKey: isKey,
            toKey: isKey ? 0 : nextKeyNumber - number - 1
        )
    }

    /// 盤が切り替わる面か（2 面目以降で、その盤の最初の面）。「8×8 に進んだ！」の演出を出す面。
    public var entersNewBoard: Bool { number > 1 && progress.position == 1 }

    /// 問題の種。ステージ番号を `SplitMix64` で 1 回かき混ぜる（隣の面で似た問題にならないように）。
    public var seed: UInt64 {
        var mixer = SplitMix64(seed: UInt64(number) &+ 3048)
        return mixer.next()
    }

    /// この面の問題。9×9 以上（46 面目から）は作るのに数秒〜数分かかり、iPhone SE では数倍になるので、
    /// 前もって作った問題（`CatPuzzleStageBank`）があればそれを使う（45 面目まではその場で `generatePuzzle` で作る。1,001 面目以降は同梱の 12×12 を面番号の順に繰り返す）。
    public func makePuzzle() -> CatPuzzle {
        CatPuzzleStageBank.puzzle(for: number) ?? generatePuzzle()
    }

    /// この面の問題をその場で作る。種から決まるので、何度作っても同じ問題になる。
    /// 生成した問題（解は必ず 1 つ）を解き手で測り、段が `tiers` に入る最初の 1 問を採る。
    /// 鍵の面は、さらに鍵の猫が先に決まる（`CatPuzzleSolver.keyCat` が nil でない）ものだけを採る。
    /// 呼び出し元の `Task` が取り消されたら、その時点の問題（段が範囲外のこともある）を返して抜ける。
    /// 取り消した側はその問題を使わない（`CatPuzzleModel.startStage`）。
    public func generatePuzzle() -> CatPuzzle {
        var generator = SplitMix64(seed: seed)
        while true {
            let puzzle = CatPuzzleLogic.generate(size: size, winding: winding, using: &generator)
            if Task.isCancelled { return puzzle }
            let difficulty = CatPuzzleSolver.rate(puzzle, maxTier: 4)
            if difficulty.solved && tiers.contains(difficulty.tier) && (!isKey || CatPuzzleSolver.keyCat(puzzle) != nil) {
                return puzzle
            }
        }
    }
}
