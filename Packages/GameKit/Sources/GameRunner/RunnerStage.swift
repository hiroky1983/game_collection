import Foundation

/// ジャンプ・進行・ステージ構成の定数（#494）。
///
/// 数字を Model の中に散らさず 1 か所へ集める（ブロック崩しの `BlocksRules` と同じ形）。
public enum RunnerRules {
    // MARK: 地形の単位

    /// レイアウト文字 1 つぶんの長さ（ワールド単位）。
    public static let tileWidth: Double = 4
    /// 1 区画（セグメント）のタイル数。**障害はこの中央付近に 1 つだけ置く**。
    ///
    /// 区画の長さがそのまま「隣り合う障害の間隔」になる。間隔が短いと、前の障害を跳んで
    /// 着地する前に次の障害へ突っ込む形になり、どう操作しても越えられないステージができる。
    /// 成立条件（間隔・跳べる幅・越えられる高さ）は `RunnerStageTests` が全ステージで確かめる。
    public static let segmentTiles = 16
    /// 区画の中で障害を置き始めるタイル位置。
    public static let hazardTileOffset = 6

    // MARK: ジャンプ

    /// 重力（ワールド単位 / 秒²）。
    public static let gravity: Double = 200
    /// 踏み切りの初速。二段目も同じ初速を使う（`RunnerField.jump()`）。
    public static let jumpVelocity: Double = 75
    /// 接地してから使える踏み切りの回数（会長決裁 2026-09-10・2段ジャンプ）。
    ///
    /// **既存 15 ステージの成立条件（`RunnerStageTests`）は一段目の単発ジャンプだけで
    /// 満たせるままにしてある**——二段目は「あってもクリア可能」を崩さない上振れの
    /// 救済として足す。自動操縦（`RunnerAutoPilot`）も接地中しか踏み切らないので、
    /// この定数を増やしてもテストの前提には影響しない。
    public static let maxJumps: Int = 2
    /// 押している間だけ弱まる重力（大ジャンプ）。
    ///
    /// **弱めるのは上昇中の最大 `maxHoldTime` 秒だけ**。押しっぱなしで浮き続けられると
    /// 地形を読む必要が無くなり、ステージ設計が意味を失う。
    public static let holdGravity: Double = 110
    /// 大ジャンプで重力を弱められる上限時間（秒）。
    public static let maxHoldTime: Double = 0.25

    /// 押さずに離した場合（= 最小の）ジャンプの滞空時間。
    ///
    /// **ステージの成立条件はこちらで判定する**。大ジャンプは余裕を増やすだけの上振れで、
    /// 「押さないと越えられない地形」を作らないための下限として使う。
    public static var jumpAirTime: Double { 2 * jumpVelocity / gravity }
    /// 同じく、押さない場合のジャンプの頂点の高さ。
    public static var jumpApex: Double { jumpVelocity * jumpVelocity / (2 * gravity) }

    /// 足が高さ `height` 以上にある時間（押さないジャンプ）。0 なら届かない。
    ///
    /// `y(t) = v0·t - g·t²/2` を `height` で解いた 2 解の差。障害物を越えられるかは
    /// 「この時間のあいだに、当たり判定が重なる区間を通り抜けられるか」で決まる。
    public static func airTime(above height: Double) -> Double {
        let discriminant = jumpVelocity * jumpVelocity - 2 * gravity * height
        guard discriminant > 0 else { return 0 }
        return discriminant.squareRoot() / gravity * 2
    }

    /// 踏み切ってから足が高さ `height` に届くまでの時間（押さないジャンプ）。
    /// 届かない高さなら `.infinity`。
    public static func riseTime(to height: Double) -> Double {
        guard height > 0 else { return 0 }
        let discriminant = jumpVelocity * jumpVelocity - 2 * gravity * height
        guard discriminant >= 0 else { return .infinity }
        return (jumpVelocity - discriminant.squareRoot()) / gravity
    }

    // MARK: 進行

