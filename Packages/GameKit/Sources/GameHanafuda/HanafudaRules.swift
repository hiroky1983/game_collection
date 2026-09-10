import Foundation

/// 種から決まる擬似乱数（SplitMix64）。配札とCPUの選択を再現可能にするために使う。
///
/// 実装は囲碁の `GoRandom` と同じ式。共有せずに持つのは、`GameHanafuda` が `Core` 以外に
/// 依存しない構成（`Package.swift` の方針）を崩さないため。
public struct HanafudaRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 配った直後の状態。
public struct HanafudaDeal: Equatable, Sendable {
    /// 親の手札 8 枚。
    public var dealerHand: [HanafudaCard]
    /// 子の手札 8 枚。
    public var opponentHand: [HanafudaCard]
    /// 場札 8 枚。
    public var field: [HanafudaCard]
    /// 山札 24 枚（先頭からめくる）。
    public var deck: [HanafudaCard]

    public init(
        dealerHand: [HanafudaCard],
        opponentHand: [HanafudaCard],
        field: [HanafudaCard],
        deck: [HanafudaCard]
    ) {
        self.dealerHand = dealerHand
        self.opponentHand = opponentHand
        self.field = field
        self.deck = deck
    }
}

/// 1 枚を出したときに場で起きること。
public enum HanafudaPlayOutcome: Equatable, Sendable {
    /// 同月の札が場に無いので、出した札はそのまま場に残る。
    case discard
    /// 場の 1 枚と合わせて 2 枚取る。
    case capture(field: HanafudaCard)
    /// 場に同月が 3 枚あるので 4 枚まとめて取る。
    case captureAll(field: [HanafudaCard])
    /// 場に同月が 2 枚あり、どちらを取るか選ぶ必要がある。
    case mustChoose(candidates: [HanafudaCard])
}

/// こいこいのルール（純粋関数のみ）。
///
/// 進行・永続化・演出は `HanafudaModel` が持ち、ここは**盤の上で何が起きるか**だけを受け持つ。
public enum HanafudaRules {

    /// 手札の枚数。
    public static let handSize = 8
    /// 初期の場札の枚数。
    public static let fieldSize = 8

    // MARK: - 配札

    /// 48 枚を配る。
    ///
    /// **場に同月が 4 枚出たら配り直す**（標準ルール。その月は誰も取り合いようがなく、
    /// 出した瞬間に 4 枚がまとめて動くため局として成立しない）。配り直しは有限回で必ず終わる
    /// ので、安全弁として上限を設けたうえで、**上限に達したら場を決定的に直して**不変条件を保つ。
    public static func deal<G: RandomNumberGenerator>(using rng: inout G) -> HanafudaDeal {
        for _ in 0..<maxRedeals {
            let deal = dealOnce(using: &rng)
            if !hasFourOfAMonth(deal.field) { return deal }
        }
        return repairingField(dealOnce(using: &rng))
    }

    /// 配り直しの上限。48 枚のシャッフルで場に同月 4 枚が出る確率はごく低いので、
    /// ここに到達することは実質無い（テストは `hasFourOfAMonth` を直接突く）。
    static let maxRedeals = 20

    static func dealOnce<G: RandomNumberGenerator>(using rng: inout G) -> HanafudaDeal {
        var deck = HanafudaCard.fullDeck
        deck.shuffle(using: &rng)
        // 実物と同じ順（親→子→場を 2 巡）で配る必要はない。取り出す位置が違うだけで
        // シャッフル済みの山からの分割は等価なので、読みやすい前から順の分割にする。
        let dealerHand = Array(deck[0..<handSize])
        let opponentHand = Array(deck[handSize..<(handSize * 2)])
        let field = Array(deck[(handSize * 2)..<(handSize * 2 + fieldSize)])
        let rest = Array(deck[(handSize * 2 + fieldSize)...])
        return HanafudaDeal(dealerHand: dealerHand, opponentHand: opponentHand, field: field, deck: rest)
    }

    /// 場に同じ月が 4 枚あるか。
    public static func hasFourOfAMonth(_ field: [HanafudaCard]) -> Bool {
        var counts: [Int: Int] = [:]
        for card in field { counts[card.month, default: 0] += 1 }
        return counts.values.contains { $0 >= 4 }
    }

