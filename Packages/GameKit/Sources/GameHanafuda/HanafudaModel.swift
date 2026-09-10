import Foundation
import Observation
import Core

// MARK: - 参加者

public enum HanafudaPlayer: Int, Codable, Sendable, Equatable, CaseIterable {
    case human = 0
    case cpu = 1

    public var other: HanafudaPlayer { self == .human ? .cpu : .human }

    public var label: String { self == .human ? "あなた" : "CPU" }
}

// MARK: - 画面の状態

public enum HanafudaPhase: String, Codable, Sendable, Equatable {
    /// 開始前（設定シート表示中）。
    case idle
    /// 対局中。
    case playing
    /// 役ができたので「こいこい / あがり」を選ぶ。
    case koiKoiPrompt
    /// 1 局の決着。
    case roundResult
    /// 全局が終わって試合の決着。
    case matchResult
}

/// 場札を 2 枚から選ぶ必要があるときの保留状態。
public struct HanafudaSelection: Equatable, Sendable, Codable {
    /// どこから出た札か。
    public enum Source: String, Codable, Sendable, Equatable {
        case hand, deck
    }
    public let source: Source
    public let card: HanafudaCard
    public let candidates: [HanafudaCard]

    public init(source: Source, card: HanafudaCard, candidates: [HanafudaCard]) {
        self.source = source
        self.card = card
        self.candidates = candidates
    }
}

/// 1 局の決着。
public struct HanafudaRoundResult: Equatable, Sendable, Codable {
    /// 勝者。流局は nil。
    public let winner: HanafudaPlayer?
    public let hits: [HanafudaYakuHit]
    /// 役の合計文数（倍率をかける前）。
    public let basePoints: Int
    /// 倍率をかけた後の獲得文数。
    public let score: Int
    /// 倍率の内訳（「7文以上で2倍」など）。
    public let reasons: [String]

    public init(
        winner: HanafudaPlayer?, hits: [HanafudaYakuHit],
        basePoints: Int, score: Int, reasons: [String]
    ) {
        self.winner = winner
        self.hits = hits
        self.basePoints = basePoints
        self.score = score
        self.reasons = reasons
    }

    /// 流局（誰もあがらずに手札が尽きた）。
    public static let drawn = HanafudaRoundResult(
        winner: nil, hits: [], basePoints: 0, score: 0, reasons: []
    )
}

// MARK: - スナップショット

struct HanafudaSnapshot: Codable {
    let options: HanafudaOptions
    let round: Int
    let dealer: HanafudaPlayer
    let turn: HanafudaPlayer
    let hands: [[HanafudaCard]]
    let captured: [[HanafudaCard]]
    let field: [HanafudaCard]
    let deck: [HanafudaCard]
    let claimed: [Int]
    let koiKoiCounts: [Int]
    let totals: [Int]
    let phase: HanafudaPhase
    let selection: HanafudaSelection?
    let drawnCard: HanafudaCard?
    let roundResult: HanafudaRoundResult?
    /// 直近の出来事（画面の 1 行メッセージ）。旧データには無いので optional。
    let message: String?
}

// MARK: - Model

/// 花札こいこい（CPU との一騎打ち・#495）。
///
/// ルール判定は `HanafudaRules` / `HanafudaScoring`、CPU は `HanafudaAI`（いずれも純粋関数）に
/// 寄せ、この型は**進行・永続化・演出**だけを持つ。
@MainActor
@Observable
public final class HanafudaModel {

    // MARK: 公開状態

