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

    /// 乗れる台座の上面の高さ（地面からの相対値・#674）。
    ///
    /// **高低差は地面を動かさずに台座で作る**（#635 会長決裁 2026-09-12）。地面の高さ
    /// （`RunnerField.Metrics.groundY`）は全ステージ固定のままで、台座はその上に置く物体として
    /// 接地面だけを差し替える（`RunnerField.surfaceY(at:)`）。
    ///
    /// 8 は `jumpApex`（≒ 14.06）より十分低く、**地面から 1 回のジャンプで確実に上面へ乗れる**
    /// 高さ。**第1弾の台座はこの 1 種類だけ**なので段差は作れない（連続する `P` は 1 基に
    /// 融合する）が、高さ違いを足して段を重ねる日（次弾）に 1 段ぶん（8）ずつなら常に
    /// 1 回のジャンプで上がれ、2 段ぶん（16）は頂点を超えて段を飛ばせない、という
    /// 刻みになるよう選んである。
    /// 低い障害物（5）より高く高い障害物（9）よりわずかに低い値なので、「跳んで越える岩」と
    /// 「跳んで乗る台座」が同じくらいの踏み切りで扱えるのも狙い。
    public static let platformHeight: Double = 8

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
    /// `jumpCutVelocity` まで切り詰める）」で機械的に検証し、**穴・低い障害物はすべて
    /// 瞬間タップだけで越えられ、高い障害物（`tallBlock`、頂点近くを通す必要がある設計）だけ
    /// 長押しが要る**、という境目になるよう選んだ（0.13 秒。飛び立つ鳥（#796/#945）は跳ぶ相手
    /// ではなく**走ったまま下を抜ける**相手なので、この境目には関わらない——
    /// `RunnerPlaythroughTests.runningUnderClearsBirds`）。会長の要望どおり「軽いタップは
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
    ///
    /// **#968（会長 QA 2026-09-15「1.2 ずつだとステージを増やしたときに破綻する」）で 1.2 → 0.8。**
    /// 隣り合う区画に障害が並んでも成立する速さの上限は 63.6（`endlessMaxSpeed` を参照）で、
    /// 1.2 だと 25 面（62.8）で頭打ち・26 面で成立条件が壊れる。0.8 なら 18 面 47.6、33 面まで
    /// 増やしても 59.6 でエンドレスの上限 60 の内側、38 面で 63.6（`stagesLeaveHeadroomForMoreStages`
    /// が固定）。エンドレスの傾き（`endlessSpeedStepDistance`）はこの変更で据え置いてある。
    ///
    /// 下げた副作用は「瞬間タップ」（`jumpCutGraceTime`）の飛距離が序盤で縮むこと: 3 タイルの穴の
    /// 初出 6 面は 40 → 38.0 で、タップの飛距離 24.04 → 22.85（越えるのに要る 22 に対する余裕が
    /// 2.0 → 0.85）。`instantTapClearsPitsAndLowBlocks` は通るが、余裕を戻したければ最初の `3` を
    /// 9 面（40.4）以降へ動かす（6〜8 面の並びを変えるので別途決裁）。
    public static let speedStep: Double = 0.8

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
    /// **実測でこの広さに決めた**（2026-09-12・全15ステージ145障害で計測）:
    /// - 押しっぱなしの全弾道（`RunnerAutoPilot` の決め打ちの走り）が着地するのは
    ///   右端から 7.8〜15.3 先。8 ならこの走りはほぼ一度も成立しない（145 障害中 1 回。
    ///   跳べる最大幅の穴を全弾道でちょうど渡り切った 1 件で、これは実際にジャスト着地。
    ///   #968 で `speedStep` を 0.8 に下げてからは 6〜8 面の 3 タイルの穴で同じ形が 3 回——
    ///   全弾道の着地は右端から `0.75 × 速さ − 22` で、38〜39.6 では 6.5〜7.7 と窓の内側。
    ///   `RunnerPlaythroughTests.autoPilotRarelyEarnsJustLanding` が 3 回を上限に固定する）
    /// - 一方、**越えられる最小のジャンプ（タップ）で跳ぶと穴の向こう岸のすぐ裏に降りられる**。
    ///   この差がそのままスキル差になる
    ///
    /// なお、岩（`lowBlock`/`tallBlock`）でこの窓に入るのは**物理的に不可能**に近い——
    /// 上端を越えてから地面までの落下距離（高さ 5〜9 ぶん）だけで体 2〜4 つぶん進むため、
    /// どんな跳び方でも右端から 12 以上先に降りる。結果としてこの加算は実質「穴を
    /// 渡り切る腕前」への報酬になる（岩を対象から外していないのは、対象の判断を
    /// `RunnerField.rewardsJustLanding` の一箇所に閉じておくため）。
    public static let justLandingWindow: Double = 8
    /// ジャスト着地 1 回で乗る、`maxPedalBoost` を**超える**一時的な上乗せ分
    /// （2026-09-12 会長決裁。アイテムの `pickupOverboost` とまったく同じ形）。
    ///
    /// **`pedalBoost` への加算ではないのが要点**。当初は `pedalBoost` に足して上限で
    /// 頭打ちにしていたが、実測すると効果がほぼ無かった——`pedalGain`（0.70/s）が速く、
    /// 障害の間の平地だけで乗りは上限へ戻るため、1 ステージを通した乗りの時間平均は
    /// 決め打ちの走りでもすでに 1.45〜1.51（上限 1.55）で、**足せる余地そのものが無い**。
    /// 加算量を 0.18 から 0.30 へ上げても全ステージのタイムが 1 フレームも変わらなかった
    /// （＝上手い人と決め打ちの走りのタイム差は 3.0% どまりで、そのうち加算の寄与は
    /// 0.14 秒＝2 割だけ）。上限を超える別枠にすると、乗り切った状態でも必ず効く。
    ///
    /// **これはアイテム（`pickupOverboost` = +0.2）と同じ大きさ**。ジャスト着地1回が
    /// 「スピードアップアイテム1個ぶん」という釣り合いで、上限は合計 1.55 + 0.2 = 1.75 倍
    /// （アイテムと同時なら 1.95 倍。どちらも別枠なので足し合わさる）。
    /// この値での上手い人と決め打ちの走りのタイム差は 3.7〜5.4%（実測・下記 `RunnerPlaythroughTests`）。
    public static let justLandingOverboost: Double = 0.2
    /// 上の上乗せ分が 0 まで減衰しきる秒数（線形減衰）。`pickupOverboostDuration` と同じ 2 秒。
    ///
    /// 障害と障害の間隔（最短でも 13 タイル ≒ 1 秒）より長いので、**ジャスト着地を続ければ
    /// 上乗せが切れる前に次が乗る**——「決め続けているあいだは速いまま」という報酬になる。
    public static let justLandingOverboostDuration: Double = 2.0

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

    // MARK: たこ焼き（無敵・#797）

    /// たこ焼きを取ってから無敵（`RunnerField.isInvincible`）が切れるまでの秒数。
    ///
    /// Issue の例示どおり 3 秒。接地中の速さ（基準速 × 乗り 1.5 前後）で進む距離に直すと
    /// 4 面（36.4）で約 164 単位 ≒ 2.6 区画、18 面（47.6）で約 214 単位 ≒ 3.3 区画——
    /// 隣り合う障害の組（`n1` `t2` `btt2` など）を 1 つ丸ごと突っ切れる長さで、面の半分を
    /// 無敵で流せるほどではない。**速さ・ジャンプの物理には一切触れない**（#635 決裁）ので、
    /// ステージの成立条件（`RunnerStageTests`）は無敵の有無で変わらない。
    public static let invincibleDuration: Double = 3.0

    // MARK: スピードアップ床（#672・#635 会長決裁 2026-09-12）

    /// スピードアップ床に乗っているあいだ、**接地中の速さ**に掛かる倍率。
    ///
    /// アイテム（`pickupOverboost`）が別枠の**足し算**なのは「乗りが上限で頭打ちでも必ず
    /// 加速する」ためだが、床は**掛け算**にしてある。床は区間の性質（地面が速い）で、
    /// 乗り（操作の上手さ）とは独立した軸なので、掛け合わせれば「上手く漕げている人ほど
    /// 床の恩恵も大きい」が素直に成り立つ。足し算にすると乗り切った状態での旨味が
    /// 相対的に薄れ、アイテムと区別が付かない効き方になる。
    ///
    /// 値は 1.3。ペダルの上限（`maxPedalBoost` = 1.55）と重ねると最大 2.0 倍強になり、
    /// 「明らかに速い区間」として体感できる一方、**空中には一切乗らない**
    /// （`RunnerField.currentSpeed`）ので、ステージの成立条件が拠って立つ
    /// 「1 回のジャンプで進む距離 = `speed × jumpAirTime`」は変わらない。
    /// 上げすぎると床の上で次の障害へ突っ込む速さになるため、まずは控えめのこの値から始める。
    public static let boostFloorMultiplier: Double = 1.3

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

    // MARK: 動く障害（#796 飛び立つ鳥 / #800 犬 / #801 イノシシ・会長決裁 2026-09-14）
    //
    // どれも**走者の距離**で動く（時計では動かない）。ゆっくりモード・一時停止・ペダルの乗りに
    // 関わらず、同じ地点では同じ場所にいる——だから自動操縦のテストで軌道ごと固定できる。
    // 「走者が 1 進むあいだに動く量」（`advance`）で書いてあるので、走者の基準速に対する
    // 倍率がそのまま見た目の速さになる。

    /// 鳥が飛び立つ間合い。走者の**前端**がこの距離まで近づいた瞬間に飛び立つ（仕様「手前 6 タイル」）。
    ///
    /// 飛び立ってから走者の前端が帯に触れるまでの走者の進みは `G/(1−k)`（= 30）。1 面の速さで
    /// 0.88 秒、18 面で 0.55 秒——このあいだに鳥は跳んだ先の高さ（`birdClimbDistance` 参照）
    /// まで上がりきる。
    public static let birdTriggerDistance: Double = 6 * tileWidth
    /// 鳥の横の速さ（走者 1 に対して）。
    ///
    /// **大きいほど出会う地点が先へずれる。** 走者から見た鳥の等価な静止区間
    /// （`RunnerHazard.encounter`）は `start + k·G/(1−k)` から `(4 + 8)/(1−k) − 8` の長さ
    /// ——0.2 なら区画中央の 6 先から長さ 7。既存の面の `bt`（鳥の次の区画に高い岩）でも
    /// 着地して踏み切り直す余白が最速の 18 面で 2 単位以上残る値（0.25 だと 0.4 まで削れる）。
    /// 走者が鳥の下を抜けるあいだ（帯と横に重なる 15 単位）鳥は 3 だけ進み、抜けたあとは
    /// 走者の後ろへ置き去りになる。
    public static let birdAdvance: Double = 0.2
    /// 飛び立ってから、帯の下端が跳んだ先の高さ（`RunnerHazardKind.birdMeetBottom`）に届くまでの
    /// 鳥の移動量（1 タイル・#945）。そこから先は同じ高さのまま飛び続ける。
    ///
    /// **走者の前端が帯に触れる（`birdTravel` = `k·G/(1−k)` = 6）より手前で上がりきる**のが要点
    /// （#945 会長QA「飛び立つのが遅く、跳ぶだけで躱せる」）。鳥が 1 タイル進むあいだに走者は
    /// 20 進むので、上がりきるのは走者の前端が帯の 8 手前に来た時点。帯の下端が走者の頭
    /// （`RunnerField.Metrics.playerHeight` = 11）を越えるのはさらに手前（走者の進み 15、
    /// 帯までの間合い 16）で、自動操縦が岩と見なして踏み切る間合い（`RunnerAutoPilot.lead`・
    /// 上限の速さで 9.5）より十分外側——自動操縦は鳥を「跳ぶ相手」として見ずに済む
    /// （`RunnerHazardMotionTests.birdRisesAboveTheHeadBeforeTheTakeOffWindow`）。
    /// 上限は 1.5 タイル（= 6。触れる瞬間にちょうど上がりきる）で、そこまで延ばすと頭を越えるのが
    /// 間合いと同じ 9.5 手前になり、自動操縦が跳んで鳥に当たる。
    public static let birdClimbDistance: Double = 1 * tileWidth
    /// 上がる傾き（鳥が 1 進むごとに上がる高さ）。止まっている帯の下端から跳んだ先の高さまで、
    /// `birdClimbDistance` で一定に上がる。
    static var birdClimbSlope: Double {
        (RunnerHazardKind.birdMeetBottom - RunnerHazardKind.bird.bottom) / birdClimbDistance
    }
    /// 飛び立つ前に羽ばたく予備動作を始める、走者の距離の手前（見た目だけ・当たり判定は変えない）。
    public static let birdFlutterDistance: Double = 2 * tileWidth

    /// 犬が画面の右の外に現れてから、鼻先が走者の前端に触れるまでの走者の進み（#955）。
    ///
    /// 現れる瞬間、鼻先は走者の前端の `(1 + dogAdvance) × 56` ≒ 75.6 先——画面の先読み
    /// （`RunnerField.Metrics.width` − `playerX` − 半身 = 70）より 5.6 外側で、絵を当たり判定より
    /// 大きく描いても（#943 の倍率 2 で前後に 2 ずつ張り出す）画面の中に「湧く」ことは無い。
    /// 13 タイル（52）だと 70.2 でぎりぎり、これ以上長くしても見え方は変わらない
    /// （見えるのは画面に入ってからで、それは `dogAdvance` だけで決まる）。
    public static let dogApproachDistance: Double = 14 * tileWidth
    /// 犬の歩く速さ（走者 1 に対して）。走者に向かって左へ歩くので相対速度は `1 + dogAdvance`。
    ///
    /// 小さいほど静止した低い岩に近づく（0 なら低い岩そのもの）。相対速度が上がるほど重なる
    /// 時間は短くなる（等価な静止区間は `(4 + 8) / (1 + k) − 8`）が、**画面に入ってから触れる
    /// までの時間も縮む**: 画面の先読み 70 を `1 + k` で詰めるので、1 面の速さ（34）で
    /// 0.5 なら 1.37 秒、0.35 なら 1.53 秒——受け入れ条件「見えてから当たるまで 1.5 秒以上」
    /// （#955）を満たす上限が 0.37。0.35 で相対速度は 1.35、重なりは 8.9 / speed
    /// （低い岩の 12 / speed より短い）。18 面（47.6・#968）では 1.09 秒で、これは低い岩（1.47 秒）と
    /// 同じ比率で縮んでいるだけ。
    public static let dogAdvance: Double = 0.35

    /// イノシシの予告から出会いまでの走者の進み（仕様「1 秒ほど」）。
    ///
    /// 出会いの地点の手前この距離で「ドドド」と土煙が出て、同じ距離だけ向こうから走者と同じ
    /// 速さで向かってくる。7 面の基準速 41 で 1.75 秒、ペダルが乗った実際の速さ（1.3〜1.5 倍）で
    /// 1.2〜1.35 秒。出現点（`start + 72`）は次の区画の岩（`start + 64`〜`68`）より先なので、
    /// 岩の手前に置いた（`it`）イノシシはその岩で止まる。予告の瞬間、出現点は画面の外
    /// （前端から 148 先・見えるのは 74 まで）で、見えてから出会うまでは約 35 単位。
    public static let boarChargeDistance: Double = 18 * tileWidth
    /// イノシシの速さ（走者 1 に対して）。走者と同じなので相対速度は 2 倍。
    public static let boarAdvance: Double = 1

    // MARK: 突き上げ（#1010 竹の子・波しぶき・会長決裁 2026-09-17〜18）

    /// 突き上げの予告が出て伸び始める間合い。走者の**前端**がこの距離まで近づいた瞬間
    /// （`RunnerHazard.shootCueDistance`）。
    ///
    /// **値は「その区画が画面の右端に入る間合い」そのもの**（= 画面の先読み `width − playerX` から
    /// 前端のぶん半身を引いた 70）で、直値では書かない。予告は**見て読むもの**なので、
    /// 画面の外で出しても意味が無く、かつ**これ以上早くはできない**——読める時間の上限は
    /// 「画面に入ってから踏み切るべき地点に着くまで」で決まる。
    ///
    /// 実測（`RunnerHazardMotionTests.shootCueLeavesTimeToRead`）: 最速の 30 面（基準速 57.2・
    /// ペダル上限 1.55 倍 = 88.7/秒）で、予告から踏み切り地点（高い岩と同じ `lead` = 15.2 手前）
    /// までは 58.8 単位 ＝ **0.66 秒**。基準速なら 1.03 秒。犬の「見えてから触れるまで」
    /// （18 面で 1.09 秒）・イノシシの「予告から出会いまで」（7 面で 1.2〜1.35 秒）と同じ物差しで、
    /// 跳ぶ相手としては最速の面でいちばん短い——だから**これ以上短くしない**（下限は
    /// テストで 0.6 秒に固定してある）。
    public static var shootTriggerDistance: Double {
        RunnerField.Metrics.width - RunnerField.Metrics.playerX - RunnerField.Metrics.playerHalfWidth
    }
    /// 予告が出てから伸び切るまでの**走者の進み**（8 タイル）。
    ///
    /// 上限は「踏み切るべき地点に走者が来るまでに伸び切る」こと——`shootTriggerDistance + 半身
    /// − lead`（30 面で 58.8）まで延ばせるが、伸び切った姿を読む時間が無くなる。32 なら
    /// 30 面でも踏み切り地点の 26.8 手前（0.30 秒）で伸び切り、残りを「高い岩と同じ相手」として
    /// 読める。時間ではなく距離で決めているのは、動く障害すべてと同じ理由——同じ地点では
    /// 常に同じ高さになり、ゆっくりモード・一時停止・ペダルの乗りに左右されない。
    public static let shootRiseDistance: Double = 8 * tileWidth

    // MARK: エンドレス（#675・会長決裁 2026-09-12）
    //
    // コースに終わりは無い（#1086・会長決裁 2026-09-17）。区画は走りながら作る（`RunnerEndlessTrack`）。

    /// エンドレスで速さが `speedStep` ぶん上がるのに要する距離（ワールド単位）。
    ///
    /// ステージ制の「1 ステージ進むごとに `speedStep`」を距離に写したもの。導入時（`speedStep` = 1.2）
    /// は 1,024 = 16 区画で、ステージ 5 前後の長さ・18 面まで通した累計（約 370 区画で 34 → 54.4）
    /// とほぼ同じ傾きだった。**#968 で `speedStep` を 0.8 に下げたときエンドレスの傾きは据え置く**
    /// ——会長の指摘は「面を増やしたときの破綻」で、エンドレスは上限 60 で頭打ちになる設計のまま
    /// 変える理由が無い——ので、距離を同じ比率（0.8 / 1.2 = 2/3）に縮めて `speedGain` を
    /// 1.2 / 1,024 のまま保っている。3 タイルの穴の解禁（速さ 41.2 = 6,144 進んだ地点・
    /// `RunnerEndlessCourse.parts`）と上限に達する距離（22,187）もこれで変わらない。
    public static let endlessSpeedStepDistance: Double = 1024 * speedStep / 1.2
    /// エンドレスの速さの上限。
    ///
    /// **隣り合う区画に障害が並んでも着地して踏み切り直せる速さの範囲**で頭打ちにする。
    /// 区画の間隔は 64 で、いちばん厳しい「高い障害物が隣に来る」場合に要る間隔は
    /// `speed × jumpAirTime + baseLead + speed × riseTime(9.5)` ≒ 0.911 × speed + 6 なので、
    /// 63.6 を超えると成立しなくなる。60 は 18 面（47.6・#968 で 54.4 から下がった）より 26% 速く、
    /// 33 面まで増やしても届かない値（`speedStep` を参照）。
    /// 画面に見える先読み（`RunnerField.Metrics.width`）は 74 単位 = 60 / 秒で約 1.2 秒。
    /// 唯一の例外は**飛び立つ鳥の直後の高い岩**（#796。鳥は出会う地点が区画中央より 6 先へ
    /// ずれるため、この速さでは 2.7 足りない）。生成器はこの並びを `canPlace` で弾いて平地に倒す
    /// （`RunnerEndlessCourseTests.maxSpeedKeepsAdjacentHazardsPassable` が固定）。
    public static let endlessMaxSpeed: Double = 60
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
/// | `b` | 飛び立つ鳥（#796） |
/// | `d` | 犬（#800） |
/// | `i` | イノシシ（#801） |
/// | `^` | 下から突き上げる障害（#1010。里山＝竹の子・港町＝波しぶき。19 面以降だけ） |
/// | `s` | スピードアップアイテム（平地 + アイテム。障害としては扱わない） |
/// | `k` | たこ焼き（平地 + 一定時間無敵になるアイテム。障害としては扱わない・#797） |
/// | `P` | 乗れる台座（区画まるごと。**連続する `P` は 1 つの台座にまとまる**） |

