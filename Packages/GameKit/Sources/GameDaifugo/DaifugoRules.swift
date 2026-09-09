import Foundation

/// 交換で動いた札（リザルト表示と検証のために誰から誰へ何を渡したかを残す）。
public struct DaifugoTransfer: Codable, Sendable, Equatable {
    public let from: Int
    public let to: Int
    public let cards: [DaifugoCard]

    public init(from: Int, to: Int, cards: [DaifugoCard]) {
        self.from = from
        self.to = to
        self.cards = cards
    }
}

/// 手札1枚のヒント表示の状態（#190）。
public enum DaifugoCardHint: Equatable, Sendable {
    /// ヒント無し（設定オフ・相手の手番・手札すべてが出せる場合）。
    case none
    /// いま出せる札。
    case playable
    /// いま出せない札。
    case unplayable
}

/// 手札全体のヒント（#190）。出せる札と出せない札を分けて持つ。
public struct DaifugoHandHint: Equatable, Sendable {
    public let playable: Set<Int>
    public let unplayable: Set<Int>

    public init(playable: Set<Int>, unplayable: Set<Int>) {
        self.playable = playable
        self.unplayable = unplayable
    }

    public func state(for cardID: Int) -> DaifugoCardHint {
        if playable.contains(cardID) { return .playable }
        if unplayable.contains(cardID) { return .unplayable }
        return .none
    }
}

/// 大富豪のルールを**乱数も状態も持たない純粋関数**として閉じ込めた層。
///
/// Model（`DaifugoModel`）は進行と永続化だけを持ち、勝ち負けの判断はここに集約する。
/// ユニットテストはこの層に対して書くので、UI・CPU の都合でルールが揺れない。
///
/// v1 の採用ルール（Issue #89）: 革命 / 8切り / 反則上がり。縛り・階段・都落ちは入れない。
public enum DaifugoRules {
    /// ジョーカーの `rank`。通常の 1〜13 と衝突しない値を使う。
    public static let jokerRank = 0
    /// 階級の呼び名（`ranking` の順に対応）。
    public static let titles = ["大富豪", "富豪", "貧民", "大貧民"]
    /// 革命が起きる同ランクの枚数。
    public static let revolutionCount = 4

    // MARK: - 強さ

    /// 革命を考えない素の強さ。3 が最弱（0）→ K（10）→ A（11）→ 2（12）、ジョーカーは別格。
    public static func baseStrength(rank: Int) -> Int {
        switch rank {
        case jokerRank: return 20
        case 1:  return 11   // A
        case 2:  return 12
        default: return rank - 3   // 3...13 → 0...10
        }
    }

    /// 現在の場の強さ。革命中は 3 が最強・2 が最弱に反転する。
    /// **ジョーカーは革命中も最強**のまま（一般的なルールに合わせる）。
    public static func strength(rank: Int, isRevolution: Bool) -> Int {
        guard rank != jokerRank else { return baseStrength(rank: jokerRank) }
        let base = baseStrength(rank: rank)
        return isRevolution ? 12 - base : base
    }

    /// 出された組の「ランク」。ジョーカーはワイルドとして扱い、他の札のランクに合わせる。
    /// - Returns: 同ランクに揃っていればそのランク、ジョーカーのみなら `jokerRank`、
    ///   ランクが混在していれば nil（＝出せない組み合わせ）。
    public static func playRank(_ cards: [DaifugoCard]) -> Int? {
        guard !cards.isEmpty else { return nil }
        let ranks = Set(cards.filter { !$0.isJoker }.map(\.rank))
        if ranks.isEmpty { return jokerRank }
        guard ranks.count == 1, let rank = ranks.first else { return nil }
        return rank
    }

    /// 出された組の強さ。組として成立していなければ nil。
    public static func playStrength(_ cards: [DaifugoCard], isRevolution: Bool) -> Int? {
        guard let rank = playRank(cards) else { return nil }
        return strength(rank: rank, isRevolution: isRevolution)
    }