    public private(set) var options = HanafudaOptions()
    /// 何局目か（1 始まり）。
    public private(set) var round = 0
    /// 親。初回は乱数で決め、以降は前局の勝者が継ぐ（流局は続投）。
    public private(set) var dealer: HanafudaPlayer = .human
    public private(set) var turn: HanafudaPlayer = .human
    public private(set) var humanHand: [HanafudaCard] = []
    public private(set) var cpuHand: [HanafudaCard] = []
    public private(set) var field: [HanafudaCard] = []
    public private(set) var deck: [HanafudaCard] = []
    public private(set) var humanCaptured: [HanafudaCard] = []
    public private(set) var cpuCaptured: [HanafudaCard] = []
    /// こいこいを宣言した時点の文数。ここを超えないと「あがる」を選べない。
    public private(set) var humanClaimed = 0
    public private(set) var cpuClaimed = 0
    /// こいこいの宣言回数（こいこい返しの判定に使う）。
    public private(set) var humanKoiKoiCount = 0
    public private(set) var cpuKoiKoiCount = 0
    /// 試合の累計文数。
    public private(set) var humanTotal = 0
    public private(set) var cpuTotal = 0
    public private(set) var phase: HanafudaPhase = .idle
    /// 場札を選ぶ必要があるときの保留（人間の手番のみ）。
    public private(set) var selection: HanafudaSelection?
    /// 山札からめくって場に見えている札（演出用。合わせ処理が終わると nil に戻る）。
    public private(set) var drawnCard: HanafudaCard?
    public private(set) var roundResult: HanafudaRoundResult?
    /// 画面に 1 行出す直近の出来事。
    public private(set) var message = ""
    /// 直近の決着で確定した自己ベスト（#115）。
    public private(set) var recordResult: RecordResult?

    // MARK: 内部

    public nonisolated static let gameID = "hanafuda"
    private let services: GameServices?
    private let cpuDelay: Duration
    private var rng: HanafudaRandom
    /// CPU の手番が二重に走らないようにする門番。テストが開始を待ち合わせるので internal。
    var isRunningCPUTurn = false
    /// 新規対局の通し番号（`.task(id:)` の再起動に使う・`AITurnKey`）。
    public private(set) var gameSerial = 0
    /// その局で消化した手番数。単調に増えるので `.task(id:)` のキーに使える。
    public private(set) var turnCount = 0

    public init(
        services: GameServices? = nil,
        cpuDelay: Duration = .milliseconds(700),
        seed: UInt64? = nil
    ) {
        self.services = services
        self.cpuDelay = cpuDelay
        self.rng = HanafudaRandom(seed: seed ?? UInt64.random(in: 0..<UInt64.max))
        if let snap = services?.snapshots.load(HanafudaSnapshot.self, for: Self.gameID),
           let restored = Self.validate(snap) {
            apply(restored)
        }
    }

    // MARK: - 復元

    /// 壊れたスナップショットを弾く（#520 と同じ姿勢）。
    ///
    /// 花札は**48 枚がちょうど 1 枚ずつどこかに在る**ことがルールの前提なので、
    /// 手札 + 取り札 + 場 + 山 + めくり札の重複と欠けをここで見る。
    /// 通らなかったら復元せず新規対局として始める（クラッシュさせない）。
    static func validate(_ snap: HanafudaSnapshot) -> HanafudaSnapshot? {
        guard snap.hands.count == 2, snap.captured.count == 2,
              snap.claimed.count == 2, snap.koiKoiCounts.count == 2, snap.totals.count == 2
        else { return nil }
        var all: [HanafudaCard] = snap.field + snap.deck
        all += snap.hands.flatMap { $0 }
        all += snap.captured.flatMap { $0 }
        if let drawn = snap.drawnCard { all.append(drawn) }
        guard all.count == HanafudaCard.deckSize,
              Set(all.map(\.id)).count == HanafudaCard.deckSize,
              all.allSatisfy({ (0..<HanafudaCard.deckSize).contains($0.id) })
        else { return nil }
        guard snap.round >= 1, snap.round <= snap.options.rounds,
              snap.claimed.allSatisfy({ $0 >= 0 }),
              snap.koiKoiCounts.allSatisfy({ $0 >= 0 }),
              snap.totals.allSatisfy({ $0 >= 0 })
        else { return nil }
        // 選択待ちの候補は場に在る札でなければならない。
        if let selection = snap.selection {
            let fieldIDs = Set(snap.field.map(\.id))
            guard !selection.candidates.isEmpty,
                  selection.candidates.allSatisfy({ fieldIDs.contains($0.id) })
            else { return nil }
            // 出どころと札の在り処も合っていなければならない。合っていないと復元後の
            // `chooseFieldCard` が元の場所に残ったままの札を取り札へ足し、同じ札が 2 枚になる。
            switch selection.source {
            case .deck:
                guard snap.drawnCard?.id == selection.card.id else { return nil }
            case .hand:
                // 選択待ちに入れるのは人間の手番だけなので、札は人間の手札に在るはず。
                guard snap.hands[0].contains(where: { $0.id == selection.card.id }) else { return nil }
            }
        }
        return snap
    }

