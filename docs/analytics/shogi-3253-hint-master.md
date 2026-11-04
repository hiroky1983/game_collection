# 将棋のヒント（達人 3.0 秒）対 達人（2.5 秒）の計測（#3253）

v1.1.15 で将棋のヒントの最善手を達人のエンジン（`ShogiMasterEngine`）で読むようにした（全体の考える時間 2.5＋0.5＝3.0 秒、
詰みの確認の分は引く）。そのヒントと、対局の「達人」（出荷の 2.5 秒）を実時間で対局させ、ヒント側の勝率を測った記録。
計測の作りは `docs/analytics/shogi-2698-master.md`（#2698）と同じ。

## 条件

- 合格: ヒント側の勝率 **50% 以上**（千日手・手数上限の引き分けは勝ちに数えない）
- 計ったコード: `release/v1.1.15`（35e45ff3）

## 計測の作り

- 実行環境（クラウド・Linux）:
  - `uname -a`: `Linux vm 6.18.44-fc-v233 #1 SMP PREEMPT_DYNAMIC @0 x86_64 x86_64 x86_64 GNU/Linux`
  - `nproc`: 4（Intel(R) Xeon(R) Processor @ 2.10GHz）
  - Swift version 6.1 (swift-6.1-RELEASE)
  - 開始 Wed Nov  4 05:34:22 UTC 2026・終了 Wed Nov  4 08:41 UTC 2026（約 3 時間 7 分）
- GameKit 全体は Linux でビルドできないので、#2698 と同じく将棋のエンジンに要るファイルだけを `swiftc -O -wmo` で 1 バイナリにした
  （`Scripts/shogi-master-bench/build.sh` の一覧に、ヒントの詰みの確認に要る `GameShogi/ShogiMateSearch.swift` と、
  定跡が使う `CoreEngine/BookPicker.swift` を足した。`BoardHintBudget` は出荷と同じ値 `engineLevel = CPUStrength.hard.rawValue`・
  `extraThinkingTime = 0.5` のスタブ）。アプリのコードは変えていない。計測用の `main.swift` は下の「計測の再現」に全文を載せた
- **ヒント側はアプリと同じ `SimpleMinimaxEngine.hint().hintAnswer(sfen:)` を毎手呼んだ**（詰みの確認＝自分の 5 手詰・相手の 3 手詰を
  全体の 40% まで、残りの時間で達人が読む）。全体の上限は 3.0 秒（起動時に `hint().timeLimit = 3.0` を出力して確かめた）
  - `.mate` が返ればその手、`.move` が返ればその手を指す
  - `.hopeless`（どの手でも詰まされる）はアプリではヒントが出ないので、対局を続けるため 3.0 秒の `ShogiMasterEngine` で指した
    （このときはもう負けの局面。下の「ヒントの詰みの確認」）
- 相手は出荷の `ShogiMasterEngine()`（2.5 秒）
- 開始局面: `CPUBenchLadder.opening`（平手から乱数で 6 手・駒の損得が歩 1 枚以内）の 1〜50。開始局面ごとに先後を入れ替えて 2 局＝100 局
- 千日手（同じ局面＝盤・持ち駒・手番 4 回）・手数上限 320 手は引き分け。同時に 2 局（4 vCPU）

## 結果（合否）

**100 局でヒント 42 勝 54 敗 4 分（勝率 42.0%）。不合格（50% に届かない）。**

| | 局数 | 勝 | 敗 | 分 | 勝率 |
|---|---|---|---|---|---|
| ヒントが先手 | 50 | 23 | 25 | 2 | 46% |
| ヒントが後手 | 50 | 19 | 29 | 2 | 38% |
| 計 | 100 | **42** | **54** | 4 | **42.0%** |

- 引き分け 4 局: 千日手 3（開始局面 5 ヒント先手 18 手・17 ヒント後手 99 手・34 ヒント後手 69 手）、手数上限 1（開始局面 9 ヒント先手 320 手）
- 手数: 最短 18（千日手）・中央 109・最長 320（手数上限）・平均 113。勝ち負けがついた局だけだと最短 65・最長 226
  （ヒントの勝ち 中央 110・達人の勝ち 中央 108）
- 勝率 42% の 95% 信頼区間はおよそ 32〜52%（100 局の二項分布）。「ヒントの方が強い」とは言えず、むしろ弱い側に寄っている

## 1 手あたりの実測時間（この環境の実時間・同時に 2 局）

| | 手数 | 平均 | 中央値 | 95% | 最大 |
|---|---|---|---|---|---|
| ヒント（`hintAnswer`・上限 3.0 秒） | 5,682 | 2.150 秒 | 2.257 秒 | 2.923 秒 | **2.928 秒** |
| 達人（出荷・2.5 秒） | 5,690 | 1.795 秒 | 1.870 秒 | 2.452 秒 | 2.507 秒 |

