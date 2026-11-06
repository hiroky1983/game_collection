import Foundation

// オセロ CPU の計測（#1464）。`build.sh` で作った単体バイナリの引数:
//   nps                                  1 秒あたりに読める局面数（最適化ビルド・1 スレッド・むずかしいの探索）
//   slip [positions]                     外しの候補の数（損の幅の中に最善以外の手が何手あるか）
//   endgame                              むずかしいが空き 12 以下を時間内に終局まで読み切れた割合
//   timing [positions]                   出荷の設定（実時間）で 1 手にかかる時間: 平均・最大・上限で打ち切られた割合
//   match <上> <上の確率> <下> <下の確率> <局面数>
//                                        上の段階と下の段階を、先後入れ替えで局面数×2 局。確率は 0...1 か shipped（出荷値）。
//                                        段階は novice / easy / normal / hard
//   random <段階> <確率|shipped> <局面数>  一様乱択の相手と先後入れ替えで局面数×2 局
// 対局は考える時間を局面数（nps × 秒）に置き換えて回す（`CPUBenchLadder.engine`）。
// 環境変数: NPS（match / random で使う 1 秒あたりの局面数）・CONCURRENCY（既定 4）・
// FIRST_OPENING（最初の開始局面の番号・既定 1。小分けにして続きから回すとき）・
// UPPER_DEPTH / LOWER_DEPTH（match の上 / 下の段の深さの上限を差し替える。#1566）。
//   vs <上の設定> <下の設定> <局面数>      設定を明示して先後入れ替えで局面数×2 局（#3362。新しい段 対 今の段を測るため）。
//                                        設定は「深さ:確率:損の幅:秒」（深さ 0 は上限なし）か、名前
//                                        novice / easy / normal / hard（出荷値）・v1115-novice / v1115-easy / v1115-normal（#3362 前の値）。
//                                        反則手（合法でない手・打てる手があるのに nil）を数えて出す。

func strength(_ name: String) -> CPUStrength {
    switch name {
    case "novice": return .novice
    case "easy": return .easy
    case "normal": return .normal
    default: return .hard
    }
}

let env = ProcessInfo.processInfo.environment

/// このプロセスが使った CPU 時間（秒）。ほかのプロセスに CPU を取られても増えない。
func cpuSeconds() -> Double {
    var ts = timespec()
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts)
    return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
}

/// 序盤〜終盤の局面を集める（深さ 3 の読みで打った対局から、空き 52〜8 の間を 4 手おきに拾う）。
func samplePositions(count: Int) -> [(OthelloBoard, OthelloStone)] {
    var out: [(OthelloBoard, OthelloStone)] = []
    var seed: UInt64 = 1
    while out.count < count {
        var (board, turn) = CPUBenchLadder.opening(seed: seed)
        var ply = 0
        var passes = 0
        while passes < 2 {
            let moves = board.validMoves(for: turn)
            if moves.isEmpty { passes += 1; turn = turn.opponent; continue }
            passes = 0
            let empties = 64 - board.count(for: .black) - board.count(for: .white)
            if empties <= 52 && empties >= 8 && ply % 4 == 0 { out.append((board, turn)) }
            let e = OthelloEngine(level: CPUStrength.easy.rawValue, timeLimitOverride: .infinity,
                                  policy: OthelloEngine.policy(0.7), seed: seed &* 1000 &+ UInt64(ply))
            guard let m = e.move(board: board, stone: turn) else { break }
            board.place(row: m.row, col: m.col, stone: turn)
            turn = turn.opponent
            ply += 1
        }
        seed += 1
    }
    return Array(out.prefix(count))
}

func f3(_ v: Double) -> String { String(format: "%.3f", v) }

