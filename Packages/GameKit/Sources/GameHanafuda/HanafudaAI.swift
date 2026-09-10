import Foundation

/// こいこいの CPU（#495）。
///
/// 探索は行わない。こいこいは山札と相手の手札が伏せられた**不完全情報**のゲームで、
/// 1 手先を読んでも「次にめくる札」が支配的なため、深さを足しても強さに繋がらない。
/// 代わりに **「取った札の値打ち」を評価する関数**を 1 本置き、難易度でその使い方を変える。
///
/// - `easy`   : 取れるなら取る、取れる札が無ければ捨てる。取り方は選ばない（先頭を取る）。
/// - `normal` : 評価が最大になる手を選ぶ（自分の得だけを見る）。
/// - `hard`   : 評価に「場に残す札が相手に渡ったときの損」を引いて選ぶ。相手の役の
///              あと 1 枚を場に置き去りにしないので、赤短・青短・猪鹿蝶を通しにくい。
public enum HanafudaAI {

    /// CPU が選んだ 1 手。
    public struct Move: Equatable, Sendable {
        /// 手札から出す札。
        public let card: HanafudaCard
        /// 合わせる場札。取れないとき・選ぶ余地が無いときは nil。
        public let target: HanafudaCard?

        public init(card: HanafudaCard, target: HanafudaCard?) {
            self.card = card
            self.target = target
        }
    }

    // MARK: - 手の選択

    /// 手札から 1 手を選ぶ。手札が空のときは nil。
    public static func chooseMove<G: RandomNumberGenerator>(
        hand: [HanafudaCard],
        field: [HanafudaCard],
        captured: [HanafudaCard],
        opponentCaptured: [HanafudaCard],
        options: HanafudaOptions,
        difficulty: HanafudaDifficulty,
        using rng: inout G
    ) -> Move? {
        guard !hand.isEmpty else { return nil }

        if difficulty == .easy {
            // 取れる札があればその中から無作為に、無ければ手札から無作為に捨てる。
            let takers = hand.filter { !HanafudaRules.matches(for: $0, in: field).isEmpty }
            let pool = takers.isEmpty ? hand : takers
            let card = pool[Int(rng.next() % UInt64(pool.count))]
            return Move(card: card, target: nil)
        }

        var best: (move: Move, score: Double)?
        for card in hand {
            for target in targetChoices(for: card, field: field) {
                let score = self.score(
                    playing: card, target: target, field: field, captured: captured,
                    opponentCaptured: opponentCaptured, options: options, difficulty: difficulty
                )
                // 同点は先に見た手を残す。手札の並びは配札で決まるので、同じ局面なら常に同じ手になる。
                if best == nil || score > best!.score + 1e-9 {
                    best = (Move(card: card, target: target), score)
                }
            }
        }
        return best?.move
    }

    /// その札で選べる「合わせ先」の候補。取れないときは nil 1 個（＝捨てる手）。
    static func targetChoices(for card: HanafudaCard, field: [HanafudaCard]) -> [HanafudaCard?] {
        let candidates = HanafudaRules.matches(for: card, in: field)
        // 3 枚あるときは 4 枚まとめて取るので選ぶ余地が無い。
        if candidates.isEmpty || candidates.count >= 3 { return [nil] }
        return candidates.map { Optional($0) }
    }

    /// 1 手の評価値。
    ///
    /// `normal` は「自分の取り札がどれだけ良くなるか」、`hard` はそこから
    /// 「場に残した札が相手に渡ったときの相手の伸び」を引く。
    /// **山札めくりの結果は評価に入れない**（伏せられていて期待値を取る意味が薄いうえ、
    /// 入れると同じ局面で毎回違う手を選び、再現できないため）。
    static func score(
        playing card: HanafudaCard,
        target: HanafudaCard?,
        field: [HanafudaCard],
        captured: [HanafudaCard],
        opponentCaptured: [HanafudaCard],
        options: HanafudaOptions,
        difficulty: HanafudaDifficulty
    ) -> Double {
        let result = HanafudaRules.resolve(playing: card, field: field, chosen: target)
        let gain = evaluate(captured + result.captured, options: options)
            - evaluate(captured, options: options)
        guard difficulty == .hard else { return gain }
        return gain - opponentThreat(field: result.field, opponentCaptured: opponentCaptured, options: options)
    }

