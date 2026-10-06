import Foundation
import Core

// MARK: - 盤の 1 マス

/// 札を取ったのは誰か。
public enum ShiritoriOwner: Equatable, Sendable {
    case player
    case cpu
}

/// 盤に並ぶ札 1 枚。`owner` が nil ならまだ誰にも取られていない。
public struct ShiritoriSlot: Equatable, Sendable {
    public let card: ShiritoriCard
    public var owner: ShiritoriOwner?

    public init(card: ShiritoriCard, owner: ShiritoriOwner? = nil) {
        self.card = card
        self.owner = owner
    }
}

/// 札を 1 枚選んだときの手。`reading` は**そのとき使った読み**（次の語尾はこの読みで決まる）。
public struct ShiritoriMove: Equatable, Sendable {
    public let slot: Int
    public let reading: String
}

// MARK: - ノルマ（難易度）

/// 難易度。**ノルマの枚数だけで表す**（会長決裁 2026-09-21・#1243。CPU の考える速さでは変えない）。
///
/// ノルマは「プレイヤーが取った札の枚数」で、**取るたびに見て、届いた瞬間に勝ち**（本家ワギャンランドと同じ
/// 即時勝利条件・社長決裁 2026-09-21 の訂正・#1245）。時間切れまでにノルマへ届かなければ負け。
/// 枚数は暫定値（参考: ランダムに打つ人の平均 6.4 枚・上位 1 割 9 枚）で、会長が本家の実プレイ動画で
/// 確かめたあとに変わりうる。数字を変えるときはこの型の `cardCount` だけを触ればよい。
public enum ShiritoriQuota: Int, CaseIterable, Codable, Sendable {
    case easy = 0
    case normal = 1
    case hard = 2

    public static let standard = ShiritoriQuota.normal

    public var label: String {
        switch self {
        case .easy:   return "かんたん"
        case .normal: return "ふつう"
        case .hard:   return "むずかしい"
        }
    }

    /// 開始シート・結果に出すノルマの説明。
    public var summary: String { "\(cardCount)枚取ったらクリア" }

    /// 勝ちになる、プレイヤーが取った枚数。
    public var cardCount: Int {
        switch self {
        case .easy:   return 4
        case .normal: return 6
        case .hard:   return 9
        }
    }

    public var analyticsLevel: AnalyticsLevel {
        switch self {
        case .easy:   return .beginner
        case .normal: return .normal
        case .hard:   return .hard
        }
    }

    /// プレイヤーが取った枚数がノルマに届いているか。
    public func isMet(player: Int) -> Bool { player >= cardCount }
}

// MARK: - モード

/// 遊び方の分岐（#1502）。**局の開始時に選び、`ShiritoriModel` へ焼き込む**（1 局 = 1 RuleSet 原則）。
public enum ShiritoriMode: Int, CaseIterable, Codable, Sendable {
    /// 従来のルール。ノルマの枚数に届いた瞬間に勝ち。
    case quota = 0
    /// 札が尽きるか相手が詰むまで続ける。盤の札は取ると山札から補充される。
    case endless = 1

    public static let standard = ShiritoriMode.quota

    public var label: String {
        switch self {
        case .quota:   return "ノルマ"
        case .endless: return "とことん"
        }
    }

    /// 開始シートの選択肢に添える一言。
    public var summary: String {
        switch self {
        case .quota:   return "ノルマの枚数を取れば勝ち"
        case .endless: return "札が尽きるまで続く"
        }
    }

    /// 成績を分ける区分（`GameScore.variant`）。従来のモードは nil のまま（自己ベストの保存先を変えない）。
    var scoreVariant: (key: String, label: String)? {
        switch self {
        case .quota:   return nil
        case .endless: return ("endless", "とことん")
        }
    }
}

// MARK: - 時間

