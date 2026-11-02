import Foundation

// 同梱ステージの問題の書き出し。`build.sh` の冒頭を参照。
let args = CommandLine.arguments
let first = args.count > 1 ? Int(args[1]) ?? 1 : 1
let last = args.count > 2 ? Int(args[2]) ?? first : first
let step = args.count > 3 ? max(1, Int(args[3]) ?? 1) : 1
let offset = args.count > 4 ? Int(args[4]) ?? 0 : 0
guard first <= last else {
    fputs("最初の面は最後の面以下にしてください\n", stderr)
    exit(2)
}

for number in first...last where (number - first) % step == offset {
    let puzzle = CatPuzzleStage(number).generatePuzzle()
    let line = puzzle.rooms.map { String($0, radix: 16) }.joined() + "|" + puzzle.solution.map { String($0, radix: 16) }.joined()
    print("\(number)\t\(line)")
    fflush(stdout)
}
