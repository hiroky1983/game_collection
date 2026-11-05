import Foundation
import Core
import CoreEngine

/// ステージをクリアしたあとの見せ方の順番（#3304）。
/// 猫全体のアニメーション（既存のくつろぐ演出。`CatPuzzleModel.showsClearCard` が真になった時点で終わっている）→
/// ライフが pt になる → ランキングの結果 → クリアのモーダル。ライフ → pt → ランキングが一続きで分かるようにする。
/// 各段はタップで早送りでき（`skip()`）、Reduce Motion では動きを省いて数字だけを短く見せる。
struct CatPuzzleClearFlow: Equatable {
    enum Step: Int, Comparable, CaseIterable {
        /// 残りライフ（♥）が 1 つずつ pt の数字に飛んで加算される。鍵の面は ×2 が掛かる。
        case lives
        /// 今日の合計 pt と、Game Center の今日の順位。
        case ranking
        /// 次の面へ／ステージを選ぶ／共有。
        case modal

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private(set) var step: Step = .lives

    /// 次の段へ進む（モーダルの次は無い）。
    mutating func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    /// タップによる早送り。今の段を飛ばして次の段へ。モーダルでは何もしない。
    mutating func skip() { advance() }

    var showsModal: Bool { step == .modal }

    // MARK: - 段ごとの時間

    /// ライフ 1 つが pt に飛ぶ間隔。
    static let lifeInterval: Duration = .milliseconds(450)
    /// 鍵の面の「×2」が掛かるまでの間。
    static let keyMultiplyDelay: Duration = .milliseconds(600)
    /// 段が終わってから次の段へ進むまでの余韻。
    static let hold: Duration = .milliseconds(900)
    /// 順位を読むのを待つ上限。これを過ぎたら合計 pt だけを出して進む。
    static let rankTimeout: Duration = .seconds(3)

    /// ライフが pt になる段の長さ（最後の余韻を含む）。Reduce Motion では余韻だけ。
    static func livesDuration(lives: Int, isKey: Bool, reduceMotion: Bool) -> Duration {
        if reduceMotion { return hold }
        var total = lifeInterval * max(0, lives) + hold
        if isKey { total += keyMultiplyDelay }
        return total
    }

    // MARK: - 加算の途中経過

    /// ライフが `flown` 個 pt に飛んだ時点の表示。`lives` は残りライフ、`isKey` は鍵の面。
    /// 戻り値は（まだ♥のままの数, 数字に加わったライフの数, ×2 が掛かった後か）。
    static func progress(lives: Int, flown: Int, isKey: Bool, multiplied: Bool) -> (hearts: Int, count: Int, multiplied: Bool) {
        let done = min(max(0, flown), max(0, lives))
        return (max(0, lives) - done, done, isKey && multiplied)
    }

    // MARK: - 順位の読み取り

    /// 順位の欄に出すもの。読み込み中・未サインイン・失敗は合計 pt だけ（順位は nil）。
    struct Standing: Equatable {
        let total: Int
        let rank: Int?
        /// 今日の順位が上位 3 位か（翌日の特典・#3256 の予告を添える）。
        var isTop3: Bool { rank.map { (1...3).contains($0) } ?? false }
    }

    /// 順位の欄に出すもの（#3327）。送った後の順位表と、自分の行が上がる動き。
    struct RankingResult: Equatable {
        let board: GameCenterBoard
        /// 送る前の合計から送った後の順位への動き。記録が伸びていない・送る前の合計が読めないときは nil（静止の表）。
        let motion: RankingMotion?

        var rank: Int? { board.myRank }
        /// 抜いた人の数（「3 人抜き！」）。送る前の位置が表の外かもしれないとき（自分が表の最下段から始まり、
        /// 参加者が表より多い）は、数えきれないので 0 にして出さない。
        var passedCount: Int {
            guard let motion else { return 0 }
            let startsInsideTable = motion.from < motion.entries.count - 1 || board.participants <= board.rows.count
            return startsInsideTable ? motion.passedCount : 0
        }
        /// 表を出せるか。自分が上位の外・まだ載っていないときは false で、今までの 1 行の表示に戻す。
        var showsTable: Bool { board.rows.contains(where: \.isMe) }
        var isTop3: Bool { rank.map { (1...3).contains($0) } ?? false }
    }

    /// クリアのモーダルの「今日の合計 pt と順位」の行（#3329）。順位が読めなかった（未サインイン・失敗・時間切れ）ときは合計 pt だけ。
    static func todayLine(total: Int, rank: Int?, participants: Int?) -> String {
        guard let rank, let participants else { return tr("今日の合計 %lldpt", total) }
        return tr("今日の合計 %1$lldpt・今日 %2$lld 位 / %3$lld 人", total, rank, max(participants, rank))
    }

    /// 順位表に出す上位の人数。
    static let tableRows = 10

    /// 読んだ順位表から出すものを作る。`beforeTotal` はこのクリアで pt を足す前の今日の合計。表が読めなければ nil。
    static func result(board: GameCenterBoard?, beforeTotal: Int) -> RankingResult? {
        guard let board else { return nil }
        return RankingResult(board: board, motion: RankingPlan.motion(beforeScore: max(0, beforeTotal), after: board))
    }

    /// ランキングの段の長さ（読めたあと、モーダルへ進むまで）。入れ替えを流すときはその長さ + 余韻。
    static func rankingDuration(motion: RankingMotion?, reduceMotion: Bool) -> Duration {
        guard motion != nil, !reduceMotion else { return hold + .milliseconds(600) }
        return .seconds(RankingMotion.duration) + hold
    }

    /// 順位を `timeout` まで待って読む。待ちきれない・読めなければ nil を返す（待たせない）。
    @MainActor
    static func loadRank(timeout: Duration = rankTimeout, _ load: @escaping @MainActor () async -> Int?) async -> Int? {
        await loadWithTimeout(timeout: timeout, load)
    }

    @MainActor
    static func loadWithTimeout<Value: Sendable>(timeout: Duration = rankTimeout,
                                                 _ load: @escaping @MainActor () async -> Value?) async -> Value? {
        var finished = false
        var value: Value?
        let loader = Task { @MainActor in
            value = await load()
            finished = true
        }
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !finished, clock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        loader.cancel()
        return finished ? value : nil
    }
}
