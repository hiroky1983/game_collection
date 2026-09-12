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

    /// 重力（ワールド単位 / 秒²）。押している間も含めて常に一定
    /// （2026-09-10 会長QA「長押しで大ジャンプ・軽いタップは本当に小ジャンプに」を受けて
    /// 「押している間だけ重力を弱める」旧方式から「離した瞬間に速度を切り詰める」方式へ
    /// 変えた。重力そのものを操作で変えないほうが軌道の計算が単純になる）。
    public static let gravity: Double = 200
    /// 踏み切りの初速。二段目も同じ初速を使う（`RunnerField.jump()`）。
    ///
    /// **これは「長押しした場合」の初速のまま**——踏み切った瞬間にどれだけ長く
    /// 離さずにいるかは分からないので、まず勢いよく踏み切っておき、早く離した場合だけ
    /// `endHold()` が速度を切り詰める（下記 `jumpCutVelocity`）。既存 15 ステージの
    /// 成立条件（`RunnerStageTests`）はこの初速のまま長押しした軌道で判定しているので、
    /// この値自体は変えていない——ステージの再設計は不要。
    public static let jumpVelocity: Double = 75
    /// 接地してから使える踏み切りの回数（会長決裁 2026-09-10・2段ジャンプ）。
    ///
    /// **既存 15 ステージの成立条件（`RunnerStageTests`）は一段目の単発ジャンプだけで
    /// 満たせるままにしてある**——二段目は「あってもクリア可能」を崩さない上振れの
    /// 救済として足す。自動操縦（`RunnerAutoPilot`）も接地中しか踏み切らないので、
    /// この定数を増やしてもテストの前提には影響しない。
    public static let maxJumps: Int = 2

    /// 早く離したときに `vy` を切り詰める上限（会長QA「軽いタップなら本当に小ジャンプ
    /// ぐらいの感じにしたい」2026-09-10）。
    ///
    /// `RunnerField.endHold()` は、離した瞬間まだ上昇中（`vy > 0`）で、かつ `vy` がこの値を
    /// 上回っていれば、ここまで切り詰める（実際に切り詰めが起きるのは `jumpCutGraceTime` を
    /// 過ぎてから。そちらのドキュメントを参照）。離すタイミングが遅くなる（≒ 長く押し続ける）
    /// ほど、離した瞬間の `vy` はすでに重力で減っているためこの切り詰めの影響が薄れ、
    /// 十分長く押せば（目安: 自然に `vy` がこの値を下回るまで、押してから
    /// (`jumpVelocity` − `jumpCutVelocity`) / `gravity` ≒ 0.225 秒）切り詰め無しの全弾道
    /// （頂点 `jumpApex` ≒ 14.06）まで伸びる。
    public static let jumpCutVelocity: Double = 30

    /// 踏み切ってから、切り詰めが実際に効き始めるまでの猶予（秒）。
    ///
    /// **会長の実機QAで「進まねえ」（2026-09-11）という深刻な不具合が発覚**したための追加。
    /// 猶予無しで「離した瞬間の `vy` をそのまま切り詰める」実装だと、SwiftUI の
    /// `DragGesture` はタップ操作で `onChanged`（`press()`）と `onEnded`（`release()`）が
    /// 同じフレーム内でほぼ同時に呼ばれることがあり、その場合 `RunnerField.step` が
    /// 1 度も進まないうちに切り詰められて頂点 2.25 のごく小さいホップにしかならず、
    /// **ステージ1の最初の穴（幅8）にすら届かなかった**（実測で確認済み）。
    ///
    /// 対策として、`endHold()` が呼ばれても猶予時間が経つまでは実際には切り詰めず
    /// （`isHolding` のまま自然な弾道を継続させ）、猶予が明けた瞬間の `vy` を基準に
    /// 切り詰める方式にした。これにより「瞬間タップ」は「ちょうど `jumpCutGraceTime` 秒
    /// だけ押し続けてから離した」のと同じ弾道になる——実際のボタン操作の長さに関わらず、
    /// 最低でもこの猶予ぶんの高さ・滞空は保証される。
    ///
    /// 値は全15ステージ・全145障害を「瞬間タップ相当（＝この猶予ぶんだけ自然に上昇させてから
    /// `jumpCutVelocity` まで切り詰める）」で機械的に検証し、**穴・低い障害物・鳥はすべて
    /// 瞬間タップだけで越えられ、高い障害物（`tallBlock`、頂点近くを通す必要がある設計）だけ
    /// 長押しが要る**、という境目になるよう選んだ（0.13 秒）。会長の要望どおり「軽いタップは
    /// 本当に小ジャンプ」の感触は残しつつ（頂点は `jumpApex` の約73%に留まる）、
    /// 実際の操作でゲームが進まなくなる事故を防ぐ。
    public static let jumpCutGraceTime: Double = 0.13

    /// 十分長く押し続けた場合（= 切り詰められない）ジャンプの滞空時間。
    ///
    /// **ステージの成立条件はこちらで判定する**（`RunnerStageTests`）。自動操縦
    /// （`RunnerAutoPilot`）は着地するまで離さないので、常にこの軌道になる。
    public static var jumpAirTime: Double { 2 * jumpVelocity / gravity }
    /// 同じく、十分長く押し続けた場合のジャンプの頂点の高さ。
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
    ///
    /// **2026-09-10 チューニング（会長の再QA）**: 導入時の 1.45 は、実際に走ると
    /// 「効率よく漕いでもタイムがほぼ変わらない」まま残っていた。原因は上限の狭さではなく、
    /// 自動操縦で必要最小限のジャンプだけをした場合でも乗りが早々に上限近くまで達してしまい
    /// （後述 `pedalGain`）、「下手なプレイと比べてどれだけ得か」の伸びしろが小さかったこと。
    /// 上限を広げることで、効率よく乗り続けたときと乗れていないときの速さの差そのものを広げた。
    public static let maxPedalBoost: Double = 1.55
    /// 接地して漕いでいるあいだに乗りが上がる速さ（毎秒）。
    ///
    /// 下限から上限（幅 0.55）まで漕ぎ切るのに約 0.79 秒。障害が詰まった後半のステージでは
    /// 跳ぶたびに巻き戻されるので、上限まで乗るのは平地が続く区間だけになる。
    public static let pedalGain: Double = 0.70
    /// 空中にいるあいだに乗りが落ちる速さ（毎秒）。
    ///
    /// 最小のジャンプ（滞空 `jumpAirTime` = 0.75 秒）で 0.23 落ちる = 幅 0.55 の半分弱を失い、
    /// 取り戻すのに 0.32 秒の地面が要る。押し続けて高く跳べば滞空が伸び、そのぶん多く落ちる。
    public static let pedalLoss: Double = 0.30
    /// ステージ 1 の区画数。ここから 1 ステージごとに 1 区画ずつ長くなる。
    public static let baseSegments = 12

    // MARK: ジャスト着地（#673・2026-09-12 会長決裁 #635）

    /// 越えた障害の右端（`RunnerHazard.end`）から着地点までの距離が、ここに収まれば
    /// 「ジャスト着地」（`RunnerField.lastLandingWasJust`）。
    ///
    /// **空中の速さは据え置いたまま、着地の質でタイムに差を出すための窓**（#635 決裁。
    /// 空中に乗りを載せる案は「跳んで進む距離 = `speed × jumpAirTime`」という全ステージの
    /// 物差しを壊すため不採用）。
    ///
    /// 値は**走者の体 1 つぶん**（`RunnerField.Metrics.playerWidth` = 8 = 2 タイル）。
    /// 「障害の真裏、自分の体が入るだけの隙間に降りる」が判定の実体。
    ///
    /// **実測でこの広さに決めた**（2026-09-12・全15ステージ145障害）:
    /// - 押しっぱなしの全弾道（`RunnerAutoPilot` の決め打ちの走り）が着地するのは
    ///   右端から 7.8〜15.3 先。8 ならこの走りはほぼ一度も成立しない（145 障害中 1 回。
    ///   跳べる最大幅の穴を全弾道でちょうど渡り切った 1 件で、これは実際にジャスト着地）
    /// - 一方、**越えられる最小のジャンプ（タップ）で跳ぶと穴の向こう岸のすぐ裏に降りられる**。
    ///   この差がそのままスキル差になる
    ///
    /// なお、岩（`lowBlock`/`tallBlock`）でこの窓に入るのは**物理的に不可能**に近い——
    /// 上端を越えてから地面までの落下距離（高さ 5〜9 ぶん）だけで体 2〜4 つぶん進むため、
    /// どんな跳び方でも右端から 12 以上先に降りる。結果としてこの加算は実質「穴を
    /// 渡り切る腕前」への報酬になる（岩を対象から外していないのは、対象の判断を
    /// `RunnerField.rewardsJustLanding` の一箇所に閉じておくため）。
    public static let justLandingWindow: Double = 8
    /// ジャスト着地 1 回で `pedalBoost` に足す量（上限は `maxPedalBoost` のまま）。
    ///
    /// **最小のジャンプ（タップ・滞空 0.60 秒）で失う乗り `pedalLoss` × 0.60 ≒ 0.18 と同じ量**
    /// ——ジャスト着地を決めれば、そのジャンプで失った乗りがちょうど帳消しになる、という
    /// 1 行で言い切れる規則にしてある（`pedalGain` に換算すると 0.26 秒ぶんの漕ぎ）。
    ///
    /// **これ以上大きくしても効きは変わらない**（実測・2026-09-12）。`pedalGain` が 0.70/s と
    /// 速く、障害の間の平地だけで乗りは上限へ戻ってしまうため、1 ステージを通した乗りの
    /// 平均は自動操縦の走りでもすでに 1.45〜1.51（上限 1.55）——足せる余地そのものが小さい。
    /// 0.18 と 0.30 で全15ステージのタイムは 1 フレームも変わらなかった。
    public static let justLandingGain: Double = 0.18

    // MARK: スピードアップアイテム（会長QA「取るタイミングが大体もうMAX速度で意味がない」2026-09-10）

    /// アイテムを取った瞬間に一時的に乗る、`maxPedalBoost` を超える上乗せ分。
    ///
    /// 通常の乗り（`pedalBoost`）は良くても `maxPedalBoost`（1.55）で頭打ちなので、
    /// すでに乗り切った状態でアイテムを取ると何も変わらなかった。この上乗せは
    /// `pedalBoost` とは別枠で足すので、どんな乗り具合で取っても必ず加速する。
    /// 倍率は控えめに——「1.55倍はやりすぎかも」という会長の感覚（2026-09-10）を踏まえ、
    /// 通常の上限より少し出るだけの上乗せ（合計で最大 1.55 + 0.2 = 1.75 倍）に留めた。
    public static let pickupOverboost: Double = 0.2
    /// 上の上乗せ分が 0 まで減衰しきる秒数（線形減衰）。
    public static let pickupOverboostDuration: Double = 2.0

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

    // MARK: 落下演出

    /// 穴に落ちた/ぶつかった瞬間から失敗パネルを出すまでの間（秒）。
    ///
    /// この間は `RunnerPhase.falling` に留まり、`RunnerScene` が短い演出（沈む・回転・フェード）を
    /// 1 回だけ流す。会長QA「穴に落ちるアニメーションがある方がいいかも」を受けて追加。
    public static let fallDuration: Double = 0.5

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
/// | `b` | 鳥 |
/// | `s` | スピードアップアイテム（平地 + アイテム。障害としては扱わない） |
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
    /// 左から順に並んだスピードアップアイテム。
    ///
    /// **`hazards` とは別の配列**。触れて失敗する障害と、触れて得するアイテムを
    /// 同じ配列に混ぜると「越えられるか」の成立条件チェック（`RunnerStageTests`）に
    /// アイテムまで巻き込んでしまう。
    public let pickups: [RunnerPickup]
    /// チェックポイント（コースの中ほど）の x。
    ///
    /// **必ず平地に置く**。障害の上に置くと、再開した瞬間にまたミスになって進めない。
    /// 中点から右へずらしながら、障害と重ならず着地に必要な余白もある位置を探す。
    /// 走行中に毎サブステップ参照するので、初期化時に 1 度だけ求めて持つ。
    public let checkpoint: Double

    /// チェックポイントの到達率（`checkpoint / length` を四捨五入した整数パーセント）。
    ///
    /// `makeCheckpoint` が障害を避けて中点から後ろへずらすため、ステージによって
    /// ちょうど 50% とは限らない（40〜90% 程度でばらつく）。見た目の標識にはこの
    /// 実際の値をそのまま出す——「50% と書かれた旗」のように固定の数字に見せない
    /// （会長QA「中間地点のデザインも変えたほうがいい。現状何なのかわからん」への対応）。
    ///
    /// 空の `pattern` で作られたステージは `length` が 0 になる。`0 / 0` は NaN で、
    /// `Int(_:)` は NaN を変換できずクラッシュするため、その場合は 0 を返す。
    public var checkpointPercent: Int {
        guard length > 0 else { return 0 }
        return Int((checkpoint / length * 100).rounded())
    }

    public init(number: Int, pattern: String, speed: Double) {
        self.number = number
        self.pattern = pattern
        self.speed = speed
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let length = Double(pattern.count) * segmentWidth
        let hazards = Self.makeHazards(pattern: pattern)
        self.length = length
        self.hazards = hazards
        self.pickups = Self.makePickups(pattern: pattern)
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
    ///
    /// `pickupSymbol`（`s`）はここには含めない。**アイテムは障害ではない**ので
    /// `makeHazards`/`RunnerStageTests` の対象から自然に外れる。
    static func segmentSpec(_ symbol: Character) -> (kind: RunnerHazardKind, tiles: Int)? {
        switch symbol {
        case "1": return (.pit, 2)
        case "2": return (.pit, 3)
        case "3": return (.pit, 4)
        case "n": return (.lowBlock, 1)
        case "t": return (.tallBlock, 1)
        case "b": return (.bird, 1)
        default:  return nil
        }
    }

    /// スピードアップアイテムの区画記号。
    static let pickupSymbol: Character = "s"

    /// 区画記号をスピードアップアイテムの並びへ展開する。障害と同じ「区画の中央」に置く。
    static func makePickups(pattern: String) -> [RunnerPickup] {
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let offset = Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth
        var result: [RunnerPickup] = []
        for (index, symbol) in pattern.enumerated() where symbol == pickupSymbol {
            result.append(RunnerPickup(start: Double(index) * segmentWidth + offset))
        }
        return result
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
    ///
    /// `s`（スピードアップアイテム）はステージ 5 以降の平地区間に 1 個ずつ混ぜてある
    /// （会長QA「スピードアップアイテムor床とかあったほうがいい」）。障害ではないので
    /// 既存の障害の割合・間隔には影響しない。**必ず先頭寄り（最初の障害の直後あたり）に置く**
    /// ——アイテムの2つの効果のうち `pedalBoost` を上限へ引き上げるほう（乗れていない状態の
    /// 底上げ）は、ペダルブースト（`pedalGain=0.70/s`）が1秒足らずで上限に達するため、
    /// 中盤以降に置くとほぼ確実に空振りする。上乗せ分（`pickupOverboost`）は `pedalBoost` と
    /// 別枠なので上限に張り付いていても必ず加速するが（`FieldTests`
    /// `collectingPickupAtMaxBoostStillSpeedsUp`）、それだけでは「取っても代わり映えしない」
    /// という印象が残る（会長QA「取るタイミング大体MAXスピードのときで全く意味がない」・
    /// 2026-09-11）。ステージ13〜15は新設時から先頭寄りに置けていたので変更していない。
    /// `b`（鳥）はステージ 13〜15 にだけ混ぜてある
    /// （会長QA「鳥とか右から車が来るとか要素はいる」）——当たり判定は `lowBlock`/`tallBlock`
    /// と同じ数学なので、間隔・跳べる高さの成立条件は他の障害と同じく `RunnerStageTests` が確かめる。
    ///
    /// **障害を足すときは平地（`-`）を潰さず、既存の障害の記号を置き換える。**
    /// 平地はタイムに操作を反映させるための余白そのもので、ここが無くなると
    /// 「上手く走ってもタイムが変わらない」状態に戻る（`inefficientPlayCostsMeaningfulTime`
    /// が最終面で 5.3% まで落ちて実際に落ちた）。鳥はこの規則に従い、平地ではなく
    /// 既存の `n`（低い障害物）を置き換えて配置してある。
    private static let patterns: [String] = [
        "--1---1--1--",              // 1: 12区画・障害3個。1 タイルの穴だけで間合いを覚える
        "--1---n---1--",             // 2: 13区画・障害3個。低い障害物の初出
        "--1--n--2--n--",            // 3: 14区画・障害4個。2 タイルの穴の初出
        "--1-n--t--1-n--",           // 4: 15区画・障害5個。高い障害物の初出
        "--ns1-t--2-n-t--",          // 5: 16区画・障害6個。スピードアップアイテムの初出
        "--1sn-3-t-2-n-t--",         // 6: 17区画・障害7個。3 タイル（跳べる最大幅）の穴の初出
        "--1sn-3-t2-n-t-1--",        // 7: 18区画・障害8個。障害が隣り合う区画が出始める
        "--2st-1n-3-t2-n-t--",       // 8: 19区画・障害9個
        "--2st1-n-3t-2-nt-3--",      // 9: 20区画・障害10個
        "--2st1-n3-t-2n-t3-2--",     // 10: 21区画・障害11個
        "--t2sn3-t1t-2t-3n-tt--",    // 11: 22区画・障害13個
        "--t2sn3-t1t-2t3-nt-t2--",   // 12: 23区画・障害14個
        "--t2sb3t1-t2t3-btt2-n3--",  // 13: 24区画・障害16個（岩穴14+鳥2）。鳥の初出
        "--3t2st3b-t3t2t-3tb-3t2--", // 14: 25区画・障害17個（岩穴15+鳥2）
        "--3t2st3bt3t2-t3tb3-t2t3--", // 15: 26区画・障害19個（岩穴17+鳥2）。速さ 50.8・約 33 秒
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
