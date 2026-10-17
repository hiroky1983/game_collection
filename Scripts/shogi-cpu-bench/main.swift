import Foundation

// 将棋 CPU の計測（#1461）。`build.sh` で作った単体バイナリの引数:
//   nps                                  1 秒あたりに読める局面数（最適化ビルド・1 スレッド）
//   slip                                 最善手を外すときの浅い読みだけの所要時間（CPU 時間）
//   timing [positions]                   出荷の設定（実時間）で 1 手にかかる時間: 平均・最大・上限で打ち切られた割合
//   match <上> <上の確率> <下> <下の確率> <局面数>
//                                        上の段階と下の段階を、先後入れ替えで局面数×2 局。確率は 0...1 か shipped（出荷値）。
//                                        段階は novice / easy / normal / hard
//   random <段階> <確率|shipped> <局面数>  一様乱択の相手と先後入れ替えで局面数×2 局
//   hint <足す秒> <局面数>               毎手ヒントどおりに指す側（#1491）と「むずかしい」を先後入れ替えで局面数×2 局。
//                                        ヒントはアプリと同じ `BoardHintBudget.engineLevel`（むずかしい）の設定で、
//                                        考える時間だけ「むずかしい」+ 足す秒（局面数 = NPS × 秒）
//   hinttiming <足す秒> [positions]      ヒントの 1 手の実時間（時間で打ち切る出荷どおりの読み・考える時間 2 秒 + 足す秒）
// 対局は考える時間を局面数（nps × 秒）に置き換えて回す（`CPUBenchLadder.engine`）。
// 環境変数: SLIP_MARGIN（外したときに許す損の幅の差し替え）・NPS（match / random で使う 1 秒あたりの局面数）・PLIES（手数上限・既定 150）・CONCURRENCY（既定 6）・
// FIRST_OPENING（最初の開始局面の番号・既定 1。小分けにして続きから回すとき）・
// UPPER_DEPTH / LOWER_DEPTH（match の上・下の段の読む深さの上限の差し替え。既定は出荷値。#1566）・
// ONLY_SIDE（hint でヒント側を black=先手 / white=後手 だけにする。#1491）・
// RESUME_SFEN / RESUME_PLY / WALL_LIMIT（hint の 1 局を途中で止めて続きから回す。HintMatch.play を参照）。

func strength(_ name: String) -> CPUStrength {
    switch name {
    case "novice": return .novice
    case "easy": return .easy
    case "normal": return .normal
    case "hard": return .hard
    default:
        FileHandle.standardError.write("不明な段階: \(name)\n".data(using: .utf8)!)
        exit(2)
    }
}

func probability(_ arg: String) -> Double? {
    if arg == "shipped" { return nil }
    guard let p = Double(arg), (0...1).contains(p) else {
        FileHandle.standardError.write("確率は 0...1 か shipped: \(arg)\n".data(using: .utf8)!)
        exit(2)
    }
    return p
}

let env = ProcessInfo.processInfo.environment

/// このプロセスが使った CPU 時間（秒）。ほかのプロセスに CPU を取られても増えない。
func cpuSeconds() -> Double {
    var ts = timespec()
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts)
    return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
}

/// 中盤の局面を集める（局面数の少ない読みで指した対局から、8 手おきに拾う）。
func samplePositions(count: Int) async -> [String] {
    var out: [String] = []
    var seed: UInt64 = 1
    while out.count < count {
        var pos = CPUBenchLadder.opening(seed: seed)
        for ply in 0..<120 {
            if ply >= 16 && ply % 8 == 0 { out.append(pos.toSFEN()) }
            let e = SimpleMinimaxEngine(depth: 2, usePositional: true, useQuiescence: true, useBook: false,
                                        timeLimit: .infinity, nodeLimit: 1_500,
                                        policy: .exact, seed: seed &* 1000 &+ UInt64(ply))
            guard let usi = await e.bestMove(sfen: pos.toSFEN()), let m = Move.fromUSI(usi) else { break }
            pos.make(m)
        }
        seed += 1
    }
    return Array(out.prefix(count))
}