/// 制限時間まわりの定数。`ShiritoriModel` は MainActor に隔離されるため、隔離のない純関数（文言など）からも
/// 読めるようここに置く。
public enum ShiritoriTime {
    /// 制限時間の初期値（秒）。全難易度共通（会長決裁 2026-09-21・#1243）。
    public static let initial: Double = 60
    /// しりとりが成立するたびに増える秒数。
    public static let successBonus: Double = 10
    /// お手つき 1 回で減る秒数。
    public static let missPenalty: Double = 5
    /// 時間切れの負けから広告を見て続けたときに足す秒数（#1717）。
    public static let adExtension: Double = 30
}

// MARK: - ルール

/// しりとりの判定（純粋関数）。進行・時間・永続化は `ShiritoriModel` が持つ。
enum ShiritoriRules {
    /// 語尾 `tail` を受けられる、この札の読み。表読みを先に見て、最初に合ったもの。
    /// 受けられなければ nil（お手つき）。
    static func acceptingReading(of card: ShiritoriCard, after tail: Character) -> String? {
        card.readings.first { reading in
            guard let head = ShiritoriKana.head(of: reading) else { return false }
            return ShiritoriKana.accepts(head: head, after: tail)
        }
    }

    /// 場の語尾 `tail` の次に取れる手すべて（盤の並び順）。取られた札は含めない。
    static func moves(slots: [ShiritoriSlot], after tail: Character) -> [ShiritoriMove] {
        slots.enumerated().compactMap { index, slot in
            guard slot.owner == nil,
                  let reading = acceptingReading(of: slot.card, after: tail) else { return nil }
            return ShiritoriMove(slot: index, reading: reading)
        }
    }

    /// 「ん」で終わる読みか。
    static func endsWithN(_ reading: String) -> Bool {
        ShiritoriKana.tail(of: reading).map(ShiritoriKana.isN) ?? false
    }

    /// CPU の手。**固定順（盤の並び順）で走査して最初に見つかった札を選ぶだけ**（本家のボスと同じ。
    /// 難易度でロジックは変えない）。裏読みも常に見る。「ん」で終わる読みも避けない
    /// （Issue #1243 の指定どおり。それが先頭なら選んで、その場で負ける）。
    static func cpuMove(slots: [ShiritoriSlot], after tail: Character) -> ShiritoriMove? {
        moves(slots: slots, after: tail).first
    }

    /// 最初の場の札にする位置。**プレイヤーの最初の手が 1 つは残る**札を、シャッフル済みの山から
    /// 先頭に近い順に選ぶ（開始直後に詰んで何もできない局を作らない）。語尾が「ん」の札も避ける。
    ///
    /// 加えて、**開場札を抜いたことで他の札が唯一の後続を失わないか**も見る（#1297: 「わに」の
    /// 唯一の後続だった「にゃんこ」＝ねこ札を開場札に選ぶと、盤の「わに」を取った瞬間に相手が
    /// 詰んで一発勝ちになる穴が再発した）。開場札自身の後続有無だけでは、開場札の**不在**が他の
    /// 札に与える影響を見落とす。
    static func openerIndex(in deck: [ShiritoriCard]) -> Int? {
        deck.indices.first { index in
            let card = deck[index]
            guard let tail = ShiritoriKana.tail(of: card.primaryReading), !ShiritoriKana.isN(tail) else { return false }
            let restCards = deck.enumerated().filter { $0.offset != index }.map(\.element)
            guard !moves(slots: restCards.map { ShiritoriSlot(card: $0) }, after: tail).isEmpty else { return false }
            return !hasDeadEndReading(in: restCards)
        }
    }

    /// `cards` の構成に、いずれかの読み（「ん」を除く）の語尾を、他のどの札の語頭でも受けられない
    /// 読み（詰み専用の唯一後続喪失）が無いか。
    static func hasDeadEndReading(in cards: [ShiritoriCard]) -> Bool {
        !deadEndCards(in: cards).isEmpty
    }

