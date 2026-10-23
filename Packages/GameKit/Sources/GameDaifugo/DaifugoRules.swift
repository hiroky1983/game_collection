import Foundation
import Core

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

/// ゲーム開始直後に卓へ出す「あなたの交換」の内容（#2607）。交換で動いた札のうち、あなたが受け取った札と渡した札。
public struct DaifugoExchangeNotice: Equatable, Sendable {
    /// 交換の相手（プレイヤー番号）。
    public let partner: Int
    public let received: [DaifugoCard]
    public let gave: [DaifugoCard]

    /// あなたが関わる交換が無いとき（1 ゲーム目・免除で動かなかったとき）は nil。
    public init?(transfers: [DaifugoTransfer], human: Int) {
        let received = transfers.first { $0.to == human }
        let gave = transfers.first { $0.from == human }
        guard let partner = received?.from ?? gave?.to else { return nil }
        self.partner = partner
        self.received = received?.cards ?? []
        self.gave = gave?.cards ?? []
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

/// 局ごとに選べるローカルルール（Issue #2605・#2721）。**1 局 = 1 RuleSet**: 配った時点の値を局に焼き込み、
/// 対局中は変わらない（中断データにも載せる）。既定（`standard`）は従来の採用ルール（8切り・反則上がりあり、
/// しばり・階段・都落ちなし）と同じ。
public struct DaifugoRuleSet: Codable, Equatable, Sendable {
    /// 8切り（8 を含む組を出すと場が流れ、出した人がそのまま親になる）。
    public var isEightCutEnabled: Bool
    /// しばり（同じスートが 2 回続いたら、場が流れるまでそのスートしか出せない）。
    public var isBindEnabled: Bool
    /// 階段（同じスートの連番 3 枚以上を 1 つの組として出せる）。
    public var isSequenceEnabled: Bool
    /// 都落ち（前のゲームの大富豪が 1 位で上がれなかったら、その場で大貧民に落ちる）。
    public var isDownfallEnabled: Bool
    /// 反則上がり（最後の 1 手が 2・ジョーカー・8 だと、上がっても最下位に落ちる）。
    public var isFoulFinishEnabled: Bool

    public init(
        isEightCutEnabled: Bool = true,
        isBindEnabled: Bool = false,
        isSequenceEnabled: Bool = false,
        isDownfallEnabled: Bool = false,
        isFoulFinishEnabled: Bool = true
    ) {
        self.isEightCutEnabled = isEightCutEnabled
        self.isBindEnabled = isBindEnabled
        self.isSequenceEnabled = isSequenceEnabled
        self.isDownfallEnabled = isDownfallEnabled
        self.isFoulFinishEnabled = isFoulFinishEnabled
    }

    /// 欠けているキーは標準の値で補う。#2605 のしばりだけを書いた保存データ（中断データ・選択の記録）も読める。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let standard = DaifugoRuleSet()
        isEightCutEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEightCutEnabled) ?? standard.isEightCutEnabled
        isBindEnabled = try c.decodeIfPresent(Bool.self, forKey: .isBindEnabled) ?? standard.isBindEnabled
        isSequenceEnabled = try c.decodeIfPresent(Bool.self, forKey: .isSequenceEnabled) ?? standard.isSequenceEnabled
        isDownfallEnabled = try c.decodeIfPresent(Bool.self, forKey: .isDownfallEnabled) ?? standard.isDownfallEnabled
        isFoulFinishEnabled = try c.decodeIfPresent(Bool.self, forKey: .isFoulFinishEnabled) ?? standard.isFoulFinishEnabled
    }

    public static let standard = DaifugoRuleSet()
}

/// 出された組の形。
public enum DaifugoPlayShape: Equatable, Sendable {
    /// 同じ数字の組（ジョーカーはワイルド）。
    case group
    /// 階段（同じスートの連番）。
    case sequence
}

