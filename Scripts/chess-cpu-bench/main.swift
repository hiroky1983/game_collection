import Foundation

// チェス CPU の計測（#1462）。`build.sh` で作った単体バイナリの引数:
//   nps                                  1 秒あたりに読める局面数（最適化ビルド・1 スレッド）
//   depth [positions]                    考える時間 0.02 / 0.1 / 0.5 / 2 秒（深さ上限なし）で中盤の局面を読んだときに
//                                        最後まで読み切れた深さ（実時間で打ち切り・NPS 相当の局面数で打ち切り の両方）
//   slip                                 最善手を外すときの浅い読みだけの所要時間（CPU 時間）
//   timing [positions]                   出荷の設定（実時間）で 1 手にかかる時間: 平均・最大・上限で打ち切られた割合（ヒントも）
//   match <上> <上の確率> <下> <下の確率> <局面数>
//                                        上の段階と下の段階を、先後入れ替えで局面数×2 局。確率は 0...1 か shipped（出荷値）。
//                                        段階は novice / easy / normal / hard
//   random <段階> <確率|shipped> <局面数>  一様乱択の相手と先後入れ替えで局面数×2 局
// 対局は考える時間を局面数（nps × 秒）に置き換えて回す（`CPUBenchLadder.engine`）。
// 環境変数: SLIP_MARGIN（外したときに許す損の幅の差し替え）・NPS（match / random / depth で使う 1 秒あたりの局面数）・
// PLIES（手数上限・既定 300）・CONCURRENCY（既定 4）・FIRST_OPENING（最初の開始局面の番号・既定 1。小分けにして続きから回すとき）。

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

/// 中盤の局面を集める（局面数の少ない読みで指した対局から、序盤 16 手を過ぎたら 8 手おきに拾う）。
func samplePositions(count: Int) async -> [String] {
    var out: [String] = []
    var seed: UInt64 = 1
    while out.count < count {
        var pos = CPUBenchLadder.opening(seed: seed)
        for ply in 0..<80 {
            if pos.legalMoves().isEmpty { break }
            if ply >= 16 && ply % 8 == 0 { out.append(pos.toFEN()) }
            let e = SimpleChessEngine(depth: 3, usePositional: true, useQuiescence: true, useBook: false,
                                      timeLimit: .infinity, nodeLimit: 3_000,
                                      policy: .exact, seed: seed &* 1000 &+ UInt64(ply))
            guard let uci = await e.bestMove(fen: pos.toFEN()), let m = ChessMove.fromUCI(uci) else { break }
            _ = pos.make(m)
        }
        seed += 1
    }
    return Array(out.prefix(count))
}