/// | `=` | スピードアップ床（平地 + 加速区間。障害としては扱わない。連続すると 1 つの床になる） |
public struct RunnerStage: Equatable, Sendable {
    /// 1 始まりのステージ番号。
    public let number: Int
    /// 区画記号の並び。
    public let pattern: String
    /// 走る速さ（ワールド単位 / 秒）。**コース先頭での値**。
    ///
    /// ステージ制ではコース全体で一定。エンドレス（#675）は距離に応じて上がるので、
    /// 走行中の基準速は `speed(at:)` で引く。
    public let speed: Double
    /// 1 ワールド単位進むごとに基準速が上がる量（#675）。ステージ制は 0（一定）。
    public let speedGain: Double
    /// 基準速の上限。`speedGain` が 0 なら `speed` と同じ。
    ///
    /// `RunnerField.step` はこの値で 1 サブステップの移動量を見積もる（速くなる余地を
    /// 最初から見込んでおくので、加速してもすり抜けは起きない）。
    public let speedCap: Double
    /// コースの全長。
    public let length: Double
    /// 左から順に並んだ障害。
    public let hazards: [RunnerHazard]
    /// 左から順に並んだアイテム（スピードアップ `s` とたこ焼き `k`・#797）。
    ///
    /// **`hazards` とは別の配列**。触れて失敗する障害と、触れて得するアイテムを
    /// 同じ配列に混ぜると「越えられるか」の成立条件チェック（`RunnerStageTests`）に
    /// アイテムまで巻き込んでしまう。種類が違っても 1 本の配列に並べる——取得済みの管理
    /// （`RunnerField.collectedPickupIndices`）と描画の消し込み（`RunnerScene`）が添字で
    /// 対応しているので、種類ごとに配列を分けるとその対応を 2 重に持つことになる。
    public let pickups: [RunnerPickup]
    /// 左から順に並んだ乗れる台座（#674）。
    ///
    /// **`hazards` とは別の配列**。台座は「越えるもの」ではなく「上に乗るもの」で、
    /// 接地面そのものを差し替える（`RunnerField.surfaceY(at:)`）。障害と同じ配列に入れると
    /// 「すべての障害が越えられる」という成立条件チェック（`RunnerStageTests`）が
    /// 意味を成さない判定を台座にまで掛けてしまう。
    public let platforms: [RunnerPlatform]

