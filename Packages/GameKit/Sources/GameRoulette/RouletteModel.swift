import Foundation
import Observation
import Core
import CoreEngine

// MARK: - Phase

public enum RoulettePhase: String, Codable, Sendable, Equatable {
    /// 盤面にチップを置いている。
    case betting
    /// ホイールが回っている（出目は決まっていて、止まるのを待っている）。
    case spinning
    /// 精算が済み、出目と収支を見せている。
    case result
}

// MARK: - Snapshot

struct RouletteSnapshot: Codable {
    let chips: Int
    let bets: [RouletteBet]
    let phase: RoulettePhase
    /// 回転中に中断したときの出目。復帰したら同じ出目で止める（引き直さない）。
    let winningNumber: Int?
    /// 直近の出目（新しい順）。
    let history: [Int]
    /// チップ切れ復活をこのセッションで使い切ったか。中断を挟んでも「1 セッション 1 回まで」を
    /// 守るために持ち回る（ブラックジャック #499 と同じ方式）。**旧データには鍵が無い**ので
    /// optional にする（非 optional にすると旧データのデコードが丸ごと失敗し、中断が黙って消える）。
    var hasRevivedThisSession: Bool? = nil
}

// MARK: - Model

/// ルーレット（#1318）。一人でハウス相手に仮想チップを賭ける。
///
/// 経済モデルはブラックジャック（#499・#523）と同じ: 1 セッション 1000 枚で始め、
/// 最小の賭け額に届かなくなったらセッション終了。リワード広告を見ると 1 セッション 1 回だけ
/// 2000 枚で復活できる。チップは現金・金銭的価値との交換を一切しない。
@MainActor
@Observable
public final class RouletteModel {
    public private(set) var chips: Int = RouletteModel.initialChips
    /// 盤面に置いた口（置いた順）。同じ場所へ何口でも置ける。
    public private(set) var bets: [RouletteBet] = []
    public private(set) var phase: RoulettePhase = .betting
    /// このスピンの出目。`spin()` の時点で決まり、`nextRound()` で消える。
    public private(set) var winningNumber: Int?
    /// 直近のスピンの精算。`result` のあいだだけ入る。
    public private(set) var lastSettlement: RouletteSettlement?
    /// 直近の出目（新しい順・最大 `historyLimit` 件）。
    public private(set) var history: [Int] = []
    public private(set) var sessionOver: Bool = false
    /// 直近のスピンで確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// いま盤面に置くチップの額。`chipOptions` のどれか。
    public var selectedChip: Int = RouletteModel.chipOptions[1]

    // MARK: 経済（ブラックジャック #499・#523 と同じ）

    /// セッション開始時の持ちチップ。
    static let initialChips = 1000
    /// 復活で戻るチップ。**無料のやり直し（`initialChips`）より必ず多くする**（#523 会長決裁 C 案。
    /// 広告を見る理由を「チップが増える」で作る）。
    public static let reviveChips = 2000
    /// 盤面に置けるチップの額。先頭が最小で、破産判定の境目にもなる。
    public static let chipOptions = [10, 50, 100, 500]
    /// いちばん安い賭け額。残高がこれに届かなければ打つ手が無い＝セッションの終わり。
    public static let minimumBet = chipOptions[0]
    /// 直近の出目を残す件数。
    public static let historyLimit = 10

    private var hasRevivedThisSession = false
    /// セッションの通し番号。`restartSession()` で進む（ブラックジャック #727 と同じ照合に使う）。
    private var sessionSerial = 0
    private var nextBetID = 0

    let gameID = "roulette"
    private let services: GameServices?
    /// テスト用の決定的な乱数。nil ならシステムの乱数を使う。
    private var generator: SplitMix64?

    /// ホイールが止まるまでの間。`.zero` なら待たずに精算する（テストの決定性のため）。
    private let spinInterval: Duration
    /// 回転を待っている `Task`。「結果まで進める」とセッションのやり直しで止める。
    private(set) var spinTask: Task<Void, Never>?

    /// - Parameters:
    ///   - seed: テスト用の固定種。nil ならシステムの乱数を使う。
    ///   - spinInterval: ホイールが止まるまでの間。画面は `RouletteMotion.spinInterval` を渡す。
    public init(services: GameServices? = nil, seed: UInt64? = nil, spinInterval: Duration = .zero) {
        self.services = services
        self.generator = seed.map { SplitMix64(seed: $0) }
        self.spinInterval = spinInterval
        if let snap = services?.snapshots.load(RouletteSnapshot.self, for: "roulette") {
            chips = snap.chips
            bets = snap.bets
            phase = snap.phase
            winningNumber = snap.winningNumber
            history = snap.history
            hasRevivedThisSession = snap.hasRevivedThisSession ?? false
            nextBetID = (bets.map(\.id).max() ?? -1) + 1
            // 精算済みの局は保存しないが、万一残っていても操作のしようがないので賭ける前に戻す。
            if phase == .result || (phase == .spinning && winningNumber == nil) {
                phase = .betting
                bets = []
                winningNumber = nil
            }
        }
        switch phase {
        case .spinning:
            // 回っている途中で中断していたら、同じ出目でもう一度回して止める（引き直さない）。
            runSpin()
        case .betting:
            // 賭ける前の局面で残高が足りなければ、その場で終わりにする（#656 と同じ理由）。
            checkSessionOver()
        case .result:
            break
        }
    }

