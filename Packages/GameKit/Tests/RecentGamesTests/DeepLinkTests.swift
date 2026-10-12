import Foundation
import Testing
@testable import Core

/// ディープリンク（#2141）の URL → 遷移先の対応。`onOpenURL` は App ターゲットにあるので、
/// 読み替えの規則だけをここで固定する。
@Suite("ディープリンクの遷移先")
struct DeepLinkTests {
    private static let openable: Set<String> = ["homerun", "shogi", "2048"]

    private static func destination(_ string: String, openable: Set<String> = openable) -> DeepLink.Destination? {
        DeepLink.destination(for: URL(string: string)!, openableGameIDs: openable)
    }

    @Test("asobiba://game/<id> はそのゲームを開く（柵越えおじさん = homerun）")
    func opensGame() {
        #expect(Self.destination("asobiba://game/homerun") == .game("homerun"))
        #expect(Self.destination("asobiba://game/2048") == .game("2048"))
        #expect(Self.destination("asobiba://game/shogi/") == .game("shogi"), "末尾のスラッシュは許す")
        #expect(Self.destination("asobiba://game/homerun?from=event") == .game("homerun"), "クエリは無視する")
        #expect(Self.destination("ASOBIBA://GAME/homerun") == .game("homerun"), "スキームとホストは大小を問わない")
    }

    @Test("asobiba:// 単体・未知の ID・形の違う URL はハブを開くだけ")
    func fallsBackToHub() {
        #expect(Self.destination("asobiba://") == .hub)
        #expect(Self.destination("asobiba:") == .hub)
        #expect(Self.destination("asobiba://game") == .hub)
        #expect(Self.destination("asobiba://game/") == .hub)
        #expect(Self.destination("asobiba://game/unknown") == .hub)
        #expect(Self.destination("asobiba://game/HOMERUN") == .hub, "ゲーム ID は大小を区別する")
        #expect(Self.destination("asobiba://game/homerun/extra") == .hub)
        #expect(Self.destination("asobiba://settings") == .hub)
    }

    @Test("設定で非表示にしたゲーム（開けるゲームに含まれない）は開かない")
    func hiddenGameIsNotOpened() {
        #expect(Self.destination("asobiba://game/homerun", openable: ["shogi"]) == .hub)
    }

    @Test("自分のスキームでない URL は扱わない")
    func ignoresOtherSchemes() {
        #expect(Self.destination("https://example.com/game/homerun") == nil)
        #expect(Self.destination("other://game/homerun") == nil)
    }
}