    /// 左から順に並んだスピードアップ床（#672）。
    ///
    /// `pickups` と同じ理由で **`hazards` とは別の配列**。床は障害としては平地なので、
    /// 成立条件チェック（`RunnerStageTests`）にも当たり判定にも巻き込まない。
    public let boostFloors: [RunnerBoostFloor]
    /// チェックポイント（コースの中ほど）の x。
    ///
    /// **必ず平地に置く**。障害の上に置くと、再開した瞬間にまたミスになって進めない。
    /// 台座も避ける（#674）——台座の範囲から再開すると、地面の高さに置かれた走者が
    /// 台座の中にめり込んだ状態で始まる。
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

    /// - Parameters:
    ///   - speedGain: 距離あたりの加速（#675）。既定の 0 で従来どおり一定の速さ。
    ///   - speedCap: 加速の上限。省略すると `speed`（= 加速しない）。
    public init(
        number: Int, pattern: String, speed: Double,
        speedGain: Double = 0, speedCap: Double? = nil
    ) {
        self.number = number
        self.pattern = pattern
        self.speed = speed
        self.speedGain = speedGain
        self.speedCap = max(speed, speedCap ?? speed)
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let length = Double(pattern.count) * segmentWidth
        let hazards = Self.makeHazards(pattern: pattern)
        let platforms = Self.makePlatforms(pattern: pattern)
        self.length = length
        self.hazards = hazards
        self.pickups = Self.makePickups(pattern: pattern)
        self.platforms = platforms
        self.checkpoint = Self.makeCheckpoint(length: length, hazards: hazards, platforms: platforms)

        self.boostFloors = Self.makeBoostFloors(pattern: pattern)
    }