@main
struct Bench {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 2 else { print("引数が足りません"); return }
        setvbuf(stdout, nil, _IOLBF, 0)
        switch args[1] {
        case "nps":
            let sfens = await samplePositions(count: 24)
            var nodes = 0
            var seconds = 0.0
            for sfen in sfens {
                let e = SimpleMinimaxEngine(depth: SimpleMinimaxEngine.maxDepth, usePositional: true,
                                            useQuiescence: true, useBook: false, timeLimit: 1.0)
                let t = Date()
                guard let r = e.analyze(sfen: sfen) else { continue }
                seconds += Date().timeIntervalSince(t)
                nodes += r.nodes
            }
            print("NPS \(Int(Double(nodes) / seconds)) （\(sfens.count) 局面・計 \(String(format: "%.1f", seconds)) 秒）")
        case "slip":
            // 最善手を外すときの浅い読み（`slipMove`）だけの所要時間（CPU 時間）。
            let sfens = await samplePositions(count: 40)
            var cpu: [Double] = []
            for (i, sfen) in sfens.enumerated() {
                guard var pos = Position.fromSFEN(sfen) else { continue }
                var rng = SplitMix64(seed: UInt64(i + 1))
                let e = SimpleMinimaxEngine(level: CPUStrength.novice.rawValue, seed: 1)
                let t = cpuSeconds()
                _ = e.slipMove(&pos, moves: pos.legalMoves(), using: &rng)
                cpu.append(cpuSeconds() - t)
            }
            cpu.sort()
            print("SLIP CPU秒: 平均 \(String(format: "%.3f", cpu.reduce(0, +) / Double(cpu.count))) 中央値 \(String(format: "%.3f", cpu[cpu.count / 2])) 最大 \(String(format: "%.3f", cpu.last!))（\(cpu.count) 局面）")
        case "timing":
            let n = args.count > 2 ? Int(args[2]) ?? 40 : 40
            let sfens = await samplePositions(count: n)
            for s in [CPUStrength.novice, .easy, .normal, .hard] {
                var wall: [Double] = []
                var cpu: [Double] = []
                for sfen in sfens {
                    let t = Date()
                    let c = cpuSeconds()
                    _ = await SimpleMinimaxEngine(level: s.rawValue).bestMove(sfen: sfen)
                    wall.append(Date().timeIntervalSince(t))
                    cpu.append(cpuSeconds() - c)
                }
                let limit = SimpleMinimaxEngine(level: s.rawValue).timeLimit
                let cut = wall.filter { $0 >= limit * 0.95 }.count
                func f(_ v: Double) -> String { String(format: "%.3f", v) }
                print("TIMING \(s.label) 上限 \(limit)s: 実時間 平均 \(f(wall.reduce(0, +) / Double(wall.count)))s 最大 \(f(wall.max()!))s / CPU 時間 平均 \(f(cpu.reduce(0, +) / Double(cpu.count)))s 最大 \(f(cpu.max()!))s / 上限で打ち切り \(cut)/\(wall.count)（\(cut * 100 / wall.count)%）")
            }
        case "match", "random":
            let nps = Double(env["NPS"] ?? "") ?? 300_000
            let plies = Int(env["PLIES"] ?? "") ?? 150
            let conc = Int(env["CONCURRENCY"] ?? "") ?? 6
            let margin = Int(env["SLIP_MARGIN"] ?? "")
            let first = Int(env["FIRST_OPENING"] ?? "") ?? 1
            if args[1] == "match" {
                let up = strength(args[2]), low = strength(args[4])
                let upP = probability(args[3])
                let p = probability(args[5])
                let openings = Int(args[6]) ?? 100
                let upD = Int(env["UPPER_DEPTH"] ?? ""), lowD = Int(env["LOWER_DEPTH"] ?? "")
                let t0 = Date()
                let t = await CPUBenchLadder.run(
                    upper: { CPUBenchLadder.engine(up, nodesPerSecond: nps, bestMoveProbability: upP, slipMargin: margin, depth: upD, seed: $0) },
                    lower: { CPUBenchLadder.engine(low, nodesPerSecond: nps, bestMoveProbability: p, slipMargin: margin, depth: lowD, seed: $0) },
                    openings: openings, maxPlies: plies, concurrency: conc, firstOpening: first)
                print("MATCH 損の幅 \(margin.map(String.init) ?? "shipped") \(up.label)(確率 \(args[3])・深さ \(upD.map(String.init) ?? "shipped")) 対 \(low.label)(確率 \(args[5])・深さ \(lowD.map(String.init) ?? "shipped")) NPS \(Int(nps)) 開始局面 \(first)〜\(first + openings - 1): \(t.games)局 上の勝ち \(t.upperWins) 負け \(t.lowerWins)（\(String(format: "%.1f", Double(t.lowerWins) * 100 / Double(t.games)))%） 引き分け \(t.draws)（うち下が駒得 \(t.drawsLowerAhead)） 所要 \(Int(Date().timeIntervalSince(t0)))s")
            } else {
                let s = strength(args[2])
                let p = probability(args[3])
                let openings = Int(args[4]) ?? 50
                let t = await CPUBenchLadder.run(
                    upper: { CPUBenchLadder.engine(s, nodesPerSecond: nps, bestMoveProbability: p, slipMargin: margin, seed: $0) },
                    lower: nil, openings: openings, maxPlies: plies, concurrency: conc, firstOpening: first)
                print("RANDOM 損の幅 \(margin.map(String.init) ?? "shipped") \(s.label)(確率 \(args[3])) 対 一様乱択: \(t.games)局 勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws)（勝率 \(String(format: "%.1f", Double(t.upperWins) * 100 / Double(t.games)))%）")
            }
        case "hint":
            let nps = Double(env["NPS"] ?? "") ?? 300_000
            let plies = Int(env["PLIES"] ?? "") ?? 150
            let conc = Int(env["CONCURRENCY"] ?? "") ?? 6
            let first = Int(env["FIRST_OPENING"] ?? "") ?? 1
            let extra = Double(args[2]) ?? 0.5
            let openings = Int(args[3]) ?? 10
            let t0 = Date()
            let r = await HintMatch.run(extraSeconds: extra, nodesPerSecond: nps, openings: openings,
                                        maxPlies: plies, concurrency: conc, firstOpening: first)
            let n = r.games
            func f(_ v: Double) -> String { String(format: "%.3f", v) }
            print("HINT ヒント(むずかしい+\(extra)s・局面数 \(Int((2.0 + extra) * nps))) 対 むずかしい(局面数 \(Int(2.0 * nps))) NPS \(Int(nps)) 開始局面 \(first)〜\(first + openings - 1): \(n)局 ヒント側の勝ち \(r.followerWins) 負け \(r.followerLosses) 引き分け \(r.draws)（うちヒント側が駒得 \(r.drawsFollowerAhead)） ヒント側先手 \(r.blackWins)勝/\(r.blackGames)局 後手 \(r.whiteWins)勝/\(r.whiteGames)局 平均手数 \(r.totalPlies / max(n, 1)) ヒント \(r.hintMoves)手 実時間 平均 \(f(r.hintSeconds / Double(max(r.hintMoves, 1))))s 最大 \(f(r.hintMaxSeconds))s 所要 \(Int(Date().timeIntervalSince(t0)))s")
        case "hinttiming":
            let extra = Double(args[2]) ?? 0.5
            let n = args.count > 3 ? Int(args[3]) ?? 40 : 40
            let sfens = await samplePositions(count: n)
            var wall: [Double] = []
            for sfen in sfens {
                let e = HintMatch.timedHintEngine(extraSeconds: extra)
                let t = Date()
                _ = await e.bestMove(sfen: sfen)
                wall.append(Date().timeIntervalSince(t))
            }
            func f(_ v: Double) -> String { String(format: "%.3f", v) }
            print("HINTTIMING 上限 \(2.0 + extra)s: 実時間 平均 \(f(wall.reduce(0, +) / Double(wall.count)))s 最大 \(f(wall.max()!))s 最小 \(f(wall.min()!))s（\(wall.count) 局面）")
        default:
            print("不明なコマンド")
        }
    }
}

