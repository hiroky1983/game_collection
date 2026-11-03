import Foundation

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

    /// 順位を `timeout` まで待って読む。待ちきれない・読めなければ nil を返す（待たせない）。
    @MainActor
    static func loadRank(timeout: Duration = rankTimeout, _ load: @escaping @MainActor () async -> Int?) async -> Int? {
        var finished = false
        var rank: Int?
        let loader = Task { @MainActor in
            rank = await load()
            finished = true
        }
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !finished, clock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        loader.cancel()
        return finished ? rank : nil
    }
}
