import Foundation

// 将棋 達人（#2698）の計測。`build.sh` で作った単体バイナリの引数:
//   check                 自前の手生成を既存の合法手生成と突き合わせる（乱数の対局 × 局面）
//   nps                   達人の 1 秒あたりの局面数と、読み切る深さ（中盤 24 局面・1 秒）
//   timing [局面数]        出荷の設定（実時間）で 1 手にかかる時間: 平均・最大
//   match <局面数>         達人 対 むずかしい。開始局面ごとに先後を入れ替えて 2 局ずつ
//   probe <SFEN>          1 局面だけ読み、手・値・深さと、指したあとの相手の合法手の数を出す
//   replay <先手が達人 true|false> <開始局面> <USI...>  対局を再生し、達人の手番ごとに達人の読み（手・値・深さ）を出す
//   ablation <局面数>      技法を 1 つ外した達人（OPTIONS）対 出荷の達人（MODE・MASTER_TIME は match と同じ。1 手詰めの検出のように局面数の数え方が変わる技法は MODE=time で比べる）
// 環境変数:
//   MODE=nodes|time       nodes（既定）: 考える時間を局面数に置き換える（同時に走る対局の負荷で強さが揺れない）。
//                         time: 両者とも出荷の実時間で指す（1 手の時間の分布もここで取る）。
//   HARD_NPS / MASTER_NPS nodes のときの 1 秒あたりの局面数（この環境で `nps` を測った値を渡す）
//   MASTER_TIME           達人の考える時間（秒・既定は出荷値）
//   OPTIONS               達人の技法を外す（例: "-nullMove,-lmr"）
//   PLIES（既定 320）・CONCURRENCY（既定 4）・FIRST_OPENING（既定 1）・OPENING_PLIES（既定 6）

let env = ProcessInfo.processInfo.environment

