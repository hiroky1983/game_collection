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
        case .easy:   return "やさしい"
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
    static func openerIndex(in deck: [ShiritoriCard]) -> Int? {
        deck.indices.first { index in
            let card = deck[index]
            guard let tail = ShiritoriKana.tail(of: card.primaryReading), !ShiritoriKana.isN(tail) else { return false }
            let rest = deck.enumerated().filter { $0.offset != index }.map { ShiritoriSlot(card: $0.element) }
            return !moves(slots: rest, after: tail).isEmpty
        }
    }
}