    private func apply(_ snap: HanafudaSnapshot) {
        options = snap.options
        round = snap.round
        dealer = snap.dealer
        turn = snap.turn
        humanHand = snap.hands[0]
        cpuHand = snap.hands[1]
        humanCaptured = snap.captured[0]
        cpuCaptured = snap.captured[1]
        field = snap.field
        deck = snap.deck
        humanClaimed = snap.claimed[0]
        cpuClaimed = snap.claimed[1]
        humanKoiKoiCount = snap.koiKoiCounts[0]
        cpuKoiKoiCount = snap.koiKoiCounts[1]
        humanTotal = snap.totals[0]
        cpuTotal = snap.totals[1]
        phase = snap.phase
        selection = snap.selection
        drawnCard = snap.drawnCard
        roundResult = snap.roundResult
        message = snap.message ?? ""
    }

    private func save() {
        guard phase != .idle else { return }
        let snap = HanafudaSnapshot(
            options: options, round: round, dealer: dealer, turn: turn,
            hands: [humanHand, cpuHand], captured: [humanCaptured, cpuCaptured],
            field: field, deck: deck,
            claimed: [humanClaimed, cpuClaimed],
            koiKoiCounts: [humanKoiKoiCount, cpuKoiKoiCount],
            totals: [humanTotal, cpuTotal],
            phase: phase, selection: selection, drawnCard: drawnCard,
            roundResult: roundResult, message: message
        )
        try? services?.snapshots.save(snap, for: Self.gameID)
    }

    // MARK: - 試合の開始

    /// 設定を確定して試合を始める。
    public func startMatch(options: HanafudaOptions) {
        self.options = options
        humanTotal = 0
        cpuTotal = 0
        // 親決め。実物は札を引き合うが、結果は五分なのでそのまま乱数で決める。
        dealer = (rng.next() % 2 == 0) ? .human : .cpu
        round = 0
        services?.gameDidStart(gameID: Self.gameID, level: options.difficulty.analyticsLevel)
        startRound()
    }

    /// 次の局を配る。
    public func startRound() {
        round += 1
        gameSerial += 1
        let deal = HanafudaRules.deal(using: &rng)
        // 親が 8 枚・子が 8 枚。親から打ち始める。
        if dealer == .human {
            humanHand = deal.dealerHand.sorted()
            cpuHand = deal.opponentHand
        } else {
            cpuHand = deal.dealerHand
            humanHand = deal.opponentHand.sorted()
        }
        field = deal.field.sorted()
        deck = deal.deck
        humanCaptured = []
        cpuCaptured = []
        humanClaimed = 0
        cpuClaimed = 0
        humanKoiKoiCount = 0
        cpuKoiKoiCount = 0
        selection = nil
        drawnCard = nil
        roundResult = nil
        recordResult = nil
        turnCount = 0
        turn = dealer
        phase = .playing
        message = "\(round)局目・親は\(dealer.label)"
        services?.feedback.impact(.medium)
        save()
    }

    // MARK: - 人間の手番

    /// その札をいま出せるか。
    public func canPlay(_ card: HanafudaCard) -> Bool {
        phase == .playing && turn == .human && selection == nil && humanHand.contains(card)
    }

    /// 手札から 1 枚出す。場に同月が 2 枚あるときは選択待ちに入る。
    public func play(_ card: HanafudaCard) {
        guard canPlay(card) else { return }
        let outcome = HanafudaRules.outcome(playing: card, field: field)
        if case .mustChoose(let candidates) = outcome {
            selection = HanafudaSelection(source: .hand, card: card, candidates: candidates)
            message = "合わせる札を選んでください"
            services?.feedback.impact(.light)
            save()
            return
        }
        applyHandPlay(card, chosen: nil, for: .human)
    }

    /// 選択待ちの場札を確定する。
    public func chooseFieldCard(_ target: HanafudaCard) {
        guard let selection, selection.candidates.contains(target) else { return }
        self.selection = nil
        switch selection.source {
        case .hand:
            applyHandPlay(selection.card, chosen: target, for: .human)
        case .deck:
            applyDraw(selection.card, chosen: target, for: .human)
            finishTurn(for: .human)
        }
    }