    // MARK: - Persist

    /// 保存するのは「続きのある状態」だけ: 回転中（同じ出目で止め直す）と、置いた口が残る賭け中。
    /// 精算済み・口の無い賭け中は消す（ブラックジャックと同じく、ラウンドをまたぐ残高は持ち越さない）。
    /// 例外は復活（#523）直後で、広告を見た報酬を離脱で失わせないよう残高だけ残す（ポーカー #1104 と同じ）。
    private func persist() {
        switch phase {
        case .spinning:
            save()
        case .betting where !bets.isEmpty:
            save()
        case .betting where hasRevivedThisSession && !sessionOver:
            save()
            notifyRoundWaitingSnapshot()
        default:
            services?.snapshots.clear(for: gameID)
        }
    }

    private func save() {
        let snap = RouletteSnapshot(
            chips: chips,
            bets: bets,
            phase: phase,
            winningNumber: winningNumber,
            history: history,
            hasRevivedThisSession: hasRevivedThisSession
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    /// 局を持たない中断データ（復活直後・口が無い）を書いたことを、解析とお知らせへ伝える（#1104）。
    /// 伝えないと「途中のままです」のお知らせが続きの無い局に予約される。次のスピン
    /// （`gameDidRestart`）で元へ戻る。
    private func notifyRoundWaitingSnapshot() {
        services?.gameWillNotResume(gameID: gameID)
        services?.gameDidRestoreFinished(gameID: gameID)
    }

    // MARK: - Betting

    /// 場に出している総額。精算まで `chips` からは引かない（表示は「残高」のまま）。
    public var totalBet: Int { bets.reduce(0) { $0 + $1.amount } }

    /// まだ置ける額。
    public var availableChips: Int { chips - totalBet }

    /// `kind` に置いている合計。盤面のマスに載せる数字。
    public func amount(on kind: RouletteBetKind) -> Int {
        bets.reduce(0) { $0 + ($1.kind == kind ? $1.amount : 0) }
    }

    /// 賭けられる局面か（賭け中でセッションが終わっていない）。
    public var canBet: Bool { phase == .betting && !sessionOver }

    /// `kind` に `selectedChip` を 1 口置く。残高が足りなければ置かない。
    public func placeBet(_ kind: RouletteBetKind) {
        guard canBet else { return }
        let amount = selectedChip
        guard availableChips >= amount else {
            services?.feedback.notify(.warning) // チップ不足で置けない
            return
        }
        bets.append(RouletteBet(id: nextBetID, kind: kind, amount: amount))
        nextBetID += 1
        services?.feedback.impact(.light)
        persist()
    }

    /// 最後に置いた 1 口を外す。
    public func undoLastBet() {
        guard canBet, !bets.isEmpty else { return }
        bets.removeLast()
        services?.feedback.impact(.light)
        persist()
    }

    /// 置いた口を全部外す。
    public func clearBets() {
        guard canBet, !bets.isEmpty else { return }
        bets = []
        services?.feedback.impact(.light)
        persist()
    }

    // MARK: - Spin

    /// 回せる局面か（口が 1 つ以上ある賭け中）。
    public var canSpin: Bool { canBet && !bets.isEmpty }

    /// 出目を決めてホイールを回す。1 スピン = 1 プレイ（`gameDidFinish` もスピンごとに呼ぶ）。
    public func spin() {
        guard canSpin else { return }
        winningNumber = drawNumber()
        lastSettlement = nil
        phase = .spinning
        // 決着が数秒後に決まるゲームでも `game_start` が先に立つよう、精算より前に数える（#158）。
        services?.gameDidRestart(gameID: gameID)
        // 回した時点で賭けは確定済み。ここから捨てれば途中離脱として数える（#500）。
        services?.gameDidProgress(gameID: gameID)
        services?.feedback.impact(.medium) // ホイールを回す
        persist()
        runSpin()
    }

    private func runSpin() {
        guard spinInterval > .zero else {
            settle()
            return
        }
        let interval = spinInterval
        spinTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            // 「結果まで進める」・やり直しで止められたか、画面ごと捨てられた。
            guard !Task.isCancelled, let self, self.phase == .spinning else { return }
            self.spinTask = nil
            self.settle()
        }
    }

    /// 「結果まで進める」。回転を待たずに精算する。出目は回し始めた時点で決まっているので、
    /// 飛ばしても結果は変わらない。
    public func skipSpin() {
        guard phase == .spinning else { return }
        spinTask?.cancel()
        spinTask = nil
        settle()
    }

    private func drawNumber() -> Int {
        if generator != nil {
            return Int.random(in: RouletteWheel.numbers, using: &generator!)
        }
        return Int.random(in: RouletteWheel.numbers)
    }

    // MARK: - Settlement

    private func settle() {
        guard phase == .spinning, let number = winningNumber else { return }
        let settlement = rouletteSettlement(bets: bets, winningNumber: number)
        chips += settlement.net
        lastSettlement = settlement
        history.insert(number, at: 0)
        if history.count > RouletteModel.historyLimit {
            history.removeLast(history.count - RouletteModel.historyLimit)
        }
        phase = .result
        // 決着の触覚は収支で決める（当たった口があっても総額で負けていれば負けの音）。
        if settlement.net > 0 {
            services?.feedback.notify(.success)
        } else if settlement.net == 0 {
            services?.feedback.notify(.warning)
        } else {
            services?.feedback.notify(.error)
        }
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: reviewOutcome, score: currentScore)
        checkSessionOver()
        persist()
    }