    // MARK: - 合法判定

    /// `cards` を今の場に出せるか。場が空なら組として成立していれば出せる。
    public static func isValidPlay(_ cards: [DaifugoCard], field: [DaifugoCard], isRevolution: Bool) -> Bool {
        guard let played = playStrength(cards, isRevolution: isRevolution) else { return false }
        guard !field.isEmpty else { return true }
        guard cards.count == field.count else { return false }
        guard let current = playStrength(field, isRevolution: isRevolution) else { return false }
        return played > current
    }

    /// 革命（同ランク4枚以上）か。
    public static func triggersRevolution(_ cards: [DaifugoCard]) -> Bool {
        playRank(cards) != nil && cards.count >= revolutionCount
    }

    /// 8切り（8 を含む組は場を流し、出した人がそのまま次の親になる）か。
    public static func clearsField(_ cards: [DaifugoCard]) -> Bool {
        cards.contains { $0.rank == 8 }
    }

    /// 反則上がり（最後の1手が 2・ジョーカー・8 を含む）か。
    /// v1 では「出せない」ではなく「上がっても最下位に落ちる」として扱う
    /// （2 しか残っていないと永久に上がれなくなるため）。
    public static func isFoulFinish(_ cards: [DaifugoCard]) -> Bool {
        cards.contains { $0.isJoker || $0.rank == 2 || $0.rank == 8 }
    }

    // MARK: - ヒント（#190）

    /// いま出せる手札の ID。**その札を含む合法手が1つでもあれば「出せる」**として数える。
    ///
    /// `legalPlays` は CPU 用に「同ランクは弱い順に必要枚数だけ」しか列挙しないため、
    /// 4枚組のうち2枚だけ出す手のように**同じ強さの別解**が落ちる。札単位の可否を問う
    /// ヒント表示でそれを使うと「出せるのに暗く落ちる」札が出るので、ここで別に数える。
    public static func playableCardIDs(
        hand: [DaifugoCard],
        field: [DaifugoCard],
        isRevolution: Bool
    ) -> Set<Int> {
        guard !hand.isEmpty else { return [] }
        // 場が流れていれば1枚から好きな組を出せる = 手札すべてが出せる。
        guard !field.isEmpty else { return Set(hand.map(\.id)) }
        guard let fieldStrength = playStrength(field, isRevolution: isRevolution) else { return [] }

        let jokers = hand.filter(\.isJoker)
        var groups: [Int: [DaifugoCard]] = [:]
        for card in hand where !card.isJoker { groups[card.rank, default: []].append(card) }

        let count = field.count
        var ids: Set<Int> = []
        var jokerUsable = false
        for (rank, group) in groups {
            guard strength(rank: rank, isRevolution: isRevolution) > fieldStrength else { continue }
            // 足りない枚数はジョーカーで埋められる。
            guard group.count + jokers.count >= count else { continue }
            ids.formUnion(group.map(\.id))
            // このランクで組が作れるなら、実札を1枚ジョーカーに置き換えた手も必ず作れる。
            if !jokers.isEmpty { jokerUsable = true }
        }
        // ジョーカーだけで出す（場がジョーカーの組でない限り最強なので通る）。
        if jokers.count >= count, strength(rank: jokerRank, isRevolution: isRevolution) > fieldStrength {
            jokerUsable = true
        }
        if jokerUsable { ids.formUnion(jokers.map(\.id)) }
        return ids
    }