@main
struct Bench {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else { print("引数が足りません"); return }
        setvbuf(stdout, nil, _IOLBF, 0)
        switch args[1] {
        case "nps":
            let positions = samplePositions(count: 24)
            var nodes = 0
            var seconds = 0.0
            var depths: [Int] = []
            for (board, turn) in positions {
                let e = OthelloEngine(level: CPUStrength.hard.rawValue, timeLimitOverride: 1.0)
                let t = Date()
                guard let r = e.analyze(board: board, stone: turn) else { continue }
                seconds += Date().timeIntervalSince(t)
                nodes += r.nodes
                depths.append(r.depth)
            }
            print("NPS \(Int(Double(nodes) / seconds)) （\(positions.count) 局面・計 \(String(format: "%.1f", seconds)) 秒・1 秒で読み切った深さ 平均 \(String(format: "%.1f", Double(depths.reduce(0, +)) / Double(depths.count))) 最小 \(depths.min()!) 最大 \(depths.max()!)）")
        case "slip":
            let n = args.count > 2 ? Int(args[2]) ?? 200 : 200
            let positions = samplePositions(count: n)
            let e = OthelloEngine(level: CPUStrength.novice.rawValue, seed: 1)
            var sizes: [Int] = []
            var moveCounts: [Int] = []
            for (board, turn) in positions {
                let moves = board.validMoves(for: turn)
                moveCounts.append(moves.count)
                sizes.append(e.slipPool(moves, board: board, stone: turn).count)
            }
            let nonEmpty = sizes.filter { $0 > 0 }.count
            print("SLIP 損の幅 \(e.policy.slipMargin): 候補あり \(nonEmpty)/\(sizes.count)（\(nonEmpty * 100 / sizes.count)%） 候補の数 平均 \(String(format: "%.1f", Double(sizes.reduce(0, +)) / Double(sizes.count))) / 合法手 平均 \(String(format: "%.1f", Double(moveCounts.reduce(0, +)) / Double(moveCounts.count)))")
        case "timing":
            let n = args.count > 2 ? Int(args[2]) ?? 40 : 40
            let positions = samplePositions(count: n)
            for s in [CPUStrength.novice, .easy, .normal, .hard] {
                var wall: [Double] = []
                var cpu: [Double] = []
                var cut = 0
                for (i, (board, turn)) in positions.enumerated() {
                    let e = OthelloEngine(level: s.rawValue, seed: UInt64(i + 1))
                    let t = Date()
                    let c = cpuSeconds()
                    _ = e.move(board: board, stone: turn)
                    wall.append(Date().timeIntervalSince(t))
                    cpu.append(cpuSeconds() - c)
                    // 上限で打ち切られたか: 同じ時間で読み直し、深さの上限（無ければ終局）まで読み切れなかったもの。
                    let empties = 64 - board.count(for: .black) - board.count(for: .white)
                    let maxDepth = max(1, min(e.depthLimit ?? empties, empties))
                    if let r = e.analyze(board: board, stone: turn), r.depth < maxDepth { cut += 1 }
                }
                print("TIMING \(s.label) 上限 \(e3(s))s: 実時間 平均 \(f3(wall.reduce(0, +) / Double(wall.count)))s 最大 \(f3(wall.max()!))s / CPU 時間 平均 \(f3(cpu.reduce(0, +) / Double(cpu.count)))s 最大 \(f3(cpu.max()!))s / 上限で打ち切り \(cut)/\(wall.count)（\(cut * 100 / wall.count)%）")
            }
        case "endgame":
            // むずかしいが、空き 12 以下の局面を時間内に終局まで読み切れた割合（終盤の完全読み）。
            let positions = samplePositions(count: 400).filter { 64 - $0.0.count(for: .black) - $0.0.count(for: .white) <= 12 }
            var full = 0
            var wall: [Double] = []
            for (board, turn) in positions.prefix(40) {
                let empties = 64 - board.count(for: .black) - board.count(for: .white)
                let t = Date()
                if let r = OthelloEngine(level: CPUStrength.hard.rawValue).analyze(board: board, stone: turn), r.depth >= empties { full += 1 }
                wall.append(Date().timeIntervalSince(t))
            }
            print("ENDGAME むずかしい 空き 8〜12: 終局まで読み切り \(full)/\(wall.count) 実時間 平均 \(f3(wall.reduce(0, +) / Double(wall.count)))s 最大 \(f3(wall.max()!))s")
        case "match", "random":
            let nps = Double(env["NPS"] ?? "") ?? 300_000
            let conc = Int(env["CONCURRENCY"] ?? "") ?? 4
            let first = Int(env["FIRST_OPENING"] ?? "") ?? 1
            if args[1] == "match" {
                let up = strength(args[2]), low = strength(args[4])
                let upP: Double? = args[3] == "shipped" ? nil : Double(args[3])
                let p: Double? = args[5] == "shipped" ? nil : Double(args[5])
                let openings = Int(args[6]) ?? 4
                let upD = Int(env["UPPER_DEPTH"] ?? ""), lowD = Int(env["LOWER_DEPTH"] ?? "")
                let t0 = Date()
                let t = CPUBenchLadder.run(
                    upper: { CPUBenchLadder.engine(up, nodesPerSecond: nps, bestMoveProbability: upP, depthLimit: upD, seed: $0) },
                    lower: { CPUBenchLadder.engine(low, nodesPerSecond: nps, bestMoveProbability: p, depthLimit: lowD, seed: $0) },
                    openings: openings, concurrency: conc, firstOpening: first)
                let dl = { (d: Int?) in d.map { " 深さ \($0)" } ?? "" }
                print("MATCH \(up.label)(確率 \(args[3])\(dl(upD))) 対 \(low.label)(確率 \(args[5])\(dl(lowD))) NPS \(Int(nps)) 開始局面 \(first)〜\(first + openings - 1): \(t.games)局 上の勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws) 石差合計(下−上) \(t.lowerDiscDiffSum) 所要 \(Int(Date().timeIntervalSince(t0)))s")
            } else {
                let s = strength(args[2])
                let p: Double? = args[3] == "shipped" ? nil : Double(args[3])
                let openings = Int(args[4]) ?? 50
                let t = CPUBenchLadder.run(
                    upper: { CPUBenchLadder.engine(s, nodesPerSecond: nps, bestMoveProbability: p, seed: $0) },
                    lower: nil, openings: openings, concurrency: conc, firstOpening: first)
                print("RANDOM \(s.label)(確率 \(args[3])) 対 一様乱択 開始局面 \(first)〜\(first + openings - 1): \(t.games)局 勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws) 石差合計(乱択−段) \(t.lowerDiscDiffSum)")
            }
        case "vs":
            let nps = Double(env["NPS"] ?? "") ?? 300_000
            let conc = Int(env["CONCURRENCY"] ?? "") ?? 4
            let first = Int(env["FIRST_OPENING"] ?? "") ?? 1
            let openings = Int(args[4]) ?? 100
            let up = engineSpec(args[2]), low = engineSpec(args[3])
            let t0 = Date()
            let t = VsBench.run(upper: up, lower: low, nps: nps, openings: openings, concurrency: conc, firstOpening: first)
            let score = (Double(t.upperWins) + Double(t.draws) * 0.5) / Double(max(1, t.games))
            print("VS \(args[2]) 対 \(args[3]) NPS \(Int(nps)) 開始局面 \(first)〜\(first + openings - 1): \(t.games)局 上の勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws) 上の得点率 \(String(format: "%.1f", score * 100))% 平均石差(下−上) \(String(format: "%.1f", Double(t.lowerDiscDiffSum) / Double(max(1, t.games)))) 反則手 \(t.illegal) 所要 \(Int(Date().timeIntervalSince(t0)))s")
        default:
            print("不明なコマンド")
        }
    }
}

