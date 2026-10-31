import Foundation
import Observation
import Core

// MARK: - 参加者

public enum HanafudaPlayer: Int, Codable, Sendable, Equatable, CaseIterable {
    case human = 0
    case cpu = 1

    public var other: HanafudaPlayer { self == .human ? .cpu : .human }

    /// 画面と読み上げに出す名前（表示言語で引く・#2166）。
    public var label: String { self == .human ? tr("あなた") : "CPU" }
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

/// CPU の 1 手番でしたこと（読み上げ用・#2280）。手札の 1 枚と山札のめくり札、こいこいの有無。
public struct HanafudaCPUTurnSummary: Equatable, Sendable {
    public var played: HanafudaCard
    public var playedCaptured: Int
    public var drawn: HanafudaCard?
    public var drawnCaptured = 0
    public var koiKoi = false
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

    /// 大きなあがりとして祝う文数（#2804）。五光（10 文）・四光（8 文）・猪鹿蝶（5 文＋α）の手を、カス（1 文）と見分ける。
    public static let bigScoreThreshold = 6

    /// 自分が大きくあがったか。見出しの拡大と強い触覚・効果音の条件。CPU のあがりでは祝わない。
    public var isBigHumanWin: Bool { winner == .human && score >= Self.bigScoreThreshold }

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
    /// 焼き込んだルール。鍵が無いデータは既定（`HanafudaOptions()`）に倒すので optional
    /// （1局=1RuleSet 規約 2・#827。非 optional だと鍵の欠けたデータのデコードが丸ごと失敗し、中断が黙って消える）。
    let options: HanafudaOptions?
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
    /// この試合で広告の延長（#1049）を使ったか。旧データには無いので optional（nil = 未使用）。
    /// 持ち回らないと、延長戦の途中で中断 → 再開したときに延長の権利が戻る。
    var hasExtendedMatch: Bool? = nil
    /// 終わった局までの、試合累計のこいこい宣言回数 [人間, CPU]（#2803）。旧データには無いので optional（nil = 0 回）。
    var bankedKoiKoiCounts: [Int]? = nil
}

// MARK: - Model

/// 花札こいこい（CPU との一騎打ち・#495）。
///
/// ルール判定は `HanafudaRules` / `HanafudaScoring`、CPU は `HanafudaAI`（いずれも純粋関数）に
/// 寄せ、この型は**進行・永続化・演出**だけを持つ。
@MainActor
@Observable
public final class HanafudaModel: AITurnGuarded {

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
    /// 終わった局までの試合累計こいこい宣言回数（局ごとに戻る `*KoiKoiCount` とは別。#2803）。
    private var bankedHumanKoiKoi = 0
    private var bankedCPUKoiKoi = 0
    /// この試合のこいこい宣言回数（試合結果カード用）。
    public var humanMatchKoiKoiCount: Int { bankedHumanKoiKoi + humanKoiKoiCount }
    public var cpuMatchKoiKoiCount: Int { bankedCPUKoiKoi + cpuKoiKoiCount }
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
    /// この試合で広告の延長（#1049）を使ったか。1 試合 1 回までの制限と、順位表から外す判定に使う。
    public private(set) var hasExtendedMatch = false
    /// この試合を投了で終えたか。文数の比較だけでは見出しを決められないため（#1496）。次の試合開始で戻す。
    public private(set) var wasResigned = false

    // MARK: 内部