func masterOptions() -> ShogiMasterOptions {
    var o = ShogiMasterOptions.shipped
    for raw in (env["OPTIONS"] ?? "").split(separator: ",") {
        let name = raw.trimmingCharacters(in: .whitespaces)
        let on = !name.hasPrefix("-")
        let key = on ? name : String(name.dropFirst())
        switch key {
        case "aspiration": o.aspiration = on
        case "pvs": o.pvs = on
        case "nullMove": o.nullMove = on
        case "lmr": o.lmr = on
        case "futility": o.futility = on
        case "checkExtension": o.checkExtension = on
        case "mateInOne": o.mateInOne = on
        case "kingSafety": o.kingSafety = on
        case "kingAttackMap": o.kingAttackMap = on
        case "badCaptures": o.badCaptures = on
        default:
            if key.hasPrefix("tt="), let b = Int(key.dropFirst(3)) { o.ttBits = b }
            else if key.hasPrefix("kaw="), let w = Int(key.dropFirst(4)) { o.kingAttackWeight = w } else {
                FileHandle.standardError.write("不明な技法: \(key)\n".data(using: .utf8)!); exit(2)
            }
        }
    }
    return o
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

func referenceMoves(_ pos: Position) -> Set<String> {
    let moves = pos.legalMoves()
    let promoting = Set(moves.compactMap { m -> String? in
        if case let .board(from, to, true) = m { return "\(from)-\(to)" }
        return nil
    })
    return Set(moves.compactMap { m -> String? in
        if case let .board(from, to, false) = m, promoting.contains("\(from)-\(to)"),
           let p = pos.squares[from], [.pawn, .bishop, .rook].contains(p.type) { return nil }
        return m.usi
    })
}

func f3(_ v: Double) -> String { String(format: "%.3f", v) }

enum Result { case masterWon, hardWon, draw(String) }

struct GameRecord {
    var result: Result
    var plies: Int
    var masterTimes: [Double]
    var hardTimes: [Double]
    var kif: [String]
}

func playGame(seed: UInt64, masterIsBlack: Bool, nodes: Bool, hardNPS: Double, masterNPS: Double,
              masterTime: Double, options: ShogiMasterOptions, maxPlies: Int, openingPlies: Int,
              opponentOptions: ShogiMasterOptions? = nil) async -> GameRecord {
    var pos = CPUBenchLadder.opening(seed: seed, plies: openingPlies)
    var seen: [String: Int] = [:]
    var rec = GameRecord(result: .draw("手数"), plies: 0, masterTimes: [], hardTimes: [], kif: [])
    let hardShipped = SimpleMinimaxEngine(level: CPUStrength.hard.rawValue)
    for ply in 0..<maxPlies {
        let moves = pos.legalMoves()
        if moves.isEmpty {
            let masterLost = (pos.sideToMove == .black) == masterIsBlack
            rec.result = masterLost ? .hardWon : .masterWon
            rec.plies = ply
            return rec
        }
        // 千日手（同じ局面 4 回）は引き分け。盤・持ち駒・手番で見る（手数は除く）。
        let key = pos.toSFEN().split(separator: " ").prefix(3).joined(separator: " ")
        seen[key, default: 0] += 1
        if seen[key]! >= 4 { rec.result = .draw("千日手"); rec.plies = ply; return rec }

        let masterToMove = (pos.sideToMove == .black) == masterIsBlack
        let sfen = pos.toSFEN()
        let t = Date()
        let usi: String?
        if masterToMove {
            let e = nodes
                ? ShogiMasterEngine(timeLimit: .infinity, nodeLimit: Int(masterTime * masterNPS), options: options)
                : ShogiMasterEngine(timeLimit: masterTime, options: options)
            usi = await e.bestMove(sfen: sfen)
        } else if let opponentOptions {
            let e = nodes
                ? ShogiMasterEngine(timeLimit: .infinity, nodeLimit: Int(masterTime * masterNPS), options: opponentOptions)
                : ShogiMasterEngine(timeLimit: masterTime, options: opponentOptions)
            usi = await e.bestMove(sfen: sfen)
        } else {
            let e = nodes
                ? SimpleMinimaxEngine(depth: hardShipped.depth, usePositional: true, useQuiescence: true, useBook: true,
                                      timeLimit: .infinity, nodeLimit: Int(hardShipped.timeLimit * hardNPS))
                : hardShipped
            usi = await e.bestMove(sfen: sfen)
        }
        let dt = Date().timeIntervalSince(t)
        if masterToMove { rec.masterTimes.append(dt) } else { rec.hardTimes.append(dt) }
        guard let usi, let m = Move.fromUSI(usi), moves.contains(m) else {
            rec.result = masterToMove ? .hardWon : .masterWon   // 非合法手は反則負け
            rec.plies = ply
            print("反則: \(masterToMove ? "達人" : "むずかしい") \(usi ?? "nil") @ \(sfen)")
            return rec
        }
        rec.kif.append(usi)
        pos.make(m)
    }
    rec.plies = maxPlies
    return rec
}

@main
struct Bench {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 2 else { print("引数が足りません"); return }
        setvbuf(stdout, nil, _IOLBF, 0)
        switch args[1] {
        case "check":
            var rng = MMIXRandom(seed: 2698)
            var checked = 0, bad = 0
            for _ in 0..<(Int(args.count > 2 ? args[2] : "") ?? 300) {
                var pos = Position.start()
                for _ in 0..<200 {
                    let ref = referenceMoves(pos)
                    let mine = Set(ShogiMasterEngine.legalMovesUSI(sfen: pos.toSFEN()))
                    if mine != ref {
                        bad += 1
                        print("不一致 \(pos.toSFEN()): 余分 \(mine.subtracting(ref)) 不足 \(ref.subtracting(mine))")
                        if bad > 5 { return }
                    }
                    checked += 1
                    let moves = pos.legalMoves()
                    if moves.isEmpty { break }
                    let caps = moves.filter { if case let .board(_, to, _) = $0 { return pos.squares[to] != nil }; return false }
                    let pool = !caps.isEmpty && rng.next() % 2 == 0 ? caps : moves
                    pos.make(pool[Int(rng.next() % UInt64(pool.count))])
                }
            }
            print("CHECK \(checked) 局面・不一致 \(bad)")
        case "replay":
            let masterBlack = args[2] == "true"
            var pos = CPUBenchLadder.opening(seed: UInt64(args[3])!, plies: Int(env["OPENING_PLIES"] ?? "") ?? 6)
            let t = Double(env["MASTER_TIME"] ?? "") ?? ShogiMasterEngine.shippedTimeLimit
            for (i, usi) in args.dropFirst(4).enumerated() {
                if (pos.sideToMove == .black) == masterBlack {
                    let r = ShogiMasterEngine(timeLimit: t, options: masterOptions()).analyze(sfen: pos.toSFEN())!
                    print("REPLAY \(i + 1) 指した \(usi) 読み \(r.usi ?? "-") 値 \(r.score) 深さ \(r.depth)")
                }
                guard let m = Move.fromUSI(usi) else { break }
                pos.make(m)
            }
        case "probe":
            let sfen = args.dropFirst(2).joined(separator: " ")
            let r = ShogiMasterEngine(timeLimit: Double(env["MASTER_TIME"] ?? "") ?? 1, options: masterOptions()).analyze(sfen: sfen)!
            var pos = Position.fromSFEN(sfen)!
            pos.make(Move.fromUSI(r.usi!)!)
            print("PROBE \(r.usi!) 値 \(r.score) 深さ \(r.depth) 相手の合法手 \(pos.legalMoves().count)")
        case "nps":
            let sfens = await samplePositions(count: 24)
            var nodes = 0, depthSum = 0
            var seconds = 0.0
            let t1 = Double(env["MASTER_TIME"] ?? "") ?? 1.0
            for sfen in sfens {
                let e = ShogiMasterEngine(timeLimit: t1, options: masterOptions())
                let t = Date()
                guard let r = e.analyze(sfen: sfen) else { continue }
                seconds += Date().timeIntervalSince(t)
                nodes += r.nodes
                depthSum += r.depth
            }
            print("MASTER NPS \(Int(Double(nodes) / seconds)) 平均深さ \(String(format: "%.1f", Double(depthSum) / Double(sfens.count)))（\(sfens.count) 局面・計 \(String(format: "%.1f", seconds)) 秒）")
        case "timing":
            let n = args.count > 2 ? Int(args[2]) ?? 40 : 40
            let sfens = await samplePositions(count: n)
            var wall: [Double] = []
            for sfen in sfens {
                let t = Date()
                _ = await ShogiMasterEngine().bestMove(sfen: sfen)
                wall.append(Date().timeIntervalSince(t))
            }
            wall.sort()
            print("TIMING 達人 上限 \(ShogiMasterEngine.shippedTimeLimit)s: 平均 \(f3(wall.reduce(0, +) / Double(wall.count)))s 中央値 \(f3(wall[wall.count / 2]))s 最大 \(f3(wall.last!))s（\(wall.count) 局面）")
        case "match", "ablation":
            let ablation = args[1] == "ablation"
            let openings = Int(args.count > 2 ? args[2] : "") ?? 50
            let nodes = (env["MODE"] ?? "nodes") != "time"
            let hardNPS = Double(env["HARD_NPS"] ?? "") ?? 53_000
            let masterNPS = Double(env["MASTER_NPS"] ?? "") ?? 1_000_000
            let masterTime = Double(env["MASTER_TIME"] ?? "") ?? ShogiMasterEngine.shippedTimeLimit
            let plies = Int(env["PLIES"] ?? "") ?? 320
            let conc = Int(env["CONCURRENCY"] ?? "") ?? 4
            let first = Int(env["FIRST_OPENING"] ?? "") ?? 1
            let openingPlies = Int(env["OPENING_PLIES"] ?? "") ?? 6
            let options = masterOptions()
            let jobs = (0..<openings).flatMap { i in [true, false].map { (UInt64(first + i), $0) } }
            var next = 0
            var wins = 0, losses = 0, draws = 0
            var masterTimes: [Double] = [], hardTimes: [Double] = []
            var plyCounts: [Int] = []
            if ablation { print("ABLATION 外した側=「達人」 \(env["OPTIONS"] ?? "") 対 出荷の達人（「むずかしい」の欄）") }
            print("MATCH mode=\(nodes ? "nodes" : "time") 達人 \(masterTime)s 対 むずかしい 2s 開始局面 \(first)〜\(first + openings - 1) options=\(env["OPTIONS"] ?? "shipped")")
            await withTaskGroup(of: (UInt64, Bool, GameRecord).self) { group in
                func add() {
                    guard next < jobs.count else { return }
                    let (seed, black) = jobs[next]
                    next += 1
                    group.addTask {
                        (seed, black, await playGame(seed: seed, masterIsBlack: black, nodes: nodes, hardNPS: hardNPS,
                                                     masterNPS: masterNPS, masterTime: masterTime, options: options,
                                                     maxPlies: plies, openingPlies: openingPlies,
                                                     opponentOptions: ablation ? .shipped : nil))
                    }
                }
                for _ in 0..<conc { add() }
                for await (seed, black, rec) in group {
                    let label: String
                    switch rec.result {
                    case .masterWon: wins += 1; label = "達人の勝ち"
                    case .hardWon: losses += 1; label = "むずかしいの勝ち"
                    case .draw(let why): draws += 1; label = "引き分け（\(why)）"
                    }
                    masterTimes += rec.masterTimes
                    hardTimes += rec.hardTimes
                    plyCounts.append(rec.plies)
                    let mx = rec.masterTimes.max() ?? 0
                    print("GAME 開始局面 \(seed) 達人=\(black ? "先手" : "後手") \(label) \(rec.plies) 手 達人の最長 \(f3(mx))s")
                    if case .masterWon = rec.result {} else { print("KIF \(seed) \(black) \(rec.kif.joined(separator: " "))") }
                    add()
                }
            }
            masterTimes.sort()
            let total = wins + losses + draws
            func pct(_ p: Double) -> Double { masterTimes.isEmpty ? 0 : masterTimes[min(masterTimes.count - 1, Int(Double(masterTimes.count) * p))] }
            print("RESULT \(total) 局: 達人 \(wins) 勝 \(losses) 敗 \(draws) 分（勝率 \(String(format: "%.1f", Double(wins) * 100 / Double(max(total, 1))))%）平均手数 \(plyCounts.reduce(0, +) / max(plyCounts.count, 1))")
            print("TIME 達人 \(masterTimes.count) 手: 平均 \(f3(masterTimes.reduce(0, +) / Double(max(masterTimes.count, 1))))s 中央値 \(f3(pct(0.5)))s 95% \(f3(pct(0.95)))s 最大 \(f3(masterTimes.last ?? 0))s / むずかしい 平均 \(f3(hardTimes.reduce(0, +) / Double(max(hardTimes.count, 1))))s 最大 \(f3(hardTimes.max() ?? 0))s")
        default:
            print("不明なコマンド")
        }
    }
}