    /// `hasDeadEndReading` に引っかかる札（いずれかの読みの語尾を、ほかのどの札の語頭でも受けられない札）。
    static func deadEndCards(in cards: [ShiritoriCard]) -> [ShiritoriCard] {
        // 語頭ごとに、その語頭の読みを持つ札の id を引けるようにしてから 1 回ずつ見る（札が 50 枚に増えて、
        // 開場札の候補ごとに全札 × 全読みを総当たりすると配りが遅くなるため）。判定は総当たりと同じ。
        var idsByHead: [Character: Set<String>] = [:]
        for card in cards {
            for reading in card.readings {
                if let head = ShiritoriKana.head(of: reading) { idsByHead[head, default: []].insert(card.id) }
            }
        }
        return cards.filter { card in
            card.readings.contains { reading in
                guard !endsWithN(reading), let tail = ShiritoriKana.tail(of: reading) else { return false }
                let followers = (idsByHead[tail] ?? []).union(idsByHead[ShiritoriKana.unvoiced(tail)] ?? [])
                return followers.subtracting([card.id]).isEmpty
            }
        }
    }
}

// MARK: - 勝てる盤か（#1659）

extension ShiritoriRules {
    /// `quota` モードで、プレイヤーが先手の最良の打ち方をすれば勝てる盤か。CPU の手は固定順（`cpuMove`）で
    /// 決まるので、プレイヤーの選択だけを枝分かれさせて全探索できる（枝は数本・深さはノルマ枚数まで）。
    /// 勝ちは `quota` 枚に届く・CPU が続けられない・CPU が「ん」で終わる読みを選ばされる、のいずれか。
    /// プレイヤーが「ん」で終わる読みを選ぶ手は負けなので探索しない。
    static func isWinnable(slots: [ShiritoriSlot], openerReading: String, quota: Int) -> Bool {
        var board = slots
        guard let tail = ShiritoriKana.tail(of: openerReading) else { return false }
        return playerCanWin(board: &board, tail: tail, taken: 0, quota: quota)
    }

    private static func playerCanWin(board: inout [ShiritoriSlot], tail: Character, taken: Int, quota: Int) -> Bool {
        for move in moves(slots: board, after: tail) where !endsWithN(move.reading) {
            guard let next = ShiritoriKana.tail(of: move.reading) else { continue }
            board[move.slot].owner = .player
            defer { board[move.slot].owner = nil }
            if taken + 1 >= quota { return true }
            guard let reply = cpuMove(slots: board, after: next) else { return true }   // CPU が詰む
            if endsWithN(reply.reading) { return true }                                   // CPU が「ん」を取らされる
            guard let replyTail = ShiritoriKana.tail(of: reply.reading) else { continue }
            board[reply.slot].owner = .cpu
            defer { board[reply.slot].owner = nil }
            if playerCanWin(board: &board, tail: replyTail, taken: taken + 1, quota: quota) { return true }
        }
        return false
    }
}

// MARK: - 配り（#1502）

/// 配った結果。`stock` は山札（盤の札が取られたときの補充元。`quota` モードでは常に空）。
struct ShiritoriDeal: Equatable {
    let opener: ShiritoriCard
    let board: [ShiritoriCard]
    let stock: [ShiritoriCard]
}

extension ShiritoriRules {
    /// 盤に並べる札の枚数（6 列 × 5 行にぴったり収まる本数（#1660: 29 枚だと右下が歯抜けだった））。
    static let boardSize = 30

