import Foundation

/// 盤の路数。9路を既定にし、13路は後日の拡張に備えて型で持つ（#398。UI では 9 だけを出す）。
///
/// 盤の大きさを型で持つのはテストのためでもある。ルールの正誤は 5路・6路の小さな盤で書くほうが
/// 「どの石が取られるか」を目で追えるので、参照局面をそのまま `#expect` に写せる。
public enum GoBoardSize: Int, Codable, Sendable, CaseIterable {
    case nine = 9
    case thirteen = 13

    public var label: String { "\(rawValue)路" }
}

/// 石の色。
public enum GoStone: Int, Codable, Equatable, Sendable {
    case black = 0, white = 1

    public var opponent: GoStone { self == .black ? .white : .black }

    /// 表示・読み上げに使う名前。
    public var name: String { self == .black ? "黒" : "白" }
}

/// 盤上の交点。
public struct GoPoint: Hashable, Sendable, Codable {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}

/// 1 手。囲碁は「打つ」ほかに「パス」があり、パスが 2 回続くと終局する。
public enum GoMove: Equatable, Hashable, Sendable, Codable {
    case play(GoPoint)
    case pass

    public static func play(row: Int, col: Int) -> GoMove { .play(GoPoint(row: row, col: col)) }

    public var point: GoPoint? {
        if case .play(let p) = self { return p }
        return nil
    }
}

/// 着手が拒否された理由。判定は必ず Model / ルール層に集約する（#202 の規約。View で
/// 早期 return すると「タップしたのに何も起きない」状態がその分岐だけ残る）。
public enum GoIllegalMove: Equatable, Sendable {
    /// 盤の外。
    case outOfBoard
    /// すでに石がある。
    case occupied
    /// 自殺手（打った石の連が呼吸点を持たない）。
    case suicide
    /// コウ（直前に取られた 1 子をすぐ取り返す手）。
    case ko
    /// 位置的スーパーコウ（同一盤面の再現）。長生などの循環で無限対局にならないための禁止。
    case superko
    /// すでに終局している。
    case gameOver

    /// 拒否をユーザーに伝える 1 行。
    public var message: String {
        switch self {
        case .outOfBoard: return "盤の外には打てません"
        case .occupied:   return "すでに石があります"
        case .suicide:    return "自殺手です（打つと自分の石が取られます）"
        case .ko:         return "コウです（すぐには取り返せません）"
        case .superko:    return "同じ盤面のくり返しになるため打てません"
        case .gameOver:   return "対局は終わっています"
        }
    }
}

/// 盤面。石の配置だけを持ち、手番・コウ・履歴は `GoState` の側にある。
public struct GoBoard: Hashable, Sendable {
    public let size: Int
    public private(set) var cells: [GoStone?]

    public init(size: Int = GoBoardSize.nine.rawValue) {
        self.size = size
        self.cells = Array(repeating: nil, count: size * size)
    }

    public init(size: Int, cells: [GoStone?]) {
        precondition(cells.count == size * size, "cells の数が盤の大きさと合っていません")
        self.size = size
        self.cells = cells
    }

    public subscript(row: Int, col: Int) -> GoStone? {
        get { cells[row * size + col] }
        set { cells[row * size + col] = newValue }
    }

    public subscript(point: GoPoint) -> GoStone? {
        get { self[point.row, point.col] }
        set { self[point.row, point.col] = newValue }
    }

    public func contains(row: Int, col: Int) -> Bool {
        row >= 0 && row < size && col >= 0 && col < size
    }

    public func contains(_ point: GoPoint) -> Bool { contains(row: point.row, col: point.col) }

    public var pointCount: Int { size * size }

    /// 石が置かれている交点の数。
    public var stoneCount: Int { cells.reduce(into: 0) { if $1 != nil { $0 += 1 } } }

    /// 盤上のすべての交点（行優先）。
    public var allPoints: [GoPoint] {
        (0..<size).flatMap { row in (0..<size).map { GoPoint(row: row, col: $0) } }
    }

    /// 上下左右の隣接点だけを走査する。斜めは連（グループ）を作らない。
    @inline(__always)
    public func forEachNeighbor(of point: GoPoint, _ body: (GoPoint) -> Void) {
        if point.row > 0          { body(GoPoint(row: point.row - 1, col: point.col)) }
        if point.row < size - 1   { body(GoPoint(row: point.row + 1, col: point.col)) }
        if point.col > 0          { body(GoPoint(row: point.row, col: point.col - 1)) }
        if point.col < size - 1   { body(GoPoint(row: point.row, col: point.col + 1)) }
    }

