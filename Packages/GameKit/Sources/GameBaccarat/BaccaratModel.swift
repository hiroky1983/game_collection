import Foundation
import Observation
import Core

// MARK: - Game Phase

public enum BaccaratPhase: String, Equatable, Sendable, Codable {
    /// 賭け先と額を選ぶところ。
    case betting
    /// 配り終えて決着したところ。
    case result
}

// MARK: - Snapshot

/// 中断データ（#1104 と同じ「賭け待ち」だけを持ち回る形）。
///
/// バカラは賭けた瞬間に決着まで進むので、**持ち回るべき「途中の局」が存在しない**。
/// 残すのは復活（#499）で戻したチップと「復活を使い切った」印だけで、これが無いと
/// 広告を見た直後にハブへ戻った人が報酬を丸ごと失い、しかも復活権まで戻ってしまう。
struct BaccaratSnapshot: Codable {
    let chips: Int
    /// チップ切れ復活（#499）をこのセッションで使い切ったか。
    /// **鍵は optional で足す**（規約。非 optional にすると形が変わったときに旧データの
    /// デコードが丸ごと失敗する）。nil は「まだ使っていない」に倒す。
    var hasRevivedThisSession: Bool? = nil
}

// MARK: - Model

@MainActor
@Observable
public final class BaccaratModel {
    public private(set) var playerHand: [BaccaratCard] = []
    public private(set) var bankerHand: [BaccaratCard] = []
    public private(set) var chips: Int = BaccaratModel.initialChips
    /// いま場に出ているベット額。決着すると 0 に戻る。
    public private(set) var bet: Int = 0
    /// 次に賭ける先。既定はプレイヤー。
    public private(set) var selectedBet: BaccaratBet = .player
    public private(set) var phase: BaccaratPhase = .betting
    public private(set) var outcome: BaccaratOutcome? = nil
    /// 直前の局のチップの増減。リザルトの表示と勝敗の振り分け（`reviewOutcome`）がここを見る。
    public private(set) var lastChipDelta: Int = 0
    public private(set) var sessionOver: Bool = false
    /// 直近のラウンドで確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    // MARK: チップ経済（ブラックジャック #499 / #523 / #656 と同じ作法）

    /// セッション開始時の持ちチップ。無料の「最初からやり直す」もこの額に戻す。
    static let initialChips = 1000

    /// 復活で戻るチップ。導線の文言もこの値から作る（数え違いを1か所に閉じる）。
    ///
    /// **無料のやり直し（`initialChips`）より必ず多くする**（#523 会長決裁 C 案）。同額以下にすると
    /// 復活は順位表にも載らないぶん無料のやり直しの完全な下位互換になり、広告を見る理由が無くなる。
    public static let reviveChips = 2000

    /// いちばん安いベット額。**ベットボタンの並びと破産判定の両方がここを見る**（#656）。
    /// 残高がこれに届かなければ、たとえ 0 枚でなくても打つ手が一つも無い＝そのセッションは終わり。
    ///
    /// バンカー勝ちは手数料 5% を引いた 0.95 倍払いなので端数が出る（50 枚なら +47 枚）。
    /// 「0 枚になるまで遊べる」という前提は成り立たないため、境目はこの値に置く。
    public static let minimumBet = 50

    /// このセッションで復活を既に使ったか。1 セッション 1 回までの制限に使う。
    private var hasRevivedThisSession = false

    /// セッションの通し番号。`restartSession()` で進む（#727）。
    /// 広告のロード中に「最初からやり直す」を押されると、同じ画面の中でセッションが入れ替わる。
    private var sessionSerial = 0

    /// チップ切れをリワード広告で 1 回だけ取り消せる状態か（#499）。
    public var canReviveAfterBust: Bool { sessionOver && !hasRevivedThisSession }

    /// 決着の種類（評価リクエスト #53 の判定用）。**賭けが当たったかどうか**で決める
    /// （プレイヤーの手が勝っても、バンカーに賭けていれば負け）。
    public var reviewOutcome: GameOutcome {
        if lastChipDelta > 0 { return .win }
        if lastChipDelta < 0 { return .loss }
        return .draw
    }

    /// 今のラウンドの成績。チップは精算後の残高で、これが「最高チップ数」の自己ベストになる。
    ///
    /// 復活（#499）を使ったセッションは順位表へ送らない（ブラックジャックと同じ思想）。
    /// **ローカルの自己ベストには残す**ので、分けるのは `variant` ではなく `isLeaderboardEligible`。
    private var currentScore: GameScore {
        GameScore(metric: .points, points: chips, isLeaderboardEligible: !hasRevivedThisSession)
    }

