import Testing
import Foundation
@testable import Core

@MainActor
private final class SpyReturnScheduler: ChallengeReturnReminderScheduler {
    var status: ReminderAuthorization
    var statusAfterRequest: ReminderAuthorization
    private(set) var requested = 0
    private(set) var scheduled: [(fireDate: Date, title: String, body: String)] = []
    private(set) var cancelled = 0

    init(status: ReminderAuthorization = .authorized, statusAfterRequest: ReminderAuthorization = .authorized) {
        self.status = status
        self.statusAfterRequest = statusAfterRequest
    }

    func authorization() async -> ReminderAuthorization { status }
    func requestExplicitAuthorization() async -> ReminderAuthorization {
        requested += 1
        status = statusAfterRequest
        return status
    }
    func pendingFireDate() async -> Date? { scheduled.last?.fireDate }
    func schedule(fireDate: Date, title: String, body: String) async {
        scheduled = [(fireDate, title, body)]   // 同じ識別子で置き換わる
    }
    func cancel() { cancelled += 1; scheduled = [] }
}

@MainActor
@Suite("挑戦回数が戻ったら知らせる（#1576）")
struct ChallengeReturnReminderTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private var fire: Date { now.addingTimeInterval(3600) }

    private func make(_ spy: SpyReturnScheduler, enabled: Bool = true) -> ChallengeReturnReminderService {
        ChallengeReturnReminderService(scheduler: spy, isEnabled: { enabled }, now: { now })
    }

    @Test("許可済みなら 1 件だけ予約し、繰り返し押しても 1 件のまま")
    func schedulesOnce() async {
        let spy = SpyReturnScheduler()
        let service = make(spy)
        #expect(await service.enable(fireDate: fire, title: "t", body: "b") == .scheduled)
        #expect(await service.enable(fireDate: fire, title: "t", body: "b") == .scheduled)
        #expect(spy.scheduled.count == 1)
        #expect(spy.scheduled.first?.fireDate == fire)
        #expect(await service.pendingFireDate() == fire)
    }

    @Test("設定の「通知」がオフなら予約せず、許可も求めない")
    func respectsSharedSetting() async {
        let spy = SpyReturnScheduler(status: .notDetermined)
        let service = make(spy, enabled: false)
        #expect(await service.enable(fireDate: fire, title: "t", body: "b") == .notificationsOff)
        #expect(spy.scheduled.isEmpty)
        #expect(spy.requested == 0)
    }

    @Test("未決定なら標準の許可ダイアログを求め、拒否されたら予約しない")
    func asksThenDenied() async {
        let spy = SpyReturnScheduler(status: .notDetermined, statusAfterRequest: .denied)
        let service = make(spy)
        #expect(await service.enable(fireDate: fire, title: "t", body: "b") == .denied)
        #expect(spy.requested == 1)
        #expect(spy.scheduled.isEmpty)
    }

    @Test("未決定から許可されれば予約する")
    func asksThenGranted() async {
        let spy = SpyReturnScheduler(status: .notDetermined)
        let service = make(spy)
        #expect(await service.enable(fireDate: fire, title: "t", body: "b") == .scheduled)
        #expect(spy.requested == 1)
    }

    @Test("発火時刻が過ぎていれば予約しない")
    func expired() async {
        let spy = SpyReturnScheduler()
        let service = make(spy)
        #expect(await service.enable(fireDate: now, title: "t", body: "b") == .expired)
        #expect(spy.scheduled.isEmpty)
    }

    @Test("取り消すと予約が消える")
    func cancelRemoves() async {
        let spy = SpyReturnScheduler()
        let service = make(spy)
        _ = await service.enable(fireDate: fire, title: "t", body: "b")
        service.cancel()
        #expect(spy.scheduled.isEmpty)
        #expect(await service.pendingFireDate() == nil)
    }
}