    // MARK: - 評価関数

    /// 取り札の値打ち。役の文数を主、札そのものの重みを従にする。
    ///
    /// 札の重みを混ぜるのは、役が 1 つも立っていない序盤に評価が平らになるのを避けるため。
    /// 役の文数（1 文＝ `yakuWeight`）より必ず小さくなるよう `cardWeight` を小さく取る。
    public static func evaluate(_ captured: [HanafudaCard], options: HanafudaOptions) -> Double {
        let points = HanafudaScoring.points(for: captured, options: options)
        let material = captured.reduce(0.0) { $0 + cardWeight($1) }
        return Double(points) * yakuWeight + material
    }

    /// 役 1 文ぶんの重み。札の重み（最大 1.0）より十分大きく取る。
    public static let yakuWeight = 4.0

    /// 札 1 枚の重み。役に絡みやすい札ほど高い。合計が `yakuWeight` を超えないよう 1.0 以下にする。
    public static func cardWeight(_ card: HanafudaCard) -> Double {
        if card.isSakeCup { return 0.9 }              // 盃は月見酒・花見酒とタネを兼ねる
        if HanafudaCard.inoshikachoIDs.contains(card.id) { return 0.8 }
        switch card.kind {
        case .hikari:  return 1.0
        case .tane:    return 0.5
        case .tanzaku: return card.ribbon == .plainRed ? 0.4 : 0.7  // 赤短・青短は役に直結する
        case .kasu:    return 0.15
        }
    }

    /// 場に残した札が相手に渡ったときの相手の伸び（`hard` だけが使う）。
    ///
    /// 場の札を 1 枚ずつ「相手が取ったら」と仮定して評価差を測り、その最大値を返す。
    /// 合計ではなく最大にするのは、相手が 1 手で取れるのは 1 枚（同月まとめ取りを除く）だからで、
    /// 合計にすると場が広いだけで過剰に怖がる。
    static func opponentThreat(
        field: [HanafudaCard], opponentCaptured: [HanafudaCard], options: HanafudaOptions
    ) -> Double {
        let base = evaluate(opponentCaptured, options: options)
        var worst = 0.0
        for card in field {
            let after = evaluate(opponentCaptured + [card], options: options)
            worst = max(worst, after - base)
        }
        return worst * threatDiscount
    }

    /// 相手の伸びをどれだけ重く見るか。1.0 にすると守りに寄りすぎて自分の役が育たない。
    static let threatDiscount = 0.6

    // MARK: - こいこいの判断

    /// 役ができたときに続けるか（true = こいこい）。
    ///
    /// - `easy`   : 続けない（すぐあがる）。初心者の相手として点が伸びすぎない。
    /// - `normal` : 得点が低く、まだ札が十分残っているときだけ続ける。
    /// - `hard`   : さらに「相手の取り札が育っていたら降りる」を加える。
    ///
    /// - Parameters:
    ///   - myPoints: いまの自分の文数。
    ///   - opponentPoints: 相手の取り札から見える文数（伏せ札は含まない）。
    ///   - handCount: この手番のあとに自分の手札に残る枚数。
    ///   - deckCount: 山札の残り枚数。
    public static func shouldKoiKoi(
        myPoints: Int,
        opponentPoints: Int,
        handCount: Int,
        deckCount: Int,
        difficulty: HanafudaDifficulty
    ) -> Bool {
        // 宣言できない局面ではそもそも呼ばれないが、単体で使われても壊れないようにしておく。
        guard HanafudaRules.canDeclareKoiKoi(handCountAfterTurn: handCount, deckCount: deckCount) else {
            return false
        }
        switch difficulty {
        case .easy:
            return false
        case .normal:
            return myPoints < koiKoiCeiling && handCount >= minimumHandToContinue
        case .hard:
            guard myPoints < koiKoiCeiling, handCount >= minimumHandToContinue else { return false }
            // 相手に役が立ちかけている（＝こいこい返しで倍にされる）なら伸ばしにいかない。
            return opponentPoints == 0
        }
    }

    /// これ以上は伸ばさずあがる文数。7 文で 2 倍になるので、そこに乗ったら確定させる。
    static let koiKoiCeiling = HanafudaScoring.sevenMonThreshold
    /// 続けるのに最低限ほしい手札の残り。
    static let minimumHandToContinue = 2
}