    /// その地点での基準速（#675）。`speed` から `speedGain` の傾きで上がり、`speedCap` で頭打ち。
    ///
    /// ステージ制（`speedGain` = 0）では常に `speed` を返す。**空中の横速度もこの値**
    /// （`RunnerField.currentSpeed`）なので、跳んでいるあいだに進んだぶんだけごくわずかに
    /// 速くなる——1 回のジャンプ（45 単位）で 0.05 程度で、踏み切りの余裕（`RunnerAutoPilot.baseLead`
    /// の半タイル = 2）に比べて無視できる。生成器はこの差も見込み、成立条件を区画の手前の
    /// 速さ（越えられるか）と先の速さ（間隔）の両方で判定する（`RunnerEndlessCourse`）。
    public func speed(at distance: Double) -> Double {
        guard speedGain > 0 else { return speed }
        return min(speedCap, speed + speedGain * max(0, distance))
    }

    /// 区画記号を障害の並びへ展開する。
    ///
    /// イノシシ（#801）は展開後に岩の並びを見て「どこで止まるか」（`stopAt`）を焼き込む。
    /// 走行中に毎サブステップ岩を探さないため。
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
        return result.map { hazard in
            guard hazard.kind == .boar else { return hazard }
            return RunnerHazard(
                kind: .boar, start: hazard.start, length: hazard.length,
                stopAt: boarStop(for: hazard, among: result)
            )
        }
    }

    /// イノシシが止まる x（#801）。出会いの地点（`start`）と出現点（`boarSpawn`）のあいだにある
    /// 岩のうち、**出現点にいちばん近い岩の右端**。走者に出会うより先にぶつかる岩が無ければ nil。
    ///
    /// 出会いの地点より手前の岩は数えない——イノシシはそこへ着く前に走者と出会っている
    /// （出会った時点で跳ばれたか当たったかのどちらかで、その先の動きは見た目にしか関わらない）。
    static func boarStop(for boar: RunnerHazard, among hazards: [RunnerHazard]) -> Double? {
        hazards
            .filter { $0.kind.isRock && $0.end > boar.start && $0.end <= boar.boarSpawn }
            .map(\.end)
            .max()
    }

    /// 区画記号 1 文字の中身。`-`（平地）と未知の文字は nil。
    ///
    /// 穴（`1`〜`3`）は**表記の数字 + 1 タイル**ぶんの幅にする。走者の見た目の横幅
    /// （`RunnerField.Metrics.playerWidth` = 8）に対して数字どおりの1タイル（4）だと
    /// 穴が走者より狭く見え、跳んで越えるべきものに見えなかった（会長QA）。
    /// 区画の並び（`hazardTileOffset`・`segmentTiles`）は変えていないので、
    /// 隣の障害までの間隔は従来どおり保たれる——広がるのは穴の幅だけ。
    ///
    /// `pickupSymbol`（`s`）・`takoyakiSymbol`（`k`）と `boostFloorSymbol`（`=`）はここには
    /// 含めない。**アイテムも床も障害ではない**ので `makeHazards`/`RunnerStageTests` の
    /// 対象から自然に外れる（いずれも地形としては平地そのもの）。
    static func segmentSpec(_ symbol: Character) -> (kind: RunnerHazardKind, tiles: Int)? {
        switch symbol {
        case "1": return (.pit, 2)
        case "2": return (.pit, 3)
        case "3": return (.pit, 4)
        case "n": return (.lowBlock, 1)
        case "t": return (.tallBlock, 1)
        case "b": return (.bird, 1)
        case "d": return (.dog, 1)
        case "i": return (.boar, 1)
        case "^": return (.shoot, 1)
        default:  return nil
        }
    }

    /// スピードアップアイテムの区画記号。
    static let pickupSymbol: Character = "s"
    /// たこ焼き（無敵・#797）の区画記号。既存の記号（`-123ntbsP=`）と被らない小文字 1 つ。
    static let takoyakiSymbol: Character = "k"

    /// 区画記号をアイテムの並びへ展開する。障害と同じ「区画の中央」に置く。
    static func makePickups(pattern: String) -> [RunnerPickup] {
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        let offset = Double(RunnerRules.hazardTileOffset) * RunnerRules.tileWidth
        var result: [RunnerPickup] = []
        for (index, symbol) in pattern.enumerated() {
            let kind: RunnerPickupKind
            switch symbol {
            case pickupSymbol:   kind = .speed
            case takoyakiSymbol: kind = .invincible
            default:             continue
            }
            result.append(RunnerPickup(kind: kind, start: Double(index) * segmentWidth + offset))
        }
        return result
    }

    /// 乗れる台座の区画記号（#674）。
    ///
    /// `=`（スピードアップ床・別 Issue）と紛れないよう大文字 1 文字にしてある。
    static let platformSymbol: Character = "P"

    /// 区画記号を台座の並びへ展開する。
    ///
    /// **障害と違い、台座は区画をまるごと占める**（`hazardTileOffset` を使わない）。台座は
    /// 上を走るものなので、区画の中央に短く置くと乗った直後に降りることになって用を成さない。
    /// **連続する `P` は 1 つの台座にまとめる**ので、`PPP` は 3 区画ぶんの長さの台座 1 つになる
    /// ——隣り合う 2 つの台座として展開すると、継ぎ目に「端から落ちる」判定が生まれてしまう。
    static func makePlatforms(pattern: String) -> [RunnerPlatform] {
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        var result: [RunnerPlatform] = []
        var runStart: Int?
        for (index, symbol) in pattern.enumerated() {
            if symbol == platformSymbol {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                result.append(RunnerPlatform(
                    start: Double(start) * segmentWidth,
                    length: Double(index - start) * segmentWidth
                ))
                runStart = nil
            }
        }
        if let start = runStart {
            result.append(RunnerPlatform(
                start: Double(start) * segmentWidth,
                length: Double(pattern.count - start) * segmentWidth
            ))
        }
        return result
    }

    /// スピードアップ床の区画記号（#672）。見た目のとおり「地面が続いている区間」を表す。
    static let boostFloorSymbol: Character = "="

    /// 区画記号をスピードアップ床の並びへ展開する。
    ///
    /// アイテム（点で持つ `RunnerPickup`）と違い、床は**区画まるごと**を占める区間にする。
    /// 「乗っているあいだずっと効く」ものなので、区画の中央に点で置いても踏んだ実感が出ない。
    /// **連続する `=` は 1 つの床にまとめる**——隣り合う区画を別々の床にすると、境目で
    /// 効果が一瞬切れる可能性を残すうえ、描画も継ぎ目が出る。
    static func makeBoostFloors(pattern: String) -> [RunnerBoostFloor] {
        let segmentWidth = Double(RunnerRules.segmentTiles) * RunnerRules.tileWidth
        var result: [RunnerBoostFloor] = []
        for (index, symbol) in pattern.enumerated() where symbol == boostFloorSymbol {
            let start = Double(index) * segmentWidth
            // 直前の床の右端にぴたりと続くなら、新しい床を作らず伸ばす。
            if let last = result.last, last.end == start {
                result[result.count - 1] = RunnerBoostFloor(
                    start: last.start, length: last.length + segmentWidth
                )
            } else {
                result.append(RunnerBoostFloor(start: start, length: segmentWidth))
            }
        }
        return result
    }

    /// 中点から右へずらしながら、障害と重ならず着地に必要な余白もある位置を探す。
    ///
    /// 台座（#674）も同じ扱いで避ける。再開は必ず地面の高さで始まる
    /// （`RunnerField.init(stage:startingAt:passedCheckpoint:)`）ので、台座の範囲に置くと
    /// 走者が台座にめり込んだ状態から走り出すことになる。
    /// 動く障害（#796）は当たり判定の位置ではなく**関わる距離の範囲**（`RunnerHazard.activeRange`）
    /// を避ける——飛び立つ最中の鳥・突進の予告中のイノシシの目の前から走り出させない。
    static func makeCheckpoint(
        length: Double, hazards: [RunnerHazard], platforms: [RunnerPlatform]
    ) -> Double {
        let step = RunnerRules.tileWidth
        // 走者の前後に体 1 つぶんの余白を要求する（縁ぎりぎりから再開させない）。
        let margin = RunnerField.Metrics.playerWidth
        var x = (length / 2 / step).rounded(.down) * step
        let limit = length - step * 4
        while x < limit {
            let onHazard = hazards.contains {
                $0.activeRange.lowerBound - margin < x && x < $0.activeRange.upperBound + margin
            }
            let onPlatform = platforms.contains { $0.start - margin < x && x < $0.end + margin }
            if !onHazard, !onPlatform { return x }
            x += step
        }
        return x
    }
}

