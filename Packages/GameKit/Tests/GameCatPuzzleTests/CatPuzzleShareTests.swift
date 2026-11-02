import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// ステージのクリアのカードから「今日の pt」を共有する（#3237）。
@Suite("おじさんちのねこさがしの今日の pt の共有")
@MainActor
struct CatPuzzleShareTests {
    private func jst(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func makeModel(now: Date) -> CatPuzzleModel {
        let suite = "asobiba.catpuzzle.share.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = CatPuzzleModel(services: services, stageDefaults: defaults)
        model.eventNow = { now }
        model.refreshEventTotal()
        return model
    }

    private func clearStage(_ model: CatPuzzleModel, _ number: Int) async {
        model.startStage(number)
        await model.stagePreparation?.value
        for cell in model.puzzle.solutionCells where model.marks[cell] != .cat { model.findCat(cell: cell) }
    }

    @Test("開催中にステージをクリアすると共有の文が「今日 npt（m 面クリア）」になる")
    func messageAfterClears() async {
        let model = makeModel(now: jst(2026, 11, 10))
        await clearStage(model, 1)
        await clearStage(model, 2)
        let share = CatPuzzleShare.content(for: model)
        #expect(share?.message == "ねこさがし 今日 6pt（2 面クリア）")
        #expect(!(share?.message.contains("賭") ?? true))
    }

    @Test("期間外のクリアでは共有を出さない")
    func hiddenOutsidePeriod() async {
        let model = makeModel(now: jst(2026, 11, 8))
        await clearStage(model, 1)
        #expect(CatPuzzleShare.content(for: model) == nil)
    }

    @Test("自由に遊ぶ・クリア前は共有を出さない")
    func hiddenInFreePlayAndBeforeClear() async {
        let model = makeModel(now: jst(2026, 11, 10))
        #expect(CatPuzzleShare.content(for: model) == nil)
        model.startStage(1)
        await model.stagePreparation?.value
        #expect(CatPuzzleShare.content(for: model) == nil)
    }

    @Test("今日クリアした面の数は日本時間の 0 時で数え直す")
    func clearsResetAtMidnight() {
        let defaults = UserDefaults(suiteName: "asobiba.catpuzzle.share.clears.\(UUID().uuidString)")!
        CatPuzzleEvent.add(3, to: defaults, now: jst(2026, 11, 10, 1))
        CatPuzzleEvent.add(2, to: defaults, now: jst(2026, 11, 10, 23))
        #expect(CatPuzzleEvent.clears(defaults, now: jst(2026, 11, 10, 23)) == 2)
        #expect(CatPuzzleEvent.clears(defaults, now: jst(2026, 11, 11, 0)) == 0)
        CatPuzzleEvent.add(1, to: defaults, now: jst(2026, 11, 11, 0))
        #expect(CatPuzzleEvent.clears(defaults, now: jst(2026, 11, 11, 9)) == 1)
    }

    @Test("画像は描け、答え（猫の位置）には依存しない")
    func imageIsRenderedAndAnswerIndependent() throws {
        let rooms = [0, 0, 1, 1, 0, 2, 1, 2, 2]
        let a = CatPuzzle(side: 3, rooms: rooms, solution: [0, 2, 1])
        let b = CatPuzzle(side: 3, rooms: rooms, solution: [2, 0, 1])
        let imageA = try #require(CatPuzzleShare.image(puzzle: a, points: 18, clears: 6))
        let imageB = try #require(CatPuzzleShare.image(puzzle: b, points: 18, clears: 6))
        #expect(imageA.width == 720 && imageA.height == 720)
        let pngA = try #require(ClearShareImage.png(imageA))
        let pngB = try #require(ClearShareImage.png(imageB))
        #expect(pngA == pngB, "答えの違う問題で画像が変わった = 答えが画像に出ている")
    }
}
