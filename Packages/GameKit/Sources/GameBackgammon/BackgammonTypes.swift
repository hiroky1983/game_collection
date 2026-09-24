import Foundation

/// 対局者。人間は常に白（`BackgammonModel.humanSide`）で、24 → 1 の向きに進む。黒（CPU）は 1 → 24。
public enum BackgammonSide: Int, Codable, Sendable, CaseIterable {
    case white = 0
    case black = 1

    public var opponent: BackgammonSide { self == .white ? .black : .white }

    /// 盤の添字（0 = 1 ポイント … 23 = 24 ポイント）に対する進行方向。白は減る向き、黒は増える向き。
    var direction: Int { self == .white ? -1 : 1 }

    /// 白から見た「自分の 1 ポイントからの距離」に揃えた添字（0 = 自陣の 1 ポイント側）。
    /// 評価やベアオフの判定を 1 本の式で書くための正規化。
    func normalized(_ index: Int) -> Int { self == .white ? index : BackgammonBoard.pointCount - 1 - index }
}

/// 決着の種類。ギャモン・バックギャモンは負けた側の駒の状態で決まる（ダブリングキューブは持たない）。
public enum BackgammonWinKind: Int, Codable, Sendable {
    /// 相手も 1 個以上あがっている。1 点。
    case single = 1
    /// 相手が 1 個もあがっていない。2 点。
    case gammon = 2
    /// 相手が 1 個もあがっておらず、さらにバーか勝者の自陣に駒を残している。3 点。
    case backgammon = 3

    public var label: String {
        switch self {
        case .single:     return "勝ち"
        case .gammon:     return "ギャモン勝ち"
        case .backgammon: return "バックギャモン勝ち"
        }
    }
}

/// 1 個の駒の移動。`from` / `to` は盤の添字で、バーからの入場は `from == bar`、あがりは `to == off`。
public struct BackgammonMove: Hashable, Sendable, Codable {
    public let from: Int
    public let to: Int
    /// 使った目。
    public let die: Int
    /// 相手のブロット（1 個だけの駒）を叩いてバーへ送るか。
    public let hits: Bool

    public init(from: Int, to: Int, die: Int, hits: Bool) {
        self.from = from
        self.to = to
        self.die = die
        self.hits = hits
    }
}

/// 盤面。`points[i]` は i 番目のポイント（0 = 白の 1 ポイント）にある駒の数で、**正が白・負が黒**。
/// バーとあがった駒は色ごとに別に数える。値型なので探索・巻き戻しはコピーで済む。
public struct BackgammonBoard: Equatable, Hashable, Sendable, Codable {
    public static let pointCount = 24
    public static let checkersPerSide = 15
    /// `BackgammonMove.from` に使う「バーから」の印。
    public static let bar = 24
    /// `BackgammonMove.to` に使う「あがり」の印。
    public static let off = 25

    public var points: [Int]
    /// バーにある駒の数。添字は `BackgammonSide.rawValue`。
    public var bar: [Int]
    /// あがった駒の数。添字は `BackgammonSide.rawValue`。
    public var off: [Int]

    /// 初期配置（白: 24 に 2・13 に 5・8 に 3・6 に 5。黒はその点対称）。
    public init() {
        var p = Array(repeating: 0, count: Self.pointCount)
        p[23] = 2; p[12] = 5; p[7] = 3; p[5] = 5
        p[0] = -2; p[11] = -5; p[16] = -3; p[18] = -5
        points = p
        bar = [0, 0]
        off = [0, 0]
    }

    public init(points: [Int], bar: [Int], off: [Int]) {
        self.points = points
        self.bar = bar
        self.off = off
    }

    /// そのポイントの駒の持ち主。空なら nil。
    public func owner(at index: Int) -> BackgammonSide? {
        guard points.indices.contains(index), points[index] != 0 else { return nil }
        return points[index] > 0 ? .white : .black
    }

    /// そのポイントの駒の数（持ち主を問わない絶対値）。
    public func count(at index: Int) -> Int {
        points.indices.contains(index) ? abs(points[index]) : 0
    }

    public func bar(for side: BackgammonSide) -> Int { bar[side.rawValue] }
    public func off(for side: BackgammonSide) -> Int { off[side.rawValue] }

    /// 盤上（バー含む）に残っている駒の数。
    public func remaining(for side: BackgammonSide) -> Int {
        Self.checkersPerSide - off(for: side)
    }

    /// 各ポイントで自分の駒の数だけ正になる向きに読み替えた値。
    func signedCount(at index: Int, for side: BackgammonSide) -> Int {
        side == .white ? points[index] : -points[index]
    }

    /// 全駒がベアオフできる状態（バーが空で、盤上の駒がすべて自陣 6 ポイント内）か。
    public func canBearOff(_ side: BackgammonSide) -> Bool {
        guard bar(for: side) == 0 else { return false }
        for index in 0..<Self.pointCount where signedCount(at: index, for: side) > 0 {
            if side.normalized(index) > 5 { return false }
        }
        return true
    }

    /// ピップカウント（あがるまでに必要な目の合計）。バーの駒は 25 と数える。
    public func pipCount(_ side: BackgammonSide) -> Int {
        var total = bar(for: side) * 25
        for index in 0..<Self.pointCount {
            let n = signedCount(at: index, for: side)
            if n > 0 { total += n * (side.normalized(index) + 1) }
        }
        return total
    }

    /// 全駒があがったか。
    public func hasWon(_ side: BackgammonSide) -> Bool { off(for: side) == Self.checkersPerSide }

    /// 勝者が確定したときの決着の種類。
    public func winKind(winner: BackgammonSide) -> BackgammonWinKind {
        let loser = winner.opponent
        guard off(for: loser) == 0 else { return .single }
        if bar(for: loser) > 0 { return .backgammon }
        // 勝者の自陣（勝者から見た 1〜6 ポイント）に負けた側の駒が残っていればバックギャモン。
        for index in 0..<Self.pointCount where signedCount(at: index, for: loser) > 0 {
            if winner.normalized(index) <= 5 { return .backgammon }
        }
        return .gammon
    }
}
