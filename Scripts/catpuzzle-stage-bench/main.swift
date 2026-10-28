import Foundation

// おじさんちのねこさがしのステージ（#3048）の計測。`build.sh` の冒頭を参照。
let args = CommandLine.arguments
let first = args.count > 1 ? Int(args[1]) ?? 1 : 1
let last = args.count > 2 ? Int(args[2]) ?? 60 : 60

var worst: [Int: Double] = [:]
print("stage\tsize\ttier\tscore\tcounts\tseconds")
for number in first...last {
    let stage = CatPuzzleStage(number)
    let start = Date()
    let puzzle = stage.makePuzzle()
    let seconds = Date().timeIntervalSince(start)
    let difficulty = CatPuzzleSolver.rate(puzzle, maxTier: 4)
    worst[stage.size.side] = max(worst[stage.size.side] ?? 0, seconds)
    print("\(number)\t\(stage.size.side)\t\(difficulty.tier)\t\(difficulty.score)\t\(difficulty.counts)\t" + String(format: "%.3f", seconds))
}
for (side, seconds) in worst.sorted(by: { $0.key < $1.key }) {
    print("worst \(side)x\(side): " + String(format: "%.3f", seconds) + "s")
}
