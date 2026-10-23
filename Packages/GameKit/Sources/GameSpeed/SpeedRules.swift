import Foundation

/// 手札の 1 枚を台札のどちらかへ出す、という 1 手。
public struct SpeedPlacement: Equatable, Hashable, Sendable {
    public let cardID: Int
    /// 台札の番号（0 = 左・1 = 右）。
    public let pile: Int

    public init(cardID: Int, pile: Int) {
        self.cardID = cardID
        self.pile = pile
    }
}

/// スピード（#1323）のルールと CPU の判断。すべて純粋関数で、時間も状態も持たない。
///
/// 時間に関わる定数（反応の速さ・つまったあとの間・タイムの長さ）はここに置くが、
/// 実際に待つのは View の `.task` で、Model は「次にどれだけ待つか」を返すだけ（ぱっと暗算 #1321 と同じ形）。
public enum SpeedRules {
    /// 手札の枚数。
    public static let handSize = 4
    /// 台札の山の数。
    public static let pileCount = 2

    /// 「めくる」だけが続いて場が動かない回数がここに達したら引き分けにする。
    ///
    /// 両方の山札が尽きて台札を切り直しても出せる札が生まれない配りは理屈の上ではありうる
    /// （手札 1 枚に台札 1 枚、のような小さな輪）。実際の遊びでは「配り直し」で済ませるが、
    /// アプリでは終わりを決めないとめくり続けることになるので、上限を置いて引き分けに倒す。
    ///
    /// 20 のまま据え置く（会長 QA 2026-10-24 の計測）: 人間役 3 種 × CPU の速さ 5 条件・各 200 局で、引き分けは 0 局、
    /// いちばん長い連続めくりは 15 回だった。下げても局は短くならず、出せる札が出てくる直前で引き分けにする局が増えるだけ。
    /// 続けてめくるときの間は `stuckRepeatDelayMilliseconds` で縮めるので、20 回に届いても 12 秒ほどで終わる。
    public static let maxConsecutiveFlips = 20

    /// CPU が出せる札を持たないあいだ、場を見直す間隔。あなたが出すのを待っている状態。
    public static let scanInterval: Duration = .milliseconds(250)
    /// どちらも出せなくなってから、CPU が「めくる」までの間。あなたが先に「めくる」を押してもよい。
    public static let stuckDelayMilliseconds = 900
    /// めくった直後にまたどちらも出せないとき（続けてめくる 2 回目以降）の、CPU が「めくる」までの間。
    /// 見るのはめくって替わった台札 2 枚だけなので、1 回目より短くてよい。両方の山札が尽きたあとの切り直しが続く
    /// 場面（計測で最長 15 回）で、900ms ずつ待つと止まって見えるため（会長 QA 2026-10-24「後半がグダる」）。
    public static let stuckRepeatDelayMilliseconds = 600
    /// 自分の番に出せる札があるのに何もしないまま、この長さが過ぎたら、出せる手札と台札を光らせて案内する
    /// （会長 QA 2026-10-24「こっちが出せる手に気づかないとき、5 秒ぐらいでナビゲーションを出したい」）。
    /// 計測では CPU があなたを待っている時間が 1 局の 3〜5 割を占め、これが後半の止まって見える場面の残りの原因。
    /// 最後の操作か、場が動いた（誰かが出す・めくる）時刻から数える。
    public static let playableNavigationDelay: Duration = .seconds(5)
    /// タイム（広告救済）で CPU が休む長さ。
    public static let timeoutDuration: Duration = .seconds(8)
    /// タイムを出してよい CPU の残り枚数の上限（これ以下で、かつあなたより少ないとき）。
    public static let timeoutCPURemainingLimit = 8
    /// 設定の「ゆっくりモード」（アクション枠共通・`FeedbackPreference.actionSlowMode`）がオンのとき、
    /// CPU の反応と「めくる」までの間に掛ける倍率。チャリンコおじさんの時間の進み（0.68 倍）の逆数に近い値。
    public static let slowModeMultiplier = 1.5
    /// あなたが出せる札を持たないあいだ、CPU の反応の間に掛ける倍率（#2690）。待つしかないあなたの間延びを防ぐ。
    /// 両方つまったときの「めくる」までの間には掛けない。
    public static let humanStuckReactionRatio = 0.5
    /// 反応の速さに載せる揺らぎの幅（±この割合）。毎回同じ間で出すと機械的に見えるため。
    public static let reactionJitterRatio = 0.2

    // MARK: - 出せるか

    /// 数字が 1 つ違いか。A（1）と K（13）もつながる。
    public static func isAdjacent(_ a: Int, _ b: Int) -> Bool {
        let d = abs(a - b)
        return d == 1 || d == 12
    }

    /// `card` を `top` が見えている台札に重ねられるか。台札が空なら重ねられない（めくって置く）。
    public static func canPlay(_ card: SpeedCard, onto top: SpeedCard?) -> Bool {
        guard let top else { return false }
        return isAdjacent(card.rank, top.rank)
    }

    /// 手札から出せる (札, 台札) の組をすべて返す。手札の順 → 台札の順。
    public static func placements(hand: [SpeedCard], tops: [SpeedCard?]) -> [SpeedPlacement] {
        var result: [SpeedPlacement] = []
        for card in hand {
            for (index, top) in tops.enumerated() where canPlay(card, onto: top) {
                result.append(SpeedPlacement(cardID: card.id, pile: index))
            }
        }
        return result
    }

    public static func hasPlayable(hand: [SpeedCard], tops: [SpeedCard?]) -> Bool {
        hand.contains { card in tops.contains { canPlay(card, onto: $0) } }
    }

    // MARK: - CPU

    /// CPU の 1 手。出せる組が無ければ nil。
    ///
    /// 出したあとの局面で「自分が続けて出せる数 − 相手が出せる数」が最大の組を選ぶ
    /// （相手の出したい台札を塞ぐ手が自然に高くなる）。同点なら手札の順で先のもの。
    public static func cpuChoice(hand: [SpeedCard], tops: [SpeedCard?], opponentHand: [SpeedCard]) -> SpeedPlacement? {
        var best: (placement: SpeedPlacement, score: Int)?
        for placement in placements(hand: hand, tops: tops) {
            guard let card = hand.first(where: { $0.id == placement.cardID }) else { continue }
            var nextTops = tops
            nextTops[placement.pile] = card
            let remaining = hand.filter { $0.id != card.id }
            let score = placements(hand: remaining, tops: nextTops).count
                - placements(hand: opponentHand, tops: nextTops).count
            if best == nil || score > best!.score {
                best = (placement, score)
            }
        }
        return best?.placement
    }
}
