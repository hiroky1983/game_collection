import Testing
import Foundation
import Core
@testable import GameSpeed

// MARK: - 1 局を時計を進めながら最後まで打つ計測器（会長 QA 2026-10-24「後半がグダる」）

/// 人間役の自動の打ち手。出せる札に気づくまでの間（揺らぎつき）と、たまの見落とし、「めくる」を押すまでの間を持つ。
struct SpeedPacingBot: Sendable {
    let name: String
    /// 出せる札に気づいてから出すまでの基準（ミリ秒）。
    let reactionMilliseconds: Int
    /// 反応に載せる揺らぎ（±この割合）。
    let jitter: Double
    /// 気づくたびに、この確率で見落としてさらに `overlookMilliseconds` 遅れる。
    let overlookChance: Double
    let overlookMilliseconds: Int
    /// どちらも出せなくなってから「めくる」を押すまで（CPU の 900ms より遅いので、ふだんは CPU がめくる）。
    let flipMilliseconds: Int
    /// 案内（`SpeedRules.playableNavigationDelay`）が光ったら 0.5 秒で気づく人か。見落としの遅れが案内で頭打ちになる。
    var seesNavigation = false

    static let quick = SpeedPacingBot(name: "素早い人", reactionMilliseconds: 1000, jitter: 0.3,
                                      overlookChance: 0, overlookMilliseconds: 0, flipMilliseconds: 1500)
    static let average = SpeedPacingBot(name: "ふつうの人", reactionMilliseconds: 1800, jitter: 0.3,
                                        overlookChance: 0.15, overlookMilliseconds: 4000, flipMilliseconds: 1500)
    static let overlooker = SpeedPacingBot(name: "見落とす人", reactionMilliseconds: 2500, jitter: 0.3,
                                           overlookChance: 0.35, overlookMilliseconds: 6000, flipMilliseconds: 1500)
    static let overlookerWithNavigation = SpeedPacingBot(name: "見落とす人（案内あり）", reactionMilliseconds: 2500, jitter: 0.3,
                                                         overlookChance: 0.35, overlookMilliseconds: 6000, flipMilliseconds: 1500,
                                                         seesNavigation: true)
}

/// 1 局の前半（どちらの山札もまだ残っている）・後半（どちらかの山札が一度でも尽きたあと）ごとの数え。
struct SpeedPacingHalf: Sendable {
    /// 経過（秒）。
    var seconds = 0.0
    /// 「どちらも出せず、めくる」の回数。
    var flips = 0
    /// どちらも出せず、めくるのを待っていた時間（秒）。
    var stuckSeconds = 0.0
    /// CPU は出せず、人間だけが出せる（CPU が人間を待っている）時間（秒）。
    var humanOnlySeconds = 0.0
    /// 上のうち、1 回の待ちが 3 秒を超えた回数（止まって見える）。
    var longHumanOnlyWaits = 0
    /// 台札を切り直して山札にした回数（どちらか一方でも 1 回）。
    var reshuffles = 0
    /// 札を出した回数（あなた + CPU）。
    var plays = 0
}

struct SpeedPacingGame: Sendable {
    var front = SpeedPacingHalf()
    var back = SpeedPacingHalf()
    var isDraw = false
    var humanWon = false
    /// 両方の山札が尽きていた時間（秒）。最後の山札が尽きてから決着までの終盤。
    var bothOutSeconds = 0.0
    /// 両方の山札が尽きていたあいだの「めくる」の回数。
    var bothOutFlips = 0
    /// 続けてめくった 2 回目以降の回数（めくった直後にまためくる）。
    var repeatFlips = 0
    /// 1 局でいちばん長く続いた「めくる」の回数。
    var maxFlipStreak = 0
    var total: Double { front.seconds + back.seconds }
}

/// 局を回す。CPU は Model の `nextCPUWait()` / `performCPUAction()` をそのまま使い、人間役は `bot` が打つ。
@MainActor
enum SpeedPacingSimulator {
    /// 小さな擬似乱数（人間役の揺らぎ用。Model の乱数と混ぜない）。
    struct Rand {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    static func play(seed: UInt64, level: SpeedLevel, bot: SpeedPacingBot) -> SpeedPacingGame {
        var current = Date(timeIntervalSince1970: 1_000_000)
        let model = SpeedModel(services: nil, seed: seed, now: { current },
                               hints: FeedbackPreference(key: "pacing.hints", defaults: .init(suiteName: "asobiba.speed.pacing")!, defaultValue: true),
                               slowMode: FeedbackPreference(key: "pacing.slow", defaults: .init(suiteName: "asobiba.speed.pacing")!, defaultValue: false))
        model.start(SpeedSettings(level: level))
        var rand = Rand(state: seed &* 0x9E3779B97F4A7C15 &+ 1)
        var game = SpeedPacingGame()
        var inBack = false
        var humanArmedAt: Date?
        var humanReaction = 0.0
        var stuckSeenAt: Date?
        var seenFlips = 0
        var humanOnlyRun = 0.0
        var steps = 0