/// 大富豪のルールを**乱数も状態も持たない純粋関数**として閉じ込めた層。
///
/// Model（`DaifugoModel`）は進行と永続化だけを持ち、勝ち負けの判断はここに集約する。
/// ユニットテストはこの層に対して書くので、UI・CPU の都合でルールが揺れない。
///
/// 既定の採用ルール（Issue #89）: 革命 / 8切り / 反則上がり。しばり・階段・都落ちと、8切り・反則上がりの
/// オン / オフは局ごとに選べる（`DaifugoRuleSet`・Issue #2605・#2721）。
public enum DaifugoRules {
    /// ジョーカーの `rank`。通常の 1〜13 と衝突しない値を使う。
    public static let jokerRank = 0
    /// 階級の呼び名（`ranking` の順に対応）。表示用なので、その時点の言語で引く（#2166）。
    public static var titles: [String] { [tr("大富豪"), tr("富豪"), tr("貧民"), tr("大貧民")] }
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
    ///
    /// `bindSuits` が空でないとき（しばり中）は、ジョーカー以外の札がすべてそのスートでなければ出せない。
    /// 階段（`ruleSet.isSequenceEnabled`）は、場が階段のときは階段だけ、場が同じ数字の組のときは組だけが出せる。
    public static func isValidPlay(
        _ cards: [DaifugoCard],
        field: [DaifugoCard],
        isRevolution: Bool,
        bindSuits: Set<DaifugoSuit> = [],
        ruleSet: DaifugoRuleSet = .standard
    ) -> Bool {
        let options = evaluations(cards, isRevolution: isRevolution, ruleSet: ruleSet)
        guard !options.isEmpty else { return false }
        guard !field.isEmpty else { return true }
        guard satisfiesBind(cards, bindSuits: bindSuits) else { return false }
        guard cards.count == field.count else { return false }
        guard let current = evaluations(field, isRevolution: isRevolution, ruleSet: ruleSet).first else { return false }
        return options.contains { $0.shape == current.shape && $0.strength > current.strength }
    }

    // MARK: - 階段（Issue #2721）

    /// 階段の最短の枚数。
    public static let minimumSequenceLength = 3
    /// 強さの段数（3〜K・A・2 の 13 段。ジョーカーは別格）。
    private static let strengthLevels = 13

    /// 組の読み方とその強さ。
    struct PlayEvaluation: Equatable {
        let shape: DaifugoPlayShape
        let strength: Int
    }

    /// `cards` の組としての読み方。同じ数字の組を先に、階段を後に挙げる（どちらにも読めるのは
    /// 「札 1 種 + ジョーカー」だけで、場に出ている組は先頭の読み方で扱う）。
    static func evaluations(_ cards: [DaifugoCard], isRevolution: Bool, ruleSet: DaifugoRuleSet) -> [PlayEvaluation] {
        var result: [PlayEvaluation] = []
        if let strength = playStrength(cards, isRevolution: isRevolution) {
            result.append(PlayEvaluation(shape: .group, strength: strength))
        }
        if ruleSet.isSequenceEnabled, let strength = sequenceStrength(cards, isRevolution: isRevolution) {
            result.append(PlayEvaluation(shape: .sequence, strength: strength))
        }
        return result
    }

    /// 階段として置ける最下段の位置の範囲（強さの並び 3→0 … K→10・A→11・2→12 での位置）。
    /// 3 枚未満・スートが混ざる・同じ数字が重なる・ジョーカーだけのときは nil。
    /// ジョーカーは欠けた段か、端の外側を埋める。
    static func sequenceLowRange(_ cards: [DaifugoCard]) -> ClosedRange<Int>? {
        guard cards.count >= minimumSequenceLength, cards.count <= strengthLevels else { return nil }
        let naturals = cards.filter { !$0.isJoker }
        guard let suit = naturals.first?.suit, naturals.allSatisfy({ $0.suit == suit }) else { return nil }
        let positions = naturals.map { baseStrength(rank: $0.rank) }
        guard Set(positions).count == positions.count, let lowest = positions.min(), let highest = positions.max() else {
            return nil
        }
        let low = max(0, highest - cards.count + 1)
        let high = min(lowest, strengthLevels - cards.count)
        return low <= high ? low...high : nil
    }

    /// 階段の強さ。ジョーカーで置き方が選べるときは、出す側に最も有利な置き方（革命中は逆向き）で数える。
    /// 革命中は強さが逆になるので、いちばん低い段が強さを決める。
    static func sequenceStrength(_ cards: [DaifugoCard], isRevolution: Bool) -> Int? {
        guard let range = sequenceLowRange(cards) else { return nil }
        return isRevolution ? strengthLevels - 1 - range.lowerBound : range.upperBound + cards.count - 1
    }

