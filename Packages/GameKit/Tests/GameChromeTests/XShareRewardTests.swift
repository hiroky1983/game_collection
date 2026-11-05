import Foundation
import SwiftUI
import Testing
import Core

/// 「X でポストして特典をもらう」（#3359）の判定と保存。通常の共有・X 以外・取り消しでは特典を渡さない。
@Suite("X でポストの特典（#3359）")
@MainActor
struct XShareRewardTests {
    @Test("X の共有拡張で完了したときだけ特典の対象。X 以外・完了しなかった・種類なしは対象外")
    func qualifiesOnlyForXCompleted() {
        let x = "com.atebits.Tweetie2.ShareExtension"
        #expect(XShareReward.qualifies(activityType: x, completed: true))
        #expect(!XShareReward.qualifies(activityType: x, completed: false))
        #expect(!XShareReward.qualifies(activityType: "com.apple.UIKit.activity.Message", completed: true))
        #expect(!XShareReward.qualifies(activityType: "com.apple.UIKit.activity.CopyToPasteboard", completed: true))
        #expect(!XShareReward.qualifies(activityType: nil, completed: true))
    }

    @Test("受け取り済みはゲームごとに別々に保存される")
    func claimedPerGame() throws {
        let suite = "asobiba.xshare.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!XShareReward.isClaimed(defaults, gameID: "catpuzzle"))
        XShareReward.markClaimed(defaults, gameID: "catpuzzle")
        #expect(XShareReward.isClaimed(defaults, gameID: "catpuzzle"))
        #expect(!XShareReward.isClaimed(defaults, gameID: "homerun"))
    }
}
