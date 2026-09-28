import Foundation

// 五目並べ CPU の計測（#1463）。`build.sh` で作った単体バイナリの引数:
//   nps                                  1 秒あたりに読める局面数（最適化ビルド・1 スレッド・むずかしいの探索）
//   timing [positions]                   出荷の設定（実時間）で 1 手にかかる時間: 平均・最大・上限で打ち切られた割合。
//                                        外す手番（確率 0% にした同じ段階）も測る
//   match <上> <上の確率> <下> <下の確率> <局面数>
//                                        上の段階と下の段階を、先後入れ替えで局面数×2 局。確率は 0...1 か shipped（出荷値）。
//                                        段階は novice / easy / normal / hard
//   random <段階> <確率|shipped> <局面数>  合法手（空いている交点）から一様乱択する相手と先後入れ替えで局面数×2 局
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

/// 序盤〜中盤の局面を集める（局面数の少ない読みで打った対局から、4 手おきに拾う）。決着した局面は入れない。
func samplePositions(count: Int) async -> [(GomokuBoard, GomokuStone)] {
    var out: [(GomokuBoard, GomokuStone)] = []
    var seed: UInt64 = 1
    while out.count < count {
        var board = CPUBenchLadder.opening(seed: seed)
        var stone = GomokuStone.white
        for ply in 0..<40 {
            if ply >= 4 && ply % 4 == 0 { out.append((board, stone)) }
            let e = SimpleGomokuEngine(level: CPUStrength.easy.rawValue, seed: CPUBenchLadder.spread(seed &* 1000 &+ UInt64(ply)),
                                       timeLimit: .infinity, nodeLimit: 3_000,
                                       policy: SimpleGomokuEngine.policy(0.7))
            guard let m = await e.bestMove(board: board, stone: stone), board[m.row, m.col] == nil else { break }
            board[m.row, m.col] = stone
            if board.checkWin(row: m.row, col: m.col) { break }
            stone = stone.opponent
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
        func f(_ v: Double) -> String { String(format: "%.3f", v) }
        switch args[1] {
        case "nps":
            let positions = await samplePositions(count: 24)
            var nodes = 0
            var seconds = 0.0
            for (board, stone) in positions {
                let e = SimpleGomokuEngine(level: CPUStrength.hard.rawValue, seed: 1, timeLimit: 1.0)
                let t = Date()
                let r = e.analyze(board: board, stone: stone)
                seconds += Date().timeIntervalSince(t)
                nodes += r.nodes
            }
            print("NPS \(Int(Double(nodes) / seconds)) （\(positions.count) 局面・計 \(String(format: "%.1f", seconds)) 秒）")
        case "depth":
            // 出荷の設定（実時間）で読み切った深さ（外さない手番）。
            let positions = await samplePositions(count: args.count > 2 ? Int(args[2]) ?? 40 : 40)
            for s in CPUStrength.allCases {
                var depths: [Int] = []
                for (board, stone) in positions {
                    depths.append(SimpleGomokuEngine(level: s.rawValue, seed: 1).analyze(board: board, stone: stone).depth)
                }
                depths.sort()
                print("DEPTH \(s.label): 平均 \(String(format: "%.1f", Double(depths.reduce(0, +)) / Double(depths.count))) 中央値 \(depths[depths.count / 2]) 最小 \(depths.first!) 最大 \(depths.last!)（\(depths.count) 局面）")
            }
        case "timing":
            let n = args.count > 2 ? Int(args[2]) ?? 40 : 40
            let positions = await samplePositions(count: n)
            for s in CPUStrength.allCases {
                for slipping in [false, true] where !(slipping && s == .hard) {
                    var wall: [Double] = []
                    var cpu: [Double] = []
                    for (i, (board, stone)) in positions.enumerated() {
                        let e = SimpleGomokuEngine(level: s.rawValue, seed: UInt64(i + 1),
                                                   policy: slipping ? SimpleGomokuEngine.policy(0) : nil)
                        let t = Date()
                        let c = cpuSeconds()
                        _ = await e.bestMove(board: board, stone: stone)
                        wall.append(Date().timeIntervalSince(t))
                        cpu.append(cpuSeconds() - c)
                    }
                    let limit = SimpleGomokuEngine(level: s.rawValue).timeLimit
                    let cut = wall.filter { $0 >= limit * 0.95 }.count
                    print("TIMING \(s.label)\(slipping ? "（外す手番）" : "") 上限 \(limit)s: 実時間 平均 \(f(wall.reduce(0, +) / Double(wall.count)))s 最大 \(f(wall.max()!))s / CPU 時間 平均 \(f(cpu.reduce(0, +) / Double(cpu.count)))s 最大 \(f(cpu.max()!))s / 上限で打ち切り \(cut)/\(wall.count)（\(cut * 100 / wall.count)%）")
                }
            }
        case "match", "random":
            guard let nps = Double(env["NPS"] ?? "") else { print("NPS を渡してください"); return }
            let conc = Int(env["CONCURRENCY"] ?? "") ?? 4
            let first = Int(env["FIRST_OPENING"] ?? "") ?? 1
            let t0 = Date()
            if args[1] == "match" {
                let up = strength(args[2]), low = strength(args[4])
                let upP: Double? = args[3] == "shipped" ? nil : Double(args[3])
                let p: Double? = args[5] == "shipped" ? nil : Double(args[5])
                let openings = Int(args[6]) ?? 4
                let t = await CPUBenchLadder.run(
                    upper: { CPUBenchLadder.engine(up, nodesPerSecond: nps, bestMoveProbability: upP, seed: $0) },
                    lower: { CPUBenchLadder.engine(low, nodesPerSecond: nps, bestMoveProbability: p, seed: $0) },
                    openings: openings, concurrency: conc, firstOpening: first)
                print("MATCH \(up.label)(確率 \(args[3])) 対 \(low.label)(確率 \(args[5])) NPS \(Int(nps)) 開始局面 \(first)〜\(first + openings - 1): \(t.games)局 上の勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws) 得点率 \(String(format: "%.1f", t.upperScore * 100))% 所要 \(Int(Date().timeIntervalSince(t0)))s")
            } else {
                let s = strength(args[2])
                let p: Double? = args[3] == "shipped" ? nil : Double(args[3])
                let openings = Int(args[4]) ?? 4
                let t = await CPUBenchLadder.run(
                    upper: { CPUBenchLadder.engine(s, nodesPerSecond: nps, bestMoveProbability: p, seed: $0) },
                    lower: nil, openings: openings, concurrency: conc, firstOpening: first)
                print("RANDOM \(s.label)(確率 \(args[3])) 対 一様乱択 開始局面 \(first)〜\(first + openings - 1): \(t.games)局 勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws)（勝率 \(String(format: "%.1f", Double(t.upperWins) * 100 / Double(t.games)))%） 所要 \(Int(Date().timeIntervalSince(t0)))s")
            }
        default:
            print("不明なコマンド")
        }
    }
}
