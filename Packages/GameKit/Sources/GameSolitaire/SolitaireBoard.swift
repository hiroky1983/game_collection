import Foundation

/// 場札の1列。伏せ札（下）と表向き札（上）を分けて持つ。
/// `faceUp` は**下から上の順**（`last` が一番上）。
public struct SolitairePile: Equatable, Sendable, Codable {
    public var faceDown: [SolitaireCard]
    public var faceUp: [SolitaireCard]

    public init(faceDown: [SolitaireCard] = [], faceUp: [SolitaireCard] = []) {
        self.faceDown = faceDown
        self.faceUp = faceUp
    }

    public var isEmpty: Bool { faceDown.isEmpty && faceUp.isEmpty }
    public var top: SolitaireCard? { faceUp.last }
}

/// プレイヤーが選べる1手。UI・ソルバー・中断復元がすべてこの型を通す。
public enum SolitaireMove: Equatable, Sendable, Codable, Hashable {
    /// 山札を1枚めくる。山札が空なら捨て札を裏返して山札に戻す（循環は無制限）。
    case draw
    case wasteToFoundation
    case wasteToTableau(pile: Int)
    case tableauToFoundation(pile: Int)
    /// `cardIndex` は移動元の `faceUp` の添字（そこから上を丸ごと動かす）。
    case tableauToTableau(from: Int, cardIndex: Int, to: Int)
    /// 救済のジョーカー（中継札）を場札の列の上に置く（#397）。
    case placeJoker(pile: Int)
}

/// クロンダイクの盤面と規則を、乱数も UI も持たない値型として閉じ込めた層。
///
/// 採用ルール（#397）: 場札7列・組札4・**山札は1枚めくり**・**山札の循環は無制限**・空列は K のみ。
/// ジョーカー（中継札）の規則もここに集約する。Model は進行と永続化だけを持ち、
/// 合法手の判断はすべてこの型に問い合わせる。
public struct SolitaireBoard: Equatable, Sendable, Codable {
    public static let pileCount = 7

    public var tableau: [SolitairePile]
    /// 添字は `SolitaireSuit.rawValue`。値は積み上げた最大ランク（0 = 空）。
    public var foundations: [Int]
    /// 山札。`last` が次にめくる1枚（一番上）。
    public var stock: [SolitaireCard]
    /// 捨て札。`last` が表を向いている1枚。
    public var waste: [SolitaireCard]
    /// 未使用のジョーカーを所持しているか（所持上限1枚・#397）。
    public var jokerAvailable: Bool

    public init(
        tableau: [SolitairePile],
        foundations: [Int] = [0, 0, 0, 0],
        stock: [SolitaireCard] = [],
        waste: [SolitaireCard] = [],
        jokerAvailable: Bool = false
    ) {
        self.tableau = tableau
        self.foundations = foundations
        self.stock = stock
        self.waste = waste
        self.jokerAvailable = jokerAvailable
        normalize()
    }

    // MARK: - 盤面の整え（自動で起きること）

    /// 手を適用したあとに必ず起きる後始末。
    ///
    /// 1. 表向きが無くなった列は伏せ札を1枚めくる
    /// 2. **受け取り済みのジョーカーが露出したら消滅させる**（#397 ルール4）
    ///
    /// 2 で下の札が出てくると 1 の条件が変わりうるので、変化が無くなるまで繰り返す。
    public mutating func normalize() {
        for index in tableau.indices {
            while true {
                if tableau[index].faceUp.isEmpty, !tableau[index].faceDown.isEmpty {
                    tableau[index].faceUp.append(tableau[index].faceDown.removeLast())
                    continue
                }
                if let top = tableau[index].faceUp.last, top.isJoker, top.hasReceived {
                    tableau[index].faceUp.removeLast()
                    continue
                }
                break
            }
        }
    }

    // MARK: - 判定

    public var isWon: Bool { foundations.allSatisfy { $0 == 13 } }

    /// 組札へ送れるか。ジョーカーは組札に置けない（#397 ルール1）。
    public func canSendToFoundation(_ card: SolitaireCard) -> Bool {
        guard !card.isJoker, let suit = card.suit else { return false }
        return foundations[suit.rawValue] == card.rank - 1
    }

