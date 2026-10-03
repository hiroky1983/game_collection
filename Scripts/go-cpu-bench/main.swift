import Foundation

// 囲碁 CPU の計測（#1465）。`build.sh` で作った単体バイナリの引数:
//   speed                                1 秒あたりのプレイアウト数（最適化ビルド・1 スレッド）
//   timing [positions]                   出荷の設定（実時間の上限つき）で 1 手にかかる時間: 平均・最大・上限で打ち切られた割合
//                                        （TIMING_PLAYOUT_SCALE=10 で回数の上限を 10 倍にし、時間で打ち切る場合を確かめる）
//   match <上> <上の確率> <下> <下の確率> <開始局面数>
//                                        上の段階と下の段階を、先後入れ替えで開始局面数×2 局。確率は 0...1 か shipped（出荷値）。
//                                        段階は novice / easy / normal / hard。`easy/1000` のように / の後ろに
//                                        回数の上限を書くと、出荷値の代わりにその回数で打ち切る（#1566）
//   random <段階> <確率|shipped> <開始局面数>  一様乱択の相手（眼は埋めない）と先後入れ替えで開始局面数×2 局
// 対局は実時間の上限を外し、回数の上限（出荷値）だけで打ち切る（`CPUBenchLadder.Player.config`）。
// 環境変数: CONCURRENCY（既定 4）・FIRST_OPENING（最初の開始局面の番号・既定 1。小分けにして続きから回すとき）。

func level(_ spec: String) -> GoLevel {
    switch spec.split(separator: "/").first.map(String.init) ?? spec {
    case "novice": return .novice
    case "easy": return .easy
    case "normal": return .normal
    default: return .hard
    }
}

/// `easy/1000` の `/` の後ろ（回数の上限の差し替え）。無ければ nil（出荷値）。
func playoutsOverride(_ spec: String) -> Int? {
    let parts = spec.split(separator: "/")
    return parts.count > 1 ? Int(parts[1]) : nil
}

let env = ProcessInfo.processInfo.environment

/// 中盤の局面を集める（少ない回数の読みで打った対局から、6 手おきに拾う）。
func samplePositions(count: Int) -> [GoState] {
    let ruleset = GoRuleset(size: 9)
    var out: [GoState] = []
    var seed: UInt64 = 1
    while out.count < count {
        var state = GoState.initial(ruleset: ruleset)
        var ply = 0
        while !state.isTwoPassEnd, ply < 70 {
            if ply >= 6 && ply % 6 == 0 { out.append(state) }
            let move = GoEngine(config: GoEngineConfig(playouts: 300, seed: seed &* 1000 &+ UInt64(ply), timeLimit: nil),
                                ruleset: ruleset).bestMove(state: state)
            state.play(move)
            ply += 1
        }
        seed += 1
    }
    return Array(out.prefix(count))
}

@main
struct Bench {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else { print("引数が足りません"); return }
        setvbuf(stdout, nil, _IOLBF, 0)
        let ruleset = GoRuleset(size: 9)
        func f(_ v: Double) -> String { String(format: "%.3f", v) }
        switch args[1] {
        case "speed":
            let states = samplePositions(count: 24)
            var playouts = 0
            var seconds = 0.0
            for state in states {
                let t = Date()
                let r = GoEngine(config: GoEngineConfig(playouts: 4_000, timeLimit: nil), ruleset: ruleset).search(state: state)
                seconds += Date().timeIntervalSince(t)
                playouts += r.playouts
            }
            print("SPEED \(Int(Double(playouts) / seconds)) 回/秒（\(states.count) 局面・計 \(String(format: "%.1f", seconds)) 秒）")
        case "timing":
            let n = args.count > 2 ? Int(args[2]) ?? 40 : 40
            let states = samplePositions(count: n)
            // 回数の上限を何倍かにして、遅い端末で時間の上限が先に来る場合を再現する（TIMING_PLAYOUT_SCALE・既定 1）。
            let scale = Int(env["TIMING_PLAYOUT_SCALE"] ?? "") ?? 1
            for l in GoLevel.allCases {
                var wall: [Double] = []
                var playouts: [Int] = []
                var cut = 0
                for (i, state) in states.enumerated() {
                    let t = Date()
                    var config = GoEngineConfig.level(l, seed: UInt64(i + 1))
                    config.playouts *= scale
                    let r = GoEngine(config: config, ruleset: ruleset).search(state: state)
                    wall.append(Date().timeIntervalSince(t))
                    playouts.append(r.playouts)
                    if r.timedOut { cut += 1 }
                }
                print("TIMING \(l.label) 上限 \(l.timeLimit)s・\(l.playouts) 回: 実時間 平均 \(f(wall.reduce(0, +) / Double(wall.count)))s 最大 \(f(wall.max()!))s / 回数 平均 \(playouts.reduce(0, +) / playouts.count) / 時間で打ち切り \(cut)/\(wall.count)（\(cut * 100 / wall.count)%）")
            }
        case "match", "random":
            let conc = Int(env["CONCURRENCY"] ?? "") ?? 4
            let first = Int(env["FIRST_OPENING"] ?? "") ?? 1
            let t0 = Date()
            if args[1] == "match" {
                guard args.count >= 6 else { print("引数が足りません: match <上> <上の確率> <下> <下の確率> [開始局面数]"); return }
                let up = level(args[2]), low = level(args[4])
                let upP: Double? = args[3] == "shipped" ? nil : Double(args[3])
                let p: Double? = args[5] == "shipped" ? nil : Double(args[5])
                let openings = args.count > 6 ? Int(args[6]) ?? 20 : 20
                let t = CPUBenchLadder.run(upper: .init(level: up, bestMoveChance: upP, playouts: playoutsOverride(args[2])),
                                           lower: .init(level: low, bestMoveChance: p, playouts: playoutsOverride(args[4])),
                                           openings: openings, firstOpening: first, concurrency: conc)
                print("MATCH \(up.label)[\(args[2])](確率 \(args[3])) 対 \(low.label)[\(args[4])](確率 \(args[5])) 開始局面 \(first)〜\(first + openings - 1): \(t.games)局 上の勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws) 所要 \(Int(Date().timeIntervalSince(t0)))s")
            } else {
                guard args.count >= 4 else { print("引数が足りません: random <段階> <確率|shipped> [開始局面数]"); return }
                let l = level(args[2])
                let p: Double? = args[3] == "shipped" ? nil : Double(args[3])
                let openings = args.count > 4 ? Int(args[4]) ?? 50 : 50
                let t = CPUBenchLadder.run(upper: .init(level: l, bestMoveChance: p), lower: .random(),
                                           openings: openings, firstOpening: first, concurrency: conc)
                print("RANDOM \(l.label)(確率 \(args[3])) 対 一様乱択 開始局面 \(first)〜\(first + openings - 1): \(t.games)局 勝ち \(t.upperWins) 負け \(t.lowerWins) 引き分け \(t.draws) 所要 \(Int(Date().timeIntervalSince(t0)))s")
            }
        default:
            print("不明なコマンド")
        }
    }
}