    /// 場の組の形。場が空なら nil。
    public static func shape(of field: [DaifugoCard], isRevolution: Bool, ruleSet: DaifugoRuleSet) -> DaifugoPlayShape? {
        evaluations(field, isRevolution: isRevolution, ruleSet: ruleSet).first?.shape
    }

    /// 手札から作れる階段の候補（ジョーカーは足りない段にだけ必要な枚数を使う）。場が空なら 3 枚以上のすべて、
    /// 場があれば同じ枚数だけ。合法かどうかは呼び出し側が `isValidPlay` で確かめる。
    private static func sequenceCandidates(hand: [DaifugoCard], field: [DaifugoCard], bindSuits: Set<DaifugoSuit>) -> [[DaifugoCard]] {
        let jokers = hand.filter(\.isJoker).sorted { $0.id < $1.id }
        let lengths = field.isEmpty ? Array(minimumSequenceLength...strengthLevels) : [field.count]
        var plays: [[DaifugoCard]] = []
        for suit in DaifugoSuit.allCases where bindSuits.isEmpty || bindSuits.contains(suit) {
            var bySuit: [Int: DaifugoCard] = [:]
            for card in hand where card.suit == suit { bySuit[baseStrength(rank: card.rank)] = card }
            for length in lengths where length >= minimumSequenceLength && length <= strengthLevels {
                for low in 0...(strengthLevels - length) {
                    let present = (low..<(low + length)).compactMap { bySuit[$0] }
                    let missing = length - present.count
                    guard !present.isEmpty, missing <= jokers.count else { continue }
                    plays.append(present + jokers.prefix(missing))
                }
            }
        }
        return plays
    }

    // MARK: - しばり（Issue #2605）

    /// 札に含まれるスート（ジョーカーはワイルドなので数えない）。
    public static func suits(of cards: [DaifugoCard]) -> Set<DaifugoSuit> {
        Set(cards.compactMap(\.suit))
    }

    /// しばり中のスートに合う組か。しばりが無ければ常に true。ジョーカーはどのスートの代わりにもなる。
    public static func satisfiesBind(_ cards: [DaifugoCard], bindSuits: Set<DaifugoSuit>) -> Bool {
        bindSuits.isEmpty || suits(of: cards).isSubset(of: bindSuits)
    }

    /// `played` を出した直後のしばりのスート。
    ///
    /// すでにしばり中ならそのまま。そうでなければ、場に組があり、直前の組と**ジョーカー以外のスートの集合が同じ**
    /// （ともに空でない）ときに、そのスートでしばる。ジョーカーだけの組はスートを持たないので、しばりを作りも解きもしない。
    /// 場が流れたら呼び出し側が空に戻す（`DaifugoModel.clearField`）。
    public static func nextBindSuits(
        current: Set<DaifugoSuit>,
        field: [DaifugoCard],
        played: [DaifugoCard],
        ruleSet: DaifugoRuleSet
    ) -> Set<DaifugoSuit> {
        guard ruleSet.isBindEnabled else { return [] }
        guard current.isEmpty else { return current }
        guard !field.isEmpty else { return [] }
        let playedSuits = suits(of: played)
        return !playedSuits.isEmpty && playedSuits == suits(of: field) ? playedSuits : []
    }

    /// しばり中のスートを「♠」「♥♦」のように並べた表示用の文字列。
    public static func bindLabel(_ suits: Set<DaifugoSuit>) -> String {
        suits.sorted { $0.rawValue < $1.rawValue }.map(\.symbol).joined()
    }

    /// 革命（同ランク4枚以上）か。
    public static func triggersRevolution(_ cards: [DaifugoCard]) -> Bool {
        playRank(cards) != nil && cards.count >= revolutionCount
    }

    /// 8切り（8 を含む組は場を流し、出した人がそのまま次の親になる）か。8切りなしの局では流れない。
    public static func clearsField(_ cards: [DaifugoCard], ruleSet: DaifugoRuleSet = .standard) -> Bool {
        ruleSet.isEightCutEnabled && cards.contains { $0.rank == 8 }
    }

