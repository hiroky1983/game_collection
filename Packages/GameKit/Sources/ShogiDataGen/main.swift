/// 将棋の訓練データ生成ツール。
/// Usage: swift run --package-path Packages/GameKit ShogiDataGen [num_positions] [output.csv]
/// 出力: features[0..94],label の CSV (label = 評価関数スコア / 1000.0)
import Foundation
import GameShogi

let numPositions = Int(CommandLine.arguments.dropFirst().first ?? "80000") ?? 80000
let outputPath = CommandLine.arguments.dropFirst().dropFirst().first ?? "shogi_train.csv"

let engine = SimpleMinimaxEngine(level: 1)
var rng = SystemRandomNumberGenerator()

var lines: [String] = []
var collected = 0
var games = 0

while collected < numPositions {
    var pos = Position.start()
    var moveCount = 0

    while moveCount < 200 {
        let moves = pos.legalMoves()
        guard !moves.isEmpty else { break }

        // 序盤10手はランダム、以降は30%ランダム + 70%で適当な手
        let move: Move
        if moveCount < 10 || Int.random(in: 0..<10, using: &rng) < 3 {
            move = moves[Int.random(in: 0..<moves.count, using: &rng)]
        } else {
            move = moves[Int.random(in: 0..<min(10, moves.count), using: &rng)]
        }

        // 序盤10手以降の局面を記録
        if moveCount >= 10 {
            let sfen = pos.toSFEN()
            if let label = engine.staticEval(sfen: sfen) {
                let features = PositionFeatures.encode(pos)
                let row = features.map { String(format: "%.4f", $0) }.joined(separator: ",")
                    + "," + String(format: "%.6f", label)
                lines.append(row)
                collected += 1
                if collected % 10000 == 0 {
                    fputs("  \(collected)/\(numPositions) positions (\(games) games)\n", stderr)
                }
                if collected >= numPositions { break }
            }
        }

        pos.make(move)
        moveCount += 1
    }

    games += 1
}

// 書き出し
let header = (0..<PositionFeatures.size).map { "f\($0)" }.joined(separator: ",") + ",label"
let csv = ([header] + lines).joined(separator: "\n")
try! csv.write(toFile: outputPath, atomically: true, encoding: .utf8)
fputs("Saved \(collected) positions to \(outputPath) (\(games) games)\n", stderr)