    /// 場の同月 4 枚を、山札の札と入れ替えて崩す（配り直しの上限に達したときだけ使う）。
    ///
    /// 入れ替え先は「その月が場にまだ 2 枚以下」の山札の札なので、1 回の交換で
    /// 4 枚の月は 3 枚に減り、受け入れた側も 3 枚を超えない。場は 8 枚・山は 24 枚あり
    /// 12 か月のうち 4 枚が揃う月は最大 2 つなので、交換先は必ず見つかる。
    static func repairingField(_ deal: HanafudaDeal) -> HanafudaDeal {
        var field = deal.field
        var deck = deal.deck
        while let month = monthWithFourCards(in: field) {
            guard let fieldIndex = field.firstIndex(where: { $0.month == month }),
                  let deckIndex = deck.firstIndex(where: { card in
                      field.filter { $0.month == card.month }.count <= 2
                  })
            else { break }
            let removed = field[fieldIndex]
            field[fieldIndex] = deck[deckIndex]
            deck[deckIndex] = removed
        }
        return HanafudaDeal(
            dealerHand: deal.dealerHand, opponentHand: deal.opponentHand, field: field, deck: deck
        )
    }

    /// 場に 4 枚ある月（無ければ nil）。
    static func monthWithFourCards(in field: [HanafudaCard]) -> Int? {
        var counts: [Int: Int] = [:]
        for card in field { counts[card.month, default: 0] += 1 }
        return counts.first { $0.value >= 4 }?.key
    }

    // MARK: - 場合わせ

    /// 場札のうち、その札と同じ月のもの。
    public static func matches(for card: HanafudaCard, in field: [HanafudaCard]) -> [HanafudaCard] {
        field.filter { $0.month == card.month }
    }

    /// 1 枚を場に出したときの結果。
    ///
    /// 場の同月が 0 枚なら場に置き、1 枚なら合わせて取り、3 枚なら 4 枚まとめて取る。
    /// 2 枚のときだけ**どちらを取るか選ぶ**（`mustChoose`）。
    public static func outcome(playing card: HanafudaCard, field: [HanafudaCard]) -> HanafudaPlayOutcome {
        let candidates = matches(for: card, in: field)
        switch candidates.count {
        case 0:  return .discard
        case 1:  return .capture(field: candidates[0])
        case 2:  return .mustChoose(candidates: candidates)
        default: return .captureAll(field: candidates)
        }
    }

    /// 選択が要らない結果か（CPU と山札めくりはここで自動的に確定する）。
    public static func isAutomatic(_ outcome: HanafudaPlayOutcome) -> Bool {
        if case .mustChoose = outcome { return false }
        return true
    }

    /// 出した札と選んだ場札から「取る札」と「取ったあとの場」を求める。
    ///
    /// - Parameter chosen: `mustChoose` のときに選んだ場札。それ以外では無視される。
    /// - Returns: 取り札に加わる札（出した札を含む）と、更新後の場。取れないときは
    ///   取り札が空で、場に出した札が加わる。
    public static func resolve(
        playing card: HanafudaCard,
        field: [HanafudaCard],
        chosen: HanafudaCard? = nil
    ) -> (captured: [HanafudaCard], field: [HanafudaCard]) {
        switch outcome(playing: card, field: field) {
        case .discard:
            return ([], field + [card])
        case .capture(let target):
            return ([card, target], remove([target], from: field))
        case .captureAll(let targets):
            return ([card] + targets, remove(targets, from: field))
        case .mustChoose(let candidates):
            // 選択が渡されなかったら先頭を取る（CPU・自動処理の既定）。人間の手番では
            // View が選ばせてから呼ぶので、ここに落ちるのは意図的な自動選択のときだけ。
            let target = chosen.flatMap { pick in candidates.first { $0 == pick } } ?? candidates[0]
            return ([card, target], remove([target], from: field))
        }
    }

    static func remove(_ cards: [HanafudaCard], from field: [HanafudaCard]) -> [HanafudaCard] {
        let ids = Set(cards.map(\.id))
        return field.filter { !ids.contains($0.id) }
    }

    // MARK: - あがり判定

    /// こいこいを宣言できるか。
    ///
    /// **手札が尽きる手番では宣言できない**（続けたくても打つ札が無く、相手だけが打てる
    /// 状態になるため）。標準ルールと同じ扱い。
    public static func canDeclareKoiKoi(handCountAfterTurn: Int, deckCount: Int) -> Bool {
        handCountAfterTurn > 0 && deckCount > 0
    }

    /// こいこいの後に「あがる」ことを選べるか。
    ///
    /// 宣言した時点の文数（`claimedPoints`）を**超えて**いなければ止まれない。同じ役のまま
    /// 止まれてしまうと、こいこいを宣言する意味が消える。
    public static func canStop(currentPoints: Int, claimedPoints: Int) -> Bool {
        currentPoints > claimedPoints
    }
}