ヒントは 3.0 秒を超えた手が無い（最大 2.928 秒）。

## ヒントの詰みの確認

- `.mate`（詰ます手）で指した手: 114 手
- `.hopeless`（受けが無い）で代わりに達人で指した手: 106 手・54 局。**54 局すべて達人が勝った局**（負けが決まってからの手）

## 考えられる理由（確かめていない）

- ヒントは全体 3.0 秒だが、詰みの確認に最大 40%（1.2 秒）を使い、残りで達人が読む。1 手の平均はヒント 2.150 秒・達人 1.795 秒と
  ヒントの方が 0.36 秒長いが、達人の反復深化は締切の手前で次の深さに入らないので、詰みの確認に使った分だけ達人の部分で読める深さが
  相手より浅くなる局面がありうる。詰みの確認と達人の読みの時間の内訳は今回は取っていない
- 詰みの確認で相手の 3 手詰を防ぐ手に根を絞る（`restrictTo`）ので、達人だけで読むのと選ぶ手が変わる局面がある
- 同じ達人どうしで考える時間の差が 0.5 秒（2 割）だけなので、もともと差が出にくい（#2698 の自己対局でも、技法 1 つの差で 45〜55% が多かった）

## 計測の再現

```bash
git checkout origin/release/v1.1.15
# 下の build.sh と main.swift を一時ディレクトリに置いて
bash build.sh /tmp/hb && CONCURRENCY=2 /tmp/hb 50    # 100 局・この環境で約 3 時間
```

<details><summary>build.sh</summary>

```bash
set -euo pipefail
R="$(git rev-parse --show-toplevel)"; G=$R/Packages/GameKit; OUT=$1
WORK=$(mktemp -d)
for f in $G/Sources/CoreEngine/{MMIXRandom,SplitMix64,CPUStrength,BookPicker}.swift \
         $G/Sources/GameShogi/{Move,MoveGenerator,OpeningBook,Position,ShogiSquare,ShogiTypes,ShogiEngine,ShogiMasterEngine,ShogiMateSearch}.swift \
         $G/Tests/GameShogiTests/CPUBenchLadder.swift; do
  grep -v '^import CoreEngine$' "$f" >"$WORK/$(basename "$f")"
done
cp "$(dirname "$0")/main.swift" "$WORK/main.swift"
cat >"$WORK/BenchStubs.swift" <<'SWIFT'
public enum AnalyticsLevel { case novice, beginner, normal, hard }
func tr(_ s: String) -> String { s }
// 出荷の BoardHintBudget（CoreEngine/BoardHintBudget.swift）と同じ値
enum BoardHintBudget { static let engineLevel = CPUStrength.hard.rawValue; static let extraThinkingTime: Double = 0.5 }
SWIFT
swiftc -O -wmo -D SHOGI_BENCH_STANDALONE -parse-as-library -o "$OUT" "$WORK"/*.swift 2>"$WORK/log" || { grep -v warning: "$WORK/log" | head -40; exit 1; }
```
</details>

<details><summary>main.swift</summary>

