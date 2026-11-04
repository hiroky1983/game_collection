import Foundation
import Core
import CoreEngine

/// `CatPuzzleModel` のデイリー pt（#3204）の加算と Game Center への送信。ファイルだけ分けている（#3309）。

extension CatPuzzleModel {
    /// ステージのクリアで、期間に関係なく（常設・#3298）デイリーの pt を貯めて Game Center へ送る（#3204）。`gameDidFinish` より前に呼び、
    /// `game_end` に `event_points` を載せる。ミスは画面に出ている数（コンティニューで戻したぶんは含まない）。ヒント・猫を教えるは見ない。
    func awardEventPoints() {
        guard stage != nil else { return }
        let earnedOnKey = stage.map { CatPuzzleStage($0).isKey } ?? false
        let earned = CatPuzzleEvent.points(mistakes: mistakes, isKey: earnedOnKey)
        lastEventPoints = earned
        lastEventWasKey = earnedOnKey
        eventTotal = CatPuzzleEvent.add(earned, to: stageDefaults, now: eventNow())
        services?.gameDidEarnEventPoints(gameID: Self.gameID, points: earned)
        submitEventTotalIfNeeded()
    }

    /// 今日の合計のうち Game Center へ未送信のぶんがあれば送る。未ログイン・オフラインでも pt は貯まり、
    /// 送れなかったら送り済みの控えを進めない（次の決着か画面を開いたときに、**その日のうちなら**送り直す。前日分は送らない）。
    public func submitEventTotalIfNeeded() {
        let now = eventNow()
        refreshEventTotal()
        let total = CatPuzzleEvent.total(stageDefaults, now: now)
        let day = CatPuzzleEvent.day(of: now)
        guard total > CatPuzzleEvent.sent(stageDefaults, now: now), eventSubmitTask == nil,
              let reporter = services?.gameCenter, reporter.isSignedIn else { return }
        eventSubmitTask = Task { [weak self] in
            let sent = await reporter.submitWeeklyAndWait(
                gameID: Self.gameID, leaderboardID: GameCenterLeaderboard.catPuzzleEvent, value: total)
            guard let self else { return }
            if sent { CatPuzzleEvent.markSent(total, day: day, in: self.stageDefaults) }
            self.eventSubmitTask = nil
            // 送っているあいだにさらに貯まっていたら続けて送る。失敗したときは繰り返さないが、日をまたいでいたら新しい日の分は送る。
            if sent || CatPuzzleEvent.day(of: self.eventNow()) != day { self.submitEventTotalIfNeeded() }
        }
    }

    /// 今日の合計の送信（`submitEventTotalIfNeeded`）が終わるまで待つ。クリアの流れが、送った pt を含む順位を読むため（#3304）。
    public func awaitEventSubmission() async { await eventSubmitTask?.value }
}
