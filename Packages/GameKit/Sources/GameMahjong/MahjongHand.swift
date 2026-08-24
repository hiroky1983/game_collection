import Foundation
import MahjongTiles

/// 標準 34 種に 0〜33 の通し番号を振る。
///
/// 手牌の判定（シャンテン・和了・役）は「34 要素の枚数配列」で行うのが最も速く単純なので、
/// `MahjongTile` と添字の変換をここ 1 か所に閉じ込める。並びは `MahjongTile.all` と同じ
/// （萬子 1〜9 → 筒子 1〜9 → 索子 1〜9 → 風牌 東南西北 → 三元牌 中發白）。
public enum MahjongTileOrder {
    /// 牌の種類数。
    public static let kindCount = 34

    /// 添字順に並べた 34 種。
    public static let all: [MahjongTile] = MahjongTile.all

    public static func index(of tile: MahjongTile) -> Int {
        switch tile {
        case .characters(let n): return n - 1
        case .circles(let n):    return 8 + n
        case .bamboos(let n):    return 17 + n
        case .wind(let n):       return 27 + n
        case .dragon(let n):     return 31 + n
        }
    }

    public static func tile(at index: Int) -> MahjongTile {
        all[index]
    }

    /// 数牌（萬子・筒子・索子）の添字か。
    public static func isNumber(_ index: Int) -> Bool { index < 27 }

    /// 数牌なら 0〜8（= 数 - 1）、字牌なら nil。
    public static func numberOffset(_ index: Int) -> Int? {
        isNumber(index) ? index % 9 : nil
    }

    /// 幺九牌（1・9 と字牌）か。
    public static func isTerminalOrHonor(_ index: Int) -> Bool {
        guard let offset = numberOffset(index) else { return true }
        return offset == 0 || offset == 8
    }

    /// 幺九牌の添字（国士無双・混老頭の判定に使う）。
    public static let terminalsAndHonors: [Int] = (0..<kindCount).filter(isTerminalOrHonor)

    /// ドラ表示牌の次の牌（= ドラ）。数牌は 9 → 1、風牌は北 → 東、三元牌は白 → 中で回る。
    public static func doraIndex(after indicator: Int) -> Int {
        if let offset = numberOffset(indicator) {
            let suitHead = indicator - offset
            return suitHead + (offset + 1) % 9
        }
        // 風牌 27〜30 は東 → 南 → 西 → 北 → 東 と添字の順に回る。
        if indicator <= 30 { return 27 + (indicator - 27 + 1) % 4 }
        // 三元牌はドラの巡りが白 → 發 → 中 → 白 で、添字の並び（31 中 / 32 發 / 33 白）とは
        // **逆向き**。+1 すると中 → 發になってしまうので、1 つ戻す（= +2 の剰余）。
        return 31 + (indicator - 31 + 2) % 3
    }
}

/// 手牌（枚数配列）。副露を扱わない（門前のみ・#106 の決裁 A）ので、手牌はこの 1 つで表せる。
public struct MahjongHand: Equatable, Sendable, Codable {
    /// 34 種それぞれの枚数。
    public private(set) var counts: [Int]

    public init() {
        counts = Array(repeating: 0, count: MahjongTileOrder.kindCount)
    }

    public init(counts: [Int]) {
        precondition(counts.count == MahjongTileOrder.kindCount, "枚数配列は 34 要素でなければならない")
        self.counts = counts
    }

    public init(tiles: [MahjongTile]) {
        self.init()
        for tile in tiles { add(tile) }
    }

    /// 手牌の総枚数。
    public var total: Int { counts.reduce(0, +) }

    /// 並べ替え済みの牌（画面表示・読み上げ用）。
    public var tiles: [MahjongTile] {
        (0..<MahjongTileOrder.kindCount).flatMap { index in
            Array(repeating: MahjongTileOrder.tile(at: index), count: counts[index])
        }
    }

    public func count(of tile: MahjongTile) -> Int {
        counts[MahjongTileOrder.index(of: tile)]
    }

    public mutating func add(_ tile: MahjongTile) {
        counts[MahjongTileOrder.index(of: tile)] += 1
    }

    public mutating func remove(_ tile: MahjongTile) {
        let index = MahjongTileOrder.index(of: tile)
        guard counts[index] > 0 else { return }
        counts[index] -= 1
    }

    public func removing(_ tile: MahjongTile) -> MahjongHand {
        var copy = self
        copy.remove(tile)
        return copy
    }

    public func adding(_ tile: MahjongTile) -> MahjongHand {
        var copy = self
        copy.add(tile)
        return copy
    }
}