    public var playerTotal: Int { baccaratTotal(playerHand) }
    public var bankerTotal: Int { baccaratTotal(bankerHand) }

    private var deck: [BaccaratCard] = []
    let gameID = "baccarat"
    private let services: GameServices?
    private var seed: UInt64?

    /// - Parameter seed: テスト用の固定種。nil ならシステムの乱数を使う。
    public init(services: GameServices? = nil, seed: UInt64? = nil) {
        self.services = services
        self.seed = seed
        guard let snap = services?.snapshots.load(BaccaratSnapshot.self, for: gameID) else { return }
        chips = snap.chips
        // 旧データには鍵が無い。復活が存在しなかった頃の中断なので「未使用」に倒す。
        hasRevivedThisSession = snap.hasRevivedThisSession ?? false
        // 戻した残高で賭けられないなら、その場で終わりにする（#656）。
        checkSessionOver()
        // 戻った先は賭け待ちで「続き」ではないので、中断のお知らせ（#663）の対象から外す（#1145）。
        // 保存したプロセスの中の予約はメモリ上の集合なので、復元側でも伝えないと
        // アプリを起動し直してから開いて戻ったときだけ予約が残る。
        services?.gameDidRestoreFinished(gameID: gameID)
    }

    // MARK: - 中断データ

    /// 局を持ち回らないので、書き出すのは復活を使ったセッションの「賭け待ち」だけ（#1104）。
    private func persist() {
        guard hasRevivedThisSession, !sessionOver else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = BaccaratSnapshot(chips: chips, hasRevivedThisSession: true)
        try? services?.snapshots.save(snap, for: gameID)
        // 局を持たない中断データは「続きから戻れる」ではない（#1104）。伝えないと離脱が
        // 休憩として数えられ、続きの無い局に「途中のままです」のお知らせが予約される。
        services?.gameWillNotResume(gameID: gameID)
        services?.gameDidRestoreFinished(gameID: gameID)
    }

    // MARK: - Betting

    /// 賭け先を選ぶ。決着の表示中は受け付けない（次の局の賭け先は `nextRound()` の後に選ぶ）。
    public func select(_ bet: BaccaratBet) {
        guard phase == .betting, !sessionOver else { return }
        guard bet != selectedBet else { return }
        selectedBet = bet
        services?.feedback.impact(.light)
    }

    public func placeBet(_ amount: Int) {
        // 終わったセッションでは賭けられない。最小ベット未満も受け付けない（#656）。
        guard phase == .betting, !sessionOver, amount >= BaccaratModel.minimumBet else { return }
        guard chips >= amount else {
            services?.feedback.notify(.warning) // チップ不足でベットできない
            return
        }
        deal(bet: amount)
    }

    // MARK: - Deal

    private func deal(bet amount: Int) {
        deck = shuffledDeck()
        bet = amount
        // 1 ラウンド = 1 プレイ。決着が即決まるので、判定より前に数える（#158）。
        services?.gameDidRestart(gameID: gameID)
        // 配った時点でベットは確定済み。ここから捨てれば途中離脱として数える（#500）。
        services?.gameDidProgress(gameID: gameID)

        // 最初の 2 枚ずつ。山は切ったばかりなので、どの位置から配っても確率は変わらない。
        let initialPlayer = [drawCard(), drawCard()]
        let initialBanker = [drawCard(), drawCard()]
        // 3 枚目の候補は先に 2 枚引いておき、引き足しの判断は純関数に任せる
        // （使わなかったぶんは捨て札。配りごとに山を切り直すので次の局には残らない）。
        let hands = baccaratPlayOut(player: initialPlayer, banker: initialBanker,
                                    thirdCards: [drawCard(), drawCard()])
        playerHand = hands.player
        bankerHand = hands.banker
        services?.feedback.impact(.medium) // カードを配る
        resolve()
    }

    // MARK: - Result