    /// 山札が増えても盤の枚数は変えない。`quota` は山札から開場札 1 枚 + 盤 30 枚だけを使い（残りは使わない）、
    /// `endless` は残りを山札にして取るたびに補充する。
    ///
    /// **配り直して保証すること**（何度か引き直して、満たす配りだけを採る）:
    /// - 開場札の語尾が「ん」でなく、プレイヤーの最初の手が盤に 1 枚以上ある
    /// - 詰み専用の唯一後続喪失が無い（`hasDeadEndReading`。`quota` は使う 30 枚の中で、`endless` は山札を含む
    ///   全体で見る。補充で後続が現れるので、盤の 30 枚の中だけでは判定しない）
    /// - `quota` は、プレイヤーの打ち方次第で勝てる手順が盤にある（`isWinnable`・#1659: ランダムな配りだと
    ///   ふつうで 35%・むずかしいで 50% の局が、どう打っても途中で詰んで負けだった）
    static func deal<G: RandomNumberGenerator>(
        deck: [ShiritoriCard], mode: ShiritoriMode, quota: ShiritoriQuota = .standard, using generator: inout G
    ) -> ShiritoriDeal {
        let boardCount = min(boardSize, max(deck.count - 1, 0))
        var fallback: ShiritoriDeal?
        for _ in 0..<attempts {
            var cards = deck.shuffled(using: &generator)
            // ノルマは 50 枚から 30 枚だけを使うので、そのまま抜くと詰み専用の札が混ざりやすい。
            // 混ざったら、その札を使わない札と入れ替えて直す。
            if mode == .quota { cards = repairedSelection(cards, count: boardCount + 1, using: &generator) }
            guard let deal = deal(from: cards, boardCount: boardCount, mode: mode, quota: quota) else {
                if fallback == nil { fallback = unguardedDeal(from: cards, boardCount: boardCount, mode: mode) }
                continue
            }
            return deal
        }
        // 満たす配りが見つからない小さな山（テスト用の少数札など）。従来どおりの最初の 1 手だけは保証を試みる。
        return fallback ?? unguardedDeal(from: deck, boardCount: boardCount, mode: mode)
    }

    /// 引き直しの上限。50 枚の山では 1〜数回で見つかる（テストが確かめる）。
    private static let attempts = 50

    /// 先頭 `count` 枚を使う札として、詰み専用の札（`deadEndCards`）が出なくなるまで、
    /// 該当する札を使わない札のどれかと入れ替える。返すのは `使う札 + 使わない札` の並び。
    private static func repairedSelection<G: RandomNumberGenerator>(
        _ cards: [ShiritoriCard], count: Int, using generator: inout G
    ) -> [ShiritoriCard] {
        var inside = Array(cards.prefix(count))
        var outside = Array(cards.dropFirst(count))
        for _ in 0..<200 where !outside.isEmpty {
            let dead = deadEndCards(in: inside)
            guard let card = dead.randomElement(using: &generator),
                  let i = inside.firstIndex(where: { $0.id == card.id }),
                  let j = outside.indices.randomElement(using: &generator) else { break }
            swap(&inside[i], &outside[j])
        }
        return inside + outside
    }

    private static func deal(
        from cards: [ShiritoriCard], boardCount: Int, mode: ShiritoriMode, quota: ShiritoriQuota
    ) -> ShiritoriDeal? {
        let used = Array(cards.prefix(boardCount + 1))
        let pool = mode == .endless ? cards : used
        for index in used.indices {
            let opener = used[index]
            guard let tail = ShiritoriKana.tail(of: opener.primaryReading), !ShiritoriKana.isN(tail) else { continue }
            let rest = pool.filter { $0.id != opener.id }
            let board = Array(rest.prefix(boardCount))
            guard !moves(slots: board.map { ShiritoriSlot(card: $0) }, after: tail).isEmpty,
                  !hasDeadEndReading(in: rest) else { continue }
            if mode == .quota,
               !isWinnable(slots: board.map { ShiritoriSlot(card: $0) }, openerReading: opener.primaryReading,
                           quota: quota.cardCount) { continue }
            return ShiritoriDeal(opener: opener, board: board, stock: Array(rest.dropFirst(boardCount)))
        }
        return nil
    }

    private static func unguardedDeal(from cards: [ShiritoriCard], boardCount: Int, mode: ShiritoriMode) -> ShiritoriDeal {
        let index = openerIndex(in: Array(cards.prefix(boardCount + 1))) ?? 0
        var rest = cards
        let opener = rest.remove(at: index)
        return ShiritoriDeal(
            opener: opener,
            board: Array(rest.prefix(boardCount)),
            stock: mode == .endless ? Array(rest.dropFirst(boardCount)) : []
        )
    }
}