func e3(_ s: CPUStrength) -> String { String(OthelloEngine.settings(for: s).timeLimit) }

/// `vs` の対局者の設定（#3362）。
struct EngineSpec: Sendable {
    var depth: Int?
    var probability: Double
    var margin: Int
    var seconds: Double

    func engine(nps: Double, seed: UInt64) -> OthelloEngine {
        // むずかしい（rawValue 2）の番号を使うと深さの上限は差し替えでも nil に戻らないので、深さ無しは hard の出荷値を使う。
        let level = depth == nil ? CPUStrength.hard.rawValue : CPUStrength.normal.rawValue
        return OthelloEngine(level: level, timeLimitOverride: .infinity, depthLimitOverride: depth,
                             nodeLimit: Int(seconds * nps),
                             policy: OthelloMovePolicy(bestMoveProbability: probability, slipMargin: margin), seed: seed)
    }
}

func engineSpec(_ s: String) -> EngineSpec {
    func shipped(_ st: CPUStrength) -> EngineSpec {
        let v = OthelloEngine.settings(for: st)
        return EngineSpec(depth: v.depthLimit, probability: v.policy.bestMoveProbability,
                          margin: v.policy.slipMargin, seconds: v.timeLimit)
    }
    switch s {
    case "novice": return shipped(.novice)
    case "easy": return shipped(.easy)
    case "normal": return shipped(.normal)
    case "hard": return shipped(.hard)
    // #3362 の前（v1.1.15 まで）の出荷値。
    case "v1115-novice": return EngineSpec(depth: 1, probability: 0.5, margin: 40, seconds: 0.3)
    case "v1115-easy": return EngineSpec(depth: 3, probability: 0.6, margin: 40, seconds: 0.5)
    case "v1115-normal": return EngineSpec(depth: 4, probability: 0.6, margin: 40, seconds: 1.0)
    default:
        let p = s.split(separator: ":").map(String.init)
        precondition(p.count == 4, "設定は 深さ:確率:損の幅:秒")
        let d = Int(p[0])!
        return EngineSpec(depth: d == 0 ? nil : d, probability: Double(p[1])!, margin: Int(p[2])!, seconds: Double(p[3])!)
    }
}