    /// 決着の種類（評価リクエスト #53 の判定用）。収支ゼロは引き分け、負けは敗北として扱う。
    public var reviewOutcome: GameOutcome {
        guard let net = lastSettlement?.net else { return .loss }
        if net > 0 { return .win }
        if net == 0 { return .draw }
        return .loss
    }

    /// 今のスピンの成績。チップは精算後の残高で、これが「最高チップ数」の自己ベストになる。
    /// 復活を使ったセッションは順位表へ送らない（ブラックジャックと同じ思想。ローカルの自己ベストには残す）。
    private var currentScore: GameScore {
        GameScore(metric: .points, points: chips, isLeaderboardEligible: !hasRevivedThisSession)
    }

    private func checkSessionOver() {
        // 0 枚ではなく「いちばん安い賭けに届かない」で終わりにする（#656）。
        if chips < RouletteModel.minimumBet {
            chips = max(0, chips)
            sessionOver = true
        }
    }

    // MARK: - Next Round

    /// 盤面を空にして次のスピンへ。
    public func nextRound() {
        guard phase == .result, !sessionOver else { return }
        clearRound()
        persist()
    }

    /// 直前と同じ口を置き直して次のスピンへ。残高が足りなければ置ける口だけ置く。
    public func repeatLastBets() {
        guard phase == .result, !sessionOver else { return }
        let previous = bets
        clearRound()
        for bet in previous where availableChips >= bet.amount {
            bets.append(RouletteBet(id: nextBetID, kind: bet.kind, amount: bet.amount))
            nextBetID += 1
        }
        persist()
    }

    private func clearRound() {
        bets = []
        winningNumber = nil
        lastSettlement = nil
        phase = .betting
    }

    // MARK: - Reward Ad Recovery

    /// チップ切れをリワード広告で 1 回だけ取り消せる状態か。1 セッション 1 回まで。
    public var canReviveAfterBust: Bool { sessionOver && !hasRevivedThisSession }

    /// リワード広告を表示し、**視聴完了したときだけ**チップ切れから復活する。
    ///
    /// - **チップが尽きたときだけ**効く。まだ遊べる残高で呼んでも広告は出さない。
    /// - **1 セッション 1 回まで**。中断を挟んでも回数は戻らない。回数が戻るのは `restartSession()` だけ。
    /// - 視聴中断・ロード失敗時は何も変更せず `.notEarned` を返す。
    /// - 広告のあいだに「最初からやり直す」でセッションが入れ替わっていたら適用しない（#727 と同型）。
    /// - services 未注入時（プレビュー・テスト）は広告機構自体が無いため従来どおり回復させる。
    public func reviveAfterAd() async -> RewardedModelOutcome {
        guard canReviveAfterBust else { return .unavailable }
        let serialBeforeAd = sessionSerial
        // 画面の世代（#653）。広告のロード中にハブへ戻られたら、このモデルは捨てられている。
        let generationBeforeAd = services?.screenGeneration.current
        guard await services?.showRewardedAd(gameID: gameID, purpose: .revival) ?? true else { return .notEarned }
        guard services?.screenGeneration.current == generationBeforeAd else { return .unavailable }
        guard sessionSerial == serialBeforeAd, canReviveAfterBust else { return .unavailable }
        hasRevivedThisSession = true
        chips = RouletteModel.reviveChips
        sessionOver = false
        clearRound()
        // 次のスピンの前にハブへ戻られても報酬が消えないように、この時点で書き出す（#1104）。
        persist()
        return .granted
    }

    // MARK: - Restart

    public func restartSession() {
        spinTask?.cancel()
        spinTask = nil
        recordResult = nil
        sessionSerial += 1
        chips = RouletteModel.initialChips
        hasRevivedThisSession = false
        sessionOver = false
        history = []
        clearRound()
        services?.snapshots.clear(for: gameID)
    }
}