public extension RunnerStage {
    /// 全 30 ステージ。Issue #494 の受け入れ条件は「最低15ステージ」で、
    /// 16〜18 は乗れる台座の枠として #674 で足した（既存 15 ステージは無変更）。
    /// 19〜30 は里山・港町の 2 世界として #1009 で足した（1〜18 面は無変更）。
    ///
    /// 難度の付け方:
    /// - 速さは 1 ステージごとに `speedStep` ずつ上がる（1 面 34 → 18 面 47.6 → 30 面 57.2。#968 までは 1.2 刻み）
    /// - 長さも 1 区画ずつ伸びる（1 面 12 区画 → 18 面 29 区画 → 30 面 41 区画。素の `length / speed` で
    ///   おおよそ 23 秒 → 34 秒。実際にはペダルの乗り・スピードアップ床で縮み、自動操縦の
    ///   実測は 16〜25 秒前後になる——`stagesAreShortEnough` が確かめるのはそちらの実測値）
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
    /// およそ半分（#987 で 1/3 から上げた）から 15 面の 8 割弱まで、面番号に対して単調非減少に
    /// 増える（#991。区画数 × 密度を目安に置き直した）。16〜18 面は台座・床が区画を占めるぶん
    /// だけ数が下がるが、台座枠の中では同じく単調非減少。どちらも `RunnerStageTests` が
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
    /// `k`（たこ焼き・#797）は**ステージ 4 以降**の平地区間に 1 個ずつ混ぜてある（Issue の
    /// 「出現は 4 面以降」）。`s` と違って乗りの底上げが無いので先頭寄りに置く理由が無く、
    /// **障害が隣り合う組の直前**に置いて「ここで取れば難所を突っ切れる」という置き方に
    /// してある（#991 で密度を上げてからは、下の「動く障害の直前には置かない」を守れる平地が
    /// 動物の直後しか残らない面が多く、ほとんどの面で犬・イノシシ・鳥の直後に置いてある）。
    /// 台座の前後と床の直後は素の平地でなければ
    /// ならない（下記 (1)(2)）ので、16〜17 面は空いている平地から選んでいる。障害ではないので
    /// 障害の割合・間隔・チェックポイントの位置・速さのどれにも影響しない
    /// （`takoyakiDoesNotAffectClearability`）——1〜15 面のベストタイムの物差しは動かない。
    /// 動物（`d`・`i`）は下の規則どおり既存の `n` を置き換えたもので、`k` が潰した平地とは
    /// 別の区画なので、#797 と #800/#801 の置き換えは互いに独立している。
    ///
    /// **たこ焼きは動く障害（鳥・犬・イノシシ）の直前には置かない**（#900 との統合時の決裁
    /// 2026-09-15）。たこ焼きは跳んでも取れてしまうので、取って 3 秒（`invincibleDuration`）以内に
    /// 動物へ着く並びだと、動物は必ず無敵で素通りになり「跳んで越える」障害として成立しない。
    /// 4〜6・8〜10・12・16・17 面は犬の後ろ（`dk`）、7・11 面はイノシシの後ろ（`ikt`）、
    /// 13〜15 面は最初の鳥の後ろ（`bk`。次の動く障害まで 10 区画以上空く）。18 面は台座・床の
    /// 規則で空く平地が動く障害の直前しか無いので置いていない
    /// （`takoyakiAppearsOnlyFromStageFour` の例外）。
    /// 「取って 3 秒以内に動く障害へ着かない」ことは `movingHazardsHitWhenIgnored` が本来の
    /// パターン（`k` あり）で機械的に確かめる。
    /// `b`（鳥）はステージ 5〜6 と 13〜18 に混ぜてある
    /// （会長QA「鳥とか右から車が来るとか要素はいる」）。#796 で**置物から「飛び立つ鳥」**になり、
    /// 手前 6 タイルで飛び立って低く飛ぶところを跳んで越える（何もしなければ当たる）。
    /// 走者から見た等価な静止区間は区画中央より少し先（`RunnerHazard.encounter`）なので、
    /// 隣の障害との間隔は `RunnerStageTests` がその区間で確かめる。
    /// 5〜6 面の鳥は #626 で足したもの（高い岩を跳んだ直後 `tb`）。
    ///
    /// `d`（犬・#800）と `i`（イノシシ・#801）は v1.1.5 で足した地面を走る動物。**平地は潰さず、
    /// 既存の `n`（低い岩）・`t`（高い岩）を置き換えて**ある——犬は止まれば低い岩そのもの、
    /// イノシシは出会う地点が区画中央で重なりは岩より短いので、成立条件は `n` のまま据え置ける
    /// （高い岩を置き換える向きは帯が下がるだけなので、間隔の余裕はむしろ増える）。
    /// 犬は朝の下町（4〜6 面）と夕方の川沿い、イノシシは夕方の川沿い（7 面〜）から出し、夜は
    /// 鳥と混ぜる（会長決裁 2026-09-14）。`it`（イノシシの次の区画が岩）は「岩で止まる」読みが
    /// できる並び（9・12〜15・17 面）。イノシシが止まる岩は `makeHazards` が障害の並びだけから
    /// 決めるので、あいだに `k` が挟まっても（7 面 `ikt`）止まる／止まらないは変わらない。
    ///
    /// `P`（乗れる台座・#674）と `=`（スピードアップ床・#672）はステージ 16 以降にだけ
    /// 置いてある（19〜30 面は #1009 でわら積み・農道／木箱・ベルトコンベアとして 1 つずつ）。どちらも障害ではないので上の「障害の割合」には数えないが、**台座は前後
    /// 1 区画ずつの素の平地を、床は直後 1 区画の素の平地を必ず連れて行く**（下の `patterns`
    /// 本体のコメントに理由）ので、1 基あたり実質 2〜3 区画を使う。そのぶん 16〜18 の障害の
    /// 数は 15 面より少ない——手応えは障害の密度だけでなく、台座への乗り降りと床を活かす
    /// 走り方でも作る。1〜15 面のパターン文字列は `firstFifteenStagePatternsArePinned` が
    /// リテラルで固定している（1〜3 面は #987、4〜15 面は #991 で組み直した値）。
    ///
    /// **障害を足すときは平地（`-`）を残す余地を必ず見る。**
    /// 平地はタイムに操作を反映させるための余白そのもので、ここが無くなると
    /// 「上手く走ってもタイムが変わらない」状態に戻る（`inefficientPlayCostsMeaningfulTime`
    /// が最終面で 5.3% まで落ちて実際に落ちた）。#991 で密度を上げたあとも、`s`・`k` の区画と
    /// 先頭・末尾の余白が下手な走りに無駄ジャンプの余地を残しており、1・8・18 面の
    /// タイム差は 20.9〜25.8%（しきい値 10%）ある。**ここを削る向きの変更をするときは、
    /// しきい値ではなく配置を直すこと**（#587 の経緯を参照）。
    private static let patterns: [String] = [
        // 1〜6 面は #626（会長決裁 2026-09-14）で障害を 1 面あたり 1 個ずつ足した。
        // 4〜13 面・17〜18 面は #800/#801（同日決裁）で `n` の一部を犬 `d`・イノシシ `i` に置き換えた
        // （障害の数・位置は変えていない）。
        // GA4 で 1 面 → 2 面の到達が 4 割しかないので #626 では 1〜3 面を +1 に留め（`earlyStagesStayGentle`
        // が上限を固定）、4〜6 面は数に加えて**障害が隣り合う区画**で間合いを詰めた。
        // **その後の決裁（会長指示 2026-09-15「1-1 からもうちょっと障害物増やしたいかな」・#987）で
        // 1〜3 面をさらに +2 個ずつ（4・4・5 → 6・6・7）にし、`earlyStagesStayGentle` の上限も上げた。**
        // GA4 の根拠そのものが消えたわけではないので、足すのは**穴（`1`/`2`）と低い岩（`n`）だけ**に
        // 留め、種類の初出の順（高い岩 4 面・鳥 5 面・犬 4 面・イノシシ 7 面）は動かしていない。
        // 区画数は `baseSegments + 面番号 - 1`（`rampsUp`）で固定なので、増やした 2 個ぶんは
        // 平地を潰して入れてある——1〜3 面は先頭・末尾の 2 区画ずつを除くと 8〜10 区画しか無く、
        // 6〜7 個を置くと障害が隣り合う区画が必ず生まれる（速さ 34〜35.6 では間隔 64 に対して
        // 必要な余裕が 36 以下なので成立する——`hazardsAreFarEnoughApart`）。
        // 鳥は 5 面から、高い岩を跳んだ直後（`tb`）に置いて「跳ぶ／くぐる」の判断を出す。
        //
        // **4 面以降は #991（会長指示 2026-09-15「全体的に増やしたい」）で数を組み直した。**
        // #987 が 1〜3 面だけを増やした結果、3 面（7 個）> 4 面（6 個）と逆転し、さらに後半は
        // 15 面 19 個 → 16 面 8 個と落ち込んでいた。目安を「区画数 × 密度」に置き直し、密度は
        // 1 面の 0.5 から 15 面の 0.77 までなだらかに上げてある（1〜3 面は #987 の値のまま）。
        // 同時に**高い岩（`t`）への偏り**（全 183 個中 58 個 = 32%）を崩し、一部を犬・イノシシ・鳥へ
        // 置き換えた（当たり判定の帯は岩と同じなので成立条件は動かない）。結果は全 221 個中
        // 高い岩 53 個（24%）・動く障害 35 個。種類の初出の順（高い岩 4 面・犬 4 面・鳥 5 面・
        // イノシシ 7 面）と、動物の出し分け（犬は朝の下町と夕方の川沿い、イノシシは 7 面から、
        // 鳥は 5〜6 面と夜）は動かしていない。
        "--1-1n-n1n--",              // 1: 12区画・障害6個（穴3+低い岩3。#987 で +2）。1 タイルの穴 2 つで間合いを覚え、3 つ目に低い障害物（#967 で穴から置き換え・初出）。単独→2 連→3 連と密度だけを上げる
        "--1-n1-n-1n--",             // 2: 13区画・障害6個（穴3+低い岩3。#987 で +2）。穴と低い障害物を交互に
        "--1n-2n-n1-2--",            // 3: 14区画・障害7個（穴4+低い岩3。#987 で +2）。2 タイルの穴の初出（#987 で 2 つ目を末尾へ足した）
        "--1n-tn1dk2-t--",           // 4: 15区画・障害8個（穴3+低い岩2+高い岩2+犬1。#991 で +2）。高い障害物と犬の初出。たこ焼きの初出（犬の後ろ）
        "--1sntb-2ndkt1--",          // 5: 16区画・障害9個（穴3+低い岩2+高い岩2+鳥1+犬1。#991 で +2）。スピードアップアイテムと飛び立つ鳥の初出（高い岩の直後 `tb`）
        "--1sn3-tb2ndkt1--",         // 6: 17区画・障害10個（穴4+低い岩2+高い岩2+鳥1+犬1。#991 で +2）。3 タイル（跳べる最大幅）の穴の初出
        "--1sn3-td2nikt2n--",        // 7: 18区画・障害11個（穴4+低い岩3+高い岩2+犬1+イノシシ1。#991 で +3）。イノシシの初出。たこ焼きはイノシシの後ろ（`ikt` は岩の手前だが出現点より先なので止まらない）
        "--2st1dk3tn2t-ni2--",       // 8: 19区画・障害12個（穴5+低い岩2+高い岩3+犬1+イノシシ1。#991 で +3）。たこ焼きは犬の後ろ
        "--2st1-2ndk2nt1it2--",      // 9: 20区画・障害13個（穴6+低い岩2+高い岩3+犬1+イノシシ1。#991 で +3）。岩の手前のイノシシ（`it`＝岩で止まる）の初出。3 タイルの穴はここだけ置かない（速さ 40.4 では決め打ちの走りでもジャスト着地が乗ってしまう——`autoPilotRarelyEarnsJustLanding`）
        "--2st1n3-tdk2n3t1ni--",     // 10: 21区画・障害14個（穴6+低い岩3+高い岩3+犬1+イノシシ1。#991 で +3）
        "--t2sn3tdt-2nikt3n2n--",    // 11: 22区画・障害15個（穴5+低い岩4+高い岩4+犬1+イノシシ1。#991 で +2）。たこ焼きはイノシシの後ろ（止まらない並び）
        "--t2sn3t1n2-ndkt3nit2--",   // 12: 23区画・障害16個（穴6+低い岩4+高い岩4+犬1+イノシシ1。#991 で +2）。末尾の `it` は岩で止まる
        "--t2sbk3t1t2n-t3bn2it1--",  // 13: 24区画・障害17個（穴7+低い岩2+高い岩5+鳥2+イノシシ1。#991 で +1）。夜は鳥とイノシシを混ぜる。たこ焼きは最初の鳥の後ろ
        "--t3sbk2t1t2n3t-nb2it1n--", // 14: 25区画・障害18個（穴7+低い岩3+高い岩5+鳥2+イノシシ1。#991 で +1）
        "--t3sbk2t3t2nt1t3nb2it1n--", // 15: 26区画・障害20個（穴8+低い岩3+高い岩6+鳥2+イノシシ1。#991 で +1）。速さ 45.2（#968 までは 50.8）・約 33 秒
        // ここから #674 の「乗れる台座」枠。置き方の規則が 2 つある。
        //
        // **(1) 台座（`P`）の前後の区画は必ず素の平地（`-`）にする。**
        // 台座の左端は正面から当たればミスなので地面から踏み切る助走が要り、右端から降りると
        // 高さ 8 を落ちるあいだ（約 0.28 秒 ＝ 15 ワールド単位）は空中で踏み切れないため、
        // 隣の区画に障害を置くと踏み切りが間に合わない（`platformsHaveFlatGroundOnBothSides`
        // が機械的に確かめる。`=` も「素の平地」ではないので台座の隣には置かない）。
        // 台座の上には障害・アイテムを置かない（第1弾の決裁どおり）。
        //
        // **(2) スピードアップ床（`=`・#672）の直後には障害を置かず、素の平地を 1 区画挟む。**
        // `RunnerAutoPilot.lead` は基準速（`stage.speed`）で踏み切り位置を決めているのに、
        // 床の上では接地中の速さが `boostFloorMultiplier` 倍まで乗る。床の上で踏み切りの
        // 判断をさせると、1 フレームぶんに進む距離が倍近くなって踏み切りが遅れる
        // （余裕が `tileWidth / 2` あるので詰みはしないが、設計上そこに寄りかからない）。
        // 素の平地を 1 区画挟めば、床の倍率は区間を出た時点で消えるので基準速に戻る。
        // 床は「障害の手前で加速して助走を稼ぐ」のではなく「平地の直線を速く走り抜ける」
        // ご褒美として、各ステージの台座と台座のあいだに置いてある。
        //
        // たこ焼き（`k`・#797）は上の 2 規則を守れる平地にしか置けない——台座の両隣と床の直後は
        // **素の平地**が要るので、16・17 面は犬の直後の区画に置いてある。18 面は規則を守れる
        // 平地が動く障害の直前しか無く、そこには置かない決まり（上の doc）なので置いていない。
        //
        // **#991（会長指示 2026-09-15）で台座・床の並べ方を詰め直した。** 16〜18 面の障害が
        // 8・8・10 個と 15 面（19 個）から大きく落ち込んでいた原因は、台座と床が「連れて行く
        // 素の平地」で区画を使い切っていたこと——16 面の従来の並びでは、障害に使える区画が
        // 23 区画中 9 しか残らなかった。**規則（1)(2) はそのままに、台座を先頭・末尾の余白
        // （先頭 2 区画・末尾 2 区画は元から素の平地）へ寄せて、連れて行く平地を 1 区画ぶん
        // 節約する**。台座の基数（16・18 面は 2 基、17 面は乗り継ぎの 2 基）と床の区画数は
        // 据え置きで、空いた区画へ障害を入れて 12・13・14 個にした
        // （15 面の 20 個より少ないのは台座・床が区画を占めるぶんで、
        // `hazardCountsNeverDecrease` は台座枠の 16〜18 をひとつづきで見る）。
        "--t2nt-PP-=-t3nbdk12t-PPP--",   // 16: 27区画・障害12個（穴4+低い岩2+高い岩4+鳥1+犬1）＋台座2基（2+3区画）＋床1区画。台座に乗る・降りるを覚える。たこ焼きは犬の後ろ
        "--PP-PP-t3ndkt2n==-tb1it2---",  // 17: 28区画・障害13個（穴4+低い岩2+高い岩4+犬1+鳥1+イノシシ1）＋台座2基（2+2区画）＋床2区画（1本）。台座を乗り継ぐ（連続台座）。末尾の `it` は岩で止まる
        "--PP-t3bn2td1n-PPP-==-tb2tb--", // 18: 29区画・障害14個（穴4+低い岩2+高い岩4+鳥3+犬1）＋台座2基（2+3区画）＋床2区画（1本）。台座と鳥・岩・犬の複合（たこ焼きは無し）
        // ここから #1009（会長決裁 2026-09-17〜18）の 4 つ目の世界「里山」（19〜24 面）と
        // 5 つ目の世界「港町」（25〜30 面）。全部手で組んだ（エンドレスの生成器は使っていない）。
        // 置き方の規則は 16〜18 面と同じ（台座の前後・床の直後は素の平地、たこ焼きは動く障害の
        // 5 区画以内の手前に置かない、先頭・末尾の 2 区画は平地）で、面ごとに台座 1〜2 基（1 基 2 区画。
        // 25・26 面だけ 2 基）と床 1 本（2 区画）を置く。
        //
        // **新しい仕組みのうち突き上げ（#1010・`^`）は入った。** 残る 3 つ（#1089 沈む床・
        // #1090 崩れる足場・#1091 高い塀）はまだ `release/v1.1.6` に無いので、予定の区画を今ある障害で
        // 仮に埋めてある（#1009 本文 D）。仮置きは 高い塀 → 高い岩 `t`、沈む床 → 2 タイルの穴 `2`、
        // 崩れる足場 → 3 タイルの穴 `3`。
        // 各行の「予定」に区画番号（0 始まり）を残してあるので、仕組み側の Issue はそこを自分の記号へ
        // 置き換える。予定の区画は #1009 の「入れない組み合わせ」を守る位置に選んである:
        // 鳥の隣に突き上げを置かない・崩れる足場と沈む床の直後に鳥を置かない・高い塀の直後
        // （着地点）は平地か低い岩・高い塀と突き上げの手前にイノシシを置かない。
        // 各世界で仕組みを初めて出す区画（19 面の竹の子・21 面の田んぼ・24 面の吊り橋と石垣・
        // 25 面の桟橋・26 面の波しぶき・27 面のコンテナ・29 面の干潟）は前後を素の平地にして単独で見せる。
        // 障害の数（仮置きを含む）は世界の中で面番号に対して減らない（`newWorldHazardCountsNeverDecrease`）。
        "--PP-1n-^-2ikt1n==-^2b-ti1^---",           // 19: 30区画・障害15個（穴5+低い岩2+高い岩2+鳥1+イノシシ2+竹の子3）。里山に入った。竹の子を覚える（初出の区画 8 は前後を素の平地にして単独で見せる）
        "--1n^-2dkt1-PP-n^2itn==-^1b-^--",          // 20: 31区画・障害17個（穴5+低い岩3+高い岩2+鳥1+犬1+イノシシ1+竹の子4）。切り株（`n`）のすぐ隣に竹の子（区画 3〜4・15〜16）。低く跳ぶか高く跳ぶかの見極め
        "--1tn-2-2ikn^1==-t1d2-b2t-PP-^--",         // 21: 32区画・障害17個（穴7+低い岩2+高い岩3+鳥1+犬1+イノシシ1+竹の子2）。予定: 田んぼ（#1089）= 区画 6・20。田んぼを覚える
        "--PP-1n2ikt2^-n1d-==-t2i1^2b-t1--",        // 22: 33区画・障害19個（穴8+低い岩2+高い岩3+鳥1+犬1+イノシシ2+竹の子2）。予定: 田んぼ = 区画 7・22。田んぼの直後にイノシシ
        "--1^n21ikt2^n22d-==-t^1bn2-^-PP---",       // 23: 34区画・障害20個（穴8+低い岩3+高い岩2+鳥1+犬1+イノシシ1+竹の子4）。予定: 田んぼ = 区画 5・13・25。田んぼを抜けた直後に用水路
        "--PP-1^n2ikt^221dn==-^-3-^t1b2-t---",      // 24: 35区画・障害20個（穴8+低い岩2+高い岩3+鳥1+犬1+イノシシ1+竹の子4）。予定: 田んぼ = 区画 8・14・29 / 吊り橋（#1090）= 区画 23 / 石垣（#1091）= 区画 31。里山の締め。全部入り
        "--PP-1n-3-tik2t1==-t2-31ti-PP-d2-b--",     // 25: 36区画・障害17個（穴8+低い岩1+高い岩4+鳥1+犬1+イノシシ2）。予定: 古い桟橋（#1090）= 区画 8・22。港町に入った。桟橋の先が切れ目
        "--132dk-^-n-PP-t31i-==-^n2b-32ti-PP--",    // 26: 37区画・障害18個（穴8+低い岩2+高い岩2+鳥1+犬1+イノシシ2+波しぶき2）。予定: 古い桟橋 = 区画 3・16・28。波しぶきの初出（区画 8 は前後を素の平地）
        "--PP-1n-t-2ikt31-t-==-2dn32tb-t-1it---",   // 27: 38区画・障害20個（穴8+低い岩2+高い岩6+鳥1+犬1+イノシシ2）。予定: 古い桟橋 = 区画 14・25 / コンテナ（#1091）= 区画 8・30。二段ジャンプを覚える
        "--1t-32ikt^1-t-d31t-==-^n2b-t-32ti-PP--",  // 28: 39区画・障害22個（穴9+低い岩1+高い岩6+鳥1+犬1+イノシシ2+波しぶき2）。予定: 古い桟橋 = 区画 5・16・30 / コンテナ = 区画 3・13・28
        "--PP--2-^2iktt-1n2it-==-^2b-t-21t^nd2---", // 29: 40区画・障害22個（穴8+低い岩2+高い岩5+鳥1+犬1+イノシシ2+波しぶき3）。予定: 干潟（#1089）= 区画 6・17・30 / コンテナ = 区画 13・28。里山で覚えた仕組みの港版
        "--PP-1^n2ikt32t-d^1-==-t2itt-32b-^n21t---", // 30: 41区画・障害25個（穴10+低い岩2+高い岩6+鳥1+犬1+イノシシ2+波しぶき3）。予定: 干潟 = 区画 8・24・35 / 古い桟橋 = 区画 12・29 / コンテナ = 区画 14・27・37。港町の締め。全部入り
    ]
}