    /// ステージ 1 の走る速さ（ワールド単位 / 秒）。
    ///
    /// **これは下限**であって実際の速さではない。走る速さは操作で `maxSpeedFactor` 倍まで
    /// 上がる（下記「走る速さ」）。ステージの成立条件（跳べる幅・間隔）はこの下限で
    /// 判定するので、加速がどう転んでも詰みは生まれない。
    public static let baseSpeed: Double = 34
    /// 1 ステージ進むごとに増える速さ。
    public static let speedStep: Double = 1.2

    // MARK: ペダル（走る速さ・#569 A案・2026-09-10 会長決裁）

    /// **ペダルは地面でしか漕げない**。接地して走り続けるほど速くなり、跳んでいるあいだは
    /// 漕げずに乗りが落ちる。タイムが操作を反映するのはこの一点で、
    /// 「越えられる高さだけの低い弾道で跳ぶ = 地面にいる時間が長い = 速い」がそのまま記録になる。
    ///
    /// **空中の横速度は乗りに関わらず必ず `speed`（基準）** にしてある（`RunnerField.currentSpeed`）。
    /// ここを乗せてしまうと、跳んで進む距離が伸びて前の障害を跳んだ勢いのまま次へ突っ込む形になり、
    /// ステージの成立条件（`RunnerStageTests` の間隔・跳び越し）が全部やり直しになる。
    /// 空中を基準速度に固定してあるおかげで、**乗りをいくら上げても地形の成立条件は変わらない**。

    /// ペダルの乗りの上限（基準の速さに対する倍率）。
    public static let maxPedalBoost: Double = 1.45
    /// 接地して漕いでいるあいだに乗りが上がる速さ（毎秒）。
    ///
    /// 下限から上限（幅 0.45）まで漕ぎ切るのに約 0.75 秒。障害が詰まった後半のステージでは
    /// 跳ぶたびに巻き戻されるので、上限まで乗るのは平地が続く区間だけになる。
    public static let pedalGain: Double = 0.60
    /// 空中にいるあいだに乗りが落ちる速さ（毎秒）。
    ///
    /// 最小のジャンプ（滞空 `jumpAirTime` = 0.75 秒）で 0.26 落ちる = 幅 0.45 の半分強を失い、
    /// 取り戻すのに 0.44 秒の地面が要る。押し続けて高く跳べば滞空が伸び、そのぶん多く落ちる。
    public static let pedalLoss: Double = 0.35
    /// ステージ 1 の区画数。ここから 1 ステージごとに 1 区画ずつ長くなる。
    public static let baseSegments = 12

    /// ゆっくりモードで**時間の進み**に掛ける倍率（アクセシビリティ）。
    ///
    /// **速さではなく時間を遅くする**のが要点。走る速さだけを落とすと、ジャンプの飛距離
    /// （速さ × 滞空時間）だけが縮んで穴を跳び越せなくなり、易しくするつもりの設定が
    /// 「クリア不能になる設定」に変わる。時間を一様に遅くすれば軌道は相似のまま、
    /// 操作に使える実時間だけが伸びる。
    public static let slowFactor: Double = 0.68

    /// 1 回の `tick` で進める時間の上限（秒）。
    ///
    /// バックグラウンドから戻った直後などに巨大な `dt` が来ると、1 フレームで穴を飛び越えて
    /// 当たり判定が意味を失う。上限を掛けると**進みが遅くなるだけ**で、すり抜けは起きない。
    public static let maxStep: Double = 1.0 / 20

    /// 総ステージ数。
    public static var stageCount: Int { RunnerStage.all.count }
}