    /// `faceUp[index...]` が場札の並び（降順・交互色）として丸ごと動かせるか。
    /// **ジョーカーを含む並びは動かせない**（置いたジョーカーは動かない・#397 ルール3）。
    public func isMovableRun(pile: Int, from index: Int) -> Bool {
        let faceUp = tableau[pile].faceUp
        guard faceUp.indices.contains(index) else { return false }
        let run = faceUp[index...]
        if run.contains(where: \.isJoker) { return false }
        for (upper, lower) in zip(run, run.dropFirst()) {
            if lower.rank != upper.rank - 1 || lower.isRed == upper.isRed { return false }
        }
        return true
    }

    /// `run`（下端が `first`）を `pile` の上に置けるか。
    public func canPlace(_ run: [SolitaireCard], onPile pile: Int) -> Bool {
        guard let bottom = run.first, !bottom.isJoker else { return false }
        guard let top = tableau[pile].top else {
            // 空列は K のみ（#397 吟味1 の確定事項。ジョーカーで迂回させない）
            return bottom.rank == 13
        }
        if top.isJoker {
            // 中継札の上には**任意のカードを1枚だけ**置ける（#397 ルール2）。
            return !top.hasReceived && run.count == 1
        }
        return bottom.rank == top.rank - 1 && bottom.isRed != top.isRed
    }

    /// ジョーカーを置けるか。所持していること・空列でないこと・上がジョーカーでないこと。
    public func canPlaceJoker(onPile pile: Int) -> Bool {
        guard jokerAvailable, let top = tableau[pile].top else { return false }
        return !top.isJoker
    }

    public func isLegal(_ move: SolitaireMove) -> Bool {
        switch move {
        case .draw:
            return !stock.isEmpty || !waste.isEmpty
        case .wasteToFoundation:
            guard let card = waste.last else { return false }
            return canSendToFoundation(card)
        case .wasteToTableau(let pile):
            guard tableau.indices.contains(pile), let card = waste.last else { return false }
            return canPlace([card], onPile: pile)
        case .tableauToFoundation(let pile):
            guard tableau.indices.contains(pile), let card = tableau[pile].top else { return false }
            return canSendToFoundation(card)
        case .tableauToTableau(let from, let cardIndex, let to):
            guard tableau.indices.contains(from), tableau.indices.contains(to), from != to else { return false }
            guard isMovableRun(pile: from, from: cardIndex) else { return false }
            return canPlace(Array(tableau[from].faceUp[cardIndex...]), onPile: to)
        case .placeJoker(let pile):
            guard tableau.indices.contains(pile) else { return false }
            return canPlaceJoker(onPile: pile)
        }
    }

    // MARK: - 適用

    /// 合法手を適用する。非合法な手は無視して false を返す（呼び出し側で握り潰さないよう戻り値で伝える）。
    @discardableResult
    public mutating func apply(_ move: SolitaireMove) -> Bool {
        guard isLegal(move) else { return false }
        switch move {
        case .draw:
            if stock.isEmpty {
                stock = waste.reversed()
                waste.removeAll()
            }
            waste.append(stock.removeLast())
        case .wasteToFoundation:
            let card = waste.removeLast()
            foundations[card.suit!.rawValue] = card.rank
        case .wasteToTableau(let pile):
            let card = waste.removeLast()
            place([card], onPile: pile)
        case .tableauToFoundation(let pile):
            let card = tableau[pile].faceUp.removeLast()
            foundations[card.suit!.rawValue] = card.rank
        case .tableauToTableau(let from, let cardIndex, let to):
            let run = Array(tableau[from].faceUp[cardIndex...])
            tableau[from].faceUp.removeSubrange(cardIndex...)
            place(run, onPile: to)
        case .placeJoker(let pile):
            jokerAvailable = false
            tableau[pile].faceUp.append(.joker)
        }
        normalize()
        return true
    }

    /// 実際に積む。中継札の上に置いた1枚は、そのジョーカーを「受け取り済み」にする。
    private mutating func place(_ run: [SolitaireCard], onPile pile: Int) {
        if let topIndex = tableau[pile].faceUp.indices.last, tableau[pile].faceUp[topIndex].isJoker {
            tableau[pile].faceUp[topIndex].hasReceived = true
        }
        tableau[pile].faceUp.append(contentsOf: run)
    }

    // MARK: - めくり演出の材料

