import Testing
@testable import GameMahjong

/// 卓上の手牌一覧からも打牌できるようにした変更（#378）の検証。
///
/// 一覧と卓下の操作行は**同じ ID・同じ判定**を通すことで選択が同期する設計なので、
/// 検証もその2点（ID の作り方と `MahjongHandTap.outcome` の分岐）に対して行う。
@Suite("麻雀: 手牌タップ（卓上一覧・卓下の操作行の共通判定）")
struct MahjongHandTapTests {
    private let hand0 = MahjongHandTap.handTileID(index: 0)
    private let hand1 = MahjongHandTap.handTileID(index: 1)

    @Test("1タップ目は選択だけで、打牌は起きない（誤タップ防止の2段階打牌）")
    func firstTapOnlySelects() {
        #expect(
            MahjongHandTap.outcome(
                tappedID: hand0, selectedID: nil, isPlayerTurn: true, isDiscardable: true
            ) == .select(hand0)
        )
    }

    @Test("選択中の牌をもう一度タップすると打牌になる")
    func secondTapOnSameTileDiscards() {
        #expect(
            MahjongHandTap.outcome(
                tappedID: hand0, selectedID: hand0, isPlayerTurn: true, isDiscardable: true
            ) == .discard
        )
    }

    @Test("別の牌をタップしたら選択が移るだけで、打牌はしない")
    func tappingAnotherTileOnlyMovesSelection() {
        #expect(
            MahjongHandTap.outcome(
                tappedID: hand1, selectedID: hand0, isPlayerTurn: true, isDiscardable: true
            ) == .select(hand1)
        )
    }

    @Test("自分の手番でなければ何も起きない（選択も打牌もしない）")
    func ignoresTapWhenNotPlayerTurn() {
        #expect(
            MahjongHandTap.outcome(
                tappedID: hand0, selectedID: nil, isPlayerTurn: false, isDiscardable: true
            ) == .ignored
        )
        // 選択済みの牌でも、手番が移っていれば打牌に化けてはいけない。
        #expect(
            MahjongHandTap.outcome(
                tappedID: hand0, selectedID: hand0, isPlayerTurn: false, isDiscardable: true
            ) == .ignored
        )
    }

    @Test("切れない牌（立直中の制限など）は選択も打牌もできない")
    func ignoresTapOnUndiscardableTile() {
        #expect(
            MahjongHandTap.outcome(
                tappedID: hand0, selectedID: nil, isPlayerTurn: true, isDiscardable: false
            ) == .ignored
        )
        // 立直宣言をまたいで選択が残っていても、切れなくなった牌は打牌に進ませない。
        #expect(
            MahjongHandTap.outcome(
                tappedID: hand0, selectedID: hand0, isPlayerTurn: true, isDiscardable: false
            ) == .ignored
        )
    }

    @Test("手牌の ID は位置ごとに異なり、ツモ牌の ID とも衝突しない")
    func tileIDsAreUniquePerSlot() {
        let ids = (0..<14).map { MahjongHandTap.handTileID(index: $0) } + [MahjongHandTap.drawnTileID]
        #expect(Set(ids).count == ids.count)
    }

    @Test("同じ位置の ID は呼ぶたびに同じ（一覧と操作行で選択が同期する根拠）")
    func tileIDIsStableForTheSameSlot() {
        #expect(MahjongHandTap.handTileID(index: 3) == MahjongHandTap.handTileID(index: 3))
        #expect(MahjongHandTap.handTileID(index: 3) != MahjongHandTap.handTileID(index: 4))
    }
}