/// `CPUBenchLadder.play` と同じ開始局面・同じ種の振り方で、反則手も数える対局（#3362）。
enum VsBench {
    struct Tally { var upperWins = 0, lowerWins = 0, draws = 0, lowerDiscDiffSum = 0, illegal = 0
        var games: Int { upperWins + lowerWins + draws } }

    static func play(upper: EngineSpec, lower: EngineSpec, nps: Double, upperIsBlack: Bool, seed: UInt64)
        -> (CPUBenchLadder.Outcome, Int, Int) {
        var (board, turn) = CPUBenchLadder.opening(seed: seed)
        var ply = 0, passes = 0, illegal = 0
        while passes < 2 {
            let moves = board.validMoves(for: turn)
            if moves.isEmpty { passes += 1; turn = turn.opponent; continue }
            passes = 0
            let upperToMove = (turn == .black) == upperIsBlack
            let engineSeed = seed &* 100_000 &+ UInt64(ply) &* 2 &+ (upperToMove ? 1 : 2)
            let e = (upperToMove ? upper : lower).engine(nps: nps, seed: engineSeed)
            guard let m = e.move(board: board, stone: turn), board.isValid(row: m.row, col: m.col, stone: turn) else {
                illegal += 1
                break
            }
            board.place(row: m.row, col: m.col, stone: turn)
            turn = turn.opponent
            ply += 1
        }
        let black = board.count(for: .black), white = board.count(for: .white)
        let u = upperIsBlack ? black : white, l = upperIsBlack ? white : black
        return (u == l ? .draw : (u > l ? .upperWon : .lowerWon), l - u, illegal)
    }

    static func run(upper: EngineSpec, lower: EngineSpec, nps: Double, openings: Int, concurrency: Int,
                    firstOpening: Int) -> Tally {
        let jobs = (0..<openings).flatMap { i in [true, false].map { (UInt64(firstOpening + i), $0) } }
        let lock = NSLock()
        nonisolated(unsafe) var next = 0
        nonisolated(unsafe) var tally = Tally()
        DispatchQueue.concurrentPerform(iterations: max(1, concurrency)) { _ in
            while true {
                lock.lock()
                guard next < jobs.count else { lock.unlock(); return }
                let (seed, upperIsBlack) = jobs[next]
                next += 1
                lock.unlock()
                let (o, d, ill) = play(upper: upper, lower: lower, nps: nps, upperIsBlack: upperIsBlack, seed: seed)
                lock.lock()
                switch o {
                case .upperWon: tally.upperWins += 1
                case .lowerWon: tally.lowerWins += 1
                case .draw: tally.draws += 1
                }
                tally.lowerDiscDiffSum += d
                tally.illegal += ill
                lock.unlock()
            }
        }
        return tally
    }
}
