import Foundation

/// 手札 1 枚のヒント表示の状態（大富豪 #190・いろリレーと同じ形）。
public enum HeartsCardHint: Equatable, Sendable {
    case none
    case playable
    case unplayable
    /// 渡す場面でヒントが示した、渡すとよい札（#3003）。
    case recommendedPass
}

/// ハーツのルールを**乱数も状態も持たない純粋関数**として閉じ込めた層（Issue #1884）。
///
/// ルールは 1 つに固定する（Issue の受け入れ条件）:
/// 52 枚を 4 人に 13 枚ずつ配る → 毎回**左隣へ 3 枚**渡す → **クラブの 2** を持つ人から始める →
/// 出された札と同じスートがあれば必ず出す（無ければ何でもよい）→ いちばん強い札（出だしのスートの最大）の人が 4 枚を取る →
/// ハート 1 点・スペードのクイーン 13 点 → 誰かが `targetScore` 点に届いた手で終わり、**合計の少ない人が勝ち**。
///
/// - ハートは場に出るまで（ハートが割れるまで）先頭に出せない。手札がハートだけなら出せる。
/// - 1 巡目は点の札（ハート・スペードのクイーン）を出せない。点の札しか持っていなければ出せる。
/// - 「全部取り」（26 点を総取りしたときに他の 3 人へ点を移す）は入れない。取った札の点をそのまま足す。
public enum HeartsRules {
    public static let playerCount = 4
    /// 人間の席（下）。1 = 左・2 = 向かい・3 = 右の CPU。
    public static let humanIndex = 0
    public static let handSize = 13
    /// 渡す枚数。
    public static let passCount = 3
    /// 対局が終わる点。誰かがこの点に届いた手の終わりで決着する（短く遊べるよう 100 ではなく 50）。
    public static let targetScore = 50
    /// 1 手（13 巡）で動く点の合計。
    public static let pointsPerHand = 26

    /// `player` が札を渡す相手（左隣 = 次に出す人）。
    public static func passTarget(from player: Int) -> Int { (player + 1) % playerCount }

    /// `player` が札を受け取る相手（右隣）。
    public static func passSource(to player: Int) -> Int { (player + playerCount - 1) % playerCount }

    /// クラブの 2 を持っている人（最初の巡の先頭）。配り方が壊れていて見つからなければ 0。
    public static func startingPlayer(hands: [[HeartsCard]]) -> Int {
        hands.firstIndex { $0.contains(.twoOfClubs) } ?? 0
    }

    // MARK: - 出せる札

    /// `hand` から、いまの巡 `trick` に出せる札（手札の並び順のまま）。
    ///
    /// - Parameters:
    ///   - trick: この巡にすでに出た札（先頭が出だし）。空ならこの人が先頭。
    ///   - heartsBroken: ハートがすでに場に出たか。
    ///   - isFirstTrick: 1 巡目か。
    public static func legalPlays(
        hand: [HeartsCard], trick: [HeartsPlay], heartsBroken: Bool, isFirstTrick: Bool
    ) -> [HeartsCard] {
        guard !hand.isEmpty else { return [] }
        guard let lead = trick.first?.card.suit else {
            // 先頭。1 巡目はクラブの 2 から。
            if isFirstTrick, hand.contains(.twoOfClubs) { return [.twoOfClubs] }
            if !heartsBroken {
                let nonHearts = hand.filter { $0.suit != .heart }
                if !nonHearts.isEmpty { return nonHearts }
            }
            return hand
        }
        let follow = hand.filter { $0.suit == lead }
        if !follow.isEmpty { return follow }
        // 出だしのスートが無い。1 巡目だけは点の札を避ける（それしか無ければ出せる）。
        if isFirstTrick {
            let safe = hand.filter { $0.points == 0 }
            if !safe.isEmpty { return safe }
        }
        return hand
    }

    // MARK: - 巡の決着

    /// 出だしのスートでいちばん強い札を出した人。4 枚そろう前に呼んでも、それまでで最も強い人を返す。
    public static func trickWinner(_ trick: [HeartsPlay]) -> Int? {
        guard let lead = trick.first?.card.suit else { return nil }
        return trick.filter { $0.card.suit == lead }.max { $0.card.rank < $1.card.rank }?.player
    }

    /// 札の点の合計。
    public static func points(_ cards: [HeartsCard]) -> Int { cards.reduce(0) { $0 + $1.points } }

    // MARK: - 対局の決着

    /// 誰かが `targetScore` に届いたか（手の終わりにだけ見る）。
    public static func isMatchOver(totals: [Int]) -> Bool { totals.contains { $0 >= targetScore } }

    /// 合計の**少ない順**に並べた順位（同点はプレイヤー番号順）。
    public static func ranking(totals: [Int]) -> [Int] {
        totals.indices.sorted { (totals[$0], $0) < (totals[$1], $1) }
    }

    /// `player` の順位（0 始まり）。自分より**少ない**人の数なので、同点の人どうしは同じ順位になる。
    public static func place(of player: Int, totals: [Int]) -> Int {
        totals.filter { $0 < totals[player] }.count
    }
}
