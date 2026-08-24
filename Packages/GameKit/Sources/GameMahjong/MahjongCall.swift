import Foundation
import MahjongTiles

/// 副露（鳴き）1 つ。手牌の外に晒す面子で、`MahjongHand`（門前の枚数配列）とは別に持つ。
///
/// 手牌側を 34 種の枚数配列のままにしておくと「どの牌を誰から鳴いたか」が表せないので、
/// 鳴いた面子だけをこの型で持ち、判定関数には枚数配列と一緒に渡す。
public struct MahjongCall: Equatable, Sendable, Codable, Identifiable {
    public enum Kind: String, Equatable, Sendable, Codable {
        /// ポン（明刻）。
        case pon
        /// チー（明順・上家からのみ）。
        case chi
        /// 大明槓（他家の打牌を槓する）。
        case openKan
        /// 加槓（既にポンしている刻子に 4 枚目を足す）。
        case addedKan
        /// 暗槓（手の内の 4 枚で槓する）。
        case closedKan
    }

    public let kind: Kind
    /// 代表牌。ポン・カンはその牌そのもの、チーは順子の**最小の**牌。
    public let tile: MahjongTile
    /// 鳴いた相手。暗槓は nil。
    public let from: Int?
    /// 鳴き取った牌。暗槓は nil。加槓は足した 4 枚目（元のポンの相手は `from` に残す）。
    public let claimedTile: MahjongTile?

    public init(kind: Kind, tile: MahjongTile, from: Int? = nil, claimedTile: MahjongTile? = nil) {
        self.kind = kind
        self.tile = tile
        self.from = from
        self.claimedTile = claimedTile
    }

    public var id: String {
        "\(kind.rawValue)-\(MahjongTileOrder.index(of: tile))-\(claimedTile.map { MahjongTileOrder.index(of: $0) } ?? -1)"
    }

    /// 晒している牌すべて。槓は 4 枚。ドラ・一色・断幺九の判定はこの牌も数える。
    public var tiles: [MahjongTile] {
        let index = MahjongTileOrder.index(of: tile)
        switch kind {
        case .chi:
            return (0..<3).map { MahjongTileOrder.tile(at: index + $0) }
        case .pon:
            return Array(repeating: tile, count: 3)
        case .openKan, .addedKan, .closedKan:
            return Array(repeating: tile, count: 4)
        }
    }

    public var isKan: Bool {
        kind == .openKan || kind == .addedKan || kind == .closedKan
    }

    /// 副露の**数**が 1 つ増えるか。加槓は既にあるポンを槓子に差し替えるだけなので増えない
    /// （手牌の枚数の勘定がここで変わるので、シャンテン計算に渡す `meldCount` はこれで決める）。
    public var addsMeld: Bool { kind != .addedKan }

    /// 門前を崩すか。**暗槓だけは崩さない**（立直・門前清自摸和・平和などが残る）。
    public var breaksConcealment: Bool { kind != .closedKan }

    /// この副露を作るために**手牌から**抜く牌。鳴き取った 1 枚は手牌に無いので含めない。
    /// 加槓は既にある刻子に足すだけなので 1 枚。
    public var tilesFromHand: [MahjongTile] {
        switch kind {
        case .chi:
            guard let claimed = claimedTile else { return tiles }
            var rest = tiles
            if let position = rest.firstIndex(of: claimed) { rest.remove(at: position) }
            return rest
        case .pon:
            return Array(repeating: tile, count: 2)
        case .openKan:
            return Array(repeating: tile, count: 3)
        case .addedKan:
            return [tile]
        case .closedKan:
            return Array(repeating: tile, count: 4)
        }
    }

    /// 役の判定に使う面子。暗槓だけが「暗」の扱い。
    public var meld: MahjongMeld {
        switch kind {
        case .chi:
            return MahjongMeld(kind: .run, tile: tile, isConcealed: false)
        case .pon:
            return MahjongMeld(kind: .triplet, tile: tile, isConcealed: false)
        case .openKan, .addedKan:
            return MahjongMeld(kind: .kan, tile: tile, isConcealed: false)
        case .closedKan:
            return MahjongMeld(kind: .kan, tile: tile, isConcealed: true)
        }
    }