func f3(_ v: Double) -> String { String(format: "%.3f", v) }

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
            for fen in sfens {
                let e = SimpleChessEngine(depth: SimpleChessEngine.maxDepth, usePositional: true,
                                          useQuiescence: true, useBook: false, timeLimit: 1.0)
                let t = Date()
                guard let r = e.analyze(fen: fen) else { continue }
                seconds += Date().timeIntervalSince(t)
                nodes += r.nodes
            }
            print("NPS \(Int(Double(nodes) / seconds)) （\(sfens.count) 局面・計 \(String(format: "%.1f", seconds)) 秒）")
        case "depth":
            let n = args.count > 2 ? Int(args[2]) ?? 40 : 40
            let nps = Double(env["NPS"] ?? "")
            let fens = await samplePositions(count: n)
            for seconds in [0.02, 0.1, 0.5, 2.0] {
                var wallDepths: [Int] = []
                var nodeDepths: [Int] = []
                for fen in fens {
                    let e = SimpleChessEngine(depth: SimpleChessEngine.maxDepth, usePositional: true,
                                              useQuiescence: true, useBook: false, timeLimit: seconds)
                    if let r = e.analyze(fen: fen) { wallDepths.append(r.depth) }
                    if let nps {
                        let n = SimpleChessEngine(depth: SimpleChessEngine.maxDepth, usePositional: true,
                                                  useQuiescence: true, useBook: false, timeLimit: .infinity,
                                                  nodeLimit: max(1, Int(seconds * nps)))
                        if let r = n.analyze(fen: fen) { nodeDepths.append(r.depth) }
                    }
                }
                func summary(_ d: [Int]) -> String {
                    guard !d.isEmpty else { return "-" }
                    let hist = Dictionary(grouping: d, by: { $0 }).mapValues(\.count).sorted { $0.key < $1.key }
                        .map { "\($0.key):\($0.value)" }.joined(separator: " ")
                    return "平均 \(String(format: "%.2f", Double(d.reduce(0, +)) / Double(d.count))) 最小 \(d.min()!) 最大 \(d.max()!)（分布 \(hist)）"
                }
                print("DEPTH \(seconds)秒: 実時間打ち切り \(summary(wallDepths)) / 局面数打ち切り(NPS \(nps.map { String(Int($0)) } ?? "-")) \(summary(nodeDepths))（\(fens.count) 局面）")
            }
        case "slip":
            // 最善手を外すときの浅い読み（`slipMove`）だけの所要時間（CPU 時間）。
            let fens = await samplePositions(count: 40)
            var cpu: [Double] = []
            for (i, fen) in fens.enumerated() {
                guard var pos = ChessPosition.fromFEN(fen) else { continue }
                var rng = SplitMix64(seed: UInt64(i + 1))
                let e = SimpleChessEngine(level: CPUStrength.novice.rawValue, seed: 1)
                let t = cpuSeconds()
                _ = e.slipMove(&pos, moves: pos.legalMoves(), using: &rng)
                cpu.append(cpuSeconds() - t)
            }
            cpu.sort()
            print("SLIP CPU秒: 平均 \(f3(cpu.reduce(0, +) / Double(cpu.count))) 中央値 \(f3(cpu[cpu.count / 2])) 最大 \(f3(cpu.last!))（\(cpu.count) 局面）")
        case "timing":
            let n = args.count > 2 ? Int(args[2]) ?? 40 : 40
            let fens = await samplePositions(count: n)
            for s in [CPUStrength.novice, .easy, .normal, .hard] {
                var wall: [Double] = []
                var cpu: [Double] = []
                for fen in fens {
                    let t = Date()
                    let c = cpuSeconds()
                    _ = await SimpleChessEngine(level: s.rawValue).bestMove(fen: fen)
                    wall.append(Date().timeIntervalSince(t))
                    cpu.append(cpuSeconds() - c)
                }
                let limit = SimpleChessEngine(level: s.rawValue).timeLimit
                let cut = wall.filter { $0 >= limit * 0.95 }.count
                print("TIMING \(s.label) 上限 \(limit)s: 実時間 平均 \(f3(wall.reduce(0, +) / Double(wall.count)))s 最大 \(f3(wall.max()!))s / CPU 時間 平均 \(f3(cpu.reduce(0, +) / Double(cpu.count)))s 最大 \(f3(cpu.max()!))s / 上限で打ち切り \(cut)/\(wall.count)（\(cut * 100 / wall.count)%）")
            }
        case "match", "random":
            let nps = Double(env["NPS"] ?? "") ?? 300_000
            let plies = Int(env["PLIES"] ?? "") ?? 300
            let conc = Int(env["CONCURRENCY"] ?? "") ?? 4
            let margin = Int(env["SLIP_MARGIN"] ?? "")
            let first = Int(env["FIRST_OPENING"] ?? "") ?? 1
            if args[1] == "match" {
                let up = strength(args[2]), low = strength(args[4])
                let upP: Double? = args[3] == "shipped" ? nil : Double(args[3])
                let p: Double? = args[5] == "shipped" ? nil : Double(args[5])
                let openings = Int(args[6]) ?? 100
                let t0 = Date()
                let t = await CPUBenchLadder.run(
                    upper: { CPUBenchLadder.engine(up, nodesPerSecond: nps, bestMoveProbability: upP, slipMargin: margin, seed: $0) },
                    lower: { CPUBenchLadder.engine(low, nodesPerSecond: nps, bestMoveProbability: p, slipMargin: margin, seed: $0) },
                    openings: openings, maxPlies: plies, concurrency: conc, firstOpening: first)
                let score = (Double(t.upperWins) + Double(t.draws) * 0.5) * 100 / Double(t.games)
                print("MATCH 損の幅 \(margin.map(String.init) ?? "shipped") \(up.label)(確率 \(args[3])) 対 \(low.label)(確率 \(args[5])) NPS \(Int(nps)) 開始局面 \(first)〜\(first + openings - 1): \(t.games)局 上の勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws)（うち下が駒得 \(t.drawsLowerAhead)） 上の得点率 \(String(format: "%.1f", score))% 所要 \(Int(Date().timeIntervalSince(t0)))s")
            } else {
                let s = strength(args[2])
                let p: Double? = args[3] == "shipped" ? nil : Double(args[3])
                let openings = Int(args[4]) ?? 50
                let t = await CPUBenchLadder.run(
                    upper: { CPUBenchLadder.engine(s, nodesPerSecond: nps, bestMoveProbability: p, slipMargin: margin, seed: $0) },
                    lower: nil, openings: openings, maxPlies: plies, concurrency: conc, firstOpening: first)
                print("RANDOM 損の幅 \(margin.map(String.init) ?? "shipped") \(s.label)(確率 \(args[3])) 対 一様乱択: \(t.games)局 勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws)（勝率 \(String(format: "%.1f", Double(t.upperWins) * 100 / Double(t.games)))%）")
            }
        default:
            print("不明なコマンド")
        }
    }
}