    /// 選択中の組を出せない理由。出せる場合と未選択のときは nil。
    ///
    /// 画面に1行で出すため短く保つ。判定の順序は `isValidPlay` と同じ
    /// （組として不成立 → 枚数違い → 強さ不足）にして、表示と可否がずれないようにする。
    public static func rejectionReason(
        _ cards: [DaifugoCard],
        field: [DaifugoCard],
        isRevolution: Bool
    ) -> String? {
        guard !cards.isEmpty else { return nil }
        guard let played = playStrength(cards, isRevolution: isRevolution) else {
            return "数字がそろっていません（ジョーカーは他の数字の代わりに使えます）"
        }
        guard !field.isEmpty else { return nil }
        guard cards.count == field.count else {
            return "場は\(field.count)枚です。\(cards.count)枚では出せません"
        }
        guard let current = playStrength(field, isRevolution: isRevolution), played > current else {
            // 場がジョーカーだけのときは非ジョーカーが無いので、そのまま JOKER と呼ぶ。
            let label = field.first { !$0.isJoker }?.rankLabel ?? "JOKER"
            return isRevolution
                ? "革命中です。場の \(label) より弱い数字が必要です"
                : "場の \(label) より強い数字が必要です"
        }
        return nil
    }

    // MARK: - 手の列挙と CPU の選択

    /// 今の場に出せる手の候補。ジョーカーは**必要な枚数だけ**使う版のみを挙げる
    /// （同じ強さでジョーカーを余分に使う手は CPU にとって常に損なので列挙しない）。
    public static func legalPlays(
        hand: [DaifugoCard],
        field: [DaifugoCard],
        isRevolution: Bool
    ) -> [[DaifugoCard]] {
        let jokers = hand.filter(\.isJoker).sorted { $0.id < $1.id }
        var groups: [Int: [DaifugoCard]] = [:]
        for card in hand where !card.isJoker { groups[card.rank, default: []].append(card) }

        let counts: [Int]
        if field.isEmpty {
            let maxCount = max(groups.values.map(\.count).max() ?? 0, 0) + jokers.count
            counts = maxCount >= 1 ? Array(1...maxCount) : []
        } else {
            counts = [field.count]
        }

        var plays: [[DaifugoCard]] = []
        for count in counts {
            for rank in groups.keys.sorted() {
                let group = groups[rank]!.sorted { $0.sortKey < $1.sortKey }
                let jokersNeeded = max(0, count - group.count)
                guard jokersNeeded <= jokers.count else { continue }
                let play = Array(group.prefix(count - jokersNeeded)) + Array(jokers.prefix(jokersNeeded))
                guard play.count == count else { continue }
                if isValidPlay(play, field: field, isRevolution: isRevolution) { plays.append(play) }
            }
            // ジョーカーだけで出す（場が空のときの最強手、または最後の1枚）。
            if count <= jokers.count {
                let play = Array(jokers.prefix(count))
                if isValidPlay(play, field: field, isRevolution: isRevolution) { plays.append(play) }
            }
        }
        return plays
    }

    /// CPU の選択（貪欲法）: **出せる最弱の手**を選ぶ。強さ調整は Issue #89 のスコープ外。
    ///
    /// 同じ強さならジョーカーを使わない手を選ぶ。枚数は場の状況で向きが変わる:
    /// 場に追随するときは枚数が場と一致するので比較に効かず、**親番（場が空）では枚数の多い手**を選ぶ。
    /// 反則上がりになる手は、他に選べる手があるときだけ避ける（避けようがなければそのまま出す）。
    public static func greedyPlay(
        hand: [DaifugoCard],
        field: [DaifugoCard],
        isRevolution: Bool
    ) -> [DaifugoCard]? {
        let plays = legalPlays(hand: hand, field: field, isRevolution: isRevolution)
        guard !plays.isEmpty else { return nil }

        func isFoul(_ play: [DaifugoCard]) -> Bool {
            play.count == hand.count && isFoulFinish(play)
        }
        // 親番だけ枚数を降順にする。場に追随するときは合法手の枚数が場と一致するのでこの項は効かないが、
        // 場が空のときは同じランクを 1 枚だけ出す手が常に最小になり、CPU がペアも革命も一度も出さなかった（#375）。
        let leadsField = field.isEmpty
        func rankKey(_ play: [DaifugoCard]) -> (Int, Int, Int, Int, Int) {
            (
                isFoul(play) ? 1 : 0,
                playStrength(play, isRevolution: isRevolution) ?? Int.max,
                play.filter(\.isJoker).count,
                leadsField ? -play.count : play.count,
                play.first?.id ?? 0
            )
        }
        return plays.min { rankKey($0) < rankKey($1) }
    }