    /// 手札の 1 枚を場に適用し、続けて山札をめくる。
    private func applyHandPlay(_ card: HanafudaCard, chosen: HanafudaCard?, for player: HanafudaPlayer) {
        removeFromHand(card, of: player)
        // 札が場に出た = 捨てたら途中離脱として数える局面（#500）。
        services?.gameDidProgress(gameID: Self.gameID)
        let result = HanafudaRules.resolve(playing: card, field: field, chosen: chosen)
        field = result.field.sorted()
        capture(result.captured, for: player)
        message = result.captured.isEmpty
            ? "\(player.label)は\(card.name)を場に出した"
            : "\(player.label)が\(card.name)で\(result.captured.count)枚取った"
        services?.feedback.impact(result.captured.isEmpty ? .light : .rigid)
        drawFromDeck(for: player)
    }

    /// 山札を 1 枚めくって合わせる。選択が要るのは人間の手番だけで、CPU は自動で決める。
    private func drawFromDeck(for player: HanafudaPlayer) {
        guard !deck.isEmpty else {
            drawnCard = nil
            finishTurn(for: player)
            return
        }
        let card = deck.removeFirst()
        drawnCard = card
        let outcome = HanafudaRules.outcome(playing: card, field: field)
        if case .mustChoose(let candidates) = outcome, player == .human {
            selection = HanafudaSelection(source: .deck, card: card, candidates: candidates)
            message = "めくり札「\(card.name)」に合わせる札を選んでください"
            save()
            return
        }
        let chosen: HanafudaCard? = {
            if case .mustChoose(let candidates) = outcome {
                // CPU は評価の高いほうを取る。
                return candidates.max { lhs, rhs in
                    HanafudaAI.cardWeight(lhs) < HanafudaAI.cardWeight(rhs)
                }
            }
            return nil
        }()
        applyDraw(card, chosen: chosen, for: player)
        finishTurn(for: player)
    }

    private func applyDraw(_ card: HanafudaCard, chosen: HanafudaCard?, for player: HanafudaPlayer) {
        let result = HanafudaRules.resolve(playing: card, field: field, chosen: chosen)
        field = result.field.sorted()
        capture(result.captured, for: player)
        if !result.captured.isEmpty {
            message = "めくり札「\(card.name)」で\(result.captured.count)枚取った"
            services?.feedback.impact(.rigid)
        }
        drawnCard = nil
    }

    /// 1 手番の締め。役ができていれば「こいこい / あがり」へ、無ければ手番を渡す。
    private func finishTurn(for player: HanafudaPlayer) {
        let points = points(of: player)
        let claimed = claimedPoints(of: player)
        if points > claimed {
            let handCount = hand(of: player).count
            let canContinue = HanafudaRules.canDeclareKoiKoi(
                handCountAfterTurn: handCount, deckCount: deck.count
            )
            if !canContinue {
                // 続けられないので自動的にあがり。
                endRound(winner: player)
                return
            }
            if player == .human {
                phase = .koiKoiPrompt
                message = "役ができました（\(points)文）"
                services?.feedback.notify(.success)
                save()
                return
            }
            let koi = HanafudaAI.shouldKoiKoi(
                myPoints: points,
                opponentPoints: self.points(of: player.other),
                handCount: handCount,
                deckCount: deck.count,
                difficulty: options.difficulty
            )
            if koi {
                declareKoiKoi(for: player)
            } else {
                endRound(winner: player)
                return
            }
        }
        passTurn(from: player)
    }

    private func passTurn(from player: HanafudaPlayer) {
        turnCount += 1
        // どちらの手札も尽きたら流局。
        if humanHand.isEmpty && cpuHand.isEmpty {
            endRound(winner: nil)
            return
        }
        turn = player.other
        phase = .playing
        save()
    }

    // MARK: - こいこい / あがり

    /// 人間が「こいこい」を選んだ。
    public func declareKoiKoi() {
        guard phase == .koiKoiPrompt else { return }
        declareKoiKoi(for: .human)
        passTurn(from: .human)
    }

    /// 人間が「あがり」を選んだ。
    public func declareStop() {
        guard phase == .koiKoiPrompt else { return }
        endRound(winner: .human)
    }

    private func declareKoiKoi(for player: HanafudaPlayer) {
        let points = points(of: player)
        switch player {
        case .human:
            humanClaimed = points
            humanKoiKoiCount += 1
        case .cpu:
            cpuClaimed = points
            cpuKoiKoiCount += 1
        }
        message = "\(player.label)がこいこい！（\(points)文）"
        services?.feedback.notify(.warning)
    }

