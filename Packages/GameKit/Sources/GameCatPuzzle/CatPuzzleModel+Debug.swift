/// 撮影・QA 用の起動引数（`-catpuzzleScenario <名前>`）で狙った画面を作る部分（#3048）。
///
/// シミュレータには自動タップの手段が無いため、チャリンコおじさんの `-simulateRunner` と同じ形で
/// 起動引数から状態を作る。まるごと `#if DEBUG` なので製品には入らない。
#if DEBUG
extension CatPuzzleModel {
    /// - `solved`: 答えの猫を全部置いてクリアにする（クリアのカードが出る）。
    /// - `failed`: 答えでないマスを 3 回見つけようとして、ミス 3 回の結果カードを出す。
    /// - `hint-used-up`: ヒントを上限まで使い切った盤。
    /// - `stage` / `stage:N`: 次に遊ぶ面（N を渡すとその面）を始める。
    /// - `stage-solved` / `stage-solved:N`: 面を始めてすぐクリアにする（「ステージ n クリア！」のカード）。
    /// - `stage-next` / `stage-next:N`: 面をクリアし、2 秒後に「次のステージへ」を押したのと同じ操作をする。
    /// それ以外（`play` など）は何もしない（開始シートを閉じて遊んでいる盤のまま）。
    public func applyDebugScenario(_ scenario: String) async {
        let parts = scenario.split(separator: ":", maxSplits: 1).map(String.init)
        let number = parts.count > 1 ? Int(parts[1]) : nil
        // 前の撮影で終局・提案中のまま保存された盤が戻ってきたら、新しい盤から始める。
        if !parts[0].hasPrefix("stage"), isOver || isOfferingContinue { newGame() }
        switch parts[0] {
        case "solved":
            solveForDebug()
        case "failed":
            let solution = Set(puzzle.solutionCells)
            for cell in (0..<puzzle.cellCount).filter({ !solution.contains($0) }).prefix(Self.maxMistakes) {
                findCat(cell: cell)
            }
        case "hint-used-up":
            while !hints.isExhausted {
                let before = hints.used
                if hints.hasFreeRemaining { useHint() } else { grantAdHint(forGame: gameSerial) }
                if hints.used == before { break }
            }
        case "stage":
            startStage(number)
            await stagePreparation?.value
        case "stage-solved":
            startStage(number)
            await stagePreparation?.value
            solveForDebug()
        case "stage-next":
            startStage(number)
            await stagePreparation?.value
            solveForDebug()
            try? await Task.sleep(for: .seconds(2))
            startStage((stage ?? 1) + 1)
            await stagePreparation?.value
        default:
            break
        }
    }

    private func solveForDebug() {
        for cell in puzzle.solutionCells where marks[cell] != .cat { findCat(cell: cell) }
    }
}
#endif
