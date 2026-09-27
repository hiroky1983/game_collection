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
// FIRST_OPENING（最初の開始局面の番号・既定 1。小分けにして続きから回すとき）。

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
                let t0 = Date()
                let t = CPUBenchLadder.run(
                    upper: { CPUBenchLadder.engine(up, nodesPerSecond: nps, bestMoveProbability: upP, seed: $0) },
                    lower: { CPUBenchLadder.engine(low, nodesPerSecond: nps, bestMoveProbability: p, seed: $0) },
                    openings: openings, concurrency: conc, firstOpening: first)
                print("MATCH \(up.label)(確率 \(args[3])) 対 \(low.label)(確率 \(args[5])) NPS \(Int(nps)) 開始局面 \(first)〜\(first + openings - 1): \(t.games)局 上の勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws) 石差合計(下−上) \(t.lowerDiscDiffSum) 所要 \(Int(Date().timeIntervalSince(t0)))s")
            } else {
                let s = strength(args[2])
                let p: Double? = args[3] == "shipped" ? nil : Double(args[3])
                let openings = Int(args[4]) ?? 50
                let t = CPUBenchLadder.run(
                    upper: { CPUBenchLadder.engine(s, nodesPerSecond: nps, bestMoveProbability: p, seed: $0) },
                    lower: nil, openings: openings, concurrency: conc, firstOpening: first)
                print("RANDOM \(s.label)(確率 \(args[3])) 対 一様乱択 開始局面 \(first)〜\(first + openings - 1): \(t.games)局 勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws) 石差合計(乱択−段) \(t.lowerDiscDiffSum)")
            }
        default:
            print("不明なコマンド")
        }
    }
}

func e3(_ s: CPUStrength) -> String { String(OthelloEngine.settings(for: s).timeLimit) }
