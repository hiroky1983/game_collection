import Testing
import Foundation
@testable import Core

/// リワード広告の先読み（#658）。実際の `GADRewardedAd` は端末側なので、預かった広告を
/// 「まだ出してよいか」「一度出したら空になるか」だけを検証する。
@Suite("先読みした広告の置き場")
struct PreloadedAdSlotTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test("何も預かっていなければ空")
    func emptyByDefault() {
        var slot = PreloadedAdSlot<String>()
        #expect(!slot.hasFreshAd(now: t0))
        #expect(slot.take(now: t0) == nil)
    }

    @Test("失効前なら取り出せて、取り出したら空になる")
    func takeConsumesFreshAd() {
        var slot = PreloadedAdSlot<String>(lifetime: 60)
        slot.store("ad", loadedAt: t0)
        #expect(slot.hasFreshAd(now: t0.addingTimeInterval(59)))
        #expect(slot.take(now: t0.addingTimeInterval(59)) == "ad")
        // 同じ広告は 2 回出せないので、次の先読みを始められる状態に戻る。
        #expect(!slot.hasFreshAd(now: t0.addingTimeInterval(59)))
        #expect(slot.take(now: t0.addingTimeInterval(59)) == nil)
    }

    @Test("失効したら出さずに捨てる（その回は読み込みに戻る）")
    func expiredAdIsDiscarded() {
        var slot = PreloadedAdSlot<String>(lifetime: 60)
        slot.store("ad", loadedAt: t0)
        #expect(!slot.hasFreshAd(now: t0.addingTimeInterval(60)))
        #expect(slot.take(now: t0.addingTimeInterval(60)) == nil)
        // 捨てたあと時計が戻っても（端末の時刻変更）、古い広告は復活しない。
        #expect(slot.take(now: t0) == nil)
    }

    /// 経過時間が負だと常に寿命未満になり、実時間で失効した広告を出して表示に失敗する。
    @Test("時計が読み込み時より前に戻っていたら失効として捨てる")
    func clockMovedBackwardIsTreatedAsExpired() {
        var slot = PreloadedAdSlot<String>(lifetime: 60)
        slot.store("ad", loadedAt: t0)
        #expect(!slot.hasFreshAd(now: t0.addingTimeInterval(-1)))
        #expect(slot.take(now: t0.addingTimeInterval(-1)) == nil)
        // 取り出しに失敗した時点で捨てているので、時計が戻り直しても出てこない。
        #expect(slot.take(now: t0) == nil)
    }

    @Test("預け直すと古いほうは捨てて新しいほうを使う")
    func storeReplacesPreviousAd() {
        var slot = PreloadedAdSlot<String>(lifetime: 60)
        slot.store("old", loadedAt: t0)
        slot.store("new", loadedAt: t0.addingTimeInterval(50))
        #expect(slot.take(now: t0.addingTimeInterval(100)) == "new")
    }

    /// AdMob のリワード広告は読み込みから 1 時間で失効する。それ以上預かると、
    /// タップ時に表示が失敗して「押したのに何も起きない」に戻る。
    @Test("既定の寿命は AdMob の失効（1 時間）より短い")
    func defaultLifetimeIsShorterThanAdMobExpiry() {
        #expect(PreloadedAdSlot<String>().lifetime < 60 * 60)
        #expect(PreloadedAdSlot<String>().lifetime > 0)
    }
}