    public nonisolated static let gameID = "hanafuda"
    private let services: GameServices?
    private let cpuDelay: Duration
    private var rng: HanafudaRandom
    /// CPU の手番が二重に走らないようにする門番。テストが開始を待ち合わせるので internal。
    var isRunningCPUTurn = false
    /// 札の動き（#3138）。モデルが確定させた 1 手番を、画面が順に見せる。
    let playback = HanafudaPlayback()
    private var scriptMoves: [HanafudaPlaybackMove] = []
    /// 新規対局の通し番号（`.task(id:)` の再起動に使う・`AITurnKey`）。
    public private(set) var gameSerial = 0
    /// その局で消化した手番数。単調に増えるので `.task(id:)` のキーに使える。
    public private(set) var turnCount = 0
    /// CPU の手番が終わって人間へ渡った直後の `aiTurnKey`（#2280）。View はこれと一致する鍵の変化だけを読み上げる。
    /// 手札を出し切る流局は `passTurn` を通るので読み上げる。あがりでの決着は `turnCount` が進まないので控えない（結果の札が出る）。
    public private(set) var lastCPUMoveKey: AITurnKey?
    /// `lastCPUMoveKey` の手番でしたこと。
    public private(set) var lastCPUTurn: HanafudaCPUTurnSummary?
    private var pendingCPUTurn: HanafudaCPUTurnSummary?

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
        // 延長の印が立つのは延長戦を配った後だけ（`extendMatchAfterAd` は印と配りを同時に行う）。
        // 印があるのに局が本来の局数以内だと、復元後の「試合の結果へ」が広告なしで延長戦を配ってしまう。
        let rounds = (snap.options ?? HanafudaOptions()).rounds
        let allowedRounds = (snap.hasExtendedMatch ?? false)
            ? (rounds + 1)...(rounds + Self.extensionRounds)
            : 1...rounds
        guard allowedRounds.contains(snap.round),
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
        playback.reset()
        options = snap.options ?? HanafudaOptions()
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
        let banked = snap.bankedKoiKoiCounts ?? []
        bankedHumanKoiKoi = banked.count == 2 ? max(banked[0], 0) : 0
        bankedCPUKoiKoi = banked.count == 2 ? max(banked[1], 0) : 0
        humanTotal = snap.totals[0]
        cpuTotal = snap.totals[1]
        phase = snap.phase
        selection = snap.selection
        drawnCard = snap.drawnCard
        roundResult = snap.roundResult
        message = snap.message ?? ""
        hasExtendedMatch = snap.hasExtendedMatch ?? false
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
            roundResult: roundResult, message: message,
            hasExtendedMatch: hasExtendedMatch,
            bankedKoiKoiCounts: [bankedHumanKoiKoi, bankedCPUKoiKoi]
        )
        try? services?.snapshots.save(snap, for: Self.gameID)
    }

    // MARK: - 試合の開始

    /// 設定を確定して試合を始める。
    public func startMatch(options: HanafudaOptions) {
        self.options = options
        humanTotal = 0
        cpuTotal = 0
        resetMatchKoiKoi()
        hasExtendedMatch = false
        // 親決め。実物は札を引き合うが、結果は五分なのでそのまま乱数で決める。
        dealer = (rng.next() % 2 == 0) ? .human : .cpu
        round = 0
        services?.gameDidStart(gameID: Self.gameID, level: options.difficulty.analyticsLevel)
        startRound()
    }

    /// 新しい試合の頭で、こいこいの累計を 0 に戻す。
    private func resetMatchKoiKoi() {
        bankedHumanKoiKoi = 0
        bankedCPUKoiKoi = 0
        humanKoiKoiCount = 0
        cpuKoiKoiCount = 0
    }

    /// 次の局を配る。
    public func startRound() {
        playback.reset()
        scriptMoves = []
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
        // 前の局のこいこいを試合累計へ繰り入れてから戻す。
        bankedHumanKoiKoi += humanKoiKoiCount
        bankedCPUKoiKoi += cpuKoiKoiCount
        humanKoiKoiCount = 0
        cpuKoiKoiCount = 0
        selection = nil
        drawnCard = nil
        roundResult = nil
        recordResult = nil
        turnCount = 0
        turn = dealer
        phase = .playing
        message = round > options.rounds
            ? tr("延長戦・親は%@", dealer.label)
            : tr("%1$lld局目・親は%2$@", round, dealer.label)
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
            message = tr("合わせる札を選んでください")
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
            applyDraw(selection.card, chosen: target, for: .human, fromReveal: true)
            emitScript(for: .human)
            finishTurn(for: .human)
        }
    }

    /// 手札の 1 枚を場に適用し、続けて山札をめくる。
    private func applyHandPlay(_ card: HanafudaCard, chosen: HanafudaCard?, for player: HanafudaPlayer) {
        removeFromHand(card, of: player)
        // 人間の札が場に出た = 捨てたら途中離脱として数える局面（#500）。CPU が親で先に出しただけでは数えない（#3000）。
        if player == .human { services?.gameDidProgress(gameID: Self.gameID) }
        let result = HanafudaRules.resolve(playing: card, field: field, chosen: chosen)
        field = result.field.sorted()
        capture(result.captured, for: player)
        scriptMoves = [HanafudaPlaybackMove(card: card, source: .hand, matched: Array(result.captured.dropFirst()), awaitsChoice: false)]
        if player == .cpu {
            pendingCPUTurn = HanafudaCPUTurnSummary(played: card, playedCaptured: result.captured.count)
        }
        switch (player, result.captured.isEmpty) {
        case (.human, true):
            message = tr("あなたは%@を場に出した", card.displayName)
        case (.cpu, true):
            message = tr("CPUは%@を場に出した", card.displayName)
        case (.human, false):
            message = tr("あなたが%1$@で%2$lld枚取った", card.displayName, result.captured.count)
        case (.cpu, false):
            message = tr("CPUが%1$@で%2$lld枚取った", card.displayName, result.captured.count)
        }
        // CPU の着手では鳴らさない（指を触れていない間に端末が振動するのを避ける・FeedbackCPUSilentTests）。
        if player == .human { services?.feedback.impact(result.captured.isEmpty ? .light : .rigid) }
        drawFromDeck(for: player)
    }

    /// 山札を 1 枚めくって合わせる。選択が要るのは人間の手番だけで、CPU は自動で決める。
    private func drawFromDeck(for player: HanafudaPlayer) {
        guard !deck.isEmpty else {
            drawnCard = nil
            emitScript(for: player)
            finishTurn(for: player)
            return
        }
        let card = deck.removeFirst()
        drawnCard = card
        let outcome = HanafudaRules.outcome(playing: card, field: field)
        if case .mustChoose(let candidates) = outcome, player == .human {
            selection = HanafudaSelection(source: .deck, card: card, candidates: candidates)
            message = tr("めくり札「%@」に合わせる札を選んでください", card.displayName)
            scriptMoves.append(HanafudaPlaybackMove(card: card, source: .deck, matched: [], awaitsChoice: true))
            emitScript(for: player)
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
        emitScript(for: player)
        finishTurn(for: player)
    }

    /// 確定した 1 手番（または選んだあとの残り）の動きを画面へ渡す。
    private func emitScript(for player: HanafudaPlayer) {
        let moves = scriptMoves
        scriptMoves = []
        playback.begin(HanafudaPlaybackScript(player: player, moves: moves, finalFieldIDs: Set(field.map(\.id))))
    }

    private func applyDraw(_ card: HanafudaCard, chosen: HanafudaCard?, for player: HanafudaPlayer,
                           fromReveal: Bool = false) {
        let result = HanafudaRules.resolve(playing: card, field: field, chosen: chosen)
        field = result.field.sorted()
        capture(result.captured, for: player)
        scriptMoves.append(HanafudaPlaybackMove(
            card: card, source: fromReveal ? .reveal : .deck,
            matched: Array(result.captured.dropFirst()), awaitsChoice: false
        ))
        if player == .cpu {
            pendingCPUTurn?.drawn = card
            pendingCPUTurn?.drawnCaptured = result.captured.count
        }
        if !result.captured.isEmpty {
            message = tr("めくり札「%1$@」で%2$lld枚取った", card.displayName, result.captured.count)
            if player == .human { services?.feedback.impact(.rigid) }
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
                message = tr("役ができました（%lld文）", points)
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
            pendingCPUTurn?.koiKoi = true
        }
        message = player == .human
            ? tr("あなたがこいこい！（%lld文）", points)
            : tr("CPUがこいこい！（%lld文）", points)
        services?.feedback.notify(.warning)
    }

    // MARK: - 局の決着

    private func endRound(winner: HanafudaPlayer?) {
        selection = nil
        drawnCard = nil
        guard let winner else {
            roundResult = .drawn
            message = tr("流局。だれもあがれませんでした")
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
        message = winner == .human
            ? tr("あなたのあがり！ %lld文", score)
            : tr("CPUのあがり！ %lld文", score)
        phase = .roundResult
        let big = roundResult?.isBigHumanWin == true
        services?.feedback.notify(big ? .milestone : (winner == .human ? .success : .error))
        save()
    }

    /// 次の局へ進む（局結果の画面から呼ぶ）。全局終わっていれば試合の決着へ。
    public func advanceAfterRound() {
        guard phase == .roundResult else { return }
        if round >= totalRounds {
            finishMatch()
        } else {
            startRound()
        }
    }

    // MARK: - 広告で延長（#1049）

    /// 延長で足す局数。
    static let extensionRounds = 1

    /// この試合の局数。延長を使ったら 1 局増える。
    public var totalRounds: Int {
        options.rounds + (hasExtendedMatch ? Self.extensionRounds : 0)
    }

    /// 最終局の決着で自分が負けていて、広告を見て 1 局延長できるか（#1049）。
    ///
    /// 試合の決着（`finishMatch`）の**前**、最終局の結果画面でだけ出す。決着後に出すと
    /// 勝敗の記録と `game_end` が済んだ試合を巻き戻すことになる。勝っている・引き分けでは出さない
    /// （続ける動機が無い）。1 試合 1 回まで。
    public var canExtendMatch: Bool {
        phase == .roundResult && round >= totalRounds
            && humanTotal < cpuTotal && !hasExtendedMatch
    }

    /// 広告を見終えたあと、試合を 1 局延長して延長戦を配る（#1049）。
    ///
    /// - Parameter serial: 広告を出す**前**に控えた `gameSerial`。広告のあいだに「試合の結果へ」「投了」で
    ///   試合が決着していたり、別の局に入れ替わっていたら延長を乗せずに false を返す（#729 の局ガード）。
    /// - Returns: 延長したか。
    public func extendMatchAfterAd(forGame serial: Int) -> Bool {
        guard serial == gameSerial, canExtendMatch else { return false }
        hasExtendedMatch = true
        services?.feedback.notify(.success)
        startRound()
        return true
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
            case .win:  return tr("あなたの勝ち！ %1$lld文 対 %2$lld文", humanTotal, cpuTotal)
            case .loss: return tr("CPUの勝ち。%1$lld文 対 %2$lld文", humanTotal, cpuTotal)
            case .draw: return tr("引き分け。%1$lld文 対 %2$lld文", humanTotal, cpuTotal)
            }
        }()
        // 見出しは**合計文数**（ポーカー・ブラックジャックと同じ流儀）。勝敗・連勝も
        // `PlayRecord` には残るが、1 行で出すのは文数のほうにする。
        // `GameCenterLeaderboard.score` は `.points` のときだけリーダーボードへ送るため、
        // 指標を `.winLoss` にすると #495 が求める「合計文数の送信」が黙って止まる。
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: outcome,
            score: matchScore
        )
        services?.feedback.notify(outcome == .win ? .success : (outcome == .loss ? .error : .warning))
        services?.snapshots.clear(for: Self.gameID)
    }

    /// 試合の決着後に「もう一度」。設定は前回のものを引き継ぐ。
    ///
    /// - Parameter difficulty: CPU の強さだけ変えて始め直すとき（リザルトの「階段」#722）に渡す。
    ///   試合の開始時に焼き込む設定の一部なので、`game_start` より前に差し替える。
    /// - Parameter options: 局数・酒の役・強さをまとめて選び直して始め直すとき（結果カードの「設定を変える」#2612）に渡す。
    public func restartMatch(difficulty: HanafudaDifficulty? = nil, options newOptions: HanafudaOptions? = nil) {
        if let newOptions { options = newOptions }
        if let difficulty { options.difficulty = difficulty }
        services?.gameDidRestart(gameID: Self.gameID, level: options.difficulty.analyticsLevel)
        let options = self.options
        humanTotal = 0
        cpuTotal = 0
        resetMatchKoiKoi()
        // 新しい試合なので延長の権利も戻る（#1049）。
        hasExtendedMatch = false
        wasResigned = false
        round = 0
        dealer = (rng.next() % 2 == 0) ? .human : .cpu
        self.options = options
        startRound()
    }

    /// 試合を投げる（ツールバーの「投了」）。負けとして記録する。
    public func resign() {
        guard phase == .playing || phase == .koiKoiPrompt || phase == .roundResult else { return }
        playback.reset()
        selection = nil
        drawnCard = nil
        phase = .matchResult
        wasResigned = true
        message = tr("投了しました。%1$lld文 対 %2$lld文", humanTotal, cpuTotal)
        // 投了しても、それまでに稼いだ文数は正当な記録として残す。文数は打つほど増える
        // 一方なので、途中で降りて有利になることはない。
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: .loss,
            score: matchScore
        )
        services?.feedback.notify(.error)
        services?.snapshots.clear(for: Self.gameID)
    }

    #if DEBUG
    /// 撮影・動作確認用（DEBUG 限定）: タップ無しで試合の結果画面まで進める
    /// （`-hanafudaMatchResult`・`-hanafudaMatchResultResigned`）。シミュレータは自動タップができないため（#1496）。
    public func debugForceMatchResult(resigned: Bool) {
        if phase == .idle { startMatch(options: options) }
        if resigned {
            resign()
        } else {
            humanTotal = 12
            cpuTotal = 8
            finishMatch()
        }
    }
    #endif

    public var canResign: Bool {
        phase == .playing || phase == .koiKoiPrompt || phase == .roundResult
    }

    /// 決着・投了で記録する成績。既定ルールは区分なし・順位表の対象のまま、分岐は別枠にする
    /// （1局=1RuleSet 規約 3・4・#827）。
    /// 広告で延長した試合は、ほかの救済（ポーカー・ブラックジャックの復活など）と同じく順位表へ送らない（#1049）。
    private var matchScore: GameScore {
        GameScore(
            metric: .points,
            points: humanTotal,
            variant: options.recordVariant,
            variantLabel: options.recordVariantLabel,
            isLeaderboardEligible: options.isLeaderboardEligible && !hasExtendedMatch
        )
    }

    // MARK: - CPU

    /// CPU の手番なら 1 手進める。View の `.task(id:)` から呼ぶ。
    public func runCPUTurnIfNeeded() async {
        // 多重起動防止。「先行タスクがいたら即リターン」にすると、下のキャンセル検知と
        // 組み合わさったとき「新タスクが即リターン → 先行タスクがキャンセルで抜ける」の順で
        // 走者不在になり CPU の手番で止まるため、大富豪（#287）・麻雀（#311）と同じく
        // 先行タスクの終了を待ってから引き継ぐ。待機中に自分もキャンセルされたら譲って抜ける（#726。#531 で共通化）。
        await withAITurnRunner(running: \.isRunningCPUTurn) {
            while phase == .playing, turn == .cpu, !cpuHand.isEmpty {
                // キャンセル済みなら無駄な sleep をしない（止めるのは下の sleep 後の判定で、ここは近道）。
                guard !Task.isCancelled else { return }
                // 画面を離れると `.task(id:)` がキャンセルされる。状態の guard だけでは通過してしまい、
                // 離れた後に CPU が待ち時間ゼロで打ち、その結果（役・あがり）が中断データに残る（#726）。
                guard await pauseCPUTurn(for: cpuDelay) else { return }
                // 人間の手の札がまだ動いているあいだは待つ（動きが重ならないように・#3138）。
                while playback.isBusy {
                    guard await pauseCPUTurn(for: .milliseconds(50)) else { return }
                }
                guard phase == .playing, turn == .cpu else { return }
                stepCPU()
            }
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
        let turnBefore = turnCount
        applyHandPlay(move.card, chosen: move.target, for: .cpu)
        // `passTurn` を通ったとき（`turnCount` が進んだとき）だけ控える。CPU があがって局が決着したときは進まない。
        if turnCount != turnBefore, let summary = pendingCPUTurn {
            lastCPUTurn = summary
            lastCPUMoveKey = aiTurnKey
        }
        pendingCPUTurn = nil
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