        func half(_ body: (inout SpeedPacingHalf) -> Void) {
            if inBack { body(&game.back) } else { body(&game.front) }
        }

        while model.phase == .playing, steps < 200_000 {
            steps += 1
            if model.humanHasPlayable {
                if humanArmedAt == nil {
                    humanArmedAt = current
                    let jitter = (rand.next() * 2 - 1) * bot.jitter
                    humanReaction = Double(bot.reactionMilliseconds) * (1 + jitter) / 1000
                    if rand.next() < bot.overlookChance { humanReaction += Double(bot.overlookMilliseconds) / 1000 }
                    if bot.seesNavigation {
                        humanReaction = min(humanReaction, SpeedRules.playableNavigationDelay.asSeconds + 0.5)
                    }
                }
            } else {
                humanArmedAt = nil
            }
            // めくった直後にまたつまったら、新しい台札を見てから「めくる」を押す（前の待ちを持ち越さない）。
            if model.consecutiveFlips != seenFlips {
                seenFlips = model.consecutiveFlips
                stuckSeenAt = nil
            }
            if model.isStuck {
                if stuckSeenAt == nil { stuckSeenAt = current }
            } else {
                stuckSeenAt = nil
            }
            guard let cpuWait = model.nextCPUWait() else { break }
            let cpuDue = current.addingTimeInterval(cpuWait.asSeconds)
            let humanDue = humanArmedAt.map { $0.addingTimeInterval(humanReaction) }
            let flipDue = stuckSeenAt.map { $0.addingTimeInterval(Double(bot.flipMilliseconds) / 1000) }
            let humanNext = [humanDue, flipDue].compactMap { $0 }.min()
            let humanActs = humanNext.map { $0 <= cpuDue } ?? false
            let next = humanActs ? humanNext! : cpuDue
            let dt = max(0, next.timeIntervalSince(current))

            // 経過を局面の種類ごとに積む。
            let stuck = model.isStuck
            let humanOnly = !model.cpuHasPlayable && model.humanHasPlayable
            if model.humanStock.isEmpty && model.cpuStock.isEmpty { game.bothOutSeconds += dt }
            half { h in
                h.seconds += dt
                if stuck { h.stuckSeconds += dt }
                if humanOnly { h.humanOnlySeconds += dt }
            }
            if humanOnly {
                humanOnlyRun += dt
            } else if humanOnlyRun > 0 {
                if humanOnlyRun > 3 { half { $0.longHumanOnlyWaits += 1 } }
                humanOnlyRun = 0
            }
            current = next

            let flipsBefore = model.consecutiveFlips
            let stocksEmptyBefore = model.humanStock.isEmpty && model.cpuStock.isEmpty
            let piles = model.piles.map(\.count)
            if humanActs {
                if let humanDue, humanDue == humanNext,
                   let placement = SpeedRules.placements(hand: model.humanHand, tops: model.tops).first,
                   let card = model.humanHand.first(where: { $0.id == placement.cardID }) {
                    model.swipeCard(card, onto: placement.pile)
                    humanArmedAt = nil
                } else if model.canFlip {
                    model.flipStocks()
                }
            } else {
                model.performCPUAction()
            }
            let flipped = model.consecutiveFlips == flipsBefore + 1 || (model.isDraw && model.phase == .result)
            if flipped {
                half { $0.flips += 1 }
                if stocksEmptyBefore { game.bothOutFlips += 1 }
                if flipsBefore > 0 { game.repeatFlips += 1 }
                game.maxFlipStreak = max(game.maxFlipStreak, flipsBefore + 1)
                // 台札の枚数が減った = 台札を山札へ戻した（切り直した）。
                if model.phase == .playing, zip(model.piles.map(\.count), piles).contains(where: { $0 < $1 }) {
                    half { $0.reshuffles += 1 }
                }
            } else if model.piles.map(\.count) != piles, model.phase != .result || model.winner != nil {
                half { $0.plays += 1 }
            }
            if model.humanStock.isEmpty || model.cpuStock.isEmpty { inBack = true }
        }
        game.isDraw = model.isDraw
        game.humanWon = model.winner == .human
        return game
    }

