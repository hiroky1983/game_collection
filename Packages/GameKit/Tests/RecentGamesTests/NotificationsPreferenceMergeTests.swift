import Testing
import CoreEngine

@Suite("通知トグルの統合規則（#1508）")
struct NotificationsPreferenceMergeTests {
    @Test("両方オンなら統合後もオン")
    func bothOnStaysOn() {
        #expect(NotificationsPreferenceMerge.mergedIsEnabled(resume: true, reengagement: true))
    }

    @Test("片方だけオフなら統合後はオフ（利用者が止めた通知を勝手に再開しない）")
    func eitherOffMakesItOff() {
        #expect(!NotificationsPreferenceMerge.mergedIsEnabled(resume: false, reengagement: true))
        #expect(!NotificationsPreferenceMerge.mergedIsEnabled(resume: true, reengagement: false))
    }

    @Test("両方オフなら統合後もオフ")
    func bothOffStaysOff() {
        #expect(!NotificationsPreferenceMerge.mergedIsEnabled(resume: false, reengagement: false))
    }
}