```swift
import Foundation
// #3253: ヒント（SimpleMinimaxEngine.hint().hintAnswer＝詰みの確認＋達人 3.0 秒）対 出荷の達人（2.5 秒）。実時間。
let env = ProcessInfo.processInfo.environment
func f3(_ v: Double) -> String { String(format: "%.3f", v) }
enum R { case hintWon, masterWon, draw(String) }
struct Rec { var r: R = .draw("手数"); var plies = 0; var hintT: [Double] = []; var mT: [Double] = []; var kif: [String] = []; var mates = 0; var fallback = 0 }

func play(seed: UInt64, hintBlack: Bool, maxPlies: Int) async -> Rec {
    var pos = CPUBenchLadder.opening(seed: seed, plies: 6)
    var seen: [String: Int] = [:]
    var rec = Rec()
    for ply in 0..<maxPlies {
        let moves = pos.legalMoves()
        if moves.isEmpty { rec.r = ((pos.sideToMove == .black) == hintBlack) ? .masterWon : .hintWon; rec.plies = ply; return rec }
        let key = pos.toSFEN().split(separator: " ").prefix(3).joined(separator: " ")
        seen[key, default: 0] += 1
        if seen[key]! >= 4 { rec.r = .draw("千日手"); rec.plies = ply; return rec }
        let hintToMove = (pos.sideToMove == .black) == hintBlack
        let sfen = pos.toSFEN()
        let t = Date()
        var usi: String?
        if hintToMove {
            let h = SimpleMinimaxEngine.hint()
            switch h.hintAnswer(sfen: sfen) {
            case let .move(m)?: usi = m.usi
            case let .mate(m)?: usi = m.usi; rec.mates += 1
            case .hopeless?, nil:
                // ヒントが出ない局面（どの手でも詰まされる）は、アプリならヒントなし。対局を続けるため同じ 3.0 秒の達人で指す。
                rec.fallback += 1
                usi = ShogiMasterEngine(timeLimit: h.timeLimit).analyze(sfen: sfen)?.usi
            }
        } else {
            usi = await ShogiMasterEngine().bestMove(sfen: sfen)
        }
        let dt = Date().timeIntervalSince(t)
        if hintToMove { rec.hintT.append(dt) } else { rec.mT.append(dt) }
        guard let usi, let m = Move.fromUSI(usi), moves.contains(m) else {
            rec.r = hintToMove ? .masterWon : .hintWon; rec.plies = ply
            print("反則: \(hintToMove ? "ヒント" : "達人") \(usi ?? "nil") @ \(sfen)"); return rec
        }
        rec.kif.append(usi); pos.make(m)
    }
    rec.plies = maxPlies
    return rec
}

@main struct Bench {
    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)
        let openings = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 50
        let conc = Int(env["CONCURRENCY"] ?? "") ?? 2
        let first = Int(env["FIRST_OPENING"] ?? "") ?? 1
        let h = SimpleMinimaxEngine.hint()
        print("MATCH ヒント(hintAnswer・全体 \(h.timeLimit)s・level \(h.depth)) 対 達人 \(ShogiMasterEngine.shippedTimeLimit)s 開始局面 \(first)〜\(first + openings - 1) 同時 \(conc)")
        let jobs = (0..<openings).flatMap { i in [true, false].map { (UInt64(first + i), $0) } }
        var next = 0
        var w = [true: 0, false: 0], l = [true: 0, false: 0], d = [true: 0, false: 0]
        var hT: [Double] = [], mT: [Double] = [], plies: [Int] = [], mates = 0, fb = 0
        await withTaskGroup(of: (UInt64, Bool, Rec).self) { g in
            func add() { guard next < jobs.count else { return }; let (s, b) = jobs[next]; next += 1
                g.addTask { (s, b, await play(seed: s, hintBlack: b, maxPlies: 320)) } }
            for _ in 0..<conc { add() }
            for await (s, b, r) in g {
                let label: String
                switch r.r { case .hintWon: w[b]! += 1; label = "ヒントの勝ち"; case .masterWon: l[b]! += 1; label = "達人の勝ち"; case .draw(let y): d[b]! += 1; label = "引き分け（\(y)）" }
                hT += r.hintT; mT += r.mT; plies.append(r.plies); mates += r.mates; fb += r.fallback
                print("GAME 開始局面 \(s) ヒント=\(b ? "先手" : "後手") \(label) \(r.plies) 手 ヒント最長 \(f3(r.hintT.max() ?? 0))s 達人最長 \(f3(r.mT.max() ?? 0))s 詰み手 \(r.mates) hopeless \(r.fallback)")
                print("KIF \(s) \(b) \(r.kif.joined(separator: " "))")
                add()
            }
        }
        hT.sort(); mT.sort(); plies.sort()
        func st(_ a: [Double]) -> String { a.isEmpty ? "-" : "\(a.count) 手 平均 \(f3(a.reduce(0,+)/Double(a.count))) 中央 \(f3(a[a.count/2])) 95% \(f3(a[min(a.count-1, Int(Double(a.count)*0.95))])) 最大 \(f3(a.last!))" }
        let W = w[true]! + w[false]!, L = l[true]! + l[false]!, D = d[true]! + d[false]!
        print("RESULT \(W+L+D) 局: ヒント \(W) 勝 \(L) 敗 \(D) 分（勝率 \(String(format: "%.1f", Double(W)*100/Double(max(W+L+D,1))))%）")
        print("SIDE ヒント先手: \(w[true]!) 勝 \(l[true]!) 敗 \(d[true]!) 分 / ヒント後手: \(w[false]!) 勝 \(l[false]!) 敗 \(d[false]!) 分")
        print("PLIES 最短 \(plies.first ?? 0) 中央 \(plies.isEmpty ? 0 : plies[plies.count/2]) 最長 \(plies.last ?? 0) 平均 \(plies.reduce(0,+)/max(plies.count,1))")
        print("TIME ヒント \(st(hT))")
        print("TIME 達人 \(st(mT))")
        print("HINT 詰み手で指した \(mates) 手 / hopeless で達人に代えた \(fb) 手")
    }
}
```
</details>