    /// 反則上がり（最後の1手が 2・ジョーカー・8 を含む）か。反則上がりなしの局では起きない。
    /// 8 は 8切りがある局だけ数える（8切りなしなら 8 は特別な札ではない）。
    /// 「出せない」ではなく「上がっても最下位に落ちる」として扱う（2 しか残っていないと永久に上がれなくなるため）。
    public static func isFoulFinish(_ cards: [DaifugoCard], ruleSet: DaifugoRuleSet = .standard) -> Bool {
        guard ruleSet.isFoulFinishEnabled else { return false }
        return cards.contains { $0.isJoker || $0.rank == 2 || (ruleSet.isEightCutEnabled && $0.rank == 8) }
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
        isRevolution: Bool,
        bindSuits: Set<DaifugoSuit> = [],
        ruleSet: DaifugoRuleSet = .standard
    ) -> Set<Int> {
        guard !hand.isEmpty else { return [] }
        // 場が流れていれば1枚から好きな組を出せる = 手札すべてが出せる。
        guard !field.isEmpty else { return Set(hand.map(\.id)) }
        // 場が階段のときは階段しか出せない。出せる階段のどれかに入る札が「出せる」札で、
        // 階段が作れるならジョーカーはどの札の代わりにもなれる。
        if shape(of: field, isRevolution: isRevolution, ruleSet: ruleSet) == .sequence {
            let plays = sequenceCandidates(hand: hand, field: field, bindSuits: bindSuits).filter {
                isValidPlay($0, field: field, isRevolution: isRevolution, bindSuits: bindSuits, ruleSet: ruleSet)
            }
            var ids = Set(plays.flatMap { $0.map(\.id) })
            if !ids.isEmpty { ids.formUnion(hand.filter(\.isJoker).map(\.id)) }
            return ids
        }
        guard let fieldStrength = playStrength(field, isRevolution: isRevolution) else { return [] }

        let jokers = hand.filter(\.isJoker)
        var groups: [Int: [DaifugoCard]] = [:]
        // しばり中は、そのスート以外の札は組を作る材料にならない（ジョーカーは別に数える）。
        for card in hand where !card.isJoker && satisfiesBind([card], bindSuits: bindSuits) {
            groups[card.rank, default: []].append(card)
        }

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
        isRevolution: Bool,
        bindSuits: Set<DaifugoSuit> = [],
        ruleSet: DaifugoRuleSet = .standard
    ) -> String? {
        guard !cards.isEmpty else { return nil }
        let options = evaluations(cards, isRevolution: isRevolution, ruleSet: ruleSet)
        guard !options.isEmpty else {
            return ruleSet.isSequenceEnabled
                ? tr("数字がそろっていないか、階段（同じ柄の連番3枚以上）になっていません")
                : tr("数字がそろっていません（ジョーカーは他の数字の代わりに使えます）")
        }
        guard !field.isEmpty else { return nil }
        guard cards.count == field.count else {
            return tr("場は%1$lld枚です。%2$lld枚では出せません", field.count, cards.count)
        }
        let current = evaluations(field, isRevolution: isRevolution, ruleSet: ruleSet).first
        if let current, !options.contains(where: { $0.shape == current.shape }) {
            return current.shape == .sequence
                ? tr("場は階段です。同じ柄の連番で出してください")
                : tr("場は同じ数字の組です。階段では出せません")
        }
        guard let current, options.contains(where: { $0.shape == current.shape && $0.strength > current.strength }) else {
            if current?.shape == .sequence {
                return isRevolution
                    ? tr("革命中です。場の階段より弱い階段が必要です")
                    : tr("場の階段より強い階段が必要です")
            }
            // 場がジョーカーだけのときは非ジョーカーが無いので、そのまま JOKER と呼ぶ。
            let label = field.first { !$0.isJoker }?.rankLabel ?? "JOKER"
            return isRevolution
                ? tr("革命中です。場の %@ より弱い数字が必要です", label)
                : tr("場の %@ より強い数字が必要です", label)
        }
        guard satisfiesBind(cards, bindSuits: bindSuits) else {
            return tr("しばり中です。%@のカードだけ出せます（ジョーカーは使えます）", bindLabel(bindSuits))
        }
        return nil
    }

    // MARK: - 手の列挙と CPU の選択