/// 毎手ヒントを使い、出たヒントどおりに指す側（#1491）と「むずかしい」の対局。
/// アプリのヒント（`ShogiGameModel.requestHint`）は対局中の段階に関わらず `BoardHintBudget.engineLevel`
/// （= むずかしい）の `SimpleMinimaxEngine` で読むので、ヒントに従う側の手は段階に依らない。
/// 考える時間だけを「むずかしい」+ `extraSeconds` にし、計測では局面数（NPS × 秒）に置き換える。
enum HintMatch {
    struct Tally {
        var followerWins = 0, followerLosses = 0, draws = 0, drawsFollowerAhead = 0
        var blackGames = 0, blackWins = 0, whiteGames = 0, whiteWins = 0
        var totalPlies = 0, hintMoves = 0
        var hintSeconds = 0.0, hintMaxSeconds = 0.0
        var games: Int { followerWins + followerLosses + draws }
    }

    static let hardSeconds = SimpleMinimaxEngine(level: CPUStrength.hard.rawValue).timeLimit

    /// ヒントのエンジン（出荷のむずかしいの設定・考える時間だけ足す）。局面数で打ち切る。
    static func hintEngine(extraSeconds: Double, nodesPerSecond: Double) -> SimpleMinimaxEngine {
        let s = SimpleMinimaxEngine(level: CPUStrength.hard.rawValue)
        return SimpleMinimaxEngine(depth: s.depth, usePositional: s.usePositional, useQuiescence: s.useQuiescence,
                                   useBook: s.useBook, timeLimit: .infinity,
                                   nodeLimit: Int((s.timeLimit + extraSeconds) * nodesPerSecond), policy: s.policy)
    }

