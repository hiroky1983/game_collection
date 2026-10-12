import Foundation
import CoreEngine

/// おじさんの荷物運びパズルの遊び方（#1920）。始める前の設定シートで選び、1 局のあいだは変えない
/// （1 局 = 1 ルールセット。局中に読み替えない）。
///
/// - `backpain`（表示名は「荷運びモード」・会長指示 2026-10-12。enum ケース名・保存キー・解析の
///   `mode` 値は旧名の `backpain` のまま変えない＝記録・解析を引き継ぐ）: 腰痛ゲージあり。最初から
///   荷物が積まれていて、時間で下からせり上がってくる。決めたラインより荷物を下げればクリア。記録はクリアタイム。
/// - `puzzle`（パズルモード）: ゲージなし。荷物を消した得点を競う、埋まるまで続くモード。記録は得点。
///
/// 画面・おじさんはどちらも同じで、違いはゲージの有無とルールだけ。各数値は会長確認前の案（#1920）。
/// **「ぷよぷよ」「とことん」は公開文言・画面に使わない**（商標）。
public enum OjisanPuzzleMode: String, CaseIterable, Identifiable, Sendable {
    case backpain
    case puzzle

    public var id: String { rawValue }

    /// 画面に出す表示名。`backpain` は「荷運びモード」（会長指示 2026-10-12。ゲージ自体の名前「腰痛ゲージ」は変えない）。
    public var title: String {
        switch self {
        case .backpain: "荷運びモード"
        case .puzzle: "パズルモード"
        }
    }

    /// 開始シートのカードで、モード名の横に出す小さなアイコン（会長指示 2026-10-12）。
    public var setupIcon: String {
        switch self {
        case .backpain: "cross.case.fill"
        case .puzzle: "star.fill"
        }
    }

    /// 腰痛ゲージ（と、それに連動する操作の重さ・おじさんの姿勢）が働くか。
    public var hasGauge: Bool { self == .backpain }

    /// 荷物が時間でせり上がり、ラインまで下げればクリアになる遊び方か。
    public var isCleanup: Bool { self == .backpain }

    /// 解析イベント `game_start` / `game_end` の `mode`。
    public var analyticsMode: AnalyticsMode {
        switch self {
        case .backpain: .backpain
        case .puzzle: .puzzle
        }
    }

    /// 自己ベストの保存先の区分（`PlayLog` の `ojisanpuzzle#<区分>`）。表示名を変えても区分キーは rawValue のまま。
    /// 荷運びモード（`backpain`）はタイム、パズルモードは得点。
    public var recordVariant: String { rawValue }

    public var recordVariantLabel: String { title }
}

/// 荷運びモード（片付け型。旧名・腰痛モード）のルールの数値と、盤の作り方。純粋関数だけで、乱数は呼び出し側が持つ。
public enum OjisanPuzzleCleanup {
    /// クリアのライン。この行より上（行番号が小さい側）に荷物が 1 つも無くなればクリア。
    /// 12 段のうち下 4 段（行 8...11）に収まれば片付いた扱い。
    public static let clearLineRow = 8
    /// 荷物が 1 段せり上がる間隔（ミリ秒）。会長確認前の案。
    public static let riseIntervalMilliseconds = 40_000
    /// 開始時の各列の積み高さ（段数）の幅。
    public static let initialHeights = 5...7

    /// 一番上の荷物がある行。荷物が 1 つも無ければ nil。
    public static func topLuggageRow(_ board: [[Int]]) -> Int? {
        board.firstIndex { $0.contains { $0 != 0 } }
    }

    /// ライン以下に片付いたか（荷物が 1 つも無い盤も片付いた扱い）。
    public static func isCleared(_ board: [[Int]], line: Int = clearLineRow) -> Bool {
        guard let top = topLuggageRow(board) else { return true }
        return top >= line
    }

    /// 開始時の盤。荷物をランダムに積む。**最初から 4 つつながっている塊は作らない**
    /// （始まった瞬間に勝手に消えない・クリア済みで始まらない）。
    public static func initialBoard(using rng: inout OjisanPuzzleRandom) -> [[Int]] {
        var board = OjisanPuzzleBoard.emptyBoard()
        for col in 0..<OjisanPuzzleBoard.columns {
            let height = Int.random(in: initialHeights, using: &rng)
            for step in 0..<height {
                let row = OjisanPuzzleBoard.rows - 1 - step
                board[row][col] = kindAvoidingClear(in: board, row: row, col: col, using: &rng)
            }
        }
        // 全列が低くて最初からクリアになる並びは作り直さず、1 列だけ積み増す。
        if isCleared(board) {
            let col = Int.random(in: 0..<OjisanPuzzleBoard.columns, using: &rng)
            let row = clearLineRow - 1
            board[row][col] = kindAvoidingClear(in: board, row: row, col: col, using: &rng)
        }
        return board
    }

    /// 下から 1 段せり上げる。戻り値の `overflowed` は、せり上げで一番上の行から荷物が押し出された（= 埋まった）こと。
    /// 新しい最下段は荷物で埋め、4 つつながる塊は作らない。
    public static func rising(
        _ board: [[Int]], using rng: inout OjisanPuzzleRandom
    ) -> (board: [[Int]], overflowed: Bool) {
        let overflowed = board[0].contains { $0 != 0 }
        var result = Array(board.dropFirst())
        result.append(Array(repeating: 0, count: OjisanPuzzleBoard.columns))
        let bottom = OjisanPuzzleBoard.rows - 1
        for col in 0..<OjisanPuzzleBoard.columns {
            result[bottom][col] = kindAvoidingClear(in: result, row: bottom, col: col, using: &rng)
        }
        return (result, overflowed)
    }

    /// そのマスに置いても 4 つつながらない荷物の種類を、乱数で 1 つ選ぶ。
    /// 5 種類あり、隣り合うマスは最大 3 つなので、必ず 1 種類は残る。
    private static func kindAvoidingClear(
        in board: [[Int]], row: Int, col: Int, using rng: inout OjisanPuzzleRandom
    ) -> Int {
        var board = board
        var kinds = Array(1...OjisanPuzzleBoard.kindCount)
        while !kinds.isEmpty {
            let index = Int.random(in: 0..<kinds.count, using: &rng)
            let kind = kinds.remove(at: index)
            board[row][col] = kind
            if OjisanPuzzleBoard.connectedGroup(board, row: row, col: col).count < OjisanPuzzleBoard.clearThreshold {
                return kind
            }
        }
        return 1
    }
}

/// パズルモード（得点を競う型）で、局が進むほど落下が速くなる倍率。会長確認前の案。
public enum OjisanPuzzleSpeedUp {
    /// 何組固定するごとに 1 段階速くなるか。
    public static let locksPerLevel = 10
    /// 1 段階ごとに縮める落下間隔の割合。
    public static let stepFactor = 0.05
    /// これ以上は速くしない（刻みの倍率の下限）。
    public static let minimumFactor = 0.55

    /// 固定した組数から落下間隔の倍率を引く（1.0 = 元の速さ、小さいほど速い）。
    public static func factor(locks: Int) -> Double {
        max(minimumFactor, 1.0 - stepFactor * Double(max(0, locks) / locksPerLevel))
    }
}