    private func resolve() {
        let result = baccaratOutcome(player: playerHand, banker: bankerHand)
        let delta = baccaratChipDelta(bet: selectedBet, outcome: result, amount: bet)
        chips += delta
        lastChipDelta = delta
        outcome = result
        bet = 0
        phase = .result
        if delta > 0 {
            services?.feedback.notify(.success)
        } else if delta == 0 {
            services?.feedback.notify(.warning)  // タイで賭け金が戻った（勝ちでも負けでもない）
        } else {
            services?.feedback.notify(.error)
        }
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: reviewOutcome, score: currentScore)
        checkSessionOver()
        persist()
    }

    private func checkSessionOver() {
        // 0 枚ではなく「いちばん安いベットに届かない」で終わりにする（#656）。
        // 残高は端数で止まりうるので、`chips = 0` に丸めずそのまま見せる
        // ——チップバーの表示と食い違わせない。
        if chips < BaccaratModel.minimumBet {
            chips = max(0, chips)
            sessionOver = true
        }
    }

    // MARK: - Next Round

    public func nextRound() {
        guard !sessionOver else { return }
        outcome = nil
        clearHands()
        phase = .betting
    }

    private func clearHands() {
        playerHand = []
        bankerHand = []
        bet = 0
        lastChipDelta = 0
    }

    // MARK: - Reward Ad Recovery

    /// リワード広告を表示し、**視聴完了したときだけ**チップ切れから復活する（#499）。
    ///
    /// - **チップが尽きたときだけ**効く（いつでも押せる増量ボタンではない）。
    /// - **1 セッション 1 回まで**。中断を挟んでも回数は戻らない（印をスナップショットに持ち回る）。
    /// - 視聴中断・ロード失敗時は何も変更しない。
    /// - 広告のあいだに「最初からやり直す」でセッションが入れ替わっていたら適用しない（#727）。
    @discardableResult
    public func recoverChipsAfterAd() async -> Bool {
        await reviveAfterAd() == .granted
    }

    /// `recoverChipsAfterAd()` の本体。見終えたのに適用できなかったこと（`.unavailable`）を
    /// 視聴しなかったこと（`.notEarned`）と分けて返す（#727。画面のアラートを出し分けるため）。
    public func reviveAfterAd() async -> RewardedModelOutcome {
        guard canReviveAfterBust else { return .unavailable }
        let serialBeforeAd = sessionSerial
        // 画面の世代（#653）。広告のロード中にハブへ戻られたら、このモデルは捨てられている。
        let generationBeforeAd = services?.screenGeneration.current
        guard await services?.showRewardedAd(gameID: gameID, purpose: .revival) ?? true else { return .notEarned }
        guard services?.screenGeneration.current == generationBeforeAd else { return .unavailable }
        // 広告のロード〜視聴のあいだも画面は操作できる。「最初からやり直す」で新しいセッションが
        // 始まっていたら、そこへ復活が乗って復活権と順位表資格まで消える（#727）。
        guard sessionSerial == serialBeforeAd, canReviveAfterBust else { return .unavailable }
        hasRevivedThisSession = true
        chips = BaccaratModel.reviveChips
        sessionOver = false
        outcome = nil
        clearHands()
        phase = .betting
        // 賭ける前にハブへ戻られても報酬が消えないように、この時点で書き出す（#1104）。
        persist()
        return .granted
    }

    // MARK: - Restart

    public func restartSession() {
        recordResult = nil
        sessionSerial += 1
        chips = BaccaratModel.initialChips
        // 新しいセッションなので復活の回数も戻る（#499）。
        hasRevivedThisSession = false
        sessionOver = false
        outcome = nil
        clearHands()
        selectedBet = .player
        phase = .betting
        services?.snapshots.clear(for: gameID)
    }

    // MARK: - Deck

    private func makeDeck() -> [BaccaratCard] {
        var cards: [BaccaratCard] = []
        var id = 0
        for suit in BaccaratSuit.allCases {
            for rank in 1...13 {
                cards.append(BaccaratCard(id: id, suit: suit, rank: rank))
                id += 1
            }
        }
        return cards
    }

    /// 山札を切る。`seed` があるときは決定的に切り、次の配りが同じにならないよう種を進める。
    private func shuffledDeck() -> [BaccaratCard] {
        var cards = makeDeck()
        if let current = seed {
            var generator = BaccaratSeededGenerator(seed: current)
            cards.shuffle(using: &generator)
            seed = generator.next()
        } else {
            cards.shuffle()
        }
        return cards
    }

    private func drawCard() -> BaccaratCard {
        if deck.isEmpty { deck = shuffledDeck() }
        return deck.removeFirst()
    }
}

// MARK: - Seeded RNG

/// テスト用の決定的な乱数生成器（CoreEngine の `SplitMix64`・#1074）。本番は `seed` を渡さない。
typealias BaccaratSeededGenerator = SplitMix64
