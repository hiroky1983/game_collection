import Foundation

/// 1 ステージぶんのブロック配置と球の速さ（#463）。
///
/// レイアウトは 1 行 = `BlocksField.Metrics.columns` 文字の文字列で、
/// `n` = 通常 / `h` = 硬い（2 回）/ `s` = 壊れない / `.` = 空き。上の行が画面の上。
public struct BlocksStage: Equatable, Sendable {
    /// 1 始まりのステージ番号。
    public let number: Int
    /// 上の行から順に並べたレイアウト。
    public let rows: [String]
    /// このステージでの球の速さ（フィールド単位 / 秒）。
    public let ballSpeed: Double

    public init(number: Int, rows: [String], ballSpeed: Double) {
        self.number = number
        self.rows = rows
        self.ballSpeed = ballSpeed
    }

    /// レイアウトを `Block?` の二次元配列に展開する。
    public func makeBlocks() -> [[Block?]] {
        rows.map { row in
            let characters = Array(row)
            return (0..<BlocksField.Metrics.columns).map { column in
                guard column < characters.count,
                      let kind = BlockKind.from(symbol: characters[column]) else { return nil }
                return Block(kind: kind)
            }
        }
    }
}

public extension BlocksStage {
    /// 球の速さの下限（ステージ 1）。フィールドの高さは 150 なので、往復におよそ 2 秒かかる。
    static let baseSpeed: Double = 70
    /// 1 ステージ進むごとに増える速さ。最終ステージ（12）で 114 = 初速の約 1.6 倍になる。
    static let speedStep: Double = 4

    /// 全ステージ（12 面）。Issue の受け入れ条件は「最低10ステージ」。
    ///
    /// 設計の意図:
    /// - 前半（1〜4）は通常ブロックだけで操作に慣れさせ、`hard` は 4 面目から出す
    /// - `solid`（壊れない）は 5 面目から。**必ず縦にも横にも隙間を空けて置く**。壁のように
    ///   並べると、その裏の通常ブロックへ球が届かずステージが詰む
    /// - 最終面（12）は全種を使うが、最上段と最下段のあいだに通常ブロックの層を挟んで
    ///   突破口を残す
    ///
    /// 顔ぶれの検証（壊せるブロックが 1 つ以上ある・列数が揃っている・詰みが無い）は
    /// `BlocksStageTests` が全面に対して機械的に行う。
    static let all: [BlocksStage] = layouts.enumerated().map { index, rows in
        BlocksStage(
            number: index + 1,
            rows: rows,
            ballSpeed: baseSpeed + Double(index) * speedStep
        )
    }

    /// ステージ番号（1 始まり）から。範囲外は nil。
    static func stage(number: Int) -> BlocksStage? {
        guard number >= 1, number <= all.count else { return nil }
        return all[number - 1]
    }

    /// レイアウトの実体。1 行 9 文字。
    private static let layouts: [[String]] = [
        // 1. まっすぐ 3 段。操作を覚えるだけの面。
        [
            "nnnnnnnnn",
            "nnnnnnnnn",
            "nnnnnnnnn",
        ],
        // 2. 市松。狙って当てる感覚を出す。
        [
            "n.n.n.n.n",
            ".n.n.n.n.",
            "n.n.n.n.n",
            "nnnnnnnnn",
        ],
        // 3. ピラミッド。端の角度が効き始める。
        [
            "....n....",
            "...nnn...",
            "..nnnnn..",
            ".nnnnnnn.",
            "nnnnnnnnn",
        ],
        // 4. 硬いブロックの初出。最上段だけなので 2 回当てれば必ず抜ける。
        [
            "hhhhhhhhh",
            "nnnnnnnnn",
            "nnnnnnnnn",
            "n.n.n.n.n",
        ],
        // 5. 壊れないブロックの初出。柱は 2 本だけで、左右にも下にも通り道がある。
        [
            "n.s.n.s.n",
            "nnnnnnnnn",
            "n.n.n.n.n",
            "nnnnnnnnn",
        ],
        // 6. ダイヤ。中央に硬いブロックを 1 つ置いて最後の 1 個を粘らせる。
        [
            "....h....",
            "...nnn...",
            "..n.n.n..",
            ".nnnnnnn.",
            "..n.n.n..",
            "...nnn...",
        ],
        // 7. 両袖が硬い壁。中央に通常ブロックの通路を開けてある。
        [
            "hh.nnn.hh",
            "nnnnnnnnn",
            ".n.nhn.n.",
            "nnnnnnnnn",
        ],
        // 8. 硬いブロックの市松。総打数がはっきり増える。
        [
            "hnhnhnhnh",
            "nhnhnhnhn",
            "hnhnhnhnh",
            "nnnnnnnnn",
        ],
        // 9. 砦。壊れないブロックは最上段に散らすだけで、下の層は素通しにする。
        [
            "s..s.s..s",
            "nnnnnnnnn",
            "nnh.h.hnn",
            "nnnnnnnnn",
            "..nnnnn..",
        ],
        // 10. 硬い両肩 + 隙間の多い胴。速度が上がってくるので当て損ないを許す形にする。
        [
            "hhhnnnhhh",
            "n.n.n.n.n",
            "nnnnnnnnn",
            ".nn.n.nn.",
            "nnnnnnnnn",
            "n.n.n.n.n",
        ],
        // 11. 硬い層で上下を挟み、中央に壊れない柱を左右 1 本ずつ置く。
        [
            "hnhnhnhnh",
            "nnnnnnnnn",
            "s.n.n.n.s",
            "nnnnnnnnn",
            "hnhnhnhnh",
            "nnnnnnnnn",
        ],
        // 12. 最終面。全種を使うが、硬い層のあいだに必ず通常ブロックの層を挟む。
        [
            "hhhhhhhhh",
            "nsnsnsnsn",
            "nnnnnnnnn",
            "hnhnhnhnh",
            "nnnnnnnnn",
            "nsnsnsnsn",
            "hhhhhhhhh",
        ],
    ]
}

/// ステージ進行・残機・得点の定数（#463）。
///
/// 数字を Model の中に散らさず 1 か所に集める。次のアクション系（スネーク等）も
/// 同じ形で自分の `Rules` を持つ、というのが基盤規約の意図。
public enum BlocksRules {
    /// 開始時の残機。
    public static let initialLives = 3
    /// コンティニュー（リワード広告）で戻る残機。Issue の「残機 +1」。
    public static let continueLives = 1
    /// ゆっくりモードで球の速さに掛ける倍率（アクセシビリティ）。
    public static let slowFactor: Double = 0.68
    /// 1 回の `tick` で進める時間の上限（秒）。
    ///
    /// バックグラウンドから戻った直後などに巨大な `dt` が来ると、1 フレームで球が
    /// 盤の端から端まで飛んで当たり判定が意味を失う。上限を掛けると**進みが遅くなるだけ**で、
    /// すり抜けは起きない。
    public static let maxStep: Double = 1.0 / 20
    /// 総ステージ数。
    public static var stageCount: Int { BlocksStage.all.count }
}