/// 1 ステージぶんのコースと速さ（#494）。
///
/// コースは**区画記号の文字列**で書く。1 文字 = 1 区画（`RunnerRules.segmentTiles` タイル）で、
/// 区画の中央に障害を 1 つだけ置く。タイルを直に並べると 1 ステージが数百文字になり、
/// 打ち間違いが静かに「詰むステージ」になるため、間隔を構造で保証する形にしてある。
///
/// | 記号 | 区画の中身 |
/// |---|---|
/// | `-` | 平地 |
/// | `1` `2` `3` | 穴（1〜3 タイル） |
/// | `n` | 低い障害物 |
/// | `t` | 高い障害物 |
public struct RunnerStage: Equatable, Sendable {
    /// 1 始まりのステージ番号。
    public let number: Int
    /// 区画記号の並び。
    public let pattern: String
    /// 走る速さ（ワールド単位 / 秒）。
    public let speed: Double
    /// コースの全長。
    public let length: Double
    /// 左から順に並んだ障害。
    public let hazards: [RunnerHazard]
    /// チェックポイント（コースの中ほど）の x。
    ///
    /// **必ず平地に置く**。障害の上に置くと、再開した瞬間にまたミスになって進めない。
    /// 中点から右へずらしながら、障害と重ならず着地に必要な余白もある位置を探す。
    /// 走行中に毎サブステップ参照するので、初期化時に 1 度だけ求めて持つ。
    public let checkpoint: Double

    public init(number: Int, pattern: String, speed: Double) {
        self.number = number
        self.pattern = pattern
        self.speed = speed
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let length = Double(pattern.count) * segmentWidth
        let hazards = Self.makeHazards(pattern: pattern)
        self.length = length
        self.hazards = hazards
        self.checkpoint = Self.makeCheckpoint(length: length, hazards: hazards)
    }

    /// 区画記号を障害の並びへ展開する。
    static func makeHazards(pattern: String) -> [RunnerHazard] {
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let offset = Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth
        var result: [RunnerHazard] = []
        for (index, symbol) in pattern.enumerated() {
            guard let spec = Self.segmentSpec(symbol) else { continue }
            result.append(RunnerHazard(
                kind: spec.kind,
                start: Double(index) * segmentWidth + offset,
                length: Double(spec.tiles) * RunnerRules.tileWidth
            ))
        }
        return result
    }

    /// 区画記号 1 文字の中身。`-`（平地）と未知の文字は nil。
    ///
    /// 穴（`1`〜`3`）は**表記の数字 + 1 タイル**ぶんの幅にする。走者の見た目の横幅
    /// （`RunnerField.Metrics.playerWidth` = 8）に対して数字どおりの1タイル（4）だと
    /// 穴が走者より狭く見え、跳んで越えるべきものに見えなかった（会長QA）。
    /// 区画の並び（`hazardTileOffset`・`segmentTiles`）は変えていないので、
    /// 隣の障害までの間隔は従来どおり保たれる——広がるのは穴の幅だけ。
    static func segmentSpec(_ symbol: Character) -> (kind: RunnerHazardKind, tiles: Int)? {
        switch symbol {
        case "1": return (.pit, 2)
        case "2": return (.pit, 3)
        case "3": return (.pit, 4)
        case "n": return (.lowBlock, 1)
        case "t": return (.tallBlock, 1)
        default:  return nil
        }
    }

    /// 中点から右へずらしながら、障害と重ならず着地に必要な余白もある位置を探す。
    static func makeCheckpoint(length: Double, hazards: [RunnerHazard]) -> Double {
        let step = RunnerRules.tileWidth
        // 走者の前後に体 1 つぶんの余白を要求する（縁ぎりぎりから再開させない）。
        let margin = RunnerField.Metrics.playerWidth
        var x = (length / 2 / step).rounded(.down) * step
        let limit = length - step * 4
        while x < limit {
            if !hazards.contains(where: { $0.start - margin < x && x < $0.end + margin }) { return x }
            x += step
        }
        return x
    }
}