    /// 1 手の実時間を測るための、時間で打ち切るヒントのエンジン（アプリと同じ打ち切り方）。
    static func timedHintEngine(extraSeconds: Double) -> SimpleMinimaxEngine {
        let s = SimpleMinimaxEngine(level: CPUStrength.hard.rawValue)
        return SimpleMinimaxEngine(depth: s.depth, usePositional: s.usePositional, useQuiescence: s.useQuiescence,
                                   useBook: s.useBook, timeLimit: s.timeLimit + extraSeconds, policy: s.policy)
    }

    struct Game { var outcome: CPUBenchLadder.Outcome; var followerAhead: Bool; var plies: Int
                  var hintMoves: Int; var hintSeconds: Double; var hintMax: Double }

    /// 1 局。upper = むずかしい、lower = ヒントに従う側。
    static func play(seed: UInt64, hardIsBlack: Bool, extraSeconds: Double, nps: Double, maxPlies: Int) async -> Game {
        // RESUME_SFEN / RESUME_PLY: 10 分に収まらない局を、打ち切った局面から続ける（両者とも乱数を使わず、
        // エンジンは手ごとに作り直すので、局面と手数だけで続きは同じになる）。WALL_LIMIT 秒を過ぎたら局面を出して止める。
        let env = ProcessInfo.processInfo.environment
        var pos = env["RESUME_SFEN"].flatMap(Position.fromSFEN) ?? CPUBenchLadder.opening(seed: seed)
        let startPly = Int(env["RESUME_PLY"] ?? "") ?? 0
        let wallLimit = Double(env["WALL_LIMIT"] ?? "") ?? .infinity
        let started = Date()
        var g = Game(outcome: .draw, followerAhead: false, plies: 0, hintMoves: 0, hintSeconds: 0, hintMax: 0)
        for ply in startPly..<maxPlies {
            if Date().timeIntervalSince(started) > wallLimit {
                print("SUSPEND 開始局面 \(seed) RESUME_PLY=\(ply) RESUME_SFEN='\(pos.toSFEN())'")
                exit(0)
            }
            let moves = pos.legalMoves()
            g.plies = ply
            if moves.isEmpty {
                let hardLost = (pos.sideToMove == .black) == hardIsBlack
                g.outcome = hardLost ? .lowerWon : .upperWon
                return g
            }
            let hardToMove = (pos.sideToMove == .black) == hardIsBlack
            let engine = hardToMove
                ? CPUBenchLadder.engine(.hard, nodesPerSecond: nps, seed: seed &* 100_000 &+ UInt64(ply))
                : hintEngine(extraSeconds: extraSeconds, nodesPerSecond: nps)
            let t = Date()
            let usi = await engine.bestMove(sfen: pos.toSFEN())
            if !hardToMove {
                let dt = Date().timeIntervalSince(t)
                g.hintMoves += 1; g.hintSeconds += dt; g.hintMax = max(g.hintMax, dt)
            }
            guard let usi, let m = Move.fromUSI(usi), moves.contains(m) else {
                g.outcome = hardToMove ? .lowerWon : .upperWon
                return g
            }
            pos.make(m)
        }
        g.plies = maxPlies
        let blackLead = CPUBenchLadder.material(pos)
        g.followerAhead = (hardIsBlack ? -blackLead : blackLead) > 0
        return g
    }