    /// 今の場に出せる手の候補。ジョーカーは**必要な枚数だけ**使う版のみを挙げる
    /// （同じ強さでジョーカーを余分に使う手は CPU にとって常に損なので列挙しない）。
    public static func legalPlays(
        hand: [DaifugoCard],
        field: [DaifugoCard],
        isRevolution: Bool,
        bindSuits: Set<DaifugoSuit> = [],
        ruleSet: DaifugoRuleSet = .standard
    ) -> [[DaifugoCard]] {
        let jokers = hand.filter(\.isJoker).sorted { $0.id < $1.id }
        var groups: [Int: [DaifugoCard]] = [:]
        for card in hand where !card.isJoker && satisfiesBind([card], bindSuits: bindSuits) {
            groups[card.rank, default: []].append(card)
        }

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
                if isValidPlay(play, field: field, isRevolution: isRevolution, bindSuits: bindSuits, ruleSet: ruleSet) {
                    plays.append(play)
                }
            }
            // ジョーカーだけで出す（場が空のときの最強手、または最後の1枚）。
            if count <= jokers.count {
                let play = Array(jokers.prefix(count))
                if isValidPlay(play, field: field, isRevolution: isRevolution, bindSuits: bindSuits, ruleSet: ruleSet) {
                    plays.append(play)
                }
            }
        }
        if ruleSet.isSequenceEnabled {
            plays += sequenceCandidates(hand: hand, field: field, bindSuits: bindSuits).filter {
                isValidPlay($0, field: field, isRevolution: isRevolution, bindSuits: bindSuits, ruleSet: ruleSet)
            }
        }
        // 「札 1 種 + ジョーカー」は組にも階段にも読めるので、同じ札の組み合わせは 1 つにする。
        var seen = Set<[Int]>()
        return plays.filter { seen.insert($0.map(\.id).sorted()).inserted }
    }

    /// CPU の選択（貪欲法）: **出せる最弱の手**を選ぶ。「ふつう」の CPU はこれをそのまま使う。
    ///
    /// 同じ強さならジョーカーを使わない手を選ぶ。枚数は場の状況で向きが変わる:
    /// 場に追随するときは枚数が場と一致するので比較に効かず、**親番（場が空）では枚数の多い手**を選ぶ。
    /// 反則上がりになる手は、他に選べる手があるときだけ避ける（避けようがなければそのまま出す）。
    public static func greedyPlay(
        hand: [DaifugoCard],
        field: [DaifugoCard],
        isRevolution: Bool,
        bindSuits: Set<DaifugoSuit> = [],
        ruleSet: DaifugoRuleSet = .standard
    ) -> [DaifugoCard]? {
        rankedPlays(hand: hand, field: field, isRevolution: isRevolution, bindSuits: bindSuits, ruleSet: ruleSet).first
    }

    /// 出せる手を、貪欲法の好みの順（先頭が `greedyPlay` の手）に並べたもの。
    static func rankedPlays(
        hand: [DaifugoCard],
        field: [DaifugoCard],
        isRevolution: Bool,
        bindSuits: Set<DaifugoSuit> = [],
        ruleSet: DaifugoRuleSet = .standard
    ) -> [[DaifugoCard]] {
        let plays = legalPlays(hand: hand, field: field, isRevolution: isRevolution, bindSuits: bindSuits, ruleSet: ruleSet)

        func isFoul(_ play: [DaifugoCard]) -> Bool {
            play.count == hand.count && isFoulFinish(play, ruleSet: ruleSet)
        }
        // 親番だけ枚数を降順にする。場に追随するときは合法手の枚数が場と一致するのでこの項は効かないが、
        // 場が空のときは同じランクを 1 枚だけ出す手が常に最小になり、CPU がペアも革命も一度も出さなかった（#375）。
        let leadsField = field.isEmpty
        func rankKey(_ play: [DaifugoCard]) -> (Int, Int, Int, Int, Int) {
            (
                isFoul(play) ? 1 : 0,
                orderingStrength(play, isRevolution: isRevolution, ruleSet: ruleSet, leads: leadsField),
                play.filter(\.isJoker).count,
                leadsField ? -play.count : play.count,
                play.first?.id ?? 0
            )
        }
        return plays.sorted { rankKey($0) < rankKey($1) }
    }

    /// 手の強さ（CPU が弱い手から選ぶための並べ替え用）。読み方が複数あるときは最も弱い読み方。
    ///
    /// 親番（`leads`）で出す階段は、勝つための強さ（いちばん強い札）ではなく**いちばん弱い札**で数える。
    /// 場を取られる心配のない親番では、弱い札から始まる階段を単独の弱い札と並べて、枚数の多いほうを先に出すため。
    private static func orderingStrength(
        _ play: [DaifugoCard], isRevolution: Bool, ruleSet: DaifugoRuleSet, leads: Bool = false
    ) -> Int {
        evaluations(play, isRevolution: isRevolution, ruleSet: ruleSet).map { option -> Int in
            guard leads, option.shape == .sequence, let range = sequenceLowRange(play) else { return option.strength }
            return isRevolution
                ? strengthLevels - 1 - (range.upperBound + play.count - 1)
                : range.lowerBound
        }.min() ?? Int.max
    }

    // MARK: - CPU の強さ（#2604）

    /// 「かんたん」が最善手を外して次善手を選ぶ確率。仮置き（実装後の会長 QA で調整する）。
    static let easySlipChance = 0.3
    /// 「むずかしい」が強い札を温存してパスする、その札の強さの下限（A・2・ジョーカー。革命中は 3・4・ジョーカー）。
    static let hoardStrength = 11
    /// 手札がこの枚数以下なら温存しない（上がりを急ぐ）。
    static let hoardMinHandCount = 3
    /// 他の誰かの手札がこの枚数以下なら温存しない（上がられる前に止める）。
    static let hoardOpponentThreshold = 2

    /// 強さを踏まえた CPU の選択。出せる手が無い・出さない（パス）なら nil。
    ///
    /// - 入門: 出せる手からでたらめに選ぶ。
    /// - かんたん: 一定確率で、最善手ではなく次善手を選ぶ。
    /// - ふつう: `greedyPlay` と同じ（回帰なし）。
    /// - むずかしい: ① 追随のとき、最善手が強い札（A・2・ジョーカー）なら、手札が多く誰も上がり間近でない間は
    ///   パスして温存する ② 親番のとき、革命を起こせて、残る手札が弱い札に偏っているなら革命で始める。
    /// - Parameter minOpponentHandCount: 手札が残っている他のプレイヤーのうち最も少ない枚数（温存の判断に使う）。
    public static func cpuPlay(
        hand: [DaifugoCard],
        field: [DaifugoCard],
        isRevolution: Bool,
        strength: CPUStrength,
        minOpponentHandCount: Int = .max,
        bindSuits: Set<DaifugoSuit> = [],
        ruleSet: DaifugoRuleSet = .standard,
        using rng: inout some RandomNumberGenerator
    ) -> [DaifugoCard]? {
        let ranked = rankedPlays(hand: hand, field: field, isRevolution: isRevolution, bindSuits: bindSuits, ruleSet: ruleSet)
        guard let best = ranked.first else { return nil }
        switch strength {
        case .normal:
            return best
        case .novice:
            return ranked.randomElement(using: &rng)
        case .easy:
            guard ranked.count > 1, Double.random(in: 0..<1, using: &rng) < easySlipChance else { return best }
            return ranked[1]
        case .hard:
            if field.isEmpty {
                return revolutionLead(ranked, hand: hand, isRevolution: isRevolution, ruleSet: ruleSet) ?? best
            }
            let isStrong = orderingStrength(best, isRevolution: isRevolution, ruleSet: ruleSet) >= hoardStrength
            let canHoard = hand.count > hoardMinHandCount && minOpponentHandCount > hoardOpponentThreshold
            return isStrong && canHoard ? nil : best
        }
    }

    /// 親番で革命から始める手。起こせる手が無い・残る手札が強い札に偏っているときは nil。
    /// 革命は強さの並びを反転するので、残る手札が弱い札ばかりのときに得になる。
    private static func revolutionLead(
        _ ranked: [[DaifugoCard]], hand: [DaifugoCard], isRevolution: Bool, ruleSet: DaifugoRuleSet
    ) -> [DaifugoCard]? {
        guard let play = ranked.first(where: {
            triggersRevolution($0) && !($0.count == hand.count && isFoulFinish($0, ruleSet: ruleSet))
        }) else { return nil }
        let playedIDs = Set(play.map(\.id))
        let rest = hand.filter { !playedIDs.contains($0.id) }
        let weak = rest.filter { !$0.isJoker && strength(rank: $0.rank, isRevolution: isRevolution) <= 4 }.count
        let strong = rest.filter { $0.isJoker || strength(rank: $0.rank, isRevolution: isRevolution) >= 8 }.count
        return weak > strong ? play : nil
    }

    // MARK: - 順位と階級

    /// 上がり順・反則上がり・都落ち・投了から最終順位を決める。反則上がりは順位を失い末尾へ回り、
    /// 投了（#194）は最後まで打っていないので反則上がりよりさらに下に置く。
    /// 都落ち（#2721）は、前のゲームの大富豪が 1 位でなければその人を（投了者を除く）最下位に落とす。
    /// - Parameters:
    ///   - finishOrder: 手札が尽きた順のプレイヤー番号。
    ///   - fouls: 反則上がりしたプレイヤー番号。
    ///   - resigned: 投了したプレイヤー番号。反則上がりと重なっても投了の扱いを優先する。
    ///   - previousTycoon: 都落ちが有効な局での、前のゲームの大富豪。無効な局・1 ゲーム目は nil。
    /// - Returns: 1位から順のプレイヤー番号。
    public static func ranking(
        finishOrder: [Int], fouls: Set<Int>, resigned: Set<Int> = [], previousTycoon: Int? = nil
    ) -> [Int] {
        let clean = finishOrder.filter { !fouls.contains($0) && !resigned.contains($0) }
        let fouled = finishOrder.filter { fouls.contains($0) && !resigned.contains($0) }
        let quit = finishOrder.filter { resigned.contains($0) }
        let ordered = clean + fouled
        guard let fallen = downfallPlayer(order: ordered, previousTycoon: previousTycoon, resigned: resigned) else {
            return ordered + quit
        }
        return ordered.filter { $0 != fallen } + [fallen] + quit
    }

    /// 都落ちで最下位に落ちる人。前の大富豪が 1 位でなく、投了してもいないとき。
    /// `order` は反則上がりを下げた後の順位（投了者を除く）。
    public static func downfallPlayer(order: [Int], previousTycoon: Int?, resigned: Set<Int> = []) -> Int? {
        guard let tycoon = previousTycoon, !resigned.contains(tycoon),
              let place = order.firstIndex(of: tycoon), place > 0 else { return nil }
        return tycoon
    }

    /// 順位（0 始まり）に対応する階級名。4人以外でも落ちないよう範囲外は空文字にする。
    public static func title(forPlace place: Int) -> String {
        let titles = self.titles
        return titles.indices.contains(place) ? titles[place] : ""
    }

    // MARK: - カード交換

    /// 次のゲーム開始時のカード交換（大富豪⇔大貧民2枚 / 富豪⇔貧民1枚）。
    ///
    /// 上位は**最弱**の札を、下位は**最強**の札を差し出す。どちらの選択も交換前の手札から
    /// 同時に決めるので、渡した札がそのまま返る（渡した札を再度選ぶ）ことは起きない。
    /// - Parameters:
    ///   - hands: プレイヤー番号順の手札。
    ///   - ranking: 1位から順のプレイヤー番号。
    ///   - waivingTopPair: 大富豪⇔大貧民の2枚交換を行わない（大貧民が広告で献上を免除した・#1048）。
    ///     片側だけ渡すと枚数が崩れるので、組ごと取りやめる。富豪⇔貧民の1枚交換はそのまま行う。
    /// - Returns: 交換後の手札と、実際に動いた札の一覧。
    public static func applyExchange(
        hands: [[DaifugoCard]],
        ranking: [Int],
        waivingTopPair: Bool = false
    ) -> (hands: [[DaifugoCard]], transfers: [DaifugoTransfer]) {
        guard ranking.count == 4 else { return (hands, []) }
        // (上位, 下位, 枚数)
        let pairs = (waivingTopPair ? [] : [(ranking[0], ranking[3], 2)]) + [(ranking[1], ranking[2], 1)]

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