public extension RunnerStage {
    /// 全 15 ステージ。Issue #494 の受け入れ条件は「最低15ステージ」。
    ///
    /// 難度の付け方:
    /// - 速さは 1 ステージごとに `speedStep` ずつ上がる（1 面 34 → 15 面 50.8）
    /// - 長さも 1 区画ずつ伸びる（1 面 12 区画 → 15 面 26 区画。おおよそ 23 秒 → 33 秒）
    /// - 障害は「穴 1 タイル → 低い障害物 → 穴 2 タイル → 高い障害物 → 穴 3 タイル」の順に出す。
    ///   後半ほど平地（`-`）の割合が減り、休む区画が少なくなる
    ///
    /// **区画の中央にしか障害を置かない**ので、隣り合う障害の間隔は常に
    /// 13 タイル（52 ワールド単位）以上になる。跳べる幅・越えられる高さ・間隔の成立条件は
    /// `RunnerStageTests` が全ステージについて機械的に確かめる。
    static let all: [RunnerStage] = patterns.enumerated().map { index, pattern in
        RunnerStage(
            number: index + 1,
            pattern: pattern,
            speed: RunnerRules.baseSpeed + Double(index) * RunnerRules.speedStep
        )
    }

    /// ステージ番号（1 始まり）から。範囲外は nil。
    static func stage(number: Int) -> RunnerStage? {
        guard number >= 1, number <= all.count else { return nil }
        return all[number - 1]
    }

    /// 区画記号の実体。**先頭と末尾は必ず 2 区画ぶん平地**（走り出しとゴール前に余白を作る）。
    ///
    /// 区画数は `RunnerRules.baseSegments + (ステージ番号 - 1)`、障害の割合はステージ 1 の
    /// およそ 1/3 から最終面の 8 割強まで一定の刻みで増える。どちらも `RunnerStageTests` が
    /// 全ステージについて機械的に確かめる（手で足したときに間隔が崩れないようにするため）。
    private static let patterns: [String] = [
        "--1---1--1--",              // 1: 12区画・障害3個。1 タイルの穴だけで間合いを覚える
        "--1---n---1--",             // 2: 13区画・障害3個。低い障害物の初出
        "--1--n--2--n--",            // 3: 14区画・障害4個。2 タイルの穴の初出
        "--1-n--t--1-n--",           // 4: 15区画・障害5個。高い障害物の初出
        "--n-1-t--2-n-t--",          // 5: 16区画・障害6個
        "--1-n-3-t-2-n-t--",         // 6: 17区画・障害7個。3 タイル（跳べる最大幅）の穴の初出
        "--1-n-3-t2-n-t-1--",        // 7: 18区画・障害8個。障害が隣り合う区画が出始める
        "--2-t-1n-3-t2-n-t--",       // 8: 19区画・障害9個
        "--2-t1-n-3t-2-nt-3--",      // 9: 20区画・障害10個
        "--2-t1-n3-t-2n-t3-2--",     // 10: 21区画・障害11個
        "--t2-n3-t1t-2t-3n-tt--",    // 11: 22区画・障害13個
        "--t2-n3-t1t-2t3-nt-t2--",   // 12: 23区画・障害14個
        "--t2-n3t1-t2t3-ntt2-n3--",  // 13: 24区画・障害16個
        "--3t2-t3n-t3t2t-3tn-3t2--", // 14: 25区画・障害17個
        "--3t2-t3nt3t2-t3tn3-t2t3--", // 15: 26区画・障害19個。速さ 50.8・約 33 秒
    ]
}

#if DEBUG
public extension RunnerStage {
    /// QA用: 低い障害物・高い障害物・穴3サイズの計5種を1本で見比べられるステージ
    /// （起動引数 `-simulateRunner showcase`）。`.all`（本番の15ステージ）には含めない
    /// ——`number` を 0 にして「実ステージではない」ことを型で示す。
    ///
    /// 間隔は他ステージよりゆったり取ってある（QA中に慌てて次の障害へ突っ込まないため）。
    /// 速さは1面と同じ `RunnerRules.baseSpeed` で固定。
    static let debugShowcase = RunnerStage(
        number: 0,
        pattern: "--n--t--1--2--3--",
        speed: RunnerRules.baseSpeed
    )
}
#endif