    /// 斜め 4 点。眼（アイ）の真偽判定にだけ使う。
    @inline(__always)
    public func forEachDiagonal(of point: GoPoint, _ body: (GoPoint) -> Void) {
        for (dr, dc) in [(-1, -1), (-1, 1), (1, -1), (1, 1)] {
            let r = point.row + dr, c = point.col + dc
            if contains(row: r, col: c) { body(GoPoint(row: r, col: c)) }
        }
    }

    /// 盤の縁（辺・隅）にある点か。眼の判定で斜めの許容数を変えるのに使う。
    @inline(__always)
    public func isOnEdge(_ point: GoPoint) -> Bool {
        point.row == 0 || point.col == 0 || point.row == size - 1 || point.col == size - 1
    }
}

/// 対局の設定（路数・コミ・置き石・CPU の強さ）。
///
/// **コミは 6.5 目**（9路・中国ルールの慣例値 5.5〜7 の範囲・#398）。半目にすることで
/// 面積計算の結果が必ず勝ち負けに決まり、引き分けの表示を考えずに済む。
/// **置き石を置く対局のコミは 0.5 目**にする（ハンデの意味を残しつつ引き分けを避ける慣例）。
public struct GoRuleset: Equatable, Sendable, Codable {
    public static let defaultKomi: Double = 6.5
    public static let handicapKomi: Double = 0.5
    /// 置き石として選べる数（0 = 互先）。
    public static let handicapChoices = [0, 2, 3, 4, 5]

    public var size: Int
    public var handicap: Int
    public var komi: Double

    public init(size: Int = GoBoardSize.nine.rawValue, handicap: Int = 0) {
        self.size = size
        self.handicap = handicap
        self.komi = handicap > 0 ? Self.handicapKomi : Self.defaultKomi
    }

    /// 中国ルールの置き石補正。置き石 1 子につき白へ 1 目を返す。
    ///
    /// 面積計算では黒が置き石のぶんだけ多く石を置けるため、補正を入れないとハンデが二重に効く。
    public var handicapCompensation: Int { handicap }

    /// 9路の置き石を打つ位置（星 4 つ + 天元）。日本・中国とも同じ配置を使う。
    ///
    /// 2 子 = 右上・左下、3 子 = + 右下、4 子 = + 左上、5 子 = + 天元。
    public func handicapPoints() -> [GoPoint] {
        guard handicap >= 2 else { return [] }
        let star = size == 9 ? 2 : 3
        let far = size - 1 - star
        let center = size / 2
        let order = [
            GoPoint(row: star, col: far),      // 右上
            GoPoint(row: far, col: star),      // 左下
            GoPoint(row: far, col: far),       // 右下
            GoPoint(row: star, col: star),     // 左上
            GoPoint(row: center, col: center), // 天元
        ]
        return Array(order.prefix(handicap))
    }
}

/// CPU の強さ。3 段階（#398 の受け入れ条件）。
public enum GoLevel: Int, Codable, Equatable, Sendable, CaseIterable {
    case easy = 0, normal = 1, hard = 2

    public var label: String {
        switch self {
        case .easy:   return "弱"
        case .normal: return "普通"
        case .hard:   return "強"
        }
    }

    /// 1 手あたりのプレイアウト数。体感差が出るよう桁で分ける。
    public var playouts: Int {
        switch self {
        case .easy:   return 400
        case .normal: return 2_500
        case .hard:   return 9_000
        }
    }

    /// 1 手にかけてよい実時間の上限（秒）。
    ///
    /// 遅い端末でも「1 手 1 秒以内」（#398）に収めるための歯止め。**段階ごとに別の値**にするのが
    /// 要点で、共通の上限にすると遅い端末で普通と強がどちらも上限に張り付いて同じ強さになる。
    public var timeLimit: TimeInterval {
        switch self {
        case .easy:   return 0.4
        case .normal: return 0.8
        case .hard:   return 0.9
        }
    }

    public var detail: String {
        switch self {
        case .easy:   return "軽く読む"
        case .normal: return "そこそこ読む"
        case .hard:   return "しっかり読む"
        }
    }
}