    static func run(extraSeconds: Double, nodesPerSecond: Double, openings: Int, maxPlies: Int,
                    concurrency: Int, firstOpening: Int) async -> Tally {
        var tally = Tally()
        // ONLY_SIDE=black / white でヒント側の手番を片方だけにする（打ち切られた局だけ回し直すため）。
        let sides: [Bool] = switch ProcessInfo.processInfo.environment["ONLY_SIDE"] {
        case "black": [false]
        case "white": [true]
        default: [true, false]
        }
        let jobs = (0..<openings).flatMap { i in sides.map { (UInt64(firstOpening + i), $0) } }
        var next = 0
        await withTaskGroup(of: (Game, Bool, UInt64).self) { group in
            func add() {
                guard next < jobs.count else { return }
                let (seed, hardIsBlack) = jobs[next]
                next += 1
                group.addTask {
                    (await play(seed: seed, hardIsBlack: hardIsBlack, extraSeconds: extraSeconds,
                                nps: nodesPerSecond, maxPlies: maxPlies), hardIsBlack, seed)
                }
            }
            for _ in 0..<concurrency { add() }
            for await (g, hardIsBlack, seed) in group {
                let won = g.outcome == .lowerWon
                switch g.outcome {
                case .lowerWon: tally.followerWins += 1
                case .upperWon: tally.followerLosses += 1
                case .draw: tally.draws += 1; if g.followerAhead { tally.drawsFollowerAhead += 1 }
                }
                if hardIsBlack { tally.whiteGames += 1; if won { tally.whiteWins += 1 } }
                else { tally.blackGames += 1; if won { tally.blackWins += 1 } }
                tally.totalPlies += g.plies
                tally.hintMoves += g.hintMoves; tally.hintSeconds += g.hintSeconds
                tally.hintMaxSeconds = max(tally.hintMaxSeconds, g.hintMax)
                print("GAME 開始局面 \(seed) \(g.plies)手 ヒント側\(hardIsBlack ? "後手" : "先手") \(won ? "勝ち" : g.outcome == .draw ? "引き分け" : "負け")")
                add()
            }
        }
        return tally
    }
}