    /// 同じ条件で `games` 局回した平均。
    struct Summary {
        let label: String
        let games: [SpeedPacingGame]
        func mean(_ f: (SpeedPacingGame) -> Double) -> Double { games.map(f).reduce(0, +) / Double(games.count) }
        var drawRate: Double { Double(games.filter(\.isDraw).count) / Double(games.count) }
        var humanWinRate: Double { Double(games.filter(\.humanWon).count) / Double(games.count) }
        var meanTotal: Double { mean(\.total) }
        var meanBack: Double { mean(\.back.seconds) }
    }

    static func run(level: SpeedLevel, bot: SpeedPacingBot, games: Int = 200) -> Summary {
        Summary(label: "\(bot.name)×CPU\(level.label)",
                games: (0..<games).map { play(seed: UInt64($0) &+ 7, level: level, bot: bot) })
    }

    static func table(_ summaries: [Summary]) -> String {
        func f(_ v: Double) -> String { String(format: "%.1f", v) }
        var rows = ["| 条件 | 1局(秒) | 前半(秒) | 後半(秒) | めくる 前/後 | めくる待ち 前/後(秒) | CPUが人を待つ 前/後(秒) | 3秒超の待ち 前/後 | 切り直し 前/後 | 両山札切れ後(秒) | 両山札切れ後のめくる | 続けてめくる(2回目以降) | 最長の連続めくり | 引き分け | 人の勝ち |",
                    "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for s in summaries {
            rows.append("| \(s.label) | \(f(s.meanTotal)) | \(f(s.mean(\.front.seconds))) | \(f(s.meanBack)) | "
                + "\(f(s.mean { Double($0.front.flips) })) / \(f(s.mean { Double($0.back.flips) })) | "
                + "\(f(s.mean(\.front.stuckSeconds))) / \(f(s.mean(\.back.stuckSeconds))) | "
                + "\(f(s.mean(\.front.humanOnlySeconds))) / \(f(s.mean(\.back.humanOnlySeconds))) | "
                + "\(f(s.mean { Double($0.front.longHumanOnlyWaits) })) / \(f(s.mean { Double($0.back.longHumanOnlyWaits) })) | "
                + "\(f(s.mean { Double($0.front.reshuffles) })) / \(f(s.mean { Double($0.back.reshuffles) })) | "
                + "\(f(s.mean(\.bothOutSeconds))) | \(f(s.mean { Double($0.bothOutFlips) })) | "
                + "\(f(s.mean { Double($0.repeatFlips) })) | \(s.games.map(\.maxFlipStreak).max() ?? 0) | "
                + "\(Int((s.drawRate * 100).rounded()))% | \(Int((s.humanWinRate * 100).rounded()))% |")
        }
        return rows.joined(separator: "\n")
    }
}

extension Duration {
    var asSeconds: Double {
        let (s, attos) = components
        return Double(s) + Double(attos) / 1e18
    }
}

@MainActor
@Suite("スピードの間延び（計測）")
struct SpeedPacingTests {
    @Test("人間役 3 種 × CPU の速さで 1 局を最後まで回し、前半・後半の内訳を表にする")
    func measure() {
        let summaries = [
            SpeedPacingSimulator.run(level: .normal, bot: .quick),
            SpeedPacingSimulator.run(level: .normal, bot: .average),
            SpeedPacingSimulator.run(level: .normal, bot: .overlooker),
            SpeedPacingSimulator.run(level: .normal, bot: .overlookerWithNavigation),
            SpeedPacingSimulator.run(level: .slow, bot: .average),
            SpeedPacingSimulator.run(level: .fast, bot: .average),
        ]
        print("SPEED_PACING_TABLE\n" + SpeedPacingSimulator.table(summaries))
        for s in summaries {
            #expect(s.games.allSatisfy { $0.total > 0 }, "\(s.label): 局が進んでいない")
            // 山札が尽きた人がめくらなくなったので、後半（どちらかの山札が尽きてから決着まで）は前半より短い。
            // 直す前は後半が前半の 1.7〜1.9 倍だった（PR の表）。
            #expect(s.meanBack < s.mean(\.front.seconds), "\(s.label): 後半が前半より長い（グダりの再発）")
            #expect(s.drawRate < 0.01, "\(s.label): 引き分けが多い")
        }
    }
}