    /// `before` では伏せていて `after` で表に出た札の id（#421 のめくり演出）。
    ///
    /// 表に返るのは `normalize()` の副作用なので、手の種類からは決まらない（同じ
    /// `tableauToTableau` でも返る局面と返らない局面がある）。盤面どうしの差分で見るのが唯一確実で、
    /// **手を適用する側の経路を増やさずに済む**。ジョーカーは伏せ札から出てこないので対象外になる。
    public static func revealedCardIDs(before: SolitaireBoard, after: SolitaireBoard) -> Set<Int> {
        var revealed: Set<Int> = []
        for pile in after.tableau.indices where before.tableau.indices.contains(pile) {
            let wasHidden = Set(before.tableau[pile].faceDown.map(\.id))
            guard !wasHidden.isEmpty else { continue }
            let wasShown = Set(before.tableau[pile].faceUp.map(\.id))
            for card in after.tableau[pile].faceUp
            where wasHidden.contains(card.id) && !wasShown.contains(card.id) {
                revealed.insert(card.id)
            }
        }
        return revealed
    }

    // MARK: - 山札の巡回

    /// 山札を循環させて到達できる札を、必要なめくり回数とともに列挙する。
    ///
    /// 循環が無制限なので、山札 + 捨て札のすべてが1周で表に出る。
    /// ソルバーはこれを使って「n 回めくってからその札を使う」を1手として扱い、
    /// めくるだけの手で探索が深くなるのを防ぐ。
    public func reachableStockCards() -> [(card: SolitaireCard, draws: Int)] {
        var result: [(SolitaireCard, Int)] = []
        if let top = waste.last { result.append((top, 0)) }
        for (offset, card) in stock.reversed().enumerated() {
            result.append((card, offset + 1))
        }
        // 1周めの最後で捨て札を戻すと、いま捨て札の一番下にある札から順に出てくる。
        // 捨て札の一番上（`waste.last`）は draws = 0 で既に数えているので除く。
        if waste.count > 1 {
            for (offset, card) in waste.dropLast().enumerated() {
                result.append((card, stock.count + offset + 1))
            }
        }
        return result
    }

    // MARK: - 詰み検知

    /// 山札を循環させるほかに有効な手が残っていない状態（#397 の詰み検知）。
    ///
    /// **ジョーカーの使用は判定から除外する**（#397 吟味3。所持していても「詰み」として警告し、
    /// そこで使用を提案する）。
    public var isDeadEnd: Bool {
        !isWon && !hasProgressMove
    }

    /// 盤面を前に進める手が1つでもあるか（めくるだけ・ジョーカーは数えない）。
    private var hasProgressMove: Bool {
        for pile in tableau.indices {
            if let card = tableau[pile].top, canSendToFoundation(card) { return true }
            for index in tableau[pile].faceUp.indices where isMovableRun(pile: pile, from: index) {
                let run = Array(tableau[pile].faceUp[index...])
                for target in tableau.indices where target != pile {
                    guard canPlace(run, onPile: target) else { continue }
                    // 伏せ札も無く、移動先も空列なら「空列の入れ替え」だけで盤面は進まない。
                    if index == 0, tableau[pile].faceDown.isEmpty, tableau[target].isEmpty { continue }
                    return true
                }
            }
        }
        for (card, _) in reachableStockCards() {
            if canSendToFoundation(card) { return true }
            for pile in tableau.indices where canPlace([card], onPile: pile) { return true }
        }
        return false
    }

    // MARK: - 探索用のキー

    /// 同一局面の判定に使う正準表現。伏せ札は配札で固定なので枚数だけで足りる。
    public var stateKey: Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(96)
        bytes.append(contentsOf: foundations.map(UInt8.init))
        for pile in tableau {
            bytes.append(UInt8(pile.faceDown.count))
            bytes.append(UInt8(pile.faceUp.count))
            for card in pile.faceUp {
                bytes.append(card.isJoker ? (card.hasReceived ? 54 : 53) : UInt8(card.id))
            }
        }
        bytes.append(0xFF)
        bytes.append(contentsOf: stock.map { UInt8($0.id) })
        bytes.append(0xFE)
        bytes.append(contentsOf: waste.map { UInt8($0.id) })
        bytes.append(jokerAvailable ? 1 : 0)
        return Data(bytes)
    }
}