    /// ボタン・読み上げに使う短い名前。
    public var actionName: String {
        switch kind {
        case .pon: return "ポン"
        case .chi: return "チー"
        case .openKan, .addedKan, .closedKan: return "カン"
        }
    }

    /// 選択肢が複数並ぶときの説明（「チー 3萬・4萬」のように手牌から使う牌を見せる）。
    public var optionDetail: String {
        tilesFromHand.map(\.displayName).joined(separator: "・")
    }
}

/// 鳴ける候補の列挙。状態を持たない純粋関数。
public enum MahjongCallFinder {

    /// 他家の打牌に対して鳴ける候補。優先度の高い順（カン → ポン → チー）に返す。
    ///
    /// - Parameters:
    ///   - hand: 鳴く人の門前の手牌。
    ///   - tile: 捨てられた牌。
    ///   - from: 捨てた人。
    ///   - allowsChi: チーできるか（捨てた人の下家だけ true）。
    public static func claimOptions(
        hand: MahjongHand, tile: MahjongTile, from: Int, allowsChi: Bool
    ) -> [MahjongCall] {
        var result: [MahjongCall] = []
        let held = hand.count(of: tile)
        if held >= 3 {
            result.append(MahjongCall(kind: .openKan, tile: tile, from: from, claimedTile: tile))
        }
        if held >= 2 {
            result.append(MahjongCall(kind: .pon, tile: tile, from: from, claimedTile: tile))
        }
        if allowsChi {
            result.append(contentsOf: chiOptions(hand: hand, tile: tile, from: from))
        }
        return result
    }

    /// チーの候補。同じ牌でも「2・3 で挟む」「3・5 で挟む」のように取り方が複数ありうる。
    private static func chiOptions(hand: MahjongHand, tile: MahjongTile, from: Int) -> [MahjongCall] {
        let index = MahjongTileOrder.index(of: tile)
        guard let offset = MahjongTileOrder.numberOffset(index) else { return [] }
        var result: [MahjongCall] = []
        // 順子の先頭になりうるのは、捨て牌の 2 つ前・1 つ前・その牌自身の 3 通り。
        // 数の小さい順（345m → 456m → 567m）に並べて、選択肢が牌姿の並びと同じ順で出るようにする。
        for back in stride(from: 2, through: 0, by: -1) {
            let start = index - back
            let startOffset = offset - back
            guard startOffset >= 0, startOffset <= 6 else { continue }
            let needed = (0..<3).map { start + $0 }.filter { $0 != index }
            guard needed.allSatisfy({ hand.counts[$0] > 0 }) else { continue }
            result.append(
                MahjongCall(
                    kind: .chi, tile: MahjongTileOrder.tile(at: start), from: from, claimedTile: tile
                )
            )
        }
        return result
    }

    /// 自分の手番でできるカン（暗槓・加槓）。`drawnTile` はツモ牌（鳴いた直後は nil）。
    public static func selfKanOptions(
        hand: MahjongHand, drawnTile: MahjongTile?, melds: [MahjongCall]
    ) -> [MahjongCall] {
        var full = hand
        if let drawnTile { full.add(drawnTile) }
        var result: [MahjongCall] = []
        for index in 0..<MahjongTileOrder.kindCount where full.counts[index] == 4 {
            result.append(MahjongCall(kind: .closedKan, tile: MahjongTileOrder.tile(at: index)))
        }
        for meld in melds where meld.kind == .pon {
            guard full.count(of: meld.tile) >= 1 else { continue }
            result.append(
                MahjongCall(
                    kind: .addedKan, tile: meld.tile, from: meld.from, claimedTile: meld.claimedTile
                )
            )
        }
        return result
    }
}