#if DEBUG
public extension RunnerStage {
    /// QA用: 低い障害物・高い障害物・鳥・犬・イノシシ・穴3サイズ・スピードアップ床・台座を1本で見比べられるステージ
    /// （起動引数 `-simulateRunner showcase`）。`.all`（本番のステージ）には含めない
    /// ——`number` を 0 にして「実ステージではない」ことを型で示す。
    ///
    /// 鳥（`b`）・犬（`d`）・イノシシ（`i`）を入れてあるのは、飛び立つ・前から歩いて来る・
    /// 突進してくる（#796/#955/#801）を本番の面まで遊ばずに確かめるため。狙った瞬間は
    /// `-simulateRunner bird` / `bird-low` / `bird-up` / `dog` / `boar` が 1 枚ずつ撮れる。
    ///
    /// 間隔は他ステージよりゆったり取ってある（QA中に慌てて次の障害へ突っ込まないため）。
    /// 速さは1面と同じ `RunnerRules.baseSpeed` で固定。
    ///
    /// スピードアップ床（`=`・#672）は**走り出しの直後に2区画続けて**置いてある。
    /// 既存15ステージには置かない（本番への投入は新ステージ 16〜18・#674）ので、
    /// 実機スクリーンショットを撮れる場所はここだけ——最初の障害より手前に置くことで、
    /// 走り出してすぐ床の上の状態を撮れる。障害としては平地なので、障害の間隔・
    /// 跳び越しの条件は従来どおり（`makeBoostFloors` を参照）。
    ///
    /// たこ焼き（`k`・#797）は床の直後の素の平地を 1 区画挟んだ次、最初の岩の直前に置いてある。
    /// 取った直後に岩・高い岩を無敵で突っ切る画が `-simulateRunner invincible` で撮れる。
    /// 突き上げ（`^`・#1010）はイノシシの次に置いてある。`-simulateRunner shoot` / `shoot-up` で
    /// 「伸びかけ」と「伸び切り」が 1 枚ずつ撮れる（絵は世界の着せ替え——ショーケースは夜の
    /// 世界で走るので、`RunnerWorld.originalDressing` の竹の子が出る）。
    static let debugShowcase = RunnerStage(
        number: 0,
        pattern: "--==-kn--t--b--d--i--^--PP--1--2--3--",
        speed: RunnerRules.baseSpeed
    )
}
#endif
