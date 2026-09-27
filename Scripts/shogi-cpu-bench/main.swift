import Foundation

// 将棋 CPU の計測（#1461）。`build.sh` で作った単体バイナリの引数:
//   nps                                  1 秒あたりに読める局面数（最適化ビルド・1 スレッド）
//   slip                                 最善手を外すときの浅い読みだけの所要時間（CPU 時間）
//   timing [positions]                   出荷の設定（実時間）で 1 手にかかる時間: 平均・最大・上限で打ち切られた割合
//   match <上> <上の確率> <下> <下の確率> <局面数>
//                                        上の段階と下の段階を、先後入れ替えで局面数×2 局。確率は 0...1 か shipped（出荷値）。
//                                        段階は novice / easy / normal / hard
//   random <段階> <確率|shipped> <局面数>  一様乱択の相手と先後入れ替えで局面数×2 局
// 対局は考える時間を局面数（nps × 秒）に置き換えて回す（`CPUBenchLadder.engine`）。
// 環境変数: SLIP_MARGIN（外したときに許す損の幅の差し替え）・NPS（match / random で使う 1 秒あたりの局面数）・PLIES（手数上限・既定 150）・CONCURRENCY（既定 6）・
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
                let upP: Double? = args[3] == "shipped" ? nil : Double(args[3])
                let p: Double? = args[5] == "shipped" ? nil : Double(args[5])
                let openings = Int(args[6]) ?? 100
                let t0 = Date()
                let t = await CPUBenchLadder.run(
                    upper: { CPUBenchLadder.engine(up, nodesPerSecond: nps, bestMoveProbability: upP, slipMargin: margin, seed: $0) },
                    lower: { CPUBenchLadder.engine(low, nodesPerSecond: nps, bestMoveProbability: p, slipMargin: margin, seed: $0) },
                    openings: openings, maxPlies: plies, concurrency: conc, firstOpening: first)
                print("MATCH 損の幅 \(margin.map(String.init) ?? "shipped") \(up.label)(確率 \(args[3])) 対 \(low.label)(確率 \(args[5])) NPS \(Int(nps)) 開始局面 \(first)〜\(first + openings - 1): \(t.games)局 上の勝ち \(t.upperWins) 負け \(t.lowerWins)（\(String(format: "%.1f", Double(t.lowerWins) * 100 / Double(t.games)))%） 引き分け \(t.draws)（うち下が駒得 \(t.drawsLowerAhead)） 所要 \(Int(Date().timeIntervalSince(t0)))s")
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
