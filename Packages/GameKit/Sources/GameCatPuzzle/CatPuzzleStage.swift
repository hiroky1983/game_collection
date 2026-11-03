import Foundation
import CoreEngine

/// ステージモードの n 面目の決まり（#3048）。クリアしたら次の面へ進むだけの連番で、問題は固定データを持たず
/// **ステージ番号から決めた種でその場で作る**（同じ番号なら誰でも同じ問題）。
///
/// 難しさはステージ番号で上げていく: 盤を 6×6 → 7×7 → 8×8 → 9×9 → 10×10 → 11×11 → 141 面目から 12×12（頭打ち）と広げる。
/// 盤ごとの面数は `boards` の表のとおり（広い盤ほど長く遊べる・#3223）。
/// 6〜8・10・11 の盤は各盤の前半を「段 3 までで解ける」、後半を「段 4 が要る」問題にする。
/// 段の意味は `CatPuzzleSolver`。段 5（当て推量）が要る問題は出さない。
/// 141 面目からは 10 面 1 周りで盤を回す（#3260）: 面番号の 1 の位が 3・8 は 11×11、5 は「ボーナスステージ」（6×6 と 7×7 を 1 周りごとに交互・前半の問題）、
/// それ以外は 12×12。12×12 の前半・後半は従来どおり（141 面目から数えた 10 面ごと）。
/// 10 面ごと（10・20・30…面目）は「鍵の面」（#3235）。鍵を持った猫の部屋が先に論理だけで決まる問題を採る（`CatPuzzleSolver.keyCat`）。
public struct CatPuzzleStage: Equatable, Sendable {
    /// 1 始まりのステージ番号。
    public let number: Int

    public init(_ number: Int) {
        self.number = max(1, number)
    }

    /// 鍵の面（#3235）の周期。10 面ごとに「鍵を持った猫」の面を入れる。
    static let keyPeriod = 10

    /// 鍵の面か（10・20・30…面目）。
    public var isKey: Bool { number % Self.keyPeriod == 0 }

    /// 盤ごとの面数。上から順に遊ぶ（最後の 12×12 は以降ずっと）。
    static let boards: [(size: CatPuzzleSize, stages: Int)] = [
        (.easy, 10), (.normal, 15), (.hard, 20), (.expert, 25), (.size10, 30), (.size11, 40),
    ]

    /// 12×12 の前半・後半を分ける周期（12×12 は面数が決まっていないので 10 面ごと）。
    static let lastBoardPeriod = 10

    /// 表の盤（6×6〜11×11）の面数の合計（140）。この次の面（141 面目）から 10 面 1 周りの回しになる。
    static let tableStages = boards.reduce(0) { $0 + $1.stages }

    /// 141 面目以降の 1 周りの面数。
    static let cycle = 10

    /// 141 面目以降の 1 周りの中で 11×11 になる 1 の位（前半・後半の順）。
    private static let size11Digits = [3, 8]

    /// 141 面目以降の 1 周りの中でボーナスステージになる 1 の位。
    static let bonusDigit = 5

    /// ボーナスステージか（141 面目以降で 1 の位が 5）。
    public var isBonus: Bool { number > Self.tableStages && number % Self.cycle == Self.bonusDigit }

    /// 盤の大きさと、その盤の中での 0 始まりの位置・その盤の面数（141 面目以降は周期）。
    private var placement: (size: CatPuzzleSize, index: Int, count: Int) {
        var rest = number - 1
        for board in Self.boards {
            if rest < board.stages { return (board.size, rest, board.stages) }
            rest -= board.stages
        }
        if isBonus {
            // 6×6 と 7×7 を 1 周り（10 面）ごとに交互に（145 面目が 6×6・155 面目が 7×7）。
            return ((number / Self.cycle).isMultiple(of: 2) ? .easy : .normal, 0, 1)
        }
        if let at = Self.size11Digits.firstIndex(of: number % Self.cycle) {
            return (.size11, at, Self.size11Digits.count)
        }
        return (.size12, rest % Self.lastBoardPeriod, Self.lastBoardPeriod)
    }

    /// 盤の大きさ。
    public var size: CatPuzzleSize { placement.size }

    /// その盤の前半か（面数が奇数なら後半のほうが 1 面多い）。ボーナスステージは前半（段 3 まで）の問題。
    private var isFirstHalf: Bool {
        if isBonus { return true }
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

    /// 今の位置の見せ方（#3240）。開始シートとクリアのカードに出す。
    public struct Progress: Equatable, Sendable {
        /// 盤の大きさ。
        public let size: CatPuzzleSize
        /// その盤の中での 1 始まりの位置（141 面目以降は 141 面目が 1 の通し番号）。
        public let position: Int
        /// その盤の面数。141 面目以降は以降ずっとなので nil（ゲージも出さない）。
        public let count: Int?
        /// 次の盤。141 面目以降では nil。
        public let nextSize: CatPuzzleSize?
        /// 次の盤に入るまでに、この面のあとに残る今の盤の面数（盤の最後の面で 0）。141 面目以降では nil。
        public let toNextBoard: Int?
        /// 鍵の面そのものか。
        public let isKey: Bool
        /// 鍵の面に着くまでに、この面のあとに挟まる面数（鍵の面の 1 つ前で 0。鍵の面そのものでは 0）。
        public let toKey: Int

        /// ボーナスステージそのものか（#3260）。
        public let isBonus: Bool
        /// 次のボーナスステージに着くまでに、この面のあとに挟まる面数（141 面目以降のみ。ボーナスの 1 つ前で 0。ボーナスそのものでは 0）。それ以前の面は nil。
        public let toBonus: Int?

        /// ゲージの進み具合（0〜1。盤の面数が決まっていない 12×12 は nil）。
        public var fraction: Double? { count.map { Double(position) / Double($0) } }
    }

    /// この面の位置（#3240）。
    public var progress: Progress {
        let place = placement
        let isLast = number > Self.tableStages
        var count: Int?
        var next: CatPuzzleSize?
        if !isLast, let at = Self.boards.firstIndex(where: { $0.size == place.size }) {
            count = place.count
            next = at + 1 < Self.boards.count ? Self.boards[at + 1].size : .size12
        }
        let position = isLast ? number - Self.tableStages : place.index + 1
        return Progress(
            size: place.size, position: position, count: count, nextSize: next,
            toNextBoard: count.map { $0 - position },
            isKey: isKey,
            toKey: isKey ? 0 : Self.keyPeriod - number % Self.keyPeriod - 1,
            isBonus: isBonus,
            toBonus: isLast ? (isBonus ? 0 : (Self.bonusDigit - number % Self.cycle + Self.cycle) % Self.cycle - 1) : nil
        )
    }

    /// 盤が切り替わる面か（2 面目以降で、その盤の最初の面）。「8×8 に進んだ！」の演出を出す面。
    /// 141 面目以降は盤が面ごとに替わるので、演出の対象は 141 面目（12×12 に入る）だけ（ボーナスステージの表示は別・`isBonus`）。
    public var entersNewBoard: Bool { number > 1 && number <= Self.tableStages + 1 && progress.position == 1 }

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