    // MARK: - 順位と階級

    /// 上がり順・反則上がり・投了から最終順位を決める。反則上がりは順位を失い末尾へ回り、
    /// 投了（#194）は最後まで打っていないので反則上がりよりさらに下に置く。
    /// - Parameters:
    ///   - finishOrder: 手札が尽きた順のプレイヤー番号。
    ///   - fouls: 反則上がりしたプレイヤー番号。
    ///   - resigned: 投了したプレイヤー番号。反則上がりと重なっても投了の扱いを優先する。
    /// - Returns: 1位から順のプレイヤー番号。
    public static func ranking(finishOrder: [Int], fouls: Set<Int>, resigned: Set<Int> = []) -> [Int] {
        finishOrder.filter { !fouls.contains($0) && !resigned.contains($0) }
            + finishOrder.filter { fouls.contains($0) && !resigned.contains($0) }
            + finishOrder.filter { resigned.contains($0) }
    }

    /// 順位（0 始まり）に対応する階級名。4人以外でも落ちないよう範囲外は空文字にする。
    public static func title(forPlace place: Int) -> String {
        titles.indices.contains(place) ? titles[place] : ""
    }

    // MARK: - カード交換

    /// 次のゲーム開始時のカード交換（大富豪⇔大貧民2枚 / 富豪⇔貧民1枚）。
    ///
    /// 上位は**最弱**の札を、下位は**最強**の札を差し出す。どちらの選択も交換前の手札から
    /// 同時に決めるので、渡した札がそのまま返る（渡した札を再度選ぶ）ことは起きない。
    /// - Parameters:
    ///   - hands: プレイヤー番号順の手札。
    ///   - ranking: 1位から順のプレイヤー番号。
    /// - Returns: 交換後の手札と、実際に動いた札の一覧。
    public static func applyExchange(
        hands: [[DaifugoCard]],
        ranking: [Int]
    ) -> (hands: [[DaifugoCard]], transfers: [DaifugoTransfer]) {
        guard ranking.count == 4 else { return (hands, []) }
        // (上位, 下位, 枚数)
        let pairs = [(ranking[0], ranking[3], 2), (ranking[1], ranking[2], 1)]

        var transfers: [DaifugoTransfer] = []
        var result = hands
        for (upper, lower, count) in pairs {
            guard hands.indices.contains(upper), hands.indices.contains(lower) else { continue }
            let sortedUpper = hands[upper].sorted { $0.sortKey < $1.sortKey }
            let sortedLower = hands[lower].sorted { $0.sortKey < $1.sortKey }
            let fromUpper = Array(sortedUpper.prefix(count))       // 最弱を差し出す
            let fromLower = Array(sortedLower.suffix(count))       // 最強を差し出す
            guard fromUpper.count == count, fromLower.count == count else { continue }

            let upperIDs = Set(fromUpper.map(\.id))
            let lowerIDs = Set(fromLower.map(\.id))
            result[upper] = result[upper].filter { !upperIDs.contains($0.id) } + fromLower
            result[lower] = result[lower].filter { !lowerIDs.contains($0.id) } + fromUpper
            transfers.append(DaifugoTransfer(from: lower, to: upper, cards: fromLower))
            transfers.append(DaifugoTransfer(from: upper, to: lower, cards: fromUpper))
        }
        return (result.map { $0.sorted { $0.sortKey < $1.sortKey } }, transfers)
    }
}
