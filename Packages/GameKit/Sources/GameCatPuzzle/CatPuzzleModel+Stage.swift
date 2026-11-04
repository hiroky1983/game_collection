import Foundation
import Core
import CoreEngine

/// `CatPuzzleModel` のステージ（#3048）の開始・先読み・盤の初期化。ファイルだけ分けている（#3309）。

extension CatPuzzleModel {
    // MARK: - ステージ（#3048）

    /// ステージの進み具合（次に遊ぶ面の番号）の保存キー。進み具合はこの番号だけを持つ（面ごとの記録は持たない）。
    public static let stageProgressKey = "catPuzzleStage"

    /// 次に遊ぶ面の番号（1 始まり）。クリアするたびに 1 つ進み、負けても戻らない。
    public var savedStage: Int { max(1, stageDefaults.integer(forKey: Self.stageProgressKey)) }

    /// ステージの面を始める。`number` を省くと次に遊ぶ面（`savedStage`）。問題はステージ番号から決めた種で作る
    /// （`CatPuzzleStage`・9×9 は数秒かかることがあるので裏で作る）。作っている間は `isPreparingStage` が真で、
    /// 盤は前のまま操作できない。先に作っておいた次の面（`prefetchStage`）があればそれを使う。
    public func startStage(_ number: Int? = nil) {
        let n = max(1, number ?? savedStage)
        // 同じ面を作っている最中の 2 回目（「次のステージへ」の連打）は何もしない（同じ問題を二重に作らない）。
        if isPreparingStage, preparingStage == n { return }
        cancelStagePreparation()
        let request = stageRequest
        pendingTap = nil
        bonusIntro = nil
        crossDrag = nil  // 進行中のスライドは捨てる（盤が変わるため）
        stopwatch.stop()
        isPreparingStage = true
        preparingStage = n
        let task: Task<CatPuzzle, Never>
        if let prefetched, prefetched.number == n {
            task = prefetched.task
        } else {
            // 別の面を先に作っていたら止める（使わない計算を残さない）。
            prefetched?.task.cancel()
            prefetched = nil
            task = Self.makeStagePuzzle(n)
        }
        stageGeneration = task
        stagePreparation = Task { [weak self] in
            let made = await task.value
            guard let self, self.stageRequest == request else { return }
            self.isPreparingStage = false
            self.preparingStage = nil
            self.stageGeneration = nil
            let advanced = self.isSolved && self.stage == n - 1 && CatPuzzleStage(n).entersNewBoard
            self.begin(puzzle: made, size: CatPuzzleStage(n).size, stage: n)
            self.boardAdvance = advanced ? CatPuzzleStage(n).size : nil
            self.bonusIntro = CatPuzzleStage(n).isBonus ? CatPuzzleStage(n).size : nil
            self.prefetchStage(n + 1)
        }
    }

    /// 「8×8 に進んだ！」を下ろす。
    public func clearBoardAdvance() { boardAdvance = nil }

    /// 「ボーナスステージ」の表示を下ろす。
    public func clearBonusIntro() { bonusIntro = nil }

    /// 次の面を裏で作っておく（作り終えた問題は `startStage` が使う）。
    func prefetchStage(_ number: Int) {
        guard prefetched?.number != number else { return }
        prefetched?.task.cancel()
        prefetched = (number, Self.makeStagePuzzle(number))
    }

    /// 作っている最中のステージの問題を捨てる（出来上がっても盤に出さない）。作っている計算も止める
    /// （`CatPuzzleStage.makePuzzle` は取り消されたら途中で抜ける）。止めた計算が先読みのものなら、先読みの記録も消す。
    func cancelStagePreparation() {
        stageRequest += 1
        if let generation = stageGeneration {
            generation.cancel()
            if prefetched?.task == generation { prefetched = nil }
        }
        stageGeneration = nil
        stagePreparation = nil
        isPreparingStage = false
        preparingStage = nil
    }

    /// ステージの問題をメインスレッドの外で作る。
    nonisolated private static func makeStagePuzzle(_ number: Int) -> Task<CatPuzzle, Never> {
        Task.detached(priority: .userInitiated) { CatPuzzleStage(number).makePuzzle() }
    }

    /// `game_start` の `level`。ステージは面の番号（チャリンコおじさんと同じ `stage-N`）、自由に遊ぶは盤の大きさ。
    var analyticsLevel: AnalyticsLevel {
        stage.map { .stage($0) } ?? size.analyticsLevel
    }

    /// 新しい問題で局を始める（自由に遊ぶ・ステージ共通）。
    func begin(puzzle newPuzzle: CatPuzzle, size newSize: CatPuzzleSize, stage newStage: Int?) {
        size = newSize
        stage = newStage
        bonusIntro = nil
        pendingTap = nil
        crossDrag = nil  // 進行中のスライドは捨てる（盤が変わるため）
        stopwatch.stop()
        puzzle = newPuzzle
        keyCat = Self.keyCat(of: newPuzzle, stage: newStage)
        marks = Array(repeating: .empty, count: puzzle.cellCount)
        history.removeAll()
        mistakes = 0
        uncleLine = nil
        continueUsed = false
        isOfferingContinue = false
        hints.reset()
        stageAssistsUsed = 0
        gameSerial += 1
        hintCells = []
        hintCrosses = []
        wrongCrosses = []
        lastWrongCell = nil
        lastHint = nil
        elapsedSeconds = 0
        moves = 0
        isSolved = false
        isFailed = false
        // 開始シートで始めた局は `gameDidRestart` だけで数える（遅らせていた開始は捨てる）。
        pendingInitialStart = false
        showsClearCard = false
        lureCell = nil
        lastEventPoints = nil
        lastEventWasKey = false
        beatNoMissBest = false
        refreshEventTotal()
        solvedAt = nil
        recordResult = nil
        services?.snapshots.clear(for: Self.gameID)
        services?.gameDidRestart(gameID: Self.gameID, level: analyticsLevel)
        // 新しい問題が出た瞬間から計時する（止めるのは画面側のシート・背面など）。
        startTimer()
    }
}
