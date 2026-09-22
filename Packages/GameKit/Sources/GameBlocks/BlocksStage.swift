import Foundation

/// 1 ステージぶんのブロック配置と球の速さ（#463）。
///
/// レイアウトは 1 行 = `BlocksField.Metrics.columns` 文字の文字列で、
/// `n` = 通常 / `h` = 硬い（2 回）/ `s` = 壊れない / `w` = 金庫の壁（#1250）/ `.` = 空き。上の行が画面の上。
public struct BlocksStage: Equatable, Sendable {
    /// 1 始まりのステージ番号。
    public let number: Int
    /// 上の行から順に並べたレイアウト。
    public let rows: [String]
    /// このステージでの球の速さ（フィールド単位 / 秒）。
    public let ballSpeed: Double
    /// フレンジー増殖（#1202）の発動に必要な連続ブロック破壊数。nil ならこのステージでは発動しない。
    ///
    /// テストで直接 `BlocksStage` を組み立てる箇所が多いため既定値 nil にしてあり、
    /// 明示しない限りフレンジーは発動しない（既存のブロック単体テストの事象を変えないため）。
    public let frenzyThreshold: Int?

    public init(number: Int, rows: [String], ballSpeed: Double, frenzyThreshold: Int? = nil) {
        self.number = number
        self.rows = rows
        self.ballSpeed = ballSpeed
        self.frenzyThreshold = frenzyThreshold
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
    /// 球の速さの下限（ステージ 1）。
    ///
    /// **盤の高さに合わせて決める**。#597 で盤を 150 → 100 に縮めたため、ブロックの最下段から
    /// 発射位置（y = 13.3）までの可動域が縮んだ（3 段のステージで 107.7 → 65.7、
    /// 7 段のステージで 87.7 → 45.7 単位）。速さを据え置くと**落球までの猶予だけが静かに縮み**、
    /// 盤を広げただけのはずが難度が上がる。
    ///
    /// 合わせる相手は「速さ」ではなく**ステージごとの猶予（可動域 ÷ そのステージの速さ）**。
    /// 可動域の縮み方は段数によって違う（3 段で 0.61 倍・7 段で 0.52 倍）ため、同じ比で
    /// 速さを割るだけでは終盤ほど猶予が足りなくなる（実測: `speedStep` を 2.6 にすると
    /// 12 面の猶予が 0.769 → 0.621 秒に落ちた）。1 面と 12 面の猶予が両端で揃う直線を引くと
    /// この値になり、全 12 面の猶予が変更前の **0.97 〜 1.08 倍**に収まる
    /// （`BlocksLayoutTests.fallingGraceMatchesTheOldBoard` が全面で固定している）。
    ///
    /// **2026-09-21（#1202）に 43 → 54 へ引き上げた**（会長判断: 序盤の「もっさりした」体感の
    /// 主因は球の遅さと分析）。`speedStep` も同じ比率で引き上げてカーブの形（最終面は初速の
    /// 約 1.4 倍）を保っているため、全ステージの猶予は**一律で約 0.77〜0.86 倍**に縮む
    /// （段数による猶予の縮み方の違い自体は変えていない。`fallingGraceMatchesTheOldBoard` の
    /// 許容比を新しい値に合わせて更新している）。
    static let baseSpeed: Double = 54
    /// 1 ステージ進むごとに増える速さ。最終ステージ（12）で 74.9 = 初速の約 1.4 倍になる。
    ///
    /// 変更前（1.5）と同じ比率で引き上げてあり、**猶予の縮み方の相対カーブは変更前と同じ**
    /// （#1202・上の `baseSpeed` のコメント参照）。
    static let speedStep: Double = 1.9

    /// 全ステージ（12 面）。Issue の受け入れ条件は「最低10ステージ」。
    ///
    /// 設計の意図:
    /// - 前半（1〜4）は通常ブロックだけで操作に慣れさせ、`hard` は 4 面目から出す
    /// - `solid`（壊れない）は 5 面目から。**必ず縦にも横にも隙間を空けて置く**。壁のように
    ///   並べると、その裏の通常ブロックへ球が届かずステージが詰む
    /// - **金庫（`w`・#1250）は 4 面目から**。1〜3 面は変えない。後半ほど箱を大きく・数を増やす。
    ///   入り口は下段の 1 マスだけ空け、壁の外接矩形の最下段に必ず切れ目を作る
    ///   （`VaultTests.everyVaultHasContentsAndAnEntrance` が全面で検査する）
    /// - 最終面（12）は全種を使うが、最上段と最下段のあいだに通常ブロックの層を挟んで
    ///   突破口を残す
    ///
    /// 顔ぶれの検証（壊せるブロックが 1 つ以上ある・列数が揃っている・詰みが無い）は
    /// `BlocksStageTests` が全面に対して機械的に行う。
    static let all: [BlocksStage] = layouts.enumerated().map { index, rows in
        BlocksStage(
            number: index + 1,
            rows: rows,
            ballSpeed: baseSpeed + Double(index) * speedStep,
            frenzyThreshold: frenzyThreshold(forStageIndex: index)
        )
    }

    /// ステージ番号（1 始まり）から。範囲外は nil。
    static func stage(number: Int) -> BlocksStage? {
        guard number >= 1, number <= all.count else { return nil }
        return all[number - 1]
    }

    /// フレンジー増殖（#1202）のしきい値。前半ほど小さく（発動しやすく）、後半ほど大きく
    /// （発動しにくく）することで「前半は爽快・後半は難度を追求する」を作る。
    ///
    /// 最終面（12）は nil にして増殖なしのまま難度を保つ（会長の新方針でも「後半で絞る」の
    /// 一形態として、いちばん厳しい面は増殖に頼らせない）。
    private static func frenzyThreshold(forStageIndex index: Int) -> Int? {
        switch index + 1 {
        case 1...4: return 3
        case 5...8: return 5
        case 9...11: return 8
        default: return nil
        }
    }

    /// レイアウトの実体。1 行 9 文字。
    private static let layouts: [[String]] = [
        // 1. まっすぐ 2 段。操作を覚えるだけの面。
        //
        // **3 段（27 個）から 2 段（18 個）へ減らした**（#1055）。1 面は球が最も遅い
        // （`baseSpeed`。猶予 1.53 秒で、12 面 0.77 秒の約 2 倍）のに、ブロックは 2 面(23)・
        // 3 面(25)・6 面(20) より多い 27 個で、**最初の 1 面だけが極端に長かった**。
        // GA4 実測（2026-09-15〜16）でも 19 人が触って 21 回 ＝ ほぼ全員が 1 回でやめており、
        // 会長 QA「ステージ1だとたまが遅くて終わるまで時間がかかるのでだるい」と一致する。
        // **2026-09-21（#1202）に球速そのものも上げた**（`baseSpeed` のコメント参照）。
        // 猶予カーブ（`BlocksLayoutTests.fallingGraceMatchesTheOldBoard`）は許容比を
        // 新しい値に合わせて更新済みで、崩れてはいない。
        [
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
        //    金庫（#1250）の初出。中身は硬いブロック 3 個で、入り口は下の 1 マス。
        [
            "hhhhhhhhh",
            "nnwwwwwnn",
            "nnwhhhwnn",
            "n.ww.wwn.",
        ],
        // 5. 壊れないブロックの初出。柱は 2 本だけで、左右にも下にも通り道がある。
        [
            "n.s.n.s.n",
            "nwwwwwnnn",
            "nwnnnwnnn",
            "nww.wwnnn",
        ],
        // 6. ダイヤ。中央に硬いブロックを 1 つ置いて最後の 1 個を粘らせる。
        [
            "....h....",
            "...nnn...",
            "..n.n.n..",
            ".wwwwwww.",
            ".wnnnnnw.",
            ".www.www.",
        ],
        // 7. 両袖が硬い壁。中央に通常ブロックの通路を開けてある。
        [
            "hh.nnn.hh",
            "nwwwwwwwn",
            "nwnhnhnwn",
            "nwww.wwwn",
        ],
        // 8. 硬いブロックの市松。総打数がはっきり増える。
        [
            "hnhnhnhnh",
            "wwww.wwww",
            "whhwnwhhw",
            "w.wwnww.w",
        ],
        // 9. 砦。壊れないブロックは最上段に散らすだけで、下の層は素通しにする。
        [
            "s..s.s..s",
            "nnnnnnnnn",
            "nwwwwwwwn",
            "nwhnnnhwn",
            ".www.www.",
        ],
        // 10. 硬い両肩 + 隙間の多い胴。速度が上がってくるので当て損ないを許す形にする。
        [
            "hhhnnnhhh",
            "nnnnnnnnn",
            "wwwn.nwww",
            "whwnnnwhw",
            "whw.n.whw",
            "w.wnnnw.w",
        ],
        // 11. 硬い層で上下を挟み、中央に壊れない柱を左右 1 本ずつ置く。
        [
            "hnhnhnhnh",
            "nnnnnnnnn",
            "swwwwwwws",
            "nwnhnhnwn",
            "nwhnnnhwn",
            "nwww.wwwn",
        ],
        // 12. 最終面。全種を使うが、硬い層のあいだに必ず通常ブロックの層を挟む。
        [
            "hhhhhhhhh",
            "nsnsnsnsn",
            "nnnnnnnnn",
            "nwwwwwwwn",
            "nwhnhnhwn",
            "nwnhnhnwn",
            "nwww.wwwn",
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
    /// このフレームは「計時の穴」とみなす、という `dt` の下限（秒）。
    ///
    /// 一時停止・オーバーレイ中は描画ループごと止める（#522）一方で時計は進み続けるため、
    /// 再開の 1 フレーム目には止めていた時間がまるごと `dt` として渡る。上の `maxStep` で
    /// 刻んでも**そのフレームだけ 3 倍速で進む**ことに変わりはないので、この値を超えた
    /// フレームは進めずに時計だけ合わせ直す。60fps の 15 フレームぶんにあたり、
    /// 通常のフレーム落ちで届く値ではない。
    public static let staleFrameThreshold: Double = 0.25
    /// 総ステージ数。
    public static var stageCount: Int { BlocksStage.all.count }

    // MARK: - パワーアップ（#599）

    /// アイテムが落ちてくる間隔（**そのステージで壊したブロックの個数**）。
    ///
    /// 乱数は使わない（基盤規約）。ステージ 1（27 個）で 3 個、最終面（47 個）で 6 個ぶん落ちる。
    /// **間隔を詰めるほど「常に効果が乗っている」状態に近づき、素の難度が消える**ため、
    /// 効果時間（`widePaddleDuration`）より長い間隔になるよう選んである
    /// （実測: 1 面の平均で 7 個壊すのに 12 秒より長くかかる）。
    public static let itemDropInterval = 7
    /// アイテムが落ちる速さ（フィールド単位 / 秒）。
    ///
    /// 球の最低速度（`BlocksStage.baseSpeed` = 54）より十分遅くして、球を追いながらでも
    /// 取りに行けるようにする。
    public static let itemFallSpeed: Double = 24
    /// バー伸長でパドルの幅に掛ける倍率。
    public static let widePaddleFactor: Double = 1.6
    /// バー伸長の効果時間（秒）。**重ねがけしても幅は変わらず、この残り時間だけが延びる**。
    public static let widePaddleDuration: Double = 12
    /// 同時に盤上にいられる球の数の上限。
    ///
    /// 上限が無いと取るたびに倍々に増え、パドルを動かさなくても勝ててしまう。
    public static let maxBalls = 3
    /// 球を増やすときに元の球から振り分ける角度（ラジアン）。
    ///
    /// 同じ向きのまま増やすと 3 個が重なったまま飛び、増えた意味が無くなる。
    public static let multiBallSpread: Double = .pi / 9

    // MARK: - フレンジー増殖（#1202）

    /// ブロックを連続で壊すこと自体をトリガーに、盤上の球数がここまで一気に増える。
    ///
    /// 会長決裁（2026-09-21）で「既存の `multiBall`（アイテム取得トリガー・上限 `maxBalls`=3）とは
    /// 規模もトリガーも別物」と明確化された「数十個規模」の下限として 30 を選んだ。
    /// 上限が無いと際限なく増え続けて操作もパフォーマンスも破綻するため必ず絶対上限を持つ。
    public static let frenzyMaxBalls = 30
    /// フレンジー増殖で球を振り分ける全体の角度（ラジアン）。この範囲に扇状に均等分散させる。
    ///
    /// `multiBallSpread`（2 分岐・狭い角度）より大きく取り、画面を広く埋める「爆発的」な
    /// 見た目にする。`BlocksPhysics.clampVertical` が真横に近い角度は押し戻すため、
    /// 90° まで広げても詰み（真横に張り付く球）は生まれない。
    public static let frenzySpreadAngle: Double = .pi / 2
}
