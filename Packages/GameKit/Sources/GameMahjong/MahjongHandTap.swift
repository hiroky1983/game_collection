/// 手牌の牌をタップしたときに何が起きるかだけを決める純ロジック（#378）。
///
/// 打牌できる面が2つある: 卓下の操作行（`MahjongView.handOnTable`・大きい牌・横スクロール）と、
/// 卓上の一覧（`MahjongView.handOverviewOnTable`・14枚を縮小して一望できる）。
/// 誤タップ防止の2段階打牌（1タップ目は選択だけ・同じ牌の2タップ目で打牌）を**両方の面で同一**に
/// するため、判定をビューから切り出してここに集約する。SwiftUI のタップは実機なしでは叩けないが、
/// この純関数ならテストで直接検証できる。
enum MahjongHandTapOutcome: Equatable {
    /// 自分の手番でない、または立直中で切れない牌などの既存ガードに弾かれた。何もしない。
    case ignored
    /// 1タップ目。この ID を選択状態にする。
    case select(String)
    /// 選択済みの牌をもう一度タップした。選択を解除して打牌する。
    case discard
}

enum MahjongHandTap {
    /// タップされた牌の ID と現在の選択から、起こすべきことを決める。
    ///
    /// 別の牌をタップしたときは選択の切り替えだけで、打牌はしない（`select`）。
    static func outcome(
        tappedID: String,
        selectedID: String?,
        isPlayerTurn: Bool,
        isDiscardable: Bool
    ) -> MahjongHandTapOutcome {
        guard isPlayerTurn, isDiscardable else { return .ignored }
        return tappedID == selectedID ? .discard : .select(tappedID)
    }

    /// 手牌 n 枚目（`MahjongModel.playerHand.tiles` の位置）を指す ID。
    ///
    /// **卓上一覧と卓下の操作行が同じ ID を使うことで、選択がそのまま同期する**。
    /// 牌の値ではなく位置で作るのは、同じ牌が複数枚あっても区別するためと、
    /// 手牌が毎回ゼロから並べ直される配列で identity を安定させるため（`handOnTable` のコメント参照）。
    static func handTileID(index: Int) -> String { "hand\(index)" }

    /// ツモ牌を指す ID。手牌とは別枠なので位置に依存しない固定値。
    static let drawnTileID = "drawn"
}