    // MARK: - 局の決着

    private func endRound(winner: HanafudaPlayer?) {
        selection = nil
        drawnCard = nil
        guard let winner else {
            roundResult = .drawn
            message = "流局。だれもあがれませんでした"
            phase = .roundResult
            services?.feedback.notify(.warning)
            save()
            return
        }
        let hits = HanafudaScoring.yaku(for: captured(of: winner), options: options)
        let base = hits.reduce(0) { $0 + $1.points }
        let opponentKoiKoi = koiKoiCount(of: winner.other) > 0
        let score = HanafudaScoring.finalScore(base: base, opponentDeclaredKoiKoi: opponentKoiKoi)
        let reasons = HanafudaScoring.multiplierReasons(base: base, opponentDeclaredKoiKoi: opponentKoiKoi)
        roundResult = HanafudaRoundResult(
            winner: winner, hits: hits, basePoints: base, score: score, reasons: reasons
        )
        switch winner {
        case .human: humanTotal += score
        case .cpu:   cpuTotal += score
        }
        // 勝った側が次の親を継ぐ。
        dealer = winner
        message = "\(winner.label)のあがり！ \(score)文"
        phase = .roundResult
        services?.feedback.notify(winner == .human ? .success : .error)
        save()
    }

    /// 次の局へ進む（局結果の画面から呼ぶ）。全局終わっていれば試合の決着へ。
    public func advanceAfterRound() {
        guard phase == .roundResult else { return }
        if round >= options.rounds {
            finishMatch()
        } else {
            startRound()
        }
    }

    private func finishMatch() {
        phase = .matchResult
        let outcome: GameOutcome = {
            if humanTotal > cpuTotal { return .win }
            if humanTotal < cpuTotal { return .loss }
            return .draw
        }()
        message = {
            switch outcome {
            case .win:  return "あなたの勝ち！ \(humanTotal)文 対 \(cpuTotal)文"
            case .loss: return "CPUの勝ち。\(humanTotal)文 対 \(cpuTotal)文"
            case .draw: return "引き分け。\(humanTotal)文 対 \(cpuTotal)文"
            }
        }()
        // 見出しは**合計文数**（ポーカー・ブラックジャックと同じ流儀）。勝敗・連勝も
        // `PlayRecord` には残るが、1 行で出すのは文数のほうにする。
        // `GameCenterLeaderboard.score` は `.points` のときだけリーダーボードへ送るため、
        // 指標を `.winLoss` にすると #495 が求める「合計文数の送信」が黙って止まる。
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: outcome,
            score: GameScore(metric: .points, points: humanTotal)
        )
        services?.feedback.notify(outcome == .win ? .success : (outcome == .loss ? .error : .warning))
        services?.snapshots.clear(for: Self.gameID)
    }

    /// 試合の決着後に「もう一度」。設定は前回のものを引き継ぐ。
    public func restartMatch() {
        services?.gameDidRestart(gameID: Self.gameID, level: options.difficulty.analyticsLevel)
        let options = self.options
        humanTotal = 0
        cpuTotal = 0
        round = 0
        dealer = (rng.next() % 2 == 0) ? .human : .cpu
        self.options = options
        startRound()
    }

    /// 試合を投げる（ツールバーの「投了」）。負けとして記録する。
    public func resign() {
        guard phase == .playing || phase == .koiKoiPrompt || phase == .roundResult else { return }
        selection = nil
        drawnCard = nil
        phase = .matchResult
        message = "投了しました。\(humanTotal)文 対 \(cpuTotal)文"
        // 投了しても、それまでに稼いだ文数は正当な記録として残す。文数は打つほど増える
        // 一方なので、途中で降りて有利になることはない。
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: .loss,
            score: GameScore(metric: .points, points: humanTotal)
        )
        services?.feedback.notify(.error)
        services?.snapshots.clear(for: Self.gameID)
    }

    public var canResign: Bool {
        phase == .playing || phase == .koiKoiPrompt || phase == .roundResult
    }

    // MARK: - CPU

    /// CPU の手番なら 1 手進める。View の `.task(id:)` から呼ぶ。
    public func runCPUTurnIfNeeded() async {
        guard !isRunningCPUTurn else { return }
        isRunningCPUTurn = true
        defer { isRunningCPUTurn = false }
        while phase == .playing, turn == .cpu, !cpuHand.isEmpty {
            try? await Task.sleep(for: cpuDelay)
            guard phase == .playing, turn == .cpu else { return }
            stepCPU()
        }
    }

    /// CPU の 1 手。
    ///
    /// `runCPUTurnIfNeeded` の中身をそのまま切り出したもので、**待ち時間を挟まない**。
    /// `public` にしてあるのは、横断テスト（`AnalyticsTests` 等・別ターゲットなので
    /// `@testable` が使えない）が実時間を待たずに 1 試合を通すため
    /// （実時間で待つテストはフレークする・#289 の教訓）。
    public func stepCPU() {
        guard turn == .cpu, phase == .playing, !cpuHand.isEmpty else { return }
        guard let move = HanafudaAI.chooseMove(
            hand: cpuHand, field: field, captured: cpuCaptured, opponentCaptured: humanCaptured,
            options: options, difficulty: options.difficulty, using: &rng
        ) else { return }
        applyHandPlay(move.card, chosen: move.target, for: .cpu)
    }

    // MARK: - 参照

    public func hand(of player: HanafudaPlayer) -> [HanafudaCard] {
        player == .human ? humanHand : cpuHand
    }

    public func captured(of player: HanafudaPlayer) -> [HanafudaCard] {
        player == .human ? humanCaptured : cpuCaptured
    }

    /// いまの取り札で成立している文数。
    public func points(of player: HanafudaPlayer) -> Int {
        HanafudaScoring.points(for: captured(of: player), options: options)
    }

    public func yaku(of player: HanafudaPlayer) -> [HanafudaYakuHit] {
        HanafudaScoring.yaku(for: captured(of: player), options: options)
    }

    func claimedPoints(of player: HanafudaPlayer) -> Int {
        player == .human ? humanClaimed : cpuClaimed
    }

    func koiKoiCount(of player: HanafudaPlayer) -> Int {
        player == .human ? humanKoiKoiCount : cpuKoiKoiCount
    }

    /// 「あがる」を選べるか。こいこい宣言後は宣言時の文数を超えている必要がある。
    public var canStop: Bool {
        phase == .koiKoiPrompt
            && HanafudaRules.canStop(currentPoints: points(of: .human), claimedPoints: humanClaimed)
    }

    /// 人間の手番で、いま出すと場札が取れる手札。ヒント表示に使う。
    public func capturableHandCards() -> Set<Int> {
        Set(humanHand.filter { !HanafudaRules.matches(for: $0, in: field).isEmpty }.map(\.id))
    }

    public var isPlayerTurn: Bool { turn == .human && phase == .playing }

    /// CPU 起動トリガー（#82 と同じ組み合わせキー）。
    ///
    /// 手数には**単調に増える `turnCount`** を使う。取り札や場の枚数から導くと、
    /// 「場に捨てただけの手番」で場が増えて取り札が増えないなど値が行ったり来たりし、
    /// 同じキーに戻った瞬間に `.task(id:)` が再起動しなくなる。
    public var aiTurnKey: AITurnKey {
        AITurnKey(gameSerial: gameSerial, ply: turnCount)
    }

    // MARK: - 内部ヘルパ

    private func removeFromHand(_ card: HanafudaCard, of player: HanafudaPlayer) {
        switch player {
        case .human: humanHand.removeAll { $0.id == card.id }
        case .cpu:   cpuHand.removeAll { $0.id == card.id }
        }
    }

    private func capture(_ cards: [HanafudaCard], for player: HanafudaPlayer) {
        guard !cards.isEmpty else { return }
        switch player {
        case .human: humanCaptured = (humanCaptured + cards).sorted()
        case .cpu:   cpuCaptured = (cpuCaptured + cards).sorted()
        }
    }
}

// MARK: - 解析

extension HanafudaDifficulty {
    /// `game_start` の `level` に載せる段階（#500）。
    /// 写像はここ（Core を import するファイル）に置き、`HanafudaYaku` は解析を知らないままにする。
    var analyticsLevel: AnalyticsLevel {
        switch self {
        case .easy:   return .beginner
        case .normal: return .normal
        case .hard:   return .hard
        }
    }
}
